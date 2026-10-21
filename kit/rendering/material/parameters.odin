package material

// 材质参数：Schema（参数声明）、Value（实例数值）及其 GPU 布局。
// 数据布局不依赖 Odin 结构体内存布局；本包不依赖编辑器。
// 分区：描述 / 生命周期与迁移 / GPU 布局。
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import foster "../../../foster"

// GPU 绑定上限与布局：每个数字参数占一个 float4 槽。
MAX_TEXTURES :: 16
MAX_UNIFORM_BYTES :: 16384
PARAM_SLOT_BYTES :: 16
// 每个绘制对象自带的数值字段（[Instance]）的硬上限；它们随顶点而不是 uniform 传给 Shader。
// 每个实例占 INSTANCE_FIXED_ATTRIBUTES + 字段数个顶点属性，再加网格自己的属性，桌面 GPU 通常支持 16～32 个，
// 所以取 16。实际用几个由效果里的 [Instance] 字段数和缓冲的 slots 决定，库里没有全局配置；
// 更多的值请改用把几个标量打包进同一个 float4。
MAX_INSTANCE_FIELDS :: 16

Kind :: enum {
	Scalar,
	Vector2,
	Vector3,
	Color,
	Texture,
}

// 贴图字段的采样方式；零值即默认的线性过滤与边缘钳制。
Texture_Filter :: enum u8 {
	Linear,
	Nearest,
}

Texture_Wrap :: enum u8 {
	Clamp,
	Repeat,
	Mirror,
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
	// 仅 Texture 字段：采样器的过滤与两个方向的寻址方式。*_declared 记录 .oshader / 标签里是否显式写了，
	// 精灵纹理只用写了的部分，其余跟随 Render2D 的 push_sampler。
	filter: Texture_Filter,
	wrap: Texture_Wrap,
	filter_declared, wrap_declared: bool,
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

// Texture 字段声明的采样器；材质库、material_set_texture 与 Shader Lab 预览共用。
field_sampler :: proc(f: Field) -> foster.TextureSampler {
	filter: foster.TextureFilter = f.filter == .Nearest ? .Nearest : .Linear
	wrap: foster.TextureWrap
	switch f.wrap {
	case .Clamp: wrap = .Clamp
	case .Repeat: wrap = .Repeat
	case .Mirror: wrap = .MirroredRepeat
	}
	return foster.TextureSamplerMake(filter, wrap)
}

// 精灵纹理字段的采样器：字段显式写了 Filter / Wrap 的部分按字段，没写的部分沿用 inherited（Render2D 的 push_sampler）。
field_sprite_sampler :: proc(f: Field, inherited: foster.TextureSampler) -> foster.TextureSampler {
	sampler := inherited
	declared := field_sampler(f)
	if f.filter_declared do sampler.Filter = declared.Filter
	if f.wrap_declared do sampler.WrapX, sampler.WrapY = declared.WrapX, declared.WrapY
	return sampler
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

// instanced 效果按绘制种类生成不同的 per-instance 接口。两种都由调用方或渲染器提供一个
// 按实例步进的顶点缓冲，一次 Draw 画出全部实例。
Instancing :: enum {
	None,
	Sprite, // 精灵缓冲变体：实例记录含 2D 变换与图集矩形，单位四边形角点展开（常驻 Sprite_Buffer 用）
	Model,  // 模型：实例数据含世界矩阵，着色器用 olib_world 取得
	Sprite_Batch, // 精灵批量变体：foster BatcherVertex 输入，[Instance] 字段从顶点 storage buffer 按 mode 偏移读取
}

// instanced 顶点输入的语义号起点（只需与网格属性的语义号不重复）；位置由声明顺序决定。
INSTANCE_SEMANTIC_BASE :: 6
// 传给片元的变量从 TEXCOORD8 起（tint、字段），避开常见的 TEXCOORD0..7 自定义变量。
INSTANCE_VARYING_BASE :: 8
// 每个实例固定的顶点属性数（4 个 float4 的变换/几何 + tint），其后是每个 [Instance] 字段一个 float4。
INSTANCE_FIXED_ATTRIBUTES :: 5

// 返回的字符串归调用方；由 shaderlang 直接放入每个 Pass 的候选 HLSL。
// 非 None（或存在 per-instance 字段）时还生成 OlibInstanceInput / OlibInstance：
// - OlibInstanceInput 是顶点输入，必须是 Input 的第一个成员（网格属性随后），其位置 0..4+字段数；
// - OlibInstance 传给片元：Output 里声明它，顶点里 o.Instance = olib_instance_from(v.Instance)，
//   片元里把它赋给全局 olib_instance，之后 _name 与 InstanceTint 即可使用；
// - Model 用 olib_world(instance) 取世界矩阵；Sprite 用 olib_sprite_vertex(instance, corner, position, uv)
//   由单位四边形的角点 (0,0)(1,0)(1,1)(0,1) 得到屏幕像素位置和 UV。
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
	case .Model: hlsl_instance_block(&b, .Model, slots)
	case .Sprite, .Sprite_Batch: hlsl_sprite_block(&b, kind, slots)
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

// 生成 instanced 效果的 OlibInstanceInput / OlibInstance 及取世界矩阵、展开精灵四边形的辅助函数。
@(private)
hlsl_instance_block :: proc(b: ^strings.Builder, kind: Instancing, slots: int) {
	// 顶点属性的位置由 HLSL 入口里属性的声明顺序决定（不是语义号）。语义号只需互不相同。
	member := kind == .Sprite ? "sprite" : "world"
	strings.write_string(b, "struct OlibInstanceInput {\n")
	for column in 0..<4 {
		fmt.sbprintf(b, "    float4 %s%d : TEXCOORD%d;\n", member, column, INSTANCE_SEMANTIC_BASE+column)
	}
	fmt.sbprintf(b, "    float4 tint : TEXCOORD%d;\n", INSTANCE_SEMANTIC_BASE+4)
	for slot in 0..<slots {
		fmt.sbprintf(b, "    float4 data%d : TEXCOORD%d;\n", slot, INSTANCE_SEMANTIC_BASE+5+slot)
	}
	// 含花括号的文本不能直接作 sbprintf 的格式串（花括号是它的占位符语法）。
	strings.write_string(b, "};\n")
	hlsl_instance_varyings(b, slots)
	if kind == .Model {
		// 与 CPU 写入 uniform 的 Matrix4 同一约定：每个 float4 是矩阵的一列（行向量约定 v * M）。
		strings.write_string(b, "float4x4 olib_world(OlibInstanceInput i) {\n    return transpose(float4x4(i.world0, i.world1, i.world2, i.world3));\n}\n")
	} else {
		// sprite0 = (m11,m12,m21,m22)，sprite1 = (m31,m32, 局部矩形 x0,y0)，
		// sprite2 = (局部矩形 宽,高, uv0.xy)，sprite3 = (uv 宽,高)。变换沿用 Matrix3x2 的行向量约定。
		strings.write_string(b, "void olib_sprite_vertex(OlibInstanceInput i, float2 corner, out float2 position, out float2 uv) {\n")
		strings.write_string(b, "    float2 local = i.sprite1.zw + corner * i.sprite2.xy;\n")
		strings.write_string(b, "    position = float2(local.x * i.sprite0.x + local.y * i.sprite0.z + i.sprite1.x,\n")
		strings.write_string(b, "                      local.x * i.sprite0.y + local.y * i.sprite0.w + i.sprite1.y);\n")
		strings.write_string(b, "    uv = i.sprite2.zw + corner * i.sprite3.xy;\n}\n")
	}
	strings.write_string(b, "OlibInstance olib_instance_from(OlibInstanceInput i) {\n    OlibInstance o;\n    o.tint = i.tint;\n")
	for slot in 0..<slots {
		fmt.sbprintf(b, "    o.data%d = i.data%d;\n", slot, slot)
	}
	strings.write_string(b, "    return o;\n}\n")
}

// 传给片元的 OlibInstance（tint 与 [Instance] 字段，不插值）及全局 olib_instance、InstanceTint。
@(private)
hlsl_instance_varyings :: proc(b: ^strings.Builder, slots: int) {
	strings.write_string(b, "struct OlibInstance {\n")
	fmt.sbprintf(b, "    nointerpolation float4 tint : TEXCOORD%d;\n", INSTANCE_VARYING_BASE)
	for slot in 0..<slots {
		fmt.sbprintf(b, "    nointerpolation float4 data%d : TEXCOORD%d;\n", slot, INSTANCE_VARYING_BASE+1+slot)
	}
	strings.write_string(b, "};\nstatic OlibInstance olib_instance;\n#define InstanceTint (olib_instance.tint)\n")
}

// 2D 精灵效果的统一顶点接口：作者写 `struct Input { OlibSpriteInput Sprite; };`，
// 顶点里 `OlibSprite s = olib_sprite(v.Sprite);` 得到目标像素位置、UV、传给片元的 OlibInstance，
// 以及 axis_x / axis_y：精灵局部 1 像素在目标像素空间里的两条轴（局部→目标的 2×2 线性部分，含变换栈），
// 可据此按精灵大小计算偏移，例如 sqrt(abs(determinant)) 是精灵的缩放。
// 两种变体只有这一段不同，position 与轴都在目标像素空间，片元代码完全相同：
// - Sprite_Batch：顶点就是 foster BatcherVertex（位置、UV、颜色、mode），颜色即 tint；
//   mode 的 4 个字节是该精灵记录在 OlibInstanceValues（顶点 storage buffer，t0 space0）里的 float4 偏移：
//   记录首项是两条轴，之后是各 Pass 的 [Instance] 字段。位置与轴已在 CPU 上套用变换栈。
// - Sprite：实例记录 + 单位四边形角点（OlibInstanceInput 在前，角点在后），供常驻 Sprite_Buffer 实例化绘制。
//   实例在变换栈之前的坐标里，olib_sprite 用 b1/space1 的变换栈 2D 仿射部分换算到目标像素。
@(private)
hlsl_sprite_block :: proc(b: ^strings.Builder, mode: Instancing, slots: int) {
	if mode == .Sprite {
		hlsl_instance_block(b, .Sprite, slots)
	} else {
		hlsl_instance_varyings(b, slots)
	}
	strings.write_string(b, "struct OlibSprite {\n    float2 position;\n    float2 uv;\n    float2 axis_x;\n    float2 axis_y;\n    OlibInstance instance;\n};\n")
	if mode == .Sprite {
		strings.write_string(b, "struct OlibSpriteInput {\n    OlibInstanceInput Instance;\n    float2 Corner : TEXCOORD0;\n};\n")
		// 变换栈的 2D 仿射部分（行向量约定）：axes = (m11,m12,m21,m22)，origin.xy = (m31,m32)。
		strings.write_string(b, "cbuffer OlibSpriteView : register(b1, space1) { float4 _olib_view_axes; float4 _olib_view_origin; };\n")
		strings.write_string(b, "OlibSprite olib_sprite(OlibSpriteInput i) {\n    OlibSprite s;\n    float2 p;\n")
		strings.write_string(b, "    olib_sprite_vertex(i.Instance, i.Corner, p, s.uv);\n")
		strings.write_string(b, "    s.position = p.x * _olib_view_axes.xy + p.y * _olib_view_axes.zw + _olib_view_origin.xy;\n")
		strings.write_string(b, "    s.axis_x = i.Instance.sprite0.x * _olib_view_axes.xy + i.Instance.sprite0.y * _olib_view_axes.zw;\n")
		strings.write_string(b, "    s.axis_y = i.Instance.sprite0.z * _olib_view_axes.xy + i.Instance.sprite0.w * _olib_view_axes.zw;\n")
		strings.write_string(b, "    s.instance = olib_instance_from(i.Instance);\n    return s;\n}\n")
		return
	}
	strings.write_string(b, "struct OlibSpriteInput {\n    float2 Position : TEXCOORD0;\n    float2 Uv : TEXCOORD1;\n")
	strings.write_string(b, "    float4 Color : TEXCOORD2;\n    float4 Mode : TEXCOORD3;\n};\n")
	strings.write_string(b, "StructuredBuffer<float4> OlibInstanceValues : register(t0, space0);\n")
	strings.write_string(b, "cbuffer OlibSpritePass : register(b1, space1) { uint _olib_pass_offset; };\n")
	strings.write_string(b, "OlibSprite olib_sprite(OlibSpriteInput i) {\n    OlibSprite s;\n")
	strings.write_string(b, "    s.position = i.Position;\n    s.uv = i.Uv;\n    s.instance.tint = i.Color;\n")
	strings.write_string(b, "    uint4 bytes = (uint4)round(i.Mode * 255.0);\n")
	strings.write_string(b, "    uint offset = bytes.x | (bytes.y << 8) | (bytes.z << 16) | (bytes.w << 24);\n")
	strings.write_string(b, "    float4 axes = OlibInstanceValues[offset];\n")
	strings.write_string(b, "    s.axis_x = axes.xy;\n    s.axis_y = axes.zw;\n")
	if slots > 0 {
		strings.write_string(b, "    offset += 1 + _olib_pass_offset;\n")
		for slot in 0..<slots {
			fmt.sbprintf(b, "    s.instance.data%d = OlibInstanceValues[offset + %d];\n", slot, slot)
		}
	}
	strings.write_string(b, "    return s;\n}\n")
}
