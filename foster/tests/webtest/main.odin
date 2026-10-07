package webtest

// M2+M3+M4 验收程序:
//   M2 纹理上传 + Textured 管线 + 中文文本(stb 烘焙路径)
//   M3 键盘/鼠标/滚轮交互 + resize(OnResize 日志)
//   M4 存档持久化(OpenUserStorage → localStorage, 刷新页面计数递增)
//
// 桌面构建回归: odin build tests/webtest -collection:ofoster=src
// Web 构建:      odin build tests/webtest -collection:ofoster=src -target:js_wasm32 -o:speed -out:tests/webtest/webtest.wasm

import "core:fmt"
import "core:math"

import foster "ofoster:."
import stb "ofoster:internal/third_party"

// 全局而非 main 局部: web 下 main() 的栈帧在 Run 返回后会被复用
batcher: foster.Batcher
font: stb.StbFont
font_texture: foster.Texture
checker_texture: foster.Texture
glyphs: map[rune]GlyphQuad

atlas_w: i32 = 512
atlas_h: i32 = 256

TEXT :: "钢铁前线 OFoster 中文验证 0123456789"
FONT_BYTES :: #load("spike-font.ttf")

GlyphQuad :: struct {
	Sx, Sy, Sw, Sh: i32, // 图集内位置
	Xoff, Yoff:     f32, // 相对基线偏移
	Advance:        f32,
}

// 交互状态(M3)
visits: int
paused: bool
marker_x: f32 = 640
circle_scale: f32 = 1
hue_shift: bool
mouse_pos: foster.Vec2

main :: proc() {
	app: foster.App
	foster.InitApp(&app, foster.DefaultAppConfig("OFoster WebTest", 1280, 720))
	app.StartupProc = startup
	app.UpdateProc = update
	app.RenderProc = render
	app.Window.OnResize = on_resize
	foster.Run(&app)
}

startup :: proc(app: ^foster.App) {
	foster.BatcherInit(&batcher, &app.GraphicsDevice, "WebTestBatcher")
	bake_font(app)
	make_checker_texture(app)
	load_and_bump_visits(app)
	fmt.println("[webtest] startup complete")
}

on_resize :: proc(window: ^foster.Window) {
	fmt.println("[webtest] resized:", foster.Size(window))
}

// ---- M2: stb 字形烘焙 + 图集纹理(与 vehicles 的 spike 同路径) ----

bake_font :: proc(app: ^foster.App) {
	font = stb.StbFontInit(FONT_BYTES)
	if !font.Valid {
		fmt.println("[webtest] font init FAILED")
		return
	}
	scale := stb.StbFontScale(&font, 36)

	atlas := make([]u8, int(atlas_w * atlas_h))
	ax: i32 = 1
	ay: i32 = 1
	row_h: i32 = 0
	for r in TEXT {
		if r == ' ' {
			continue
		}
		glyph_index := stb.StbFontGlyph(&font, int(r))
		w, h, advance, xoff, yoff, visible := stb.StbFontCharacter(&font, glyph_index, scale)
		wi := i32(w)
		hi := i32(h)
		if !visible || wi <= 0 || hi <= 0 {
			continue
		}
		if ax + wi + 1 > atlas_w {
			ax = 1
			ay += row_h + 1
			row_h = 0
		}
		bitmap := stb.StbFontRasterize(&font, glyph_index, w, h, scale)
		for y: i32 = 0; y < hi; y += 1 {
			for x: i32 = 0; x < wi; x += 1 {
				atlas[int((ay + y) * atlas_w + (ax + x))] = bitmap[int(y * wi + x)]
			}
		}
		glyphs[r] = GlyphQuad{Sx = ax, Sy = ay, Sw = wi, Sh = hi, Xoff = xoff, Yoff = yoff, Advance = advance}
		ax += wi + 1
		if hi + 1 > row_h {
			row_h = hi + 1
		}
	}

	// 覆盖度 → RGBA(白 RGB + 覆盖度 alpha, 适配预乘混合)
	rgba := make([]u8, int(atlas_w * atlas_h) * 4)
	for i := 0; i < int(atlas_w * atlas_h); i += 1 {
		rgba[i * 4 + 0] = 255
		rgba[i * 4 + 1] = 255
		rgba[i * 4 + 2] = 255
		rgba[i * 4 + 3] = atlas[i]
	}
	foster.TextureInit(&font_texture, &app.GraphicsDevice, int(atlas_w), int(atlas_h), .Color, "FontAtlas")
	foster.TextureSetData(&font_texture, &rgba[0], len(rgba))
	fmt.println("[webtest] glyphs baked:", len(glyphs))
}

make_checker_texture :: proc(app: ^foster.App) {
	size := 64
	cell := 8
	rgba := make([]u8, size * size * 4)
	for y := 0; y < size; y += 1 {
		for x := 0; x < size; x += 1 {
			on := ((x / cell) + (y / cell)) % 2 == 0
			at := (y * size + x) * 4
			if on {
				rgba[at + 0], rgba[at + 1], rgba[at + 2], rgba[at + 3] = 120, 220, 160, 255
			} else {
				rgba[at + 0], rgba[at + 1], rgba[at + 2], rgba[at + 3] = 30, 60, 45, 255
			}
		}
	}
	foster.TextureInit(&checker_texture, &app.GraphicsDevice, size, size, .Color, "Checker")
	foster.TextureSetData(&checker_texture, &rgba[0], len(rgba))
}

// ---- M4: 存档持久化 ----

load_and_bump_visits :: proc(app: ^foster.App) {
	container := foster.OpenUserStorage(&app.FileSystem)
	visits = 0
	if foster.Exists(&container, "visits.txt") {
		text := foster.ReadAllText(&container, "visits.txt")
		parsed := 0
		valid := len(text) > 0
		for c in text {
			if c < '0' || c > '9' {
				valid = false
				break
			}
			parsed = parsed * 10 + int(c - '0')
		}
		if valid {
			visits = parsed
		}
	}
	visits += 1
	foster.WriteAllText(&container, "visits.txt", fmt.aprintf("%d", visits))
	fmt.println("[webtest] visits:", visits, "(刷新页面应递增)")
}

// ---- M3: 输入交互 ----

update :: proc(app: ^foster.App) {
	if app.Time.Frame > 0 && app.Time.Frame % 240 == 0 {
		fmt.println("[webtest] frame", app.Time.Frame, "elapsed", foster.TimeSecondsF(app.Time))
	}

	keyboard := &app.Input.State.Keyboard
	mouse := &app.Input.State.Mouse

	if foster.KeyboardPressed(keyboard, .Space) {
		paused = !paused
		fmt.println("[webtest] paused =", paused)
	}
	if foster.KeyboardDown(keyboard, .Left) {
		marker_x -= 4
	}
	if foster.KeyboardDown(keyboard, .Right) {
		marker_x += 4
	}
	if mouse.Wheel.Y != 0 {
		circle_scale = math.clamp(circle_scale + mouse.Wheel.Y * 0.1, 0.3, 3)
	}
	if foster.MousePressed(mouse, .Left) {
		hue_shift = !hue_shift
	}
	mouse_pos = foster.Vec2{mouse.Position.X, mouse.Position.Y}
}

// ---- 渲染 ----

render :: proc(app: ^foster.App) {
	target := foster.DrawableTargetFromWindow(&app.Window)
	foster.GraphicsDeviceClear(&app.GraphicsDevice, target, foster.Color{24, 28, 36, 255})

	t := foster.TimeSecondsF(app.Time)
	if paused {
		t = 0
	}
	pulse := 0.5 + 0.5 * math.sin(t * 1.5)

	foster.BatcherClear(&batcher)

	// M2: 纹理四边形(棋盘格, Textured 管线)
	foster.BatcherQuadTexture(&batcher, &checker_texture,
		foster.Vec2{80, 60}, foster.Vec2{300, 60}, foster.Vec2{300, 200}, foster.Vec2{80, 200},
		[2]f32{0, 0}, [2]f32{1, 0}, [2]f32{1, 1}, [2]f32{0, 1},
		foster.White)

	// M2: 中文文本(stb 图集)
	draw_text(60, 130, TEXT, foster.Color{230, 235, 240, 255})
	draw_text(60, 190, fmt.aprintf("OFoster %d", visits), foster.Color{255, 180, 90, 255})

	// M1 形状: 呼吸矩形 + 缩放圆(M3 滚轮控制)
	r := 60 + 120 * pulse
	g := 130 + 100 * (1 - pulse)
	foster.BatcherRect(&batcher, foster.Rect{80, 300, 220, 140}, foster.Color{u8(r), u8(g), 220, 255})
	foster.BatcherCircle(&batcher, foster.Vec2{460, 370}, 70 * circle_scale, 32, foster.Color{70, 170, 235, 255})
	foster.BatcherCircleLine(&batcher, foster.Vec2{460, 370}, 90 * circle_scale, 4, 48,
		hue_shift ? foster.Color{255, 140, 60, 255} : foster.Color{160, 120, 255, 255})

	// M3: 键盘控制的红标矩形
	foster.BatcherRect(&batcher, foster.Rect{marker_x - 16, 500, 32, 32}, foster.Color{235, 90, 90, 255})

	// M3: 鼠标位置十字线
	foster.BatcherLine(&batcher, foster.Vec2{mouse_pos[0] - 12, mouse_pos[1]}, foster.Vec2{mouse_pos[0] + 12, mouse_pos[1]}, 2, foster.Color{255, 255, 255, 200})
	foster.BatcherLine(&batcher, foster.Vec2{mouse_pos[0], mouse_pos[1] - 12}, foster.Vec2{mouse_pos[0], mouse_pos[1] + 12}, 2, foster.Color{255, 255, 255, 200})

	foster.BatcherRender(&batcher, target)
}

draw_text :: proc(x, y: f32, text: string, color: foster.Color) {
	tx := x
	for r in text {
		if r == ' ' {
			tx += 14
			continue
		}
		g, ok := glyphs[r]
		if !ok {
			continue
		}
		u0 := f32(g.Sx) / f32(atlas_w)
		v0 := f32(g.Sy) / f32(atlas_h)
		u1 := f32(g.Sx + g.Sw) / f32(atlas_w)
		v1 := f32(g.Sy + g.Sh) / f32(atlas_h)
		x0 := tx + g.Xoff
		y0 := y + g.Yoff
		x1 := x0 + f32(g.Sw)
		y1 := y0 + f32(g.Sh)
		foster.BatcherQuadTexture(&batcher, &font_texture,
			foster.Vec2{x0, y0}, foster.Vec2{x1, y0}, foster.Vec2{x1, y1}, foster.Vec2{x0, y1},
			[2]f32{u0, v0}, [2]f32{u1, v0}, [2]f32{u1, v1}, [2]f32{u0, v1},
			color)
		tx += g.Advance
	}
}
