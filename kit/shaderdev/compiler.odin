#+build !js
package shaderdev

// 开发期编译器：独立临时目录承载完整候选版本，不覆盖发布产物。
// 分区：编译 / 源码指纹。所有返回的持久数据使用 heap_allocator。

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"

// core:os 的 process_start 会修改句柄继承标记；跨会话编译必须串行创建子进程。
@(private)
compiler_mutex: sync.Mutex

Resources :: struct {
	samplers: int,
	storage_textures: int,
	storage_buffers: int,
	uniform_buffers: int,
}

Build :: struct {
	code: [2][]u8,
	resources: [2]Resources,
	error: string,
}

build_dispose :: proc(b: ^Build) {
	for code in b.code {
		delete(code, runtime.heap_allocator())
	}
	delete(b.error, runtime.heap_allocator())
	b^ = {}
}

@(private)
run_compiler :: proc(args: ..string) -> string {
	sync.mutex_lock(&compiler_mutex)
	defer sync.mutex_unlock(&compiler_mutex)
	command := make([]string, len(args) + 1, context.temp_allocator)
	command[0] = "shadercross"
	copy(command[1:], args)
	state, stdout, stderr, err := os.process_exec({command = command}, context.temp_allocator)
	if err != nil || !state.exited || state.exit_code != 0 ||
		strings.contains(string(stderr), "error:") || strings.contains(string(stdout), "error:") {
		return fmt.aprintf("shadercross failed (%v, exit %d)\n%s%s", err, state.exit_code,
			string(stdout), string(stderr))
	}
	return ""
}

// source 为绝对路径；format 是 spv/dxil/msl。调用方拥有结果，使用 build_dispose。
compile :: proc(source, format: string, header: string = "", header_include: string = "") -> (result: Build) {
	context.allocator = runtime.heap_allocator()
	if format != "spv" && format != "dxil" && format != "msl" {
		result.error = strings.clone("Unsupported shader format")
		return
	}
	directory, err := os.make_directory_temp("", "olib_shader_*", context.temp_allocator)
	if err != nil {
		result.error = fmt.aprintf("Cannot create shader workspace: %v", err)
		return
	}
	defer {

		remove_workspace(directory)
	}
	root := filepath.dir(source)
	if !snapshot_sources(root, directory, header_include) {
		result.error = strings.clone("Cannot snapshot shader sources")
		return
	}
	if header != "" && os.write_entire_file(fmt.tprintf("%s/params.generated.hlsli", directory), header) != nil {
		result.error = strings.clone("Cannot write generated parameter include")
		return
	}
	local_source := fmt.tprintf("%s/%s", directory, filepath.base(source))
	for stage, i in ([2]string{"vertex", "fragment"}) {
		spv := fmt.tprintf("%s/%s.spv", directory, stage)
		entry := fmt.tprintf("%s_main", stage)
		result.error = run_compiler(local_source, "-s", "HLSL", "-d", "SPIRV", "-t", stage,
			"-e", entry, "-I", directory, "-o", spv)
		if result.error != "" do return
		reflection := fmt.tprintf("%s/%s.json", directory, stage)
		result.error = run_compiler(spv, "-s", "SPIRV", "-d", "JSON", "-t", stage,
			"-o", reflection)
		if result.error != "" do return
		metadata, read_ok := os.read_entire_file(reflection, context.temp_allocator)
		if read_ok != nil || json.unmarshal(metadata, &result.resources[i]) != nil {
			result.error = strings.clone("Cannot read shader resource reflection")
			return
		}
		output := spv
		if format != "spv" {
			output = fmt.tprintf("%s/%s.%s", directory, stage, format)
			dest := format == "dxil" ? "DXIL" : "MSL"
			result.error = run_compiler(spv, "-s", "SPIRV", "-d", dest, "-t", stage,
				"-e", entry, "-o", output)
			if result.error != "" do return
		}
		result.code[i], read_ok = os.read_entire_file(output, context.allocator)
		if read_ok != nil || len(result.code[i]) == 0 {
			result.error = strings.clone("Cannot read compiled shader")
			return
		}
	}
	return
}

// 两个阶段从同一份快照编译，编辑器后续保存不会改写编译中的输入。
@(private)
snapshot_sources :: proc(root, destination: string, header_include: string = "") -> bool {
	entries, err := os.read_all_directory_by_path(root, context.temp_allocator)
	if err != nil do return false
	for entry in entries {
		path := fmt.tprintf("%s/%s", destination, entry.name)
		if entry.type == .Directory {
			if os.make_directory(path) != nil || !snapshot_sources(entry.fullpath, path, header_include) do return false
		} else if entry.type == .Regular &&
			(strings.has_suffix(entry.name, ".hlsl") || strings.has_suffix(entry.name, ".hlsli")) {
			data, read_error := os.read_entire_file(entry.fullpath, context.temp_allocator)
			if read_error != nil do return false
			if header_include != "" {
				// IDE 读取 library 中的相对路径；编译副本仍使用本次候选的独立头文件。
				text, _ := strings.replace_all(string(data), fmt.tprintf("\"%s\"", header_include),
					"\"params.generated.hlsli\"", context.temp_allocator)
				data = transmute([]u8)text
			}
			if os.write_entire_file(path, data) != nil do return false
		}
	}
	return true
}

// 仅用于 make_directory_temp 创建、由本编译器写入的目录；不跟随链接。
@(private)
remove_workspace :: proc(root: string) {
	entries, _ := os.read_all_directory_by_path(root, context.temp_allocator)
	for entry in entries {
		if entry.type == .Directory {
			remove_workspace(entry.fullpath)
		} else {
			_ = os.remove(entry.fullpath)
		}
	}
	_ = os.remove(root)
}

// 对目录内所有 HLSL/HLSLI 内容计算指纹，包括子目录。include 应放在此根内。
// 内容散列避免编辑器原子保存、时间戳精度以及同长度修改漏检。
source_fingerprint :: proc(root: string) -> (hash: u64, ok: bool) {
	paths := make([dynamic]string, 0, 0, context.temp_allocator)
	defer delete(paths)
	if !collect_sources(root, &paths) do return 0, false
	slice.sort(paths[:])
	hash = 1469598103934665603
	for path in paths {
		data, read_ok := os.read_entire_file(path, context.temp_allocator)
		if read_ok != nil do return 0, false
		for b in transmute([]u8)path {
			hash = (hash ~ u64(b)) * 1099511628211
		}
		for b in data {
			hash = (hash ~ u64(b)) * 1099511628211
		}
		hash = (hash ~ u64(len(data))) * 1099511628211
	}
	return hash, true
}

@(private)
collect_sources :: proc(root: string, paths: ^[dynamic]string) -> bool {
	entries, err := os.read_all_directory_by_path(root, context.temp_allocator)
	if err != nil do return false
	for entry in entries {
		if entry.type == .Directory {
			if !collect_sources(entry.fullpath, paths) do return false
		} else if entry.type == .Regular &&
			(strings.has_suffix(entry.name, ".hlsl") || strings.has_suffix(entry.name, ".hlsli")) {
			append(paths, entry.fullpath)
		}
	}
	return true
}
