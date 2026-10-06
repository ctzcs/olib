// ui:backend —— clay 渲染命令的翻译与发射。
//
// ui_translate 把 clay 的 RenderCommand 数组转成扁平的四边形操作流
//（纯 CPU，可单测）；ui_render 把操作流经 ofoster Batcher 画出去：
//   Rectangle/Border -> 纯色四边形（Border 展开为 4 条）
//   Image            -> 贴图四边形（imageData 即 ^foster.Texture）
//   Text             -> 每字形一个图集四边形
//   ScissorStart/End -> 翻译层保留并透传（v1 发射端暂不裁剪，见限制）
//
// v1 已知限制（后续增量）：圆角按直角绘制；scissor 不生效（ofoster
// Batcher 无裁剪钩子，接 DrawCommand 路径时补）；文本为图集直采样
//（msdf 抗锯齿需换 Msdf 材质路径）。
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
			append(&ops, UI_Op{
				kind  = .Quad,
				x0 = bb.x, y0 = bb.y, x1 = bb.x + bb.width, y1 = bb.y + bb.height,
				color = ui_color(cmd.renderData.rectangle.backgroundColor),
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
ui_render :: proc(batcher: ^foster.Batcher, ops: ^[dynamic]UI_Op) {
	for &op in ops^ {
		switch op.kind {
		case .Quad:
			tl := foster.Vec2{op.x0, op.y0}
			tr := foster.Vec2{op.x1, op.y0}
			br := foster.Vec2{op.x1, op.y1}
			bl := foster.Vec2{op.x0, op.y1}
			if op.texture != nil {
				foster.BatcherQuadTexture(batcher, op.texture, tl, tr, br, bl,
					{op.u0, op.v0}, {op.u1, op.v0}, {op.u1, op.v1}, {op.u0, op.v1},
					op.color)
			} else {
				foster.BatcherQuad(batcher, foster.Rect{
					op.x0, op.y0, op.x1 - op.x0, op.y1 - op.y0,
				}, op.color)
			}
		case .Scissor_Start, .Scissor_End:
			// v1 限制：不裁剪
		case:
		}
	}
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
