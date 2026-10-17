package material

// Odin 声明中的参数类型、资源路径与稳定引用；不持有 GPU 资源。
// 数值类型自动选择控件；默认值仍可直接使用数字或数组字面量。
Scalar :: distinct f32
Vector2 :: distinct [2]f32
Vector3 :: distinct [3]f32
Color :: distinct [4]f32 // RGBA，默认范围 0..1。

// distinct 保留字符串字面量写法，但禁止不同用途的已命名值互相赋值。
Texture_Path :: distinct string
Shader_Path :: distinct string
Params_Ref :: distinct string
Target_Ref :: distinct string
Field_Ref :: distinct string
Pass_Id :: distinct string

Preview_Mode :: enum {
	Auto,
	Two_D,
	Three_D,
}
