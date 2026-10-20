#+test
package material

import "core:mem"
import "core:testing"


@(test)
reflect_controls_and_validate_defaults :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)
	Good :: struct {
		speed: f32 `ui:"slider" id:"flow" min:"-2" max:"4" step:"0.1"`,
		offset: [2]f32 `ui:"vector" min:"-1" max:"1"`,
		tint: [4]f32 `ui:"color" label:"染色"`,
		image: string `ui:"texture"`,
	}
	schema, error := describe("Good", "test.hlsl", "3d", Good{speed = 2, image = "noise.png"})
	testing.expect(t, error == "" && len(schema.fields) == 4)
	testing.expect(t, schema.fields[0].id == "flow" && schema.fields[0].initial[0] == 2)
	testing.expect(t, schema.fields[1].kind == .Vector2 && schema.fields[3].texture == "noise.png")
	_, range_error := describe("Bad", "test.hlsl", "2d", Good{speed = 10})
	testing.expect(t, range_error != "")
	Duplicate :: struct {
		a: f32 `ui:"slider" id:"same"`,
		b: f32 `ui:"slider" id:"same"`,
	}
	_, duplicate_error := describe("Bad", "test.hlsl", "2d", Duplicate{})
	testing.expect(t, duplicate_error != "")
	Unsupported :: struct {
		value: int `ui:"slider"`,
	}
	_, unsupported_error := describe("Bad", "test.hlsl", "2d", Unsupported{})
	testing.expect(t, unsupported_error != "")
	Texture :: struct { image: Texture_Path }
	typed, typed_error := describe("Typed", "typed.hlsl", "3d", Texture{image = "noise.png"})
	testing.expect(t, typed_error == "" && typed.fields[0].kind == .Texture && typed.fields[0].texture == "noise.png")
	Wrong_Control :: struct { image: Texture_Path `ui:"slider"` }
	_, control_error := describe("Bad", "typed.hlsl", "2d", Wrong_Control{})
	testing.expect(t, control_error != "")
	// 贴图字段的采样标签：缺省线性、钳制；只用于贴图，值必须是已知名字。
	Sampled :: struct { tiles: Texture_Path `filter:"nearest" wrap:"repeat"`, plain: Texture_Path }
	sampled, sampled_error := describe("Sampled", "typed.hlsl", "3d", Sampled{})
	testing.expect(t, sampled_error == "" && sampled.fields[0].filter == .Nearest && sampled.fields[0].wrap == .Repeat)
	testing.expect(t, sampled.fields[1].filter == .Linear && sampled.fields[1].wrap == .Clamp)
	Bad_Wrap :: struct { tiles: Texture_Path `wrap:"tile"` }
	_, wrap_error := describe("Bad", "typed.hlsl", "3d", Bad_Wrap{})
	testing.expect(t, wrap_error != "")
	Not_Texture :: struct { speed: f32 `ui:"slider" filter:"nearest"` }
	_, filter_error := describe("Bad", "typed.hlsl", "3d", Not_Texture{})
	testing.expect(t, filter_error != "")
}

@(test)
dedicated_controls_preserve_schema_and_validate_tags :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)
	Legacy :: struct {
		speed: f32 `ui:"slider" id:"flow" label:"Speed" min:"-2" max:"5" step:"0.1"`,
		offset: [2]f32 `ui:"vector" min:"-1" max:"1"`,
		direction: [3]f32 `ui:"vector" min:"-1" max:"1"`,
		tint: [4]f32 `ui:"color"`,
	}
	Typed :: struct {
		speed: Scalar `id:"flow" label:"Speed" min:"-2" max:"5" step:"0.1"`,
		offset: Vector2 `min:"-1" max:"1"`,
		direction: Vector3 `min:"-1" max:"1"`,
		tint: Color,
	}
	legacy, legacy_error := describe("Water", "water.hlsl", "2d",
		Legacy{speed = 2, offset = {-0.5, 0.25}, direction = {0.25, -1, 0.5}, tint = {1, 0.5, 0.25, 0.75}})
	defaults := Typed{speed = 2, offset = {-0.5, 0.25}, direction = {0.25, -1, 0.5}, tint = {1, 0.5, 0.25, 0.75}}
	typed, typed_error := describe("Water", "water.hlsl", "2d", defaults)
	testing.expect(t, legacy_error == "" && typed_error == "" && schema_equal(legacy, typed),
		"Dedicated types preserve field IDs, defaults, ranges and GPU layout")
	defaults.tint[3] = 2
	_, range_error := describe("Water", "water.hlsl", "2d", defaults)
	testing.expect(t, range_error != "", "Color alpha still obeys the declared range")
	Wrong_Control :: struct {
		speed: Scalar `ui:"color"`,
	}
	_, control_error := describe("Bad", "water.hlsl", "2d", Wrong_Control{})
	testing.expect(t, control_error != "", "Explicit conflicting controls are rejected")
}
