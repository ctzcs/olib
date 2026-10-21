#+test
package lang

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

SOURCE :: `Shader "Water" {
Label "Water demo"
Properties {
    [Id("velocity")] [Step(0.1)] _Speed ("Speed", Range(0, 5)) = 1
    _Tint ("Tint", Color) = (0.2, 0.5, 0.8, 1)
    [Filter(Nearest)] [Wrap(Repeat)] _Source ("Source", 2D) = ""
}
HLSLINCLUDE
float4 shared_color() { return _Tint; }
ENDHLSL
Pass "scene" {
    Output "scene"
    Target { Scale 0.5 Format Float16 }
    HLSLPROGRAM
// ENDHLSL in a comment is ordinary HLSL.
/*
ENDHLSL
*/
float4 fragment_main() : SV_Target0 { return shared_color(); }
ENDHLSL
}
Pass "compose" {
    Output "color"
    Input _Source "scene" Current
    Value "velocity" 2
    HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return _Source.Load(int3(0, 0, 0)); }
ENDHLSL
}
}`

@(test)
properties_passes_and_original_hlsl_locations :: proc(t: ^testing.T) {
	doc := parse(SOURCE, "water.oshader")
	defer dispose(&doc)
	if !testing.expectf(t, doc.error == "", "%s", doc.error) {
		return
	}
	testing.expect(t, len(doc.schemas) == 2 && len(doc.programs) == 2)
	testing.expect(t, doc.schemas[0].name == "Water_scene")
	testing.expect(t, doc.schemas[0].fields[0].id == "velocity")
	testing.expect(t, doc.schemas[0].fields[0].step == 0.1)
	// 贴图的采样方式随 Schema 发布；未声明的贴图保持线性、钳制。
	testing.expect(t, doc.schemas[0].fields[2].filter == .Nearest && doc.schemas[0].fields[2].wrap == .Repeat)
	testing.expect(t, doc.schemas[0].fields[1].filter == .Linear && doc.schemas[0].fields[1].wrap == .Clamp)
	testing.expect(t, doc.schemas[0].fields[2].filter_declared && doc.schemas[0].fields[2].wrap_declared)
	testing.expect(t, !doc.schemas[0].fields[1].filter_declared && !doc.schemas[0].fields[1].wrap_declared)
	testing.expect(t, doc.effect.output == "color")
	testing.expect(t, doc.effect.passes[0].target.scale == 0.5)
	testing.expect(t, doc.effect.passes[1].inputs[0].target == "scene")
	testing.expect(t, doc.effect.passes[1].values[0].field == "velocity")
	testing.expect(t, strings.contains(doc.programs[0], "#define _Speed"))
	testing.expectf(t, strings.contains(doc.programs[0], "#line 8 \"water.oshader\""), "%s", doc.programs[0])
	testing.expect(t, strings.contains(doc.programs[0], "/*\nENDHLSL\n*/"))
	testing.expect(t, strings.contains(doc.programs[1], "Texture2D _Source"))
}

@(test)
invalid_declarations_fail_without_partial_document :: proc(t: ^testing.T) {
	changes := [][2]string{
		{"Range(0, 5)", "Range(5, 0)"},
		{"Range(0, 5)", "Range(0, 0.5)"},
		{"Step(0.1)", "Step(0)"},
		{"_Tint (", "_Speed ("},
		{"_Tint (", "_SourceSampler ("},
		{"Input _Source \"scene\" Current", "Input _Source \"color\" Current"},
		{"Input _Source \"scene\" Current", "Input _Speed \"scene\" Current"},
		{"Value \"velocity\" 2", "Value \"velocity\" 9"},
		{"Scale 0.5", "Scale nan"},
		{"Scale 0.5", "Unknown 1"},
		{"Pass \"compose\"", "Pass \"scene\""},
		{"Pass \"compose\"", "Pass \"../bad\""},
		{"Label \"Water demo\"", "Label \"Water demo\" Label \"Other\""},
		{"[Wrap(Repeat)]", "[Wrap(Tile)]"},
		{"[Filter(Nearest)]", "[Filter(Point)]"},
		{"[Wrap(Repeat)]", "[Wrap(Repeat)] [Wrap(Clamp)]"},
		{"[Step(0.1)]", "[Step(0.1)] [Filter(Nearest)]"}, // 采样方式只用于 2D 属性
	}
	for change in changes {
		bad, _ := strings.replace_all(SOURCE, change[0], change[1])
		doc := parse(bad, "broken.oshader")
		testing.expectf(t, doc.error != "" && len(doc.schemas) == 0,
			"must reject %s: %s", change[1], doc.error)
		testing.expect(t, strings.has_prefix(doc.error, "broken.oshader:"))
		dispose(&doc)
		delete(bad)
	}
	source := SOURCE
	for length in 0..<len(source) {
		doc := parse(source[:length], "truncated.oshader")
		testing.expectf(t, doc.error != "", "truncated input accepted at %d", length)
		dispose(&doc)
	}
}

// ZTest 按枚举名解析，补全的四种比较与原有取值同样可用。
@(test)
model_depth_compare_names :: proc(t: ^testing.T) {
	for name in ([?]string{"Greater", "Greater_Equal", "Not_Equal", "Never"}) {
		text, _ := strings.replace_all(`Shader "Depth" {
Pass "silhouette" { Draw Model ZTest NAME ZWrite Off
HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return 1; }
ENDHLSL
}
}`, "NAME", name, context.temp_allocator)
		doc := parse(text, "depth.oshader")
		defer dispose(&doc)
		if testing.expectf(t, doc.error == "", "%s: %s", name, doc.error) {
			testing.expect_value(t, fmt.tprint(doc.effect.passes[0].state.depth), name)
		}
	}
}

@(test)
model_render_states_and_previous_frame_graph :: proc(t: ^testing.T) {
	model := `Shader "Outlined" {
Properties { _Color ("Color", Color) = (1, 1, 1, 1) }
Pass "body" { Draw Model Cull Back Blend Opaque ZTest Less ZWrite On
HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return _Color; }
ENDHLSL
}
Pass "outline" { Draw Model Cull Front ZTest Less_Equal ZWrite Off
HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return _Color; }
ENDHLSL
}
}`
	doc := parse(model, "model.oshader")
	defer dispose(&doc)
	if testing.expectf(t, doc.error == "", "%s", doc.error) {
		testing.expect(t, doc.schemas[0].preview == "3d")
		testing.expect(t, doc.effect.passes[1].state.cull == .Front)
		testing.expect(t, doc.effect.passes[1].state.depth_write == .Off)
	}
	feedback, _ := strings.replace_all(SOURCE, "\"scene\" Current", "\"color\" Previous")
	defer delete(feedback)
	history := parse(feedback, "feedback.oshader")
	defer dispose(&history)
	testing.expectf(t, history.error == "", "%s", history.error)
}

@(test)
instance_properties_and_instanced_directive :: proc(t: ^testing.T) {
	source := `Shader "Glow" {
Preview 2D
Properties {
    [Instance] _Hue ("Hue", Range(0, 1)) = 0.2
    _Image ("Image", 2D) = ""
    [Id("amount")] [Instance] _Amount ("Amount", Range(0, 2)) = 1
}
Pass "body" {
    Draw Sprite
    SpriteTexture _Image
    HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return float4(_Hue, _Amount, 0, 1); }
ENDHLSL
}
}`
	doc := parse(source, "glow.oshader")
	defer dispose(&doc)
	if !testing.expectf(t, doc.error == "", "%s", doc.error) do return
	testing.expect(t, doc.effect.instanced)
	testing.expect(t, doc.schemas[0].fields[0].instance && !doc.schemas[0].fields[1].instance)
	testing.expect(t, doc.schemas[0].fields[2].instance && doc.schemas[0].fields[2].id == "amount")
	testing.expect(t, strings.contains(doc.programs[0], "#define _Hue (olib_instance.data0.x)"))
	testing.expect(t, strings.contains(doc.programs[0], "#define _Amount (olib_instance.data1.x)"))
	// Sprite Pass：programs 是批量变体（BatcherVertex 输入，字段从顶点 storage buffer 按 mode 偏移读取），
	// instanced 效果另有缓冲变体（实例记录 + 角点）；两者都 include olib/sprite_vertex.hlsli 得到 OlibSpriteInput / olib_sprite。
	batch, buffer := doc.programs[0], doc.instanced_programs[0]
	testing.expect(t, strings.contains(batch, "#define OLIB_SPRITE_BATCH\n") && !strings.contains(batch, "OLIB_INSTANCE_SPRITE"))
	testing.expect(t, strings.contains(buffer, "#define OLIB_INSTANCE_SPRITE\n") && !strings.contains(buffer, "OLIB_SPRITE_BATCH"))
	for program in ([2]string{batch, buffer}) {
		testing.expect(t, strings.contains(program, "#define OLIB_INSTANCE_DATA(X) X(0, 11, 9) X(1, 12, 10)\n"))
		testing.expect(t, strings.contains(program, "#include \"olib/instance.hlsli\"\n#include \"olib/sprite_vertex.hlsli\"\n"))
	}

	// 只写 Instanced：效果启用顶点 tint，没有实例字段。
	flag_only := `Shader "Tinted" {
Instanced
Pass "body" {
    Draw Sprite
    HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return InstanceTint; }
ENDHLSL
}
}`
	tinted := parse(flag_only, "tinted.oshader")
	defer dispose(&tinted)
	testing.expectf(t, tinted.error == "" && tinted.effect.instanced, "%s", tinted.error)
	// 没有实例字段：槽位为空，批量变体仍 include 精灵接口（从 storage buffer 读两条轴，不读字段）。
	testing.expect(t, strings.contains(tinted.programs[0], "#define OLIB_INSTANCE_SLOTS 0\n#define OLIB_INSTANCE_DATA(X)\n"))
	testing.expect(t, strings.contains(tinted.instanced_programs[0], "#define OLIB_INSTANCE_SPRITE\n"))
	// 非 Sprite 的效果没有缓冲变体。
	water := parse(SOURCE, "water.oshader")
	defer dispose(&water)
	for program in water.instanced_programs do testing.expect_value(t, program, "")

	// Texture 不能是 Instance。
	bad := parse(`Shader "Bad" {
Properties { [Instance] _Image ("Image", 2D) = "" }
Pass "p" { HLSLPROGRAM
float4 fragment_main() : SV_Target0 { return 0; }
ENDHLSL }
}`, "bad.oshader")
	defer dispose(&bad)
	testing.expect(t, strings.contains(bad.error, "Texture cannot be Instance"))
}

// 生成代码 include 的两个文件提供作者用到的接口；批量变体读 storage buffer，缓冲变体在 GPU 上套用变换栈（b1）。
@(test)
generator_includes_provide_sprite_and_instance_interfaces :: proc(t: ^testing.T) {
	read :: proc(name: string) -> string {
		bytes, err := os.read_entire_file(fmt.tprintf("%s/olib/%s", INCLUDE_DIRECTORY, name), context.temp_allocator)
		return err == nil ? string(bytes) : ""
	}
	instance, sprite := read("instance.hlsli"), read("sprite_vertex.hlsli")
	for text in ([]string{
		"struct OlibInstance {", "OLIB_INSTANCE_DATA(OLIB_INSTANCE_VARYING)", "#define InstanceTint (olib_instance.tint)",
		"struct OlibInstanceInput {", "float4x4 olib_world(OlibInstanceInput i)", "void olib_sprite_vertex(OlibInstanceInput i,",
		"OlibInstance olib_instance_from(OlibInstanceInput i)",
	}) {
		testing.expectf(t, strings.contains(instance, text), "instance.hlsli: %s", text)
	}
	for text in ([]string{
		"#ifdef OLIB_INSTANCE_SPRITE", "OlibInstanceInput Instance;", "_olib_view_axes", "StructuredBuffer<float4> OlibInstanceValues",
		"#if OLIB_INSTANCE_SLOTS > 0", "OlibSprite olib_sprite(OlibSpriteInput i)",
	}) {
		testing.expectf(t, strings.contains(sprite, text), "sprite_vertex.hlsli: %s", text)
	}
}
