package ui

import "core:math"
import "core:mem"

import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   翻译 —— ui_translate
//   发射 —— ui_render / 嵌套裁剪 / MSDF 材质
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

// 结束布局并复用 ctx 内操作缓冲。调用者仍负责 BatcherClear/BatcherRender。
ui_draw :: proc(ctx: ^UI_Context, batcher: ^foster.Batcher) {
	ui_translate_into(ctx, ui_end(ctx), &ctx.ops)
	ui_render(ctx, batcher, &ctx.ops)
}

// UI 使用自己的像素变换，退出时恢复 batcher 状态；外部 scissor 作为根裁剪。
ui_render :: proc(ctx: ^UI_Context, batcher: ^foster.Batcher, ops: ^[dynamic]UI_Op) {
	if op_has_rounded(ops) {
		ui_ensure_corner_texture(ctx, batcher.GraphicsDevice)
	}
	foster.BatcherPushMatrixTRS(batcher, ctx.viewport_origin, {ctx.scale, ctx.scale}, 0, false)
	defer foster.BatcherPopMatrix(batcher)
	foster.BatcherPushSampler(batcher, foster.TextureSamplerMake(.Linear, .Clamp))
	defer foster.BatcherPopSampler(batcher)
	foster.BatcherPushBlend(batcher, foster.BlendModePremultiply)
	defer foster.BatcherPopBlend(batcher)
	foster.BatcherPushMode(batcher, .Normal)
	defer foster.BatcherPopMode(batcher)
	saved_texture := batcher.Texture
	defer {
		batcher.Texture = saved_texture
	}
	saved_has_material := batcher.HasMaterial
	defer {
		batcher.HasMaterial = saved_has_material
	}
	root := ui_pixel_clip(ctx, {0, 0, ctx.width, ctx.height})
	if batcher.HasScissor {
		root = ui_clip_intersection(root, batcher.Scissor)
	}
	foster.BatcherPushScissor(batcher, root)
	clip_depth := 1
	defer {
		for clip_depth > 0 {
			foster.BatcherPopScissor(batcher)
			clip_depth -= 1
		}
	}
	current_font := -1
	for &op in ops^ {
		switch op.kind {
		case .Quad:
			if batcher.Scissor.Width <= 0 || batcher.Scissor.Height <= 0 {
				continue
			}
			font_id := op.msdf ? op.font_id : -1
			if font_id != current_font {
				if current_font >= 0 {
					foster.BatcherPopMaterial(batcher)
					ui_material_boundary(batcher)
					current_font = -1
				}
				if font_id >= 0 {
					material := ui_msdf_material(ctx, font_id, batcher.GraphicsDevice)
					if material == nil {
						continue
					}
					foster.BatcherPushMaterial(batcher, material)
					ui_material_boundary(batcher)
					current_font = font_id
				}
			}
			if op.radius >= 1 && ctx.corner_texture_ok {
				ui_emit_rounded(batcher, &ctx.corner_texture, op)
			} else if op.texture != nil {
				foster.BatcherQuadTexture(batcher, op.texture,
					{op.x0, op.y0}, {op.x1, op.y0}, {op.x1, op.y1}, {op.x0, op.y1},
					{op.u0, op.v0}, {op.u1, op.v0}, {op.u1, op.v1}, {op.u0, op.v1}, op.color)
			} else {
				foster.BatcherPushMode(batcher, .Fill)
				foster.BatcherQuad(batcher, foster.Rect{op.x0, op.y0, op.x1 - op.x0, op.y1 - op.y0}, op.color)
				foster.BatcherPopMode(batcher)
			}
		case .Scissor_Start:
			clip := ui_pixel_clip(ctx, {op.clip_x, op.clip_y, op.clip_w, op.clip_h})
			foster.BatcherPushScissor(batcher, ui_clip_intersection(batcher.Scissor, clip))
			clip_depth += 1
		case .Scissor_End:
			if clip_depth > 1 {
				foster.BatcherPopScissor(batcher)
				clip_depth -= 1
			}
		}
	}
	if current_font >= 0 {
		foster.BatcherPopMaterial(batcher)
		ui_material_boundary(batcher)
	}
}

// Foster 当前按纹理/裁剪等合批，不比较材质；材质切换时显式建立批次边界。
// 保持相同 Layer 和插入顺序，也覆盖相同纹理在位图/MSDF 路径间切换。
@(private)
ui_material_boundary :: proc(b: ^foster.Batcher) {
	if len(b.Batches) > 0 {
		last := &b.Batches[len(b.Batches) - 1]
		last.IndexCount = len(b.Indices) - last.IndexStart
	}
	material := new(foster.Material)
	material^ = foster.MaterialClone(&b.Material)
	append(&b.Batches, foster.BatcherBatch{
		IndexStart = len(b.Indices), Material = material,
		Texture = b.Texture, Sampler = b.Sampler, Blend = b.Blend, Layer = b.Layer,
		Scissor = b.Scissor, HasScissor = b.HasScissor, Stencil = b.Stencil,
	})
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
	material: foster.Material,
	initialized: bool,
}

@(private)
ui_msdf_material :: proc(ctx: ^UI_Context, id: int, device: ^foster.GraphicsDevice) -> ^foster.Material {
	if id < 0 || id >= len(ctx.font_renderers) {
		return nil
	}
	renderer := &ctx.font_renderers[id]
	if !renderer.initialized {
		if device == nil || !device.Defaults.Initialized {
			return nil
		}
		renderer.material = foster.MaterialClone(&device.Defaults.MsdfMaterial)
		distance := ctx.fonts[id].DistanceRange
		uniform: [size_of(f32)]u8
		mem.copy(raw_data(uniform[:]), &distance, size_of(distance))
		foster.MaterialStageSetUniformBuffer(&renderer.material.Fragment, uniform[:], 0)
		renderer.initialized = true
	}
	return &renderer.material
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
		if w <= 0.01 || h <= 0.01 {
			return
		}
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
		u8(math.round(math.clamp(f32(c.r), 0, 1) * math.clamp(f32(c.a), 0, 1) * 255)),
		u8(math.round(math.clamp(f32(c.g), 0, 1) * math.clamp(f32(c.a), 0, 1) * 255)),
		u8(math.round(math.clamp(f32(c.b), 0, 1) * math.clamp(f32(c.a), 0, 1) * 255)),
		u8(math.round(math.clamp(f32(c.a), 0, 1) * 255)),
	}
}
