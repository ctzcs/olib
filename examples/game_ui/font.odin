package main

import "core:os"

import ui "olib:kit/ui"
import foster "olib:foster"
import stbtt "olib:foster/internal/third_party"

// 演示用 ASCII 位图图集；产品可换成资产管线提供的位图或 MSDF 字体。
FONT_ATLAS_SIZE :: 48

bake_font :: proc() -> bool {
	ttf_paths := []string{
		font_path,
		"C:/Windows/Fonts/segoeui.ttf",
		"C:/Windows/Fonts/arial.ttf",
		"C:/Windows/Fonts/tahoma.ttf",
	}
	data: []u8
	for p in ttf_paths {
		d, err := os.read_entire_file_from_path(p, context.allocator)
		if err == nil {
			data = d
			break
		}
	}
	if data == nil {
		return false
	}
	defer delete(data)

	stb := stbtt.StbFontInit(data)
	if !stb.Valid {
		return false
	}

	scale := stbtt.StbFontScale(&stb, FONT_ATLAS_SIZE)
	ascent, descent, _gap := stbtt.StbFontMetrics(&stb)

	// shelf 打包 ASCII 32..126（48px：两行装进 1024x512）
	atlas_w := 1024
	atlas_h := 512
	atlas := make([]foster.Color, atlas_w * atlas_h)
	defer delete(atlas)

	x, y, row_h := 2, 2, 0
	for cp in 32..=126 {
		glyph := stbtt.StbFontGlyph(&stb, cp)
		w_i, h_i, advance, ox, oy, visible := stbtt.StbFontCharacter(&stb, glyph, scale)
		if visible {
			if x + w_i + 2 > atlas_w {
				x = 2
				y += row_h + 2
				row_h = 0
			}
			if h_i > row_h {
				row_h = h_i
			}

			bitmap := stbtt.StbFontRasterize(&stb, glyph, w_i, h_i, scale)
			for by in 0..<h_i {
				for bx in 0..<w_i {
					a := bitmap[by * w_i + bx]
					// 预乘 alpha：Foster Batcher 默认 BlendModePremultiply
					atlas[(y + by) * atlas_w + (x + bx)] = foster.Color{a, a, a, a}
				}
			}
			delete(bitmap)

			append(&font.Characters, foster.MsdfCharacter{
				Codepoint  = cp,
				SourceRect = foster.Rect{f32(x), f32(y), f32(w_i), f32(h_i)},
				Advance    = advance,
				Offset     = {ox, oy},
			})
			x += w_i + 2
		} else {
			// 空格等不可见字形：只有 advance
			append(&font.Characters, foster.MsdfCharacter{
				Codepoint  = cp,
				SourceRect = foster.Rect{0, 0, 0, 0},
				Advance    = advance,
			})
		}
		// 字距表（只记非零）
		for cp2 in 32..=126 {
			k := stbtt.StbFontKerning(&stb, cp, cp2, scale)
			if k != 0 {
				append(&font.Kerning, foster.MsdfKerning{First = cp, Second = cp2, Advance = k})
			}
		}
	}

	font.Size = f32(FONT_ATLAS_SIZE)
	font.Ascent = f32(ascent) * scale
	font.Descent = f32(descent) * scale
	font.LineHeight = (font.Ascent - font.Descent)
	font.Image.Width = atlas_w
	font.Image.Height = atlas_h

	pixel_buf: [dynamic]foster.Color
	append(&pixel_buf, ..atlas[:])
	image := foster.Image{
		Width  = atlas_w,
		Height = atlas_h,
		Pixels = pixel_buf,
	}
	texture := foster.TextureFromImage(&game.GraphicsDevice, &image, "ui demo font")
	if texture.Resource == nil {
		delete(pixel_buf)
		return false
	}

	font.Image.Pixels = pixel_buf
	font_texture = texture
	ui.ui_register_font(&ctx, &font, texture)
	return true
}
