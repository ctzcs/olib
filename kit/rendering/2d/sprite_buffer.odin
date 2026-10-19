package rendering2d

// 精灵实例缓冲：调用方持有的 GPU 缓冲，一次 Draw 画出几十万到上百万个精灵（instanced 材质效果）。
// 库不缓存、不排序、不剔除：调用方决定写入哪些精灵、何时更新、分成几块。
// 逐个 sprite_draw 的 instanced 精灵内部也使用同样的实例记录自动合批，两者共用一份着色器。
// 分区：实例记录 / 缓冲创建与上传 / 绘制。
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"

// ------------------------------------------------------------------------------
// 实例记录 —— 一个精灵的数据
// ------------------------------------------------------------------------------

// 一个精灵的数据：2D 变换、局部矩形（已减去锚点）、UV 矩形与 tint。
// [Instance] 字段的数值不放在这里：它们的个数由效果决定，由调用方另备一个平铺数组，上传时一并传入
// （sprite_buffer_upload 的 values，用 mat.instance_array_set 写入）。
// 一次 Draw 里所有精灵共用同一张贴图（图集页），贴图在 sprite_draw_buffer 时指定。
Sprite_Item :: struct {
	transform: foster.Matrix3x2,
	rect: [4]f32, // 局部 x0, y0, 宽, 高（像素，已减去锚点）
	uv: [4]f32, // u0, v0, 宽, 高
	tint: [4]f32,
}

// 由图集子图构造：保留裁剪后的 DrawCoords / TexCoords；origin 相对于未裁剪原图。
sprite_item_make :: proc(frame: foster.Subtexture, origin: foster.Vec2, transform: foster.Matrix3x2,
	tint: [4]f32 = {1, 1, 1, 1}) -> Sprite_Item {
	top_left := frame.DrawCoords[0] - origin
	bottom_right := frame.DrawCoords[2] - origin
	uv0, uv1 := frame.TexCoords[0], frame.TexCoords[2]
	return {
		transform = transform,
		rect = {top_left.x, top_left.y, bottom_right.x - top_left.x, bottom_right.y - top_left.y},
		uv = {uv0.x, uv0.y, uv1.x - uv0.x, uv1.y - uv0.y},
		tint = tint,
	}
}

// 实例记录在 GPU 上的字节数：5 个 float4（变换、矩形、UV、tint）加每个字段一个 float4。
@(private)
sprite_stride :: proc(slots: int) -> int {
	return mat.INSTANCE_FIXED_ATTRIBUTES*16 + 16*slots
}

// 把一个精灵写成 GPU 记录：与 hlsl 生成的 OlibInstanceInput / olib_sprite_vertex 的约定一致。
// dst 至少 sprite_stride(slots) 字节；values 是这个精灵的 [Instance] 数值（至多 slots 个，不足的补 0）。
@(private)
sprite_item_pack :: proc(dst: []u8, item: Sprite_Item, slots: int, values: [][4]f32 = nil) {
	item := item // 取字段地址需要一个可寻址的副本
	t := item.transform
	head := [20]f32{
		t.M11, t.M12, t.M21, t.M22,
		t.M31, t.M32, item.rect[0], item.rect[1],
		item.rect[2], item.rect[3], item.uv[0], item.uv[1],
		item.uv[2], item.uv[3], 0, 0,
		item.tint[0], item.tint[1], item.tint[2], item.tint[3],
	}
	mem.copy(raw_data(dst), &head, 80)
	if slots <= 0 do return
	copied := min(len(values), slots)
	if copied > 0 do mem.copy(raw_data(dst[80:]), raw_data(values), 16*copied)
	if copied < slots do mem.zero(raw_data(dst[80+16*copied:]), 16*(slots-copied))
}

// 实例缓冲的顶点格式：每个 float4 一个属性，位置 0..4+slots（角点网格的属性整体后移）。
@(private)
sprite_instance_format :: proc(slots: int) -> foster.VertexFormat {
	elements := make([]foster.VertexElement, mat.INSTANCE_FIXED_ATTRIBUTES+slots, context.temp_allocator)
	for i in 0..<len(elements) do elements[i] = {i, .Float4, false}
	return foster.VertexFormatMake(elements, sprite_stride(slots))
}

// ------------------------------------------------------------------------------
// 缓冲创建与上传
// ------------------------------------------------------------------------------

Sprite_Buffer :: struct {
	buffer: foster.VertexBuffer,
	slots: int,
	capacity: int,
}

// 预留 capacity 个精灵的 GPU 空间（实际按 2 的幂向上取整）。slots 为效果的 [Instance] 字段数。
// 每个精灵 80 + 16×slots 字节，100 万个精灵（1 个字段）约 96 MB。
sprite_buffer_init :: proc(buf: ^Sprite_Buffer, device: ^foster.GraphicsDevice, capacity: int,
	slots := 0, name := "") -> bool {
	if device == nil || capacity <= 0 || slots < 0 || slots > mat.MAX_INSTANCE_FIELDS do return false
	format := sprite_instance_format(slots)
	defer foster.VertexFormatDispose(&format)
	buf^ = {slots = slots, capacity = capacity}
	foster.VertexBufferInit(&buf.buffer, device, format, name)
	foster.VertexBufferReserve(&buf.buffer, capacity)
	return true
}

sprite_buffer_dispose :: proc(buf: ^Sprite_Buffer) {
	if buf.capacity > 0 do foster.VertexBufferDispose(&buf.buffer)
	buf^ = {}
}

// 一次最多打包上传的精灵数：限制临时内存；更大的批量分段写入。
@(private)
SPRITE_UPLOAD_CHUNK :: 65536

// 把 items 写到缓冲第 first 个精灵起的位置（部分更新只需传变化的区间）。
// values 是这批精灵的 [Instance] 数值：平铺数组，每个精灵连续 buf.slots 个 float4，长度须为 len(items) × slots
// （用 mat.instance_array_set 写入）；slots 为 0 或传 nil（全部为 0）时可省略。
// 超出容量或 values 长度不对返回 false 且不写入。帧内上传会占用设备暂存区，百万级请在加载时一次性上传。
sprite_buffer_upload :: proc(buf: ^Sprite_Buffer, items: []Sprite_Item, first := 0,
	values: [][4]f32 = nil) -> bool {
	if buf.capacity <= 0 || first < 0 || first + len(items) > buf.capacity do return false
	slots := buf.slots
	if values != nil && len(values) != len(items)*slots do return false
	stride := sprite_stride(slots)
	scratch := make([]u8, min(len(items), SPRITE_UPLOAD_CHUNK)*stride)
	defer delete(scratch)
	for start := 0; start < len(items); start += SPRITE_UPLOAD_CHUNK {
		chunk := items[start:min(start+SPRITE_UPLOAD_CHUNK, len(items))]
		for item, i in chunk {
			own: [][4]f32
			if values != nil do own = values[(start+i)*slots:(start+i+1)*slots]
			sprite_item_pack(scratch[i*stride:], item, slots, own)
		}
		foster.VertexBufferUpload(&buf.buffer, raw_data(scratch), len(chunk), first+start)
	}
	return true
}

// ------------------------------------------------------------------------------
// 绘制
// ------------------------------------------------------------------------------

// instanced 效果：缓冲里前 count 个精灵每个 Pass 一次 Draw，全部使用 texture（图集页）作为帧贴图。
// 先提交 begin/end 里已排队的精灵再绘制，保持调用顺序；pass_id 为空画全部启用的 Pass，规则同 sprite_draw。
// [Instance] 字段的数据以缓冲为准；统一参数（非 [Instance]）来自材质，整批共用。
sprite_draw_buffer :: proc(renderer: ^Sprite_Renderer, material: ^mat.Material, buf: ^Sprite_Buffer,
	count: int, texture: ^foster.Texture, view: Sprite_View, pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if material.owner.device != renderer.device do return .Device_Mismatch
	if buf == nil || buf.capacity <= 0 do return .Instance_Mismatch
	w, h := view.target.WidthInPixels, view.target.HeightInPixels
	if w <= 0 || h <= 0 do return .Invalid_Target
	mesh := sprite_corner_mesh(renderer)
	if mesh == nil do return .Missing_Device
	sprite_flush(renderer)
	projection, frame := sprite_uniforms(view, {}, {1, 1, 1, 1})
	return mat.material_draw(renderer.device, material.effect.desc, material.bindings, {
		mesh = mesh, target = view.target, kind = .Sprite,
		vertex_uniform = mem.slice_to_bytes(projection[:]), frame_uniform = mem.slice_to_bytes(frame[:]),
		sprite_texture = texture, pass_limit = view.pass_limit,
		options = {pass_id = pass_id},
		instance_buffer = &buf.buffer, instance_count = clamp(count, 0, buf.capacity),
		instance_slots = buf.slots, mesh_location_offset = mat.INSTANCE_FIXED_ATTRIBUTES + buf.slots,
	})
}
