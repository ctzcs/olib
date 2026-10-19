package material

// 材质参数：Schema（参数声明）、Value（实例数值）及其 GPU 布局。
// 数据布局不依赖 Odin 结构体内存布局；本包不依赖编辑器。
// 分区：描述 / 生命周期与迁移 / GPU 布局。
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

// GPU 绑定上限与布局：每个数字参数占一个 float4 槽。
MAX_TEXTURES :: 16
MAX_UNIFORM_BYTES :: 16384
PARAM_SLOT_BYTES :: 16
// 每个绘制对象自带的数值字段（[Instance]）上限；它们随顶点而不是 uniform 传给 Shader。
MAX_INSTANCE_FIELDS :: 4

Kind :: enum {
	Scalar,
	Vector2,
	Vector3,
	Color,
	Texture,
}

Field :: struct {
	id, name, label: string,
	kind: Kind,
	minimum, maximum, step: f32,
	initial: [4]f32,
	texture: string,
	// 仅数值字段。true 时不占 uniform 槽，值随每个绘制对象的顶点传入，
	// 因此不同取值的对象仍可合批。Shader 里照常用 _name 读取。
	instance: bool,
}

Schema :: struct {
	name, shader, preview: string,
	label, folder: string, // 仅用于显示；name 仍是绑定和迁移的稳定 ID。
	fields: []Field,
}

// 每个数字参数占一个 float4 槽；Texture 单独编号，不占 uniform 空间。
// instance 字段同样保存在这里，但随顶点（见 Instance_Values）而不是 uniform 传给 Shader。
Value :: struct {
	number: [4]f32,
	texture: string,
}

components :: proc(kind: Kind) -> int {
	switch kind {
	case .Scalar: return 1
	case .Vector2: return 2
	case .Vector3: return 3
	case .Color: return 4
	case .Texture: return 0
	}
	return 0
}

// ==============================================================================
// 生命周期与迁移：所有字符串和切片由调用方 allocator 持有
// ==============================================================================

schema_dispose :: proc(s: ^Schema) {
	delete(s.name)
	delete(s.shader)
	delete(s.preview)
	delete(s.label)
	delete(s.folder)
	for f in s.fields {
		delete(f.id)
		delete(f.name)
		delete(f.label)
		delete(f.texture)
	}
	delete(s.fields)
	s^ = {}
}

schema_clone :: proc(s: Schema) -> Schema {
	r := s
	r.name = strings.clone(s.name)
	r.shader = strings.clone(s.shader)
	r.preview = strings.clone(s.preview)
	r.label = strings.clone(s.label)
	r.folder = strings.clone(s.folder)
	r.fields = make([]Field, len(s.fields))
	for f, i in s.fields {
		r.fields[i] = f
		r.fields[i].id = strings.clone(f.id)
		r.fields[i].name = strings.clone(f.name)
		r.fields[i].label = strings.clone(f.label)
		r.fields[i].texture = strings.clone(f.texture)
	}
	return r
}

schema_equal :: proc(a, b: Schema) -> bool {
	if a.name != b.name || a.shader != b.shader || a.preview != b.preview || len(a.fields) != len(b.fields) do return false
	if a.label != b.label || a.folder != b.folder do return false
	for f, i in a.fields {
		if f != b.fields[i] do return false
	}
	return true
}

values_dispose :: proc(values: []Value) {
	for value in values do delete(value.texture)
	delete(values)
}

// 字段 ID + 类型相同才迁移；新增/变更类型取默认值，范围收窄时钳制旧值。
values_make :: proc(schema: Schema, old: Schema = {}, previous: []Value = nil) -> []Value {
	values := make([]Value, len(schema.fields))
	for f, i in schema.fields {
		v := Value{number = f.initial, texture = f.texture}
		for prior, j in old.fields {
			if j < len(previous) && prior.id == f.id && prior.kind == f.kind {
				v = previous[j]
				break
			}
		}
		for c in 0..<components(f.kind) {
			v.number[c] = math.clamp(v.number[c], f.minimum, f.maximum)
		}
		v.texture = strings.clone(v.texture)
		values[i] = v
	}
	return values
}

// ==============================================================================
// GPU 布局：fragment b1/space3；引擎公共输入保留 b0
// ==============================================================================

// 字段是否占 fragment uniform 槽：数值且不是 per-instance。
uniform_field :: proc(f: Field) -> bool {
	return f.kind != .Texture && !f.instance
}

uniform_size :: proc(schema: Schema) -> int {
	count := 0
	for f in schema.fields do count += int(uniform_field(f))
	return max(1, count)*PARAM_SLOT_BYTES
}

// per-instance 字段个数，即每个对象顶点里携带的 float4 数据槽数。
instance_count :: proc(schema: Schema) -> int {
	count := 0
	for f in schema.fields do count += int(f.instance)
	return count
}

texture_count :: proc(schema: Schema) -> int {
	count := 0
	for f in schema.fields do count += int(f.kind == .Texture)
	return count
}

pack :: proc(schema: Schema, values: []Value, buffer: []u8) -> bool {
	if len(values) != len(schema.fields) || len(buffer) != uniform_size(schema) do return false
	mem.zero_slice(buffer)
	offset := 0
	for f, i in schema.fields {
		if !uniform_field(f) do continue
		mem.copy(raw_data(buffer[offset:]), raw_data(values[i].number[:]), PARAM_SLOT_BYTES)
		offset += PARAM_SLOT_BYTES
	}
	return true
}

// instanced 效果按绘制种类生成不同的 per-instance 接口。
Instancing :: enum {
	None,
	Sprite, // 精灵：OlibInstance 既是顶点输入（TEXCOORD2..）也是传给片元的变量
	Model,  // 模型：OlibInstanceInput 为顶点输入（世界矩阵 + tint + 字段），OlibInstance 传给片元
}

// 模型 instanced 顶点输入的语义号起点（只需与网格属性的语义号不重复）。
INSTANCE_MODEL_SEMANTIC_BASE :: 6
// 模型 instanced 传给片元的变量从 TEXCOORD8 起（tint、字段），避开常见的 TEXCOORD0..7 自定义变量。
INSTANCE_MODEL_VARYING_BASE :: 8

// 返回的字符串归调用方；由 shaderlang 直接放入每个 Pass 的候选 HLSL。
// 非 None（或存在 per-instance 字段）时还生成 OlibInstance，见 Instancing 各值的含义。
// 着色器须在 Output 里声明 OlibInstance，顶点里赋值，片元里把它赋给全局 olib_instance，
// 之后 _name 与 InstanceTint 即可使用；模型另需用 olib_world(instance) 取世界矩阵。
hlsl :: proc(schema: Schema, mode := Instancing.None) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "// Generated from Odin; do not edit.\ncbuffer MaterialParams : register(b1, space3) {\n")
	index := 0
	for f in schema.fields {
		if !uniform_field(f) do continue
		fmt.sbprintf(&b, "    float4 _olib_param_%d;\n", index)
		index += 1
	}
	if index == 0 do strings.write_string(&b, "    float4 _olib_unused;\n")
	strings.write_string(&b, "};\n")
	slots := instance_count(schema)
	kind := mode
	if kind == .None && slots > 0 do kind = .Sprite
	switch kind {
	case .None:
	case .Sprite:
		strings.write_string(&b, "struct OlibInstance {\n    nointerpolation float4 tint : TEXCOORD2;\n")
		for slot in 0..<slots {
			fmt.sbprintf(&b, "    nointerpolation float4 data%d : TEXCOORD%d;\n", slot, 3+slot)
		}
		strings.write_string(&b, "};\nstatic OlibInstance olib_instance;\n#define InstanceTint (olib_instance.tint)\n")
	case .Model:
		// 顶点属性的位置由 HLSL 入口里属性的声明顺序决定（不是语义号）：OlibInstanceInput 须是
		// Input 的第一个成员（位置 0..4+字段数），网格属性随后，绘制时网格属性整体后移。语义号只需互不相同。
		strings.write_string(&b, "struct OlibInstanceInput {\n")
		for column in 0..<4 {
			fmt.sbprintf(&b, "    float4 world%d : TEXCOORD%d;\n", column, INSTANCE_MODEL_SEMANTIC_BASE+column)
		}
		fmt.sbprintf(&b, "    float4 tint : TEXCOORD%d;\n", INSTANCE_MODEL_SEMANTIC_BASE+4)
		for slot in 0..<slots {
			fmt.sbprintf(&b, "    float4 data%d : TEXCOORD%d;\n", slot, INSTANCE_MODEL_SEMANTIC_BASE+5+slot)
		}
		// 含花括号的文本不能直接作 sbprintf 的格式串（花括号是它的占位符语法）。
		strings.write_string(&b, "};\nstruct OlibInstance {\n")
		fmt.sbprintf(&b, "    nointerpolation float4 tint : TEXCOORD%d;\n", INSTANCE_MODEL_VARYING_BASE)
		for slot in 0..<slots {
			fmt.sbprintf(&b, "    nointerpolation float4 data%d : TEXCOORD%d;\n", slot, INSTANCE_MODEL_VARYING_BASE+1+slot)
		}
		strings.write_string(&b, "};\nstatic OlibInstance olib_instance;\n#define InstanceTint (olib_instance.tint)\n")
		// 与 CPU 写入 uniform 的 Matrix4 同一约定：每个 float4 是矩阵的一列（行向量约定 v * M）。
		strings.write_string(&b, "float4x4 olib_world(OlibInstanceInput i) {\n    return transpose(float4x4(i.world0, i.world1, i.world2, i.world3));\n}\n")
		strings.write_string(&b, "OlibInstance olib_instance_from(OlibInstanceInput i) {\n    OlibInstance o;\n    o.tint = i.tint;\n")
		for slot in 0..<slots {
			fmt.sbprintf(&b, "    o.data%d = i.data%d;\n", slot, slot)
		}
		strings.write_string(&b, "    return o;\n}\n")
	}
	swizzles := [4]string{"x", "xy", "xyz", "xyzw"}
	index = 0
	slot := 0
	texture_slot := 0
	for f in schema.fields {
		switch {
		case f.kind == .Texture:
			fmt.sbprintf(&b, "Texture2D _%s : register(t%d, space2);\n", f.name, texture_slot)
			fmt.sbprintf(&b, "SamplerState _%sSampler : register(s%d, space2);\n", f.name, texture_slot)
			texture_slot += 1
		case f.instance:
			fmt.sbprintf(&b, "#define _%s (olib_instance.data%d.%s)\n", f.name, slot, swizzles[components(f.kind)-1])
			slot += 1
		case:
			fmt.sbprintf(&b, "#define _%s (_olib_param_%d.%s)\n", f.name, index, swizzles[components(f.kind)-1])
			index += 1
		}
	}
	return strings.to_string(b)
}
