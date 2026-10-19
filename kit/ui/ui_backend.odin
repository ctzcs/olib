package ui

import "core:math"

import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import mat "olib:kit/rendering/material"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   翻译 —— ui_translate
//   发射 —— ui_render（写入 r2d.Render2D）/ 嵌套裁剪 / MSDF 材质
//   坐标为逻辑像素，ui_render 统一应用 viewport；颜色为预乘 alpha。

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
	// 已合成的逻辑坐标变换；零值 op 保持旧版轴对齐行为。
	transformed: bool,
	transform: foster.Matrix3x2,

	// Quad 有效字段
	x0, y0, x1, y1: f32, // 逻辑像素（左上/右下）
	u0, v0, u1, v1: f32, // UV（纯色时 0..1）
	color:          foster.Color,
	texture:        ^foster.Texture, // nil = 纯色
	msdf:           bool,
	font_id:        int,
	radius:         f32,             // 圆角半径（<1 走直角路径）

	// Scissor 有效字段
	clip_x, clip_y, clip_w, clip_h: f32,
}

// 把 clay 渲染命令翻译成操作流（分配于 context.allocator，调用方 delete）。
ui_translate :: proc(ctx: ^UI_Context, commands: clay.ClayArray(clay.RenderCommand)) -> [dynamic]UI_Op {
	ops: [dynamic]UI_Op
	ui_translate_into(ctx, commands, &ops)
	return ops
}

// 复用输出容量；命令、字体纹理指针仅在本帧内有效。
ui_translate_into :: proc(
	ctx: ^UI_Context,
	commands: clay.ClayArray(clay.RenderCommand),
	ops: ^[dynamic]UI_Op,
) {
	clear(ops)

	cmds := commands // 取址需要局部变量
	for i in 0..<cmds.length {
		cmd := clay.RenderCommandArray_Get(&cmds, i)
		if cmd == nil {
			continue
		}
		bb := cmd.boundingBox
		op_start := len(ops^)
		// defer 也覆盖九宫格等提前 continue 的路径。
		defer ui_visual_apply_ops(ctx, cmd.elementId, ops, op_start)

		#partial switch cmd.commandType {
		case .Rectangle:
			r := cmd.renderData.rectangle.cornerRadius
			radius := min(min(r.topLeft, r.topRight), min(r.bottomLeft, r.bottomRight))
			append(ops, UI_Op{
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
			if t > 0 {
				append(ops, quad(x0, y0, x1, y0 + t, col))
			}
			if bo > 0 {
				append(ops, quad(x0, y1 - bo, x1, y1, col))
			}
			if l > 0 {
				append(ops, quad(x0, y0, x0 + l, y1, col))
			}
			if r > 0 {
				append(ops, quad(x1 - r, y0, x1, y1, col))
			}
		case .Image:
			data := cmd.renderData.image
			texture := cast(^foster.Texture)(data.imageData)
			// 原生 Clay 图像声明未指定颜色时按无染色处理。
			tint := data.backgroundColor == clay.Color{} ? foster.White : ui_color(data.backgroundColor)
			append(ops, UI_Op{
				kind  = .Quad,
				x0 = bb.x, y0 = bb.y, x1 = bb.x + bb.width, y1 = bb.y + bb.height,
				color = tint,
				texture = texture,
				u1 = 1, v1 = 1,
			})
		case .Custom:
			// 只接受当前帧 image_pool 中对齐的指针，避免解释调用者的 customData。
			address := cast(uintptr)cmd.renderData.custom.customData
			base := cast(uintptr)raw_data(ctx.image_pool)
			if address < base {
				continue
			}
			offset := address - base
			if offset >= uintptr(ctx.image_len * size_of(UI_Image_Data)) || offset % size_of(UI_Image_Data) != 0 {
				continue
			}
			data := ctx.image_pool[int(offset / size_of(UI_Image_Data))]
			sub := data.sub
			if sub.Frame.Width <= 0 || sub.Frame.Height <= 0 {
				continue
			}
			if data.source_border > 0 {
				ui_translate_nine_slice(ops, bb, data, ui_color(cmd.renderData.custom.backgroundColor))
				continue
			}
			sx, sy := bb.width / sub.Frame.Width, bb.height / sub.Frame.Height
			append(ops, UI_Op{
				x0 = bb.x + sub.DrawCoords[0].x * sx, y0 = bb.y + sub.DrawCoords[0].y * sy,
				x1 = bb.x + sub.DrawCoords[2].x * sx, y1 = bb.y + sub.DrawCoords[2].y * sy,
				u0 = sub.TexCoords[0].x, v0 = sub.TexCoords[0].y,
				u1 = sub.TexCoords[2].x, v1 = sub.TexCoords[2].y,
				texture = sub.Texture, color = ui_color(cmd.renderData.custom.backgroundColor),
			})
		case .Text:
			data := cmd.renderData.text
			font := ui_font_of(ctx, int(data.fontId))
			if font == nil || font.Size <= 0 {
				continue
			}
			text := string(data.stringContents.chars[:data.stringContents.length])
			col := ui_color(data.textColor)
			texture := ui_texture_of(ctx, int(data.fontId))
			// 基线：boundingBox 顶 + 字体上行（clay 的文字盒从行顶开始）
			baseline := bb.y + font.Ascent * (f32(data.fontSize) / font.Size)
			scale := f32(data.fontSize) / font.Size
			atlas_w := f32(font.Image.Width)
			atlas_h := f32(font.Image.Height)
			if atlas_w <= 0 || atlas_h <= 0 {
				continue
			}

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
					append(ops, UI_Op{
						kind  = .Quad,
						x0 = gx, y0 = gy,
						x1 = gx + src.Width * scale, y1 = gy + src.Height * scale,
						u0 = src.X / atlas_w, v0 = src.Y / atlas_h,
						u1 = (src.X + src.Width) / atlas_w, v1 = (src.Y + src.Height) / atlas_h,
						color = col,
						texture = texture,
						font_id = int(data.fontId),
						msdf = ctx.font_renderers[int(data.fontId)].kind == .MSDF,
					})
					x += char.Advance * scale
				} else {
					x += font.Size * scale * 0.5
				}
				prev = code
			}
		case .ScissorStart:
			append(ops, UI_Op{
				kind = .Scissor_Start,
				clip_x = bb.x, clip_y = bb.y, clip_w = bb.width, clip_h = bb.height,
			})
		case .ScissorEnd:
			append(ops, UI_Op{kind = .Scissor_End})
		case:
		}
	}
}

@(private)
ui_translate_nine_slice :: proc(ops: ^[dynamic]UI_Op, bb: clay.BoundingBox,
	data: UI_Image_Data, color: foster.Color) {
	if bb.width <= 0 || bb.height <= 0 {
		return
	}
	b := min(data.border, min(bb.width, bb.height) * 0.5)
	x := [4]f32{bb.x, bb.x + b, bb.x + bb.width - b, bb.x + bb.width}
	y := [4]f32{bb.y, bb.y + b, bb.y + bb.height - b, bb.y + bb.height}
	u := [4]f32{0, data.source_border / data.sub.Frame.Width, 1 - data.source_border / data.sub.Frame.Width, 1}
	v := [4]f32{0, data.source_border / data.sub.Frame.Height, 1 - data.source_border / data.sub.Frame.Height, 1}
	for row in 0..<3 {
		for col in 0..<3 {
			if x[col + 1] <= x[col] || y[row + 1] <= y[row] {
				continue
			}
			append(ops, UI_Op{
				x0 = x[col], y0 = y[row], x1 = x[col + 1], y1 = y[row + 1],
				u0 = u[col], v0 = v[row], u1 = u[col + 1], v1 = v[row + 1],
				texture = data.sub.Texture, color = color,
			})
		}
	}
}

ui_ops_dispose :: proc(ops: ^[dynamic]UI_Op) {
	delete(ops^)
	ops^ = {}
}

// ------------------------------------------------------------------------------
// 发射
// ------------------------------------------------------------------------------

// 结束布局并复用 ctx 内操作缓冲。调用者仍负责 r2d.submit。
ui_draw :: proc(ctx: ^UI_Context, r: ^r2d.Render2D) {
	ui_translate_into(ctx, ui_end(ctx), &ctx.ops)
	ui_render(ctx, r, &ctx.ops)
}

// UI 使用自己的像素变换，退出时恢复 Render2D 的状态栈；外部 scissor 作为根裁剪。
ui_render :: proc(ctx: ^UI_Context, r: ^r2d.Render2D, ops: ^[dynamic]UI_Op) {
	if r.library == nil do return
	if op_has_rounded(ops) {
		ui_ensure_corner_texture(ctx, r.library.device)
	}
	r2d.push_matrix_trs(r, ctx.viewport_origin, {ctx.scale, ctx.scale}, 0, false)
	defer r2d.pop_matrix(r)
	r2d.push_sampler(r, foster.TextureSamplerMake(.Linear, .Clamp))
	defer r2d.pop_sampler(r)
	r2d.push_blend(r, foster.BlendModePremultiply)
	defer r2d.pop_blend(r)
	r2d.push_mode(r, .Normal)
	defer r2d.pop_mode(r)
	root := ui_pixel_clip(ctx, {0, 0, ctx.width, ctx.height})
	if r.has_scissor {
		root = ui_clip_intersection(root, r.scissor)
	}
	r2d.push_scissor(r, root)
	clip_depth := 1
	defer {
		for clip_depth > 0 {
			r2d.pop_scissor(r)
			clip_depth -= 1
		}
	}
	for &op in ops^ {
		switch op.kind {
		case .Quad:
			if r.scissor.Width <= 0 || r.scissor.Height <= 0 {
				continue
			}
			// MSDF 字形用内置 Text_Msdf 材质；其余（位图字形、图片、纯色、圆角）用默认材质。
			material: ^mat.Material
			if op.msdf {
				material = ui_msdf_material(ctx, op.font_id, r.library)
				if material == nil {
					continue
				}
			}
			if op.transformed {
				r2d.push_matrix_raw(r, ui_visual_pixel_matrix(ctx, op.transform), false)
			}
			if op.radius >= 1 && ctx.corner_texture_ok {
				ui_emit_rounded(r, &ctx.corner_texture, op)
			} else if op.texture != nil {
				r2d.quad_texture(r, op.texture,
					{op.x0, op.y0}, {op.x1, op.y0}, {op.x1, op.y1}, {op.x0, op.y1},
					{op.u0, op.v0}, {op.u1, op.v0}, {op.u1, op.v1}, {op.u0, op.v1}, op.color, material)
			} else {
				r2d.rect(r, foster.Rect{op.x0, op.y0, op.x1 - op.x0, op.y1 - op.y0}, op.color)
			}
			if op.transformed {
				r2d.pop_matrix(r)
			}
		case .Scissor_Start:
			clip := ui_pixel_clip(ctx, {op.clip_x, op.clip_y, op.clip_w, op.clip_h})
			r2d.push_scissor(r, ui_clip_intersection(r.scissor, clip))
			clip_depth += 1
		case .Scissor_End:
			if clip_depth > 1 {
				r2d.pop_scissor(r)
				clip_depth -= 1
			}
		}
	}
}

@(private)
ui_pixel_clip :: proc(ctx: ^UI_Context, rect: foster.Rect) -> foster.RectInt {
	x0 := int(math.floor(ctx.viewport_origin.x + rect.X * ctx.scale))
	y0 := int(math.floor(ctx.viewport_origin.y + rect.Y * ctx.scale))
	x1 := int(math.ceil(ctx.viewport_origin.x + (rect.X + rect.Width) * ctx.scale))
	y1 := int(math.ceil(ctx.viewport_origin.y + (rect.Y + rect.Height) * ctx.scale))
	return {x0, y0, max(0, x1 - x0), max(0, y1 - y0)}
}

@(private)
ui_clip_intersection :: proc(a, b: foster.RectInt) -> foster.RectInt {
	x, y := max(a.X, b.X), max(a.Y, b.Y)
	return {x, y, max(0, min(a.X + a.Width, b.X + b.Width) - x),
		max(0, min(a.Y + a.Height, b.Y + b.Height) - y)}
}

UI_Font_Kind :: enum {
	Bitmap,
	MSDF,
}

UI_Font_Renderer :: struct {
	kind: UI_Font_Kind,
	material: ^mat.Material, // MSDF 字体：内置 Text_Msdf 材质实例，归材质库所有
}

// 每种 MSDF 字体一个 Text_Msdf 材质实例，distance_range 取字体图集的距离范围；首次使用时在材质库里创建。
@(private)
ui_msdf_material :: proc(ctx: ^UI_Context, id: int, library: ^mat.Material_Library) -> ^mat.Material {
	if id < 0 || id >= len(ctx.font_renderers) {
		return nil
	}
	renderer := &ctx.font_renderers[id]
	if renderer.material == nil {
		material, reason := mat.material_create(library, mat.BUILTIN_TEXT)
		if reason != "" {
			return nil
		}
		_ = mat.material_set_number(material, mat.BUILTIN_TEXT, "distance_range", {ctx.fonts[id].DistanceRange, 0, 0, 0})
		renderer.material = material
	}
	return renderer.material
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
	if ctx.corner_texture_ok {
		return true
	}
	if device == nil {
		return false
	}

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
	if tex.Resource == nil {
		return false
	}

	ctx.corner_texture = tex
	ctx.corner_texture_ok = true
	return true
}

// 圆角矩形 9-patch：4 个角采圆盘对应象限（Normal 模式），5 个纯色矩形条（Render2D 自动用 Fill）。
// r 钳到半宽/半高（全圆/胶囊自动成立）。
@(private)
ui_emit_rounded :: proc(r: ^r2d.Render2D, disc: ^foster.Texture, op: UI_Op) {
	w := op.x1 - op.x0
	h := op.y1 - op.y0
	radius := min(op.radius, w * 0.5, h * 0.5)
	if radius < 1 { // 退化成直角
		r2d.rect(r, foster.Rect{op.x0, op.y0, w, h}, op.color)
		return
	}

	// 4 角（象限 UV：TL(0,0)-(0.5,0.5) TR/BR/BL 顺时针）
	corner :: proc(r: ^r2d.Render2D, disc: ^foster.Texture,
		px, py: f32, u0, v0: f32, size: f32, color: foster.Color,
	) {
		r2d.quad_texture(r, disc,
			foster.Vec2{px, py},
			foster.Vec2{px + size, py},
			foster.Vec2{px + size, py + size},
			foster.Vec2{px, py + size},
			{u0, v0}, {u0 + 0.5, v0}, {u0 + 0.5, v0 + 0.5}, {u0, v0 + 0.5},
			color)
	}
	corner(r, disc, op.x0, op.y0, 0, 0, radius, op.color)                       // TL
	corner(r, disc, op.x1 - radius, op.y0, 0.5, 0, radius, op.color)            // TR
	corner(r, disc, op.x1 - radius, op.y1 - radius, 0.5, 0.5, radius, op.color) // BR
	corner(r, disc, op.x0, op.y1 - radius, 0, 0.5, radius, op.color)            // BL

	// 5 个填充条（零尺寸自动跳过）
	bar :: proc(r: ^r2d.Render2D, x, y, w, h: f32, color: foster.Color) {
		if w <= 0.01 || h <= 0.01 {
			return
		}
		r2d.rect(r, foster.Rect{x, y, w, h}, color)
	}
	bar(r, op.x0 + radius, op.y0, w - 2 * radius, radius, op.color)                     // 上条
	bar(r, op.x0 + radius, op.y1 - radius, w - 2 * radius, radius, op.color)            // 下条
	bar(r, op.x0, op.y0 + radius, radius, h - 2 * radius, op.color)                     // 左条
	bar(r, op.x1 - radius, op.y0 + radius, radius, h - 2 * radius, op.color)            // 右条
	bar(r, op.x0 + radius, op.y0 + radius, w - 2 * radius, h - 2 * radius, op.color)    // 中心
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
		u8(math.round(math.clamp(f32(c.r), 0, 1) * math.clamp(f32(c.a), 0, 1) * 255)),
		u8(math.round(math.clamp(f32(c.g), 0, 1) * math.clamp(f32(c.a), 0, 1) * 255)),
		u8(math.round(math.clamp(f32(c.b), 0, 1) * math.clamp(f32(c.a), 0, 1) * 255)),
		u8(math.round(math.clamp(f32(c.a), 0, 1) * 255)),
	}
}
