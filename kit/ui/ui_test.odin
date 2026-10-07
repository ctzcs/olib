// ui 包单元测试：真实 clay 布局 + 翻译 + 控件状态机（全 CPU，无 GPU）。
#+test
package ui

import "core:sync"
import "core:testing"

import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// clay 的 context 是进程级全局：ui_init/ui_dispose 并发会段错误，测试串行化。
@(private)
clay_test_mutex: sync.Mutex

// ---------------------------------------------------------------------------
// 真实字体：CPU 烘焙与资源所有权（无 GPU）
// ---------------------------------------------------------------------------

@(test)
font_bake_ascii_atlas :: proc(t: ^testing.T) {
	data :: #load("../../foster/tests/port_regression/fonts/Abel-Regular.ttf")
	source := foster.FontMake(data)
	defer foster.FontDispose(&source)
	font, ok := ui_font_bake_image(&source, 48)
	if !testing.expect(t, ok) {
		return
	}
	defer foster.MsdfFontDispose(&font)
	testing.expect(t, len(font.Characters) == 95)
	testing.expect(t, font.Image.Width == 1024 && font.Image.Height == 512)
	testing.expect(t, font.OwnsImage && len(font.Image.Pixels) == 1024 * 512)
	a, found_a := foster.MsdfFontFindCharacter(&font, 'A')
	testing.expect(t, found_a && a.SourceRect.Width > 0 && a.SourceRect.Height > 0)
	space, found_space := foster.MsdfFontFindCharacter(&font, ' ')
	testing.expect(t, found_space && space.SourceRect == (foster.Rect{}) && space.Advance > 0)
	testing.expect(t, font.Descent < 0 && font.LineHeight == font.Ascent - font.Descent)
	visible := false
	for pixel in font.Image.Pixels {
		testing.expect(t, pixel.R == pixel.A && pixel.G == pixel.A && pixel.B == pixel.A)
		visible = visible || pixel.A > 0
	}
	testing.expect(t, visible)
}

@(test)
font_bake_default_and_explicit_ascii_have_codepoint_kerning :: proc(t: ^testing.T) {
	data :: #load("../../foster/tests/port_regression/fonts/Abel-Regular.ttf")
	source := foster.FontMake(data)
	defer foster.FontDispose(&source)
	points: [95]int
	for &cp, i in points {
		cp = 32 + i
	}
	default_font, default_ok := ui_font_bake_image(&source, 48)
	defer foster.MsdfFontDispose(&default_font)
	explicit_font, explicit_ok := ui_font_bake_image(&source, 48, points[:])
	defer foster.MsdfFontDispose(&explicit_font)
	if !testing.expect(t, default_ok && explicit_ok) {
		return
	}
	testing.expect(t, len(default_font.Kerning) == len(explicit_font.Kerning))
	scale := foster.FontGetScale(&source, 48)
	nonzero_pairs := 0
	for first in points {
		for second in points {
			expected := foster.FontGetKerning(&source, first, second, scale)
			testing.expect(t, foster.MsdfFontGetKerning(&default_font, first, second) == expected)
			testing.expect(t, foster.MsdfFontGetKerning(&explicit_font, first, second) == expected)
			if expected != 0 {
				nonzero_pairs += 1
			}
		}
	}
	testing.expect(t, nonzero_pairs > 0)
	testing.expect(t, len(default_font.Kerning) == nonzero_pairs)
}

@(test)
font_bake_custom_charset_grows_atlas :: proc(t: ^testing.T) {
	data :: #load("../../foster/tests/port_regression/fonts/Abel-Regular.ttf")
	source := foster.FontMake(data)
	defer foster.FontDispose(&source)
	points: [95]int
	for &cp, i in points {
		cp = 32 + i
	}
	font, ok := ui_font_bake_image(&source, 192, points[:])
	if !testing.expect(t, ok) {
		return
	}
	defer foster.MsdfFontDispose(&font)
	testing.expect(t, len(font.Characters) == len(points))
	testing.expect(t, font.Image.Height > 512)
	for ch in font.Characters {
		r := ch.SourceRect
		testing.expect(t, r.X >= 0 && r.Y >= 0)
		testing.expect(t, r.X + r.Width <= f32(font.Image.Width))
		testing.expect(t, r.Y + r.Height <= f32(font.Image.Height))
	}
}

@(test)
font_bake_rejects_unusable_inputs :: proc(t: ^testing.T) {
	_, ok := ui_font_bake_image(nil, 48)
	testing.expect(t, !ok)
	empty: foster.Font
	_, ok = ui_font_bake_image(&empty, 48)
	testing.expect(t, !ok)
	_, ok = ui_font_bake_image(&empty, 0)
	testing.expect(t, !ok)
	_, _, ok = ui_font_bake(nil, &empty, 48)
	testing.expect(t, !ok)
}

// ---------------------------------------------------------------------------
// 测试字体：手工构造 msdf 元数据（2 字符 + 1 对字距）
// ---------------------------------------------------------------------------

@(private)
make_test_font :: proc() -> ^foster.MsdfFont {
	font := new(foster.MsdfFont)
	font.Size = 32
	font.Ascent = 24
	font.Descent = -8
	font.LineHeight = 36
	font.Image = foster.Image{Width = 64, Height = 64}
	append(&font.Characters, foster.MsdfCharacter{
		Codepoint = 'A',
		SourceRect = foster.Rect{0, 0, 16, 20},
		Advance = 18,
		Offset = {0, 0},
	})
	append(&font.Characters, foster.MsdfCharacter{
		Codepoint = 'B',
		SourceRect = foster.Rect{16, 0, 14, 20},
		Advance = 15,
		Offset = {1, 0},
	})
	append(&font.Kerning, foster.MsdfKerning{First = 'A', Second = 'B', Advance = -2})
	return font
}

@(private)
dispose_test_font :: proc(font: ^foster.MsdfFont) {
	delete(font.Characters)
	delete(font.Kerning)
	delete(font.Image.Pixels)
	free(font)
}

// ---------------------------------------------------------------------------
// 测量
// ---------------------------------------------------------------------------

@(test)
measure_text_advances_and_kerning :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	// 单字符 16px（scale 0.5）：advance 18*0.5 = 9
	d := ui_measure_text(font, "A", 16, 0, 0)
	testing.expectf(t, math_abs(d.width - 9) < 1e-5, "A 宽: %v", d.width)
	testing.expectf(t, math_abs(d.height - 36*0.5) < 1e-5, "行高: %v", d.height)

	// AB：9 + (-2*0.5) + 7.5 = 15.5；字距 +2*1
	d2 := ui_measure_text(font, "AB", 16, 2, 0)
	testing.expectf(t, math_abs(d2.width - (9 - 1 + 7.5 + 2)) < 1e-4, "AB 宽: %v", d2.width)

	// 显式行高覆盖
	d3 := ui_measure_text(font, "A", 16, 0, 20)
	testing.expect(t, d3.height == 20)
}

@(private)
math_abs :: proc(v: f32) -> f32 {
	return v < 0 ? -v : v
}

// ---------------------------------------------------------------------------
// 字形四边形
// ---------------------------------------------------------------------------

@(test)
glyph_quads_advance_and_uv :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)

	quads: [dynamic]UI_Glyph_Quad
	defer delete(quads)
	end_x := ui_push_glyph_quads(font, "AB", 10, 30, 16, 0, {255, 255, 255, 255}, &quads)

	testing.expect(t, len(quads) == 2)
	// A：offset(0,0)，quad 从 (10,30) 起，uv 0..0.25 / 0..0.3125
	a := quads[0]
	testing.expect(t, a.x0 == 10 && a.y0 == 30)
	testing.expectf(t, math_abs(a.x1 - (10 + 16*0.5)) < 1e-5, "A 宽: %v", a.x1 - a.x0)
	testing.expect(t, a.u0 == 0 && a.v0 == 0)
	testing.expectf(t, math_abs(a.u1 - 16.0/64) < 1e-6 && math_abs(a.v1 - 20.0/64) < 1e-6, "A uv")

	// B：offset.x=1*0.5，起点 x = 10 + 9（A 推进）+ kerning(-1) + 0.5
	b := quads[1]
	testing.expectf(t, math_abs(b.x0 - (10 + 9 - 1 + 0.5)) < 1e-5, "B 起: %v", b.x0)
	// 笔尖返回：10 + 9 - 1 + 7.5
	testing.expectf(t, math_abs(end_x - (10 + 9 - 1 + 7.5)) < 1e-4, "笔尖: %v", end_x)
}

// ---------------------------------------------------------------------------
// 端到端：clay 布局 -> 命令 -> 翻译
// ---------------------------------------------------------------------------

@(test)
layout_translate_roundtrip :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)

	font := make_test_font()
	defer dispose_test_font(font)

	ctx: UI_Context
	if !ui_init(&ctx, 800, 600) {
		testing.expect(t, false, "ui_init")
		return
	}
	defer ui_dispose(&ctx)
	ui_register_font(&ctx, font, {}) // 纹理零值（CPU 测试不解码）

	ui_begin(&ctx, 1.0 / 60)
	theme := UI_THEME_DARK
	// 一个按钮 + 一个独立标签
	_ = ui_button(&ctx, &theme, "btn1", "AB")
	ops := ui_translate(&ctx, ui_end(&ctx))
	defer delete(ops)

	// 至少：按钮背景 1 + 文本 2 字形 = 3 个 Quad
	quads := 0
	for &op in ops {
		if op.kind == .Quad {
			quads += 1
		}
	}
	testing.expectf(t, quads >= 3, "quad 数: %d", quads)
}

// ---------------------------------------------------------------------------
// 控件状态机
// ---------------------------------------------------------------------------

// 真正按帧驱动交互；无字体时按钮仍有 80px 最小宽度和 20px padding 高度。
@(private)
button_frame :: proc(ctx: ^UI_Context, x, y: f32, down: bool, options: UI_Widget_Options = {}) -> bool {
	ui_set_pointer(ctx, x, y, down)
	ui_begin(ctx, 1.0 / 60)
	theme := UI_THEME_DARK
	clicked := ui_button(ctx, &theme, "button", "", options)
	ui_end(ctx)
	return clicked
}

@(test)
button_release_capture_cancel_and_disabled :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	button_frame(&ctx, 5, 5, false)
	testing.expect(t, !button_frame(&ctx, 5, 5, true))
	testing.expect(t, ctx.active_id != 0)
	testing.expect(t, !button_frame(&ctx, 5, 5, true))
	testing.expect(t, button_frame(&ctx, 5, 5, false))
	testing.expect(t, ctx.active_id == 0 && ui_input_capture(&ctx).pointer)
	button_frame(&ctx, 5, 5, true)
	testing.expect(t, !button_frame(&ctx, 500, 500, false), "outside release cancels")
	button_frame(&ctx, 500, 500, true)
	testing.expect(t, !button_frame(&ctx, 5, 5, false), "outside press cannot activate")
	testing.expect(t, !button_frame(&ctx, 5, 5, true, {disabled = true}))
	testing.expect(t, !button_frame(&ctx, 5, 5, false, {disabled = true}))
	testing.expect(t, ui_input_capture(&ctx).pointer, "disabled still blocks world")
	testing.expect(t, button_frame(&ctx, 5, 5, true, {trigger = .Press}))
	testing.expect(t, !button_frame(&ctx, 5, 5, false, {trigger = .Press}))
}

@(test)
toggle_flips_only_after_confirmation :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	theme := UI_THEME_DARK
	value := false
	for down, i in ([5]bool{false, true, false, true, false}) {
		ui_set_pointer(&ctx, 5, 5, down)
		ui_begin(&ctx, 1.0 / 60)
		ui_toggle(&ctx, &theme, "toggle", &value)
		ui_end(&ctx)
		testing.expect(t, value == (i == 2 || i == 3))
	}
}

@(test)
unicode_spacing_and_glyph_positions_agree :: proc(t: ^testing.T) {
	font := make_test_font()
	defer dispose_test_font(font)
	font.Characters[0].Codepoint = '中'
	font.Characters[1].Codepoint = '文'
	d := ui_measure_text(font, "中文", 16, 2, 0)
	testing.expectf(t, d.width == 18.5, "Unicode width: %v", d.width)
	testing.expect(t, ui_measure_text(font, "中", 16, 2, 0).width == 9)
	quads: [dynamic]UI_Glyph_Quad
	defer delete(quads)
	end := ui_push_glyph_quads(font, "中文", 0, 0, 16, 2, {255, 255, 255, 255}, &quads)
	testing.expect(t, end == d.width)
	testing.expect(t, quads[1].x0 == 11.5, "spacing precedes second glyph")
}

@(test)
image_uv_and_trimmed_atlas_frame :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	tex := foster.Texture{Width = 128, Height = 64}
	commands := [1]clay.RenderCommand{{commandType = .Image,
		boundingBox = {0, 0, 40, 40},
		renderData = {image = {imageData = &tex}}}}
	ops := ui_translate(&ctx, {capacity = 1, length = 1, internalArray = raw_data(commands[:])})
	defer delete(ops)
	testing.expect(t, ops[0].u0 == 0 && ops[0].v0 == 0 && ops[0].u1 == 1 && ops[0].v1 == 1)
	testing.expect(t, ops[0].color == foster.White)
	ui_begin(&ctx, 1.0 / 60)
	sub := foster.SubtextureMake(&tex, {32, 16, 16, 16}, {-4, -8, 32, 32})
	ui_image(&ctx, sub, 64, 64)
	ui_translate_into(&ctx, ui_end(&ctx), &ops)
	found := false
	for op in ops {
		if op.texture == &tex {
			found = true
			testing.expect(t, op.x0 == 8 && op.y0 == 16 && op.x1 == 40 && op.y1 == 48)
			testing.expect(t, op.u0 == 0.25 && op.u1 == 0.375 && op.v0 == 0.25 && op.v1 == 0.5)
		}
	}
	testing.expect(t, found)
}

@(test)
nested_scissor_and_scaled_batch_state :: proc(t: ^testing.T) {
	ctx := UI_Context{width = 200, height = 200, scale = 2, viewport_origin = {10, 20}}
	batch: foster.Batcher
	foster.BatcherInit(&batch, nil)
	defer foster.BatcherDispose(&batch)
	foster.BatcherPushScissor(&batch, {0, 0, 500, 500})
	foster.BatcherPushMatrixPosition(&batch, {100, 100})
	saved_matrix := batch.Matrix
	ops := make([dynamic]UI_Op)
	defer delete(ops)
	append(&ops,
		UI_Op{kind = .Scissor_Start, clip_x = 10, clip_y = 10, clip_w = 50, clip_h = 50},
		UI_Op{kind = .Scissor_Start, clip_x = 40, clip_y = 0, clip_w = 50, clip_h = 40},
		quad(0, 0, 100, 100, {255, 255, 255, 255}),
		UI_Op{kind = .Scissor_End},
		quad(1, 1, 5, 5, {255, 255, 255, 255}),
		UI_Op{kind = .Scissor_End},
		quad(1, 1, 5, 5, {255, 255, 255, 255}))
	ui_render(&ctx, &batch, &ops)
	testing.expect(t, len(batch.Batches) == 3)
	testing.expect(t, batch.Batches[0].Scissor == foster.RectInt{90, 40, 40, 60})
	testing.expect(t, batch.Batches[1].Scissor == foster.RectInt{30, 40, 100, 100})
	testing.expect(t, batch.Batches[2].Scissor == foster.RectInt{10, 20, 400, 400})
	testing.expect(t, batch.Vertices[0].Pos == foster.Vec2{10, 20})
	testing.expect(t, batch.Scissor == foster.RectInt{0, 0, 500, 500} && batch.HasScissor)
	testing.expect(t, batch.Matrix == saved_matrix && len(batch.ScissorStack) == 1)
	empty := ui_clip_intersection({0, 0, 10, 10}, {30, 30, 10, 10})
	testing.expect(t, empty.Width == 0 && empty.Height == 0)
}

@(test)
nine_slice_preserves_corners_and_draws_behind_children :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	tex := foster.Texture{Width = 128, Height = 128}
	for size in ([2]foster.Vec2{{240, 50}, {20, 12}}) {
		ui_begin(&ctx, 1.0 / 60)
		decl := ui_nine_slice_decl(&ctx, &tex, 32, 12)
		decl.layout.sizing = {width = clay.SizingFixed(size.x), height = clay.SizingFixed(size.y)}
		if clay.UI()(decl) {
			if clay.UI()(clay.ElementDeclaration{
				layout = {sizing = {width = clay.SizingFixed(2), height = clay.SizingFixed(2)}},
				backgroundColor = {1, 0, 0, 1},
			}) {}
		}
		ops := ui_translate(&ctx, ui_end(&ctx))
		defer delete(ops)
		testing.expect(t, len(ops) > 1)
		testing.expect(t, ops[0].texture == &tex && ops[len(ops)-1].texture == nil,
			"background must precede child content")
		testing.expect(t, ops[0].x1 - ops[0].x0 == min(12, size.y * 0.5))
		testing.expect(t, ops[0].u1 == 0.25 && ops[0].v1 == 0.25)
		area: f32
		for op in ops {
			if op.texture != &tex {
				continue
			}
			testing.expect(t, op.x1 > op.x0 && op.y1 > op.y0, "small widgets cannot invert slices")
			testing.expect(t, op.x0 >= 0 && op.y0 >= 0 && op.x1 <= size.x && op.y1 <= size.y)
			testing.expect(t, op.u0 >= 0 && op.v0 >= 0 && op.u1 <= 1 && op.v1 <= 1)
			area += (op.x1 - op.x0) * (op.y1 - op.y0)
		}
		testing.expect(t, area == size.x * size.y, "slices must cover the requested rectangle")
	}
}

@(test)
msdf_batches_separate_even_with_same_texture :: proc(t: ^testing.T) {
	ctx := UI_Context{width = 100, height = 100, scale = 1}
	defer delete(ctx.font_renderers)
	renderer := UI_Font_Renderer{kind = .MSDF, initialized = true}
	foster.MaterialInit(&renderer.material)
	foster.MaterialStageSetUniformBuffer(&renderer.material.Fragment, []u8{1, 2, 3, 4}, 0)
	defer foster.MaterialDispose(&renderer.material)
	append(&ctx.font_renderers, renderer)
	batch: foster.Batcher
	foster.BatcherInit(&batch, nil)
	defer foster.BatcherDispose(&batch)
	tex: foster.Texture
	ops := make([dynamic]UI_Op)
	defer delete(ops)
	append(&ops,
		UI_Op{texture = &tex, x1 = 10, y1 = 10},
		UI_Op{texture = &tex, x1 = 10, y1 = 10, msdf = true},
		UI_Op{texture = &tex, x1 = 10, y1 = 10})
	ui_render(&ctx, &batch, &ops)
	testing.expect(t, len(batch.Batches) == 3)
	testing.expect(t, len(batch.Batches[0].Material.Fragment.UniformBuffers[0]) == 0)
	testing.expect(t, len(batch.Batches[1].Material.Fragment.UniformBuffers[0]) == 4)
	testing.expect(t, len(batch.Batches[2].Material.Fragment.UniformBuffers[0]) == 0)
	testing.expect(t, len(batch.Material.Fragment.UniformBuffers[0]) == 0)
}

@(test)
focus_navigation_and_modal_isolation :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	theme := UI_THEME_DARK
	for frame in 0..<4 {
		if frame == 1 {
			ui_set_navigation(&ctx, {next = 1, activate = true})
		}
		if frame == 2 {
			ui_set_modal(&ctx, "dialog")
			ui_set_navigation(&ctx, {next = 1, activate = true})
		}
		ui_begin(&ctx, 1.0 / 60)
		background := ui_button(&ctx, &theme, "background", "")
		ui_button(&ctx, &theme, "disabled", "", {disabled = true})
		ui_set_scope(&ctx, "dialog")
		dialog := ui_button(&ctx, &theme, "confirm", "")
		ui_set_scope(&ctx, "")
		ui_end(&ctx)
		if frame == 1 {
			testing.expect(t, background && !dialog && ctx.input.keyboard)
		}
		if frame == 2 {
			testing.expect(t, !background && dialog && ctx.input.pointer && ctx.input.keyboard)
			testing.expect(t, ctx.focused_id == clay.ID("confirm").id)
		}
		if frame == 3 {
			testing.expect(t, !background && !dialog, "navigation is one-shot")
		}
	}
}

@(test)
slider_capture_scale_and_keyboard :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	ui_set_viewport(&ctx, {10, 20, 800, 600}, 2)
	theme := UI_THEME_DARK
	value: f32 = 0.5
	for frame in 0..<5 {
		ui_set_pointer(&ctx, frame == 2 ? 1000 : 26, 30, frame == 1 || frame == 2)
		if frame == 4 {
			ui_set_navigation(&ctx, {adjust = -1})
		}
		ui_begin(&ctx, 1.0 / 60)
		ui_slider(&ctx, &theme, "volume", &value)
		ui_end(&ctx)
		if frame == 1 {
			testing.expect(t, value == 0)
		}
		if frame == 2 {
			testing.expect(t, value == 1 && ctx.input.pointer, "drag clamps outside")
		}
		if frame == 4 {
			testing.expect(t, value == 0 && ctx.input.keyboard)
		}
	}
}

@(test)
context_reinitialization_and_pool_diagnostics :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	testing.expect(t, ui_init(&ctx, 400, 300))
	defer ui_dispose(&ctx)
	ui_begin(&ctx, 1.0 / 60)
	ctx.text_config_len = len(ctx.text_config_pool)
	testing.expect(t, ui_text_config(&ctx, {}) == nil && ctx.pool_overflow)
	ui_end(&ctx)
	ui_begin(&ctx, 1.0 / 60)
	testing.expect(t, !ctx.pool_overflow && ui_text_config(&ctx, {}) != nil)
	ui_end(&ctx)
	testing.expect(t, ui_color({1, 1, 1, 0.5}) == foster.Color{128, 128, 128, 128})
}

@(test)
scroll_layout_starts_at_top_and_clips_after_wheel :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 300, 300))
	defer ui_dispose(&ctx)
	for frame in 0..<3 {
		ui_set_pointer(&ctx, 5, 5, false)
		if frame == 2 {
			ui_add_scroll(&ctx, 0, -2)
		}
		ui_begin(&ctx, 1.0 / 60)
		if clay.UI()(ui_scroll_decl(&ctx, "list", 50, 100)) {
			for i in 0..<8 {
				if clay.UI()(clay.ElementDeclaration{
					id = clay.ID("row", u32(i)),
					layout = {sizing = {width = clay.SizingFixed(80), height = clay.SizingFixed(20)}},
					backgroundColor = {1, 1, 1, 1},
				}) {}
			}
		}
		commands := ui_end(&ctx)
		data := clay.GetScrollContainerData(clay.ID("list"))
		testing.expect(t, data.found)
		if frame == 0 {
			testing.expect(t, clay.GetElementData(clay.ID("row", 0)).boundingBox.y == 0)
		}
		if frame == 2 {
			testing.expect(t, data.scrollPosition.y < 0)
			testing.expectf(t, clay.GetElementData(clay.ID("row", 0)).boundingBox.y < 0, "row=%v scroll=%v", clay.GetElementData(clay.ID("row", 0)), data.scrollPosition^)
		}
		ops := ui_translate(&ctx, commands)
		has_start, has_end := false, false
		for op in ops {
			has_start = has_start || op.kind == .Scissor_Start
			has_end = has_end || op.kind == .Scissor_End
		}
		testing.expect(t, has_start && has_end)
		delete(ops)
	}
}

@(test)
contexts_switch_without_stealing_layout_or_lifetime :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	a, b: UI_Context
	testing.expect(t, ui_init(&a, 200, 100))
	testing.expect(t, ui_init(&b, 400, 300))
	defer ui_dispose(&b)
	button_frame(&a, 5, 5, false)
	testing.expect(t, clay.GetCurrentContext() == a.clay_context)
	button_frame(&b, 5, 5, false)
	ui_dispose(&a)
	testing.expect(t, clay.GetCurrentContext() == b.clay_context)
	button_frame(&b, 5, 5, true)
	testing.expect(t, button_frame(&b, 5, 5, false))
}

@(test)
cancel_and_disappearing_widget_release_capture :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 200, 100))
	defer ui_dispose(&ctx)
	button_frame(&ctx, 5, 5, false)
	button_frame(&ctx, 5, 5, true)
	ui_set_navigation(&ctx, {cancel = true})
	testing.expect(t, !button_frame(&ctx, 5, 5, false))
	testing.expect(t, ctx.active_id == 0 && ctx.focused_id == 0)
	button_frame(&ctx, 5, 5, true)
	ui_begin(&ctx, 1.0 / 60)
	ui_end(&ctx)
	testing.expect(t, ctx.active_id == 0 && ctx.focused_id == 0)
	testing.expect(t, !button_frame(&ctx, 5, 5, false))
}
