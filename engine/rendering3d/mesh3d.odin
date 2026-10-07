// rendering3d:mesh3d —— dasset 顶点 -> Foster Mesh 上传（对位 DragonLib MeshUpload3D）。
package rendering3d

import dasset "olib:core/dasset"
import foster "olib:foster"

// 分区：
//   顶点格式 —— 静态 / 蒙皮（与 dasset 二进制布局一致）
//   上传 —— dasset primitive -> Foster Mesh

// ------------------------------------------------------------------------------
// 顶点格式 —— 静态 / 蒙皮
// ------------------------------------------------------------------------------

// 静态顶点格式：Float3 位置 + Float3 法线 + Float2 UV + Float4 切线（48B）。
mesh3d_static_format :: proc() -> foster.VertexFormat {
	return foster.vertex_format_make(
		[]foster.VertexElement{
			{0, .Float3, false},
			{1, .Float3, false},
			{2, .Float2, false},
			{3, .Float4, false},
		},
		dasset.DASSET_VERTEX_STRIDE_STATIC,
	)
}

// 蒙皮顶点格式：静态布局 + UByte4 关节 + Float4 权重（68B）。
mesh3d_skin_format :: proc() -> foster.VertexFormat {
	return foster.vertex_format_make(
		[]foster.VertexElement{
			{0, .Float3, false},
			{1, .Float3, false},
			{2, .Float2, false},
			{3, .Float4, false},
			{4, .UByte4, false},
			{5, .Float4, false},
		},
		dasset.DASSET_VERTEX_STRIDE_SKIN,
	)
}

// ------------------------------------------------------------------------------
// 上传 —— dasset primitive -> Foster Mesh
// ------------------------------------------------------------------------------

// 把 dasset primitive 的顶点/索引整块上传为 Foster Mesh。
// 顶点是 #packed 不了的普通 struct，但 dasset 布局与格式步长一致，
// 直接按字节整块拷贝。失败（空 primitive / 无 device）返回 false。
mesh3d_upload :: proc(mesh: ^foster.Mesh, device: ^foster.GraphicsDevice, p: ^dasset.Dasset_Primitive, name := "") -> bool {
	if device == nil { return false }

	skinned := dasset.dasset_primitive_is_skinned(p)
	format := skinned ? mesh3d_skin_format() : mesh3d_static_format()
	defer foster.vertex_format_dispose(&format)

	foster.mesh_init_with_format(mesh, device, format, .ThirtyTwo, name)

	if skinned {
		if p.skin_vertices == nil { return false }
		foster.mesh_set_vertex_count(mesh, len(p.skin_vertices))
		foster.mesh_set_vertices(mesh, raw_data(p.skin_vertices), len(p.skin_vertices))
	} else {
		if p.vertices == nil { return false }
		foster.mesh_set_vertex_count(mesh, len(p.vertices))
		foster.mesh_set_vertices(mesh, raw_data(p.vertices), len(p.vertices))
	}
	foster.mesh_set_index_count(mesh, len(p.indices))
	foster.mesh_set_indices(mesh, raw_data(p.indices), len(p.indices))
	return true
}

// 释放 Mesh 的 GPU 缓冲。终止态调用。
mesh3d_dispose :: proc(mesh: ^foster.Mesh) {
	if mesh == nil { return }
	foster.vertex_buffer_dispose(&mesh.VertexData)
	foster.index_buffer_dispose(&mesh.IndexData)
	if mesh.HasInstanceBuffer {
		foster.vertex_buffer_dispose(&mesh.InstanceData)
	}
	mesh^ = {}
}
