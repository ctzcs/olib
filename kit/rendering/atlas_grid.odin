// atlas:grid —— 等分网格图集来源（对位 DragonLib GridAtlasSource）。
//
// 无坐标文件，按 cellW×cellH 均匀切格，名字为 "r{行}_c{列}"（从 0 起），
// 适合简单 tilesheet。
package rendering

import "core:fmt"

import foster "olib:foster"

// 按等分网格产出矩形表（分配于 context.allocator，键随表存活；
// 注入图集后用 grid_rects_dispose 释放原件）。
grid_build_rects :: proc(atlas_width, atlas_height, cell_w, cell_h: int) -> ^map[string]foster.RectInt {
	rects := new(map[string]foster.RectInt)
	rects^ = make(map[string]foster.RectInt)
	cols := atlas_width / cell_w
	rows := atlas_height / cell_h
	for r in 0..<rows {
		for c in 0..<cols {
			key := fmt.aprintf("r%d_c%d", r, c, allocator = context.allocator)
			rects[key] = foster.RectInt{
				X = c * cell_w, Y = r * cell_h,
				Width = cell_w, Height = cell_h,
			}
		}
	}
	return rects
}

// 便捷入口：网格图（读 PNG -> 切格 -> 图集，CPU 形态，之后 atlas_upload）。
grid_atlas_load :: proc(atlas: ^Sprite_Atlas, png_path: string, cell_w, cell_h: int) -> bool {
	image := foster.ImageLoadFile(png_path)
	if image.Width <= 0 do return false

	rects := grid_build_rects(image.Width, image.Height, cell_w, cell_h)
	atlas_from_rects(atlas, image, rects^)
	grid_rects_dispose(rects)
	return true
}

// 释放 grid_build_rects 的产出（克隆进图集后的原件）。
grid_rects_dispose :: proc(rects: ^map[string]foster.RectInt) {
	for key in rects^ {
		delete(key, context.allocator)
	}
	delete(rects^)
	free(rects)
}
