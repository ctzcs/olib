package paramgen

// 单个项目生成程序的反射端；默认值由真实 Odin 代码求值，不解析表达式。
import "core:encoding/json"
import "core:fmt"
import "core:os"

import mat "olib:kit/material"

// 保持原生成器 API；反射与布局校验由运行时 material 包统一提供。
describe :: mat.describe

// 生成入口在整个包内逐个调用，最终一次输出。错误终止，不发布部分参数描述。
add :: proc(schemas: ^[dynamic]mat.Schema, name: string, shader: mat.Shader_Path, preview: string, defaults: $T, label: string = "", folder: string = "") {
	schema, error := describe(name, shader, preview, defaults)
	schema.label = label
	schema.folder = folder
	if error != "" {
		fmt.eprintfln("%s: %s", name, error)
		os.exit(1)
	}
	for other in schemas {
		if other.shader == string(shader) {
			fmt.eprintfln("%s and %s reference the same shader", name, other.name)
			os.exit(1)
		}
	}
	append(schemas, schema)
}

add_effect :: proc(effects: ^[dynamic]mat.Effect_Desc, name: string,
	passes: []mat.Pass_Desc, output: mat.Target_Ref, schemas: []mat.Schema, label: string = "", preview: string = "") {
	effect := mat.Effect_Desc{name = name, output = output, passes = passes, label = label, preview = preview}
	order, error := mat.effect_order(effect, schemas)
	delete(order)
	if error != "" {
		fmt.eprintfln("%s: %s", name, error)
		os.exit(1)
	}
	append(effects, effect)
}

// 声明使用枚举；保留旧声明的字符串输入，运行时清单格式不变。
preview_name :: proc {preview_name_enum, preview_name_string}

@(private)
preview_name_enum :: proc(mode: mat.Preview_Mode) -> string {
	switch mode {
	case .Auto: return ""
	case .Two_D: return "2d"
	case .Three_D: return "3d"
	}
	return "invalid"
}

@(private)
preview_name_string :: proc(mode: string) -> string {
	return mode
}

write :: proc(schemas: []mat.Schema, effects: []mat.Effect_Desc = nil) {
	data := struct {schemas: []mat.Schema, effects: []mat.Effect_Desc}{schemas, effects}
	bytes, err := json.marshal(data)
	if err != nil || len(os.args) != 2 {
		fmt.eprintln("Cannot encode parameter descriptions / missing output path")
		os.exit(1)
	}
	if os.write_entire_file(os.args[1], bytes) != nil do os.exit(1)
}
