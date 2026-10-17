package shader_lab

// Shader Lab 专用紧凑主题；控件继续使用 UI_Context 的焦点与输入捕获。
import "core:math"

import foster "olib:foster"
import rendering "olib:kit/rendering"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

lab_theme :: proc() -> ui.UI_Theme {
	t := ui.UI_THEME_DARK
	t.window_bg = {13, 16, 20, 255}
	t.panel = {22, 26, 33, 255}
	t.panel_border = {43, 51, 60, 255}
	t.button = {25, 31, 38, 255}
	t.button_hover = {36, 45, 54, 255}
	t.button_press = {20, 38, 42, 255}
	t.accent = {117, 184, 255, 255}
	t.primary = {36, 54, 77, 255}
	t.primary_hover = {35, 81, 74, 255}
	t.primary_press = {22, 54, 50, 255}
	t.text = {210, 219, 228, 255}
	t.text_dim = {140, 154, 168, 255}
	t.text_on_accent = t.accent
	t.corner_radius = 2
	t.padding = 5
	t.body_font_size = 16
	t.heading_font_size = 20
	t.small_font_size = 14
	return t
}

// 图集子图引用稳定的 Session / 宿主纹理；跟随 UI 比例直接画到最终像素。
lab_icon :: proc(s: ^Session, name: string, tint: foster.Color, size: f32 = 20) {
	if name == "" || s.icons == nil do return
	sub, found := rendering.atlas_subtexture(s.icons, name)
	if found do ui.ui_image(&s.ctx, sub, size, size, tint)
}

lab_button :: proc(s: ^Session, id, label: string, selected := false, grow := false,
	icon: string = "", trailing_icon: string = "") -> bool {
	state := ui.ui_interact(&s.ctx, id)
	decl := ui.ui_row_decl(6)
	decl.id = clay.ID(id)
	decl.layout.sizing = {width = grow ? clay.SizingGrow({}) : clay.SizingFit({}), height = clay.SizingFixed(30)}
	decl.layout.padding = {left = 8, right = 8}
	decl.backgroundColor = ui.ui_clay_color(state.active ? s.theme.button_press :
		state.hovered ? s.theme.button_hover : selected ? s.theme.primary : s.theme.button)
	decl.border = {color = ui.ui_clay_color(s.theme.accent), width = {bottom = state.focused ? 1 : 0}}
	decl.cornerRadius = clay.CornerRadiusAll(4)
	if clay.UI()(decl) {
		lab_icon(s, icon, selected ? s.theme.accent : s.theme.text)
		ui.ui_label_ex(&s.ctx, &s.theme, label, selected ? s.theme.accent : s.theme.text, 16)
		if trailing_icon != "" {
			if grow do ui.ui_spacer()
			lab_icon(s, trailing_icon, s.theme.text_dim, 16)
		}
	}
	return state.clicked
}

lab_checkbox :: proc(s: ^Session, id: string, checked: bool) -> bool {
	state := ui.ui_interact(&s.ctx, id)
	decl := ui.ui_row_decl(0)
	decl.id = clay.ID(id)
	decl.layout.sizing = {width = clay.SizingFixed(24), height = clay.SizingFixed(30)}
	decl.layout.childAlignment = {x = .Center, y = .Center}
	if clay.UI()(decl) {
		box := ui.ui_row_decl(0)
		box.layout.sizing = {width = clay.SizingFixed(18), height = clay.SizingFixed(18)}
		box.layout.childAlignment = {x = .Center, y = .Center}
		box.backgroundColor = ui.ui_clay_color(checked ? s.theme.primary : s.theme.button)
		box.border = {color = ui.ui_clay_color(state.focused || checked || state.hovered ? s.theme.accent : s.theme.text_dim),
			width = {left = 1, right = 1, top = 1, bottom = 1}}
		box.cornerRadius = clay.CornerRadiusAll(3)
		if clay.UI()(box) {
			if checked do lab_icon(s, "ui/tick", s.theme.accent, 16)
		}
	}
	return state.clicked
}

lab_slider :: proc(s: ^Session, id: string, value: ^f32, minimum, maximum, step: f32) {
	width := panel_width(s)
	state := ui.ui_interact(&s.ctx, id)
	box := clay.GetElementData(clay.ID(id))
	span := maximum-minimum
	if !state.disabled && span > 0 {
		if box.found && (state.active || state.released) {
			value^ = minimum+span*math.clamp((s.ctx.pointer_x-box.boundingBox.x-4)/
				max(1, box.boundingBox.width-8), 0, 1)
		}
		if state.focused do value^ += s.ctx.navigation.adjust*step
		value^ = math.clamp(value^, minimum, maximum)
	}
	t := span > 0 ? math.clamp((value^-minimum)/span, 0, 1) : 0
	decl := ui.ui_row_decl(0)
	decl.id = clay.ID(id)
	decl.layout.sizing = {width = clay.SizingFixed(width), height = clay.SizingFixed(18)}
	decl.layout.childAlignment.y = .Center
	decl.border = {color = ui.ui_clay_color(state.focused ? s.theme.accent : foster.Transparent),
		width = {bottom = 1}}
	if clay.UI()(decl) {
		fill := t*(width-8)
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(fill), height = clay.SizingFixed(4)}},
			backgroundColor = ui.ui_clay_color(s.theme.primary),
		}) {}
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(8), height = clay.SizingFixed(12)}},
			backgroundColor = ui.ui_clay_color(s.theme.accent),
		}) {}
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(width-8-fill), height = clay.SizingFixed(4)}},
			backgroundColor = ui.ui_clay_color(s.theme.panel_border),
		}) {}
	}
}
