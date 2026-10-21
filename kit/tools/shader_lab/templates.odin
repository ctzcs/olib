package shader_lab

// 新建着色器：把能直接编译、满足 D3D12 规则的 .oshader 模板写到 source_root，热重载发现后自动选中。
// 模板在 templates/ 下，是普通 .oshader，单元测试按游戏同一解析器检查。
import "core:fmt"
import "core:os"
import "core:strings"

Shader_Template :: enum {
	Sprite,          // 2D 精灵材质
	Model,           // 3D 模型材质
	Model_Instanced, // 3D 实例化模型材质
}

// 模板文件名（文件里的 Shader 名是 "Template"）、新文件的默认名与显示名。
template_source :: proc(template: Shader_Template) -> (text, base, label: string) {
	switch template {
	case .Sprite: return #load("templates/Sprite.oshader", string), "NewSprite", "新精灵材质"
	case .Model: return #load("templates/Model.oshader", string), "NewModel", "新模型材质"
	case .Model_Instanced: return #load("templates/Model_Instanced.oshader", string), "NewInstancedModel", "新实例化模型材质"
	}
	return
}

// 写出模板，返回新文件路径（临时分配）。Shader 名取 base、base2、base3… 中第一个没被文件或已有效果占用的，不覆盖文件。
new_shader :: proc(s: ^Session, template: Shader_Template) -> (path, reason: string) {
	if !s.initialized do return "", "Shader Lab is not initialized"
	text, base, label := template_source(template)
	for n in 1..<100 {
		suffix := n == 1 ? "" : fmt.tprint(n)
		name := fmt.tprintf("%s%s", base, suffix)
		path = fmt.tprintf("%s/%s.oshader", s.source_root, name)
		if os.exists(path) || template_shader_named(s, name) do continue
		content, _ := strings.replace(text, `Shader "Template"`, fmt.tprintf(`Shader "%s"`, name), 1, context.temp_allocator)
		if suffix != "" {
			content, _ = strings.replace(content, fmt.tprintf(`Label "%s"`, label),
				fmt.tprintf(`Label "%s %s"`, label, suffix), 1, context.temp_allocator)
		}
		if os.write_entire_file(path, transmute([]u8)content) != nil do return "", fmt.tprintf("Cannot write %s", path)
		delete(s.pending_shader)
		s.pending_shader = strings.clone(name)
		return path, ""
	}
	return "", fmt.tprintf("No free name for %s", base)
}

// 新建的效果编译进 bank 后选中它；编译失败时继续等待，错误照常显示在面板上。
@(private)
templates_update :: proc(s: ^Session) {
	if s.pending_shader == "" do return
	for e, i in s.shaders {
		if e.desc.name != s.pending_shader do continue
		select_shader(s, i)
		delete(s.pending_shader)
		s.pending_shader = ""
		return
	}
}

@(private = "file")
template_shader_named :: proc(s: ^Session, name: string) -> bool {
	for e in s.shaders do if e.desc.name == name do return true
	return false
}
