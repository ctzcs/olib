package shader_lab

// Shader 选择、中间目标查看和反馈控制；没有节点编辑器，源声明仍归外部 .oshader 文件。
import "core:fmt"
import foster "olib:foster"
import sh "olib:kit/rendering/shader"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

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
	branch := ui.ui_column_decl(6)
	branch.layout.sizing.width = clay.SizingFixed(panel_width(s))
	branch.layout.padding.left = 16
	branch.border = {color = ui.ui_clay_color(s.theme.panel_border), width = {left = 1}}
	s.parameter_inset = 16
	defer s.parameter_inset = 0
	if clay.UI()(branch) {
		if lab_button(s, id, name, false, true, "media/folder",
			p.folder_closed ? "ui/arrow-right-03" : "ui/arrow-down-03") {
			cancel(s)
			p.folder_closed = !p.folder_closed
		}
		if p.folder_closed do return
		// 宿主接了 open_file 时，源码文件名就是“用代码编辑器打开”的按钮。
		if s.open_file != nil {
			if lab_button(s, fmt.tprintf("open-source:%s", p.name), fmt.tprintf("编辑 %s", p.live.shader), false, true,
				"media/code") && !s.open_file(texture_path(s, p.live.shader)) {
				bank_error(s, fmt.tprintf("Cannot open %s", p.live.shader))
			}
		} else {
			ui.ui_label_dim(&s.ctx, &s.small_theme, p.live.shader)
		}
		if s.file_dialogs && s.selected_shader >= 0 && sh.shader_is_material(s.shaders[s.selected_shader].desc) {
			ui.ui_label_dim(&s.ctx, &s.small_theme, "保存 / 载入整个材质")
		}
		if clay.UI()(ui.ui_row_decl(4)) {
			if s.file_dialogs {
				if lab_button(s, "preset-save", "保存", icon = "ui/save") do request_file(s, index, .Save_Preset)
				if lab_button(s, "preset-load", "载入", icon = "media/import") do request_file(s, index, .Load_Preset)
			}
			if lab_button(s, "preset-reset", "重置", icon = "editing/undo") do _ = reset_defaults(s, index)
		}
		if s.request.id != 0 do ui.ui_label_dim(&s.ctx, &s.small_theme, "Waiting for file selection...")
		parameters_panel(s, index)
	}
}

// 无论一个还是多个 Pass，只有 Shader 这一个选择入口。
shader_selector :: proc(s: ^Session) {
	ui.ui_label_dim(&s.ctx, &s.small_theme, "Shader")
	name := "选择 Shader"
	if s.selected_shader >= 0 {
		e := &s.shaders[s.selected_shader]
		name = display_name(e.desc.label, e.desc.name)
	}
	if s.shader_menu && ui.ui_clicked(&s.ctx) && !clay.PointerOver(clay.ID("shader-popup")) && !clay.PointerOver(clay.ID("shader-menu")) {
		s.shader_menu = false
	}
	if lab_button(s, "shader-menu", name, true, true, "media/clapper",
		s.shader_menu ? "ui/arrow-up-03" : "ui/arrow-down-03") {
		s.shader_menu = !s.shader_menu
	}
	if !s.shader_menu do return
	popup := ui.ui_scroll_decl(&s.ctx, "shader-popup", min(248, max(96, s.ctx.height-200)), panel_width(s), 4)
	popup.floating = {attachTo = .ElementWithId, parentId = clay.ID("shader-menu").id,
		attachment = {element = .LeftTop, parent = .LeftBottom}, offset = {0, 4}, zIndex = 30,
		pointerCaptureMode = .Capture}
	popup.layout.padding = clay.PaddingAll(6)
	popup.backgroundColor = ui.ui_clay_color(s.theme.panel)
	popup.border = {color = ui.ui_clay_color(s.theme.panel_border), width = {left = 1, right = 1, top = 1, bottom = 1}}
	popup.cornerRadius = clay.CornerRadiusAll(4)
	if clay.UI()(popup) {
		for e, i in s.shaders {
			if shader_has_3d(s, i) != (s.workspace == 1) do continue
			if lab_button(s, fmt.tprintf("shader:%s", e.desc.name), display_name(e.desc.label, e.desc.name), s.selected_shader == i, true) {
				select_shader(s, i)
				s.shader_menu = false
			}
		}
		// 新建：按当前工作区写一份能直接编译的模板到源码目录，热重载后自动选中。
		templates := s.workspace == 1 ? []Shader_Template{.Model, .Model_Instanced} : []Shader_Template{.Sprite, .Post_Process}
		for template in templates {
			if lab_button(s, fmt.tprintf("shader-new:%v", template), template_menu_label(template), false, true, "symbols/plus") {
				if _, reason := new_shader(s, template); reason != "" do bank_error(s, reason)
				s.shader_menu = false
			}
		}
	}
}

passes_panel :: proc(s: ^Session) {
	if s.selected_shader < 0 do return
	e := &s.shaders[s.selected_shader]
	pending_pass := -1
	if clay.UI()(ui.ui_column_decl(4)) {
		for i in e.order {
			p := e.desc.passes[i]
			selected := s.inspect_pass == i
			if clay.UI()(ui.ui_row_decl(4)) {
				if lab_checkbox(s, fmt.tprintf("pass-enabled:%s:%s", e.desc.name, p.id), e.enabled[i]) {
					set_pass_enabled(s, s.selected_shader, i, !e.enabled[i])
				}
				label := display_name(p.label, string(p.id))
				if lab_button(s, fmt.tprintf("pass:%s", p.id), label, selected, true) {
					if selected {
						cancel(s)
						e.expanded[i] = !e.expanded[i]
					} else {
						e.expanded[i] = true
					}
					pending_pass = i
				}
			}
		}
	}
	if pending_pass >= 0 do select_shader(s, s.selected_shader, pending_pass)
}

inspector_panel :: proc(s: ^Session) {
	if s.workspace_empty || s.program_count == 0 do return
	if s.selected_shader < 0 do return
	e := &s.shaders[s.selected_shader]
	if s.inspect_pass >= 0 {
		i := s.inspect_pass
		p := e.desc.passes[i]
		ui.ui_label_ex(&s.ctx, &s.theme, display_name(p.label, string(p.id)), s.theme.text, 18)
		if !e.enabled[i] do ui.ui_label_dim(&s.ctx, &s.small_theme, "已禁用 · 单输入直通，否则清屏")
		if e.expanded[i] {
			group_folder(s, s.selected, fmt.tprintf("group-folder:%s:%s", e.desc.name, p.id))
		} else {
			ui.ui_label_dim(&s.ctx, &s.small_theme, "参数已折叠，点击上方 Pass 展开")
		}
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
