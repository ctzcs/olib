package material

// 共享实现：供精灵、模型及 ShaderLab 集成，不是业务绘制入口。
// 因跨包复用保留这些接口；普通业务使用 material_load + r2d.image / r3d.model。
// 分区：绑定与绘制输入 / Pass 状态 / 对象多 Pass 执行。
import foster "../../../foster"

Material_Binding :: struct {
	schema: Schema,
	values: []Value,
	material: ^foster.Material,
	samplers: []foster.BoundSampler, // 按 Schema 的 Texture 字段顺序，含默认纹理。
}

// 选择、单次覆盖与工具扩展：2D、3D 的绘制请求都内嵌同一份，字段含义只在这里说明一次。
// 业务代码会用到 pass_id 和 instance_values；其余供 ShaderLab 预览和合批使用。
Draw_Options :: struct {
	// 本次绘制这个实例的 [Instance] 字段数值（按槽位，见 instance_slot）：只覆盖被显式设置的槽位，
	// 其余沿用材质里保存的值；不修改共享材质，取值不同的实例仍可合批。缓冲绘制时数据来自缓冲，忽略它。
	instance_values: ^Instance_Values,
	// 优先级：材质实例值 < instance_values < Pass 的固定 values。
	// 可选预览覆盖：enabled 空值使用声明的 disabled；非空须覆盖全部 Pass。
	enabled: []bool,
	// 空值绘制全部；非空按稳定 Pass ID 选择，未知 ID 返回 false，不提交绘制。
	pass_id: Pass_Id,
	// 工具回调：prepare 在应用 Pass 状态前改 DrawCommand，submit 取代直接提交。
	// instance 为该 Pass 的 per-instance 数值（始终非 nil），回调期间有效。
	user_data: rawptr,
	prepare: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand, instance: ^Instance_Values),
	submit: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand, instance: ^Instance_Values),
}

// 带回调时调用方不能假设 DrawCommand 状态可预测，渲染器应把它当作合批边界。
draw_has_hooks :: proc(options: Draw_Options) -> bool {
	return options.prepare != nil || options.submit != nil
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
	Not_Material_Effect,    // 效果不是 Sprite/Model 对象材质
	Too_Many_Passes,        // 效果没有 Pass 或超过 MAX_PASSES
	Bad_Pass_Selection,     // Draw_Options.enabled 比 Pass 数少
	Unknown_Pass,           // 指定的 Pass ID 不存在
	Wrong_Pass_Kind,        // Pass 种类与本次绘制（Sprite/Model）不符
	Missing_Binding,        // 某个 Pass 的参数组没有绑定
	Invalid_Binding,        // 绑定的 Shader、数值或贴图不完整
	Missing_Sprite_Texture, // Pass 需要当前帧贴图，但没有提供或字段不是 Texture
	Instance_Buffer_Required, // 工具立即绘制缺实例缓冲，或 r2d/r3d.buffer 传了未创建的缓冲
	Not_Instanced_Effect,   // 用实例缓冲绘制，但效果没有声明 instanced
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
	case .Not_Material_Effect: return "Effect is not a Sprite or Model material"
	case .Too_Many_Passes: return "Effect has no passes or too many passes"
	case .Bad_Pass_Selection: return "Enabled list is shorter than the pass list"
	case .Unknown_Pass: return "Unknown pass ID"
	case .Wrong_Pass_Kind: return "Pass kind does not match this draw call"
	case .Missing_Binding: return "A pass has no parameter group binding"
	case .Invalid_Binding: return "A binding has missing shaders, values or textures"
	case .Missing_Sprite_Texture: return "Pass needs a frame texture that was not provided"
	case .Instance_Buffer_Required: return "Instanced effects must be drawn with an instance buffer"
	case .Not_Instanced_Effect: return "Effect is not instanced; it cannot use an instance buffer"
	case .Instance_Mismatch: return "Instance buffer field count differs from the effect's Instance fields"
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

Material_Draw :: struct {
	mesh: ^foster.Mesh,
	target: foster.DrawableTarget,
	kind: Pass_Draw,
	vertex_uniform: []u8,
	frame_uniform: []u8,
	view_globals: []u8, // Model Pass 的视图块，nil 为全零；见 VIEW_GLOBALS_SIZE
	sprite_texture: ^foster.Texture,
	pass_limit: int, // 0 绘制全部，否则只绘制前 N 个 Pass。
	options: Draw_Options,
	// instanced 绘制：每实例顶点缓冲（按实例步进）与实例数；buffer 为 nil 表示单个对象。
	instance_buffer: ^foster.VertexBuffer,
	instance_count: int,
	instance_slots: int, // 缓冲里的 [Instance] 字段数，须等于效果的字段数
	// 实例属性占用的顶点属性位置数（实例缓冲 0..n-1，网格属性整体后移 n）。
	// HLSL 里 OlibInstanceInput 须是 Input 的第一个成员：这样实例属性位置稠密且全被使用，
	// 不受网格里未使用属性被编译器删除（D3D12 语义号按存活属性重新编号）的影响。
	mesh_location_offset: int,
}

pass_state_apply :: proc(command: ^foster.DrawCommand, state: Pass_State) {
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
	case .Less, .Less_Equal, .Equal, .Always:
		command.DepthTestEnabled = true
		#partial switch state.depth {
		case .Less:
			command.DepthCompare = .Less
		case .Less_Equal:
			command.DepthCompare = .LessOrEqual
		case .Equal:
			command.DepthCompare = .Equal
		case .Always:
			command.DepthCompare = .Always
		case:
		}
	}
	if state.depth_write != .Default do command.DepthWriteEnabled = state.depth_write == .On
}

// 先解析完整选择，再提交；显式选择也遵守 disabled/enabled 和 pass_limit。
@(private)
material_pass_indices :: proc(effect: Effect_Desc, draw: Material_Draw,
	indices: ^[MAX_PASSES]int) -> (count: int, error: Draw_Error) {
	if len(effect.passes) == 0 || len(effect.passes) > len(indices) do return 0, .Too_Many_Passes
	options := draw.options
	if len(options.enabled) != 0 && len(options.enabled) < len(effect.passes) do return 0, .Bad_Pass_Selection
	found := options.pass_id == ""
	for p, i in effect.passes {
		if options.pass_id != "" && p.id != options.pass_id do continue
		found = true
		if draw.pass_limit > 0 && i >= draw.pass_limit do continue
		if len(options.enabled) > 0 ? !options.enabled[i] : p.disabled do continue
		indices[count] = i
		count += 1
	}
	if !found do return 0, .Unknown_Pass
	return count, .None
}

// 找到 Pass 参数组对应的绑定并检查其可用于提交；多个同名绑定时取最后一个。
@(private)
material_binding_find :: proc(p: Pass_Desc, draw: Material_Draw, bindings: []Material_Binding) -> (index: int, error: Draw_Error) {
	index = -1
	for b, j in bindings {
		if b.schema.name != string(p.params) do continue
		if b.material == nil || len(b.values) != len(b.schema.fields) ||
			len(b.samplers) != texture_count(b.schema) || len(b.samplers) > MAX_TEXTURES {
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
		if draw.kind != .Sprite || draw.sprite_texture == nil || draw.sprite_texture.Resource == nil {
			return -1, .Missing_Sprite_Texture
		}
		schema := bindings[index].schema
		field := field_index(schema, string(p.sprite_texture))
		if field < 0 || schema.fields[field].kind != .Texture do return -1, .Missing_Sprite_Texture
	}
	return index, .None
}

// 一个 Pass 本次绘制的参数：参数 uniform（按 uniform_size 打包，借用 temp_allocator）与 [Instance] 字段数值。
// 不分配内存的实例值解析，供批量记录模型逐实例使用；与 material_pass_values 的覆盖顺序相同。
material_pass_instance :: proc(p: Pass_Desc, b: Material_Binding,
	overrides: ^Instance_Values) -> (instance: Instance_Values) {
	for field, i in b.schema.fields {
		if !field.instance || instance.count >= MAX_INSTANCE_FIELDS do continue
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
material_pass_values :: proc(p: Pass_Desc, b: Material_Binding, overrides: ^Instance_Values) -> (uniform: []u8, instance: Instance_Values) {
	values := make([]Value, len(b.values), context.temp_allocator)
	copy(values, b.values)
	instance_values_apply(overrides, b.schema, values)
	for value in p.values {
		j := field_index(b.schema, string(value.field))
		if j >= 0 do values[j].number = value.number
	}
	uniform = make([]u8, uniform_size(b.schema), context.temp_allocator)
	_ = pack(b.schema, values, uniform)
	for f, i in b.schema.fields {
		if !f.instance || instance.count >= MAX_INSTANCE_FIELDS do continue
		instance.numbers[instance.count] = values[i].number
		instance.count += 1
	}
	return
}

// 提交单个 Pass：应用固定覆盖值、写入 uniform 与采样器、套用 Pass 状态后绘制。
@(private)
material_pass_submit :: proc(device: ^foster.GraphicsDevice, draw: Material_Draw, layout: Uniform_Layout,
	p: Pass_Desc, pass_index: int, b: Material_Binding, globals: []u8) {
	buffer, instance := material_pass_values(p, b, draw.options.instance_values)
	foster.MaterialStageSetUniformBuffer(&b.material.Vertex, draw.vertex_uniform)
	if layout == .Foster {
		// 借用 foster 默认 Shader 的内置效果：片元 b0 直接是参数，没有帧块。
		foster.MaterialStageSetUniformBuffer(&b.material.Fragment, buffer)
	} else {
		foster.MaterialStageSetUniformBuffer(&b.material.Fragment, draw.frame_uniform)
		foster.MaterialStageSetUniformBuffer(&b.material.Fragment, buffer, 1)
		if p.draw == .Model {
			foster.MaterialStageSetUniformBuffer(&b.material.Vertex, globals, MODEL_VIEW_VERTEX_SLOT)
			foster.MaterialStageSetUniformBuffer(&b.material.Fragment, globals, MODEL_VIEW_FRAGMENT_SLOT)
		}
	}
	b.material.Fragment.Samplers = {}
	copy(b.material.Fragment.Samplers[:], b.samplers)
	if p.sprite_texture != "" {
		slot := 0
		for field in b.schema.fields {
			if field.kind != .Texture do continue
			if field.id == string(p.sprite_texture) {
				b.material.Fragment.Samplers[slot].Texture = draw.sprite_texture
			}
			slot += 1
		}
	}
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, draw.target, draw.mesh, b.material)
	// 网格属性后移时用浅拷贝换格式：共享 GPU 资源，不改动网格自己的格式。
	shifted: foster.VertexBuffer
	if draw.instance_buffer != nil {
		if draw.mesh_location_offset > 0 {
			shifted = draw.mesh.VertexData
			shifted.Format = foster.VertexFormatClone(draw.mesh.VertexData.Format)
			for &element in shifted.Format.Elements do element.Index += draw.mesh_location_offset
			command.VertexBuffers[0].Buffer = &shifted
		}
		append(&command.VertexBuffers, foster.VertexBufferBinding{Buffer = draw.instance_buffer, InstanceInputRate = true})
		command.InstanceCount = draw.instance_count
	}
	defer if draw.mesh_location_offset > 0 && draw.instance_buffer != nil do foster.VertexFormatDispose(&shifted.Format)
	command.DepthTestEnabled = draw.kind == .Model
	command.DepthWriteEnabled = draw.kind == .Model
	command.CullMode = draw.kind == .Model ? .Back : .None
	command.BlendMode = draw.kind == .Model ? foster.BlendModeDisabled : foster.BlendModePremultiply
	if draw.options.prepare != nil do draw.options.prepare(draw.options.user_data, pass_index, &command, &instance)
	pass_state_apply(&command, p.state)
	if draw.options.submit != nil {
		draw.options.submit(draw.options.user_data, pass_index, &command, &instance)
	} else {
		foster.GraphicsDeviceDraw(device, &command)
	}
	foster.DrawCommandDispose(&command)
}

// 调用方先通过 effect_order / instance_make 验证定义。绑定完整性仍在提交首个 Pass 前检查。
// 返回非 .None 时不发出任何 Draw；每次 draw 重新绑定，多个实例可以共享 GPU Material。
material_draw :: proc(device: ^foster.GraphicsDevice, effect: Effect_Desc,
	bindings: []Material_Binding, draw: Material_Draw) -> Draw_Error {
	if device == nil do return .Missing_Device
	if draw.mesh == nil do return .Missing_Mesh
	if !effect_is_material(effect) do return .Not_Material_Effect
	// 模型的 instanced 效果只有实例缓冲一种接口；精灵的批量变体可以逐个绘制。
	if effect.instanced && draw.kind == .Model && draw.instance_buffer == nil do return .Instance_Buffer_Required
	if draw.instance_buffer != nil {
		if !effect.instanced do return .Not_Instanced_Effect
		for binding in bindings {
			if instance_count(binding.schema) != draw.instance_slots do return .Instance_Mismatch
		}
	}
	globals: [VIEW_GLOBALS_SIZE]u8
	if !view_globals_pack(&globals, draw.view_globals) do return .View_Globals_Too_Large
	selection: Pass_Selection
	if error := material_select(effect, bindings, draw, &selection); error != .None do return error
	if draw.instance_buffer != nil && draw.instance_count <= 0 do return .None
	for i in 0..<selection.count {
		pass := selection.passes[i]
		material_pass_submit(device, draw, effect.uniforms, effect.passes[pass], pass,
			bindings[selection.bindings[i]], globals[:])
	}
	return .None
}

// 本次绘制要画的 Pass（按声明顺序）及各自的绑定下标。
Pass_Selection :: struct {
	count: int,
	passes, bindings: [MAX_PASSES]int,
}

// 解析选择并检查 Pass 种类与绑定，不提交、不改动绑定；渲染器记录绘制时用它提前得到错误。
// draw 只读取 kind、sprite_texture、pass_limit 与 options。
material_select :: proc(effect: Effect_Desc, bindings: []Material_Binding, draw: Material_Draw,
	selection: ^Pass_Selection) -> Draw_Error {
	selection^ = {}
	selected: [MAX_PASSES]int
	count, error := material_pass_indices(effect, draw, &selected)
	if error != .None do return error
	for i in selected[:count] {
		if effect.passes[i].draw != draw.kind do return .Wrong_Pass_Kind
		bound: int
		bound, error = material_binding_find(effect.passes[i], draw, bindings)
		if error != .None do return error
		selection.passes[selection.count] = i
		selection.bindings[selection.count] = bound
		selection.count += 1
	}
	return .None
}
