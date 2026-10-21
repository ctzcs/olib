package shader_lab

// 参数包和所有效果作为一个候选整体切换；Shader/Material 地址在 bank 存活期间固定。
// 分区：资源所有权 / 候选创建 / GPU 探测与提交。
import "core:fmt"
import "core:strings"

import foster "olib:foster"
import mat "olib:kit/rendering/material"
import sh "olib:kit/rendering/shader"
import dev "olib:kit/rendering/shader/dev"

Parameter_Bank :: struct {
	// 按构建结果一次分配，之后不再增长，Material 才能长期指向 programs 里的着色器。
	programs: []dev.Session,
	materials: []foster.Material,
	parameters: []Parameter_State,
	program_count: int,
	program_used: []bool,
	last_status: []dev.Status,
	shaders: []Shader_Runtime,
	fingerprint: u64,
	candidate_failed: bool,
}

bank_error :: proc(s: ^Session, error: string) {
	if s.bank_error == error do return
	delete(s.bank_error)
	s.bank_error = strings.clone(error)
	if error != "" do fmt.eprintln(error)
}

bank_dispose :: proc(b: ^Parameter_Bank) {
	if b == nil do return
	for &material in b.materials do foster.MaterialDispose(&material)
	for &p in b.parameters do parameter_dispose(&p)
	for &program in b.programs do dev.dispose(&program)
	for &shader in b.shaders do shader_dispose(&shader)
	delete(b.programs)
	delete(b.materials)
	delete(b.parameters)
	delete(b.program_used)
	delete(b.last_status)
	delete(b.shaders)
	free(b)
}

bank_index :: proc(b: ^Parameter_Bank, name: string) -> int {
	for p, i in b.parameters[:b.program_count] {
		if p.name == name do return i
	}
	return -1
}

bank_make :: proc(s: ^Session, build: dev.Parameter_Build) -> ^Parameter_Bank {
	b := new(Parameter_Bank)
	b.fingerprint = s.parameter_watch.attempted
	count := len(build.schemas)
	b.program_count = count
	b.programs = make([]dev.Session, count)
	b.materials = make([]foster.Material, count)
	b.parameters = make([]Parameter_State, count)
	b.program_used = make([]bool, count)
	b.last_status = make([]dev.Status, count)
	for schema, i in build.schemas {
		p := &b.parameters[i]
		p.name = strings.clone(schema.name)
		p.live = sh.schema_clone(schema)
		p.available = true
		p.values = sh.values_make(p.live)
		p.buffer = make([]u8, sh.uniform_size(p.live))
		program := build.programs[i]
		source, program_text := program.source, program.text
		// Sprite Pass 的批量变体从顶点 storage buffer 读两条轴和 [Instance] 字段（见 sh.hlsl 的 Sprite_Batch）。
		// Model Pass 另有顶点 b1 / 片元 b2 视图块（见 mat.VIEW_GLOBALS_SIZE），与材质库的槽数一致。
		storage := bank_group_draws(build.shaders, schema.name, .Sprite) ? 1 : 0
		view := bank_group_draws(build.shaders, schema.name, .Model) ? 1 : 0
		_ = dev.init(&b.programs[i], source, s.device.Driver,
			{uniform_buffers = 1 + storage + view, storage_buffers = storage}, {uniform_buffers = 2 + view})
		b.programs[i].source_text = strings.clone(program_text)
		if prior := bank_index(s.bank, schema.name); prior >= 0 {
			b.programs[i].revision = s.programs[prior].revision
			b.last_status[i] = s.last_status[prior]
		}
		foster.MaterialInitWithShaders(&b.materials[i], &b.programs[i].vertex, &b.programs[i].fragment)
		dev.configure_parameters(&b.programs[i], sh.texture_count(schema))
	}
	// 参数组只是 Shader 资源；每个 .oshader 创建一个效果及其 Pass 目标。
	b.shaders = make([]Shader_Runtime, len(build.shaders))
	for desc, i in build.shaders {
		e := &b.shaders[i]
		e.desc = sh.shader_clone(desc)
		e.order, _ = sh.shader_order(e.desc, build.schemas)
		e.targets = make([]Pass_Target, len(desc.passes))
		e.validated_revision = make([]u64, count)
		e.rejected_revision = make([]u64, count)
		for p, j in desc.passes {
			e.enabled[j] = !p.disabled
			e.expanded[j] = true
		}
		for input_pass in desc.passes {
			for input in input_pass.inputs {
				if input.frame != .Previous do continue
				for p, j in desc.passes {
					if p.output == input.target do e.targets[j].history = true
				}
			}
		}
	}
	return b
}

// 候选包跟随当前选择，按稳定 ID 映射；当前效果被删除后使用该工作区书签或首项。
bank_selected_shader :: proc(s: ^Session, b: ^Parameter_Bank) -> int {
	if b == s.bank do return s.selected_shader
	name := s.workspaces[s.workspace].shader
	if s.selected_shader >= 0 do name = s.shaders[s.selected_shader].desc.name
	chosen := -1
	for e, i in b.shaders {
		if bank_shader_has_3d(b, i) != (s.workspace == 1) do continue
		if chosen < 0 do chosen = i
		if e.desc.name == name do return i
	}
	return chosen
}

// 只为选中效果分配目标、验证管线；其他 Shader 仅保留编译结果。
bank_apply :: proc(s: ^Session, b: ^Parameter_Bank, selected: int, apply_updates: bool = true) -> bool {
	if b == nil || b.candidate_failed do return false
	if !shader_targets_prepare(s, b, selected) {
		if selected >= 0 do b.shaders[selected].ready = false
		return false
	}
	ready := true
	drawable := true
	for &program, i in b.programs[:b.program_count] {
		if b.program_used[i] {
			e := &b.shaders[selected]
			needs_apply := program.status == .Ready && apply_updates
			needs_check := program.vertex.Resource != nil && e.validated_revision[i] != program.revision &&
				e.rejected_revision[i] != program.revision
			if needs_apply || needs_check {
				probes := make([dynamic]foster.DrawCommand, context.temp_allocator)
				for p, j in e.desc.passes {
					if string(p.params) != b.parameters[i].name do continue
					target := foster.DrawableTargetFromTarget(&e.targets[sh.shader_is_material(e.desc) ? 0 : j].buffers[0])
					command := pass_command(s, b, i, p.draw, target, e.desc.instanced)
					mat.pass_state_apply(&command, p.state)
					append(&probes, command)
				}
				applied := false
				if needs_apply {
					applied = dev.apply(&program, s.device, probes[:])
				} else {
					// 切到另一套目标/网格时，用缓存代码验证实际管线，无需重新编译 HLSL。
					error: string
					applied, error = foster.ShaderPairTryReplace(&program.vertex, &program.fragment, s.device,
						program.vertex.CreateInfo, program.fragment.CreateInfo, probes[:])
					if !applied {
						e.rejected_revision[i] = program.revision
						bank_error(s, error)
					}
				}
				for &probe in probes do foster.DrawCommandDispose(&probe)
				if applied {
					e.validated_revision[i] = program.revision
					e.rejected_revision[i] = 0
					if b == s.bank {
						shader_reset(s, e)
						if s.pending_bank == nil do bank_error(s, "")
					}
				}
			}
			drawable = drawable && program.vertex.Resource != nil && program.fragment.Resource != nil &&
				e.validated_revision[i] == program.revision
		}
		if program.status == .Error && b == s.pending_bank {
			bank_error(s, fmt.tprintf("%s: %s", b.parameters[i].name, program.diagnostic))
			b.candidate_failed = true
		}
		// 候选包仍等待源码编译成功；未选中效果不分配目标或创建 GPU Shader。
		ready = ready && (program.status == .Live || (!b.program_used[i] && program.status == .Ready))
	}
	if selected >= 0 do b.shaders[selected].ready = drawable
	return b == s.pending_bank ? ready && drawable : drawable
}

bank_commit :: proc(s: ^Session) {
	b := s.pending_bank
	current, ok := dev.parameters_fingerprint(s.source_root)
	if !ok || current != b.fingerprint do return
	workspace_save(s)
	cancel(s)
	// 最后时刻迁移值，编译期间用户继续调参数也不会被旧快照覆盖。
	for &p in b.parameters[:b.program_count] {
		for &texture in p.textures do foster.TextureDispose(&texture)
		p.textures = {}
		prior := bank_index(s.bank, p.name)
		sh.values_dispose(p.values)
		if prior >= 0 {
			old := &s.parameters[prior]
			p.folder_closed = old.folder_closed
			p.values = sh.values_make(p.live, old.live, old.values)
		} else {
			p.values = sh.values_make(p.live)
		}
		slot := 0
		for f, j in p.live.fields {
			if f.kind != .Texture do continue
			valid: bool
			p.textures[slot], valid = load_parameter_texture(s, s.device, p.values[j].texture)
			if !valid {
				bank_error(s, fmt.tprintf("%s: cannot load texture; previous shader retained", p.name))
				b.candidate_failed = true
				return
			}
			slot += 1
		}
		s.schema_generation += 1
		p.generation = s.schema_generation
		texture_stamps_reset(s, &p)
	}
	selected := s.selected < s.program_count ? bank_index(b, s.parameters[s.selected].name) : -1
	new_selected := -1
	new_pass := -1
	new_preview := -1
	for &e in b.shaders {
		for old in s.shaders {
			if old.desc.name != e.desc.name do continue
			for p, i in e.desc.passes {
				for prior, j in old.desc.passes {
					if prior.id != p.id do continue
					e.expanded[i] = old.expanded[j]
					if prior.disabled == p.disabled do e.enabled[i] = old.enabled[j]
				}
			}
		}
	}
	if s.selected_shader >= 0 {
		name := s.shaders[s.selected_shader].desc.name
		for e, i in b.shaders {
			if e.desc.name != name do continue
			new_selected = i
			if s.preview_pass >= 0 {
				id := s.shaders[s.selected_shader].desc.passes[s.preview_pass].id
				for p, j in e.desc.passes {
					if p.id == id do new_preview = j
				}
			}
			if s.inspect_pass >= 0 {
				id := s.shaders[s.selected_shader].desc.passes[s.inspect_pass].id
				for p, j in e.desc.passes {
					if p.id == id do new_pass = j
				}
			}
		}
	}
	bank_dispose(s.bank)
	s.bank = b
	s.pending_bank = nil
	s.selected = max(0, selected)
	s.selected_shader = new_selected
	s.inspect_pass = -1
	s.preview_pass = new_preview
	if new_selected >= 0 && shader_has_3d(s, new_selected) == (s.workspace == 1) {
		select_shader(s, new_selected, new_pass)
		if (s.mode >= 2) != shader_has_3d(s, new_selected) do s.mode = shader_has_3d(s, new_selected) ? 2 : 0
	} else {
		workspace_restore(s)
	}
	s.fonts_dirty = true
	bank_error(s, "")
}

// 参数组是否被某种 Pass（Sprite / Model）使用。
@(private)
bank_group_draws :: proc(shaders: []sh.Shader_Desc, group: string, draw: sh.Pass_Draw) -> bool {
	for shader in shaders {
		for pass in shader.passes {
			if pass.draw == draw && string(pass.params) == group do return true
		}
	}
	return false
}
