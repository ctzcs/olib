package foster_framework

// [olib L-012] Graphics / Shader — 在实际绘制配置上验证后原位替换两个阶段。
// 必须在提交使用此 Shader 的绘制前调用；不允许存在尚未 flush 的 Batcher 命令。
// probes 应覆盖所有使用方式（顶点格式、目标格式、混合、深度、MSAA）。
// 借用 Code/Name/EntryPoint；成功后调用方才能释放旧 Code。
// 此函数保持 Shader 地址稳定，不复制或销毁材质的 uniform/纹理。
ShaderPairTryReplace :: proc(
	vertex, fragment: ^Shader,
	device: ^GraphicsDevice,
	vertex_info, fragment_info: ShaderCreateInfo,
	probes: []DrawCommand,
) -> (ok: bool, error: string) {
	if vertex == nil || fragment == nil || vertex == fragment || len(probes) == 0 {
		return false, "Shader replacement requires two shaders and draw probes"
	}
	if vertex_info.Stage != .Vertex || fragment_info.Stage != .Fragment {
		return false, "Shader replacement requires vertex and fragment stages"
	}
	if (vertex.Resource != nil && vertex.GraphicsDevice != device) ||
	   (fragment.Resource != nil && fragment.GraphicsDevice != device) {
		return false, "Shader replacement cannot change graphics device"
	}
	candidate_vertex: Shader
	if created, why := ShaderTryInit(&candidate_vertex, device, vertex_info, vertex.Name); !created {
		return false, why
	}
	candidate_fragment: Shader
	if created, why := ShaderTryInit(&candidate_fragment, device, fragment_info, fragment.Name); !created {
		ShaderDispose(&candidate_vertex)
		return false, why
	}
	accepted := false
	defer {
		if !accepted {
			ShaderDispose(&candidate_vertex)
			ShaderDispose(&candidate_fragment)
		}
	}
	material: Material
	MaterialInitWithShaders(&material, &candidate_vertex, &candidate_fragment)
	defer MaterialDispose(&material)
	for probe in probes {
		command := probe
		command.Material = &material
		if create_pipeline_for_draw_command(device, &command) == nil {
			return false, "Candidate shader pipeline rejected; previous shader retained (see GPU log)"
		}
	}
	ShaderDispose(vertex)
	ShaderDispose(fragment)
	vertex^ = candidate_vertex
	fragment^ = candidate_fragment
	accepted = true
	return true, ""
}
