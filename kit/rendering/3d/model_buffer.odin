package rendering3d

// 模型缓冲：调用方持有的 GPU 顶点缓冲（按实例步进），用于 instanced 模型效果的大批量绘制（与 Sprite_Buffer 对应）。
// 库不缓存、不排序、不剔除：调用方决定哪些实例写入、分成几块（每块一个缓冲，按块剔除）、何时更新。
// 分区：类型 / 创建与释放 / 上传。
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"
import sh "olib:kit/rendering/shader"
import world "olib:kit/world"

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 一个实例的数据：世界矩阵与 tint。
// [Instance] 字段的数值不放在这里：个数由效果决定，由调用方另备一个平铺数组，上传时一并传入
// （model_buffer_upload 的 values，用 mat.instance_array_set 写入）。
// 内存布局就是 GPU 记录的前 80 字节：没有 [Instance] 字段时整块上传。
Model_Item :: struct {
	world: world.Matrix4,
	tint: [4]f32,
}
#assert(size_of(Model_Item) == 80)

// 缓冲里每个实例按 世界矩阵(64B) + tint(16B) + slots × 16B 紧凑排列；
// slots 是材质效果的 [Instance] 字段数（init 时读取）。大批量静态场景只需上传一次，动画交给着色器（Clock）。
Model_Buffer :: struct {
	buffer: foster.VertexBuffer,
	slots: int,
	capacity: int,
}

@(private)
MODEL_BASE_BYTES :: 64 + 16

@(private)
model_stride :: proc(slots: int) -> int {
	return MODEL_BASE_BYTES + 16*slots
}

// ------------------------------------------------------------------------------
// 创建与释放
// ------------------------------------------------------------------------------

// 为 material 的 instanced 效果预留 capacity 个实例的 GPU 空间（实际按 2 的幂向上取整）。
// 设备与槽数取自材质；成功返回空串，失败返回原因。
// 属性位置固定为 0..4+slots（世界矩阵 4 列、tint、字段）：HLSL 里 OlibInstanceInput 须是 Input
// 的第一个成员，绘制时网格的属性整体后移，同一缓冲可用于不同网格。
model_buffer_init :: proc(buf: ^Model_Buffer, material: ^mat.Material, capacity: int, name := "") -> string {
	if material == nil || material.owner == nil || material.shader == nil do return "Missing material"
	if material.owner.device == nil do return "Missing graphics device"
	slots := mat.instance_slot_count(material)
	if !material.shader.desc.instanced do return "Material shader is not instanced"
	if capacity <= 0 do return "Instance capacity must be positive"
	if slots < 0 || slots > sh.MAX_INSTANCE_FIELDS do return "Inconsistent instance field count"
	model_buffer_create(buf, material.owner.device, slots, capacity, name)
	return ""
}

// 按槽数创建缓冲，不经材质；参数由调用方校验。Render3D 的临时实例缓冲按槽数共用，
// Shader Lab 建 instanced 模型的管线时也用它（只需格式，不上传实例）。
model_buffer_create :: proc(buf: ^Model_Buffer, device: ^foster.GraphicsDevice, slots, capacity: int, name: string) {
	elements := make([]foster.VertexElement, sh.INSTANCE_FIXED_ATTRIBUTES+slots, context.temp_allocator)
	for i in 0..<len(elements) do elements[i] = {i, .Float4, false}
	format := foster.VertexFormatMake(elements, model_stride(slots))
	defer foster.VertexFormatDispose(&format)
	buf^ = {slots = slots, capacity = capacity}
	foster.VertexBufferInit(&buf.buffer, device, format, name)
	foster.VertexBufferReserve(&buf.buffer, capacity)
}

// 把网格的绘制命令改成实例化：网格属性排在实例属性之后（Shader 里 OlibInstanceInput 是 Input 的第一个成员），
// 再追加实例缓冲。shifted 是改了属性位置的顶点缓冲副本，须保持到绘制或建管线结束，之后 VertexFormatDispose(&shifted.Format)。
model_instanced_command :: proc(command: ^foster.DrawCommand, mesh: ^foster.Mesh, buf: ^Model_Buffer, shifted: ^foster.VertexBuffer) {
	shifted^ = mesh.VertexData
	shifted.Format = foster.VertexFormatClone(mesh.VertexData.Format)
	for &element in shifted.Format.Elements do element.Index += sh.INSTANCE_FIXED_ATTRIBUTES + buf.slots
	command.VertexBuffers[0].Buffer = shifted
	append(&command.VertexBuffers, foster.VertexBufferBinding{Buffer = &buf.buffer, InstanceInputRate = true})
}

model_buffer_dispose :: proc(buf: ^Model_Buffer) {
	if buf.capacity > 0 do foster.VertexBufferDispose(&buf.buffer)
	buf^ = {}
}

// ------------------------------------------------------------------------------
// 上传
// ------------------------------------------------------------------------------

// 一次最多拼接上传的实例数：限制临时内存；更大的批量分段写入。
@(private)
INSTANCE_UPLOAD_CHUNK :: 262144

// 把 instances 写到缓冲的第 first 个实例起的位置（部分更新只需传变化的区间）。
// values 是这批实例的 [Instance] 数值：平铺数组，每个实例连续 buf.slots 个 float4，长度须为 len(instances) × slots
// （用 mat.instance_array_set 写入）；slots 为 0 或传 nil（全部为 0）时可省略。
// 没有 [Instance] 字段时 instances 整块拷贝到 GPU；有字段时按实例拼接两块内存。
// 超出容量或 values 长度不对返回 false 且不写入。帧内上传会占用设备的暂存区，百万级请在加载时一次性上传。
model_buffer_upload :: proc(buf: ^Model_Buffer, instances: []Model_Item, first := 0,
	values: [][4]f32 = nil) -> bool {
	if buf.capacity <= 0 || first < 0 || first + len(instances) > buf.capacity do return false
	slots := buf.slots
	if values != nil && len(values) != len(instances)*slots do return false
	if slots == 0 {
		// 与 Model_Item 同一布局，可直接上传。
		foster.VertexBufferUpload(&buf.buffer, raw_data(instances), len(instances), first)
		return true
	}
	stride := model_stride(slots)
	scratch := make([]u8, min(len(instances), INSTANCE_UPLOAD_CHUNK)*stride)
	defer delete(scratch)
	value_bytes := 16*slots
	for start := 0; start < len(instances); start += INSTANCE_UPLOAD_CHUNK {
		chunk := instances[start:min(start+INSTANCE_UPLOAD_CHUNK, len(instances))]
		for i in 0..<len(chunk) {
			record := raw_data(scratch[i*stride:])
			mem.copy(record, &chunk[i], size_of(Model_Item))
			if values != nil {
				mem.copy(rawptr(uintptr(record) + size_of(Model_Item)), &values[(start+i)*slots], value_bytes)
			} else {
				mem.zero(rawptr(uintptr(record) + size_of(Model_Item)), value_bytes)
			}
		}
		foster.VertexBufferUpload(&buf.buffer, raw_data(scratch), len(chunk), first+start)
	}
	return true
}
