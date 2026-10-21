package material

// 材质库：登记 Shader，集中持有并复用 Shader/纹理；实例见 material.odin。
// 分区：类型与所有权 / Shader 登记 / 贴图缓存。
import "core:fmt"
import "core:strings"

import foster "../../../foster"
import sh "../shader"

// ------------------------------------------------------------------------------
// 类型与所有权
// ------------------------------------------------------------------------------

// 使用当前设备后端的预编译代码；借用字节至 material_library_dispose，通常来自 #load。
Material_Program_Code :: struct {
	vertex, fragment: []u8,
	instanced_vertex: []u8, // instanced 精灵 Shader 的缓冲变体顶点，供常驻 Sprite_Buffer；其余 Shader 为空
}

Material_Library :: struct {
	device: ^foster.GraphicsDevice,
	storage: ^foster.StorageContainer,
	// 以下缓存由库维护；库地址、device/storage 须在存活期间保持稳定。
	shaders: [dynamic]^Material_Shader,
	textures: [dynamic]^Material_Texture,
	instances: [dynamic]^Material,
	white: foster.Texture,
}

Material_Shader :: struct {
	desc: sh.Shader_Desc,
	schemas: []sh.Schema,
	code: []Material_Program_Code,
	vertex, fragment: []foster.Shader,
	instanced_vertex: []foster.Shader, // 只有 instanced 精灵 Shader 有，与 gpu 同序
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
	for shader in library.shaders {
		material_shader_gpu_clear(shader)
		for &schema in shader.schemas do sh.schema_dispose(&schema)
		sh.shader_dispose(&shader.desc)
		delete(shader.schemas)
		delete(shader.code)
		free(shader)
	}
	for texture in library.textures {
		foster.TextureDispose(&texture.texture)
		delete(texture.path)
		free(texture)
	}
	foster.TextureDispose(&library.white)
	delete(library.instances)
	delete(library.shaders)
	delete(library.textures)
	library^ = {}
}

@(private)
material_shader_gpu_clear :: proc(shader: ^Material_Shader) {
	for &gpu in shader.gpu do foster.MaterialDispose(&gpu)
	for &program in shader.vertex do foster.ShaderDispose(&program)
	for &program in shader.fragment do foster.ShaderDispose(&program)
	for &program in shader.instanced_vertex do foster.ShaderDispose(&program)
	delete(shader.gpu)
	delete(shader.vertex)
	delete(shader.fragment)
	delete(shader.instanced_vertex)
	shader.gpu, shader.vertex, shader.fragment, shader.instanced_vertex = nil, nil, nil, nil
	shader.ready = false
}

// ------------------------------------------------------------------------------
// Shader 登记 —— 资源初始化调用一次；深复制描述，惰性创建 GPU 资源。
// ------------------------------------------------------------------------------

@(private)
material_register :: proc(library: ^Material_Library, shader: sh.Shader_Desc,
	schemas: []sh.Schema, code: []Material_Program_Code) -> string {
	when ODIN_OS == .JS {
		if reason := material_web_check(shader, schemas); reason != "" do return reason
	}
	if !sh.shader_is_material(shader) do return "Expected Model or Sprite material shader"
	if len(schemas) != len(code) do return "Shader code count differs from schema count"
	for prior in library.shaders {
		if prior.desc.name == shader.name do return "Shader already registered"
	}
	for schema, i in schemas {
		for prior in schemas[:i] {
			if prior.name == schema.name do return "Duplicate shader group"
		}
		if len(code[i].vertex) == 0 || len(code[i].fragment) == 0 do return "Missing compiled shader code"
		if shader.instanced && sh.shader_is_sprite(shader) && len(code[i].instanced_vertex) == 0 {
			return "Missing instanced sprite vertex code"
		}
		if sh.texture_count(schema) > sh.MAX_TEXTURES do return "Too many texture bindings"
	}
	order, reason := sh.shader_order(shader, schemas)
	defer delete(order)
	if reason != "" do return reason
	entry := new(Material_Shader)
	entry.desc = sh.shader_clone(shader)
	entry.schemas = make([]sh.Schema, len(schemas))
	entry.code = make([]Material_Program_Code, len(code))
	copy(entry.code, code)
	for schema, i in schemas do entry.schemas[i] = sh.schema_clone(schema)
	append(&library.shaders, entry)
	return ""
}

// Web 后端只支持 foster 的 uniform 布局（矩阵与一个片元 float），没有 storage buffer 与实例缓冲。
// 只在 Web 构建时调用；独立成函数以便在桌面上测试。
@(private)
material_web_check :: proc(shader: sh.Shader_Desc, schemas: []sh.Schema) -> string {
	for schema in schemas {
		if sh.instance_count(schema) > 0 do return "Web does not support Instance storage buffers"
	}
	if shader.instanced do return "Web does not support instanced materials"
	if shader.uniforms != .Foster do return "Web requires Foster uniform layout; Olib Clock and parameter blocks are unsupported"
	return ""
}

// 宿主为每阶段提交的 uniform 槽数（精灵缓冲变体另有自己的顶点 Shader，不在此列）。
// Olib：顶点 b0 帧块，精灵 b1 Pass 偏移；片元 b0 帧块、b1 参数。Model 另有顶点 b1 / 片元 b2 视图块。
// Foster 布局只有顶点 b0 与片元 b0 参数。Shader 可以少声明，不能多于这里的槽数。
@(private)
material_uniform_counts :: proc(desc: sh.Shader_Desc) -> (vertex, fragment: int) {
	if desc.uniforms == .Foster do return 1, 1
	if sh.shader_is_model(desc) do return 2, 3
	if sh.shader_is_sprite(desc) do return 2, 2
	return 1, 2
}

@(private)
material_shader_prepare :: proc(library: ^Material_Library, shader: ^Material_Shader) -> bool {
	if shader.ready do return true
	if library.device == nil do return false
	shader.vertex = make([]foster.Shader, len(shader.code))
	shader.fragment = make([]foster.Shader, len(shader.code))
	shader.gpu = make([]foster.Material, len(shader.code))
	sprite := sh.shader_is_sprite(shader.desc)
	if sprite && shader.desc.instanced do shader.instanced_vertex = make([]foster.Shader, len(shader.code))
	vertex_uniforms, fragment_uniforms := material_uniform_counts(shader.desc)
	for code, i in shader.code {
		// 精灵批量变体从顶点 storage buffer 读两条轴和 [Instance] 字段（见 hlsl 的 Sprite_Batch）。
		storage := sprite && shader.desc.uniforms == .Olib ? 1 : 0
		foster.ShaderInit(&shader.vertex[i], library.device, {
			Stage = .Vertex, Code = code.vertex, UniformBufferCount = vertex_uniforms, StorageBufferCount = storage,
			EntryPoint = "vertex_main",
		}, shader.schemas[i].name)
		if shader.instanced_vertex != nil {
			// 缓冲变体：b0 投影与 Clock，b1 变换栈（见 hlsl 的 Sprite）。
			foster.ShaderInit(&shader.instanced_vertex[i], library.device, {
				Stage = .Vertex, Code = code.instanced_vertex, UniformBufferCount = 2,
				EntryPoint = "vertex_main",
			}, shader.schemas[i].name)
			if shader.instanced_vertex[i].Resource == nil {
				material_shader_gpu_clear(shader)
				return false
			}
		}
		foster.ShaderInit(&shader.fragment[i], library.device, {
			Stage = .Fragment, Code = code.fragment, UniformBufferCount = fragment_uniforms,
			SamplerCount = sh.texture_count(shader.schemas[i]), EntryPoint = "fragment_main",
		}, shader.schemas[i].name)
		if shader.vertex[i].Resource == nil || shader.fragment[i].Resource == nil {
			material_shader_gpu_clear(shader)
			return false
		}
		foster.MaterialInitWithShaders(&shader.gpu[i], &shader.vertex[i], &shader.fragment[i])
	}
	shader.ready = true
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
