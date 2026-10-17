package ui

import "core:math"

import foster "olib:foster"

// 分区：
//   字体烘焙 —— CPU 图集与字形表 / GPU 上传

// ------------------------------------------------------------------------------
// 字体烘焙
// ------------------------------------------------------------------------------

// 用 Foster 公开 Font API 烘焙预乘 alpha 位图字体；nil 字符集为 ASCII 32..126。
// 返回的 msdf 拥有 Image.Pixels、Characters 和 Kerning，须用 MsdfFontDispose 释放；
// texture 须由调用方 TextureDispose。源 Font 由调用方管理，可在烘焙后释放。
// 默认和自定义字符集均按 Unicode 码点查询字距。
ui_font_bake :: proc(
	device: ^foster.GraphicsDevice,
	font: ^foster.Font,
	size: f32,
	codepoints: []int = nil,
	label := "ui font",
) -> (msdf: foster.MsdfFont, texture: foster.Texture, ok: bool) {
	if device == nil {
		return {}, {}, false
	}
	msdf, ok = ui_font_bake_image(font, size, codepoints)
	if !ok {
		return {}, {}, false
	}
	texture = foster.TextureFromImage(device, &msdf.Image, label)
	if texture.Resource == nil {
		foster.MsdfFontDispose(&msdf)
		return {}, {}, false
	}
	return msdf, texture, true
}

// 独立于 GPU 的生成阶段，便于工具链与单测验证像素、度量和打包。
@(private)
ui_font_bake_image :: proc(
	font: ^foster.Font,
	size: f32,
	codepoints: []int = nil,
) -> (foster.MsdfFont, bool) {
	if font == nil || font.Disposed || size <= 0 || math.is_nan(size) || math.is_inf(size) {
		return {}, false
	}
	scale := foster.FontGetScale(font, size)
	if scale <= 0 || math.is_nan(scale) || math.is_inf(scale) {
		return {}, false
	}
	points := codepoints
	ascii: [95]int
	if points == nil {
		for &cp, i in ascii {
			cp = 32 + i
		}
		points = ascii[:]
	}

	glyphs := make([]foster.FontCharacter, len(points))
	defer delete(glyphs)
	atlas_w, atlas_h := 1024, 512
	for cp, i in points {
		glyphs[i] = foster.FontGetCharacter(font, cp, scale)
		for glyphs[i].Width + 4 > atlas_w {
			atlas_w *= 2
		}
	}

	msdf: foster.MsdfFont
	msdf.Size = size
	msdf.Ascent = f32(font.Ascent) * scale
	// FontMake 在 line gap 非正时把负 Descent 移到 LineGap。
	// 恢复这类字体的下降量；scale 按 em 映射，不能用于逆算度量高度。
	descent := font.Descent
	if descent == 0 && font.LineGap > 0 {
		descent = -font.LineGap
	}
	msdf.Descent = f32(descent) * scale
	msdf.LineHeight = msdf.Ascent - msdf.Descent

	x, y, row_h := 2, 2, 0
	for cp, i in points {
		ch := glyphs[i]
		entry := foster.MsdfCharacter{Codepoint = cp, Advance = ch.Advance}
		if ch.Visible {
			if x + ch.Width + 2 > atlas_w {
				x = 2
				y += row_h + 2
				row_h = 0
			}
			row_h = max(row_h, ch.Height)
			for y + ch.Height + 2 > atlas_h {
				atlas_h *= 2
			}
			entry.SourceRect = {f32(x), f32(y), f32(ch.Width), f32(ch.Height)}
			entry.Offset = ch.Offset
			x += ch.Width + 2
		}
		append(&msdf.Characters, entry)
		for cp2 in points {
			kerning := foster.FontGetKerning(font, cp, cp2, scale)
			if kerning != 0 {
				append(&msdf.Kerning, foster.MsdfKerning{First = cp, Second = cp2, Advance = kerning})
			}
		}
	}

	msdf.Image = foster.ImageMake(atlas_w, atlas_h)
	msdf.OwnsImage = true
	for ch, i in glyphs {
		if !ch.Visible {
			continue
		}
		pixels := make([]foster.Color, ch.Width * ch.Height)
		if !foster.FontGetPixels(font, ch, pixels, true) {
			delete(pixels)
			foster.MsdfFontDispose(&msdf)
			return {}, false
		}
		rect := msdf.Characters[i].SourceRect
		for by in 0..<ch.Height {
			for bx in 0..<ch.Width {
				msdf.Image.Pixels[(int(rect.Y) + by) * atlas_w + int(rect.X) + bx] = pixels[by * ch.Width + bx]
			}
		}
		delete(pixels)
	}
	return msdf, true
}
