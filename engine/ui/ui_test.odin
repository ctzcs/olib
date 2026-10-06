// ui 包单元测试：真实 clay 布局 + 翻译 + 控件状态机（全 CPU，无 GPU）。
#+test
package ui

import "core:testing"

import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// ---------------------------------------------------------------------------
// 测试字体：手工构造 msdf 元数据（2 字符 + 1 对字距）
// ---------------------------------------------------------------------------

@(private)
make_test_font :: proc() -> ^foster.MsdfFont {
	font := new(foster.MsdfFont)
	font.Size = 32
	font.Ascent = 24
	font.Descent = -8
	font.LineHeight = 36
	font.Image = foster.Image{Width = 64, Height = 64}
	append(&font.Characters, foster.MsdfCharacter{
		Codepoint = 'A',
		SourceRect = foster.Rect{0, 0, 16, 20},
		Advance = 18,
		Offset = {0, 0},
	})
	append(&font.Characters, foster.MsdfCharacter{
		Codepoint = 'B',
		SourceRect = foster.Rect{16, 0, 14, 20},
		Advance = 15,
		Offset = {1, 0},
	})
	append(&font.Kerning, foster.MsdfKerning{First = 'A', Second = 'B', Advance = -2})
	return font
}

@(private)
dispose_test_font :: proc(font: ^foster.MsdfFont) {
	delete(font.Characters)
	delete(font.Kerning)
	delete(font.Image.Pixels)
	free(font)
}

// ---------------------------------------------------------------------------
// 测量
// ---------------------------------------------------------------------------

@(test)
measure_text_advances_and_kerning :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	// 单字符 16px（scale 0.5）：advance 18*0.5 = 9
	d := ui_measure_text(font, "A", 16, 0, 0)
	testing.expectf(t, math_abs(d.width - 9) < 1e-5, "A 宽: %v", d.width)
	testing.expectf(t, math_abs(d.height - 36*0.5) < 1e-5, "行高: %v", d.height)

	// AB：9 + (-2*0.5) + 7.5 = 15.5；字距 +2*1
	d2 := ui_measure_text(font, "AB", 16, 2, 0)
	testing.expectf(t, math_abs(d2.width - (9 - 1 + 7.5 + 2)) < 1e-4, "AB 宽: %v", d2.width)

	// 显式行高覆盖
	d3 := ui_measure_text(font, "A", 16, 0, 20)
	testing.expect(t, d3.height == 20)
}

@(private)
math_abs :: proc(v: f32) -> f32 {
	return v < 0 ? -v : v
}

// ---------------------------------------------------------------------------
// 字形四边形
// ---------------------------------------------------------------------------

@(test)
glyph_quads_advance_and_uv :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	quads: [dynamic]UI_Glyph_Quad
	defer delete(quads)
	end_x := ui_push_glyph_quads(font, "AB", 10, 30, 16, 0, {255, 255, 255, 255}, &quads)

	testing.expect(t, len(quads) == 2)
	// A：offset(0,0)，quad 从 (10,30) 起，uv 0..0.25 / 0..0.3125
	a := quads[0]
	testing.expect(t, a.x0 == 10 && a.y0 == 30)
	testing.expectf(t, math_abs(a.x1 - (10 + 16*0.5)) < 1e-5, "A 宽: %v", a.x1 - a.x0)
	testing.expect(t, a.u0 == 0 && a.v0 == 0)
	testing.expectf(t, math_abs(a.u1 - 16.0/64) < 1e-6 && math_abs(a.v1 - 20.0/64) < 1e-6, "A uv")

	// B：offset.x=1*0.5，起点 x = 10 + 9（A 推进）+ kerning(-1) + 0.5
	b := quads[1]
	testing.expectf(t, math_abs(b.x0 - (10 + 9 - 1 + 0.5)) < 1e-5, "B 起: %v", b.x0)
	// 笔尖返回：10 + 9 - 1 + 7.5
	testing.expectf(t, math_abs(end_x - (10 + 9 - 1 + 7.5)) < 1e-4, "笔尖: %v", end_x)
}

// ---------------------------------------------------------------------------
// 端到端：clay 布局 -> 命令 -> 翻译
// ---------------------------------------------------------------------------

@(test)
layout_translate_roundtrip :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	ctx: UI_Context
	if !ui_init(&ctx, 800, 600) {
		testing.expect(t, false, "ui_init")
		return
	}
	defer ui_dispose(&ctx)
	ui_register_font(&ctx, font, {}) // 纹理零值（CPU 测试不解码）

	ui_begin(&ctx, 1.0 / 60)
	theme := UI_THEME_DARK
	// 一个按钮 + 一个独立标签
	_ = ui_button(&ctx, &theme, "btn1", "AB")
	ops := ui_translate(&ctx, ui_end(&ctx))
	defer delete(ops)

	// 至少：按钮背景 1 + 文本 2 字形 = 3 个 Quad
	quads := 0
	for &op in ops {
		if op.kind == .Quad { quads += 1 }
	}
	testing.expectf(t, quads >= 3, "quad 数: %d", quads)
}

// ---------------------------------------------------------------------------
// 控件状态机
// ---------------------------------------------------------------------------

@(test)
button_click_requires_hover_and_edge :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	ui_register_font(&ctx, font, {})
	theme := UI_THEME_DARK

	clicked := false

	// 帧 1：指针在左上角（按钮布局未知，先跑一帧建立 id）
	ui_set_pointer(&ctx, 5, 5, false)
	ui_begin(&ctx, 1.0 / 60)
	clicked = ui_button(&ctx, &theme, "btnX", "OK")
	ui_end(&ctx)
	testing.expect(t, !clicked)

	// 找到按钮的实际包围盒（从布局命令反查），把指针放进去
	ui_set_pointer(&ctx, 5, 5, false)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_button(&ctx, &theme, "btnX", "OK")
	commands := clay.EndLayout()
	box := find_first_rect(commands, "btnX")
	if box == nil {
		testing.expect(t, false, "找不到按钮命令")
		return
	}

	// 预热帧：指针移到中心但未按（让 clay 的 hover 表按新指针位置重建）
	center_x := box.x + box.width * 0.5
	center_y := box.y + box.height * 0.5
	ui_set_pointer(&ctx, center_x, center_y, false)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_button(&ctx, &theme, "btnX", "OK")
	ui_end(&ctx)

	// 点击帧：按下边沿 -> 点击（诊断 hover 状态）
	ui_set_pointer(&ctx, center_x, center_y, true)
	ui_begin(&ctx, 1.0 / 60)
	clicked = ui_button(&ctx, &theme, "btnX", "OK")
	ui_end(&ctx)
	testing.expect(t, clicked)

	// 帧 3：持续按住（无边沿）-> 不再点击
	ui_begin(&ctx, 1.0 / 60)
	clicked = ui_button(&ctx, &theme, "btnX", "OK")
	ui_end(&ctx)
	testing.expect(t, !clicked)
}

@(private)
find_first_rect :: proc(commands: clay.ClayArray(clay.RenderCommand), id_label: string) -> ^clay.BoundingBox {
	cmds := commands
	for i in 0..<cmds.length {
		cmd := clay.RenderCommandArray_Get(&cmds, i)
		if cmd == nil { continue }
		if cmd.commandType == .Rectangle {
			return &cmd.boundingBox
		}
	}
	return nil
}

@(test)
toggle_flips_on_click :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	ui_register_font(&ctx, font, {})
	theme := UI_THEME_DARK

	value := false

	// 帧甲：建立布局
	ui_set_pointer(&ctx, 5, 5, false)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_toggle(&ctx, &theme, "tog1", &value)
	ui_end(&ctx)

	// 帧乙：点击 -> 翻转
	ui_set_pointer(&ctx, 5, 5, false)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_toggle(&ctx, &theme, "tog1", &value)
	commands := clay.EndLayout()
	box := find_first_rect(commands, "tog1")

	if box == nil {
		testing.expect(t, false, "找不到开关命令")
		return
	}
	tx := box.x + 4
	ty := box.y + 4

	// 预热帧（指针就位未按）后点击 -> 翻转
	ui_set_pointer(&ctx, tx, ty, false)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_toggle(&ctx, &theme, "tog1", &value)
	ui_end(&ctx)
	ui_set_pointer(&ctx, tx, ty, true)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_toggle(&ctx, &theme, "tog1", &value)
	ui_end(&ctx)
	testing.expect(t, value == true)

	// 松开帧 + 预热帧 + 再点击 -> 翻回
	ui_set_pointer(&ctx, tx, ty, false)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_toggle(&ctx, &theme, "tog1", &value)
	ui_end(&ctx)
	ui_set_pointer(&ctx, tx, ty, true)
	ui_begin(&ctx, 1.0 / 60)
	_ = ui_toggle(&ctx, &theme, "tog1", &value)
	ui_end(&ctx)
	testing.expect(t, value == false)
}
