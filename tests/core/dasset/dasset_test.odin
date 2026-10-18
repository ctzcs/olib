// dasset 包单元测试：写读往返 + 坏文件防御。
#+test
package dasset

import "core:testing"

@(test)
dasset_roundtrip_full_model :: proc(t: ^testing.T) {
	model := make_test_model()
	defer dasset_model_dispose(&model)

	bytes, ok := dasset_write(&model)
	if !testing.expectf(t, ok, "写出失败") { return }
	defer delete(bytes)

	back, err := dasset_read(bytes)
	defer dasset_model_dispose(&back)
	if !testing.expectf(t, err == .None, "读回失败: %v", err) { return }

	// 贴图
	testing.expectf(t, len(back.textures) == 1, "贴图数")
	tex := back.textures[0]
	testing.expect(t, tex.name == "albedo" && tex.codec == .Png && len(tex.bytes) == 4 && tex.bytes[3] == 9)

	// 骨架
	testing.expect(t, len(back.skeletons) == 1)
	skel := back.skeletons[0]
	testing.expect(t, len(skel.joints) == 2)
	testing.expect(t, skel.joints[0].name == "root" && skel.joints[0].parent_index == -1)
	testing.expect(t, skel.joints[1].parent_index == 0)
	testing.expect(t, skel.joints[0].inverse_bind_matrix[15] == 1)

	// primitives：静态 + 蒙皮
	testing.expect(t, len(back.primitives) == 2)
	p0 := back.primitives[0]
	testing.expect(t, !dasset_primitive_is_skinned(&p0) && len(p0.vertices) == 3 && p0.skin_index == -1)
	testing.expectf(t, p0.vertices[2].uv == [2]f32{0.5, 0.25}, "uv 往返")
	testing.expect(t, len(p0.indices) == 3 && p0.indices[2] == 5)
	p1 := back.primitives[1]
	testing.expect(t, dasset_primitive_is_skinned(&p1) && len(p1.skin_vertices) == 1 && p1.skin_index == 0)
	testing.expect(t, p1.skin_vertices[0].joints == 0x01020003) // byte0|byte1<<8|...
	testing.expect(t, p1.skin_vertices[0].weights[3] == 0.25)

	// 材质（v3 字段）
	m := p1.material
	testing.expect(t, m.base_color_factor == [4]f32{1, 0.5, 0.25, 1})
	testing.expect(t, m.metallic == 0.1 && m.roughness == 0.9)
	testing.expect(t, m.alpha_mode == .Blend && m.double_sided && m.alpha_cutoff == 0.5)
	testing.expect(t, m.albedo_texture_index == 0 && m.normal_texture_index == -1)
	testing.expect(t, m.emissive_texture_index == 0 && m.emissive_factor == [3]f32{0.1, 0.2, 0.3})

	// 剪辑（cubic + v4 插值）
	testing.expect(t, len(back.clips) == 1)
	clip := back.clips[0]
	testing.expect(t, clip.name == "idle" && clip.skin_index == 0 && clip.duration == 2)
	testing.expect(t, len(clip.channels) == 2)
	ch := clip.channels[0]
	testing.expect(t, ch.interpolation == .Cubic_Spline && ch.path == .Rotation)
	testing.expect(t, len(ch.times) == 2 && ch.times[1] == 1.5)
	testing.expect(t, ch.values[1] == [4]f32{0, 0.7, 0, 0.7})
	testing.expect(t, ch.in_tangents[0] == [4]f32{0.1, 0, 0, 0})
	testing.expect(t, ch.out_tangents[1] == [4]f32{0, 0.2, 0, 0})
	ch1 := clip.channels[1]
	testing.expect(t, ch1.interpolation == .Linear && len(ch1.in_tangents) == 0)

	// 模型级 AABB
	testing.expect(t, back.bounds.min == [3]f32{-1, -2, -3} && back.bounds.max == [3]f32{4, 5, 6})
}

@(test)
dasset_rejects_bad_input :: proc(t: ^testing.T) {
	// 魔数不符
	bad := []u8{0, 0, 0, 0, 4, 0, 0, 0}
	_, err := dasset_read(bad)
	testing.expect(t, err == .Not_Dasset)

	// 版本超界
	high := []u8{0x44, 0x41, 0x53, 0x54, 99, 0, 0, 0}
	_, err2 := dasset_read(high)
	testing.expect(t, err2 == .Bad_Version)

	// 截断
	if bytes, ok := make_minimal_v4(); ok {
		defer delete(bytes)
		cuts := []int{4, 12, len(bytes) - 1}
		for cut in cuts {
			if cut >= len(bytes) { continue }
			model, err3 := dasset_read(bytes[:cut])
			dasset_model_dispose(&model)
			testing.expectf(t, err3 != .None, "截断到 %d 应报错", cut)
		}
	}

	// 空数据
	_, err4 := dasset_read(nil)
	testing.expect(t, err4 == .Truncated)
}

@(private)
make_minimal_v4 :: proc() -> ([]u8, bool) {
	model := make_test_model()
	defer dasset_model_dispose(&model)
	return dasset_write(&model)
}

@(private)
make_test_model :: proc() -> Dasset_Model {
	model := Dasset_Model{
		bounds = {min = {-1, -2, -3}, max = {4, 5, 6}},
	}

	append(&model.textures, Dasset_Texture_Entry{
		name  = clone_owned("albedo"),
		codec = .Png,
		bytes = clone_bytes([]u8{1, 2, 3, 9}),
	})

	skel: Dasset_Skeleton
	root: Dasset_Joint
	root.name = clone_owned("root")
	root.parent_index = -1
	root.bind_scale = {1, 1, 1}
	root.bind_rotation = {0, 0, 0, 1}
	root.inverse_bind_matrix = matrix_identity16()
	append(&skel.joints, root)
	child: Dasset_Joint
	child.name = clone_owned("child")
	child.parent_index = 0
	child.inverse_bind_matrix = matrix_identity16()
	append(&skel.joints, child)
	append(&model.skeletons, skel)

	p_static: Dasset_Primitive
	p_static.vertices = make([]Dasset_Vertex, 3)
	p_static.vertices[2].uv = {0.5, 0.25}
	p_static.vertices[2].normal = {0, 1, 0}
	p_static.indices = make([]u32, 3)
	p_static.indices[2] = 5
	p_static.skin_index = -1
	p_static.material = DASSET_MATERIAL_DEFAULT
	p_static.bounds = {min = {0, 0, 0}, max = {1, 1, 1}}
	append(&model.primitives, p_static)

	p_skin: Dasset_Primitive
	p_skin.skin_vertices = make([]Dasset_Skin_Vertex, 1)
	p_skin.skin_vertices[0].joints = 0x01020003
	p_skin.skin_vertices[0].weights = {0.25, 0.25, 0.25, 0.25}
	p_skin.skin_index = 0
	p_skin.indices = make([]u32, 3)
	p_skin.material = DASSET_MATERIAL_DEFAULT
	p_skin.material.base_color_factor = {1, 0.5, 0.25, 1}
	p_skin.material.metallic = 0.1
	p_skin.material.roughness = 0.9
	p_skin.material.double_sided = true
	p_skin.material.alpha_mode = .Blend
	p_skin.material.albedo_texture_index = 0
	p_skin.material.emissive_texture_index = 0
	p_skin.material.emissive_factor = {0.1, 0.2, 0.3}
	p_skin.bounds = {min = {0, 0, 0}, max = {1, 1, 1}}
	append(&model.primitives, p_skin)

	clip: Dasset_Animation_Clip
	clip.name = clone_owned("idle")
	clip.skin_index = 0
	clip.duration = 2

	rot: Dasset_Animation_Channel
	rot.joint_index = 0
	rot.path = .Rotation
	rot.interpolation = .Cubic_Spline
	rot.times = make([]f32, 2)
	rot.times[1] = 1.5
	rot.values = make([][4]f32, 2)
	rot.values[1] = {0, 0.7, 0, 0.7}
	rot.in_tangents = make([][4]f32, 2)
	rot.in_tangents[0] = {0.1, 0, 0, 0}
	rot.out_tangents = make([][4]f32, 2)
	rot.out_tangents[1] = {0, 0.2, 0, 0}
	append(&clip.channels, rot)

	tr: Dasset_Animation_Channel
	tr.joint_index = 1
	tr.path = .Translation
	tr.interpolation = .Linear
	tr.times = make([]f32, 2)
	tr.times[1] = 1
	tr.values = make([][4]f32, 2)
	tr.values[1] = {1, 2, 3, 0}
	append(&clip.channels, tr)

	append(&model.clips, clip)
	return model
}

@(private)
matrix_identity16 :: proc() -> [16]f32 {
	m: [16]f32
	m[0] = 1
	m[5] = 1
	m[10] = 1
	m[15] = 1
	return m
}

