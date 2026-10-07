package ui

import "core:math"

import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   主题 —— UI_Theme / 默认深色主题
//   控件 —— button / heading / label / toggle / separator
//   游戏控件 —— image / image_button / progress_bar / slider
//   容器 —— row / column / panel / scroll / modal

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

// 按钮默认在内部松开时触发；options.trigger = .Press 可保留按下即触发。
// id 必须帧间稳定（clay 的悬停/过渡按 id 记忆；hover 查询发生在声明前，
// 用的是上一帧的布局——clay 官方模式）。
ui_button :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	id: string,
	label: string,
	options: UI_Widget_Options = {},
) -> bool {
	return ui_button_ex(ctx, theme, id, label, .Normal, options)
}

ui_button_ex :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	id: string,
	label: string,
	style: UI_Button_Style,
	options: UI_Widget_Options = {},
) -> bool {
	state := ui_interact(ctx, id, options)
	hovered := state.hovered && !state.disabled
	clicked := state.clicked

	bg, label_col: foster.Color
	#partial switch style {
	case .Primary:
		bg = theme.primary
		label_col = theme.text_on_accent
		if hovered {
			bg = state.active ? theme.primary_press : theme.primary_hover
		}
	case .Ghost:
		bg = foster.Color{0, 0, 0, 0}
		label_col = theme.text
		if hovered {
			bg = state.active ? theme.ghost_press : theme.ghost_hover
		}
	case:
		bg = theme.button
		label_col = theme.text
		if hovered {
			bg = state.active ? theme.button_press : theme.button_hover
		}
	}

	if state.disabled {
		label_col = theme.text_dim
		bg = theme.panel
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
			border = ui_focus_border(theme, state),
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

// 标签：运行时字符串，使用 Clay 默认 Words 换行。
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
	if config == nil {
		return
	}
	clay.TextDynamic(text, config)
}

// 开关：点击翻转 *value，返回新值。胶囊轨道 + 圆形滑块。
ui_toggle :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	id: string,
	value: ^bool,
	options: UI_Widget_Options = {},
) -> bool {
	state := ui_interact(ctx, id, options)
	hovered := state.hovered && !state.disabled
	if state.clicked {
		value^ = !value^
	}

	track := value^ ? theme.accent : theme.button_hover
	if hovered && !value^ {
		track = theme.button
	}
	if clay.UI()(
		clay.ElementDeclaration{
			id = clay.ID(id),
			layout = {
				sizing = {width = clay.SizingFixed(36), height = clay.SizingFixed(20)},
				padding = {left = 2, right = 2, top = 2, bottom = 2},
				childAlignment = {x = value^ ? .Right : .Left, y = .Center},
			},
			border = ui_focus_border(theme, state),
			backgroundColor = ui_clay_color(state.disabled ? theme.panel : track),
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
ui_row_decl :: proc(gap: u16 = 8) -> clay.ElementDeclaration {
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
ui_panel_decl :: proc(theme: ^UI_Theme, gap: u16 = 8, width: f32 = 0) -> clay.ElementDeclaration {
	return clay.ElementDeclaration{
		layout = {
			sizing = {width = width > 0 ? clay.SizingFixed(width) : clay.SizingGrow({}), height = clay.SizingFit({})},
			layoutDirection = .TopToBottom, childGap = gap,
			padding = clay.PaddingAll(theme.padding * 2),
		},
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

// ------------------------------------------------------------------------------
// 游戏常用控件 —— 图像 / 图像按钮 / 进度 / 滑条
// ------------------------------------------------------------------------------

@(private)
ui_focus_border :: proc(theme: ^UI_Theme, state: UI_Interaction) -> clay.BorderElementConfig {
	if state.focused && !state.disabled {
		return {color = ui_clay_color(theme.accent), width = {left = 2, right = 2, top = 2, bottom = 2}}
	}
	return {}
}

UI_Image_Data :: struct {
	sub: foster.Subtexture,
	source_border, border: f32,
}

// 可容纳文字/图标的图片背景声明。纹理由调用者持有，颜色使用预乘 alpha。
ui_image_decl :: proc(ctx: ^UI_Context, sub: foster.Subtexture,
	tint: foster.Color = {255, 255, 255, 255}) -> clay.ElementDeclaration {
	decl := clay.ElementDeclaration{
		layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
	}
	if sub.Texture == nil || ctx.image_len >= len(ctx.image_pool) {
		ctx.pool_overflow = ctx.pool_overflow || ctx.image_len >= len(ctx.image_pool)
		return decl
	}
	data := &ctx.image_pool[ctx.image_len]
	data^ = {sub = sub}
	ctx.image_len += 1
	decl.backgroundColor = ui_clay_color(tint)
	decl.custom = {customData = data}
	return decl
}

// 整张纹理的对称九宫格背景。source_border 为源图片像素，border 为逻辑像素。
// 保留四角比例，边缘仅沿对应方向拉伸；透明圆角需由图片自身提供。
ui_nine_slice_decl :: proc(ctx: ^UI_Context, texture: ^foster.Texture,
	source_border, border: f32, tint: foster.Color = {255, 255, 255, 255}) -> clay.ElementDeclaration {
	sub: foster.Subtexture
	if texture != nil {
		sub = foster.SubtextureFromTexture(texture)
	}
	decl := ui_image_decl(ctx, sub, tint)
	if decl.custom.customData != nil {
		data := cast(^UI_Image_Data)decl.custom.customData
		data.source_border = math.clamp(source_border, 0, min(sub.Frame.Width, sub.Frame.Height) * 0.5)
		data.border = max(border, 0)
	}
	return decl
}

// Subtexture 同时支持整张贴图、图集区域和裁切后的帧；按 Frame 尺寸缩放。
// sub 被复制到帧内池，GPU 纹理仍由调用者拥有。尺寸单位为逻辑像素。
ui_image :: proc(
	ctx: ^UI_Context,
	sub: foster.Subtexture,
	width, height: f32,
	tint: foster.Color = {255, 255, 255, 255},
) {
	decl := ui_image_decl(ctx, sub, tint)
	if decl.custom.customData == nil {
		return
	}
	decl.layout.sizing = {width = clay.SizingFixed(max(width, 0)), height = clay.SizingFixed(max(height, 0))}
	if clay.UI()(decl) {}
}

ui_image_button :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	id: string,
	sub: foster.Subtexture,
	size: f32 = 48,
	options: UI_Widget_Options = {},
) -> bool {
	state := ui_interact(ctx, id, options)
	bg := state.active ? theme.button_press : state.hovered ? theme.button_hover : theme.button
	if clay.UI()(clay.ElementDeclaration{
		id = clay.ID(id),
		layout = {padding = clay.PaddingAll(theme.padding)},
		backgroundColor = ui_clay_color(state.disabled ? theme.panel : bg),
		border = ui_focus_border(theme, state),
		cornerRadius = clay.CornerRadiusAll(theme.corner_radius),
	}) {
		ui_image(ctx, sub, size, size, state.disabled ? theme.text_dim : foster.Color{255, 255, 255, 255})
	}
	return state.clicked
}

// value 按 0..1 归一化，越界钳制；零进度不产生最小可见填充。
ui_progress_bar :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	value: f32,
	width: f32 = 200,
	height: f32 = 12,
) {
	value := math.clamp(value, 0, 1)
	if clay.UI()(clay.ElementDeclaration{
		layout = {sizing = {width = clay.SizingFixed(max(width, 0)), height = clay.SizingFixed(max(height, 0))}},
		backgroundColor = ui_clay_color(theme.button),
		cornerRadius = clay.CornerRadiusAll(height * 0.5),
	}) {
		if value > 0 {
			if clay.UI()(clay.ElementDeclaration{
				layout = {sizing = {width = clay.SizingFixed(max(width, 0) * value), height = clay.SizingFixed(max(height, 0))}},
				backgroundColor = ui_clay_color(theme.accent),
				cornerRadius = clay.CornerRadiusAll(height * 0.5),
			}) {}
		}
	}
}

// 返回本帧是否改变值。鼠标按下捕获后可拖出区域；导航 adjust 单位为 step。
ui_slider :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	id: string,
	value: ^f32,
	minimum: f32 = 0,
	maximum: f32 = 1,
	step: f32 = 0.05,
	width: f32 = 200,
	options: UI_Widget_Options = {},
) -> bool {
	state := ui_interact(ctx, id, options)
	before := value^
	span := maximum - minimum
	width := max(width, 24)
	if !state.disabled && span > 0 {
		box := clay.GetElementData(clay.ID(id))
		if box.found && (state.active || state.released) {
			t := math.clamp((ctx.pointer_x - box.boundingBox.x - 8) / max(box.boundingBox.width - 16, 1), 0, 1)
			value^ = minimum + span * t
		}
		if state.focused && ctx.navigation.adjust != 0 {
			value^ += ctx.navigation.adjust * (step > 0 ? step : span * 0.01)
		}
		value^ = math.clamp(value^, minimum, maximum)
	}
	t := span > 0 ? math.clamp((value^ - minimum) / span, 0, 1) : 0
	if clay.UI()(clay.ElementDeclaration{
		id = clay.ID(id),
		layout = {
			sizing = {width = clay.SizingFixed(width), height = clay.SizingFixed(24)},
			padding = {left = u16(t * (width - 16)), top = 4},
		},
		backgroundColor = ui_clay_color(state.disabled ? theme.panel : theme.button),
		cornerRadius = clay.CornerRadiusAll(12),
		border = ui_focus_border(theme, state),
	}) {
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(16), height = clay.SizingFixed(16)}},
			backgroundColor = ui_clay_color(state.disabled ? theme.text_dim : theme.accent),
			cornerRadius = clay.CornerRadiusAll(8),
		}) {}
	}
	return before != value^
}

// ------------------------------------------------------------------------------
// 容器 —— 列 / 滚动区域 / 全屏模态遮罩
// ------------------------------------------------------------------------------

ui_column_decl :: proc(gap: u16 = 8) -> clay.ElementDeclaration {
	decl := ui_row_decl(gap)
	decl.layout.layoutDirection = .TopToBottom
	decl.layout.childAlignment = {x = .Left, y = .Top}
	return decl
}

// 内容竖排、滚轮滚动、双轴裁剪；width=0 时占满父容器。
UI_Scroll_Entry :: struct {
	id: u32,
	offset: clay.Vector2,
	seen: bool,
}

ui_scroll_decl :: proc(
	ctx: ^UI_Context,
	id: string,
	height: f32,
	width: f32 = 0,
	gap: u16 = 8,
) -> clay.ElementDeclaration {
	ui_block_pointer(ctx, id)
	decl := ui_column_decl(gap)
	decl.id = clay.ID(id)
	decl.layout.sizing = {width = width > 0 ? clay.SizingFixed(width) : clay.SizingGrow({}), height = clay.SizingFixed(height)}
	decl.clip = {vertical = true, horizontal = true}
	for &scroll in ctx.scrolls {
		if scroll.id == decl.id.id {
			decl.clip.childOffset = scroll.offset
			scroll.seen = true
			return decl
		}
	}
	append(&ctx.scrolls, UI_Scroll_Entry{id = decl.id.id, seen = true})
	return decl
}

// 配合 ui_set_modal/ui_set_scope；尺寸覆盖逻辑 viewport，内容居中。
ui_modal_decl :: proc(ctx: ^UI_Context, id: string) -> clay.ElementDeclaration {
	return {
		id = clay.ID(id),
		layout = {
			sizing = {width = clay.SizingFixed(ctx.width), height = clay.SizingFixed(ctx.height)},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = {0, 0, 0, 0.65},
		floating = {attachTo = .Root, zIndex = 100, pointerCaptureMode = .Capture},
	}
}
