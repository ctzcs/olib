package main

// Compiled/sources.json：生成产物时记下每个源码文件的指纹，-check 据此判断产物是否过期（不需要 shadercross）。
// 源码是目录下（含子目录，跳过 Compiled 和隐藏目录）的 .oshader / .hlsl / .hlsli；
// 有 .oshader 时再加上编译时复制进去的 olib 标准 include。
// 指纹去掉 \r 再算，Windows 上 git 的换行转换不会造成误报。
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import lang "../../kit/rendering/shader/lang"

SOURCES_RECORD :: "sources.json"
SOURCES_RECORD_VERSION :: 1

Source_Entry :: struct {
	path: string, // 相对 shader 目录，/ 分隔；olib 标准 include 记为 olib/<文件名>
	hash: string, // 去掉 \r 后内容的 FNV-1a 64 位，16 位十六进制
}

Sources_Record :: struct {
	version: int,
	files: []Source_Entry,
}

// 当前源码的记录，按路径排序；读文件失败或用了保留目录名时返回原因。分配在 temp_allocator。
sources_collect :: proc(dir: string) -> (record: Sources_Record, reason: string) {
	entries := make([dynamic]Source_Entry, context.temp_allocator)
	if reason = sources_walk(dir, "", &entries); reason != "" do return
	oshader := false
	for entry in entries {
		if strings.has_suffix(entry.path, ".oshader") do oshader = true
	}
	if oshader {
		include := path_join(lang.INCLUDE_DIRECTORY, "olib")
		list, err := os.read_all_directory_by_path(include, context.temp_allocator)
		if err != nil do return {}, fmt.tprintf("无法读取 %s: %v", include, err)
		for item in list {
			if item.type != .Regular || !strings.has_suffix(item.name, ".hlsli") do continue
			data, read_err := os.read_entire_file(item.fullpath, context.temp_allocator)
			if read_err != nil do return {}, fmt.tprintf("无法读取 %s: %v", item.fullpath, read_err)
			append(&entries, Source_Entry{fmt.tprintf("olib/%s", item.name), source_hash(data)})
		}
	}
	slice.sort_by(entries[:], proc(a, b: Source_Entry) -> bool { return a.path < b.path })
	return {SOURCES_RECORD_VERSION, entries[:]}, ""
}

@(private = "file")
sources_walk :: proc(root, rel: string, entries: ^[dynamic]Source_Entry) -> string {
	dir := rel == "" ? root : path_join(root, rel)
	list, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return fmt.tprintf("无法读取 %s: %v", dir, err)
	for item in list {
		path := rel == "" ? item.name : fmt.tprintf("%s/%s", rel, item.name)
		if item.type == .Directory {
			if item.name == "Compiled" || strings.has_prefix(item.name, ".") do continue
			if rel == "" && item.name == "olib" {
				return "olib/ 是保留的 include 目录名（编译时放 olib 标准 include），shader 目录里不能有 olib/ 子目录"
			}
			if reason := sources_walk(root, path, entries); reason != "" do return reason
		} else if item.type == .Regular && (strings.has_suffix(item.name, ".oshader") ||
			strings.has_suffix(item.name, ".hlsl") || strings.has_suffix(item.name, ".hlsli")) {
			data, read_err := os.read_entire_file(item.fullpath, context.temp_allocator)
			if read_err != nil do return fmt.tprintf("无法读取 %s: %v", item.fullpath, read_err)
			append(entries, Source_Entry{path, source_hash(data)})
		}
	}
	return ""
}

// 去掉 \r 后的 FNV-1a 64 位。
source_hash :: proc(data: []u8) -> string {
	h: u64 = 0xcbf29ce484222325
	for b in data {
		if b == '\r' do continue
		h ~= u64(b)
		h *= 0x100000001b3
	}
	return fmt.tprintf("%016x", h)
}

// 记录的 JSON 文本（带结尾换行），分配在 allocator：编译循环会清空 temp_allocator，记录要活到编译结束。
sources_encode :: proc(record: Sources_Record, allocator := context.allocator) -> (text: []u8, ok: bool) {
	data, err := json.marshal(record, {pretty = true, use_spaces = true, spaces = 2}, context.temp_allocator)
	if err != nil {
		fmt.eprintln(err)
		return nil, false
	}
	text = make([]u8, len(data) + 1, allocator)
	copy(text, data)
	text[len(data)] = '\n'
	return text, true
}

// 读 Compiled/sources.json；没有记录时 found 为 false。
sources_read :: proc(out: string) -> (record: Sources_Record, found: bool, reason: string) {
	path := path_join(out, SOURCES_RECORD)
	if !os.exists(path) do return {}, false, ""
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return {}, true, fmt.tprintf("无法读取 %s: %v", path, err)
	if json.unmarshal(data, &record, allocator = context.temp_allocator) != nil {
		return {}, true, fmt.tprintf("%s 格式不对", path)
	}
	return record, true, ""
}

// 记录与当前源码的差异，每行一项（修改 / 新增 / 删除），一致时为空。分配在 temp_allocator。
sources_diff :: proc(recorded, current: Sources_Record) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	if recorded.version != current.version {
		append(&lines, fmt.tprintf("记录版本 %d，当前工具为 %d", recorded.version, current.version))
	}
	known := make(map[string]string, context.temp_allocator)
	for entry in recorded.files do known[entry.path] = entry.hash
	for entry in current.files {
		hash, ok := known[entry.path]
		if !ok {
			append(&lines, fmt.tprintf("新增 %s", entry.path))
		} else if hash != entry.hash {
			append(&lines, fmt.tprintf("修改 %s", entry.path))
		}
		delete_key(&known, entry.path)
	}
	for entry in recorded.files {
		if entry.path in known do append(&lines, fmt.tprintf("删除 %s", entry.path))
	}
	return lines[:]
}

// -check：产物与源码一致时返回 true；否则打印原因。
sources_check :: proc(dir: string) -> bool {
	out := path_join(dir, "Compiled")
	current, reason := sources_collect(dir)
	if reason != "" {
		fmt.eprintln(reason)
		return false
	}
	recorded, found, read_reason := sources_read(out)
	if read_reason != "" {
		fmt.eprintln(read_reason)
		return false
	}
	if !found {
		fmt.eprintfln("%s 没有源码记录：用 tools/shaders 重新生成 -dir:%s", out, dir)
		return false
	}
	lines := sources_diff(recorded, current)
	if len(lines) == 0 {
		fmt.printfln("%s 与源码一致（%d 个文件）", out, len(current.files))
		return true
	}
	fmt.eprintfln("%s 已过期，用 tools/shaders 重新生成 -dir:%s", out, dir)
	for line in lines do fmt.eprintfln("  %s", line)
	return false
}
