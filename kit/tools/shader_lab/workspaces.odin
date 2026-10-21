package shader_lab

// 工作区书签：2D/3D 各自记住选中的 Shader、Pass、载体和相机。只拥有预览状态，不改写 .oshader 或材质预设。
import "core:strings"

Workspace_State :: struct {
	shader, pass, preview: string, // 拥有的稳定 ID，跨候选包提交仍有效。
	paused, custom_preview, preview_settings: bool,
	mode: int,
	yaw, pitch, distance: f32,
}

workspace_dispose :: proc(w: ^Workspace_State) {
	delete(w.shader)
	delete(w.pass)
	delete(w.preview)
	w^ = {}
}

workspace_save :: proc(s: ^Session) {
	if s.program_count == 0 || s.workspace_empty do return
	w := &s.workspaces[s.workspace]
	workspace_dispose(w)
	if s.selected_shader >= 0 {
		e := &s.shaders[s.selected_shader]
		w.shader = strings.clone(e.desc.name)
		if s.inspect_pass >= 0 do w.pass = strings.clone(string(e.desc.passes[s.inspect_pass].id))
		if s.preview_pass >= 0 do w.preview = strings.clone(string(e.desc.passes[s.preview_pass].id))
	}
	w.mode = s.mode
	w.paused = s.paused
	w.custom_preview = s.custom_preview
	w.preview_settings = s.preview_settings
	w.yaw = s.yaw
	w.pitch = s.pitch
	w.distance = s.distance
}

workspace_view_restore :: proc(s: ^Session) {
	w := &s.workspaces[s.workspace]
	s.mode = s.workspace == 1 ? 2 : 0
	s.preview_settings = false
	s.shader_menu = false
	s.mode = w.mode
	s.paused = w.paused
	s.custom_preview = w.custom_preview
	s.preview_settings = w.preview_settings
	s.yaw = w.yaw
	s.pitch = w.pitch
	s.distance = w.distance
}

select_workspace :: proc(s: ^Session, dimension: int) {
	if !s.initialized || dimension < 0 || dimension > 1 || dimension == s.workspace do return
	workspace_save(s)
	cancel(s)
	s.workspace = dimension
	workspace_restore(s)
}

workspace_restore :: proc(s: ^Session) {
	workspace_view_restore(s)
	w := &s.workspaces[s.workspace]
	s.selected_shader = -1
	s.inspect_pass = -1
	s.preview_pass = -1
	s.workspace_empty = false
	chosen := -1
	for e, i in s.shaders {
		if shader_has_3d(s, i) != (s.workspace == 1) do continue
		if chosen < 0 do chosen = i
		if e.desc.name == w.shader {
			chosen = i
			break
		}
	}
	if chosen >= 0 {
		pass := -1
		if s.shaders[chosen].desc.name == w.shader {
			for p, i in s.shaders[chosen].desc.passes {
				if string(p.id) == w.pass do pass = i
			}
		}
		select_shader(s, chosen, pass)
		if s.shaders[chosen].desc.name == w.shader {
			for p, i in s.shaders[chosen].desc.passes {
				if string(p.id) == w.preview do s.preview_pass = i
			}
		}
		return
	}
	s.workspace_empty = true
}
