package shader_lab

// 分区：工作区书签 / 固定区域的滚动记忆。只拥有预览状态，不改写 Odin 或材质预设。
import "core:fmt"
import "core:strings"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

Workspace_State :: struct {
	effect, pass, preview: string, // 拥有的稳定 ID，跨候选包提交仍有效。
	paused, custom_preview, preview_settings: bool,
	mode: int,
	yaw, pitch, distance: f32,
}

workspace_dispose :: proc(w: ^Workspace_State) {
	delete(w.effect)
	delete(w.pass)
	delete(w.preview)
	w^ = {}
}

workspace_save :: proc(s: ^Session) {
	if s.shader_count == 0 || s.workspace_empty do return
	w := &s.workspaces[s.workspace]
	workspace_dispose(w)
	if s.selected_effect >= 0 {
		e := &s.effects[s.selected_effect]
		w.effect = strings.clone(e.desc.name)
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
	s.effect_menu = false
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
	s.selected_effect = -1
	s.inspect_pass = -1
	s.preview_pass = -1
	s.workspace_empty = false
	chosen := -1
	for e, i in s.effects {
		if effect_has_3d(s, i) != (s.workspace == 1) do continue
		if chosen < 0 do chosen = i
		if e.desc.name == w.effect {
			chosen = i
			break
		}
	}
	if chosen >= 0 {
		pass := -1
		if s.effects[chosen].desc.name == w.effect {
			for p, i in s.effects[chosen].desc.passes {
				if string(p.id) == w.pass do pass = i
			}
		}
		select_effect(s, chosen, pass)
		if s.effects[chosen].desc.name == w.effect {
			for p, i in s.effects[chosen].desc.passes {
				if string(p.id) == w.preview do s.preview_pass = i
			}
		}
		return
	}
	s.workspace_empty = true
}

// ui_begin 已快照上一布局的实际滚动位置。按稳定容器 ID 保存，不把旧 Pass 偏移套给新 Pass。
scroll_memory_capture :: proc(s: ^Session) {
	clear(&s.scroll_restores)
	for scroll in s.ctx.scrolls do s.scroll_offsets[scroll.id] = scroll.offset
}

lab_scroll :: proc(s: ^Session, id: string, height, width: f32, gap: u16 = 8) -> clay.ElementDeclaration {
	key := clay.ID(id).id
	exists := false
	for scroll in s.ctx.scrolls do exists = exists || scroll.id == key
	decl := ui.ui_scroll_decl(&s.ctx, id, height, width, gap)
	if !exists {
		if offset, saved := s.scroll_offsets[key]; saved {
			decl.clip.childOffset = offset
			append(&s.scroll_restores, ui.UI_Scroll_Entry{id = key, offset = offset})
		}
	}
	return decl
}

scroll_memory_restore :: proc(s: ^Session) {
	for scroll in s.scroll_restores {
		data := clay.GetScrollContainerData(clay.ElementId{id = scroll.id})
		if data.found do data.scrollPosition^ = scroll.offset
	}
}

inspector_scroll_id :: proc(s: ^Session) -> string {
	if s.preview_settings do return fmt.tprintf("inspector:settings:%d", s.workspace)
	if s.selected_effect >= 0 && s.inspect_pass >= 0 {
		e := &s.effects[s.selected_effect]
		return fmt.tprintf("inspector:%d:%s:%s", s.workspace, e.desc.name, e.desc.passes[s.inspect_pass].id)
	}
	return fmt.tprintf("inspector:%d:empty", s.workspace)
}
