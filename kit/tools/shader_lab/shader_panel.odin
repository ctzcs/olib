package shader_lab

// Shader 选择、中间目标查看和反馈控制；没有节点编辑器，源声明仍归外部 .oshader 文件。
import "core:fmt"
import foster "olib:foster"
import sh "olib:kit/rendering/shader"
import imgui "olib:thirdparty/odin-imgui"

preview_size_label :: proc(s: ^Session) -> string {
	if s.selected_shader >= 0 {
		e := &s.shaders[s.selected_shader]
		for p, i in e.desc.passes {
			if i == s.preview_pass || (s.preview_pass < 0 && p.output == e.desc.output) {
				t := &e.targets[sh.shader_is_material(e.desc) ? 0 : i].buffers[0]
				if len(t.Attachments) == 0 do break
				x := foster.TargetAttachment(t).SampleCount == .One ? 1 : 4
				return fmt.tprintf("RT %d x %d / MSAA %dx", t.Width, t.Height, x)
			}
		}
	}
	return fmt.tprintf("VIEW %d x %d", int(s.viewport.Width), int(s.viewport.Height))
}

shader_has_3d :: proc(s: ^Session, index: int) -> bool {
	return bank_shader_has_3d(s.bank, index)
}

bank_shader_has_3d :: proc(b: ^Parameter_Bank, index: int) -> bool {
	if b.shaders[index].desc.preview != "" do return b.shaders[index].desc.preview == "3d"
	for p in b.shaders[index].desc.passes {
		if p.draw != .Fullscreen && b.parameters[bank_index(b, string(p.params))].live.preview == "3d" do return true
	}
	return false
}

select_shader :: proc(s: ^Session, index: int, pass: int = -1) {
	if !s.initialized do return
	if index < 0 || index >= len(s.shaders) do return
	e := &s.shaders[index]
	if pass < -1 || pass >= len(e.desc.passes) do return
	dimension := shader_has_3d(s, index) ? 1 : 0
	if dimension != s.workspace {
		workspace_save(s)
		s.workspace = dimension
		workspace_view_restore(s)
	}
	s.workspace_empty = false
	selected_pass := pass < 0 ? e.order[0] : pass
	if index != s.selected_shader || selected_pass != s.inspect_pass do cancel(s)
	if index == s.selected_shader && s.preview_pass >= 0 do s.preview_pass = selected_pass
	if index != s.selected_shader {
		s.preview_pass = -1
		e.last_clock = s.clock
		e.last_tick = s.tick_serial
		if (s.mode >= 2) != (dimension == 1) do s.mode = dimension == 1 ? 2 : 0
	}
	s.selected_shader = index
	s.inspect_pass = selected_pass
	for p, i in e.desc.passes {
		if i == selected_pass {
			s.selected = bank_index(s.bank, string(p.params))
			break
		}
	}
}

display_name :: proc(label, id: string) -> string {
	return label == "" ? id : label
}

// folder 只是参数组的展示分组；一个 Pass 仍只绑定一个参数组（一个程序）。
group_folder :: proc(s: ^Session, index: int, id: string) {
	p := &s.parameters[index]
	name := display_name(p.live.label, p.name)
	if p.live.folder != "" do name = fmt.tprintf("%s / %s", p.live.folder, name)
	if lab_button(s, id, name, !p.folder_closed, true, "media/folder") {
		cancel(s)
		p.folder_closed = !p.folder_closed
	}
	if p.folder_closed do return
	imgui.Indent()
	defer imgui.Unindent()
	// 宿主接了 open_file 时，源码文件名就是“用代码编辑器打开”的按钮。
	if s.open_file != nil {
		if lab_button(s, fmt.tprintf("open-source:%s", p.name), fmt.tprintf("编辑 %s", p.live.shader), icon = "media/code") &&
			!s.open_file(texture_path(s, p.live.shader)) {
			bank_error(s, fmt.tprintf("Cannot open %s", p.live.shader))
		}
	} else {
		lab_dim(p.live.shader)
	}
	if s.file_dialogs && s.selected_shader >= 0 && sh.shader_is_material(s.shaders[s.selected_shader].desc) {
		lab_dim("保存 / 载入整个材质")
	}
	if s.file_dialogs {
		if lab_button(s, "preset-save", "保存", icon = "ui/save") do request_file(s, index, .Save_Preset)
		lab_same_line("载入")
		if lab_button(s, "preset-load", "载入", icon = "media/import") do request_file(s, index, .Load_Preset)
		lab_same_line("重置")
	}
	if lab_button(s, "preset-reset", "重置", icon = "editing/undo") do _ = reset_defaults(s, index)
	if s.request.id != 0 do lab_dim("Waiting for file selection...")
	parameters_panel(s, index)
}

// 无论一个还是多个 Pass，只有 Shader 这一个选择入口。菜单是 s.shader_menu 控制的浮层，
// 点外面、选中或 Escape 关闭，不挤动下方的 Pass 列表。
shader_selector :: proc(s: ^Session) {
	name := "选择 Shader"
	if s.selected_shader >= 0 {
		e := &s.shaders[s.selected_shader]
		name = display_name(e.desc.label, e.desc.name)
	}
	if lab_button(s, "shader-menu", name, s.shader_menu, true, "media/clapper") do s.shader_menu = true
	anchor := imgui.GetItemRectMin()
	size := imgui.GetItemRectSize()
	if s.shader_menu && !imgui.IsPopupOpen("shader-popup") {
		// 上一帧已打开、现在被 ImGui 关掉（点了浮层外面，包括这个按钮）就同步关闭，不能马上重开，
		// 否则重开的浮层第一帧隐藏测量尺寸，看起来闪一下而且关不掉。
		if s.shader_menu_shown {
			s.shader_menu = false
		} else {
			imgui.OpenPopup("shader-popup")
		}
	}
	s.shader_menu_shown = s.shader_menu
	imgui.SetNextWindowPos({anchor.x, anchor.y + size.y + 2})
	imgui.SetNextWindowSizeConstraints({size.x, 0}, {max(size.x, 480), 360})
	if !imgui.BeginPopup("shader-popup") {
		s.shader_menu = false
		return
	}
	defer imgui.EndPopup()
	if !s.shader_menu {
		imgui.CloseCurrentPopup()
		return
	}
	for e, i in s.shaders {
		if shader_has_3d(s, i) != (s.workspace == 1) do continue
		label := display_name(e.desc.label, e.desc.name)
		if imgui.Selectable(fmt.ctprintf("%s##shader:%s", label, e.desc.name), s.selected_shader == i) {
			select_shader(s, i)
			s.shader_menu = false
		}
		track(s, fmt.tprintf("shader:%s", e.desc.name))
	}
	imgui.Separator()
	// 新建：按当前工作区写一份能直接编译的模板到源码目录，热重载后自动选中。
	templates := s.workspace == 1 ? []Shader_Template{.Model, .Model_Instanced} : []Shader_Template{.Sprite, .Post_Process}
	for template in templates {
		if lab_button(s, fmt.tprintf("shader-new:%v", template), template_menu_label(template), false, true, "symbols/plus") {
			if _, reason := new_shader(s, template); reason != "" do bank_error(s, reason)
			s.shader_menu = false
		}
	}
}

passes_panel :: proc(s: ^Session) {
	if s.selected_shader < 0 do return
	e := &s.shaders[s.selected_shader]
	pending_pass := -1
	for i in e.order {
		p := e.desc.passes[i]
		selected := s.inspect_pass == i
		if lab_checkbox(s, fmt.tprintf("pass-enabled:%s:%s", e.desc.name, p.id), e.enabled[i]) {
			set_pass_enabled(s, s.selected_shader, i, !e.enabled[i])
		}
		imgui.SameLine()
		label := display_name(p.label, string(p.id))
		if imgui.Selectable(fmt.ctprintf("%s##pass:%s", label, p.id), selected) {
			if selected {
				cancel(s)
				e.expanded[i] = !e.expanded[i]
			} else {
				e.expanded[i] = true
			}
			pending_pass = i
		}
		track(s, fmt.tprintf("pass:%s", p.id))
	}
	if pending_pass >= 0 do select_shader(s, s.selected_shader, pending_pass)
}

inspector_panel :: proc(s: ^Session) {
	if s.workspace_empty || s.program_count == 0 do return
	if s.selected_shader < 0 || s.inspect_pass < 0 do return
	e := &s.shaders[s.selected_shader]
	i := s.inspect_pass
	p := e.desc.passes[i]
	imgui.SeparatorText(cstr(display_name(p.label, string(p.id))))
	if !e.enabled[i] do lab_dim("已禁用 · 单输入直通，否则清屏")
	if e.expanded[i] {
		group_folder(s, s.selected, fmt.tprintf("group-folder:%s:%s", e.desc.name, p.id))
	} else {
		lab_dim("参数已折叠，点击上方 Pass 展开")
	}
}

shader_value :: proc(s: ^Session, index: int, field: string) -> (value: [4]f32, overridden: bool) {
	if s.selected_shader < 0 do return
	e := &s.shaders[s.selected_shader]
	for p, i in e.desc.passes {
		if (s.inspect_pass >= 0 && s.inspect_pass != i) ||
			(s.inspect_pass < 0 && e.desc.output != p.output) || string(p.params) != s.parameters[index].name {
			continue
		}
		for v in p.values {
			if string(v.field) == field do return v.number, true
		}
	}
	return
}

// 显示当前被检查 Pass 的纹理输入；由流程连接的字段不弹出磁盘图片选择器。
shader_input :: proc(s: ^Session, index: int, field: string) -> (texture: ^foster.Texture, label: string) {
	if s.selected_shader < 0 do return
	e := &s.shaders[s.selected_shader]
	for p, i in e.desc.passes {
		if (s.inspect_pass >= 0 && s.inspect_pass != i) ||
			(s.inspect_pass < 0 && e.desc.output != p.output) || string(p.params) != s.parameters[index].name {
			continue
		}
		for input in p.inputs {
			if string(input.field) != field do continue
			for source, j in e.desc.passes {
				if source.output != input.target do continue
				t := &e.targets[j]
				buffer := t.history ? (input.frame == .Previous ? 1-e.current : e.current) : 0
				return foster.TargetAttachment(&t.buffers[buffer]),
					fmt.tprintf("%s / %v", input.target, input.frame)
			}
		}
	}
	return
}
