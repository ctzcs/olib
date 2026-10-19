package shader_lab

// 分区：工作区布局 / 预览设置 / 诊断。选择参数不会隐式切换右侧输出。
import "core:fmt"
import "core:math"
import "core:strings"
import foster "olib:foster"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

panel :: proc(s: ^Session, pixel_w, pixel_h: f32) {
	s.panel_active = true
	defer s.panel_active = false
	ui.ui_set_viewport(&s.ctx, {0, 0, pixel_w, pixel_h}, s.ui_scale)
	w := s.ctx.width
	h := s.ctx.height
	input := s.input
	if !input.focused || input.escape do cancel(s)
	s.pointer = input.focused ? input.pointer : foster.Vec2{-10000, -10000}
	ui.ui_set_pointer(&s.ctx, s.pointer.x, s.pointer.y, input.focused && input.left_down)
	inside_panel := s.pointer.x >= 0 && s.pointer.y >= 0 && s.pointer.x < pixel_w && s.pointer.y < pixel_h
	if input.focused && inside_panel do ui.ui_add_scroll(&s.ctx, input.scroll.x, input.scroll.y)
	nav := input.focused ? input.navigation : ui.UI_Navigation{}
	nav.cancel = nav.cancel || !input.focused || input.escape
	ui.ui_set_navigation(&s.ctx, nav)
	ui.ui_set_modal(&s.ctx, s.color_picker.open ? "color-picker" : "")
	ui.ui_begin(&s.ctx, s.delta_time)
	scroll_memory_capture(s)
	if input.escape do s.effect_menu = false
	root := ui.ui_column_decl(8)
	root.layout.padding = clay.PaddingAll(8)
	if clay.UI()(root) {
		header := ui.ui_row_decl(12)
		header.layout.sizing.height = clay.SizingFixed(36)
		if clay.UI()(header) {
			if lab_button(s, "toggle-sidebar", s.sidebar_collapsed ? "面板" : "收起", icon = "ui/menu") {
				s.sidebar_collapsed = !s.sidebar_collapsed
			}
			ui.ui_heading(&s.ctx, &s.heading_theme, "SHADER LAB")
			ui.ui_spacer()
			if w > 700 do ui.ui_label_dim(&s.ctx, &s.small_theme, "保存源码即更新")
			if lab_button(s, "pause", s.paused ? "播放" : "暂停", icon = s.paused ? "media/play" : "media/pause") do s.paused = !s.paused
			if s.selected_effect >= 0 && w > 900 {
				if lab_button(s, "effect-step", "单步", icon = "media/next-frame") do step(s)
				if lab_button(s, "effect-reset", "重置反馈", icon = "ui/refresh") do reset_history(s)
			}
		}
		if !s.sidebar_collapsed {
			settings := ui.ui_column_decl(8)
			settings.id = clay.ID("settings")
			settings.layout.sizing = {width = clay.SizingFixed(s.sidebar_effective), height = clay.SizingFixed(h-84)}
			settings.layout.padding = clay.PaddingAll(12)
			settings.backgroundColor = ui.ui_clay_color(s.theme.panel)
			settings.cornerRadius = clay.CornerRadiusAll(6)
			ui.ui_block_pointer(&s.ctx, "settings")
			if clay.UI()(settings) {
				head := ui.ui_column_decl(6)
				head.layout.sizing.height = clay.SizingFixed(100)
				if clay.UI()(head) {
					if clay.UI()(ui.ui_row_decl(6)) {
						if lab_button(s, "workspace:2d", "2D", s.workspace == 0, true, "media/image") do select_workspace(s, 0)
						if lab_button(s, "workspace:3d", "3D", s.workspace == 1, true, "media/pc-host") do select_workspace(s, 1)
					}
					effect_selector(s)
				}
				list_height := math.clamp((h-84)*0.25, 80, 156)
				list := ui.ui_column_decl(6)
				list.layout.sizing.height = clay.SizingFixed(list_height)
				if clay.UI()(list) {
					ui.ui_label_dim(&s.ctx, &s.small_theme, "处理流程 · 勾选启用，点击编辑")
					id := s.selected_effect >= 0 ? fmt.tprintf("passes:%d:%s", s.workspace, s.effects[s.selected_effect].desc.name) : fmt.tprintf("passes:%d", s.workspace)
					if clay.UI()(lab_scroll(s, id, list_height-24, panel_width(s), 4)) {
						effects_panel(s)
					}
				}
				if clay.UI()(ui.ui_row_decl(6)) {
					if lab_button(s, "inspector-parameters", "参数", !s.preview_settings, true, "ui/slider") {
						cancel(s)
						s.preview_settings = false
					}
					if lab_button(s, "preview-settings", "预览设置", s.preview_settings, true, "ui/settings") {
						cancel(s)
						s.preview_settings = true
					}
				}
				if clay.UI()(lab_scroll(s, inspector_scroll_id(s), max(40, h-262-list_height), panel_width(s), 8)) {
					if s.preview_settings {
						preview_options(s)
					} else {
						inspector_panel(s)
					}
					lab_diagnostics(s)
				}
			}
		} else {
			if clay.UI()(clay.ElementDeclaration{layout = {sizing = {
				width = clay.SizingFixed(1), height = clay.SizingFixed(h-84)}}}) {}
		}
		if !s.sidebar_collapsed && !s.compact do splitter(s, h)
		if !s.compact || s.sidebar_collapsed {
			bar := ui.ui_row_decl(8)
			bar.id = clay.ID("preview-toolbar")
			bar.layout.sizing = {width = clay.SizingFixed(s.viewport.Width/s.ui_scale), height = clay.SizingFixed(36)}
			bar.floating = {attachTo = .Parent, offset = {s.viewport.X/s.ui_scale, 52}}
			ui.ui_block_pointer(&s.ctx, "preview-toolbar")
			if clay.UI()(bar) {
				ui.ui_label_dim(&s.ctx, &s.small_theme, "预览")
				if s.selected_effect >= 0 && len(s.effects[s.selected_effect].desc.passes) > 1 {
					if lab_button(s, "effect-final", "最终效果", s.preview_pass < 0, icon = "media/display") do s.preview_pass = -1
					if lab_button(s, "pass-preview", "当前 Pass", s.preview_pass >= 0, icon = "ui/visible") do s.preview_pass = s.inspect_pass
					if s.preview_pass >= 0 && s.viewport.Width/s.ui_scale > 550 {
						p := s.effects[s.selected_effect].desc.passes[s.preview_pass]
						ui.ui_label_dim(&s.ctx, &s.small_theme, display_name(p.label, string(p.id)))
					}
				} else {
					ui.ui_label(&s.ctx, &s.theme, "最终效果")
				}
			}
		}
		if clay.UI()(ui.ui_row_decl(8)) {
			failed := s.bank_error != "" || s.parameter_watch.status == .Error
			status := failed ? "编译失败 · 保留上次结果" : s.pending_bank != nil ? "正在编译" : "LIVE"
			ui.ui_label_dim(&s.ctx, &s.small_theme, status)
			ui.ui_spacer()
			if w > 650 {
				time := s.selected_effect >= 0 ? s.effects[s.selected_effect].time : s.clock
				ui.ui_label_dim(&s.ctx, &s.small_theme, fmt.tprintf("%.2fs   UI %d%%   %s", time, int(s.ui_scale*100), preview_size_label(s)))
			}
		}
	}
	color_picker_panel(s)
	foster.BatcherClear(&s.batch)
	ui.ui_draw(&s.ctx, &s.batch)
	scroll_memory_restore(s)
	capture := ui.ui_input_capture(&s.ctx)
	inside := s.pointer.x >= s.viewport.X && s.pointer.x < (s.viewport.X+s.viewport.Width) &&
		s.pointer.y >= s.viewport.Y && s.pointer.y < (s.viewport.Y+s.viewport.Height)
	if input.right_pressed && input.focused && inside && !capture.pointer && s.mode >= 2 {
		s.orbiting = true
	}
	if !input.right_down || !input.focused do s.orbiting = false
	if s.orbiting {
		s.yaw -= input.delta.x*0.008
		s.pitch = math.clamp(s.pitch + input.delta.y*0.008, -1.4, 1.4)
	}
	if inside && input.focused && !capture.pointer && s.mode >= 2 {
		s.distance = math.clamp(s.distance - input.scroll.y*0.25, 2, 10)
	}
	s.capture = capture
	s.capture.pointer = input.focused && (capture.pointer || inside_panel || s.orbiting)
	s.capture.keyboard = input.focused && (capture.keyboard || input.escape || s.color_picker.open)
}

preview_options :: proc(s: ^Session) {
	if s.workspace_empty || s.shader_count == 0 do return
	ui.ui_label_dim(&s.ctx, &s.small_theme, "预览载体 · 不会切换 Shader")
	model3d := s.selected_effect >= 0 ? effect_has_3d(s, s.selected_effect) : s.parameters[s.selected].live.preview == "3d"
	if clay.UI()(ui.ui_row_decl(6)) {
		for id, i in ([4]string{"2D / Fullscreen", "2D / Sprite", "3D / Sphere", "3D / Cube"}) {
			if model3d != (i >= 2) do continue
			names := [4]string{"全屏", "精灵", "球体", "立方体"}
			if lab_button(s, id, names[i], s.mode == i) do s.mode = i
		}
	}
	if s.preview_hooks.prepare != nil || s.preview_hooks.draw != nil {
		if lab_button(s, "preview-host", "使用宿主模型", s.custom_preview) do s.custom_preview = !s.custom_preview
	}
	if model3d {
		ui.ui_label_dim(&s.ctx, &s.small_theme, "右键旋转 / 滚轮缩放")
		if lab_button(s, "reset-camera", "重置相机", icon = "media/camera") {
			s.yaw = 0.4
			s.pitch = 0.25
			s.distance = 4
		}
	}
	if s.selected_effect >= 0 {
		if clay.UI()(ui.ui_row_decl(6)) {
			if lab_button(s, "settings-step", "单步", icon = "media/next-frame") do step(s)
			if lab_button(s, "settings-reset", "重置反馈", icon = "ui/refresh") do reset_history(s)
		}
	}
	if lab_button(s, "retry", "重新编译", icon = "media/code") {
		s.parameter_watch.has_attempted = false
	}
}

lab_diagnostics :: proc(s: ^Session) {
	if s.bank_error != "" do ui.ui_label(&s.ctx, &s.theme, wrap_diagnostic(s.bank_error))
	if s.parameter_watch.diagnostic != "" {
		ui.ui_label(&s.ctx, &s.theme, wrap_diagnostic(s.parameter_watch.diagnostic))
	}
	if s.shader_count > 0 && s.shaders[s.selected].diagnostic != "" {
		if clay.UI()(ui.ui_scroll_decl(&s.ctx, "diagnostic", 170, panel_width(s), gap = 4)) {
			message, _ := strings.replace_all(s.shaders[s.selected].diagnostic, s.source_root,
				"shaders", context.temp_allocator)
			ui.ui_label(&s.ctx, &s.theme, wrap_diagnostic(message))
		}
	}
}

// 编译器路径可能没有空格；显式断行保证诊断在侧栏可读，完整原文仍输出到控制台。
wrap_diagnostic :: proc(message: string) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	column := 0
	for character in message {
		strings.write_rune(&builder, character)
		column = character == '\n' ? 0 : column+1
		if column >= 29 {
			strings.write_rune(&builder, '\n')
			column = 0
		}
	}
	return strings.to_string(builder)
}
