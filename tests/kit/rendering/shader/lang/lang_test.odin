#+test
package lang

import "core:strings"
import "core:testing"

SOURCE :: `Shader "Water" {
Label "Water demo"
Properties {
    [Id("velocity")] [Step(0.1)] _Speed ("Speed", Range(0, 5)) = 1
    _Tint ("Tint", Color) = (0.2, 0.5, 0.8, 1)
    _Source ("Source", 2D) = ""
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
	// instanced 效果另有缓冲变体（实例记录 + 角点）；两者都提供 OlibSpriteInput / olib_sprite。
	batch, buffer := doc.programs[0], doc.instanced_programs[0]
	testing.expect(t, strings.contains(batch, "float4 Mode : TEXCOORD3;"))
	testing.expect(t, strings.contains(batch, "StructuredBuffer<float4> OlibInstanceValues : register(t0, space0);"))
	testing.expect(t, strings.contains(batch, "s.instance.data1 = OlibInstanceValues[offset + 1];"))
	testing.expect(t, !strings.contains(batch, "OlibInstanceInput"))
	testing.expect(t, strings.contains(buffer, "struct OlibSpriteInput {\n    OlibInstanceInput Instance;"))
	testing.expect(t, strings.contains(buffer, "olib_sprite_vertex(i.Instance, i.Corner, s.position, s.uv);"))
	testing.expect(t, !strings.contains(buffer, "StructuredBuffer"))
	for program in ([2]string{batch, buffer}) {
		testing.expect(t, strings.contains(program, "OlibSprite olib_sprite(OlibSpriteInput i)"))
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
	testing.expect(t, strings.contains(tinted.programs[0], "OlibInstance"))
	// 没有实例字段：批量变体不声明 storage buffer，tint 直接取顶点色。
	testing.expect(t, !strings.contains(tinted.programs[0], "StructuredBuffer"))
	testing.expect(t, strings.contains(tinted.programs[0], "s.instance.tint = i.Color;"))
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
