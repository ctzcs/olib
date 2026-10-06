// ui:text —— msdf 字体测量与字形四边形生成。
//
// 测量按 msdf-atlas-gen 的图集元数据：Advance 缩放 fontSize/atlas.Size，
// 字距对查 Kerning 表；字形四边形给出笔尖推进布局（基线原点 + Offset），
// UV 取图集 SourceRect 归一化。
package ui

import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// 分区：
//   测量 —— ui_measure_text
//   字形四边形 —— UI_Glyph_Quad / ui_push_glyph_quads

// ------------------------------------------------------------------------------
// 测量
// ------------------------------------------------------------------------------

// 单行文本尺寸（clay 回调与自用）。
// lineHeight 配置为 0 时用字体默认行高；字距按字符间计数。
ui_measure_text :: proc "contextless" (
	font: ^foster.MsdfFont,
	text: string,
	font_size: u16,
	letter_spacing: u16,
	line_height: u16,
) -> clay.Dimensions {
	if font == nil || len(text) == 0 || font.Size <= 0 {
		return {0, 0}
	}
	scale := f32(font_size) / font.Size

	width: f32 = 0
	prev_codepoint: int = -1
	for r in text {
		if prev_codepoint >= 0 {
			width += ui_kerning(font, prev_codepoint, int(r)) * scale
		}
		char, ok := ui_find_character(font, int(r))
		if ok {
			width += char.Advance * scale
		} else {
			width += font.Size * scale * 0.5 // 未知字形给半宽
		}
		prev_codepoint = int(r)
	}
	if len(text) > 1 {
		width += f32(letter_spacing) * f32(len(text) - 1)
	}

	h := f32(line_height)
	if h <= 0 {
		h = font.LineHeight * scale
	}
	return {width, h}
}

// ------------------------------------------------------------------------------
// 字形四边形
// ------------------------------------------------------------------------------

// 一个字形的绘制数据：屏幕四点 + 图集 UV + 颜色（msdf 抗锯齿由渲染端
// 决定是否启用；v1 直采样图集）。
UI_Glyph_Quad :: struct {
	x0, y0: f32, // 左上（屏幕像素）
	x1, y1: f32, // 右下
	u0, v0: f32, // UV 左上
	u1, v1: f32, // UV 右下
	color:  foster.Color,
}

// 从笔尖 (pen_x, pen_y 为基线原点) 推进生成全部字形四边形。
// 返回推进后的笔尖 x。
ui_push_glyph_quads :: proc(
	font: ^foster.MsdfFont,
	text: string,
	pen_x, pen_y: f32,
	font_size: u16,
	letter_spacing: u16,
	color: foster.Color,
	out: ^[dynamic]UI_Glyph_Quad,
) -> f32 {
	if font == nil { return pen_x }
	atlas_w := f32(font.Image.Width)
	atlas_h := f32(font.Image.Height)
	if atlas_w <= 0 || atlas_h <= 0 { return pen_x }
	scale := f32(font_size) / font.Size

	x := pen_x
	prev_codepoint: int = -1
	for r in text {
		if prev_codepoint >= 0 {
			x += ui_kerning(font, prev_codepoint, int(r)) * scale
		}
		char, ok := ui_find_character(font, int(r))
		if ok {
			src := char.SourceRect
			gx := x + char.Offset[0] * scale
			gy := pen_y + char.Offset[1] * scale
			gw := src.Width * scale
			gh := src.Height * scale
			append(out, UI_Glyph_Quad{
				x0 = gx, y0 = gy,
				x1 = gx + gw, y1 = gy + gh,
				u0 = src.X / atlas_w, v0 = src.Y / atlas_h,
				u1 = (src.X + src.Width) / atlas_w, v1 = (src.Y + src.Height) / atlas_h,
				color = color,
			})
			x += char.Advance * scale
		} else {
			x += font.Size * scale * 0.5
		}
		if prev_codepoint >= 0 {
			x += f32(letter_spacing)
		}
		prev_codepoint = int(r)
	}
	return x
}

// ofoster 的 MsdfFontFindCharacter 未标 contextless（clay 测量回调是 C 调用约定），
// 这里自写等价查找（线性扫描，图集字符量级 ~百）。
@(private)
ui_find_character :: proc "contextless" (font: ^foster.MsdfFont, codepoint: int) -> (foster.MsdfCharacter, bool) {
	for c in font.Characters {
		if c.Codepoint == codepoint {
			return c, true
		}
	}
	return {}, false
}

ui_kerning :: proc "contextless" (font: ^foster.MsdfFont, first, second: int) -> f32 {
	for &k in font.Kerning {
		if k.First == first && k.Second == second {
			return k.Advance
		}
	}
	return 0
}
