#+build !js
package hotreload

import "base:intrinsics"
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:thread"

import "olib:core/devbuild"

// 分区：监听配置与状态 / 生命周期 / 内容检测与后台编译 / 主线程提交。

Build_Status :: enum {
	Waiting,
	Compiling,
	Ready,
	Live,
	Error,
}

Watch_Config :: struct {
	// 参数数组，不经过 shell；至少一个参数含 {output}，如 -out:{output}。
	command: []string,
	working_directory: string,
	// 显式列出游戏代码/共享定义/#load 资产所在目录或文件；不自动解析 import。
	roots: []string,
	extensions: []string, // 空时只监听 .odin；显式文件不受扩展名过滤。
	cache_parent: string, // 空时使用系统临时目录；目录内依赖须由宿主/系统解决。
	poll_seconds: f64, // <=0 使用 0.25 秒。
	debounce_seconds: f64, // <=0 使用 0.25 秒。
}

// 必须在常驻宿主中创建，地址稳定。只允许一个线程调用公开接口。
// 后台仅编译，不调用模块/UI/GPU。持久内存固定使用宿主 heap_allocator。
Watch :: struct {
	status: Build_Status,
	diagnostic: string,
	initialized: bool,
	command, roots, extensions: []string,
	working_directory, cache: string,
	poll_seconds, debounce_seconds: f64,
	poll, stable: f64,
	observed, attempted: u64,
	has_observed, has_attempted: bool,
	build_invalidated: bool,
	generation: u64,
	worker: ^thread.Thread,
	job: Build_Job,
}

@(private)
Build_Job :: struct {
	command: []string,
	working_directory, output: string,
	fingerprint: u64,
	diagnostic: string,
	succeeded, done: bool,
}

watch_init :: proc(w: ^Watch, config: Watch_Config) -> bool {
	if w.initialized do return false
	context.allocator = runtime.heap_allocator()
	w^ = {}
	if len(config.command) == 0 || len(config.roots) == 0 do return false
	has_output := false
	for arg in config.command do has_output = has_output || strings.contains(arg, "{output}")
	if !has_output do return false
	w.initialized = true
	success := false
	defer if !success do watch_dispose(w)
	w.command = clone_strings(config.command)
	w.extensions = clone_strings(len(config.extensions) == 0 ? []string{".odin"} : config.extensions)
	work := config.working_directory == "" ? "." : config.working_directory
	wd, wd_err := filepath.abs(work)
	if wd_err != nil do return false
	w.working_directory = wd
	w.roots = make([]string, len(config.roots))
	for root, i in config.roots {
		path := root
		if !filepath.is_abs(path) do path = fmt.tprintf("%s/%s", wd, path)
		absolute, err := filepath.abs(path)
		if err != nil do return false
		w.roots[i] = absolute
	}
	cache, cache_err := os.make_directory_temp(config.cache_parent, "olib_hotreload_", context.allocator)
	if cache_err != nil do return false
	w.cache = cache
	w.poll_seconds = config.poll_seconds > 0 ? config.poll_seconds : 0.25
	w.debounce_seconds = config.debounce_seconds > 0 ? config.debounce_seconds : 0.25
	success = true
	return true
}

// 退出时等待正在运行的编译器完成；先 dispose Session，再 dispose Watch。
watch_dispose :: proc(w: ^Watch) {
	if !w.initialized do return
	context.allocator = runtime.heap_allocator()
	if w.worker != nil {
		thread.join(w.worker)
		thread.destroy(w.worker)
	}
	job_dispose(&w.job)
	delete_strings(w.command)
	delete_strings(w.roots)
	delete_strings(w.extensions)
	delete(w.working_directory)
	delete(w.diagnostic)
	if w.cache != "" {
		// 只删除本会话创建的独占目录内的文件；不跟随链接或递归删除外部路径。
		entries, err := os.read_all_directory_by_path(w.cache, context.allocator)
		if err == nil {
			for e in entries {
				if e.type != .Directory do _ = os.remove(e.fullpath)
			}
			os.file_info_slice_delete(entries, context.allocator)
		}
		_ = os.remove(w.cache)
		delete(w.cache)
	}
	w^ = {}
}

watch_retry :: proc(w: ^Watch) {
	w.has_attempted = false
}

// 内容哈希捕获新增/删除/同大小同时间戳修改；每次调用释放扫描用的临时内存。
// 默认忽略隐藏目录、build、Library，不扫描生成产物；roots 应尽量小。
watch_fingerprint :: proc(w: ^Watch) -> (hash: u64, ok: bool) {
	context.allocator = runtime.heap_allocator()
	paths := make([dynamic]string)
	defer {
		for path in paths do delete(path)
		delete(paths)
	}
	for root in w.roots {
		if !collect_sources(root, w.extensions, &paths, explicit = true) do return 0, false
	}
	slice.sort(paths[:])
	hash = 1469598103934665603
	for path in paths {
		data, err := os.read_entire_file(path, context.allocator)
		if err != nil do return 0, false
		for b in transmute([]u8)path do hash = (hash ~ u64(b)) * 1099511628211
		for b in data do hash = (hash ~ u64(b)) * 1099511628211
		hash = (hash ~ u64(len(data))) * 1099511628211
		delete(data)
	}
	return hash, true
}

// 每帧调用；编译期间游戏继续运行。失败版本只尝试一次，修改源码或 retry 后重试。
watch_update :: proc(w: ^Watch, dt: f64) {
	if !w.initialized do return
	context.allocator = runtime.heap_allocator()
	w.poll += max(dt, 0)
	w.stable += max(dt, 0)
	if w.poll < w.poll_seconds do return
	w.poll = 0
	hash, readable := watch_fingerprint(w)
	if readable && (!w.has_observed || hash != w.observed) {
		w.observed = hash
		w.has_observed = true
		w.stable = 0
		if w.worker == nil {
			w.status = .Waiting
			w.has_attempted = false
		}
	}
	if w.worker != nil {
		if !readable || hash != w.job.fingerprint do w.build_invalidated = true
		if !intrinsics.atomic_load(&w.job.done) do return
		thread.join(w.worker)
		thread.destroy(w.worker)
		w.worker = nil
		if readable && w.job.fingerprint == hash && !w.build_invalidated {
			watch_diagnostic(w, w.job.diagnostic)
			w.status = w.job.succeeded ? .Ready : .Error
		} else {
			w.status = .Waiting
			w.has_attempted = false
		}
	}
	if !readable {
		w.has_observed = false
		w.has_attempted = false
		w.status = .Error
		watch_diagnostic(w, "Cannot read watched sources; live module retained")
		return
	}
	if w.stable < w.debounce_seconds || (w.has_attempted && w.attempted == hash) do return
	job_dispose(&w.job)
	w.generation += 1
	output := fmt.aprintf("%s/game_%d.%s", w.cache, w.generation, dynlib.LIBRARY_FILE_EXTENSION)
	w.job = {working_directory = w.working_directory, output = output, fingerprint = hash}
	w.build_invalidated = false
	w.job.command = make([]string, len(w.command))
	for arg, i in w.command {
		expanded, allocated := strings.replace_all(arg, "{output}", output, context.allocator)
		w.job.command[i] = allocated ? expanded : strings.clone(expanded)
	}
	w.attempted = hash
	w.has_attempted = true
	w.worker = thread.create(build_worker)
	if w.worker == nil {
		w.status = .Error
		watch_diagnostic(w, "Cannot create compiler worker")
		return
	}
	w.worker.data = &w.job
	w.status = .Compiling
	watch_diagnostic(w, "")
	thread.start(w.worker)
}

// 与 reload 相同的帧边界要求；再次检查源码，拒绝编译期间或 Ready 之后过期的结果。
watch_apply :: proc(w: ^Watch, s: ^Session, policy: State_Policy = .Compatible) -> Result {
	if w.status != .Ready do return .Not_Initialized
	hash, ok := watch_fingerprint(w)
	if !ok || hash != w.job.fingerprint {
		w.status = .Waiting
		w.has_attempted = false
		return .Busy
	}
	result := reload(s, w.job.output, policy)
	if result == .Busy do return result
	w.status = result == .Success ? .Live : .Error
	watch_diagnostic(w, s.diagnostic)
	return result
}

@(private)
build_worker :: proc(t: ^thread.Thread) {
	context.allocator = runtime.heap_allocator()
	j := cast(^Build_Job)t.data
	state, stdout, stderr, err := devbuild.exec(
		{command = j.command, working_dir = j.working_directory}, context.allocator)
	defer delete(stdout)
	defer delete(stderr)
	j.succeeded = err == nil && state.exited && state.exit_code == 0 && os.is_file(j.output)
	if !j.succeeded {
		j.diagnostic = fmt.aprintf("Game build failed (%v, exit %d)\n%s%s",
			err, state.exit_code, string(stdout), string(stderr))
	}
	intrinsics.atomic_store(&j.done, true)
}

@(private)
collect_sources :: proc(path: string, extensions: []string, paths: ^[dynamic]string,
	explicit: bool = false) -> bool {
	info, err := os.stat_do_not_follow_links(path, context.allocator)
	if err != nil do return false
	defer os.file_info_delete(info, context.allocator)
	if info.type == .Regular {
		matches := explicit
		for ext in extensions do matches = matches || strings.has_suffix(path, ext)
		if matches do append(paths, strings.clone(path))
		return true
	}
	if info.type != .Directory do return !explicit
	if !explicit && (strings.has_prefix(info.name, ".") || info.name == "build" || info.name == "Library") {
		return true
	}
	entries, entries_err := os.read_all_directory_by_path(path, context.allocator)
	if entries_err != nil do return false
	defer os.file_info_slice_delete(entries, context.allocator)
	for e in entries {
		if !collect_sources(e.fullpath, extensions, paths) do return false
	}
	return true
}

@(private)
clone_strings :: proc(values: []string) -> []string {
	result := make([]string, len(values))
	for value, i in values do result[i] = strings.clone(value)
	return result
}

@(private)
delete_strings :: proc(values: []string) {
	for value in values do delete(value)
	delete(values)
}

@(private)
job_dispose :: proc(j: ^Build_Job) {
	if j.output != "" {
		_ = os.remove(j.output)
		for extension in ([]string{".pdb", ".lib", ".exp"}) {
			sidecar := fmt.tprintf("%s/%s%s", filepath.dir(j.output), filepath.stem(j.output), extension)
			_ = os.remove(sidecar)
		}
	}
	delete(j.output)
	delete(j.diagnostic)
	delete_strings(j.command)
	j^ = {}
}

@(private)
watch_diagnostic :: proc(w: ^Watch, value: string) {
	delete(w.diagnostic, runtime.heap_allocator())
	w.diagnostic = strings.clone(value, runtime.heap_allocator())
}
