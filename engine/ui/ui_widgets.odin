// ui:widgets —— 控件与主题层（Paper 观感的 olib 自建方案）。
//
// clay 不提供控件库（v0.14 也无文本输入），这层用 clay 的布局原语 +
// PointerOver/点击边沿搭出最小控件集：Button/Label/Toggle。
// 状态色来自 Theme；hover/按下即时生效，过渡动画接 clay 的 transition
// API 是后续增量。
package ui

import "core:strings"

import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// 分区：
//   主题 —— UI_Theme / 默认深色主题
//   控件 —— button / label / toggle

// ------------------------------------------------------------------------------
// 主题
// ------------------------------------------------------------------------------

UI_Theme :: struct {
	window_bg:      foster.Color,
	panel:          foster.Color,
	button:         foster.Color,
	button_hover:   foster.Color,
	button_press:   foster.Color,
	text:           foster.Color,
	text_disabled:  foster.Color,
	accent:         foster.Color,
	corner_radius:  f32,
	padding:        u16,
	body_font_id:   u16,
	body_font_size: u16,
}

UI_THEME_DARK :: UI_Theme{
	window_bg      = {24, 26, 32, 255},
	panel          = {32, 35, 43, 255},
	button         = {55, 61, 78, 255},
	button_hover   = {72, 80, 100, 255},
	button_press   = {46, 52, 66, 255},
	text           = {228, 230, 235, 255},
	text_disabled  = {120, 124, 133, 255},
	accent         = {86, 156, 210, 255},
	corner_radius  = 6,
	padding        = 8,
	body_font_id   = 0,
	body_font_size = 16,
}

// clay 颜色换算（foster.Color 的 u8 通道 -> clay 的 0..1）。
ui_clay_color :: proc(c: foster.Color) -> clay.Color {
	return clay.Color{
		f32(c.R) / 255,
		f32(c.G) / 255,
		f32(c.B) / 255,
		f32(c.A) / 255,
	}
}

// ------------------------------------------------------------------------------
// 控件
// ------------------------------------------------------------------------------

// 按钮：返回本帧是否被点击（悬停 + 按下边沿）。label 为运行时字符串。
// id 必须帧间稳定（clay 的悬停/过渡按 id 记忆；hover 查询发生在声明前，
// 用的是上一帧的布局——clay 官方模式）。
ui_button :: proc(ctx: ^UI_Context, theme: ^UI_Theme, id: string, label: string) -> bool {
	hovered := clay.PointerOver(clay.ID(id))
	clicked := hovered && ui_clicked(ctx)

	bg := theme.button
	if hovered {
		bg = ctx.pointer_down ? theme.button_press : theme.button_hover
	}

	if clay.UI()(
		clay.ElementDeclaration{
			id = clay.ID(id),
			layout = {
				sizing = {width = clay.SizingFit({min = 80, max = 400}), height = clay.SizingFit({})},
				padding = clay.PaddingAll(theme.padding),
				childAlignment = {x = .Center, y = .Center},
			},
			backgroundColor = ui_clay_color(bg),
			cornerRadius = clay.CornerRadiusAll(theme.corner_radius),
		},
	) {
		ui_label(ctx, theme, label)
	}
	return clicked
}

// 标签：单行文本（运行时字符串）。
// config 经 ctx 的帧内池分配：clay 存裸指针、EndLayout 才回读，
// 栈上局部 config 会悬垂（表现为渲染命令里颜色/字号变垃圾值）。
ui_label :: proc(ctx: ^UI_Context, theme: ^UI_Theme, text: string) {
	config := ui_text_config(ctx, clay.TextElementConfig{
		fontId = theme.body_font_id,
		fontSize = theme.body_font_size,
		textColor = ui_clay_color(theme.text),
	})
	if config == nil { return }
	clay.TextDynamic(text, config)
}

// 开关：点击翻转 *value，返回新值。外观 = 圆角轨道 + 方形滑块。
ui_toggle :: proc(ctx: ^UI_Context, theme: ^UI_Theme, id: string, value: ^bool) -> bool {
	hovered := clay.PointerOver(clay.ID(id))
	if hovered && ui_clicked(ctx) {
		value^ = !value^
	}

	if clay.UI()(
		clay.ElementDeclaration{
			id = clay.ID(id),
			layout = {
				sizing = {width = clay.SizingFixed(34), height = clay.SizingFixed(18)},
				padding = {left = 2, right = 2, top = 2, bottom = 2},
				childAlignment = {x = value^ ? .Right : .Left, y = .Center},
			},
			backgroundColor = ui_clay_color(value^ ? theme.accent : theme.button),
			cornerRadius = clay.CornerRadiusAll(theme.corner_radius),
		},
	) {
		if clay.UI()(
			clay.ElementDeclaration{
				id = clay.ID(id, 1), // 下标 1：滑块子元素的稳定 id
				layout = {sizing = {width = clay.SizingFixed(14), height = clay.SizingFixed(14)}},
				backgroundColor = ui_clay_color(theme.text),
				cornerRadius = clay.CornerRadiusAll(2),
			},
		) {}
	}
	return value^
}

// 面板：带内边距与圆角的容器声明（子内容在返回的 if 块里声明）。
ui_panel_decl :: proc(theme: ^UI_Theme) -> clay.ElementDeclaration {
	return clay.ElementDeclaration{
		layout = {padding = clay.PaddingAll(theme.padding * 2)},
		backgroundColor = ui_clay_color(theme.panel),
		cornerRadius = clay.CornerRadiusAll(theme.corner_radius),
	}
}

