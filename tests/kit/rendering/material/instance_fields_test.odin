#+test
package material

import "core:fmt"
import "core:strings"
import "core:testing"

@(private)
instance_schema :: proc() -> Schema {
	fields := make([]Field, 4, context.temp_allocator)
	fields[0] = {id = "hue", name = "hue", kind = .Scalar, maximum = 1, initial = {0.15, 0, 0, 0}, instance = true}
	fields[1] = {id = "image", name = "image", kind = .Texture}
	fields[2] = {id = "strength", name = "strength", kind = .Scalar, maximum = 5, initial = {2, 0, 0, 0}}
	fields[3] = {id = "tint", name = "tint", kind = .Color, maximum = 1, initial = {1, 1, 1, 1}, instance = true}
	return {name = "Body", preview = "2d", fields = fields}
}

@(test)
instance_fields_leave_uniform_layout_and_define_olib_instance :: proc(t: ^testing.T) {
	schema := instance_schema()
	// 只有 strength 占 uniform 槽；hue / tint 随顶点。
	testing.expect_value(t, uniform_size(schema), 16)
	testing.expect_value(t, instance_count(schema), 2)
	values := values_make(schema)
	defer values_dispose(values)
	bytes: [16]u8
	testing.expect(t, pack(schema, values, bytes[:]))
	packed: [4]f32
	copy(packed[:], ([^]f32)(raw_data(bytes[:]))[:4])
	testing.expect_value(t, packed[0], 2)

	text := hlsl(schema, .Sprite)
	defer delete(text)
	testing.expect(t, strings.contains(text, "_olib_param_0;") && !strings.contains(text, "_olib_param_1"))
	// 精灵：顶点输入 sprite0..3 + tint + 字段；传给片元的变量从 TEXCOORD8 起，且为 nointerpolation。
	testing.expect(t, strings.contains(text, "struct OlibInstanceInput {"))
	for column in 0..<4 {
		testing.expect(t, strings.contains(text, fmt.tprintf("float4 sprite%d : TEXCOORD%d;", column, INSTANCE_SEMANTIC_BASE+column)))
	}
	testing.expect(t, strings.contains(text, "float4 tint : TEXCOORD10;"))
	testing.expect(t, strings.contains(text, "nointerpolation float4 tint : TEXCOORD8;"))
	testing.expect(t, strings.contains(text, "nointerpolation float4 data1 : TEXCOORD10;"))
	testing.expect(t, strings.contains(text, "void olib_sprite_vertex(OlibInstanceInput i, float2 corner,"))
	testing.expect(t, !strings.contains(text, "olib_world"))
	testing.expect(t, strings.contains(text, "#define _hue (olib_instance.data0.x)"))
	testing.expect(t, strings.contains(text, "#define _tint (olib_instance.data1.xyzw)"))
	testing.expect(t, strings.contains(text, "#define _strength (_olib_param_0.x)"))
	testing.expect(t, strings.contains(text, "register(t0, space2)"))

	testing.expect(t, !strings.contains(text, "%!")) // 格式串里的花括号不能被 fmt 吃掉
	// 没有 instance 字段且效果不是 instanced：不生成 OlibInstance，保持原有输出。
	plain := Schema{name = "Plain", fields = {{id = "a", name = "a", kind = .Scalar, maximum = 1}}}
	plain_text := hlsl(plain)
	defer delete(plain_text)
	testing.expect(t, !strings.contains(plain_text, "OlibInstance"))
	// 仅 instanced（只用 tint）也生成 OlibInstance。
	tint_only := hlsl(plain, .Sprite)
	defer delete(tint_only)
	testing.expect(t, strings.contains(tint_only, "OlibInstance") && !strings.contains(tint_only, "data0"))
}

@(test)
instanced_effect_rules :: proc(t: ^testing.T) {
	schemas := make([]Schema, 1, context.temp_allocator)
	schemas[0] = instance_schema()
	schemas[0].fields = schemas[0].fields[:3] // 去掉第二个 instance 字段，保留一个
	pass := Pass_Desc{id = "body", params = "Body", draw = .Sprite, output = "color"}
	passes := []Pass_Desc{pass}
	effect := Effect_Desc{name = "E", output = "color", passes = passes}
	// 有 instance 字段但效果没声明 instanced。
	testing.expect(t, strings.contains(effect_validate(effect, schemas), "Instanced effect"))
	effect.instanced = true
	testing.expect_value(t, effect_validate(effect, schemas), "")
	// instanced 支持 Sprite 和 Model；图像（全屏）效果不支持。
	model_passes := []Pass_Desc{{id = "body", params = "Body", draw = .Model, output = "color"}}
	model_schemas := []Schema{instance_schema()}
	model_schemas[0].preview = "3d"
	model_effect := Effect_Desc{name = "E", output = "color", passes = model_passes, instanced = true}
	testing.expect_value(t, effect_validate(model_effect, model_schemas), "")
	testing.expect_value(t, effect_instancing(model_effect), Instancing.Model)
	testing.expect_value(t, effect_instancing(effect), Instancing.Sprite)
	testing.expect_value(t, effect_instancing(Effect_Desc{}), Instancing.None)
	graph := Effect_Desc{name = "E", output = "color", instanced = true,
		passes = []Pass_Desc{{id = "a", params = "Body", draw = .Fullscreen, output = "color"}}}
	testing.expect(t, strings.contains(effect_validate(graph, schemas), "Sprite or Model passes"))
	// Texture 不能是 instance；数量有上限。
	bad := make([]Field, 1, context.temp_allocator)
	bad[0] = {id = "image", name = "image", kind = .Texture, instance = true}
	bad_schemas := []Schema{{name = "Body", preview = "2d", fields = bad}}
	testing.expect(t, strings.contains(effect_validate(effect, bad_schemas), "Texture cannot be Instance"))
	many := make([]Field, MAX_INSTANCE_FIELDS+1, context.temp_allocator)
	for &f, i in many {
		name := fmt.tprintf("f%d", i)
		f = {id = name, name = name, kind = .Scalar, maximum = 1, instance = true}
	}
	many_schemas := []Schema{{name = "Body", preview = "2d", fields = many}}
	limit_text := fmt.tprintf("more than %d Instance fields", MAX_INSTANCE_FIELDS)
	testing.expect(t, strings.contains(effect_validate(effect, many_schemas), limit_text))
	// clone 保留 instanced。
	copy := effect_clone(effect)
	defer effect_dispose(&copy)
	testing.expect(t, copy.instanced)
}

@(private)
slot_material :: proc(effect: ^Material_Effect) -> Material {
	schemas := make([]Schema, 2, context.temp_allocator)
	schemas[0], schemas[1] = instance_schema(), instance_schema()
	schemas[1].name = "Other"
	effect.schemas = schemas
	return Material{effect = effect}
}

@(test)
instance_slot_resolves_once_and_rejects_bad_names :: proc(t: ^testing.T) {
	effect: Material_Effect
	material := slot_material(&effect)
	hue := instance_slot(&material, "hue")
	tint := instance_slot(&material, "tint")
	testing.expect(t, hue.valid && hue.index == 0 && tint.valid && tint.index == 1)
	testing.expect(t, !instance_slot(&material, "strength").valid) // 统一参数不是实例字段
	testing.expect(t, !instance_slot(&material, "image").valid)
	testing.expect(t, !instance_slot(&material, "nope").valid)
	testing.expect(t, !instance_slot(nil, "hue").valid)
	testing.expect(t, !instance_slot(&Material{}, "hue").valid)
	// 不同参数组里槽位不一致时无法用同一个句柄。
	effect.schemas[1].fields[0], effect.schemas[1].fields[3] = effect.schemas[1].fields[3], effect.schemas[1].fields[0]
	testing.expect(t, !instance_slot(&material, "hue").valid)
}

@(test)
instance_values_set_marks_slots_and_apply_overrides_only_those :: proc(t: ^testing.T) {
	schema := instance_schema()
	values := values_make(schema)
	defer values_dispose(values)
	overrides: Instance_Values
	testing.expect(t, instance_values_set(&overrides, {0, true}, {0.7, 0, 0, 0}))
	testing.expect_value(t, overrides.set, u32(0b1))
	testing.expect_value(t, overrides.count, 1)
	testing.expect(t, !instance_values_set(&overrides, {}, {1, 0, 0, 0})) // 句柄无效
	testing.expect(t, !instance_values_set(&overrides, {MAX_INSTANCE_FIELDS, true}, {1, 0, 0, 0})) // 越界
	testing.expect(t, !instance_values_set(nil, {0, true}, {1, 0, 0, 0}))
	instance_values_apply(&overrides, schema, values)
	testing.expect_value(t, values[0].number[0], 0.7) // hue 被覆盖
	testing.expect_value(t, values[3].number, [4]f32{1, 1, 1, 1}) // tint 没设置，沿用材质值
	// 超出范围的值钳制到字段范围；非有限值忽略。
	instance_values_set(&overrides, {0, true}, {5, 0, 0, 0})
	instance_values_apply(&overrides, schema, values)
	testing.expect_value(t, values[0].number[0], 1)
	instance_values_set(&overrides, {0, true}, {max(f32) * 2, 0, 0, 0})
	instance_values_apply(&overrides, schema, values)
	testing.expect_value(t, values[0].number[0], 1)
	// 没有显式设置任何槽位，或传 nil：什么都不改。
	untouched := values_make(schema)
	defer values_dispose(untouched)
	instance_values_apply(nil, schema, untouched)
	instance_values_apply(&Instance_Values{}, schema, untouched)
	testing.expect_value(t, untouched[0].number[0], 0.15)
}

@(test)
draw_collects_instance_values_in_field_order :: proc(t: ^testing.T) {
	// 与 material_pass_submit 相同的规则：材质值 < Instance_Values < Pass 固定覆盖。
	schema := instance_schema()
	values := values_make(schema)
	defer values_dispose(values)
	overrides: Instance_Values
	instance_values_set(&overrides, {0, true}, {0.6, 0, 0, 0})
	instance_values_set(&overrides, {1, true}, {0.1, 0.2, 0.3, 0.4})
	instance_values_apply(&overrides, schema, values)
	for fixed in ([]Pass_Value{{field = "hue", number = {0.9, 0, 0, 0}}}) {
		values[field_index(schema, string(fixed.field))].number = fixed.number
	}
	instance: Instance_Values
	for f, i in schema.fields {
		if !f.instance do continue
		instance.numbers[instance.count] = values[i].number
		instance.count += 1
	}
	testing.expect_value(t, instance.count, 2)
	testing.expect_value(t, instance.numbers[0][0], 0.9) // Pass 固定值最后生效
	testing.expect_value(t, instance.numbers[1], [4]f32{0.1, 0.2, 0.3, 0.4})
	testing.expect_value(t, values[2].number[0], 2) // 统一参数保持材质里的值，不受实例值影响
}

@(test)
model_instancing_hlsl_declares_input_world_and_varyings :: proc(t: ^testing.T) {
	schema := instance_schema()
	schema.preview = "3d"
	text := hlsl(schema, .Model)
	defer delete(text)
	testing.expect(t, !strings.contains(text, "%!"))
	testing.expect(t, strings.contains(text, "struct OlibInstanceInput {"))
	for column in 0..<4 {
		testing.expect(t, strings.contains(text, fmt.tprintf("float4 world%d : TEXCOORD%d;", column, INSTANCE_SEMANTIC_BASE+column)))
	}
	testing.expect(t, strings.contains(text, "float4 tint : TEXCOORD10;"))
	testing.expect(t, strings.contains(text, "float4 data0 : TEXCOORD11;") && strings.contains(text, "float4 data1 : TEXCOORD12;"))
	// 传给片元的变量从 TEXCOORD8 起，且为 nointerpolation。
	testing.expect(t, strings.contains(text, "nointerpolation float4 tint : TEXCOORD8;"))
	testing.expect(t, strings.contains(text, "nointerpolation float4 data1 : TEXCOORD10;"))
	testing.expect(t, strings.contains(text, "transpose(float4x4(i.world0, i.world1, i.world2, i.world3))"))
	testing.expect(t, strings.contains(text, "OlibInstance olib_instance_from(OlibInstanceInput i)"))
	testing.expect(t, strings.contains(text, "o.data1 = i.data1;"))
	testing.expect(t, strings.contains(text, "#define _hue (olib_instance.data0.x)"))
	// 精灵没有世界矩阵输入。
	sprite := hlsl(schema, .Sprite)
	defer delete(sprite)
	testing.expect(t, strings.contains(sprite, "OlibInstanceInput") && !strings.contains(sprite, "olib_world"))
	testing.expect(t, !strings.contains(text, "sprite0") || !strings.contains(sprite, "world0"))
}

@(test)
instance_slot_count_requires_consistent_groups :: proc(t: ^testing.T) {
	fields := []Field{{id = "hue", instance = true}, {id = "tint"}, {id = "glow", instance = true}}
	effect := Material_Effect{schemas = []Schema{{fields = fields}, {fields = fields}}}
	material := Material{effect = &effect}
	testing.expect_value(t, instance_slot_count(&material), 2)
	effect.schemas = []Schema{{fields = fields}, {fields = fields[:1]}}
	testing.expect_value(t, instance_slot_count(&material), -1) // 各组字段数不同，无法共用一个缓冲布局
	testing.expect_value(t, instance_slot_count(nil), 0)
	testing.expect_value(t, instance_slot_count(&Material{}), 0)
}
