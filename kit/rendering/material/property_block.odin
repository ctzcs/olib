package material

// 单次绘制的数值覆盖（类似 Unity 的 MaterialPropertyBlock）：不创建材质实例，不修改共享材质。
// 它是调用方持有的普通值，没有隐藏缓存；字符串只借用，须在绘制调用期间保持有效（通常是字面量）。
import "core:math"

MAX_BLOCK_ENTRIES :: 16

Property_Entry :: struct {
	group, field: string, // group 为空表示所有参数组（效果的每个 Pass）
	value: [4]f32,
}

Property_Block :: struct {
	count: int,
	entries: [MAX_BLOCK_ENTRIES]Property_Entry,
}

// 覆盖所有包含该稳定字段 ID 的参数组；同一字段重复设置以最后一次为准。已满返回 false。
block_set :: proc(block: ^Property_Block, field: string, value: [4]f32) -> bool {
	return block_set_group(block, "", field, value)
}

// 只覆盖指定参数组（Schema.name，如 "Sprite_body"）里的字段。
block_set_group :: proc(block: ^Property_Block, group, field: string, value: [4]f32) -> bool {
	for &entry in block.entries[:block.count] {
		if entry.group == group && entry.field == field {
			entry.value = value
			return true
		}
	}
	if block.count >= MAX_BLOCK_ENTRIES do return false
	block.entries[block.count] = {group, field, value}
	block.count += 1
	return true
}

block_clear :: proc(block: ^Property_Block) {
	block.count = 0
}

// 把覆盖写进 values（与 schema.fields 一一对应）。未知字段、贴图字段和非有限数值被忽略，
// 其余按字段范围钳制，与 values_make 迁移时的规则一致。
block_apply :: proc(block: ^Property_Block, schema: Schema, values: []Value) {
	if len(values) != len(schema.fields) do return
	for entry in block.entries[:block.count] {
		if entry.group != "" && entry.group != schema.name do continue
		i := field_index(schema, entry.field)
		if i < 0 || schema.fields[i].kind == .Texture do continue
		f := schema.fields[i]
		finite := true
		for c in 0..<components(f.kind) {
			finite = finite && !math.is_nan(entry.value[c]) && !math.is_inf(entry.value[c])
		}
		if !finite do continue
		for c in 0..<components(f.kind) {
			values[i].number[c] = math.clamp(entry.value[c], f.minimum, f.maximum)
		}
	}
}
