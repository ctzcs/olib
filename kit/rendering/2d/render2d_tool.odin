package rendering2d

// Shader Lab 的立即绘制入口：用调用方自己管理的 GPU 绑定（不是 mat.Material）立刻画一个精灵，
// 保留预览需要的 pass_limit、启用列表与 prepare / submit 回调。业务使用 Render2D 的记录接口（image 等）。
// 借用 Render2D 的设备；与记录中的图元无关，不影响下一次 submit。
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"

Material_Draw2D :: struct {
	frame: foster.Subtexture,
	origin: foster.Vec2,
	transform: foster.Matrix3x2,
	view: View,
	color: foster.Color, // 顶点色（tint）
	pass_limit: int, // 0 绘制全部，否则只绘制前 N 个 Pass
	options: mat.Draw_Options,
}

@(private)
Render2D_Tool_Submission :: struct {
	r: ^Render2D,
	slots: int,
	user: mat.Draw_Options, // 调用方原本的回调，包装回调转发给它
}

material_draw :: proc(r: ^Render2D, effect: mat.Effect_Desc, bindings: []mat.Material_Binding,
	draw: Material_Draw2D) -> mat.Draw_Error {
	if r.library == nil || r.library.device == nil do return .Missing_Device
	if !mat.effect_is_sprite(effect) do return .Not_Material_Effect
	w, h := draw.view.target.WidthInPixels, draw.view.target.HeightInPixels
	if w <= 0 || h <= 0 do return .Invalid_Target
	device := r.library.device
	if !r.tool_ready {
		format := foster.BatcherVertexFormat()
		defer foster.VertexFormatDispose(&format)
		foster.MeshInitWithFormat(&r.tool_mesh, device, format, .ThirtyTwo, "render2d tool quad")
		indices := [6]u32{0, 1, 2, 0, 2, 3}
		foster.MeshSetIndicesTyped(u32, &r.tool_mesh, indices[:])
		r.tool_ready = true
	}
	// tool_mesh 存着这次的四边形；回调重建命令时可用 r.tool_mesh 作几何。
	slots := 0
	if effect.uniforms == .Olib {
		for binding in bindings do slots = max(slots, mat.instance_count(binding.schema))
	}
	// 有 [Instance] 字段时数值在 storage buffer 的偏移 1 处（每个 Pass 绘制前写入），否则 mode 选 Normal。
	mode := slots > 0 ? foster.Color{1, 0, 0, 0} : render2d_mode_color(.Normal)
	vertices: [4]foster.BatcherVertex
	corners := render2d_frame_corners(draw.frame, draw.origin, draw.transform)
	for &vertex, i in vertices {
		vertex = {Pos = corners[i], Tex = draw.frame.TexCoords[i], Col = draw.color, Mode = mode}
	}
	foster.MeshSetVerticesTyped(foster.BatcherVertex, &r.tool_mesh, vertices[:])
	projection := [16]f32{2/f32(w), 0, 0, 0, 0, -2/f32(h), 0, 0, 0, 0, 1, 0, -1, 1, 0, 1}
	view := draw.view
	frame := [12]f32{view.time, view.delta_time, f32(view.frame), 1, view.pointer[0], view.pointer[1],
		f32(w), f32(h), 1, 1, 1, 1}
	submission := Render2D_Tool_Submission{r, slots, draw.options}
	options := draw.options
	if slots > 0 {
		options.user_data = &submission
		options.prepare = render2d_tool_prepare
		options.submit = draw.options.submit != nil ? render2d_tool_submit : nil
	}
	return mat.material_draw(device, effect, bindings, {
		mesh = &r.tool_mesh, target = view.target, kind = .Sprite,
		vertex_uniform = mem.slice_to_bytes(projection[:]), frame_uniform = mem.slice_to_bytes(frame[:]),
		sprite_texture = draw.frame.Texture, pass_limit = draw.pass_limit, options = options,
	})
}

// 每个 Pass 的 [Instance] 数值不同：先转交调用方的回调（它可能整条替换命令），再把数值写进
// storage buffer 偏移 1 处并绑定到最终的命令上。
@(private)
render2d_tool_prepare :: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	submission := cast(^Render2D_Tool_Submission)user_data
	user := submission.user
	if user.prepare != nil do user.prepare(user.user_data, pass_index, command, values)
	r := submission.r
	pass_offset := [4]u32{}
	foster.MaterialStageSetUniformBuffer(&command.Material.Vertex, mem.slice_to_bytes(pass_offset[:]), 1)
	if !r.tool_values_ready {
		foster.StorageBufferInitTyped([4]f32, &r.tool_values, r.library.device, "render2d tool instance values")
		r.tool_values_ready = true
	}
	data: [1 + mat.MAX_INSTANCE_FIELDS][4]f32
	if values != nil do copy(data[1:], values.numbers[:submission.slots])
	foster.StorageBufferUploadTyped([4]f32, &r.tool_values, data[:1 + submission.slots])
	append(&command.VertexStorageBuffers, &r.tool_values)
}

@(private)
render2d_tool_submit :: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	user := (cast(^Render2D_Tool_Submission)user_data).user
	user.submit(user.user_data, pass_index, command, values)
}
