package main

import "core:math"

import foster "olib:foster"

// 场景与图标均由几何生成，示例不依赖外部美术资产。
GOLD :: foster.Color{196, 167, 105, 255}
PAPER :: foster.Color{225, 218, 199, 255}
MUTED :: foster.Color{137, 148, 143, 255}
JADE :: foster.Color{94, 190, 167, 255}

line :: proc(a, b: foster.Vec2, width: f32, color: foster.Color) {
	foster.BatcherLine(&batcher, a, b, width, color)
}

ellipse :: proc(center: foster.Vec2, rx, ry: f32, color: foster.Color) {
	for i in 0..<48 {
		a := f32(i) * math.TAU / 48
		b := f32(i + 1) * math.TAU / 48
		foster.BatcherTriangle(&batcher, center,
			center + foster.Vec2{math.cos(a) * rx, math.sin(a) * ry},
			center + foster.Vec2{math.cos(b) * rx, math.sin(b) * ry}, color)
	}
}

ring :: proc(center: foster.Vec2, rx, ry, width: f32, color: foster.Color) {
	for i in 0..<64 {
		a := f32(i) * math.TAU / 64
		b := f32(i + 1) * math.TAU / 64
		line(center + foster.Vec2{math.cos(a) * rx, math.sin(a) * ry},
			center + foster.Vec2{math.cos(b) * rx, math.sin(b) * ry}, width, color)
	}
}

stone :: proc(x, y, w, d, height: f32, top: foster.Color) {
	a, b := foster.Vec2{x, y - d - height}, foster.Vec2{x + w, y - height}
	c, e := foster.Vec2{x, y + d - height}, foster.Vec2{x - w, y - height}
	foster.BatcherQuadPoints(&batcher, e, c, {x, y + d}, {x - w, y}, {25, 38, 40, 255})
	foster.BatcherQuadPoints(&batcher, c, b, {x + w, y}, {x, y + d}, {17, 29, 34, 255})
	foster.BatcherQuadPoints(&batcher, a, b, c, e, top)
	line(e, c, 1, {72, 90, 82, 255})
	line(c, b, 1, {54, 72, 69, 255})
}

pillar :: proc(x, y, height: f32) {
	ellipse({x + 36, y + 18}, 65, 19, {4, 10, 14, 130})
	stone(x, y, 33, 18, 12, {62, 79, 70, 255})
	stone(x, y - 10, 21, 12, height, {73, 87, 73, 255})
	stone(x, y - height - 10, 30, 17, 12, {81, 95, 78, 255})
	line({x - 11, y - 18}, {x - 11, y - height + 2}, 2, {55, 72, 64, 255})
	line({x + 9, y - 18}, {x + 9, y - height + 2}, 2, {9, 22, 25, 255})
	line({x - 2, y - height * 0.45}, {x + 10, y - height * 0.58}, 2, {9, 23, 25, 255})
}

torch :: proc(x, y: f32) {
	foster.BatcherCircle(&batcher, {x, y - 23}, 100, 40, {34, 23, 6, 52}, {0, 0, 0, 0})
	stone(x, y, 12, 7, 20, {63, 58, 44, 255})
	foster.BatcherTriangle(&batcher, {x - 9, y - 23}, {x + 7, y - 23},
		{x + 2 + math.sin(elapsed * 4) * 3, y - 55}, {222, 120, 40, 255})
	foster.BatcherTriangle(&batcher, {x - 4, y - 23}, {x + 4, y - 23},
		{x, y - 42}, {255, 223, 128, 255})
}

actor :: proc(at: foster.Vec2, enemy: bool) {
	x, y := at.x, at.y
	ellipse({x, y + 5}, 20, 8, {2, 8, 10, 155})
	cloak := enemy ? foster.Color{74, 87, 83, 255} : foster.Color{145, 60, 40, 255}
	foster.BatcherTriangle(&batcher, {x, y - 37}, {x - 18, y + 2}, {x + 14, y + 4}, cloak)
	foster.BatcherTriangle(&batcher, {x, y - 37}, {x + 14, y + 4}, {x + 5, y - 1}, {52, 37, 31, 255})
	foster.BatcherQuad(&batcher, foster.Rect{x - 6, y - 33, 13, 23}, {109, 125, 119, 255})
	foster.BatcherTriangle(&batcher, {x - 9, y - 34}, {x + 1, y - 50}, {x + 10, y - 34}, {154, 164, 147, 255})
	foster.BatcherQuad(&batcher, foster.Rect{x - 7, y - 35, 15, 5}, {32, 42, 41, 255})
	line({x + 13, y - 13}, {x + 29, y - 44}, 3, {198, 208, 185, 255})
	line({x + 12, y - 24}, {x + 24, y - 18}, 3, GOLD)
	line({x - 4, y - 7}, {x - 7, y + 6}, 5, {40, 42, 36, 255})
	line({x + 5, y - 7}, {x + 7, y + 6}, 5, {40, 42, 36, 255})
	if enemy {
		foster.BatcherQuad(&batcher, foster.Rect{x - 22, y - 64, 44, 4}, {29, 28, 26, 255})
		foster.BatcherQuad(&batcher, foster.Rect{x - 21, y - 63, 32, 2}, {155, 65, 54, 255})
	}
}

draw_world :: proc() {
	foster.BatcherQuad(&batcher, foster.Rect{0, 0, VIEW_W, VIEW_H},
		foster.Color{10, 23, 28, 255}, {16, 32, 34, 255}, {9, 17, 23, 255}, {6, 15, 22, 255})
	foster.BatcherCircle(&batcher, {606, 265}, 360, 64, {13, 31, 27, 55}, {0, 0, 0, 0})
	// 远处残墙与尖塔。
	for i in 0..<14 {
		x := f32(i) * 98 - 20
		y := 190 + f32((i * 37) % 6) * 12
		stone(x, y, 56, 25, 80 + f32((i * 19) % 70), {28, 48, 46, 255})
	}
	// 手工配色的菱形地砖与厚重平台边缘。
	for row in 0..<12 {
		for col in 0..<12 {
			x := 580 + f32(col - row) * 52
			y := 155 + f32(col + row) * 25
			v := u8((col * 17 + row * 11) % 12)
			stone(x, y, 51, 24, 12, {u8(33 + v), u8(49 + v), u8(47 + v), 255})
			if (col * 3 + row * 7) % 11 == 0 {
				line({x - 15, y - 14}, {x + 7, y - 5}, 1, {18, 32, 33, 255})
				line({x + 7, y - 5}, {x + 19, y - 9}, 1, {18, 32, 33, 255})
			}
		}
	}
	// 潮湿反光、祭坛、石阶。
	ellipse({571, 413}, 164, 78, {23, 45, 43, 255})
	ring({571, 413}, 166, 80, 3, {73, 99, 83, 255})
	ring({571, 413}, 145, 69, 1, {90, 124, 99, 255})
	ring({571, 413}, 103, 49, 2, {50, 106, 89, 255})
	for i in 0..<12 {
		a := f32(i) * math.TAU / 12
		p := foster.Vec2{571 + math.cos(a) * 126, 413 + math.sin(a) * 60}
		line(p + {-3, -5}, p + {3, 4}, 2, {77, 135, 104, 255})
	}
	pillar(345, 322, 116)
	pillar(583, 219, 145)
	pillar(819, 328, 108)
	stone(770, 486, 30, 16, 38, {57, 73, 63, 255})
	stone(802, 504, 24, 13, 15, {65, 77, 63, 255})
	stone(301, 457, 24, 13, 22, {66, 77, 62, 255})
	torch(362, 337)
	torch(804, 346)
	// 发光的封印门。
	foster.BatcherCircle(&batcher, {583, 228}, 84, 48, {11, 42, 35, 68}, {0, 0, 0, 0})
	foster.BatcherQuadPoints(&batcher, {557, 207}, {583, 172}, {609, 207}, {583, 239}, {56, 137, 111, 255})
	foster.BatcherQuadPoints(&batcher, {569, 207}, {583, 186}, {597, 207}, {583, 226}, {162, 222, 179, 255})
	actor({414, 391}, true)
	actor({721, 425}, true)
	ring(player + {0, 5}, 26, 12, 2, GOLD)
	actor(player, false)
	if math.abs(destination.x - player.x) + math.abs(destination.y - player.y) > 5 {
		ring(destination, 13, 6, 1, GOLD)
	}
	if effect_timer > 0 {
		ring(player, 40 + (0.8 - effect_timer) * 180, 20 + (0.8 - effect_timer) * 80,
			3, {90, 170, 125, 200})
	}
	// 苔草、碎石和空气中的余烬。
	for i in 0..<80 {
		x := f32((i * 137 + 31) % 1100) + 80
		y := f32((i * 89) % 390) + 270
		if i % 3 == 0 {
			line({x, y}, {x - 3, y - 9}, 2, {49, 71, 48, 255})
			line({x, y}, {x + 4, y - 7}, 1, {72, 87, 52, 255})
		} else {
			foster.BatcherQuad(&batcher, foster.Rect{x, y, 3, 2}, {55, 68, 58, 255})
		}
	}
	for i in 0..<30 {
		x := 270 + f32((i * 131) % 600)
		y := 170 + f32((i * 79) % 380) - math.sin(elapsed + f32(i)) * 6
		foster.BatcherQuad(&batcher, foster.Rect{x, y, 2, 2}, {110, 137, 84, 160})
	}
	// 下沿雾色，为快捷栏留出可读的暗部。
	foster.BatcherQuad(&batcher, foster.Rect{0, 610, VIEW_W, 190},
		foster.Color{0, 0, 0, 0}, {0, 0, 0, 0}, {5, 10, 14, 248}, {5, 10, 14, 248})
}

icon_sub :: proc(index: int) -> foster.Subtexture {
	return foster.SubtextureFromSource(&icons, {f32(index % 8) * 64, 0, 64, 64})
}

// 8 格图集：剑、盾、火焰、晶体、药剂、羽翼、头盔、遗迹小地图。
make_icons :: proc(device: ^foster.GraphicsDevice) {
	image := foster.ImageMake(512, 64)
	defer foster.ImageDispose(&image)
	colors := [8]foster.Color{{204, 207, 181, 255}, {128, 171, 182, 255},
		{222, 153, 71, 255}, {137, 175, 210, 255}, {193, 86, 70, 255},
		{111, 185, 146, 255}, {186, 163, 113, 255}, {100, 137, 118, 255}}
	for n in 0..<8 {
		for y in 0..<64 {
			for x in 0..<64 {
				xf, yf := f32(x) - 32, f32(y) - 32
				inside := false
				switch n {
				case 0:
					inside = (math.abs(xf + yf) < 5 && xf - yf > -10 && xf - yf < 45) ||
						(math.abs(xf - yf + 10) < 3 && math.abs(xf + yf) < 15) ||
						(math.abs(xf + yf) < 3 && xf - yf > -32 && xf - yf < -12)
				case 1:
					inside = math.abs(xf) < 20 && yf > -21 && yf < 23 - math.abs(xf) * 0.75
				case 2:
					inside = math.abs(xf + math.sin(yf * 0.1) * 5) < (yf + 27) * 0.4 && yf > -27 && yf < 19
				case 3:
					inside = math.abs(xf) * 1.4 + math.abs(yf) < 27
				case 4:
					inside = (xf * xf + (yf - 7) * (yf - 7) < 260) || (math.abs(xf) < 7 && yf > -23 && yf < 4)
				case 5:
					inside = math.abs(xf + yf * 0.6) < 10 && yf > -23 && yf < 20 &&
						(int(yf + 50) % 7 < 5 || math.abs(xf + yf * 0.6) < 2)
				case 6:
					inside = math.abs(xf) < 18 && yf > -23 + math.abs(xf) * 0.4 && yf < 23 &&
						!(yf > -4 && yf < 2 && math.abs(xf) > 3)
				case 7:
					inside = (math.abs(xf) < 2 && math.abs(yf) < 25) ||
						(math.abs(yf) < 2 && math.abs(xf) < 25) ||
						(math.abs(math.abs(xf) - 20) < 2 && math.abs(yf) < 9) ||
						(math.abs(math.abs(yf) - 20) < 2 && math.abs(xf) < 9)
				}
				if inside {
					color := colors[n]
					if xf > 1 {
						color.R = u8(f32(color.R) * 0.65)
						color.G = u8(f32(color.G) * 0.65)
						color.B = u8(f32(color.B) * 0.65)
					}
					foster.ImageSetPixel(&image, n * 64 + x, y, color)
				}
			}
		}
	}
	icons = foster.TextureFromImage(device, &image, "game item atlas")
}
