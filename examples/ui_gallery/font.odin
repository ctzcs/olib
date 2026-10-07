package main

import "core:math"

import foster "olib:foster"
import ui "olib:kit/ui"

// 演示用 ASCII 位图图集；产品可换成资产管线提供的位图或 MSDF 字体。
FONT_ATLAS_SIZE :: 48

// 把解析环形距离编码到 RGB 三通道，验证与 MSDF 共用的 median/屏幕导数路径。
// 这是无需外部资产的着色器探针，不是字体生成器。
make_distance_probe :: proc(device: ^foster.GraphicsDevice) -> int {
	image := foster.ImageMake(32, 32)
	for y in 0..<32 {
		for x in 0..<32 {
			dx, dy := f32(x) + 0.5 - 16, f32(y) + 0.5 - 16
			d := 3 - math.abs(math.sqrt(dx * dx + dy * dy) - 10)
			v := u8(math.clamp(0.5 + d / 8, 0, 1) * 255)
			foster.ImageSetPixel(&image, x, y, {v, v, v, 255})
		}
	}
	distance_font = {
		Size = 32, Ascent = 32, LineHeight = 32, DistanceRange = 8,
		Image = image,
	}
	append(&distance_font.Characters, foster.MsdfCharacter{
		Codepoint = 'O', SourceRect = {0, 0, 32, 32}, Advance = 32, Offset = {0, -32},
	})
	distance_texture = foster.TextureFromImage(device, &image, "distance field probe")
	return ui.ui_register_font(&ctx, &distance_font, distance_texture, .MSDF)
}

bake_font :: proc() -> bool {
	ttf_paths := []string{
		font_path,
		"C:/Windows/Fonts/segoeui.ttf",
		"C:/Windows/Fonts/arial.ttf",
		"C:/Windows/Fonts/tahoma.ttf",
	}
	for path in ttf_paths {
		if len(path) == 0 {
			continue
		}
		source := foster.FontLoadFile(path)
		defer foster.FontDispose(&source)
		baked, texture, ok := ui.ui_font_bake(&game.GraphicsDevice, &source, FONT_ATLAS_SIZE, label = "ui demo font")
		if ok {
			font = baked
			font_texture = texture
			ui.ui_register_font(&ctx, &font, texture)
			return true
		}
	}
	return false
}
