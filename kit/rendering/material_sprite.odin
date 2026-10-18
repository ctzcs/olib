package rendering

// 材质 Sprite 为立即绘制；每个对象按声明顺序提交全部 Pass，不进入 Batcher。
// 分区：实例与视图 / 网格生命周期 / 几何准备 / 绘制。
import "core:mem"
import foster "olib:foster"
import mat "olib:kit/material"

// 帧动画资源 Sprite 不保存对象状态；各绘制对象独立持有材质参数和当前帧。
Sprite_Instance :: struct {
	frame: foster.Subtexture,
	origin: foster.Vec2,
	material: ^Material,
}
Sprite_View :: struct {
	target: foster.DrawableTarget,
	time, delta_time: f32,
	frame: u64,
	pass_limit: int,
}
Sprite_Renderer :: struct {
	device: ^foster.GraphicsDevice,
	mesh: foster.Mesh,
}
Sprite_Vertex :: struct {
	position, uv: [2]f32,
}
Sprite_Material_Draw :: struct {
	frame: foster.Subtexture,
	origin: foster.Vec2,
	transform: foster.Matrix3x2,
	view: Sprite_View,
	tint: [4]f32,
	pointer: [2]f32,
	enabled: []bool,
	user_data: rawptr,
	prepare: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
	submit: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
}

// renderer 不得搬动；借用 device，所有材质 Sprite 可共用一份，dispose 释放网格。
sprite_renderer_init :: proc(renderer: ^Sprite_Renderer, device: ^foster.GraphicsDevice) {
	renderer.device = device
	format := foster.VertexFormatMake([]foster.VertexElement{
		{0, .Float2, false}, {1, .Float2, false},
	}, size_of(Sprite_Vertex))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(&renderer.mesh, device, format, .ThirtyTwo, "material sprite")
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	foster.MeshSetIndicesTyped(u32, &renderer.mesh, indices[:])
	vertices: [4]Sprite_Vertex
	foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, vertices[:])
}

sprite_renderer_dispose :: proc(renderer: ^Sprite_Renderer) {
	foster.MeshDispose(&renderer.mesh)
	renderer^ = {}
}

// 保留图集裁剪后的 DrawCoords / TexCoords；origin 相对于未裁剪原图。
sprite_vertices :: proc(frame: foster.Subtexture, origin: foster.Vec2,
	transform: foster.Matrix3x2) -> [4]Sprite_Vertex {
	vertices: [4]Sprite_Vertex
	for &vertex, i in vertices {
		point := foster.Matrix3x2TransformPoint(transform, frame.DrawCoords[i]-origin)
		vertex = {{point.x, point.y}, {frame.TexCoords[i].x, frame.TexCoords[i].y}}
	}
	return vertices
}

// 屏幕像素坐标：左上原点、向右/下为正；相机可先乘入 transform。
// Vertex b0 为 64 字节列主序投影，Fragment b0 为 Clock / Pointer / Tint，b1 为参数。
sprite_material_draw :: proc(renderer: ^Sprite_Renderer, effect: mat.Effect_Desc,
	bindings: []Material_Binding, draw: Sprite_Material_Draw) -> bool {
	if renderer.device == nil || !mat.effect_is_sprite(effect) do return false
	w, h := draw.view.target.WidthInPixels, draw.view.target.HeightInPixels
	if w <= 0 || h <= 0 do return false
	vertices := sprite_vertices(draw.frame, draw.origin, draw.transform)
	foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, vertices[:])
	projection := [16]f32{2/f32(w), 0, 0, 0, 0, -2/f32(h), 0, 0,
		0, 0, 1, 0, -1, 1, 0, 1}
	frame := [12]f32{draw.view.time, draw.view.delta_time, f32(draw.view.frame), 1,
		draw.pointer[0], draw.pointer[1], f32(w), f32(h),
		draw.tint[0], draw.tint[1], draw.tint[2], draw.tint[3]}
	return material_draw(renderer.device, effect, bindings, {
		mesh = &renderer.mesh, target = draw.view.target, kind = .Sprite,
		vertex_uniform = mem.slice_to_bytes(projection[:]), frame_uniform = mem.slice_to_bytes(frame[:]),
		sprite_texture = draw.frame.Texture, enabled = draw.enabled, pass_limit = draw.view.pass_limit,
		user_data = draw.user_data, prepare = draw.prepare, submit = draw.submit,
	})
}

// 混用 Batcher 时，先提交需要位于此 Sprite 下方的批次，再调用；此函数不隐式 flush。
sprite_draw :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1}) -> bool {
	material := sprite.material
	if material == nil || material.owner == nil || material.effect == nil ||
		material.owner.device != renderer.device {
		return false
	}
	return sprite_material_draw(renderer, material.effect.desc, material.bindings, {
		frame = sprite.frame, origin = sprite.origin, transform = transform, view = view, tint = tint,
	})
}
