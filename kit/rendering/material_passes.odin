package rendering

// 共享实现：供精灵、模型及 ShaderLab 集成，不是业务绘制入口。
// 因跨包复用保留这些接口；普通业务使用 material_load + sprite_draw / model_draw。
// 分区：绑定 / 绘制输入 / Pass 状态 / 对象多 Pass 执行。
import foster "olib:foster"
import mat "olib:kit/material"

Material_Binding :: struct {
	schema: mat.Schema,
	values: []mat.Value,
	material: ^foster.Material,
	samplers: []foster.BoundSampler, // 按 Schema 的 Texture 字段顺序，含默认纹理。
}
Material_Draw :: struct {
	mesh: ^foster.Mesh,
	target: foster.DrawableTarget,
	kind: mat.Pass_Draw,
	vertex_uniform: []u8,
	frame_uniform: []u8,
	sprite_texture: ^foster.Texture,
	// 可选预览覆盖：enabled 空值使用声明；pass_limit=0 绘制全部。
	enabled: []bool,
	pass_limit: int,
	// 空值绘制全部；非空按稳定 Pass ID 选择，未知 ID 返回 false，不提交绘制。
	pass_id: mat.Pass_Id,
	user_data: rawptr,
	prepare: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
	submit: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
}

pass_state_apply :: proc(command: ^foster.DrawCommand, state: mat.Pass_State) {
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
material_pass_indices :: proc(effect: mat.Effect_Desc, draw: Material_Draw,
	indices: ^[32]int) -> (count: int, ok: bool) {
	if len(effect.passes) == 0 || len(effect.passes) > len(indices) do return 0, false
	if len(draw.enabled) != 0 && len(draw.enabled) < len(effect.passes) do return 0, false
	found := draw.pass_id == ""
	for p, i in effect.passes {
		if draw.pass_id != "" && p.id != draw.pass_id do continue
		found = true
		if draw.pass_limit > 0 && i >= draw.pass_limit do continue
		if len(draw.enabled) > 0 ? !draw.enabled[i] : p.disabled do continue
		indices[count] = i
		count += 1
	}
	return count, found
}

// 调用方先通过 effect_order / instance_make 验证定义。绑定完整性仍在提交首个 Pass 前检查。
// 返回 false 时不发出任何 Draw；每次 draw 重新绑定，多个实例可以共享 GPU Material。
material_draw :: proc(device: ^foster.GraphicsDevice, effect: mat.Effect_Desc,
	bindings: []Material_Binding, draw: Material_Draw) -> bool {
	if device == nil || draw.mesh == nil || !mat.effect_is_material(effect) || len(effect.passes) > 32 do return false
	selected: [32]int
	count, ok := material_pass_indices(effect, draw, &selected)
	if !ok do return false
	indices: [32]int
	for i in selected[:count] {
		p := effect.passes[i]
		if p.draw != draw.kind do return false
		indices[i] = -1
		for b, j in bindings {
			if b.schema.name != string(p.params) do continue
			if b.material == nil || len(b.values) != len(b.schema.fields) ||
				len(b.samplers) != mat.texture_count(b.schema) || len(b.samplers) > 16 {
				return false
			}
			if b.material.Vertex.Shader == nil || b.material.Fragment.Shader == nil do return false
			if b.material.Vertex.Shader.Resource == nil || b.material.Fragment.Shader.Resource == nil do return false
			for sampler in b.samplers {
				if sampler.Texture == nil || sampler.Texture.Resource == nil do return false
			}
			indices[i] = j
		}
		if indices[i] < 0 do return false
		if p.sprite_texture != "" {
			if draw.kind != .Sprite || draw.sprite_texture == nil || draw.sprite_texture.Resource == nil do return false
			field := mat.field_index(bindings[indices[i]].schema, string(p.sprite_texture))
			if field < 0 || bindings[indices[i]].schema.fields[field].kind != .Texture do return false
		}
	}
	for i in selected[:count] {
		p := effect.passes[i]
		b := bindings[indices[i]]
		values := make([]mat.Value, len(b.values), context.temp_allocator)
		copy(values, b.values)
		for value in p.values {
			j := mat.field_index(b.schema, string(value.field))
			if j >= 0 do values[j].number = value.number
		}
		buffer := make([]u8, mat.uniform_size(b.schema), context.temp_allocator)
		_ = mat.pack(b.schema, values, buffer)
		foster.MaterialStageSetUniformBuffer(&b.material.Vertex, draw.vertex_uniform)
		foster.MaterialStageSetUniformBuffer(&b.material.Fragment, draw.frame_uniform)
		foster.MaterialStageSetUniformBuffer(&b.material.Fragment, buffer, 1)
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
		command.DepthTestEnabled = draw.kind == .Model
		command.DepthWriteEnabled = draw.kind == .Model
		command.CullMode = draw.kind == .Model ? .Back : .None
		command.BlendMode = draw.kind == .Model ? foster.BlendModeDisabled : foster.BlendModePremultiply
		if draw.prepare != nil do draw.prepare(draw.user_data, i, &command)
		pass_state_apply(&command, p.state)
		if draw.submit != nil {
			draw.submit(draw.user_data, i, &command)
		} else {
			foster.GraphicsDeviceDraw(device, &command)
		}
		foster.DrawCommandDispose(&command)
	}
	return true
}
