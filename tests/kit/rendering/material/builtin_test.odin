#+test
package material

import "core:testing"

import foster "olib:foster"

// 内置效果借用设备默认 Shader：没有 GPU 时用标记为已初始化的空设备检查登记逻辑。
@(test)
builtin_effects_register_once_with_foster_uniforms :: proc(t: ^testing.T) {
	library: Material_Library
	defer material_library_dispose(&library)
	testing.expect_value(t, builtin_register(&library, BUILTIN_SPRITE), "Missing graphics device")

	device: foster.GraphicsDevice
	library.device = &device
	testing.expect_value(t, builtin_register(&library, BUILTIN_SPRITE), "Graphics device defaults are not initialized")

	device.Defaults.Initialized = true
	device.Defaults.VertexShader.Stage = .Vertex
	device.Defaults.FragmentShader.Stage = .Fragment
	device.Defaults.MsdfVertexShader.Stage = .Vertex
	device.Defaults.MsdfFragmentShader.Stage = .Fragment
	testing.expect_value(t, builtin_register(&library, BUILTIN_SPRITE), "")
	testing.expect_value(t, builtin_register(&library, BUILTIN_SPRITE), "") // 幂等
	testing.expect_value(t, builtin_register(&library, BUILTIN_TEXT), "")
	testing.expect_value(t, len(library.effects), 2)

	sprite, text := library.effects[0], library.effects[1]
	testing.expect(t, sprite.ready && effect_is_sprite(sprite.desc))
	testing.expect_value(t, sprite.desc.uniforms, Uniform_Layout.Foster)
	testing.expect(t, sprite.gpu[0].Fragment.Shader == &device.Defaults.FragmentShader)
	testing.expect(t, sprite.vertex == nil && sprite.fragment == nil) // Shader 归设备所有，库不释放
	testing.expect(t, text.gpu[0].Fragment.Shader == &device.Defaults.MsdfFragmentShader)
	testing.expect_value(t, field_index(text.schemas[0], "distance_range"), 1)
	testing.expect_value(t, string(text.desc.passes[0].sprite_texture), "texture")
}

@(test)
material_create_reports_unknown_effects :: proc(t: ^testing.T) {
	material, reason := material_create(nil, BUILTIN_SPRITE)
	testing.expect(t, material == nil && reason == "Missing material library")
	library: Material_Library
	defer material_library_dispose(&library)
	material, reason = material_create(&library, "Nope")
	testing.expect(t, material == nil && reason == "Unknown material effect: Nope")
	material, reason = material_create(&library, BUILTIN_TEXT)
	testing.expect(t, material == nil && reason == "Missing graphics device")
	testing.expect_value(t, len(library.instances), 0)
}

// Web 构建登记效果时的限制（material_register 只在 ODIN_OS == .JS 时调用它）。
@(test)
web_check_rejects_unsupported_effects :: proc(t: ^testing.T) {
	schemas := []Schema{{fields = []Field{{kind = .Scalar, instance = true}}}}
	testing.expect_value(t, material_web_check({}, schemas), "Web does not support Instance storage buffers")
	testing.expect_value(t, material_web_check({instanced = true}, nil), "Web does not support instanced materials")
	testing.expect_value(t, material_web_check({}, nil), "Web requires Foster uniform layout; Olib Clock and parameter blocks are unsupported")
	testing.expect_value(t, material_web_check({uniforms = .Foster}, nil), "")
}
