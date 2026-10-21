#+test
package rendering2d

import "core:testing"

import foster "olib:foster"
import mat "olib:kit/rendering/material"
import sh "olib:kit/rendering/shader"

// 只检查 CPU 侧的状态栈、记录分段与错误码；不创建窗口，也不伪造 GPU 句柄。

@(test)
render2d_stacks_follow_batcher_semantics :: proc(t: ^testing.T) {
	r: Render2D
	defer dispose(&r)
	render2d_reset_state(&r)
	testing.expect_value(t, render2d_transform(&r, {2, 3}), foster.Vec2{2, 3})

	push_matrix_trs(&r, {10, 0}, {1, 1}, 0)            // 相机
	push_matrix_trs(&r, {0, 0}, {2, 2}, 0)             // 物体：先缩放，再接相机平移
	testing.expect_value(t, render2d_transform(&r, {1, 1}), foster.Vec2{12, 2})
	pop_matrix(&r)
	testing.expect_value(t, render2d_transform(&r, {1, 1}), foster.Vec2{11, 1})
	push_matrix(&r, foster.Matrix3x2{1, 0, 0, 1, 5, 5}, relative = false)
	testing.expect_value(t, render2d_transform(&r, {0, 0}), foster.Vec2{5, 5})
	pop_matrix(&r)
	pop_matrix(&r)
	pop_matrix(&r) // 空栈弹出不改变状态
	testing.expect_value(t, render2d_transform(&r, {1, 1}), foster.Vec2{1, 1})

	push_mode(&r, .Fill)
	testing.expect_value(t, r.mode_color, foster.Color{0, 0, 255, 0})
	pop_mode(&r)
	testing.expect_value(t, r.mode_color, foster.Color{255, 0, 0, 0})

	push_scissor(&r, {1, 2, 3, 4})
	push_scissor(&r, {5, 6, 7, 8})
	pop_scissor(&r)
	testing.expect(t, r.has_scissor && r.scissor == foster.RectInt{1, 2, 3, 4})
	pop_scissor(&r)
	testing.expect(t, !r.has_scissor)

	push_blend(&r, foster.BlendModeNonPremultiplied)
	push_sampler(&r, foster.TextureSamplerMake(.Linear, .Repeat))
	testing.expect(t, r.blend == foster.BlendModeNonPremultiplied)
	// 提交后（即使没有记录）恢复默认状态。
	testing.expect_value(t, submit(&r, {}), mat.Draw_Error.None)
	testing.expect(t, r.blend == foster.BlendModePremultiply && r.sampler == foster.TextureSamplerMake(.Nearest, .Clamp))
	testing.expect_value(t, len(r.blend_stack), 0)
}

@(test)
render2d_record_reports_errors :: proc(t: ^testing.T) {
	r: Render2D
	defer dispose(&r)
	testing.expect_value(t, rect(&r, {0, 0, 1, 1}, foster.White), mat.Draw_Error.Missing_Device)

	device, other: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r.library = &library
	render2d_reset_state(&r)
	testing.expect_value(t, rect(&r, {0, 0, 1, 1}, foster.White), mat.Draw_Error.Missing_Material)
	foreign_library := mat.Material_Library{device = &other}
	effect: mat.Material_Effect
	alien := mat.Material{owner = &foreign_library, effect = &effect}
	testing.expect_value(t, rect(&r, {0, 0, 1, 1}, foster.White, &alien), mat.Draw_Error.Device_Mismatch)
	testing.expect_value(t, texture(&r, nil, {1, 0, 0, 1, 0, 0}), mat.Draw_Error.Missing_Sprite_Texture)
	testing.expect_value(t, image(&r, {}, {1, 0, 0, 1, 0, 0}), mat.Draw_Error.Missing_Sprite_Texture)
	// 零长度线段、步数不足的圆不记录也不报错。
	testing.expect_value(t, line(&r, {1, 1}, {1, 1}, 2, foster.White, &alien), mat.Draw_Error.None)
	testing.expect_value(t, circle(&r, {0, 0}, 1, 2, foster.White, &alien), mat.Draw_Error.None)
	testing.expect_value(t, len(r.vertices), 0)
}

// 段的拆分条件：材质、Pass、帧贴图、采样器、混合、裁剪或材质 revision 任何一项不同都开新段。
@(test)
render2d_runs_split_on_state_and_parameters :: proc(t: ^testing.T) {
	r: Render2D
	defer dispose(&r)
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r.library = &library
	render2d_reset_state(&r)

	fields := []sh.Field{{id = "texture", name = "texture", kind = .Texture},
		{id = "strength", name = "strength", kind = .Scalar, maximum = 1},
		{id = "mask", name = "mask", kind = .Texture}}
	schema := sh.Schema{name = "Glow", preview = "2d", fields = fields}
	effect := mat.Material_Effect{desc = {name = "Glow", output = "color", preview = "2d", passes = []sh.Pass_Desc{
		{id = "main", params = "Glow", output = "color", draw = .Sprite, sprite_texture = "texture"}}}}
	gpu: foster.Material
	foster.MaterialInit(&gpu)
	defer foster.MaterialDispose(&gpu)
	values := []sh.Value{{}, {number = {0.5, 0, 0, 0}}, {}} // 参数 strength 为 0.5
	white, atlas: foster.Texture
	samplers := []foster.BoundSampler{{Texture = &white}, {Texture = &white}}
	material := mat.Material{owner = &library, effect = &effect,
		bindings = []mat.Material_Binding{{schema, values, &gpu, samplers}}}
	selection := mat.Pass_Selection{count = 1}

	render2d_run_begin(&r, &material, "", &atlas, selection, nil)
	run := &r.runs[0]
	testing.expect(t, render2d_run_matches(&r, run, &material, "", &atlas, selection))
	run.quad_count = RENDER2D_BATCH_QUADS
	testing.expect(t, !render2d_run_matches(&r, run, &material, "", &atlas, selection))
	run.quad_count = 0
	testing.expect(t, r.snapshots[0].Fragment.Samplers[0].Texture == &atlas) // 帧贴图替换到 sprite_texture 槽
	testing.expect_value(t, len(r.snapshots[0].Fragment.UniformBuffers[1]), 16) // .oshader 效果的参数在片元槽 1

	testing.expect(t, !render2d_run_matches(&r, run, &material, "", &white, selection))
	testing.expect(t, !render2d_run_matches(&r, run, &material, "outline", &atlas, selection))
	push_blend(&r, foster.BlendModeNonPremultiplied)
	testing.expect(t, !render2d_run_matches(&r, run, &material, "", &atlas, selection))
	pop_blend(&r)
	push_scissor(&r, {0, 0, 4, 4})
	testing.expect(t, !render2d_run_matches(&r, run, &material, "", &atlas, selection))
	pop_scissor(&r)
	testing.expect(t, render2d_run_matches(&r, run, &material, "", &atlas, selection))
	// material_set_number / material_set_texture / reload 递增 revision：快照过期，开新段。
	material.revision += 1
	testing.expect(t, !render2d_run_matches(&r, run, &material, "", &atlas, selection))

	// 有记录但目标无效：返回错误并清空记录，快照留待复用。
	testing.expect_value(t, submit(&r, {}), mat.Draw_Error.Invalid_Target)
	testing.expect_value(t, len(r.runs), 0)
	testing.expect_value(t, r.snapshot_count, 0)
	testing.expect_value(t, len(r.snapshots), 1)
}

@(test)
render2d_instance_values_preserve_each_pass :: proc(t: ^testing.T) {
	r: Render2D
	defer dispose(&r)
	schema := sh.Schema{fields = []sh.Field{{id = "hue", name = "hue", kind = .Scalar, instance = true, maximum = 1}}}
	effect := mat.Material_Effect{desc = {passes = []sh.Pass_Desc{{}, {}}}}
	m := mat.Material{effect = &effect, bindings = []mat.Material_Binding{
		{schema = schema, values = []sh.Value{{number = {0.2, 0, 0, 0}}}},
		{schema = schema, values = []sh.Value{{number = {0.8, 0, 0, 0}}}},
	}}
	selection := mat.Pass_Selection{count = 2}
	selection.passes[1], selection.bindings[1] = 1, 1
	// 记录首项是两条轴，之后是各 Pass 的数值。
	axes := [4]f32{2, 0, 0, 3}
	testing.expect_value(t, render2d_record_instances(&r, &m, selection, nil, axes), 1)
	testing.expect_value(t, r.instance_values[1], axes)
	testing.expect_value(t, r.instance_values[2][0], 0.2)
	testing.expect_value(t, r.instance_values[3][0], 0.8)
	testing.expect_value(t, render2d_record_instances(&r, &m, selection, nil, axes), 4)
}
