// dasset:io —— .dasset 二进制读写（对位 DragonLib DassetReader / DassetWriter）。
//
// 比特兼容 DragonLib 的 v4 布局（little-endian；字符串为 7-bit 变长前缀 +
// UTF-8，同 C# BinaryWriter.ReadString）。Reader 兼容 v1..v4：
// v1 无骨架/剪辑段、primitive 无布局前缀、材质无 v3 字段、channel 无 v4 插值。
// 计数与剩余长度做 sanity 检查，坏文件不产生巨额分配。
//
// 所有权：dasset_read 产出的 model 深拷贝全部字符串/数组，
// 用 dasset_model_dispose 释放；dasset_write 产出的字节块由调用方释放。
package dasset

import "core:mem"
import "core:strings"

// 分区：
//   写出 —— dasset_write
//   读入 —— dasset_read / dasset_model_dispose
//   内部 —— 游标 / LE 编解码 / 字符串前缀

// ------------------------------------------------------------------------------
// 写出
// ------------------------------------------------------------------------------

// 把 model 编成 .dasset 字节块（当前 v4；分配于 context.allocator）。
dasset_write :: proc(model: ^Dasset_Model) -> ([]u8, bool) {
	out: [dynamic]u8

	w_u32(&out, DASSET_MAGIC)
	w_i32(&out, DASSET_VERSION)

	// 贴图表
	w_i32(&out, i32(len(model.textures)))
	for &tex in model.textures {
		w_string(&out, tex.name)
		w_i32(&out, i32(tex.codec))
		w_i32(&out, i32(len(tex.bytes)))
		append(&out, ..tex.bytes)
	}

	// 骨架表
	w_i32(&out, i32(len(model.skeletons)))
	for &skel in model.skeletons {
		w_i32(&out, i32(len(skel.joints)))
		for &joint in skel.joints {
			w_string(&out, joint.name)
			w_i32(&out, joint.parent_index)
			w_vec3(&out, joint.bind_translation)
			w_vec4(&out, joint.bind_rotation)
			w_vec3(&out, joint.bind_scale)
			for f in joint.inverse_bind_matrix {
				w_f32(&out, f)
			}
		}
	}

	// primitives
	w_i32(&out, i32(len(model.primitives)))
	for &p in model.primitives {
		skinned := dasset_primitive_is_skinned(&p)
		layout := skinned ? Dasset_Vertex_Layout.Position_Normal_Uv_Skin : Dasset_Vertex_Layout.Position_Normal_Uv
		w_i32(&out, i32(layout))
		w_i32(&out, p.skin_index)
		if skinned {
			w_i32(&out, i32(len(p.skin_vertices)))
			for &v in p.skin_vertices {
				w_f32(&out, v.position[0]); w_f32(&out, v.position[1]); w_f32(&out, v.position[2])
				w_f32(&out, v.normal[0]); w_f32(&out, v.normal[1]); w_f32(&out, v.normal[2])
				w_f32(&out, v.uv[0]); w_f32(&out, v.uv[1])
				for f in v.tangent { w_f32(&out, f) }
				w_u32(&out, v.joints)
				for f in v.weights { w_f32(&out, f) }
			}
		} else {
			w_i32(&out, i32(len(p.vertices)))
			for &v in p.vertices {
				w_f32(&out, v.position[0]); w_f32(&out, v.position[1]); w_f32(&out, v.position[2])
				w_f32(&out, v.normal[0]); w_f32(&out, v.normal[1]); w_f32(&out, v.normal[2])
				w_f32(&out, v.uv[0]); w_f32(&out, v.uv[1])
				for f in v.tangent { w_f32(&out, f) }
			}
		}

		w_i32(&out, i32(len(p.indices)))
		for index in p.indices {
			w_u32(&out, index)
		}
		w_bounds(&out, p.bounds)
		w_material(&out, p.material)
	}

	w_bounds(&out, model.bounds)

	// 动画剪辑表
	w_i32(&out, i32(len(model.clips)))
	for &clip in model.clips {
		w_string(&out, clip.name)
		w_i32(&out, clip.skin_index)
		w_f32(&out, clip.duration)
		w_i32(&out, i32(len(clip.channels)))
		for &ch in clip.channels {
			w_i32(&out, ch.joint_index)
			w_i32(&out, i32(ch.path))
			w_i32(&out, i32(ch.interpolation))
			n := len(ch.times)
			w_i32(&out, i32(n))
			for t in ch.times { w_f32(&out, t) }
			for &v in ch.values { w_vec4(&out, v) }
			if ch.interpolation == .Cubic_Spline {
				for &v in ch.in_tangents { w_vec4(&out, v) }
				for &v in ch.out_tangents { w_vec4(&out, v) }
			}
		}
	}

	return out[:], true
}

// ------------------------------------------------------------------------------
// 读入
// ------------------------------------------------------------------------------

Dasset_Error :: enum {
	None,
	Not_Dasset, // magic 不符
	Bad_Version, // 版本超出 1..当前
	Truncated, // 数据不足/计数越界
	Bad_Value, // 枚举值非法
}

dasset_read :: proc(data: []u8) -> (Dasset_Model, Dasset_Error) {
	model: Dasset_Model

	if data == nil || len(data) < 8 {
		return model, .Truncated
	}
	cur := 0

	magic, ok := r_u32(data, &cur)
	if !ok || magic != DASSET_MAGIC do return model, .Not_Dasset
	version, ok2 := r_i32(data, &cur)
	if !ok2 || version < 1 || version > DASSET_VERSION do return model, .Bad_Version

	// 贴图表
	tex_count, ok3 := r_count(data, &cur, 8)
	if !ok3 do return model, .Truncated
	for _ in 0..<tex_count {
		name, okn := r_string(data, &cur)
		if !okn do return dispose_partial(&model), .Truncated
		codec_v, okc := r_i32(data, &cur)
		if !okc || codec_v < 0 || codec_v > 1 do return dispose_partial(&model), .Bad_Value
		byte_count, okb := r_count(data, &cur, 1)
		if !okb do return dispose_partial(&model), .Truncated
		bytes := clone_bytes(data[cur:cur + byte_count])
		if len(bytes) != byte_count do return dispose_partial(&model), .Truncated
		cur += byte_count
		append(&model.textures, Dasset_Texture_Entry{name = name, codec = cast(Dasset_Texture_Codec)codec_v, bytes = bytes})
	}

	// 骨架表（v2+）
	if version >= 2 {
		skel_count, oks := r_count(data, &cur, 4)
		if !oks do return dispose_partial(&model), .Truncated
		for _ in 0..<skel_count {
			joint_count, okj := r_count(data, &cur, 4)
			if !okj do return dispose_partial(&model), .Truncated
			append(&model.skeletons, Dasset_Skeleton{}) // 先挂进 model：中途失败也由 dispose 兜底
			skel := &model.skeletons[len(model.skeletons) - 1]
			for _ in 0..<joint_count {
				joint: Dasset_Joint
				j, ojn := r_string(data, &cur)
				if !ojn do return dispose_partial(&model), .Truncated
				joint.name = j
				joint.parent_index, _ = r_i32(data, &cur)
				joint.bind_translation = r_vec3(data, &cur)
				joint.bind_rotation = r_vec4(data, &cur)
				joint.bind_scale = r_vec3(data, &cur)
				for k in 0..<16 {
					joint.inverse_bind_matrix[k] = r_f32(data, &cur)
				}
				append(&skel.joints, joint)
			}
		}
	}

	// primitives
	prim_count, okp := r_count(data, &cur, 8)
	if !okp do return dispose_partial(&model), .Truncated
	for _ in 0..<prim_count {
		append(&model.primitives, Dasset_Primitive{skin_index = -1, material = DASSET_MATERIAL_DEFAULT})
		p := &model.primitives[len(model.primitives) - 1]
		layout := i32(0)
		if version >= 2 {
			layout, _ = r_i32(data, &cur)
			p.skin_index, _ = r_i32(data, &cur)
			if layout < 0 || layout > 1 do return dispose_partial(&model), .Bad_Value
		}
		skinned := layout == 1
		stride := skinned ? DASSET_VERTEX_STRIDE_SKIN : DASSET_VERTEX_STRIDE_STATIC
		vert_count, okv := r_count(data, &cur, stride)
		if !okv do return dispose_partial(&model), .Truncated
		if skinned {
			verts := make([]Dasset_Skin_Vertex, vert_count)
			for &v in verts {
				v.position = r_vec3(data, &cur)
				v.normal = r_vec3(data, &cur)
				v.uv = [2]f32{r_f32(data, &cur), r_f32(data, &cur)}
				v.tangent = r_vec4(data, &cur)
				jv, _ := r_u32(data, &cur)
				v.joints = jv
				v.weights = r_vec4(data, &cur)
			}
			p.skin_vertices = verts
		} else {
			verts := make([]Dasset_Vertex, vert_count)
			for &v in verts {
				v.position = r_vec3(data, &cur)
				v.normal = r_vec3(data, &cur)
				v.uv = [2]f32{r_f32(data, &cur), r_f32(data, &cur)}
				v.tangent = r_vec4(data, &cur)
			}
			p.vertices = verts
		}

		index_count, oki := r_count(data, &cur, 4)
		if !oki do return dispose_partial(&model), .Truncated
		indices := make([]u32, index_count)
		for &index in indices {
			index = r_u32(data, &cur) or_else 0
		}
		p.indices = indices
		p.bounds = Dasset_Bounds{min = r_vec3(data, &cur), max = r_vec3(data, &cur)}

		// 材质
		p.material.base_color_factor = r_vec4(data, &cur)
		p.material.metallic = r_f32(data, &cur)
		p.material.roughness = r_f32(data, &cur)
		dv, _ := r_u8(data, &cur)
		p.material.double_sided = dv != 0
		alpha_v, oka := r_i32(data, &cur)
		if !oka || alpha_v < 0 || alpha_v > 2 do return dispose_partial(&model), .Bad_Value
		p.material.alpha_mode = cast(Dasset_Alpha_Mode)alpha_v
		p.material.alpha_cutoff = r_f32(data, &cur)
		p.material.albedo_texture_index, _ = r_i32(data, &cur)
		p.material.normal_texture_index, _ = r_i32(data, &cur)
		if version >= 3 {
			p.material.metallic_roughness_texture_index, _ = r_i32(data, &cur)
			p.material.occlusion_texture_index, _ = r_i32(data, &cur)
			p.material.occlusion_strength = r_f32(data, &cur)
			p.material.emissive_texture_index, _ = r_i32(data, &cur)
			p.material.emissive_factor = r_vec3(data, &cur)
			p.material.normal_scale = r_f32(data, &cur)
		}
	}

	model.bounds = Dasset_Bounds{min = r_vec3(data, &cur), max = r_vec3(data, &cur)}

	// 动画剪辑表（v2+）
	if version >= 2 {
		clip_count, okc := r_count(data, &cur, 8)
		if !okc do return dispose_partial(&model), .Truncated
		for _ in 0..<clip_count {
			append(&model.clips, Dasset_Animation_Clip{}) // 先挂进 model：中途失败也由 dispose 兜底
			clip := &model.clips[len(model.clips) - 1]
			n, okn := r_string(data, &cur)
			if !okn do return dispose_partial(&model), .Truncated
			clip.name = n
			clip.skin_index, _ = r_i32(data, &cur)
			clip.duration = r_f32(data, &cur)
			channel_count, okch := r_count(data, &cur, 8)
			if !okch do return dispose_partial(&model), .Truncated
			for _ in 0..<channel_count {
				ch: Dasset_Animation_Channel
				ch.joint_index, _ = r_i32(data, &cur)
				path_v, okpv := r_i32(data, &cur)
				if !okpv || path_v < 0 || path_v > 2 do return dispose_partial(&model), .Bad_Value
				ch.path = cast(Dasset_Anim_Path)path_v
				if version >= 4 {
					interp_v, okiv := r_i32(data, &cur)
					if !okiv || interp_v < 0 || interp_v > 2 do return dispose_partial(&model), .Bad_Value
					ch.interpolation = cast(Dasset_Interpolation)interp_v
				}
				key_count, okk := r_count(data, &cur, ch.interpolation == .Cubic_Spline ? 52 : 20)
				if !okk do return dispose_partial(&model), .Truncated
				ch.times = make([]f32, key_count)
				for &t in ch.times { t = r_f32(data, &cur) }
				ch.values = make([][4]f32, key_count)
				for &v in ch.values { v = r_vec4(data, &cur) }
				if ch.interpolation == .Cubic_Spline {
					ch.in_tangents = make([][4]f32, key_count)
					ch.out_tangents = make([][4]f32, key_count)
					for &v in ch.in_tangents { v = r_vec4(data, &cur) }
					for &v in ch.out_tangents { v = r_vec4(data, &cur) }
				}
				append(&clip.channels, ch)
			}
		}
	}

	return model, .None
}

// 释放 model 的全部深拷贝数据。
dasset_model_dispose :: proc(model: ^Dasset_Model) {
	for &tex in model.textures {
		if len(tex.name) > 0 do delete(tex.name) // 空串未分配（见 clone_owned）
		if tex.bytes != nil do delete(tex.bytes)
	}
	delete(model.textures)
	for &p in model.primitives {
		delete(p.vertices)
		delete(p.skin_vertices)
		delete(p.indices)
	}
	delete(model.primitives)
	for &skel in model.skeletons {
		for &joint in skel.joints {
			if len(joint.name) > 0 do delete(joint.name)
		}
		delete(skel.joints)
	}
	delete(model.skeletons)
	for &clip in model.clips {
		if len(clip.name) > 0 do delete(clip.name)
		for &ch in clip.channels {
			delete(ch.times)
			delete(ch.values)
			delete(ch.in_tangents)
			delete(ch.out_tangents)
		}
		delete(clip.channels)
	}
	delete(model.clips)
	model^ = {}
}

@(private)
dispose_partial :: proc(model: ^Dasset_Model) -> Dasset_Model {
	dasset_model_dispose(model)
	return {}
}

// ------------------------------------------------------------------------------
// 内部 —— 写辅助
// ------------------------------------------------------------------------------

@(private)
w_u8 :: proc(out: ^[dynamic]u8, v: u8) {
	append(out, v)
}

@(private)
w_u32 :: proc(out: ^[dynamic]u8, v: u32) {
	append(out, u8(v))
	append(out, u8(v >> 8))
	append(out, u8(v >> 16))
	append(out, u8(v >> 24))
}

@(private)
w_i32 :: proc(out: ^[dynamic]u8, v: i32) {
	w_u32(out, cast(u32)v)
}

@(private)
w_f32 :: proc(out: ^[dynamic]u8, v: f32) {
	w_u32(out, transmute(u32)v)
}

@(private)
w_vec3 :: proc(out: ^[dynamic]u8, v: [3]f32) {
	for f in v { w_f32(out, f) }
}

@(private)
w_vec4 :: proc(out: ^[dynamic]u8, v: [4]f32) {
	for f in v { w_f32(out, f) }
}

@(private)
w_bounds :: proc(out: ^[dynamic]u8, b: Dasset_Bounds) {
	w_vec3(out, b.min)
	w_vec3(out, b.max)
}

@(private)
w_material :: proc(out: ^[dynamic]u8, m: Dasset_Material) {
	w_vec4(out, m.base_color_factor)
	w_f32(out, m.metallic)
	w_f32(out, m.roughness)
	w_u8(out, m.double_sided ? 1 : 0)
	w_i32(out, i32(m.alpha_mode))
	w_f32(out, m.alpha_cutoff)
	w_i32(out, m.albedo_texture_index)
	w_i32(out, m.normal_texture_index)
	// v3 字段（当前固定写 v4 布局）
	w_i32(out, m.metallic_roughness_texture_index)
	w_i32(out, m.occlusion_texture_index)
	w_f32(out, m.occlusion_strength)
	w_i32(out, m.emissive_texture_index)
	w_vec3(out, m.emissive_factor)
	w_f32(out, m.normal_scale)
}

// C# BinaryWriter.Write(string)：7-bit 变长长度前缀 + UTF-8 字节。
@(private)
w_string :: proc(out: ^[dynamic]u8, s: string) {
	n := u32(len(s))
	for n >= 0x80 {
		append(out, u8(n) | 0x80)
		n >>= 7
	}
	append(out, u8(n))
	append(out, ..transmute([]u8)s)
}

// ------------------------------------------------------------------------------
// 内部 —— 读辅助（游标越界返回零值/false）
// ------------------------------------------------------------------------------

@(private)
r_u8 :: proc(data: []u8, cur: ^int) -> (u8, bool) {
	if cur^ >= len(data) {
		cur^ = len(data) + 1 // 推进游标防止后续误读
		return 0, false
	}
	v := data[cur^]
	cur^ += 1
	return v, true
}

@(private)
r_u32 :: proc(data: []u8, cur: ^int) -> (u32, bool) {
	if cur^ + 4 > len(data) { cur^ = len(data) + 1; return 0, false }
	v := u32(data[cur^]) | u32(data[cur^ + 1]) << 8 | u32(data[cur^ + 2]) << 16 | u32(data[cur^ + 3]) << 24
	cur^ += 4
	return v, true
}

@(private)
r_i32 :: proc(data: []u8, cur: ^int) -> (i32, bool) {
	v, ok := r_u32(data, cur)
	return cast(i32)v, ok
}

@(private)
r_f32 :: proc(data: []u8, cur: ^int) -> f32 {
	v, _ := r_u32(data, cur)
	return transmute(f32)v
}

@(private)
r_vec3 :: proc(data: []u8, cur: ^int) -> [3]f32 {
	return [3]f32{r_f32(data, cur), r_f32(data, cur), r_f32(data, cur)}
}

@(private)
r_vec4 :: proc(data: []u8, cur: ^int) -> [4]f32 {
	return [4]f32{r_f32(data, cur), r_f32(data, cur), r_f32(data, cur), r_f32(data, cur)}
}

// 读元素计数并校验：非负，且按 element_size 换算不超过剩余字节。
@(private)
r_count :: proc(data: []u8, cur: ^int, element_size: int) -> (int, bool) {
	count, ok := r_i32(data, cur)
	if !ok || count < 0 {
		return 0, false
	}
	remaining := len(data) - cur^
	if int(count) * element_size > remaining {
		return 0, false
	}
	return int(count), true
}

@(private)
r_string :: proc(data: []u8, cur: ^int) -> (string, bool) {
	// 7-bit 变长长度
	n := 0
	shift := 0
	for {
		b, ok := r_u8(data, cur)
		if !ok { return "", false }
		n |= int(b & 0x7F) << u32(shift)
		if b & 0x80 == 0 { break }
		shift += 7
		if shift > 28 { return "", false }
	}
	if n < 0 || cur^ + n > len(data) { return "", false }
	s := clone_owned(string(data[cur^:cur^ + n]))
	cur^ += n
	return s, true
}

@(private)
clone_owned :: proc(s: string) -> string {
	out, _ := strings.clone(s, context.allocator)
	return out
}

@(private)
clone_bytes :: proc(b: []u8) -> []u8 {
	if b == nil { return nil }
	out := make([]u8, len(b))
	mem.copy(raw_data(out), raw_data(b), len(b))
	return out
}
