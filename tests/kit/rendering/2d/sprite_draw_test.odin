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


// 不同 [Instance] 取值和 tint 的精灵共用同一份 uniform，应合成一个批次，且各自的数据写进顶点。
@(test)
sprite_batch_merges_different_instance_values :: proc(t: ^testing.T) {
	renderer: Sprite_Renderer
	defer delete(renderer.instance_vertices)
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
	quad := [4]Sprite_Vertex{{{0, 0}, {0, 0}}, {{10, 0}, {1, 0}}, {{10, 10}, {1, 1}}, {{0, 10}, {0, 1}}}
	first := Sprite_Submission{renderer = &renderer, vertices = quad, tint = {1, 0, 0, 1}, layout = 2}
	second := Sprite_Submission{renderer = &renderer, vertices = quad, tint = {0, 1, 0, 1}, layout = 2}
	red := mat.Instance_Values{count = 1}
	red.numbers[0] = {0.2, 0, 0, 0}
	green := mat.Instance_Values{count = 1}
	green.numbers[0] = {0.7, 0, 0, 0}
	sprite_batch_submit(&first, 0, &command, &red)
	sprite_batch_submit(&second, 0, &command, &green)
	testing.expect(t, renderer.sprite_passes == 2 && renderer.draw_calls == 0)
	testing.expect(t, len(renderer.vertices) == 0 && len(renderer.instance_vertices) == 8 && len(renderer.indices) == 12)
	testing.expect_value(t, renderer.instance_vertices[0].tint, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, renderer.instance_vertices[0].data[0][0], 0.2)
	testing.expect_value(t, renderer.instance_vertices[7].tint, [4]f32{0, 1, 0, 1})
	testing.expect_value(t, renderer.instance_vertices[7].data[0][0], 0.7)
	testing.expect_value(t, renderer.instance_vertices[5].uv, [2]f32{1, 0})
	testing.expect_value(t, renderer.indices[6], 4)
	// 布局不同（普通顶点）不能并入同一批：状态比较不相等。
	plain_state := renderer.batch_state
	plain_state.layout = 0
	testing.expect(t, !sprite_batch_matches(&renderer, plain_state, &source))
}
