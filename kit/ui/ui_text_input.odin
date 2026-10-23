package ui

import "core:math"
import "core:unicode/utf8"

import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   宿主接入 —— UI_Text_Edit / ui_set_text_edit / ui_text_editing / ui_text_input_area
//   控件 —— ui_text_input（单行）
//   测量 —— 光标位置与点击定位

// ------------------------------------------------------------------------------
// 宿主接入
// ------------------------------------------------------------------------------

// 宿主每帧在 ui_begin 前传入的文字编辑输入，字符串借用到 ui_end。
// text 是本帧键入的文字（含输入法提交，如 foster 的 Keyboard.Text）；paste 由宿主在 Ctrl+V 时读剪贴板填入。
// 其余是按键边沿（含按住重复）：Enter 为 submit，Escape 为 cancel。
UI_Text_Edit :: struct {
	text, paste: string,
	backspace, delete, left, right, home, end: bool,
	submit, cancel: bool,
}

// 同一时间只有一个文本框在编辑。
UI_Text_State :: struct {
	id: u32,
	caret: int, // 字节位置，总在字符边界
	scroll: f32, // 水平滚动（逻辑像素）
	blink: f32, // 光标闪烁计时，有编辑或移动时归零
	area: foster.Rect, // 光标的渲染目标像素矩形，给输入法候选框
	editing, seen: bool,
}

UI_Text_Result :: struct {
	changed, submitted: bool,
}

ui_set_text_edit :: proc(ctx: ^UI_Context, edit: UI_Text_Edit) {
	ctx.text_edit = edit
}

// 上一帧是否有文本框在编辑。宿主据此打开系统文字输入（foster.SetTextInput），
// 并且不把字母、空格、方向键交给游戏；Tab 仍可作为导航移出文本框。
ui_text_editing :: proc(ctx: ^UI_Context) -> bool {
	return ctx.text.editing
}

// 编辑中光标的渲染目标像素矩形（不含 ui_set_visual 变换），交给 foster.SetTextInputArea 定位候选框。
ui_text_input_area :: proc(ctx: ^UI_Context) -> (rect: foster.Rect, ok: bool) {
	return ctx.text.area, ctx.text.editing
}

// ------------------------------------------------------------------------------
// 控件
// ------------------------------------------------------------------------------

// 单行文本框，UTF-8 内容直接写入 buffer（调用方拥有），最多 max_bytes 字节，不截断半个字符。
// 按下即获得焦点并按点击位置放光标；也可用导航移入。编辑键见 UI_Text_Edit；Enter 返回 submitted，
// Escape 或导航 cancel 结束编辑。文字过长时水平滚动跟随光标。不支持选区、多行与密码掩码。
ui_text_input :: proc(
	ctx: ^UI_Context,
	theme: ^UI_Theme,
	id: string,
	buffer: ^[dynamic]u8,
	placeholder: string = "",
	width: f32 = 240,
	max_bytes: int = 256,
	widget: UI_Widget_Options = {},
) -> (result: UI_Text_Result) {
	element := clay.ID(id)
	options := widget
	options.trigger = .Press
	state := ui_interact(ctx, id, options)
	font := ui_font_of(ctx, int(theme.body_font_id))
	size := theme.body_font_size
	pad := f32(theme.padding)
	t := &ctx.text
	editing := state.focused && !state.disabled
	if editing && t.id != element.id {
		t.id = element.id
		t.caret = len(buffer)
		t.scroll = 0
		t.blink = 0
	}
	if editing {
		result = ui_text_apply(ctx, element, id, font, size, pad, buffer, max_bytes, state.pressed)
		if ctx.text_edit.cancel {
			ctx.focused_id = 0
			editing = false
		}
	}
	if editing {
		ctx.input.keyboard = true
		t.seen = true
	}

	text := string(buffer[:])
	inner := max(width - pad*2, 1)
	caret_x := editing ? ui_text_width(font, text[:t.caret], size) : 0
	if editing {
		if caret_x - t.scroll > inner - 2 {
			t.scroll = caret_x - inner + 2
		}
		if caret_x < t.scroll {
			t.scroll = caret_x
		}
		t.scroll = math.clamp(t.scroll, 0, max(ui_text_width(font, text, size) - inner + 2, 0))
	}
	scroll := editing ? t.scroll : 0
	line := ui_text_line_height(font, size)
	border: clay.BorderElementConfig
	if editing {
		border = {color = ui_clay_color(theme.accent), width = {left = 2, right = 2, top = 2, bottom = 2}}
	} else if state.hovered && !state.disabled {
		border = {color = ui_clay_color(theme.panel_border), width = {left = 1, right = 1, top = 1, bottom = 1}}
	}
	if clay.UI()(clay.ElementDeclaration{
		id = element,
		layout = {
			sizing = {width = clay.SizingFixed(max(width, 16)), height = clay.SizingFixed(line + pad*2)},
			padding = clay.PaddingAll(theme.padding),
			childAlignment = {y = .Center},
		},
		clip = {horizontal = true, childOffset = {-scroll, 0}},
		backgroundColor = ui_clay_color(state.disabled ? theme.panel : theme.window_bg),
		border = border,
		cornerRadius = clay.CornerRadiusAll(theme.corner_radius),
	}) {
		shown, color := text, state.disabled ? theme.text_dim : theme.text
		if len(text) == 0 {
			shown, color = placeholder, theme.text_dim
		}
		if config := ui_text_config(ctx, clay.TextElementConfig{
			fontId = theme.body_font_id, fontSize = size, textColor = ui_clay_color(color), wrapMode = .None,
		}); config != nil && len(shown) > 0 {
			clay.TextDynamic(shown, config)
		}
		if editing && math.mod(t.blink, 1) < 0.5 {
			if clay.UI()(clay.ElementDeclaration{
				layout = {sizing = {width = clay.SizingFixed(2), height = clay.SizingFixed(line)}},
				floating = {attachTo = .Parent, offset = {pad + caret_x - scroll - 1, pad}, clipTo = .AttachedParent},
				backgroundColor = ui_clay_color(theme.text),
			}) {}
		}
	}
	if editing {
		// 上一帧布局的元素位置；视口原点与缩放换算到渲染目标像素。
		bb := clay.GetElementData(element).boundingBox
		x := bb.x + pad + caret_x - scroll
		t.area = {ctx.viewport_origin.x + x*ctx.scale, ctx.viewport_origin.y + (bb.y + pad)*ctx.scale,
			2*ctx.scale, line*ctx.scale}
	}
	return
}

@(private)
ui_text_apply :: proc(ctx: ^UI_Context, element: clay.ElementId, id: string, font: ^foster.MsdfFont,
	size: u16, pad: f32, buffer: ^[dynamic]u8, max_bytes: int, pressed: bool) -> (result: UI_Text_Result) {
	t := &ctx.text
	edit := ctx.text_edit
	t.caret = clamp(t.caret, 0, len(buffer))
	if pressed {
		bb := clay.GetElementData(element).boundingBox
		if local, ok := ui_pointer_local(ctx, id); ok {
			t.caret = ui_text_caret_at(font, string(buffer[:]), size, local.x - bb.x - pad + t.scroll)
		}
		t.blink = 0
	}
	moved := false
	if edit.backspace && t.caret > 0 {
		_, n := utf8.decode_last_rune(buffer[:t.caret])
		remove_range(buffer, t.caret - n, t.caret)
		t.caret -= n
		result.changed = true
	}
	if edit.delete && t.caret < len(buffer) {
		_, n := utf8.decode_rune(buffer[t.caret:])
		remove_range(buffer, t.caret, t.caret + n)
		result.changed = true
	}
	if edit.left && t.caret > 0 {
		_, n := utf8.decode_last_rune(buffer[:t.caret])
		t.caret -= n
		moved = true
	}
	if edit.right && t.caret < len(buffer) {
		_, n := utf8.decode_rune(buffer[t.caret:])
		t.caret += n
		moved = true
	}
	if edit.home {
		t.caret = 0
		moved = true
	}
	if edit.end {
		t.caret = len(buffer)
		moved = true
	}
	for insert in ([2]string{edit.text, edit.paste}) {
		for r in insert {
			// 换行、制表等控制字符和无效字节丢弃；超出上限时停在完整字符处。
			if r < 0x20 || r == 0x7f || r == utf8.RUNE_ERROR {
				continue
			}
			bytes, n := utf8.encode_rune(r)
			if len(buffer) + n > max_bytes {
				break
			}
			inject_at(buffer, t.caret, ..bytes[:n])
			t.caret += n
			result.changed = true
		}
	}
	if result.changed || moved {
		t.blink = 0
	}
	result.submitted = edit.submit
	return
}

// ------------------------------------------------------------------------------
// 测量
// ------------------------------------------------------------------------------

@(private)
ui_text_width :: proc(font: ^foster.MsdfFont, text: string, size: u16) -> f32 {
	return ui_measure_text(font, text, size, 0, 0).width
}

@(private)
ui_text_line_height :: proc(font: ^foster.MsdfFont, size: u16) -> f32 {
	if font == nil || font.Size <= 0 {
		return f32(size)*1.25
	}
	return font.LineHeight*f32(size)/font.Size
}

// 离 x（逻辑像素，相对文字起点）最近的字符边界的字节位置。
@(private)
ui_text_caret_at :: proc(font: ^foster.MsdfFont, text: string, size: u16, x: f32) -> int {
	best, best_distance := 0, abs(x)
	for _, offset in text {
		if offset == 0 {
			continue
		}
		distance := abs(ui_text_width(font, text[:offset], size) - x)
		if distance < best_distance {
			best, best_distance = offset, distance
		}
	}
	if distance := abs(ui_text_width(font, text, size) - x); distance < best_distance {
		best = len(text)
	}
	return best
}
