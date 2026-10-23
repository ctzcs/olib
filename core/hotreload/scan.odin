#+build !js
package hotreload

import "base:intrinsics"
import "base:runtime"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// 分区：
//   扫描表 —— 每个被监听文件一行：元数据、内容哈希、最近变化
//   扫描线程 —— 启停、唤醒、完整扫描请求与结果发布
//   完整扫描 —— 列目录比较元数据，只读取新增、变化或时间戳过近的文件
//   热文件 —— 完整扫描间隔被拉长时，单独检查最近变化的文件
// 平台层（scan_windows.odin / scan_other.odin）提供 scan_list、scan_stat、scan_hash_file。

// ------------------------------------------------------------------------------
// 扫描表
// ------------------------------------------------------------------------------

@(private)
FNV_OFFSET :: u64(1469598103934665603)
@(private)
FNV_PRIME :: u64(1099511628211)

// 读取内容时，修改时间离读取时刻不足此余量的文件可能在同一时间戳内再次改写，下次扫描仍按内容复核。
// 覆盖 FAT 的 2 秒、HFS+ 的 1 秒精度和网络盘的元数据缓存；NTFS/ext4/APFS 只是多读几次刚改过的文件。
@(private)
SCAN_RACY_NS :: i64(3 * time.Second)

// 内容变化后这段时间内算热文件：完整扫描间隔被拉长时，每次唤醒仍单独检查，最多 SCAN_HOT_LIMIT 个。
@(private)
SCAN_HOT_NS :: i64(30 * time.Second)
@(private)
SCAN_HOT_LIMIT :: 64

// 完整扫描的间隔至少是其耗时的这个倍数：文件很多时后台最多占约十分之一个核心，检测延迟随之变长。
@(private)
SCAN_COST_FACTOR :: 10

@(private)
Scan_Kind :: enum u8 {
	Other, // 符号链接、挂载点等，不跟随
	File,
	Directory,
}

// 平台层返回的一项元数据；name 只在调用方给的分配器上有效。
@(private)
Scan_Entry :: struct {
	name: string,
	kind: Scan_Kind,
	size, modified: i64, // 字节数；修改时间，Unix 纳秒
}

// 扫描表的一行，紧凑布局：0..<len 是最近一次完整扫描见到的文件。path 由扫描器持有并作为 index 的键；
// 交换删除会改变行号，行号只在当前扫描内使用。
@(private)
Scan_File :: struct {
	path: string,
	path_hash, content: u64,
	size, modified: i64,
	checked: i64, // 最近一次读取内容的扫描开始时刻（Unix 纳秒），判断时间戳是否过近
	hot_until: i64, // 内容最近变化：此前每次唤醒都单独检查
	sweep: u32, // 最近一次见到它的完整扫描编号
}

// ------------------------------------------------------------------------------
// 扫描线程
// ------------------------------------------------------------------------------

// 主线程读取的结果，由 Scanner.lock 保护。
@(private)
Scan_Result :: struct {
	fingerprint: u64,
	readable: bool,
	sweeps: u64, // 已完成的完整扫描次数；0 表示还没有结果
	served: u64, // 已满足的完整扫描请求号
}

// 内嵌在 Watch 中，地址稳定。主线程只调用 scan_result / scan_request；其余字段只由扫描线程读写
// （Manual 模式没有线程，由调用线程同步扫描），线程停止后由 scan_destroy 释放。roots / extensions 借用 Watch。
@(private)
Scanner :: struct {
	lock: sync.Mutex,
	result: Scan_Result,
	wake: sync.Sema,
	requested: u64, // 原子：完整扫描请求号
	stop: bool, // 原子
	thread: ^thread.Thread,
	roots, extensions: []string,
	interval: time.Duration,
	files: #soa[dynamic]Scan_File,
	index: map[string]int,
	sweep: u32,
	served: u64,
	readable: bool,
}

@(private)
scan_init :: proc(sc: ^Scanner, roots, extensions: []string, interval: time.Duration) {
	sc.roots = roots
	sc.extensions = extensions
	sc.interval = interval
}

// 启动后台扫描线程，低优先级，不与游戏主线程争抢。
@(private)
scan_start :: proc(sc: ^Scanner) -> bool {
	sc.thread = thread.create(scan_worker, .Low)
	if sc.thread == nil do return false
	sc.thread.data = sc
	thread.start(sc.thread)
	return true
}

// 停止并等待扫描线程，再释放扫描表。
@(private)
scan_destroy :: proc(sc: ^Scanner) {
	context.allocator = runtime.heap_allocator()
	if sc.thread != nil {
		intrinsics.atomic_store(&sc.stop, true)
		sync.sema_post(&sc.wake)
		thread.join(sc.thread)
		thread.destroy(sc.thread)
	}
	for path in sc.files.path[:len(sc.files)] do delete(path)
	delete_soa(sc.files)
	delete(sc.index)
	sc^ = {}
}

// 主线程读取最近一次发布的结果。
@(private)
scan_result :: proc(sc: ^Scanner) -> Scan_Result {
	sync.mutex_lock(&sc.lock)
	defer sync.mutex_unlock(&sc.lock)
	return sc.result
}

// 请求一次在此之后开始的完整扫描并唤醒线程；结果的 served 达到返回值即已完成。
@(private)
scan_request :: proc(sc: ^Scanner) -> u64 {
	ticket := intrinsics.atomic_add(&sc.requested, 1) + 1
	sync.sema_post(&sc.wake)
	return ticket
}

@(private)
scan_worker :: proc(t: ^thread.Thread) {
	context.allocator = runtime.heap_allocator()
	sc := cast(^Scanner)t.data
	next := time.tick_now()
	for !intrinsics.atomic_load(&sc.stop) {
		ticket := intrinsics.atomic_load(&sc.requested)
		start := time.tick_now()
		if ticket > sc.served || time.tick_diff(next, start) >= 0 {
			scan_sweep(sc)
			sc.served = ticket
			scan_publish(sc, true)
			next = time.tick_add(start, max(sc.interval, time.tick_since(start) * SCAN_COST_FACTOR))
		} else if scan_hot(sc) {
			scan_publish(sc, false)
		}
		free_all(context.temp_allocator)
		_ = sync.sema_wait_with_timeout(&sc.wake, sc.interval)
	}
}

@(private)
scan_publish :: proc(sc: ^Scanner, complete: bool) {
	fingerprint := scan_fingerprint(sc)
	sync.mutex_lock(&sc.lock)
	defer sync.mutex_unlock(&sc.lock)
	sc.result.fingerprint = fingerprint
	sc.result.readable = sc.readable
	if complete {
		sc.result.sweeps += 1
		sc.result.served = sc.served
	}
}

// ------------------------------------------------------------------------------
// 完整扫描
// ------------------------------------------------------------------------------

// 列出全部 roots 并比较元数据，只读取新增、元数据变化或时间戳过近的文件；扫描完整时删除未见到的行。
// 显式 root 或任一目录无法读取时 readable = false，本次不删除行。
@(private)
scan_sweep :: proc(sc: ^Scanner) {
	sc.sweep += 1
	now := time.time_to_unix_nano(time.now())
	sc.readable = true
	for root in sc.roots {
		entry, ok := scan_stat(root)
		switch {
		case !ok:
			sc.readable = false
		case entry.kind == .File:
			sc.readable = scan_visit(sc, root, entry, now) // 显式文件不受扩展名过滤
		case entry.kind == .Directory:
			sc.readable = scan_directory(sc, root, now)
		case:
			sc.readable = false // 显式 root 也不跟随符号链接
		}
		if !sc.readable do return
	}
	// 倒序交换删除：搬来的行已经检查过。
	for i := len(sc.files) - 1; i >= 0; i -= 1 {
		if sc.files[i].sweep != sc.sweep do scan_remove(sc, i)
	}
}

// 递归列目录，忽略隐藏目录、build、Library 和符号链接；本层的临时名字在返回前释放。
@(private)
scan_directory :: proc(sc: ^Scanner, dir: string, now: i64) -> bool {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	entries := make([dynamic]Scan_Entry, context.temp_allocator)
	if !scan_list(dir, &entries, context.temp_allocator) do return false
	for entry in entries {
		path := strings.concatenate({dir, filepath.SEPARATOR_STRING, entry.name},
			context.temp_allocator)
		switch entry.kind {
		case .Directory:
			if strings.has_prefix(entry.name, ".") || entry.name == "build" ||
				entry.name == "Library" {
				continue
			}
			if !scan_directory(sc, path, now) do return false
		case .File:
			if !scan_matches(sc.extensions, entry.name) do continue
			if !scan_visit(sc, path, entry, now) do return false
		case .Other:
		}
	}
	return true
}

@(private)
scan_matches :: proc(extensions: []string, name: string) -> bool {
	for extension in extensions {
		if strings.has_suffix(name, extension) do return true
	}
	return false
}

// 查找或新增一行并记为本次已见；新文件、元数据变化或时间戳过近才读取内容。
// 首次扫描的文件不算热文件，之后新出现的才算。
@(private)
scan_visit :: proc(sc: ^Scanner, path: string, entry: Scan_Entry, now: i64) -> bool {
	row, found := sc.index[path]
	if found {
		sc.files[row].sweep = sc.sweep
		return !scan_stale(sc, row, entry) || scan_refresh(sc, row, entry, now)
	}
	content := scan_hash_file(path) or_return
	owned := strings.clone(path)
	sc.index[owned] = len(sc.files)
	append_soa(&sc.files, Scan_File{
		path = owned,
		path_hash = fnv_bytes(FNV_OFFSET, transmute([]u8)owned),
		content = content,
		size = entry.size,
		modified = entry.modified,
		checked = now,
		hot_until = sc.sweep > 1 ? now + SCAN_HOT_NS : 0,
		sweep = sc.sweep,
	})
	return true
}

// 大小和修改时间都没变，且上次读取时修改时间已早于余量，才沿用上次的内容哈希。
@(private)
scan_stale :: proc(sc: ^Scanner, row: int, entry: Scan_Entry) -> bool {
	return entry.size != sc.files[row].size || entry.modified != sc.files[row].modified ||
		entry.modified + SCAN_RACY_NS >= sc.files[row].checked
}

// 重新读取一行的内容并记录元数据；内容变化时设为热文件。
@(private)
scan_refresh :: proc(sc: ^Scanner, row: int, entry: Scan_Entry, now: i64) -> bool {
	content := scan_hash_file(sc.files[row].path) or_return
	if content != sc.files[row].content do sc.files[row].hot_until = now + SCAN_HOT_NS
	sc.files[row].content = content
	sc.files[row].size = entry.size
	sc.files[row].modified = entry.modified
	sc.files[row].checked = now
	return true
}

@(private)
scan_remove :: proc(sc: ^Scanner, row: int) {
	path := sc.files[row].path
	delete_key(&sc.index, path)
	delete(path)
	last := len(sc.files) - 1
	if row != last do sc.index[sc.files[last].path] = row
	unordered_remove_soa(&sc.files, row)
}

// 与顺序无关地合成全部行的路径与内容：增删改任一文件都会改变结果。
@(private)
scan_fingerprint :: proc(sc: ^Scanner) -> u64 {
	n := len(sc.files)
	paths := sc.files.path_hash[:n]
	contents := sc.files.content[:n]
	sum := u64(n) * FNV_PRIME
	for i in 0 ..< n do sum += scan_mix(paths[i] ~ (contents[i] * 0x9e3779b97f4a7c15))
	return sum
}

// splitmix64 的末段混合，把相近的输入打散。
@(private)
scan_mix :: proc(x: u64) -> u64 {
	z := (x ~ (x >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	return z ~ (z >> 31)
}

@(private)
fnv_bytes :: proc(hash: u64, data: []u8) -> u64 {
	h := hash
	for b in data do h = (h ~ u64(b)) * FNV_PRIME
	return h
}

// ------------------------------------------------------------------------------
// 热文件
// ------------------------------------------------------------------------------

// 两次完整扫描之间单独查询最近变化的文件；返回是否重读过内容。消失或读不到的文件留给下次完整扫描。
@(private)
scan_hot :: proc(sc: ^Scanner) -> (refreshed: bool) {
	now := time.time_to_unix_nano(time.now())
	hot := sc.files.hot_until[:len(sc.files)]
	checked := 0
	for until, i in hot {
		if until <= now do continue
		if checked == SCAN_HOT_LIMIT do break
		checked += 1
		entry, ok := scan_stat(sc.files[i].path)
		if !ok || entry.kind != .File || !scan_stale(sc, i, entry) do continue
		refreshed = scan_refresh(sc, i, entry, now) || refreshed
	}
	return
}
