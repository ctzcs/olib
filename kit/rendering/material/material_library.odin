package material

// 材质库：登记效果，集中持有并复用 Shader/纹理；实例见 material.odin。
// 分区：类型与所有权 / 效果登记 / 贴图缓存。
import "core:fmt"
import "core:strings"

import foster "../../../foster"

// ------------------------------------------------------------------------------
// 类型与所有权
// ------------------------------------------------------------------------------

// 使用当前设备后端的预编译代码；借用字节至 material_library_dispose，通常来自 #load。
Material_Shader_Code :: struct {
	vertex, fragment: []u8,
}

Material_Library :: struct {
	device: ^foster.GraphicsDevice,
	storage: ^foster.StorageContainer,
	// 以下缓存由库维护；库地址、device/storage 须在存活期间保持稳定。
	effects: [dynamic]^Material_Effect,
	textures: [dynamic]^Material_Texture,
	instances: [dynamic]^Material,
	white: foster.Texture,
}

Material_Effect :: struct {
	desc: Effect_Desc,
	schemas: []Schema,
	code: []Material_Shader_Code,
	vertex, fragment: []foster.Shader,
	gpu: []foster.Material,
	ready: bool,
}
Material_Texture :: struct {
	path: string,
	texture: foster.Texture,
}

material_library_dispose :: proc(library: ^Material_Library) {
	for instance in library.instances {
		material_instance_clear(instance)
		free(instance)
	}
	for effect in library.effects {
		material_effect_gpu_clear(effect)
		for &schema in effect.schemas do schema_dispose(&schema)
		effect_dispose(&effect.desc)
		delete(effect.schemas)
		delete(effect.code)
		free(effect)
	}
	for texture in library.textures {
		foster.TextureDispose(&texture.texture)
		delete(texture.path)
		free(texture)
	}
	foster.TextureDispose(&library.white)
	delete(library.instances)
	delete(library.effects)
	delete(library.textures)
	library^ = {}
}

@(private)
material_effect_gpu_clear :: proc(effect: ^Material_Effect) {
	for &gpu in effect.gpu do foster.MaterialDispose(&gpu)
	for &shader in effect.vertex do foster.ShaderDispose(&shader)
	for &shader in effect.fragment do foster.ShaderDispose(&shader)
	delete(effect.gpu)
	delete(effect.vertex)
	delete(effect.fragment)
	effect.gpu, effect.vertex, effect.fragment = nil, nil, nil
	effect.ready = false
}

// ------------------------------------------------------------------------------
// 效果登记 —— 资源初始化调用一次；深复制描述，惰性创建 GPU 资源。
// ------------------------------------------------------------------------------

material_register :: proc(library: ^Material_Library, effect: Effect_Desc,
	schemas: []Schema, code: []Material_Shader_Code) -> string {
	if !effect_is_material(effect) do return "Expected Model or Sprite material effect"
	if len(schemas) != len(code) do return "Shader code count differs from schema count"
	for prior in library.effects {
		if prior.desc.name == effect.name do return "Effect already registered"
	}
	for schema, i in schemas {
		for prior in schemas[:i] {
			if prior.name == schema.name do return "Duplicate shader group"
		}
		if len(code[i].vertex) == 0 || len(code[i].fragment) == 0 do return "Missing compiled shader code"
		if texture_count(schema) > MAX_TEXTURES do return "Too many texture bindings"
	}
	order, reason := effect_order(effect, schemas)
	defer delete(order)
	if reason != "" do return reason
	entry := new(Material_Effect)
	entry.desc = effect_clone(effect)
	entry.schemas = make([]Schema, len(schemas))
	entry.code = make([]Material_Shader_Code, len(code))
	copy(entry.code, code)
	for schema, i in schemas do entry.schemas[i] = schema_clone(schema)
	append(&library.effects, entry)
	return ""
}

@(private)
material_effect_prepare :: proc(library: ^Material_Library, effect: ^Material_Effect) -> bool {
	if effect.ready do return true
	if library.device == nil do return false
	effect.vertex = make([]foster.Shader, len(effect.code))
	effect.fragment = make([]foster.Shader, len(effect.code))
	effect.gpu = make([]foster.Material, len(effect.code))
	for code, i in effect.code {
		foster.ShaderInit(&effect.vertex[i], library.device, {
			Stage = .Vertex, Code = code.vertex, UniformBufferCount = 1,
			EntryPoint = "vertex_main",
		}, effect.schemas[i].name)
		foster.ShaderInit(&effect.fragment[i], library.device, {
			Stage = .Fragment, Code = code.fragment, UniformBufferCount = 2,
			SamplerCount = texture_count(effect.schemas[i]), EntryPoint = "fragment_main",
		}, effect.schemas[i].name)
		if effect.vertex[i].Resource == nil || effect.fragment[i].Resource == nil {
			material_effect_gpu_clear(effect)
			return false
		}
		foster.MaterialInitWithShaders(&effect.gpu[i], &effect.vertex[i], &effect.fragment[i])
	}
	effect.ready = true
	return true
}

// ------------------------------------------------------------------------------
// 贴图缓存 —— 同路径只上传一次，由库统一释放。
// ------------------------------------------------------------------------------

@(private)
material_texture :: proc(library: ^Material_Library, source: string) -> (^foster.Texture, string) {
	for entry in library.textures {
		if entry.path == source do return &entry.texture, ""
	}
	bytes := foster.ReadAllBytes(library.storage, source, context.temp_allocator)
	image := foster.ImageFromEncoded(bytes)
	defer foster.ImageDispose(&image)
	if image.Width == 0 || image.Height == 0 do return nil, fmt.tprintf("Cannot read material texture: %s", source)
	foster.ImagePremultiply(&image)
	entry := new(Material_Texture)
	entry.texture = foster.TextureFromImage(library.device, &image, source)
	if entry.texture.Resource == nil {
		free(entry)
		return nil, fmt.tprintf("Cannot upload material texture: %s", source)
	}
	entry.path = strings.clone(source)
	append(&library.textures, entry)
	return &entry.texture, ""
}
