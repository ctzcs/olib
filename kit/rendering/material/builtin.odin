package material

// 内置 2D 效果：直接借用 foster 设备的默认 Shader（Batcher、Msdf），foster 已按驱动选好字节码，
// 含 Web 的 GLSL，所以这两个效果在所有后端可用。它们沿用 foster 的 uniform 布局（Uniform_Layout.Foster）。
// 首次用名字创建材质（material_create）或 2D 渲染器初始化时自动登记，调用方不用手动 register。
// 分区：名字与参数组 / 登记。
import foster "../../../foster"

// ------------------------------------------------------------------------------
// 名字与参数组
// ------------------------------------------------------------------------------

// 默认精灵：贴图 × 顶点色；顶点 mode 字节选 Normal / Wash / Fill（与 foster Batcher 相同）。
BUILTIN_SPRITE :: "Sprite_Default"
// MSDF 文字：参数 distance_range 为字体图集的距离范围（像素）。
BUILTIN_TEXT :: "Text_Msdf"

builtin_is :: proc(name: string) -> bool {
	return name == BUILTIN_SPRITE || name == BUILTIN_TEXT
}

// ------------------------------------------------------------------------------
// 登记 —— 幂等；设备默认资源未初始化时返回原因。
// ------------------------------------------------------------------------------

@(private)
builtin_register :: proc(library: ^Material_Library, name: string) -> string {
	for effect in library.effects {
		if effect.desc.name == name do return ""
	}
	device := library.device
	if device == nil do return "Missing graphics device"
	if !device.Defaults.Initialized do return "Graphics device defaults are not initialized"
	text := name == BUILTIN_TEXT
	fields := make([]Field, text ? 2 : 1, context.temp_allocator)
	fields[0] = {id = "texture", name = "texture", label = "Texture", kind = .Texture}
	if text {
		fields[1] = {id = "distance_range", name = "distance_range", label = "Distance range",
			kind = .Scalar, minimum = 0, maximum = 64, step = 0.1, initial = {4, 0, 0, 0}}
	}
	schemas := []Schema{{name = name, preview = "2d", fields = fields}}
	passes := []Pass_Desc{{id = "main", params = Params_Ref(name), output = "color", draw = .Sprite,
		sprite_texture = "texture"}}
	desc := Effect_Desc{name = name, output = "color", passes = passes, preview = "2d", uniforms = .Foster}
	order, reason := effect_order(desc, schemas)
	delete(order)
	if reason != "" do return reason
	entry := new(Material_Effect)
	entry.desc = effect_clone(desc)
	entry.schemas = make([]Schema, 1)
	entry.schemas[0] = schema_clone(schemas[0])
	// Shader 归设备所有：vertex/fragment 留空，material_effect_gpu_clear 只释放 gpu 里的 Material。
	entry.gpu = make([]foster.Material, 1)
	if text {
		foster.MaterialInitWithShaders(&entry.gpu[0], &device.Defaults.MsdfVertexShader, &device.Defaults.MsdfFragmentShader)
	} else {
		foster.MaterialInitWithShaders(&entry.gpu[0], &device.Defaults.VertexShader, &device.Defaults.FragmentShader)
	}
	entry.ready = true
	append(&library.effects, entry)
	return ""
}
