// 单文件 Shader 描述：声明式参数、Pass 与原样 HLSL；解析过程不读取文件、不创建设备或执行 GPU 操作。
package lang

// 分区：文档与所有权 / 解析入口 / 属性与 Pass / 词法与诊断。
import "core:fmt"
import "core:math"
import "core:mem"
import "core:reflect"
import "core:strconv"
import "core:strings"

import fx "../effect"

// 标准 include 的根目录：作者写 #include "olib/<Draw>.hlsli"（model / sprite / fullscreen），引擎 b0 块都声明在那里。
// shadercross 只接受一个 -I，tools/shaders 与 Shader Lab 编译前把 <INCLUDE_DIRECTORY>/olib 复制到各自的临时目录。
// 写成 "/include"：单元测试的隔离编译把 #directory 换成不带结尾分隔符的路径。
INCLUDE_DIRECTORY :: #directory + "/include"

Document :: struct {
	schemas: []fx.Schema,
	effect: fx.Effect_Desc,
	// 与 schemas 一一对应，已包含参数布局、共享代码和原文件 #line。
	// Sprite Pass 的 programs 是批量变体（foster BatcherVertex 输入，Render2D 逐个绘制用）；
	// instanced 效果另有 instanced_programs：缓冲变体（实例记录 + 角点，常驻 Sprite_Buffer 用），只需编译顶点阶段。
	// 其他 Pass 或非 instanced 效果对应项为空串。
	programs: []string,
	instanced_programs: []string,
	error: string,
}

dispose :: proc(d: ^Document) {
	for &s in d.schemas {
		fx.schema_dispose(&s)
	}
	delete(d.schemas)
	fx.effect_dispose(&d.effect)
	for text in d.programs {
		delete(text)
	}
	delete(d.programs)
	for text in d.instanced_programs {
		delete(text)
	}
	delete(d.instanced_programs)
	delete(d.error)
	d^ = {}
}

@(private)
Token :: struct {
	text: string,
	quoted: bool,
	line, column: int,
}

@(private)
Parser :: struct {
	text, path: string,
	pos: int,
	line, column: int,
	token: Token,
	error: string,
}

@(private)
Code :: struct {
	text: string,
	line: int,
}

// 顶层 Shader { ... } 解析出的原始部分；passes 与 codes、previews 一一对应。
@(private)
Shader_Source :: struct {
	effect: fx.Effect_Desc,
	fields: []fx.Field,
	passes: [dynamic]fx.Pass_Desc,
	codes: [dynamic]Code,
	previews: [dynamic]string, // 每个 Pass 显式声明的预览维度，空值由 shader_programs 推断。
	shared: Code, // HLSLINCLUDE 共享代码。
}

// source_path 同时写入诊断和 HLSL #line；返回文档独立拥有全部数据。
parse :: proc(text, source_path: string) -> (result: Document) {
	allocator := context.allocator
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)
	context.temp_allocator = context.allocator
	p := Parser{text = text, path = source_path, line = 1, column = 1}
	next(&p)
	expect(&p, "Shader")
	name := string_value(&p)
	if !identifier(name) {
		fail(&p, "Shader name must be an identifier; use Label for display names")
	}
	source := shader_body(&p, name)
	schemas, programs, instanced_programs := shader_programs(&source, name, source_path)
	if p.error == "" {
		_, error := fx.effect_order(source.effect, schemas)
		if error != "" {
			fail(&p, error)
		}
	}
	context.allocator = allocator
	if p.error != "" {
		result.error = strings.clone(p.error)
		return
	}
	result.effect = fx.effect_clone(source.effect)
	result.schemas = make([]fx.Schema, len(schemas))
	result.programs = make([]string, len(programs))
	result.instanced_programs = make([]string, len(programs))
	for s, i in schemas {
		result.schemas[i] = fx.schema_clone(s)
		result.programs[i] = strings.clone(programs[i])
		result.instanced_programs[i] = strings.clone(instanced_programs[i])
	}
	return
}

// 解析 `{ 指令... }`：每个指令至多一次（Pass 除外），并补全默认 Output。
@(private)
shader_body :: proc(p: ^Parser, name: string) -> (source: Shader_Source) {
	expect(p, "{")
	source.effect = fx.Effect_Desc{name = name}
	seen := make(map[string]bool)
	for p.error == "" && p.token.text != "}" {
		key := p.token.text
		if key != "HLSLINCLUDE" {
			next(p)
		}
		if key != "Pass" && seen[key] {
			fail(p, "Duplicate Shader directive")
			break
		}
		seen[key] = true
		switch key {
		case "Label":
			source.effect.label = string_value(p)
		case "Preview":
			source.effect.preview = preview(p)
		case "Output":
			source.effect.output = fx.Target_Ref(string_value(p))
		case "Instanced":
			source.effect.instanced = true
		case "Properties":
			source.fields = properties(p)
		case "HLSLINCLUDE":
			source.shared = code_block(p)
		case "Pass":
			pass, code, dimension := pass_block(p)
			append(&source.passes, pass)
			append(&source.codes, code)
			append(&source.previews, dimension)
		case:
			fail(p, "Expected Properties, Pass, HLSLINCLUDE, Label, Preview, Output or Instanced")
		}
	}
	expect(p, "}")
	if p.token.text != "" {
		fail(p, "Unexpected content after Shader")
	}
	if len(source.passes) == 0 {
		fail(p, "Shader requires at least one Pass")
	}
	if source.effect.output == "" && len(source.passes) > 0 {
		source.effect.output = source.passes[len(source.passes)-1].output
	}
	for field in source.fields do source.effect.instanced = source.effect.instanced || field.instance
	source.effect.passes = source.passes[:]
	return
}

// 每个 Pass 一份参数组 Schema 和候选 HLSL（参数布局 + 共享代码 + Pass 代码，带原文件 #line）。
// 会把 Pass 的 params 指向生成的组名 `<Shader>_<Pass>`。Sprite Pass 生成批量变体，instanced 效果再生成缓冲变体。
@(private)
shader_programs :: proc(source: ^Shader_Source, name, source_path: string) -> (schemas: []fx.Schema,
	programs, instanced_programs: []string) {
	schemas = make([]fx.Schema, len(source.passes))
	programs = make([]string, len(source.passes))
	instanced_programs = make([]string, len(source.passes))
	for &pass, i in source.passes {
		group := fmt.tprintf("%s_%s", name, pass.id)
		pass.params = fx.Params_Ref(group)
		dimension := source.previews[i]
		if dimension == "" {
			dimension = pass.draw == .Model ? "3d" : "2d"
			if pass.draw == .Preview_Model && source.effect.preview != "" {
				dimension = source.effect.preview
			}
		}
		schemas[i] = {name = group, shader = source_path, preview = dimension,
			label = pass.label, fields = source.fields}
		if pass.draw == .Sprite {
			programs[i] = shader_program(source, i, schemas[i], .Sprite_Batch, source_path)
			if source.effect.instanced {
				instanced_programs[i] = shader_program(source, i, schemas[i], .Sprite, source_path)
			}
		} else {
			programs[i] = shader_program(source, i, schemas[i], fx.effect_instancing(source.effect), source_path)
		}
	}
	return
}

@(private)
shader_program :: proc(source: ^Shader_Source, index: int, schema: fx.Schema, mode: fx.Instancing,
	source_path: string) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, fx.hlsl(schema, mode))
	for block in ([2]Code{source.shared, source.codes[index]}) {
		if block.text == "" {
			continue
		}
		path, _ := strings.replace_all(source_path, "\\", "/")
		fmt.sbprintf(&b, "\n#line %d %q\n%s\n", block.line, path, block.text)
	}
	return strings.to_string(b)
}

// ==============================================================================
// 属性与 Pass
// ==============================================================================

@(private)
properties :: proc(p: ^Parser) -> []fx.Field {
	expect(p, "{")
	fields: [dynamic]fx.Field
	textures, instances := 0, 0
	for p.error == "" && p.token.text != "}" {
		attributes := property_attributes(p)
		name := p.token.text
		if p.token.quoted || !strings.has_prefix(name, "_") ||
			!identifier(name[1:]) || strings.has_prefix(name, "_olib_") {
			fail(p, "Property name must start with _ followed by an identifier; _olib_ is reserved")
			break
		}
		next(p)
		field := property_declaration(p, name[1:], attributes.id, attributes.step)
		field.instance = attributes.instance
		field.filter, field.wrap = attributes.filter, attributes.wrap
		field.filter_declared, field.wrap_declared = attributes.filter_declared, attributes.wrap_declared
		if (field.filter_declared || field.wrap_declared) && field.kind != .Texture {
			fail(p, "Filter and Wrap apply only to 2D properties")
		}
		if field.kind == .Texture do textures += 1
		if field.instance do instances += 1
		property_check(p, field, fields[:], textures, instances)
		append(&fields, field)
	}
	expect(p, "}")
	return fields[:]
}

// 属性前的 [Id("...")] [Step(n)] [Instance] [Filter(Linear|Nearest)] [Wrap(Clamp|Repeat|Mirror)] 特性，
// 每种至多一次；Instance 没有参数。结果放在 Field 的 id/step/instance/filter/wrap 与 *_declared。
@(private)
property_attributes :: proc(p: ^Parser) -> (result: fx.Field) {
	result.step = 0.01
	attributes := make(map[string]bool)
	for p.token.text == "[" && p.error == "" {
		next(p)
		key := p.token.text
		next(p)
		if attributes[key] {
			fail(p, "Duplicate property attribute")
		}
		attributes[key] = true
		if key == "Instance" {
			result.instance = true
			expect(p, "]")
			continue
		}
		expect(p, "(")
		switch key {
		case "Id":
			result.id = string_value(p)
		case "Step":
			result.step = number(p)
		case "Filter":
			result.filter_declared = true
			switch p.token.text {
			case "Linear": result.filter = .Linear
			case "Nearest": result.filter = .Nearest
			case: fail(p, "Filter must be Linear or Nearest")
			}
			next(p)
		case "Wrap":
			result.wrap_declared = true
			switch p.token.text {
			case "Clamp": result.wrap = .Clamp
			case "Repeat": result.wrap = .Repeat
			case "Mirror": result.wrap = .Mirror
			case: fail(p, "Wrap must be Clamp, Repeat or Mirror")
			}
			next(p)
		case:
			fail(p, "Expected Id, Step, Instance, Filter or Wrap attribute")
		}
		expect(p, ")")
		expect(p, "]")
	}
	return
}

// 解析 `(标签, 类型[(最小, 最大)]) = 默认值`；向量/颜色可显式指定控件范围，Float 默认 -10000..10000。
@(private)
property_declaration :: proc(p: ^Parser, name, id: string, step: f32) -> fx.Field {
	field := fx.Field{name = name, minimum = 0, maximum = 1, step = step}
	field.id = id == "" ? field.name : id
	expect(p, "(")
	field.label = string_value(p)
	expect(p, ",")
	kind := p.token.text
	next(p)
	switch kind {
	case "Range", "Float":
		field.kind = .Scalar
	case "Vector2":
		field.kind = .Vector2
	case "Vector3":
		field.kind = .Vector3
	case "Color":
		field.kind = .Color
	case "2D":
		field.kind = .Texture
	case:
		fail(p, "Expected Range, Float, Vector2, Vector3, Color or 2D")
	}
	if kind == "Float" {
		field.minimum = -10000
		field.maximum = 10000
	}
	if kind == "Range" || p.token.text == "(" {
		if field.kind == .Texture {
			fail(p, "Texture cannot have a numeric range")
		}
		expect(p, "(")
		field.minimum = number(p)
		expect(p, ",")
		field.maximum = number(p)
		expect(p, ")")
	}
	expect(p, ")")
	expect(p, "=")
	if field.kind == .Texture {
		field.texture = string_value(p)
	} else {
		field.initial = vector(p, fx.components(field.kind))
	}
	return field
}

// 范围、纹理数量、默认值区间，以及与已有属性的重名/采样器冲突。
@(private)
property_check :: proc(p: ^Parser, field: fx.Field, prior_fields: []fx.Field, textures, instances: int) {
	if field.instance && field.kind == .Texture {
		fail(p, "Texture cannot be Instance")
	}
	if instances > fx.MAX_INSTANCE_FIELDS {
		fail(p, "More than 4 Instance properties")
	}
	if field.minimum > field.maximum || field.step <= 0 || textures > fx.MAX_TEXTURES {
		fail(p, "Invalid property range/step or more than 16 textures")
	}
	for c in 0..<fx.components(field.kind) {
		if field.initial[c] < field.minimum || field.initial[c] > field.maximum {
			fail(p, "Property default is outside its range")
		}
	}
	for prior in prior_fields {
		if prior.id == field.id || prior.name == field.name {
			fail(p, "Duplicate property name or Id")
		}
		if (prior.kind == .Texture && field.name == fmt.tprintf("%sSampler", prior.name)) ||
			(field.kind == .Texture && prior.name == fmt.tprintf("%sSampler", field.name)) {
			fail(p, "Property collides with a generated sampler")
		}
	}
}

@(private)
pass_block :: proc(p: ^Parser) -> (pass: fx.Pass_Desc, code: Code, dimension: string) {
	pass.id = fx.Pass_Id(string_value(p))
	if !identifier(string(pass.id)) {
		fail(p, "Pass name must be an identifier")
	}
	pass.output = "color"
	expect(p, "{")
	seen := make(map[string]bool)
	inputs: [dynamic]fx.Pass_Input
	values: [dynamic]fx.Pass_Value
	for p.error == "" && p.token.text != "}" {
		key := p.token.text
		if key != "HLSLPROGRAM" {
			next(p)
		}
		if key != "Input" && key != "Value" && seen[key] {
			fail(p, "Duplicate Pass directive")
			break
		}
		seen[key] = true
		switch key {
		case "Label":
			pass.label = string_value(p)
		case "Preview":
			dimension = preview(p)
		case "Draw":
			pass.draw = enum_value(p, fx.Pass_Draw)
		case "Cull":
			pass.state.cull = enum_value(p, fx.Pass_Cull)
		case "Blend":
			pass.state.blend = enum_value(p, fx.Pass_Blend)
		case "ZTest":
			pass.state.depth = enum_value(p, fx.Pass_Depth)
		case "ZWrite":
			pass.state.depth_write = enum_value(p, fx.Pass_Write)
		case "Disabled":
			pass.disabled = enum_value(p, fx.Pass_Write) == .On
		case "Output":
			pass.output = fx.Target_Ref(string_value(p))
		case "SpriteTexture":
			pass.sprite_texture = fx.Field_Ref(field_ref(p))
		case "Target":
			pass.target = target_block(p)
		case "Input":
			input: fx.Pass_Input
			input.field = fx.Field_Ref(field_ref(p))
			input.target = fx.Target_Ref(string_value(p))
			input.frame = enum_value(p, fx.Pass_Frame)
			append(&inputs, input)
		case "Value":
			value: fx.Pass_Value
			value.field = fx.Field_Ref(field_ref(p))
			value.number = vector(p, 0)
			append(&values, value)
		case "HLSLPROGRAM":
			code = code_block(p)
		case:
			fail(p, "Unknown Pass directive")
		}
	}
	expect(p, "}")
	if strings.trim_space(code.text) == "" {
		fail(p, "Pass requires a nonempty HLSLPROGRAM")
	}
	pass.inputs = inputs[:]
	pass.values = values[:]
	return
}

@(private)
target_block :: proc(p: ^Parser) -> (target: fx.Target_Desc) {
	expect(p, "{")
	seen := make(map[string]bool)
	for p.error == "" && p.token.text != "}" {
		key := p.token.text
		next(p)
		if seen[key] {
			fail(p, "Duplicate Target directive")
		}
		seen[key] = true
		switch key {
		case "Scale":
			target.scale = number(p)
		case "Format":
			target.format = enum_value(p, fx.Target_Format)
		case "Depth":
			target.depth = enum_value(p, fx.Pass_Write) == .On
		case "Samples":
			target.samples = integer(p)
		case "Size":
			target.width = integer(p)
			target.height = integer(p)
		case "Clear":
			target.clear = vector(p, 4)
		case:
			fail(p, "Unknown Target directive")
		}
	}
	expect(p, "}")
	return
}

// ==============================================================================
// 词法与诊断
// ==============================================================================

@(private)
fail :: proc(p: ^Parser, message: string) {
	if p.error == "" {
		p.error = fmt.aprintf("%s:%d:%d: %s (at '%s')", p.path,
			p.token.line, p.token.column, message, p.token.text)
	}
}

@(private)
advance :: proc(p: ^Parser) {
	if p.pos >= len(p.text) {
		return
	}
	if p.text[p.pos] == '\n' {
		p.line += 1
		p.column = 1
	} else {
		p.column += 1
	}
	p.pos += 1
}

@(private)
next :: proc(p: ^Parser) {
	if p.error != "" {
		return
	}
	for p.pos < len(p.text) {
		c := p.text[p.pos]
		if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
			advance(p)
		} else if strings.has_prefix(p.text[p.pos:], "//") {
			for p.pos < len(p.text) && p.text[p.pos] != '\n' {
				advance(p)
			}
		} else if strings.has_prefix(p.text[p.pos:], "/*") {
			advance(p)
			advance(p)
			for p.pos < len(p.text) && !strings.has_prefix(p.text[p.pos:], "*/") {
				advance(p)
			}
			if p.pos == len(p.text) {
				fail(p, "Unterminated comment")
				return
			}
			advance(p)
			advance(p)
		} else {
			break
		}
	}
	p.token = {line = p.line, column = p.column}
	if p.pos == len(p.text) {
		return
	}
	start := p.pos
	c := p.text[p.pos]
	advance(p)
	if c == '"' {
		for p.pos < len(p.text) && p.text[p.pos] != '"' {
			if p.text[p.pos] == '\\' {
				advance(p)
			}
			advance(p)
		}
		if p.pos == len(p.text) {
			fail(p, "Unterminated string")
			return
		}
		advance(p)
		value, _, ok := strconv.unquote_string(p.text[start:p.pos])
		if !ok {
			fail(p, "Invalid string escape")
			return
		}
		p.token.text = value
		p.token.quoted = true
	} else if strings.contains_rune("{}()[]=,", rune(c)) {
		p.token.text = p.text[start:p.pos]
	} else {
		for p.pos < len(p.text) {
			c = p.text[p.pos]
			if strings.contains_rune(" \t\r\n{}()[]=,\"/", rune(c)) {
				break
			}
			advance(p)
		}
		p.token.text = p.text[start:p.pos]
	}
}

@(private)
expect :: proc(p: ^Parser, value: string) {
	if p.token.quoted || p.token.text != value {
		fail(p, fmt.tprintf("Expected %s", value))
		return
	}
	next(p)
}

@(private)
string_value :: proc(p: ^Parser) -> string {
	if !p.token.quoted {
		fail(p, "Expected quoted string")
	}
	value := p.token.text
	next(p)
	return value
}

@(private)
number :: proc(p: ^Parser) -> f32 {
	value, ok := strconv.parse_f32(p.token.text)
	if !ok || p.token.quoted || math.is_nan(value) || math.is_inf(value) {
		fail(p, "Expected finite number")
	}
	next(p)
	return value
}

@(private)
integer :: proc(p: ^Parser) -> int {
	value := number(p)
	if value < 0 || value > 8192 || value != math.floor(value) {
		fail(p, "Expected integer within 0..8192")
		return 0
	}
	return int(value)
}

@(private)
vector :: proc(p: ^Parser, count: int) -> (value: [4]f32) {
	if count == 1 || (count == 0 && p.token.text != "(") {
		value[0] = number(p)
		return
	}
	expect(p, "(")
	n := 0
	for p.error == "" && n < 4 {
		value[n] = number(p)
		n += 1
		if p.token.text != "," {
			break
		}
		next(p)
	}
	expect(p, ")")
	if count != 0 && n != count {
		fail(p, "Wrong number of vector components")
	}
	return
}

@(private)
identifier :: proc(value: string) -> bool {
	if len(value) == 0 {
		return false
	}
	for c, i in value {
		if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(i > 0 && c >= '0' && c <= '9') {
			continue
		}
		return false
	}
	return true
}

@(private)
enum_value :: proc(p: ^Parser, $T: typeid) -> T {
	value, ok := reflect.enum_from_name(T, p.token.text)
	if !ok || p.token.quoted {
		fail(p, fmt.tprintf("Invalid %T value", value))
	}
	next(p)
	return value
}

@(private)
preview :: proc(p: ^Parser) -> string {
	value := p.token.text
	if p.token.quoted || (value != "2D" && value != "3D") {
		fail(p, "Expected 2D or 3D")
	}
	next(p)
	return value == "3D" ? "3d" : "2d"
}

@(private)
field_ref :: proc(p: ^Parser) -> string {
	if p.token.quoted {
		return string_value(p) // 字符串引用稳定 Id。
	}
	value := p.token.text
	if !strings.has_prefix(value, "_") || !identifier(value[1:]) {
		fail(p, "Expected _property or quoted stable Id")
		return ""
	}
	next(p)
	return value[1:]
}

// HLSL 保持原文；ENDHLSL 必须单独成行，注释和字符串中的同名文字不是结束标记。
// 调用方停在起始标记；不把 HLSL 交给外层词法器，保留开头注释和预处理指令。
@(private)
code_block :: proc(p: ^Parser) -> Code {
	start := p.pos
	first_line := p.line
	block_comment := false
	quote: u8
	for p.pos < len(p.text) && p.error == "" {
		line_start := p.pos
		line_end := line_start
		for line_end < len(p.text) && p.text[line_end] != '\n' {
			line_end += 1
		}
		if !block_comment && quote == 0 && strings.trim_space(p.text[line_start:line_end]) == "ENDHLSL" {
			result := Code{p.text[start:line_start], first_line}
			for p.pos < line_end {
				advance(p)
			}
			next(p)
			return result
		}
		for p.pos < line_end {
			c := p.text[p.pos]
			if block_comment {
				if strings.has_prefix(p.text[p.pos:], "*/") {
					advance(p)
					block_comment = false
				}
			} else if quote != 0 {
				if c == '\\' {
					advance(p)
				} else if c == quote {
					quote = 0
				}
			} else if strings.has_prefix(p.text[p.pos:], "//") {
				for p.pos < line_end {
					advance(p)
				}
				break
			} else if strings.has_prefix(p.text[p.pos:], "/*") {
				block_comment = true
				advance(p)
			} else if c == '"' || c == '\'' {
				quote = c
			}
			advance(p)
		}
		advance(p)
	}
	fail(p, "Missing ENDHLSL on its own line")
	return {}
}
