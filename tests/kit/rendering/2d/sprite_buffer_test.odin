#+test
package rendering2d

import "core:testing"

import foster "olib:foster"
import mat "olib:kit/rendering/material"

@(test)
sprite_item_matches_gpu_record_layout :: proc(t: ^testing.T) {
	// 带裁剪的子图：Source 在贴图 (32,64) 起 16x8，Frame 为未裁剪的 24x24（裁掉左右各 4 像素、上下各 8 像素）。
	texture := foster.Texture{Width = 128, Height = 128}
	frame := foster.SubtextureMake(&texture, {32, 64, 16, 8}, {-4, -8, 24, 24})
	item := sprite_item_make(frame, {12, 12}, {2, 0, 0, 3, 100, 200}, {0.5, 0.25, 1, 1})
	testing.expect_value(t, item.rect, [4]f32{-8, -4, 16, 8}) // 局部 x0, y0 = 裁剪起点(4,8) - 锚点(12,12)
	testing.expect_value(t, item.uv, [4]f32{0.25, 0.5, 0.125, 0.0625})
	testing.expect_value(t, size_of(Sprite_Item), 80) // 与 GPU 记录同一布局，无字段时整块上传
	testing.expect_value(t, offset_of(Sprite_Item, tint), 64)
	testing.expect_value(t, sprite_stride(0), 80)
	testing.expect_value(t, sprite_stride(2), 112)
}

@(test)
sprite_buffer_guards_and_draw_errors :: proc(t: ^testing.T) {
	buf: Sprite_Buffer
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	plain := mat.Material_Effect{desc = {passes = []mat.Pass_Desc{{draw = .Sprite}}}}
	instanced := mat.Material_Effect{desc = {instanced = true, passes = []mat.Pass_Desc{{draw = .Sprite}}}}
	testing.expect_value(t, sprite_buffer_init(&buf, nil, 10), "Material is not loaded")
	testing.expect_value(t, sprite_buffer_init(&buf, &mat.Material{effect = &instanced}, 10), "Material is not loaded")
	testing.expect_value(t, sprite_buffer_init(&buf, &mat.Material{owner = &library, effect = &plain}, 10),
		"Sprite buffers require an Instanced sprite effect")
	testing.expect_value(t, sprite_buffer_init(&buf, &mat.Material{owner = &library, effect = &instanced}, 0),
		"Sprite buffer capacity must be positive")
	items := []Sprite_Item{{}, {}}
	testing.expect(t, !sprite_buffer_upload(&buf, items)) // 未创建
	buf.capacity = 1
	testing.expect(t, !sprite_buffer_upload(&buf, items)) // 超出容量
	testing.expect(t, !sprite_buffer_upload(&buf, items[:1], 1))
	buf.capacity, buf.slots = 2, 2
	testing.expect(t, !sprite_buffer_upload(&buf, items, 0, make([][4]f32, 3, context.temp_allocator))) // 应为 2×2

	// r2d.buffer 的错误码：都在提交前返回。
	r := Render2D{library = &library}
	defer dispose(&r)
	render2d_reset_state(&r)
	atlas: foster.Texture
	testing.expect_value(t, buffer(&r, nil, &buf, 1, &atlas), mat.Draw_Error.Missing_Material)
	material := mat.Material{owner = &library, effect = &plain}
	testing.expect_value(t, buffer(&r, &material, &buf, 1, &atlas), mat.Draw_Error.Not_Instanced_Effect)
	shaders := make([]foster.Shader, 1, context.temp_allocator)
	instanced.instanced_vertex = shaders
	material.effect = &instanced
	testing.expect_value(t, buffer(&r, &material, nil, 1, &atlas), mat.Draw_Error.Instance_Buffer_Required)
	testing.expect_value(t, buffer(&r, &material, &buf, 1, &atlas), mat.Draw_Error.Instance_Mismatch) // 材质 0 个字段，缓冲 2 个
	buf.slots = 0
	testing.expect_value(t, buffer(&r, &material, &buf, 1, nil), mat.Draw_Error.Missing_Sprite_Texture)
}
