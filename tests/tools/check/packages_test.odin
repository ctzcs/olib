#+test
package main

import "core:testing"

// 构建标记与注释不能掩盖真实包名；数字目录仍使用合法的 vet 标识符。
@(test)
vet_uses_declared_package_name :: proc(t: ^testing.T) {
	testing.expect_value(t, source_package_name(
		"// package wrong\n#+build !js\npackage rendering2d\n", "kit/rendering/2d/sprite.odin"),
		"rendering2d")
	testing.expect_value(t, source_package_name(
		"package /* shared */ material\n", "kit/rendering/material/material.odin"), "material")
	testing.expect_value(t, source_package_name("package main\n", "tools/shaders/main.odin"), "main")
	testing.expect_value(t, source_package_name("// package absent\n", "empty.odin"), "")
}
