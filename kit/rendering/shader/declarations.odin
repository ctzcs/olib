package shader

// 效果声明里的稳定引用；不持有 GPU 资源。
import "core:strings"

// distinct 保留字符串字面量写法，但禁止不同用途的已命名值互相赋值。
Params_Ref :: distinct string
Target_Ref :: distinct string
Field_Ref :: distinct string
Pass_Id :: distinct string

// 复制 / 释放字符串类声明：普通 string 与上面的 distinct string 通用，免去逐处强制转换。
// 新增拥有字符串的声明字段时，须同步 shader_clone / shader_dispose（Schema 见 schema_clone / schema_dispose）。
clone_text :: proc(value: $T) -> T {
	return T(strings.clone(string(value)))
}

delete_text :: proc(value: $T) {
	delete(string(value))
}
