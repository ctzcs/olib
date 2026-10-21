package rendering2d

// 精灵实例缓冲：调用方持有、常驻显存的 GPU 缓冲，r2d.buffer 一次 Draw 画出几十万到上百万个精灵。
// 库不缓存、不排序、不剔除：调用方决定写入哪些精灵、何时更新、分成几块。
// 使用 instanced 精灵效果的缓冲变体（实例记录 + 角点）；逐个绘制走 Render2D 的批量变体，片元代码相同。
// 分区：实例记录 / 缓冲创建与上传。
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"
import sh "olib:kit/rendering/shader"

// ------------------------------------------------------------------------------
// 实例记录 —— 一个精灵的数据
// ------------------------------------------------------------------------------

// 一个精灵的数据：2D 变换、局部矩形（已减去锚点）、UV 矩形与 tint。
// 内存布局就是 GPU 记录的前 80 字节（与 hlsl 生成的 OlibInstanceInput 的前 5 个 float4 一致），
// 没有 [Instance] 字段时整块上传，有字段时按块拷贝拼接，不做逐字段打包。
// [Instance] 字段的数值不放在这里：它们的个数由效果决定，由调用方另备一个平铺数组，上传时一并传入
// （sprite_buffer_upload 的 values，用 mat.instance_array_set 写入）。
// 一次 Draw 里所有精灵共用同一张贴图（图集页），贴图在 r2d.buffer 时指定。
Sprite_Item :: struct {
	transform: foster.Matrix3x2,
	rect: [4]f32, // 局部 x0, y0, 宽, 高（像素，已减去锚点）
	uv: [4]f32, // u0, v0, 宽, 高
	_: [2]f32, // GPU 布局的保留字节，由 sprite_item_make 置零
	tint: [4]f32,
}
#assert(size_of(Sprite_Item) == 80 && offset_of(Sprite_Item, rect) == 24 &&
	offset_of(Sprite_Item, uv) == 40 && offset_of(Sprite_Item, tint) == 64)

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
	return sh.INSTANCE_FIXED_ATTRIBUTES*16 + 16*slots
}

// 实例缓冲的顶点格式：每个 float4 一个属性，位置 0..4+slots（角点网格的属性整体后移）。
@(private)
sprite_instance_format :: proc(slots: int) -> foster.VertexFormat {
	elements := make([]foster.VertexElement, sh.INSTANCE_FIXED_ATTRIBUTES+slots, context.temp_allocator)
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

// 为 material 的 instanced 效果预留 capacity 个精灵的 GPU 空间（实际按 2 的幂向上取整），用 r2d.buffer 绘制。
// 设备与槽数（效果的 [Instance] 字段数）都取自材质。返回 "" 表示成功，否则是失败原因。
// 每个精灵 80 + 16×slots 字节，100 万个精灵（1 个字段）约 96 MB。
sprite_buffer_init :: proc(buf: ^Sprite_Buffer, material: ^mat.Material, capacity: int, name := "") -> string {
	if material == nil || material.owner == nil || material.owner.device == nil || material.shader == nil {
		return "Material is not loaded"
	}
	if !sh.shader_is_sprite(material.shader.desc) || !material.shader.desc.instanced {
		return "Sprite buffers require an Instanced sprite shader"
	}
	slots := mat.instance_slot_count(material)
	if slots < 0 do return "Instance field count differs between parameter groups"
	if slots > sh.MAX_INSTANCE_FIELDS do return "Too many Instance fields"
	if capacity <= 0 do return "Sprite buffer capacity must be positive"
	format := sprite_instance_format(slots)
	defer foster.VertexFormatDispose(&format)
	buf^ = {slots = slots, capacity = capacity}
	foster.VertexBufferInit(&buf.buffer, material.owner.device, format, name)
	foster.VertexBufferReserve(&buf.buffer, capacity)
	return ""
}

sprite_buffer_dispose :: proc(buf: ^Sprite_Buffer) {
	if buf.capacity > 0 do foster.VertexBufferDispose(&buf.buffer)
	buf^ = {}
}

// 一次最多拼接上传的精灵数：限制临时内存；更大的批量分段写入。
@(private)
SPRITE_UPLOAD_CHUNK :: 262144

// 把 items 写到缓冲第 first 个精灵起的位置（部分更新只需传变化的区间）。
// values 是这批精灵的 [Instance] 数值：平铺数组，每个精灵连续 buf.slots 个 float4，长度须为 len(items) × slots
// （用 mat.instance_array_set 写入）；slots 为 0 或传 nil（全部为 0）时可省略。
// 没有 [Instance] 字段时 items 整块拷贝到 GPU；有字段时按精灵拼接 items 与 values 两块内存。
// 超出容量或 values 长度不对返回 false 且不写入。帧内上传会占用设备暂存区，百万级请在加载时一次性上传。
sprite_buffer_upload :: proc(buf: ^Sprite_Buffer, items: []Sprite_Item, first := 0,
	values: [][4]f32 = nil) -> bool {
	if buf.capacity <= 0 || first < 0 || first + len(items) > buf.capacity do return false
	slots := buf.slots
	if values != nil && len(values) != len(items)*slots do return false
	if slots == 0 {
		// 与 GPU 记录同一布局，直接上传。
		foster.VertexBufferUpload(&buf.buffer, raw_data(items), len(items), first)
		return true
	}
	stride := sprite_stride(slots)
	scratch := make([]u8, min(len(items), SPRITE_UPLOAD_CHUNK)*stride)
	defer delete(scratch)
	value_bytes := 16*slots
	for start := 0; start < len(items); start += SPRITE_UPLOAD_CHUNK {
		chunk := items[start:min(start+SPRITE_UPLOAD_CHUNK, len(items))]
		for i in 0..<len(chunk) {
			record := raw_data(scratch[i*stride:])
			mem.copy(record, &chunk[i], size_of(Sprite_Item))
			if values != nil {
				mem.copy(rawptr(uintptr(record) + size_of(Sprite_Item)), &values[(start+i)*slots], value_bytes)
			} else {
				mem.zero(rawptr(uintptr(record) + size_of(Sprite_Item)), value_bytes)
			}
		}
		foster.VertexBufferUpload(&buf.buffer, raw_data(scratch), len(chunk), first+start)
	}
	return true
}
