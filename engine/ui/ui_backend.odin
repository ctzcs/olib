// ui:backend —— clay 渲染命令的翻译与发射。
//
// ui_translate 把 clay 的 RenderCommand 数组转成扁平的四边形操作流
//（纯 CPU，可单测）；ui_render 把操作流经 ofoster Batcher 画出去：
//   Rectangle/Border -> 纯色四边形（圆角走圆盘 9-patch；Border 展开为 4 条）
//   Image            -> 贴图四边形（imageData 即 ^foster.Texture）
//   Text             -> 每字形一个图集四边形
//   ScissorStart/End -> 翻译层保留并透传（v1 发射端暂不裁剪，见限制）
//
// v1 已知限制（后续增量）：scissor 不生效（ofoster Batcher 无裁剪钩子，
// 接 DrawCommand 路径时补）；文本为图集直采样（msdf 抗锯齿需换 Msdf
// 材质路径）。
package ui

import "core:math"

import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// 分区：
//   翻译 —— ui_translate
//   发射 —— ui_render

// ------------------------------------------------------------------------------
// 翻译
// ------------------------------------------------------------------------------

UI_Op_Kind :: enum u8 {
	Quad, // 纯色或贴图四边形
	Scissor_Start,
	Scissor_End,
}

UI_Op :: struct {
	kind: UI_Op_Kind,

	// Quad 有效字段
	x0, y0, x1, y1: f32, // 屏幕像素（左上/右下）
	u0, v0, u1, v1: f32, // UV（纯色时 0..1）
	color:          foster.Color,
	texture:        ^foster.Texture, // nil = 纯色
	radius:         f32,             // 圆角半径（<1 走直角路径）

	// Scissor 有效字段
	clip_x, clip_y, clip_w, clip_h: f32,
}

// 把 clay 渲染命令翻译成操作流（分配于 context.allocator，调用方 delete）。
ui_translate :: proc(ctx: ^UI_Context, commands: clay.ClayArray(clay.RenderCommand)) -> [dynamic]UI_Op {
	ops: [dynamic]UI_Op
	reserve(&ops, 64)

	cmds := commands // 取址需要局部变量
	for i in 0..<cmds.length {
		cmd := clay.RenderCommandArray_Get(&cmds, i)
		if cmd == nil { continue }
		bb := cmd.boundingBox

		#partial switch cmd.commandType {
		case .Rectangle:
			r := cmd.renderData.rectangle.cornerRadius
			radius := min(min(r.topLeft, r.topRight), min(r.bottomLeft, r.bottomRight))
			append(&ops, UI_Op{
				kind  = .Quad,
				x0 = bb.x, y0 = bb.y, x1 = bb.x + bb.width, y1 = bb.y + bb.height,
				color = ui_color(cmd.renderData.rectangle.backgroundColor),
				radius = radius,
			})
		case .Border:
			// 四边展开（betweenChildren 的内部分隔线不在此路径）
			b := cmd.renderData.border
			w := b.width
			l, r, t, bo := f32(w.left), f32(w.right), f32(w.top), f32(w.bottom)
			col := ui_color(b.color)
			x0, y0 := bb.x, bb.y
			x1, y1 := bb.x + bb.width, bb.y + bb.height
			if t > 0 { append(&ops, quad(x0, y0, x1, y0 + t, col)) }
			if bo > 0 { append(&ops, quad(x0, y1 - bo, x1, y1, col)) }
			if l > 0 { append(&ops, quad(x0, y0, x0 + l, y1, col)) }
			if r > 0 { append(&ops, quad(x1 - r, y0, x1, y1, col)) }
		case .Image:
			data := cmd.renderData.image
			texture := cast(^foster.Texture)(data.imageData)
			append(&ops, UI_Op{
				kind  = .Quad,
				x0 = bb.x, y0 = bb.y, x1 = bb.x + bb.width, y1 = bb.y + bb.height,
				color = ui_color(data.backgroundColor),
				texture = texture,
			})
		case .Text:
			data := cmd.renderData.text
			font := ui_font_of(ctx, int(data.fontId))
			if font == nil { continue }
			text := string(data.stringContents.chars[:data.stringContents.length])
			col := ui_color(data.textColor)
			texture := ui_texture_of(ctx, int(data.fontId))
			// 基线：boundingBox 顶 + 字体上行（clay 的文字盒从行顶开始）
			baseline := bb.y + font.Ascent * (f32(data.fontSize) / font.Size)
			scale := f32(data.fontSize) / font.Size
			atlas_w := f32(font.Image.Width)
			atlas_h := f32(font.Image.Height)
			if atlas_w <= 0 || atlas_h <= 0 { continue }

			x := bb.x
			prev: int = -1
			for r in text {
				code := int(r)
				if prev >= 0 {
					x += ui_kerning(font, prev, code) * scale
					x += f32(data.letterSpacing)
				}
				char, ok := foster.MsdfFontFindCharacter(font, code)
				if ok {
					src := char.SourceRect
					gx := x + char.Offset[0] * scale
					gy := baseline + char.Offset[1] * scale
					append(&ops, UI_Op{
						kind  = .Quad,
						x0 = gx, y0 = gy,
						x1 = gx + src.Width * scale, y1 = gy + src.Height * scale,
						u0 = src.X / atlas_w, v0 = src.Y / atlas_h,
						u1 = (src.X + src.Width) / atlas_w, v1 = (src.Y + src.Height) / atlas_h,
						color = col,
						texture = texture,
					})
					x += char.Advance * scale
				} else {
					x += font.Size * scale * 0.5
				}
				prev = code
			}
		case .ScissorStart:
			append(&ops, UI_Op{
				kind = .Scissor_Start,
				clip_x = bb.x, clip_y = bb.y, clip_w = bb.width, clip_h = bb.height,
			})
		case .ScissorEnd:
			append(&ops, UI_Op{kind = .Scissor_End})
		case:
		}
	}
	return ops
}

ui_ops_dispose :: proc(ops: ^[dynamic]UI_Op) {
	delete(ops^)
	ops^ = {}
}

// ------------------------------------------------------------------------------
// 发射
// ------------------------------------------------------------------------------

// 把操作流画到 batcher（rect/图像/字形 -> Batcher 四边形）。
// scissor 操作当前跳过（见文件头的 v1 限制）。
//   - 圆角四边形：单位圆盘纹理 9-patch（4 角贴图 + 5 矩形填充）
//   - 纯色直角：.Fill 模式（着色器忽略采样——solid 路径会沿用当前绑定
//     纹理，混排在贴图四边形之后会错误采样字体图集而变透明）
//   - 文本/图像按缩小采样，统一 Linear（Batcher 默认 Nearest 会把 2 倍
//     缩放的笔画打成噪点）
ui_render :: proc(ctx: ^UI_Context, batcher: ^foster.Batcher, ops: ^[dynamic]UI_Op) {
	if op_has_rounded(ops) {
		ui_ensure_corner_texture(ctx, batcher.GraphicsDevice)
	}

	foster.BatcherPushSampler(
		batcher,
		foster.TextureSamplerMake(.Linear, .Clamp),
	)
	defer foster.BatcherPopSampler(batcher)

	fill_mode := false
	for &op in ops^ {
		switch op.kind {
		case .Quad:
			if op.radius >= 1 && ctx.corner_texture_ok {
				if fill_mode {
					foster.BatcherPopMode(batcher)
					fill_mode = false
				}
				ui_emit_rounded(batcher, &ctx.corner_texture, op)
			} else if op.texture != nil {
				if fill_mode {
					foster.BatcherPopMode(batcher)
					fill_mode = false
				}
				tl := foster.Vec2{op.x0, op.y0}
				tr := foster.Vec2{op.x1, op.y0}
				br := foster.Vec2{op.x1, op.y1}
				bl := foster.Vec2{op.x0, op.y1}
				foster.BatcherQuadTexture(batcher, op.texture, tl, tr, br, bl,
					{op.u0, op.v0}, {op.u1, op.v0}, {op.u1, op.v1}, {op.u0, op.v1},
					op.color)
			} else {
				if !fill_mode {
					foster.BatcherPushMode(batcher, .Fill)
					fill_mode = true
				}
				foster.BatcherQuad(batcher, foster.Rect{
					op.x0, op.y0, op.x1 - op.x0, op.y1 - op.y0,
				}, op.color)
			}
		case .Scissor_Start, .Scissor_End:
			// v1 限制：不裁剪
		case:
		}
	}
	if fill_mode {
		foster.BatcherPopMode(batcher)
	}
}

@(private)
op_has_rounded :: proc(ops: ^[dynamic]UI_Op) -> bool {
	for &op in ops^ {
		if op.kind == .Quad && op.radius >= 1 do return true
	}
	return false
}

// 圆盘纹理：预乘 alpha、1px 盒式过滤边缘（Batcher 默认预乘混合下无白边）。
@(private)
ui_ensure_corner_texture :: proc(ctx: ^UI_Context, device: ^foster.GraphicsDevice) -> bool {
	if ctx.corner_texture_ok { return true }
	if device == nil { return false }

	N :: 128
	pixels: [dynamic]foster.Color
	defer delete(pixels)
	reserve(&pixels, N * N)
	c := f32(N - 1) * 0.5
	r := f32(N) * 0.5
	for y in 0..<N {
		for x in 0..<N {
			dx := f32(x) + 0.5 - c
			dy := f32(y) + 0.5 - c
			d := math.sqrt(dx * dx + dy * dy)
			t := math.clamp(r - d + 0.5, 0, 1)
			a := u8(t * 255)
			append(&pixels, foster.Color{a, a, a, a})
		}
	}
	image := foster.Image{
		Width  = N,
		Height = N,
		Pixels = pixels,
	}
	tex := foster.TextureFromImage(device, &image, "ui corner disc")
	if tex.Resource == nil { return false }

	ctx.corner_texture = tex
	ctx.corner_texture_ok = true
	return true
}

// 圆角矩形 9-patch：4 个角采圆盘对应象限（.Normal 模式），5 个矩形条
// （.Fill 模式）。r 钳到半宽/半高（全圆/胶囊自动成立）。
@(private)
ui_emit_rounded :: proc(batcher: ^foster.Batcher, disc: ^foster.Texture, op: UI_Op) {
	w := op.x1 - op.x0
	h := op.y1 - op.y0
	r := min(op.radius, w * 0.5, h * 0.5)
	if r < 1 { // 退化成直角
		foster.BatcherPushMode(batcher, .Fill)
		foster.BatcherQuad(batcher, foster.Rect{op.x0, op.y0, w, h}, op.color)
		foster.BatcherPopMode(batcher)
		return
	}

	// 4 角（象限 UV：TL(0,0)-(0.5,0.5) TR/BR/BL 顺时针）
	corner :: proc(batcher: ^foster.Batcher, disc: ^foster.Texture,
		px, py: f32, u0, v0: f32, size: f32, color: foster.Color,
	) {
		foster.BatcherQuadTexture(batcher, disc,
			foster.Vec2{px, py},
			foster.Vec2{px + size, py},
			foster.Vec2{px + size, py + size},
			foster.Vec2{px, py + size},
			{u0, v0}, {u0 + 0.5, v0}, {u0 + 0.5, v0 + 0.5}, {u0, v0 + 0.5},
			color)
	}
	corner(batcher, disc, op.x0, op.y0, 0, 0, r, op.color)             // TL
	corner(batcher, disc, op.x1 - r, op.y0, 0.5, 0, r, op.color)       // TR
	corner(batcher, disc, op.x1 - r, op.y1 - r, 0.5, 0.5, r, op.color) // BR
	corner(batcher, disc, op.x0, op.y1 - r, 0, 0.5, r, op.color)       // BL

	// 5 个填充条（零尺寸自动跳过）
	rect :: proc(batcher: ^foster.Batcher, x, y, w, h: f32, color: foster.Color) {
		if w <= 0.01 || h <= 0.01 { return }
		foster.BatcherQuad(batcher, foster.Rect{x, y, w, h}, color)
	}
	foster.BatcherPushMode(batcher, .Fill)
	rect(batcher, op.x0 + r, op.y0, w - 2 * r, r, op.color)          // 上条
	rect(batcher, op.x0 + r, op.y1 - r, w - 2 * r, r, op.color)     // 下条
	rect(batcher, op.x0, op.y0 + r, r, h - 2 * r, op.color)         // 左条
	rect(batcher, op.x1 - r, op.y0 + r, r, h - 2 * r, op.color)     // 右条
	rect(batcher, op.x0 + r, op.y0 + r, w - 2 * r, h - 2 * r, op.color) // 中心
	foster.BatcherPopMode(batcher)
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

@(private)
quad :: proc(x0, y0, x1, y1: f32, color: foster.Color) -> UI_Op {
	return UI_Op{
		kind  = .Quad,
		x0 = x0, y0 = y0, x1 = x1, y1 = y1,
		color = color,
	}
}

@(private)
ui_color :: proc(c: clay.Color) -> foster.Color {
	return foster.Color{
		u8(math.round(f32(c.r) * 255)),
		u8(math.round(f32(c.g) * 255)),
		u8(math.round(f32(c.b) * 255)),
		u8(math.round(f32(c.a) * 255)),
	}
}
