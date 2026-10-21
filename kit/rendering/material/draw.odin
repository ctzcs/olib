package material

// 共享实现：Render2D / Render3D 记录绘制时用的绑定、Pass 选择、Pass 状态与参数打包，不是业务绘制入口。
// 因跨包复用保留这些接口；普通业务使用 material_load + r2d.image / r3d.model。
// 分区：绑定与错误 / 视图块 / Pass 状态 / Pass 选择与参数。
import foster "../../../foster"
import sh "../shader"

Material_Binding :: struct {
	schema: sh.Schema,
	values: []sh.Value,
	material: ^foster.Material,
	samplers: []foster.BoundSampler, // 按 Schema 的 Texture 字段顺序，含默认纹理。
}

// 绘制请求被拒绝的原因；.None 表示已提交（可能 0 个 Pass：全部被禁用）。
// 出错时不会发出任何 Draw，调用方可用 draw_error_text 得到可读说明。
Draw_Error :: enum {
	None,
	Missing_Device,         // 没有图形设备
	Missing_Material,       // 精灵/模型没有材质，或材质尚未成功加载
	Device_Mismatch,        // 材质属于另一个设备
	Missing_Mesh,           // 没有可绘制的网格
	Invalid_Target,         // 绘制目标尺寸无效
	Not_Material_Shader,    // 效果不是 Sprite/Model 对象材质
	Too_Many_Passes,        // 效果没有 Pass 或超过 MAX_PASSES
	Unknown_Pass,           // 指定的 Pass ID 不存在
	Wrong_Pass_Kind,        // Pass 种类与本次绘制（Sprite/Model）不符
	Missing_Binding,        // 某个 Pass 的参数组没有绑定
	Invalid_Binding,        // 绑定的 Shader、数值或贴图不完整
	Missing_Sprite_Texture, // Pass 需要当前帧贴图，但没有提供或字段不是 Texture
	Instance_Buffer_Required, // r2d/r3d.buffer 传了未创建的缓冲，或自动实例化的缓冲创建失败
	Not_Instanced_Shader,   // 用实例缓冲绘制，但效果没有声明 instanced
	Instance_Mismatch,      // 实例缓冲的字段数与效果的 [Instance] 字段数不一致
	Unsupported_Mesh,       // 网格顶点格式不是模型材质路径支持的静态格式（例如蒙皮网格）
	Missing_View_Matrix,    // 3D 视图没有设置视矩阵（view_matrix 为零矩阵）
	View_Globals_Too_Large, // 视图块超过 VIEW_GLOBALS_SIZE 字节
}

draw_error_text :: proc(error: Draw_Error) -> string {
	switch error {
	case .None: return ""
	case .Missing_Device: return "No graphics device"
	case .Missing_Material: return "Sprite or model has no loaded material"
	case .Device_Mismatch: return "Material belongs to a different graphics device"
	case .Missing_Mesh: return "No mesh to draw"
	case .Invalid_Target: return "Draw target has no pixels"
	case .Not_Material_Shader: return "Shader is not a Sprite or Model material"
	case .Too_Many_Passes: return "Shader has no passes or too many passes"
	case .Unknown_Pass: return "Unknown pass ID"
	case .Wrong_Pass_Kind: return "Pass kind does not match this draw call"
	case .Missing_Binding: return "A pass has no parameter group binding"
	case .Invalid_Binding: return "A binding has missing shaders, values or textures"
	case .Missing_Sprite_Texture: return "Pass needs a frame texture that was not provided"
	case .Instance_Buffer_Required: return "Instanced shaders must be drawn with an instance buffer"
	case .Not_Instanced_Shader: return "Shader is not instanced; it cannot use an instance buffer"
	case .Instance_Mismatch: return "Instance buffer field count differs from the shader's Instance fields"
	case .Unsupported_Mesh: return "Model materials only support the static vertex format"
	case .Missing_View_Matrix: return "3D view needs a view matrix (for example camera3d_view)"
	case .View_Globals_Too_Large: return "View globals exceed VIEW_GLOBALS_SIZE bytes"
	}
	return ""
}

// Model Pass（Olib 布局）的视图块：游戏按 std140 打包的视图级数据，库不定义其中字段。
// 顶点 b1/space1 与片元 b2/space3 是同一份字节；每次 Draw 整块提交 VIEW_GLOBALS_SIZE 字节，
// 不足部分补零，Shader 声明的块不能超过这个大小。顶点 b2/b3 预留给蒙皮 palette。
VIEW_GLOBALS_SIZE :: 1024
MODEL_VIEW_VERTEX_SLOT :: 1
MODEL_VIEW_FRAGMENT_SLOT :: 2

// 把 globals 拷进 block、余下补零；超过 VIEW_GLOBALS_SIZE 返回 false 且不改 block。
view_globals_pack :: proc(block: ^[VIEW_GLOBALS_SIZE]u8, globals: []u8) -> bool {
	if len(globals) > VIEW_GLOBALS_SIZE do return false
	block^ = {}
	copy(block[:], globals)
	return true
}

pass_state_apply :: proc(command: ^foster.DrawCommand, state: sh.Pass_State) {
	switch state.cull {
	case .Default:
	case .None:
		command.CullMode = .None
	case .Front:
		command.CullMode = .Front
	case .Back:
		command.CullMode = .Back
	}
	switch state.blend {
	case .Default:
	case .Opaque:
		command.BlendMode = foster.BlendModeDisabled
	case .Alpha:
		command.BlendMode = foster.BlendModeNonPremultiplied
	case .Premultiplied:
		command.BlendMode = foster.BlendModePremultiply
	case .Additive:
		command.BlendMode = foster.BlendModeMake(.Add, .One, .One)
	}
	switch state.depth {
	case .Default:
	case .Off:
		command.DepthTestEnabled = false
	case .Less:
		command.DepthTestEnabled, command.DepthCompare = true, .Less
	case .Less_Equal:
		command.DepthTestEnabled, command.DepthCompare = true, .LessOrEqual
	case .Equal:
		command.DepthTestEnabled, command.DepthCompare = true, .Equal
	case .Always:
		command.DepthTestEnabled, command.DepthCompare = true, .Always
	case .Greater:
		command.DepthTestEnabled, command.DepthCompare = true, .Greater
	case .Greater_Equal:
		command.DepthTestEnabled, command.DepthCompare = true, .GreatorOrEqual
	case .Not_Equal:
		command.DepthTestEnabled, command.DepthCompare = true, .NotEqual
	case .Never:
		command.DepthTestEnabled, command.DepthCompare = true, .Never
	}
	if state.depth_write != .Default do command.DepthWriteEnabled = state.depth_write == .On
}

// 按声明顺序列出要画的 Pass：pass_id 为空选全部，非空只选该 Pass；声明为 disabled 的 Pass 都不画。
@(private)
material_pass_indices :: proc(shader: sh.Shader_Desc, pass_id: Pass_Id,
	indices: ^[sh.MAX_PASSES]int) -> (count: int, error: Draw_Error) {
	if len(shader.passes) == 0 || len(shader.passes) > len(indices) do return 0, .Too_Many_Passes
	found := pass_id == ""
	for p, i in shader.passes {
		if pass_id != "" && p.id != pass_id do continue
		found = true
		if p.disabled do continue
		indices[count] = i
		count += 1
	}
	if !found do return 0, .Unknown_Pass
	return count, .None
}

// 找到 Pass 参数组对应的绑定并检查其可用于提交；多个同名绑定时取最后一个。
@(private)
material_binding_find :: proc(p: sh.Pass_Desc, kind: sh.Pass_Draw, sprite_texture: ^foster.Texture,
	bindings: []Material_Binding) -> (index: int, error: Draw_Error) {
	index = -1
	for b, j in bindings {
		if b.schema.name != string(p.params) do continue
		if b.material == nil || len(b.values) != len(b.schema.fields) ||
			len(b.samplers) != sh.texture_count(b.schema) || len(b.samplers) > sh.MAX_TEXTURES {
			return -1, .Invalid_Binding
		}
		if b.material.Vertex.Shader == nil || b.material.Fragment.Shader == nil ||
			b.material.Vertex.Shader.Resource == nil || b.material.Fragment.Shader.Resource == nil {
			return -1, .Invalid_Binding
		}
		for sampler in b.samplers {
			if sampler.Texture == nil || sampler.Texture.Resource == nil do return -1, .Invalid_Binding
		}
		index = j
	}
	if index < 0 do return -1, .Missing_Binding
	if p.sprite_texture != "" {
		if kind != .Sprite || sprite_texture == nil || sprite_texture.Resource == nil {
			return -1, .Missing_Sprite_Texture
		}
		schema := bindings[index].schema
		field := sh.field_index(schema, string(p.sprite_texture))
		if field < 0 || schema.fields[field].kind != .Texture do return -1, .Missing_Sprite_Texture
	}
	return index, .None
}

// 一个 Pass 本次绘制的参数：参数 uniform（按 uniform_size 打包，借用 temp_allocator）与 [Instance] 字段数值。
// 不分配内存的实例值解析，供批量记录模型逐实例使用；与 material_pass_values 的覆盖顺序相同。
material_pass_instance :: proc(p: sh.Pass_Desc, b: Material_Binding,
	overrides: ^Instance_Values) -> (instance: Instance_Values) {
	for field, i in b.schema.fields {
		if !field.instance || instance.count >= sh.MAX_INSTANCE_FIELDS do continue
		value := b.values[i]
		if overrides != nil && overrides.set & (1 << u32(instance.count)) != 0 {
			value_assign(field, &value, overrides.numbers[instance.count])
		}
		for fixed in p.values do if string(fixed.field) == field.id do value.number = fixed.number
		instance.numbers[instance.count] = value.number
		instance.count += 1
	}
	return
}

// 参数 uniform 借用 temp_allocator，实例值按值返回。
// 套用顺序：材质实例值 < overrides（instance_values）< Pass 的固定 values。
material_pass_values :: proc(p: sh.Pass_Desc, b: Material_Binding, overrides: ^Instance_Values) -> (uniform: []u8, instance: Instance_Values) {
	values := make([]sh.Value, len(b.values), context.temp_allocator)
	copy(values, b.values)
	instance_values_apply(overrides, b.schema, values)
	for value in p.values {
		j := sh.field_index(b.schema, string(value.field))
		if j >= 0 do values[j].number = value.number
	}
	uniform = make([]u8, sh.uniform_size(b.schema), context.temp_allocator)
	_ = sh.pack(b.schema, values, uniform)
	for f, i in b.schema.fields {
		if !f.instance || instance.count >= sh.MAX_INSTANCE_FIELDS do continue
		instance.numbers[instance.count] = values[i].number
		instance.count += 1
	}
	return
}

// 本次绘制要画的 Pass（按声明顺序）及各自的绑定下标。
Pass_Selection :: struct {
	count: int,
	passes, bindings: [sh.MAX_PASSES]int,
}

// 解析选择并检查 Pass 种类与绑定，不提交、不改动绑定；渲染器记录绘制时用它提前得到错误。
// kind 是本次绘制的种类（Sprite / Model），sprite_texture 是精灵的当前帧（Model 传 nil）。
material_select :: proc(shader: sh.Shader_Desc, bindings: []Material_Binding, kind: sh.Pass_Draw, pass_id: Pass_Id,
	sprite_texture: ^foster.Texture, selection: ^Pass_Selection) -> Draw_Error {
	selection^ = {}
	selected: [sh.MAX_PASSES]int
	count, error := material_pass_indices(shader, pass_id, &selected)
	if error != .None do return error
	for i in selected[:count] {
		if shader.passes[i].draw != kind do return .Wrong_Pass_Kind
		bound: int
		bound, error = material_binding_find(shader.passes[i], kind, sprite_texture, bindings)
		if error != .None do return error
		selection.passes[selection.count] = i
		selection.bindings[selection.count] = bound
		selection.count += 1
	}
	return .None
}
