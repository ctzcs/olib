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
	defer {
		entries, _ := os.read_all_directory_by_path(workspace, context.temp_allocator)
		for entry in entries {
			_ = os.remove(entry.fullpath)
		}
		_ = os.remove(workspace)
	}
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
		// 发布描述只保留可移植的 GPU 资源键，不泄露开发机绝对路径。
		delete(schema.shader)
		schema.shader = strings.clone(schema.name)
	}
	manifest := struct {
		version: int,
		schemas: []mat.Schema,
		effect: mat.Effect_Desc,
	}{1, doc.schemas, doc.effect}
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

write_shader_file :: proc(path: string, data: []u8) -> bool {
	if err := os.write_entire_file(path, data); err != nil {
		fmt.eprintln("Cannot write", path, err)
		return false
	}
	return true
}
