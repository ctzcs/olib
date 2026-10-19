#+test
package rendering2d

import "core:testing"
import foster "olib:foster"
import mat "olib:kit/rendering/material"

// CPU 侧检查真实合批输入与快照，不创建窗口或伪造 GPU 句柄。
@(test)
sprite_batch_preserves_geometry_and_material_snapshot :: proc(t: ^testing.T) {
	renderer: Sprite_Renderer
	defer delete(renderer.vertices)
	defer delete(renderer.indices)
	defer foster.MaterialDispose(&renderer.batch_material)
	source: foster.Material
	foster.MaterialInit(&source)
	defer foster.MaterialDispose(&source)
	uniform := [4]u8{1, 2, 3, 4}
	foster.MaterialStageSetUniformBuffer(&source.Fragment, uniform[:])
	texture: foster.Texture
	source.Fragment.Samplers[0] = {&texture, foster.TextureSamplerMake(.Linear, .Clamp)}
	command: foster.DrawCommand
	foster.DrawCommandInit(&command)
	command.Material = &source
	command.Target = {WidthInPixels = 800, HeightInPixels = 600}
	first := Sprite_Submission{renderer = &renderer, vertices = {
		{{0, 0}, {0, 0}}, {{10, 0}, {0.5, 0}}, {{10, 10}, {0.5, 1}}, {{0, 10}, {0, 1}},
	}}
	sprite_batch_submit(&first, 0, &command, nil)
	// 不同 Material 地址但 GPU 输入相同，也应合批。
	other := foster.MaterialClone(&source)
	defer foster.MaterialDispose(&other)
	command.Material = &other
	second := first
	for &vertex in second.vertices do vertex.position.x += 20
	sprite_batch_submit(&second, 0, &command, nil)
	testing.expect(t, renderer.sprite_passes == 2 && renderer.draw_calls == 0)
	testing.expect(t, len(renderer.vertices) == 8 && len(renderer.indices) == 12)
	testing.expect_value(t, renderer.vertices[0].position, [2]f32{0, 0})
	testing.expect_value(t, renderer.vertices[4].position, [2]f32{20, 0})
	testing.expect_value(t, renderer.vertices[6].uv, [2]f32{0.5, 1})
	for value, i in ([12]u32{0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7}) {
		testing.expect_value(t, renderer.indices[i], value)
	}
	testing.expect(t, sprite_batch_matches(&renderer, renderer.batch_state, &other))
	uniform[0] = 9
	foster.MaterialStageSetUniformBuffer(&other.Fragment, uniform[:])
	testing.expect(t, !sprite_batch_matches(&renderer, renderer.batch_state, &other))
	testing.expect_value(t, foster.MaterialStageGetUniformBuffer(&renderer.batch_material.Fragment)[0], 1)
	foster.MaterialCopyTo(&source, &other)
	other.Fragment.Samplers[0].Texture = nil
	testing.expect(t, !sprite_batch_matches(&renderer, renderer.batch_state, &other))
	state := renderer.batch_state
	state.depth_write = !state.depth_write
	testing.expect(t, !sprite_batch_matches(&renderer, state, &source))
	state = renderer.batch_state
	state.target.WidthInPixels += 1
	testing.expect(t, !sprite_batch_matches(&renderer, state, &source))
}


// 不同 [Instance] 取值和 tint 的精灵共用同一份 uniform，应合成一个批次，且各自的数据写进实例记录。
@(test)
sprite_batch_merges_different_instance_values :: proc(t: ^testing.T) {
	renderer: Sprite_Renderer
	defer delete(renderer.instance_bytes)
	defer delete(renderer.vertices)
	defer delete(renderer.indices)
	defer foster.MaterialDispose(&renderer.batch_material)
	source: foster.Material
	foster.MaterialInit(&source)
	defer foster.MaterialDispose(&source)
	uniform := [4]u8{1, 2, 3, 4}
	foster.MaterialStageSetUniformBuffer(&source.Fragment, uniform[:])
	command: foster.DrawCommand
	foster.DrawCommandInit(&command)
	command.Material = &source
	command.Target = {WidthInPixels = 800, HeightInPixels = 600}
	frame := foster.SubtextureMake(nil, {0, 0, 16, 16}, {0, 0, 16, 16})
	first := Sprite_Submission{renderer = &renderer, layout = 2,
		item = sprite_item_make(frame, {8, 8}, {2, 0, 0, 2, 100, 50}, {1, 0, 0, 1})}
	second := Sprite_Submission{renderer = &renderer, layout = 2,
		item = sprite_item_make(frame, {8, 8}, {1, 0, 0, 1, 10, 20}, {0, 1, 0, 1})}
	red := mat.Instance_Values{count = 1}
	red.numbers[0] = {0.2, 0, 0, 0}
	green := mat.Instance_Values{count = 1}
	green.numbers[0] = {0.7, 0, 0, 0}
	sprite_batch_submit(&first, 0, &command, &red)
	sprite_batch_submit(&second, 0, &command, &green)
	testing.expect(t, renderer.sprite_passes == 2 && renderer.draw_calls == 0)
	testing.expect_value(t, renderer.instance_pending, 2)
	stride := sprite_stride(1)
	testing.expect_value(t, len(renderer.instance_bytes), 2*stride)
	testing.expect(t, len(renderer.vertices) == 0 && len(renderer.indices) == 0)
	records := ([^]f32)(raw_data(renderer.instance_bytes))
	per := stride / 4
	// 记录布局：变换(4)、平移+局部矩形起点(4)、局部矩形大小+uv起点(4)、uv大小(4)、tint(4)、字段。
	testing.expect_value(t, records[0], 2) // m11
	testing.expect_value(t, records[4], 100) // m31
	testing.expect_value(t, records[16], 1) // 第一个精灵 tint.r
	testing.expect_value(t, records[20], 0.2) // 第一个精灵 hue
	testing.expect_value(t, records[per+16], 0) // 第二个精灵 tint.r
	testing.expect_value(t, records[per+17], 1)
	testing.expect_value(t, records[per+20], 0.7)
	// 布局不同（普通顶点）不能并入同一批：状态比较不相等。
	plain_state := renderer.batch_state
	plain_state.layout = 0
	testing.expect(t, !sprite_batch_matches(&renderer, plain_state, &source))
}

@(test)
sprite_item_packs_gpu_record_layout :: proc(t: ^testing.T) {
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
	record: [112]u8
	sprite_item_pack(record[:], item, 2, [][4]f32{{7, 0, 0, 0}, {8, 0, 0, 0}})
	floats := ([^]f32)(raw_data(record[:]))[:28]
	testing.expect_value(t, floats[0], 2) // m11
	testing.expect_value(t, floats[3], 3) // m22
	testing.expect_value(t, floats[4], 100) // m31
	testing.expect_value(t, floats[5], 200) // m32
	testing.expect_value(t, floats[6], -8) // 局部矩形 x0
	testing.expect_value(t, floats[8], 16) // 局部矩形宽
	testing.expect_value(t, floats[10], 0.25) // uv0.x
	testing.expect_value(t, floats[12], 0.125) // uv 宽
	testing.expect_value(t, floats[16], 0.5) // tint.r
	testing.expect_value(t, floats[20], 7)
	testing.expect_value(t, floats[24], 8)
}

// 平铺数组里每个精灵连续占 slots 个 float4；值不足的槽位补 0。
@(test)
sprite_item_pack_pads_missing_values_with_zero :: proc(t: ^testing.T) {
	values := make([][4]f32, 2*2, context.temp_allocator)
	testing.expect(t, mat.instance_array_set(values, 2, 1, {1, true}, {0.3, 0, 0, 0}))
	record: [112]u8
	for &b in record do b = 0xFF
	sprite_item_pack(record[:], Sprite_Item{}, 2, values[2:4]) // 第 2 个精灵
	floats := ([^]f32)(raw_data(record[:]))[:28]
	testing.expect_value(t, floats[20], 0)
	testing.expect_value(t, floats[24], 0.3) // 槽位 1 写在第二个字段 float4
	sprite_item_pack(record[:], Sprite_Item{}, 2, values[3:4]) // 只给 1 个值：第二个槽补 0
	testing.expect_value(t, floats[20], 0.3)
	testing.expect_value(t, floats[24], 0)
}

@(test)
sprite_buffer_guards_and_draw_errors :: proc(t: ^testing.T) {
	buffer: Sprite_Buffer
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	plain := mat.Material_Effect{}
	instanced := mat.Material_Effect{desc = {instanced = true}}
	testing.expect(t, !sprite_buffer_init(&buffer, nil, 10))
	testing.expect(t, !sprite_buffer_init(&buffer, &mat.Material{owner = &library, effect = &plain}, 10)) // 不是 instanced 效果
	testing.expect(t, !sprite_buffer_init(&buffer, &mat.Material{owner = &library, effect = &instanced}, 0))
	testing.expect(t, !sprite_buffer_init(&buffer, &mat.Material{effect = &instanced}, 10)) // 材质未加载
	items := []Sprite_Item{{}, {}}
	testing.expect(t, !sprite_buffer_upload(&buffer, items)) // 未创建
	buffer.capacity = 1
	testing.expect(t, !sprite_buffer_upload(&buffer, items)) // 超出容量
	testing.expect(t, !sprite_buffer_upload(&buffer, items[:1], 1))
	buffer.capacity, buffer.slots = 2, 2
	testing.expect(t, !sprite_buffer_upload(&buffer, items, 0, make([][4]f32, 3, context.temp_allocator))) // 应为 2×2
	renderer := Sprite_Renderer{device = &device}
	view := Sprite_View{target = {WidthInPixels = 100, HeightInPixels = 100}}
	testing.expect_value(t, sprite_draw_buffer(&renderer, nil, &buffer, 1, nil, view), mat.Draw_Error.Missing_Material)
	testing.expect_value(t, sprite_draw_buffer(&renderer, &mat.Material{owner = &library, effect = &instanced}, nil, 1, nil, view),
		mat.Draw_Error.Instance_Buffer_Required)
}
