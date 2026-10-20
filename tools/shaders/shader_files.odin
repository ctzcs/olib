package main

// 单文件格式和预览共用 shaderlang；发布时输出字节码与纯数据描述，不依赖开发工具。
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

import mat "../../kit/rendering/material"
import lang "../../kit/rendering/shader/lang"

read_shader :: proc(path: string) -> lang.Document {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		fmt.eprintln("Cannot read", path, err)
		os.exit(1)
	}
	doc := lang.parse(string(data), path)
	if doc.error != "" {
		fmt.eprintln(doc.error)
		os.exit(1)
	}
	return doc
}

reserve_output :: proc(outputs: ^map[string]bool, name: string) {
	key := strings.to_lower(name)
	if outputs[key] {
		fmt.eprintln("Duplicate shader output:", name)
		os.exit(1)
	}
	outputs[key] = true
}

compile_shader :: proc(source, include_directory, output: string) -> bool {
	doc := read_shader(source)
	defer lang.dispose(&doc)
	workspace, err := os.make_directory_temp("", "olib_shader_publish_*", context.temp_allocator)
	if err != nil {
		fmt.eprintln(err)
		return false
	}
	defer remove_workspace(workspace)
	if !copy_includes(workspace) do return false
	files: [dynamic]string
	defer {
		for name in files {
			delete(name)
		}
		delete(files)
	}
	for &schema, i in doc.schemas {
		extracted := path_join(workspace, fmt.tprintf("%s.hlsl", schema.name))
		if !write_shader_file(extracted, transmute([]u8)doc.programs[i]) {
			return false
		}
		for stage in ([]string{"vertex", "fragment"}) {
			entry := fmt.tprintf("%s_main", stage)
			stem := fmt.tprintf("%s.%s", schema.name, stage)
			spv := path_join(workspace, fmt.tprintf("%s.spv", stem))
			if !shadercross(extracted, "-s", "HLSL", "-d", "SPIRV", "-t", stage,
				"-e", entry, "-I", include_directory, "-o", spv) {
				return false
			}
			for format in ([]string{"dxil", "msl"}) {
				if !shadercross(spv, "-s", "SPIRV", "-d", format == "dxil" ? "DXIL" : "MSL",
					"-t", stage, "-e", entry, "-o", path_join(workspace, fmt.tprintf("%s.%s", stem, format))) {
					return false
				}
			}
			for format in ([]string{"spv", "dxil", "msl"}) {
				append(&files, fmt.aprintf("%s.%s", stem, format))
			}
		}
		// instanced 精灵效果的缓冲变体：片元与批量变体相同，只编译顶点阶段。
		if doc.instanced_programs[i] != "" {
			instanced := path_join(workspace, fmt.tprintf("%s.instanced.hlsl", schema.name))
			if !write_shader_file(instanced, transmute([]u8)doc.instanced_programs[i]) {
				return false
			}
			stem := fmt.tprintf("%s.instanced.vertex", schema.name)
			spv := path_join(workspace, fmt.tprintf("%s.spv", stem))
			if !shadercross(instanced, "-s", "HLSL", "-d", "SPIRV", "-t", "vertex",
				"-e", "vertex_main", "-I", include_directory, "-o", spv) {
				return false
			}
			for format in ([]string{"dxil", "msl"}) {
				if !shadercross(spv, "-s", "SPIRV", "-d", format == "dxil" ? "DXIL" : "MSL",
					"-t", "vertex", "-e", "vertex_main", "-o", path_join(workspace, fmt.tprintf("%s.%s", stem, format))) {
					return false
				}
			}
			for format in ([]string{"spv", "dxil", "msl"}) {
				append(&files, fmt.aprintf("%s.%s", stem, format))
			}
		}
		// 发布描述只保留可移植的 GPU 资源键，不泄露开发机绝对路径。
		delete(schema.shader)
		schema.shader = strings.clone(schema.name)
	}
	manifest := struct {
		version: int,
		schemas: []mat.Schema,
		effect: mat.Effect_Desc,
	}{mat.MANIFEST_VERSION, doc.schemas, doc.effect}
	data, json_err := json.marshal(manifest)
	if json_err != nil {
		fmt.eprintln(json_err)
		return false
	}
	defer delete(data)
	// 全部 Pass 编译成功后才发布；描述最后写入。
	for name in files {
		bytes, read_err := os.read_entire_file(path_join(workspace, name), context.temp_allocator)
		if read_err != nil {
			fmt.eprintln(read_err)
			return false
		}
		if !write_shader_file(path_join(output, name), bytes) {
			return false
		}
	}
	if !write_shader_file(path_join(output, fmt.tprintf("%s.shader.json", doc.effect.name)), data) {
		return false
	}
	fmt.printfln("compiled %s (%d passes)", source, len(doc.schemas))
	return true
}

// 把 olib 标准 include 复制到工作区的 olib/ 下：生成的程序就在工作区，DXC 按当前文件所在目录找到
// #include "olib/..."；shadercross 只接受一个 -I，留给 shader 源目录。
copy_includes :: proc(workspace: string) -> bool {
	source := path_join(lang.INCLUDE_DIRECTORY, "olib")
	target := path_join(workspace, "olib")
	if err := os.make_directory(target); err != nil {
		fmt.eprintln("Cannot create", target, err)
		return false
	}
	entries, err := os.read_all_directory_by_path(source, context.temp_allocator)
	if err != nil {
		fmt.eprintln("Cannot read", source, err)
		return false
	}
	for entry in entries {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".hlsli") do continue
		data, read_err := os.read_entire_file(entry.fullpath, context.temp_allocator)
		if read_err != nil {
			fmt.eprintln("Cannot read", entry.fullpath, read_err)
			return false
		}
		if !write_shader_file(path_join(target, entry.name), data) do return false
	}
	return true
}

// 工作区只有本次写入的文件和 olib/ 子目录；不跟随链接。
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

write_shader_file :: proc(path: string, data: []u8) -> bool {
	if err := os.write_entire_file(path, data); err != nil {
		fmt.eprintln("Cannot write", path, err)
		return false
	}
	return true
}
