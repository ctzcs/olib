package main

import foster "olib:foster"
import ui "olib:kit/ui"

// 演示用 ASCII 位图图集；产品可换成资产管线提供的位图或 MSDF 字体。
FONT_ATLAS_SIZE :: 48

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
