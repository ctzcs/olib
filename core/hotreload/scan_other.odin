#+build !windows
#+build !js
package hotreload

import "base:runtime"
import "core:os"
import "core:time"

// Linux/macOS 等的扫描平台层：core:os 列目录时用 fstatat 一类调用取元数据，不读取文件内容；
// POSIX 打开文件不会阻止其他进程写入、删除或改名。

// 列出目录项，名字分配在 allocator 上；目录不存在或无法读取时返回 false。
@(private)
scan_list :: proc(dir: string, entries: ^[dynamic]Scan_Entry, allocator: runtime.Allocator) -> bool {
	infos, err := os.read_all_directory_by_path(dir, allocator)
	if err != nil do return false
	for info in infos do append(entries, scan_entry(info))
	return true
}

// 查询单个路径的元数据，不跟随符号链接；返回的 name 为空。
@(private)
scan_stat :: proc(path: string) -> (entry: Scan_Entry, ok: bool) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	info, err := os.stat_do_not_follow_links(path, context.temp_allocator)
	if err != nil do return {}, false
	entry = scan_entry(info)
	entry.name = ""
	return entry, true
}

// 读取整个文件计算内容哈希（长度参与）。
@(private)
scan_hash_file :: proc(path: string) -> (hash: u64, ok: bool) {
	data, err := os.read_entire_file(path, runtime.heap_allocator())
	if err != nil do return 0, false
	defer delete(data, runtime.heap_allocator())
	return (fnv_bytes(FNV_OFFSET, data) ~ u64(len(data))) * FNV_PRIME, true
}

@(private = "file")
scan_entry :: proc(info: os.File_Info) -> Scan_Entry {
	kind := Scan_Kind.Other
	#partial switch info.type {
	case .Regular:
		kind = .File
	case .Directory:
		kind = .Directory
	}
	return {
		name = info.name,
		kind = kind,
		size = info.size,
		modified = time.time_to_unix_nano(info.modification_time),
	}
}
