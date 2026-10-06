// ui:widgets —— 控件与主题层（Paper 观感的 olib 自建方案）。
//
// clay 不提供控件库（v0.14 也无文本输入），这层用 clay 的布局原语 +
// PointerOver/点击边沿搭出最小控件集：Button(三种样式)/Heading/Label/
// Toggle/Separator。状态色来自 Theme；hover/按下即时生效，过渡动画接
// clay 的 transition API 是后续增量。
package ui

import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// 分区：
//   主题 —— UI_Theme / 默认深色主题
//   控件 —— button / heading / label / toggle / separator / 容器声明

// ------------------------------------------------------------------------------
// 主题
// ------------------------------------------------------------------------------

UI_Theme :: struct {
	window_bg:     foster.Color,
	panel:         foster.Color,
	panel_border:  foster.Color,
	button:        foster.Color,
	button_hover:  foster.Color,
	button_press:  foster.Color,
	primary:       foster.Color, // 主按钮底色（accent 填充）
	primary_hover: foster.Color,
	primary_press: foster.Color,
	text:          foster.Color,
	text_dim:      foster.Color, // 次级文本
	text_on_accent: foster.Color, // 主按钮上的文字
	accent:        foster.Color,
	ghost_hover:   foster.Color, // 幽灵按钮 hover 蒙层（半透明叠加色）
	ghost_press:   foster.Color,
	corner_radius:  f32,
	padding:        u16,
	body_font_id:   u16,
	body_font_size: u16,
	heading_font_size: u16,
	small_font_size:   u16,
}

UI_THEME_DARK :: UI_Theme{
	window_bg       = {14, 15, 19, 255},
	panel           = {24, 26, 32, 255},
	panel_border    = {47, 51, 62, 255},
	button          = {42, 46, 56, 255},
	button_hover    = {55, 60, 73, 255},
	button_press    = {33, 36, 44, 255},
	primary         = {62, 109, 232, 255},
	primary_hover   = {82, 128, 242, 255},
	primary_press   = {48, 86, 196, 255},
	text            = {235, 237, 243, 255},
	text_dim        = {148, 154, 168, 255},
	text_on_accent  = {255, 255, 255, 255},
	accent          = {62, 109, 232, 255},
	ghost_hover     = {255, 255, 255, 26},
	ghost_press     = {255, 255, 255, 46},
	corner_radius   = 8,
	padding         = 10,
	body_font_id    = 0,
	body_font_size  = 16,
	heading_font_size = 22,
	small_font_size   = 13,
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

UI_Button_Style :: enum {
	Normal,  // 常规：深灰底
	Primary, // 主操作：accent 填充白字
	Ghost,   // 幽灵：透明底，hover 半透明白
}

// 按钮：返回本帧是否被点击（悬停 + 按下边沿）。label 为运行时字符串。
// id 必须帧间稳定（clay 的悬停/过渡按 id 记忆；hover 查询发生在声明前，
// 用的是上一帧的布局——clay 官方模式）。
ui_button :: proc(ctx: ^UI_Context, theme: ^UI_Theme, id: string, label: string) -> bool {
	return ui_button_ex(ctx, theme, id, label, .Normal)
}

ui_button_ex :: proc(ctx: ^UI_Context, theme: ^UI_Theme, id: string, label: string, style: UI_Button_Style) -> bool {
	hovered := clay.PointerOver(clay.ID(id))
	clicked := hovered && ui_clicked(ctx)

	bg, label_col: foster.Color
	#partial switch style {
	case .Primary:
		bg = theme.primary
		label_col = theme.text_on_accent
		if hovered { bg = ctx.pointer_down ? theme.primary_press : theme.primary_hover }
	case .Ghost:
		bg = foster.Color{0, 0, 0, 0}
		label_col = theme.text
		if hovered { bg = ctx.pointer_down ? theme.ghost_press : theme.ghost_hover }
	case:
		bg = theme.button
		label_col = theme.text
		if hovered { bg = ctx.pointer_down ? theme.button_press : theme.button_hover }
	}

	if clay.UI()(
		clay.ElementDeclaration{
			id = clay.ID(id),
			layout = {
				sizing = {
					width = clay.SizingFit({min = style == .Ghost ? 0 : 80, max = 400}),
					height = clay.SizingFit({}),
				},
				padding = clay.PaddingAll(theme.padding),
				childAlignment = {x = .Center, y = .Center},
			},
			backgroundColor = ui_clay_color(bg),
			cornerRadius = clay.CornerRadiusAll(theme.corner_radius),
		},
	) {
		ui_label_ex(ctx, theme, label, label_col, theme.body_font_size)
	}
	return clicked
}

// 标题文本（heading 字号）。
ui_heading :: proc(ctx: ^UI_Context, theme: ^UI_Theme, text: string) {
	ui_label_ex(ctx, theme, text, theme.text, theme.heading_font_size)
}

// 标签：单行文本（运行时字符串）。
// config 经 ctx 的帧内池分配：clay 存裸指针、EndLayout 才回读，
// 栈上局部 config 会悬垂（表现为渲染命令里颜色/字号变垃圾值）。
ui_label :: proc(ctx: ^UI_Context, theme: ^UI_Theme, text: string) {
	ui_label_ex(ctx, theme, text, theme.text, theme.body_font_size)
}

// 次级标签（暗色小字）。
ui_label_dim :: proc(ctx: ^UI_Context, theme: ^UI_Theme, text: string) {
	ui_label_ex(ctx, theme, text, theme.text_dim, theme.small_font_size)
}

ui_label_ex :: proc(ctx: ^UI_Context, theme: ^UI_Theme, text: string, color: foster.Color, size: u16) {
	config := ui_text_config(ctx, clay.TextElementConfig{
		fontId = theme.body_font_id,
		fontSize = size,
		textColor = ui_clay_color(color),
	})
	if config == nil { return }
	clay.TextDynamic(text, config)
}

// 开关：点击翻转 *value，返回新值。胶囊轨道 + 圆形滑块。
ui_toggle :: proc(ctx: ^UI_Context, theme: ^UI_Theme, id: string, value: ^bool) -> bool {
	hovered := clay.PointerOver(clay.ID(id))
	if hovered && ui_clicked(ctx) {
		value^ = !value^
	}

	track := value^ ? theme.accent : theme.button_hover
	if hovered && !value^ { track = theme.button }
	if clay.UI()(
		clay.ElementDeclaration{
			id = clay.ID(id),
			layout = {
				sizing = {width = clay.SizingFixed(36), height = clay.SizingFixed(20)},
				padding = {left = 2, right = 2, top = 2, bottom = 2},
				childAlignment = {x = value^ ? .Right : .Left, y = .Center},
			},
			backgroundColor = ui_clay_color(track),
			cornerRadius = clay.CornerRadiusAll(10), // 半高 = 胶囊
		},
	) {
		if clay.UI()(
			clay.ElementDeclaration{
				id = clay.ID(id, 1), // 下标 1：滑块子元素的稳定 id
				layout = {sizing = {width = clay.SizingFixed(16), height = clay.SizingFixed(16)}},
				backgroundColor = ui_clay_color(theme.text),
				cornerRadius = clay.CornerRadiusAll(8), // 半宽 = 圆
			},
		) {}
	}
	return value^
}

// 分隔线：横贯父容器宽度的 1px 细线。
ui_separator :: proc(ctx: ^UI_Context, theme: ^UI_Theme) {
	if clay.UI()(
		clay.ElementDeclaration{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(1)},
			},
			backgroundColor = ui_clay_color(theme.panel_border),
		},
	) {}
}

// 水平行容器声明（gap 像素间距，子元素垂直居中）。子内容在调用侧的
// if clay.UI()(ui_row_decl(...)) {} 块里声明。
ui_row_decl :: proc(gap: u16) -> clay.ElementDeclaration {
	return clay.ElementDeclaration{
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
			childGap = gap,
			childAlignment = {x = .Left, y = .Center},
		},
	}
}

// 占位元素：吃掉行内剩余空间（推右对齐用）。
ui_spacer :: proc() {
	if clay.UI()(
		clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(1)}},
		},
	) {}
}

// 面板：带内边距与圆角的容器声明（子内容在返回的 if 块里声明）。
ui_panel_decl :: proc(theme: ^UI_Theme) -> clay.ElementDeclaration {
	return clay.ElementDeclaration{
		layout = {padding = clay.PaddingAll(theme.padding * 2)},
		backgroundColor = ui_clay_color(theme.panel),
		cornerRadius = clay.CornerRadiusAll(theme.corner_radius + 2),
	}
}

// 面板描边容器：padding 1px + 边框色圆角底，包在 panel 外层即得 1px 边框。
ui_panel_border_decl :: proc(theme: ^UI_Theme) -> clay.ElementDeclaration {
	return clay.ElementDeclaration{
		layout = {padding = {left = 1, right = 1, top = 1, bottom = 1}},
		backgroundColor = ui_clay_color(theme.panel_border),
		cornerRadius = clay.CornerRadiusAll(theme.corner_radius + 3),
	}
}
