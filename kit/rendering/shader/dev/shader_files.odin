#+build !js
package dev

// .oshader 候选包：程序文本和参数来自同一次文件读取。
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import sh "olib:kit/rendering/shader"
import lang "olib:kit/rendering/shader/lang"

Parameter_Program :: struct {
	group, source, text: string,
}

// 递归读取 source_directory 下的 .oshader。
// 全部持久数据由 heap_allocator 持有，使用 parameter_build_dispose 释放。
parameters_compile :: proc(source_directory: string) -> (result: Parameter_Build) {
	context.allocator = runtime.heap_allocator()
	paths := make([dynamic]string, context.temp_allocator)
	if !collect_sources(source_directory, &paths) {
		result.error = strings.clone("Cannot read shader source directory")
		return
	}
	slice.sort(paths[:])
	for path in paths {
		if !strings.has_suffix(path, ".oshader") {
			continue
		}
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil {
			result.error = fmt.aprintf("Cannot read %s: %v", path, err)
			return
		}
		absolute, _ := filepath.abs(path, context.temp_allocator)
		doc := lang.parse(string(data), absolute)
		defer lang.dispose(&doc)
		if doc.error != "" {
			result.error = strings.clone(doc.error)
			return
		}
		for old in result.effects {
			if old.name == doc.effect.name {
				result.error = fmt.aprintf("%s: duplicate effect %s", path, old.name)
				return
			}
		}
		for schema in doc.schemas {
			for old in result.schemas {
				if old.name == schema.name {
					result.error = fmt.aprintf("%s: duplicate parameter group %s", path, old.name)
					return
				}
			}
		}
		schemas := make([]sh.Schema, len(result.schemas)+len(doc.schemas))
		copy(schemas, result.schemas)
		for schema, i in doc.schemas {
			index := len(result.schemas)+i
			schemas[index] = sh.schema_clone(schema)
			delete(schemas[index].shader)
			relative, _ := filepath.rel(source_directory, path, context.temp_allocator)
			normalized, _ := strings.replace_all(relative, "\\", "/", context.temp_allocator)
			schemas[index].shader = strings.clone(normalized)
		}
		delete(result.schemas)
		result.schemas = schemas
		effects := make([]sh.Shader_Desc, len(result.effects)+1)
		copy(effects, result.effects)
		effects[len(result.effects)] = sh.shader_clone(doc.effect)
		delete(result.effects)
		result.effects = effects
		programs := make([]Parameter_Program, len(result.programs)+len(doc.programs))
		copy(programs, result.programs)
		for program, i in doc.programs {
			programs[len(result.programs)+i] = {strings.clone(doc.schemas[i].name),
				strings.clone(absolute), strings.clone(program)}
		}
		delete(result.programs)
		result.programs = programs
	}
	return
}

// .oshader 和其 HLSL include 共同参与包指纹；提交前再次检查，拒绝过期候选。
parameters_fingerprint :: proc(source_directory: string) -> (hash: u64, ok: bool) {
	return source_fingerprint(source_directory)
}
