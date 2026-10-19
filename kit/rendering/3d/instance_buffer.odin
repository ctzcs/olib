package rendering3d

// 模型实例缓冲：调用方持有的 GPU 顶点缓冲（按实例步进），用于 instanced 模型效果的大批量绘制。
// 库不缓存、不排序、不剔除：调用方决定哪些实例写入、分成几块（每块一个缓冲，按块剔除）、何时更新。
// 分区：类型 / 创建与释放 / 上传。
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 一个实例的数据：世界矩阵、tint，以及 [Instance] 字段数值（按效果里的字段顺序，只用前 slots 个）。
Model_Instance :: struct {
	world: world.Matrix4,
	tint: [4]f32,
	values: [mat.MAX_INSTANCE_FIELDS][4]f32,
}

// 缓冲里每个实例按 世界矩阵(64B) + tint(16B) + slots × 16B 紧凑排列；
// slots 须等于效果的 [Instance] 字段数。大批量静态场景只需上传一次，动画交给着色器（Clock）。
Instance_Buffer :: struct {
	buffer: foster.VertexBuffer,
	slots: int,
	capacity: int,
}

INSTANCE_BASE_BYTES :: 64 + 16

instance_buffer_stride :: proc(slots: int) -> int {
	return INSTANCE_BASE_BYTES + 16*slots
}

// ------------------------------------------------------------------------------
// 创建与释放
// ------------------------------------------------------------------------------

// 预留 capacity 个实例的 GPU 空间（实际按 2 的幂向上取整）。slots 为效果的 [Instance] 字段数。
// 属性位置固定为 0..4+slots（世界矩阵 4 列、tint、字段）：HLSL 里 OlibInstanceInput 须是 Input
// 的第一个成员，绘制时网格的属性整体后移，同一缓冲可用于不同网格。
instance_buffer_init :: proc(buf: ^Instance_Buffer, device: ^foster.GraphicsDevice, capacity: int,
	slots := 0, name := "") -> bool {
	if device == nil || capacity <= 0 || slots < 0 || slots > mat.MAX_INSTANCE_FIELDS do return false
	elements := make([]foster.VertexElement, 5+slots, context.temp_allocator)
	for i in 0..<len(elements) do elements[i] = {i, .Float4, false}
	format := foster.VertexFormatMake(elements, instance_buffer_stride(slots))
	defer foster.VertexFormatDispose(&format)
	buf^ = {slots = slots, capacity = capacity}
	foster.VertexBufferInit(&buf.buffer, device, format, name)
	foster.VertexBufferReserve(&buf.buffer, capacity)
	return true
}

instance_buffer_dispose :: proc(buf: ^Instance_Buffer) {
	if buf.capacity > 0 do foster.VertexBufferDispose(&buf.buffer)
	buf^ = {}
}

// ------------------------------------------------------------------------------
// 上传
// ------------------------------------------------------------------------------

// 一次最多打包上传的实例数：限制临时内存；更大的批量分段写入。
@(private)
INSTANCE_UPLOAD_CHUNK :: 65536

// 把 instances 写到缓冲的第 first 个实例起的位置（部分更新只需传变化的区间）。
// 超出容量返回 false 且不写入。帧内上传会占用设备的暂存区，百万级请在加载时一次性上传。
instance_buffer_upload :: proc(buf: ^Instance_Buffer, instances: []Model_Instance, first := 0) -> bool {
	if buf.capacity <= 0 || first < 0 || first + len(instances) > buf.capacity do return false
	stride := instance_buffer_stride(buf.slots)
	if buf.slots == mat.MAX_INSTANCE_FIELDS {
		// 与 Model_Instance 同一布局，可直接上传。
		foster.VertexBufferUpload(&buf.buffer, raw_data(instances), len(instances), first)
		return true
	}
	scratch := make([]u8, min(len(instances), INSTANCE_UPLOAD_CHUNK)*stride)
	defer delete(scratch)
	for start := 0; start < len(instances); start += INSTANCE_UPLOAD_CHUNK {
		chunk := instances[start:min(start+INSTANCE_UPLOAD_CHUNK, len(instances))]
		for instance, i in chunk {
			instance := instance
			base := i*stride
			mem.copy(raw_data(scratch[base:]), &instance.world, 64)
			mem.copy(raw_data(scratch[base+64:]), &instance.tint, 16)
			if buf.slots > 0 do mem.copy(raw_data(scratch[base+80:]), &instance.values, 16*buf.slots)
		}
		foster.VertexBufferUpload(&buf.buffer, raw_data(scratch), len(chunk), first+start)
	}
	return true
}
