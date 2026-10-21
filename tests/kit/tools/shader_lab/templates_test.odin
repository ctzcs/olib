#+test
package shader_lab

// 新建着色器的模板必须能直接用：游戏同一解析器（含 D3D12 规则检查）通过，Shader 是可登记的材质。
import "core:testing"

import sh "olib:kit/rendering/shader"
import lang "olib:kit/rendering/shader/lang"

@(test)
templates_parse_as_materials :: proc(t: ^testing.T) {
	for template in Shader_Template {
		text, base, _ := template_source(template)
		doc := lang.parse(text, base)
		defer lang.dispose(&doc)
		if !testing.expectf(t, doc.error == "", "%v: %s", template, doc.error) do continue
		testing.expectf(t, sh.shader_is_material(doc.shader), "%v is not a material", template)
		testing.expect_value(t, sh.shader_is_sprite(doc.shader), template == .Sprite || template == .Post_Process)
		testing.expect_value(t, doc.shader.instanced, template == .Sprite || template == .Model_Instanced)
	}
}
