package shader_lab

// 材质预览：2D/3D 对象与游戏共用绘制实现；本文件负责预览接入和材质存取。
import "core:fmt"
import "core:math"
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"
import sh "olib:kit/rendering/shader"
import world "olib:kit/world"

// 材质效果的预览：借用 bank 的 GPU 绑定组成材质，用 Render2D / Render3D 记录后提交到预览目标，
// 渲染状态与游戏一致。Pass 启停与“只预览到第 N 个 Pass”在这里逐 Pass 处理。
material_shader_render :: proc(s: ^Session, e: ^Shader_Runtime) -> ^foster.Texture {
	target := &e.targets[0].buffers[0]
	target_clear(s, target, e.desc.passes[0].target.clear)
	// 每帧组装：编辑或载入参数时，数值切片会被替换。绑定按 Pass 首次引用参数组的顺序排列。
	groups := make([dynamic]int, context.temp_allocator)
	for pass in e.desc.passes {
		index := bank_index(s.bank, string(pass.params))
		known := index < 0
		for g in groups do known = known || g == index
		if !known do append(&groups, index)
	}
	schemas := make([]sh.Schema, len(groups), context.temp_allocator)
	bindings := make([]mat.Material_Binding, len(groups), context.temp_allocator)
	for index, i in groups {
		p := &s.parameters[index]
		samplers := make([]foster.BoundSampler, sh.texture_count(p.live), context.temp_allocator)
		j := 0
		for field in p.live.fields {
			if field.kind != .Texture do continue
			samplers[j] = {p.textures[j].Resource != nil ? &p.textures[j] : &s.texture, sh.field_sampler(field)}
			j += 1
		}
		schemas[i] = p.live
		bindings[i] = {p.live, p.values, &s.materials[index], samplers}
	}
	shader := mat.Material_Shader{desc = e.desc, schemas = schemas}
	material, reason := mat.material_from_bindings(&s.library, &shader, bindings)
	if reason != "" {
		bank_error(s, fmt.tprintf("Cannot bind material: %s", reason))
		return foster.TargetAttachment(target)
	}
	drawable := foster.DrawableTargetFromTarget(target)
	pointer := [2]f32{(s.pointer.x-s.viewport.X)/s.viewport.Width, (s.pointer.y-s.viewport.Y)/s.viewport.Height}
	limit := s.preview_pass >= 0 ? min(s.preview_pass+1, len(e.desc.passes)) : len(e.desc.passes)
	sprite := sh.shader_is_sprite(e.desc)
	custom := s.custom_preview && s.preview_hooks.record != nil
	frame := Preview_Frame{dimension = sprite ? "2d" : "3d", time = e.time, delta_time = e.last_delta,
		frame_index = e.frame, width = target.Width, height = target.Height}
	draw_error: mat.Draw_Error
	if sprite {
		texture := preview_sprite_texture(s, e)
		size := f32(min(target.Width, target.Height))*0.7
		scale := size/f32(max(texture.Width, texture.Height))
		view := r2d.View{target = drawable, time = e.time, delta_time = e.last_delta, frame = e.frame, pointer = pointer}
		for pass, i in e.desc.passes[:limit] {
			if !e.enabled[i] do continue
			frame.pass, frame.group = string(pass.id), string(pass.params)
			if !custom || !s.preview_hooks.record(s.preview_hooks.user_data, frame, &material, &s.preview_sprites, nil) {
				draw_error = r2d.image(&s.preview_sprites, foster.SubtextureFromTexture(texture),
					{scale, 0, 0, scale, f32(target.Width)/2, f32(target.Height)/2},
					origin = {f32(texture.Width)/2, f32(texture.Height)/2}, material = &material, pass_id = pass.id)
			}
			if draw_error == .None do draw_error = r2d.submit(&s.preview_sprites, view)
			if draw_error != .None do break
		}
	} else {
		world.camera3d_set_viewport(&s.camera, target.Width, target.Height)
		world.camera3d_set_position(&s.camera, {math.sin(s.yaw)*math.cos(s.pitch)*s.distance,
			math.sin(s.pitch)*s.distance, math.cos(s.yaw)*math.cos(s.pitch)*s.distance})
		view := r3d.View{target = drawable, view_projection = world.camera3d_view_projection(&s.camera),
			view_matrix = world.camera3d_view(&s.camera), draw_debug = false,
			time = e.time, delta_time = e.last_delta, frame = e.frame}
		for pass, i in e.desc.passes[:limit] {
			if !e.enabled[i] do continue
			r3d.clear(&s.preview_models)
			frame.pass, frame.group = string(pass.id), string(pass.params)
			if !custom || !s.preview_hooks.record(s.preview_hooks.user_data, frame, &material, nil, &s.preview_models) {
				draw_error = r3d.model(&s.preview_models, &s.meshes[s.mode == 3 ? 2 : 1], &material, world.MATRIX4_IDENTITY)
			}
			if draw_error == .None do draw_error = r3d.submit(&s.preview_models, view, pass.id)
			if draw_error != .None do break
		}
		r3d.clear(&s.preview_models) // 记录借用本帧组装的材质，不留到下一帧
	}
	if draw_error != .None {
		bank_error(s, fmt.tprintf("Cannot draw %s material: %s", sprite ? "sprite" : "model", mat.draw_error_text(draw_error)))
	}
	return foster.TargetAttachment(target)
}

// 被检查 Pass 的帧字段可选预览图片；业务运行时该字段由 Sprite 当前帧覆盖。
@(private = "file")
preview_sprite_texture :: proc(s: ^Session, e: ^Shader_Runtime) -> ^foster.Texture {
	texture := &s.sprite_texture
	for pass, i in e.desc.passes {
		if i != s.inspect_pass || pass.sprite_texture == "" do continue
		parameter := &s.parameters[bank_index(s.bank, string(pass.params))]
		slot := 0
		for field in parameter.live.fields {
			if field.kind != .Texture do continue
			if field.id == string(pass.sprite_texture) && parameter.textures[slot].Resource != nil {
				texture = &parameter.textures[slot]
			}
			slot += 1
		}
	}
	return texture
}


// 保存整个对象效果的参数；临时借用组和数值，文件保存函数内部复制路径。
save_material :: proc(s: ^Session, shader: int, path: string) -> bool {
	if shader < 0 || shader >= len(s.shaders) || !sh.shader_is_material(s.shaders[shader].desc) do return false
	color_picker_close(s, true)
	e := s.shaders[shader].desc
	groups := make([dynamic]sh.Instance_Group, context.temp_allocator)
	for pass in e.passes {
		found := false
		for group in groups do found = found || group.schema.name == string(pass.params)
		if found do continue
		p := &s.parameters[bank_index(s.bank, string(pass.params))]
		append(&groups, sh.Instance_Group{p.live, p.values})
	}
	reason := material_file_save({e.name, groups[:]}, path, s.source_root)
	parameter_error(&s.parameters[bank_index(s.bank, string(e.passes[0].params))], reason)
	return reason == ""
}

// 所有参数和贴图准备完成再提交；任一组失败都保留整个旧材质。
load_material :: proc(s: ^Session, shader: int, path: string) -> bool {
	if shader < 0 || shader >= len(s.shaders) do return false
	e := s.shaders[shader].desc
	schemas := make([]sh.Schema, s.program_count, context.temp_allocator)
	for p, i in s.parameters[:s.program_count] do schemas[i] = p.live
	next, reason := material_file_load(e, schemas, path)
	defer sh.instance_dispose(&next)
	reporter := &s.parameters[bank_index(s.bank, string(e.passes[0].params))]
	if reason != "" {
		parameter_error(reporter, reason)
		return false
	}
	textures := make([][sh.MAX_TEXTURES]foster.Texture, len(next.groups), context.temp_allocator)
	defer for &group in textures do for &texture in group do foster.TextureDispose(&texture)
	for group, i in next.groups {
		slot := 0
		for f, j in group.schema.fields {
			if f.kind != .Texture do continue
			ok: bool
			textures[i][slot], ok = load_parameter_texture(s, s.device, group.values[j].texture)
			if !ok {
				parameter_error(reporter, "Cannot load material texture; previous material retained")
				return false
			}
			slot += 1
		}
	}
	cancel(s)
	color_picker_close(s, false)
	for &group, i in next.groups {
		p := &s.parameters[bank_index(s.bank, group.schema.name)]
		sh.values_dispose(p.values)
		p.values, group.values = group.values, nil
		for &texture, j in p.textures {
			parameter_texture_replace(s, &texture, textures[i][j])
			textures[i][j] = {}
		}
		texture_stamps_reset(s, p)
		parameter_error(p, "")
	}
	return true
}
