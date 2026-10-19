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
	testing.expect(t, strings.contains(text, "nointerpolation float4 tint : TEXCOORD2;"))
	testing.expect(t, strings.contains(text, "nointerpolation float4 data0 : TEXCOORD3;"))
	testing.expect(t, strings.contains(text, "nointerpolation float4 data1 : TEXCOORD4;"))
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
	many_names := []string{"a", "b", "c", "d", "e"}
	for &f, i in many {
		f = {id = many_names[i], name = many_names[i], kind = .Scalar, maximum = 1, instance = true}
	}
	many_schemas := []Schema{{name = "Body", preview = "2d", fields = many}}
	testing.expect(t, strings.contains(effect_validate(effect, many_schemas), "more than 4 Instance fields"))
	// clone 保留 instanced。
	copy := effect_clone(effect)
	defer effect_dispose(&copy)
	testing.expect(t, copy.instanced)
}

@(test)
property_block_overrides_without_touching_shared_values :: proc(t: ^testing.T) {
	schema := instance_schema()
	values := values_make(schema)
	defer values_dispose(values)
	block: Property_Block
	testing.expect(t, block_set(&block, "hue", {0.7, 0, 0, 0}))
	testing.expect(t, block_set(&block, "hue", {0.8, 0, 0, 0})) // 同一字段以最后一次为准
	testing.expect_value(t, block.count, 1)
	testing.expect(t, block_set(&block, "strength", {99, 0, 0, 0})) // 钳制到最大 5
	testing.expect(t, block_set(&block, "image", {1, 0, 0, 0})) // 贴图字段被忽略
	testing.expect(t, block_set(&block, "missing", {1, 0, 0, 0})) // 未知字段被忽略
	testing.expect(t, block_set(&block, "tint", {0.1, 0.2, 0.3, 0.4}))
	testing.expect(t, block_set_group(&block, "Other", "hue", {0.1, 0, 0, 0})) // 其它组不影响
	block_apply(&block, schema, values)
	testing.expect_value(t, values[0].number[0], 0.8)
	testing.expect_value(t, values[2].number[0], 5)
	testing.expect_value(t, values[3].number, [4]f32{0.1, 0.2, 0.3, 0.4})
	testing.expect_value(t, values[1].texture, "")
	// 非有限值整条忽略。
	nan := block
	block_clear(&nan)
	block_set(&nan, "hue", {max(f32) * 2, 0, 0, 0})
	block_apply(&nan, schema, values)
	testing.expect_value(t, values[0].number[0], 0.8)
	// 容量满后拒绝新字段，但仍可改已有字段。
	full: Property_Block
	for i in 0..<MAX_BLOCK_ENTRIES {
		full.entries[i] = {"", i == 0 ? "a" : "x", {}}
		full.count += 1
	}
	testing.expect(t, !block_set(&full, "new", {}))
	testing.expect(t, block_set(&full, "a", {1, 0, 0, 0}))
}

@(test)
draw_collects_instance_values_in_field_order :: proc(t: ^testing.T) {
	// 与 material_pass_submit 相同的收集规则：材质值 < Property_Block < Pass 固定覆盖。
	schema := instance_schema()
	values := values_make(schema)
	defer values_dispose(values)
	block: Property_Block
	block_set(&block, "hue", {0.6, 0, 0, 0})
	block_apply(&block, schema, values)
	pass_values := []Pass_Value{{field = "hue", number = {0.9, 0, 0, 0}}}
	for override in pass_values {
		values[field_index(schema, string(override.field))].number = override.number
	}
	instance: Instance_Values
	for f, i in schema.fields {
		if !f.instance do continue
		instance.numbers[instance.count] = values[i].number
		instance.count += 1
	}
	testing.expect_value(t, instance.count, 2)
	testing.expect_value(t, instance.numbers[0][0], 0.9)
	testing.expect_value(t, instance.numbers[1], [4]f32{1, 1, 1, 1})
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
		testing.expect(t, strings.contains(text, fmt.tprintf("float4 world%d : TEXCOORD%d;", column, INSTANCE_MODEL_SEMANTIC_BASE+column)))
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
	testing.expect(t, !strings.contains(sprite, "OlibInstanceInput") && !strings.contains(sprite, "olib_world"))
}
