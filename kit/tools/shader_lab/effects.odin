package shader_lab

// 分区：RenderTexture 所有权 / 历史帧 / 命令与输入 / 多 Pass 执行。
import "core:math"

import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"
import fx "olib:kit/rendering/shader/effect"
import world "olib:kit/world"

Pass_Target :: struct {
	buffers: [2]foster.Target,
	history: bool,
}

Effect_Runtime :: struct {
	desc: fx.Effect_Desc,
	order: []int,
	targets: []Pass_Target,
	current: int,
	frame: u64,
	time, last_clock, last_delta: f32,
	last_tick: u64,
	clear_pending: bool,
	ready: bool,
	// 按参数组下标记录，长度等于所属 bank 的 shader_count。
	validated_revision: []u64,
	rejected_revision: []u64,
	enabled, expanded: [32]bool,
}

// 启停是会话预览状态；同时重置反馈，避免切换后混入旧历史。
set_pass_enabled :: proc(s: ^Session, effect, pass: int, enabled: bool) {
	if !s.initialized || effect < 0 || effect >= len(s.effects) do return
	e := &s.effects[effect]
	if pass < 0 || pass >= len(e.desc.passes) || e.enabled[pass] == enabled do return
	cancel(s)
	e.enabled[pass] = enabled
	effect_reset(s, e)
}

// 唯一 Current 输入自动直通；无输入或多个 Current 输入时使用声明的清屏色。
pass_bypass :: proc(s: ^Session, e: ^Effect_Runtime, pass: int, target: ^foster.Target) {
	p := e.desc.passes[pass]
	target_clear(s, target, p.target.clear)
	source_name: fx.Target_Ref
	count := 0
	for input in p.inputs {
		if input.frame != .Current do continue
		source_name = input.target
		count += 1
	}
	if count != 1 do return
	for producer, i in e.desc.passes {
		if producer.output != source_name do continue
		t := &e.targets[i]
		texture := foster.TargetAttachment(&t.buffers[t.history ? e.current : 0])
		r2d.push_blend(&s.render, foster.BlendModeDisabled)
		quad(&s.render, texture, {0, 0, f32(target.Width), f32(target.Height)})
		r2d.submit(&s.render, {target = foster.DrawableTargetFromTarget(target)})
		return
	}
}

effect_dispose :: proc(e: ^Effect_Runtime) {
	effect_targets_release(e)
	delete(e.targets)
	delete(e.order)
	delete(e.validated_revision)
	delete(e.rejected_revision)
	fx.effect_dispose(&e.desc)
	e^ = {}
}

// 仅释放 GPU 目标，保留声明、Pass 启停和折叠状态。
effect_targets_release :: proc(e: ^Effect_Runtime) {
	for &target in e.targets {
		for &buffer in target.buffers {
			foster.TargetDispose(&buffer)
			buffer = {}
		}
	}
	e.ready = false
	for &r in e.validated_revision do r = 0
	for &r in e.rejected_revision do r = 0
}

effect_targets_trim :: proc(bank: ^Parameter_Bank, selected: int) {
	if bank == nil do return
	for &e, i in bank.effects {
		if i != selected do effect_targets_release(&e)
	}
}

target_size :: proc(t: fx.Target_Desc, w, h: int) -> (int, int) {
	if t.width > 0 do return t.width, t.height
	scale := t.scale == 0 ? f32(1) : t.scale
	return max(1, int(f32(w)*scale)), max(1, int(f32(h)*scale))
}

target_clear :: proc(s: ^Session, target: ^foster.Target, color: [4]f32) {
	colors := [1]foster.Color{{u8(color[0]*255), u8(color[1]*255), u8(color[2]*255), u8(color[3]*255)}}
	foster.GraphicsDeviceClear(s.device, foster.DrawableTargetFromTarget(target), colors[:], 1, 0,
		foster.ClearMask.Color | foster.ClearMask.Depth)
}

// Resize 先分配整套新目标，失败保留该效果旧目标。历史目标始终两张，其余只分配一张。
effect_targets_prepare :: proc(s: ^Session, bank: ^Parameter_Bank, selected: int) -> bool {
	effect_targets_trim(bank, selected)
	for &used in bank.shader_used do used = false
	for &e, effect_index in bank.effects {
		if effect_index != selected do continue
		model := fx.effect_is_material(e.desc)
		changed := false
		for p, i in e.desc.passes {
			bank.shader_used[bank_index(bank, string(p.params))] = true
			if model && i > 0 do continue
			w, h := target_size(p.target, int(s.viewport.Width), int(s.viewport.Height))
			if w > 8192 || h > 8192 {
				bank_error(s, "RenderTexture exceeds 8192 pixels per axis")
				return false
			}
			changed = changed || e.targets[i].buffers[0].Width != w || e.targets[i].buffers[0].Height != h
		}
		if !changed do continue
		next := make([]Pass_Target, len(e.targets))
		valid := true
		for p, i in e.desc.passes {
			if model && i > 0 do continue
			w, h := target_size(p.target, int(s.viewport.Width), int(s.viewport.Height))
			next[i].history = e.targets[i].history
			formats := [3]foster.TextureFormat{.Color, .R16G16B16A16_FLOAT, .R32G32B32A32_FLOAT}
			samples: foster.SampleCount = .One
			if p.target.samples == 4 || (p.target.samples == 0 && p.draw != .Fullscreen) do samples = .Four
			depth := p.target.depth || (p.draw != .Fullscreen &&
				bank.parameters[bank_index(bank, string(p.params))].live.preview == "3d")
			attachments := [2]foster.TargetAttachmentSpec{{formats[int(p.target.format)], samples}, {.Depth32, samples}}
			for j in 0..<(next[i].history ? 2 : 1) {
				target := &next[i].buffers[j]
				foster.TargetInit(target, s.device, w, h, attachments[:depth ? 2 : 1], string(p.output))
				for texture in target.Attachments do valid = valid && texture.Resource != nil &&
					(texture.SampleCount == .One || !foster.TextureFormatIsColorFormat(texture.Format) || texture.ResolveResource != nil)
			}
		}
		if !valid {
			for &target in next {
				for &buffer in target.buffers do foster.TargetDispose(&buffer)
			}
			delete(next)
			bank_error(s, "Cannot allocate effect targets; previous targets retained")
			return false
		}
		for &target in e.targets {
			for &buffer in target.buffers do foster.TargetDispose(&buffer)
		}
		delete(e.targets)
		e.targets = next
		effect_reset(s, &e)
	}
	return true
}

effect_reset :: proc(s: ^Session, e: ^Effect_Runtime) {
	e.current = 0
	e.frame = 0
	e.time = 0
	e.last_delta = 0
	e.last_clock = s.clock
	e.last_tick = s.tick_serial
	// reset_history 允许从 Update 调用；GPU 清屏必须等到下一次 Render 的有效帧内。
	e.clear_pending = true
}

reset_history :: proc(s: ^Session) {
	if !s.initialized do return
	if s.selected_effect >= 0 do effect_reset(s, &s.effects[s.selected_effect])
}

step :: proc(s: ^Session) {
	if !s.initialized do return
	s.paused = true
	s.step_requested = true
}

// 非材质效果的绘制命令与热重载的管线探测都用内置几何。instanced 模型的探测与 Render3D 一样把网格属性
// 排在实例属性之后并绑定实例缓冲；改了属性位置的网格副本分配在临时内存里，探测在本帧内用完。
pass_command :: proc(s: ^Session, bank: ^Parameter_Bank, index: int, draw: fx.Pass_Draw,
	target: foster.DrawableTarget, instanced := false) -> foster.DrawCommand {
	preview3d := draw != .Fullscreen && bank.parameters[index].live.preview == "3d"
	mesh := preview3d ? (s.mode == 3 ? 2 : 1) : 0
	command: foster.DrawCommand
	geometry := &s.meshes[mesh]
	// 精灵 Pass 只用于管线探测（材质预览走 Render2D），需要的是 BatcherVertex 布局。
	if draw == .Sprite do geometry = &s.sprite_mesh
	foster.DrawCommandFromMesh(&command, target, geometry, &bank.materials[index])
	if draw == .Model && instanced {
		slots := fx.instance_count(bank.parameters[index].live)
		buf := &s.probe_instances[slots]
		if buf.capacity == 0 do r3d.model_buffer_create(buf, s.device, slots, 1, "shader lab instance probe")
		context.allocator = context.temp_allocator
		r3d.model_instanced_command(&command, geometry, buf, new(foster.VertexBuffer))
	}
	command.DepthTestEnabled = preview3d
	command.DepthWriteEnabled = preview3d
	command.CullMode = preview3d ? .Back : .None
	if draw != .Preview_Model && draw != .Sprite do command.BlendMode = foster.BlendModeDisabled
	return command
}

pass_uniforms :: proc(s: ^Session, index: int, draw: fx.Pass_Draw, target: foster.DrawableTarget,
	time, dt: f32, frame: u64) {
	material := &s.materials[index]
	w, h := target.WidthInPixels, target.HeightInPixels
	pointer := [2]f32{(s.pointer.x-s.viewport.X)/s.viewport.Width, (s.pointer.y-s.viewport.Y)/s.viewport.Height}
	block: [r3d.MATERIAL_FRAME_BLOCK_SIZE]u8
	if draw != .Fullscreen && s.parameters[index].live.preview == "3d" {
		// 3D 预览（model.hlsli 布局）与 Render3D 用同一个打包函数。
		world.camera3d_set_viewport(&s.camera, w, h)
		world.camera3d_set_position(&s.camera, {math.sin(s.yaw)*math.cos(s.pitch)*s.distance,
			math.sin(s.pitch)*s.distance, math.cos(s.yaw)*math.cos(s.pitch)*s.distance})
		matrices: [r3d.MATERIAL_VERTEX_BLOCK_SIZE]u8
		view := r3d.View{target = target, time = time, delta_time = dt, frame = frame}
		r3d.pack_material_blocks(matrices[:], block[:], world.camera3d_view_projection(&s.camera), world.MATRIX4_IDENTITY,
			view, r3d.camera_position(world.camera3d_view(&s.camera)), pointer, {1, 1, 1, 1})
		foster.MaterialStageSetUniformBuffer(&material.Fragment, block[:])
		foster.MaterialStageSetUniformBuffer(&material.Vertex, matrices[:])
		return
	}
	// Fullscreen 与 2D 预览（fullscreen.hlsli 布局）只有 Shader Lab 一个宿主：Clock.w 为精灵预览模式标记。
	sprite := draw == .Preview_Model && s.mode == 1
	mat.std140_write_vec4(block[:], 0, {time, dt, f32(frame), sprite ? 1 : 0})
	mat.std140_write_vec4(block[:], 16, {pointer[0], pointer[1], f32(w), f32(h)})
	mat.std140_write_vec4(block[:], 32, {1, 1, 1, 1})
	foster.MaterialStageSetUniformBuffer(&material.Fragment, block[:])
	view: [16]u8
	scale: f32 = sprite ? 0.7 : 1
	xscale := sprite ? scale*f32(h)/f32(w) : scale
	mat.std140_write_vec4(view[:], 0, {xscale, scale, 0, 0})
	foster.MaterialStageSetUniformBuffer(&material.Vertex, view[:])
}

// 暂停时重绘当前输出但保持 Previous 不动，因此调参数不会偷偷推进反馈模拟。
effect_render :: proc(s: ^Session, e: ^Effect_Runtime) -> ^foster.Texture {
	if e.clear_pending {
		for p, i in e.desc.passes {
			if fx.effect_is_material(e.desc) && i > 0 do continue
			for j in 0..<(e.targets[i].history ? 2 : 1) {
				target_clear(s, &e.targets[i].buffers[j], p.target.clear)
			}
		}
		e.clear_pending = false
	}
	advance := s.step_requested || (!s.paused && e.last_tick != s.tick_serial)
	dt := e.last_delta
	if advance {
		dt = s.step_requested ? f32(1.0/60.0) : max(0, s.clock-e.last_clock)
		e.current = 1-e.current
		e.time += dt
		e.frame += 1
		e.last_delta = dt
	}
	e.last_tick = s.tick_serial
	e.last_clock = s.clock
	s.step_requested = false
	if fx.effect_is_material(e.desc) do return material_effect_render(s, e)
	for i in e.order {
		p := e.desc.passes[i]
		index := bank_index(s.bank, string(p.params))
		t := &e.targets[i]
		target := &t.buffers[t.history ? e.current : 0]
		if !e.enabled[i] {
			pass_bypass(s, e, i, target)
			continue
		}
		drawable := foster.DrawableTargetFromTarget(target)
		command := pass_command(s, s.bank, index, p.draw, drawable)
		mat.pass_state_apply(&command, p.state)
		pass_uniforms(s, index, p.draw, drawable, e.time, dt, e.frame)
		parameters_bind(s, index)
		parameter := &s.parameters[index]
		if len(p.values) > 0 {
			values := make([]fx.Value, len(parameter.values), context.temp_allocator)
			copy(values, parameter.values)
			for value in p.values {
				for f, j in parameter.live.fields {
					if f.id == string(value.field) do values[j].number = value.number
				}
			}
			_ = fx.pack(parameter.live, values, parameter.buffer)
			foster.MaterialStageSetUniformBuffer(&s.materials[index].Fragment, parameter.buffer, 1)
		}
		for input in p.inputs {
			slot := 0
			for f in parameter.live.fields {
				if f.kind != .Texture do continue
				if f.id == string(input.field) {
					for producer, j in e.desc.passes {
						if producer.output != input.target do continue
						source := &e.targets[j]
						buffer := source.history ? (input.frame == .Previous ? 1-e.current : e.current) : 0
						s.materials[index].Fragment.Samplers[slot].Texture = foster.TargetAttachment(&source.buffers[buffer])
					}
				}
				slot += 1
			}
		}
		target_clear(s, target, p.target.clear)
		foster.GraphicsDeviceDraw(s.device, &command)
		foster.DrawCommandDispose(&command)
	}
	for p, i in e.desc.passes {
		if (s.preview_pass < 0 && p.output == e.desc.output) || s.preview_pass == i {
			t := &e.targets[i]
			return foster.TargetAttachment(&t.buffers[t.history ? e.current : 0])
		}
	}
	return &s.texture
}
