package shader_lab

// 材质预览：2D/3D 对象与游戏共用绘制实现；本文件负责预览接入和材质存取。
import "core:fmt"
import "core:math"
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

Material_Preview :: struct { session: ^Session, effect: ^Effect_Runtime }

material_preview_prepare :: proc(data: rawptr, pass: int, command: ^foster.DrawCommand, _: ^mat.Instance_Values) {
	host := cast(^Material_Preview)data
	s, e := host.session, host.effect
	p := e.desc.passes[pass]
	foster.DrawCommandDispose(command)
	command^ = pass_command(s, s.bank, bank_index(s.bank, string(p.params)), p.draw,
		foster.DrawableTargetFromTarget(&e.targets[0].buffers[0]), string(p.id), e.time, e.last_delta, e.frame)
}

material_preview_submit :: proc(data: rawptr, pass: int, command: ^foster.DrawCommand, _: ^mat.Instance_Values) {
	host := cast(^Material_Preview)data
	s, e := host.session, host.effect
	if s.custom_preview && s.preview_hooks.draw != nil {
		p := e.desc.passes[pass]
		frame := preview_frame(s, bank_index(s.bank, string(p.params)), mat.effect_is_sprite(e.desc) ? "2d" : "3d", foster.DrawableTargetFromTarget(&e.targets[0].buffers[0]))
		frame.pass, frame.time, frame.delta_time, frame.frame_index = string(p.id), e.time, e.last_delta, e.frame
		s.preview_hooks.draw(s.preview_hooks.user_data, frame, command)
	} else {
		foster.GraphicsDeviceDraw(s.device, command)
	}
}

material_effect_render :: proc(s: ^Session, e: ^Effect_Runtime) -> ^foster.Texture {
	target := &e.targets[0].buffers[0]
	target_clear(s, target, e.desc.passes[0].target.clear)
	bindings := make([]mat.Material_Binding, s.shader_count, context.temp_allocator)
	for &p, i in s.parameters[:s.shader_count] {
		samplers := make([]foster.BoundSampler, mat.texture_count(p.live), context.temp_allocator)
		for &sampler, j in samplers {
			sampler = {p.textures[j].Resource != nil ? &p.textures[j] : &s.texture, foster.TextureSamplerMake(.Linear, .Clamp)}
		}
		bindings[i] = {p.live, p.values, &s.materials[i], samplers}
	}
	host := Material_Preview{s, e}
	if mat.effect_is_sprite(e.desc) {
		texture := &s.sprite_texture
		// 被检查 Pass 的帧字段可选预览图片；业务运行时该字段由 Sprite 当前帧覆盖。
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
		size := f32(min(target.Width, target.Height))*0.7
		scale := size/f32(max(texture.Width, texture.Height))
		draw_error := r2d.material_draw(&s.render, e.desc, bindings, {
			frame = foster.SubtextureFromTexture(texture),
			origin = {f32(texture.Width)/2, f32(texture.Height)/2},
			transform = {scale, 0, 0, scale, f32(target.Width)/2, f32(target.Height)/2},
			view = {target = foster.DrawableTargetFromTarget(target), time = e.time,
				delta_time = e.last_delta, frame = e.frame,
				pointer = {(s.pointer.x-s.viewport.X)/s.viewport.Width, (s.pointer.y-s.viewport.Y)/s.viewport.Height}},
			color = foster.White, pass_limit = s.preview_pass+1,
			options = {enabled = e.enabled[:len(e.desc.passes)],
				user_data = &host, prepare = material_preview_prepare, submit = material_preview_submit},
		})
		if draw_error != .None do bank_error(s, fmt.tprintf("Cannot bind sprite material: %s", mat.draw_error_text(draw_error)))
		return foster.TargetAttachment(target)
	}
	world.camera3d_set_viewport(&s.camera, target.Width, target.Height)
	world.camera3d_set_position(&s.camera, {math.sin(s.yaw)*math.cos(s.pitch)*s.distance,
		math.sin(s.pitch)*s.distance, math.cos(s.yaw)*math.cos(s.pitch)*s.distance})
	draw_error := r3d.model_material_draw(s.device, e.desc, bindings, {
		mesh = &s.meshes[s.mode == 3 ? 2 : 1], world_matrix = world.MATRIX4_IDENTITY,
		view = {target = foster.DrawableTargetFromTarget(target), view_projection = world.camera3d_view_projection(&s.camera),
			time = e.time, delta_time = e.last_delta, frame = e.frame},
		pointer = {(s.pointer.x-s.viewport.X)/s.viewport.Width, (s.pointer.y-s.viewport.Y)/s.viewport.Height},
		pass_limit = s.preview_pass+1,
		options = {enabled = e.enabled[:len(e.desc.passes)],
			user_data = &host, prepare = material_preview_prepare, submit = material_preview_submit},
	})
	if draw_error != .None do bank_error(s, fmt.tprintf("Cannot bind model material: %s", mat.draw_error_text(draw_error)))
	return foster.TargetAttachment(target)
}

// 保存整个对象效果的参数；临时借用组和数值，文件保存函数内部复制路径。
save_material :: proc(s: ^Session, effect: int, path: string) -> bool {
	if effect < 0 || effect >= len(s.effects) || !mat.effect_is_material(s.effects[effect].desc) do return false
	color_picker_close(s, true)
	e := s.effects[effect].desc
	groups := make([dynamic]mat.Instance_Group, context.temp_allocator)
	for pass in e.passes {
		found := false
		for group in groups do found = found || group.schema.name == string(pass.params)
		if found do continue
		p := &s.parameters[bank_index(s.bank, string(pass.params))]
		append(&groups, mat.Instance_Group{p.live, p.values})
	}
	reason := material_file_save({e.name, groups[:]}, path, s.source_root)
	parameter_error(&s.parameters[bank_index(s.bank, string(e.passes[0].params))], reason)
	return reason == ""
}

// 所有参数和贴图准备完成再提交；任一组失败都保留整个旧材质。
load_material :: proc(s: ^Session, effect: int, path: string) -> bool {
	if effect < 0 || effect >= len(s.effects) do return false
	e := s.effects[effect].desc
	schemas := make([]mat.Schema, s.shader_count, context.temp_allocator)
	for p, i in s.parameters[:s.shader_count] do schemas[i] = p.live
	next, reason := material_file_load(e, schemas, path)
	defer mat.instance_dispose(&next)
	reporter := &s.parameters[bank_index(s.bank, string(e.passes[0].params))]
	if reason != "" {
		parameter_error(reporter, reason)
		return false
	}
	textures: [16][16]foster.Texture
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
		mat.values_dispose(p.values)
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
