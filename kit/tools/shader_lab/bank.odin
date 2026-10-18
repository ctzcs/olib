package shader_lab

// 参数包和所有效果作为一个候选整体切换；Shader/Material 地址在 bank 存活期间固定。
// 分区：资源所有权 / 候选创建 / GPU 探测与提交。
import "core:fmt"
import "core:path/filepath"
import "core:strings"

import foster "olib:foster"
import mat "olib:kit/material"
import rendering "olib:kit/rendering"
import dev "olib:kit/shaderdev"

Parameter_Bank :: struct {
	shaders: [16]dev.Session,
	materials: [16]foster.Material,
	parameters: [16]Parameter_State,
	shader_count: int,
	shader_used: [16]bool,
	effects: []Effect_Runtime,
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
	for &shader in b.shaders do dev.dispose(&shader)
	for &effect in b.effects do effect_dispose(&effect)
	delete(b.effects)
	free(b)
}

bank_index :: proc(b: ^Parameter_Bank, name: string) -> int {
	for p, i in b.parameters[:b.shader_count] {
		if p.name == name do return i
	}
	return -1
}

bank_make :: proc(s: ^Session, build: dev.Parameter_Build) -> ^Parameter_Bank {
	b := new(Parameter_Bank)
	b.fingerprint = s.parameter_watch.attempted
	b.shader_count = len(build.schemas)
	for schema, i in build.schemas {
		p := &b.parameters[i]
		p.name = strings.clone(schema.name)
		p.live = mat.schema_clone(schema)
		p.available = true
		p.values = mat.values_make(p.live)
		p.buffer = make([]u8, mat.uniform_size(p.live))
		source, _ := filepath.abs(fmt.tprintf("%s/%s", s.source_root, schema.shader), context.temp_allocator)
		_ = dev.init(&b.shaders[i], source, s.device.Driver, {uniform_buffers = 1}, {uniform_buffers = 2})
		if prior := bank_index(s.bank, schema.name); prior >= 0 {
			b.shaders[i].revision = s.shaders[prior].revision
		}
		foster.MaterialInitWithShaders(&b.materials[i], &b.shaders[i].vertex, &b.shaders[i].fragment)
		header := mat.hlsl(schema)
		include_path := ""
		if s.generated_directory != "" {
			generated, _ := filepath.abs(fmt.tprintf("%s/%s/params.generated.hlsli",
				s.generated_directory, schema.name), context.temp_allocator)
			include_path, _ = filepath.rel(filepath.dir(source), generated, context.temp_allocator)
			include_path, _ = strings.replace_all(include_path, "\\", "/", context.temp_allocator)
		}
		dev.configure_parameters(&b.shaders[i], header, mat.texture_count(schema), source, include_path)
		delete(header)
	}
	// 参数组只是 Shader 资源；只有显式 X_Passes / X_Output 才创建效果和目标。
	b.effects = make([]Effect_Runtime, len(build.effects))
	for desc, i in build.effects {
		e := &b.effects[i]
		e.desc = mat.effect_clone(desc)
		e.order, _ = mat.effect_order(e.desc, build.schemas)
		e.targets = make([]Pass_Target, len(desc.passes))
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
bank_selected_effect :: proc(s: ^Session, b: ^Parameter_Bank) -> int {
	if b == s.bank do return s.selected_effect
	name := s.workspaces[s.workspace].effect
	if s.selected_effect >= 0 do name = s.effects[s.selected_effect].desc.name
	chosen := -1
	for e, i in b.effects {
		if bank_effect_has_3d(b, i) != (s.workspace == 1) do continue
		if chosen < 0 do chosen = i
		if e.desc.name == name do return i
	}
	return chosen
}

// 只为选中效果分配目标、验证管线；其他 Shader 仅保留编译结果。
bank_apply :: proc(s: ^Session, b: ^Parameter_Bank, selected: int, apply_updates: bool = true) -> bool {
	if b == nil || b.candidate_failed do return false
	if !effect_targets_prepare(s, b, selected) {
		if selected >= 0 do b.effects[selected].ready = false
		return false
	}
	ready := true
	drawable := true
	for &shader, i in b.shaders[:b.shader_count] {
		if b.shader_used[i] {
			e := &b.effects[selected]
			needs_apply := shader.status == .Ready && apply_updates
			needs_check := shader.vertex.Resource != nil && e.validated_revision[i] != shader.revision &&
				e.rejected_revision[i] != shader.revision
			if needs_apply || needs_check {
				probes := make([dynamic]foster.DrawCommand, context.temp_allocator)
				for p, j in e.desc.passes {
					if string(p.params) != b.parameters[i].name do continue
					target := foster.DrawableTargetFromTarget(&e.targets[mat.effect_is_material(e.desc) ? 0 : j].buffers[0])
					command := pass_command(s, b, i, p.draw, target, string(p.id))
					rendering.pass_state_apply(&command, p.state)
					append(&probes, command)
				}
				applied := false
				if needs_apply {
					applied = dev.apply(&shader, s.device, probes[:])
				} else {
					// 切到另一套目标/网格时，用缓存代码验证实际管线，无需重新编译 HLSL。
					error: string
					applied, error = foster.ShaderPairTryReplace(&shader.vertex, &shader.fragment, s.device,
						shader.vertex.CreateInfo, shader.fragment.CreateInfo, probes[:])
					if !applied {
						e.rejected_revision[i] = shader.revision
						bank_error(s, error)
					}
				}
				for &probe in probes do foster.DrawCommandDispose(&probe)
				if applied {
					e.validated_revision[i] = shader.revision
					e.rejected_revision[i] = 0
					if b == s.bank {
						effect_reset(s, e)
						if s.pending_bank == nil do bank_error(s, "")
					}
				}
			}
			drawable = drawable && shader.vertex.Resource != nil && shader.fragment.Resource != nil &&
				e.validated_revision[i] == shader.revision
		}
		if shader.status == .Error && b == s.pending_bank {
			bank_error(s, fmt.tprintf("%s: %s", b.parameters[i].name, shader.diagnostic))
		}
		// 候选包仍等待源码编译成功；未选中效果不分配目标或创建 GPU Shader。
		ready = ready && (shader.status == .Live || (!b.shader_used[i] && shader.status == .Ready))
	}
	if selected >= 0 do b.effects[selected].ready = drawable
	return b == s.pending_bank ? ready && drawable : drawable
}

bank_commit :: proc(s: ^Session) {
	b := s.pending_bank
	current, ok := dev.parameters_fingerprint(s.parameter_directory)
	if !ok || current != b.fingerprint do return
	workspace_save(s)
	cancel(s)
	// 最后时刻迁移值，编译期间用户继续调参数也不会被旧快照覆盖。
	for &p in b.parameters[:b.shader_count] {
		for &texture in p.textures do foster.TextureDispose(&texture)
		p.textures = {}
		prior := bank_index(s.bank, p.name)
		mat.values_dispose(p.values)
		if prior >= 0 {
			old := &s.parameters[prior]
			p.folder_closed = old.folder_closed
			p.values = mat.values_make(p.live, old.live, old.values)
		} else {
			p.values = mat.values_make(p.live)
		}
		slot := 0
		for f, j in p.live.fields {
			if f.kind != .Texture do continue
			valid: bool
			p.textures[slot], valid = load_parameter_texture(s, s.device, p.values[j].texture)
			if !valid {
				bank_error(s, fmt.tprintf("%s: cannot load texture; previous effect retained", p.name))
				b.candidate_failed = true
				return
			}
			slot += 1
		}
		s.schema_generation += 1
		p.generation = s.schema_generation
		texture_stamps_reset(s, &p)
	}
	selected := bank_index(b, s.parameters[s.selected].name)
	new_effect := -1
	new_pass := -1
	new_preview := -1
	for &e in b.effects {
		for old in s.effects {
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
	if s.selected_effect >= 0 {
		name := s.effects[s.selected_effect].desc.name
		for e, i in b.effects {
			if e.desc.name != name do continue
			new_effect = i
			if s.preview_pass >= 0 {
				id := s.effects[s.selected_effect].desc.passes[s.preview_pass].id
				for p, j in e.desc.passes {
					if p.id == id do new_preview = j
				}
			}
			if s.inspect_pass >= 0 {
				id := s.effects[s.selected_effect].desc.passes[s.inspect_pass].id
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
	s.selected_effect = new_effect
	s.inspect_pass = -1
	s.preview_pass = new_preview
	if new_effect >= 0 && effect_has_3d(s, new_effect) == (s.workspace == 1) {
		select_effect(s, new_effect, new_pass)
		if (s.mode >= 2) != effect_has_3d(s, new_effect) do s.mode = effect_has_3d(s, new_effect) ? 2 : 0
	} else {
		workspace_restore(s)
	}
	s.fonts_dirty = true
	bank_error(s, "")
}
