package material

// 每个实例的 [Instance] 字段数值：按槽位（字段在效果里声明的先后）存放的小数组。
// 它是实例化合批的数据来源，也是唯一的"每实例值"形态：
//   - 逐个绘制时用 Instance_Values 给这一次绘制的实例设值（sprite_draw 的 values 参数）；
//   - 缓冲里的大批量实例用平铺的 [][4]f32（每个实例 slots 个，见 instance_array_set），长度由调用方的槽数决定。
// 名字只用来解析成句柄（instance_slot），之后全部按槽位赋值，没有字符串比较。
import "core:math"

// 字段名解析出的句柄。valid=false 表示材质里没有这个 [Instance] 字段（或各参数组里槽位不一致）。
Instance_Slot :: struct {
	index: int,
	valid: bool,
}

// 带掩码的槽位数组：逐个绘制的覆盖，以及材质回调拿到的一个 Pass 的实例数值。
// set 的第 i 位为 1 表示第 i 个槽位被显式设置，没设置的槽位沿用材质里保存的值。
Instance_Values :: struct {
	count: int, // 回调里：该 Pass 的 [Instance] 字段数；0 表示没有这类字段
	numbers: [MAX_INSTANCE_FIELDS][4]f32, // 下标是 Instance_Slot.index，每个槽一个 float4
	set: u32,
}

// 解析 [Instance] 字段的槽位：在每个参数组里按声明顺序数出它是第几个实例字段。
// 材质加载后调用一次并保存句柄，大批量赋值时不再查字符串。
instance_slot :: proc(material: ^Material, field: string) -> Instance_Slot {
	if material == nil || material.effect == nil do return {}
	found := false
	index := 0
	for schema in material.effect.schemas {
		rank := 0
		for f in schema.fields {
			if !f.instance do continue
			if f.id == field {
				if found && index != rank do return {} // 不同参数组里槽位不一致，无法用同一个句柄
				found, index = true, rank
			}
			rank += 1
		}
	}
	return {index, found}
}

// 材质效果的 [Instance] 字段数，即实例缓冲每个实例的槽数（sprite_buffer_init / model_buffer_init 用它）。
// 材质未加载返回 0；各参数组的字段数不一致时返回 -1（与 instance_slot 的规则一致，无法共用一个缓冲布局）。
instance_slot_count :: proc(material: ^Material) -> int {
	if material == nil || material.effect == nil do return 0
	count := -1
	for schema in material.effect.schemas {
		n := instance_count(schema)
		if count >= 0 && n != count do return -1
		count = n
	}
	return max(count, 0)
}

// 写平铺数组里第 index 个实例的一个字段：values 里每个实例连续占 slots 个 float4，按实例顺序排列
// （缓冲上传的 values 参数就是这个布局，长度 = 实例数 × slots）。
// value 依次是 x、y、z、w，只写用到的分量（Scalar 一个、Vector3 三个），没写的补 0；已有的 [4]f32 写成 ..v[:]。
// 句柄无效、越界或超过 4 个分量返回 false，不写入。
instance_array_set :: proc(values: [][4]f32, slots, index: int, slot: Instance_Slot, value: ..f32) -> bool {
	if !slot.valid || slot.index < 0 || slot.index >= slots || index < 0 || len(value) > 4 do return false
	at := index*slots + slot.index
	if at >= len(values) do return false
	values[at] = {}
	copy(values[at][:], value)
	return true
}

// 设置一个实例字段的值并记入掩码；value 的写法同 instance_array_set。句柄无效或超过 4 个分量返回 false，不写入。
instance_values_set :: proc(values: ^Instance_Values, slot: Instance_Slot, value: ..f32) -> bool {
	if values == nil || !slot.valid || slot.index < 0 || slot.index >= MAX_INSTANCE_FIELDS || len(value) > 4 do return false
	values.numbers[slot.index] = {}
	copy(values.numbers[slot.index][:], value)
	values.set |= 1 << u32(slot.index)
	values.count = max(values.count, slot.index+1)
	return true
}

// 平铺数组里一个实例的全部字段（该实例的 slots 个 float4，例如 values[i*slots:][:slots]）转成整套覆盖值：
// 每个槽位都算显式设置。超过 MAX_INSTANCE_FIELDS 的部分忽略。
instance_values_from :: proc(numbers: [][4]f32) -> (values: Instance_Values) {
	values.count = min(len(numbers), MAX_INSTANCE_FIELDS)
	copy(values.numbers[:values.count], numbers)
	values.set = (1 << u32(values.count)) - 1
	return
}

// 把显式设置的槽位写进 values（与 schema.fields 一一对应）：非有限数值忽略，其余按字段范围钳制。
@(private)
instance_values_apply :: proc(overrides: ^Instance_Values, schema: Schema, values: []Value) {
	if overrides == nil || overrides.set == 0 || len(values) != len(schema.fields) do return
	slot := 0
	for f, i in schema.fields {
		if !f.instance do continue
		if slot < MAX_INSTANCE_FIELDS && overrides.set & (1 << u32(slot)) != 0 {
			value_assign(f, &values[i], overrides.numbers[slot])
		}
		slot += 1
	}
}

// 数值字段的赋值规则：非有限数值整条忽略，其余按字段范围钳制（与 values_make 迁移时一致）。
@(private)
value_assign :: proc(f: Field, dst: ^Value, src: [4]f32) {
	if f.kind == .Texture do return
	for c in 0..<components(f.kind) {
		if math.is_nan(src[c]) || math.is_inf(src[c]) do return
	}
	for c in 0..<components(f.kind) {
		dst.number[c] = math.clamp(src[c], f.minimum, f.maximum)
	}
}
