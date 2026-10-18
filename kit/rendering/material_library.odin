package rendering

// 对象材质资源：一次登记效果，按文件创建独立实例，集中复用 Shader/纹理。
// 分区：类型与所有权 / 效果登记 / 资源加载与替换。
import "core:encoding/json"
import "core:fmt"
import "core:math"
import path "core:path/slashpath"
import "core:strings"

import foster "olib:foster"
import mat "olib:kit/material"

// ------------------------------------------------------------------------------
// 类型与所有权
// ------------------------------------------------------------------------------

// 使用当前设备后端的预编译代码；借用字节至 materials_dispose，通常来自 #load。
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
	desc: mat.Effect_Desc,
	schemas: []mat.Schema,
	code: []Material_Shader_Code,
	vertex, fragment: []foster.Shader,
	gpu: []foster.Material,
	ready: bool,
}
Material_Texture :: struct {
	path: string,
	texture: foster.Texture,
}

// 返回的指针借用至 materials_dispose；reload 保持地址不变，模型不需要重新接线。
// 不直接修改这些字段；数值使用 material_set_number，资源变更通过 material_reload。
Material :: struct {
	owner: ^Material_Library,
	effect: ^Material_Effect,
	instance: mat.Instance,
	source: string,
	bindings: []Material_Binding,
	samplers: [][16]foster.BoundSampler,
}

materials_dispose :: proc(library: ^Material_Library) {
	for instance in library.instances {
		material_instance_clear(instance)
		free(instance)
	}
	for effect in library.effects {
		material_effect_gpu_clear(effect)
		for &schema in effect.schemas do mat.schema_dispose(&schema)
		mat.effect_dispose(&effect.desc)
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
material_instance_clear :: proc(material: ^Material) {
	mat.instance_dispose(&material.instance)
	delete(material.source)
	delete(material.bindings)
	delete(material.samplers)
	material^ = {}
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

materials_register :: proc(library: ^Material_Library, effect: mat.Effect_Desc,
	schemas: []mat.Schema, code: []Material_Shader_Code) -> string {
	if !mat.effect_is_material(effect) do return "Expected Model or Sprite material effect"
	if len(schemas) != len(code) do return "Shader code count differs from schema count"
	for prior in library.effects {
		if prior.desc.name == effect.name do return "Effect already registered"
	}
	for schema, i in schemas {
		for prior in schemas[:i] {
			if prior.name == schema.name do return "Duplicate shader group"
		}
		if len(code[i].vertex) == 0 || len(code[i].fragment) == 0 do return "Missing compiled shader code"
		if mat.texture_count(schema) > 16 do return "Too many texture bindings"
	}
	order, reason := mat.effect_order(effect, schemas)
	defer delete(order)
	if reason != "" do return reason
	entry := new(Material_Effect)
	entry.desc = mat.effect_clone(effect)
	entry.schemas = make([]mat.Schema, len(schemas))
	entry.code = make([]Material_Shader_Code, len(code))
	copy(entry.code, code)
	for schema, i in schemas do entry.schemas[i] = mat.schema_clone(schema)
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
			SamplerCount = mat.texture_count(effect.schemas[i]), EntryPoint = "fragment_main",
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
// 资源加载与替换 —— JSON、贴图都走同一 StorageContainer。
// ------------------------------------------------------------------------------

// 逻辑路径相对于容器根；贴图相对于材质文件。统一斜杠、折叠 ./ 和 ../ 以复用纹理。
@(private)
material_path :: proc(file, relative: string) -> (string, string) {
	normalized, _ := strings.replace_all(relative, "\\", "/", context.temp_allocator)
	if normalized == "" || strings.has_prefix(normalized, "/") || strings.contains(normalized, ":") {
		return "", "Material paths must be relative to the storage root"
	}
	if file == "" do return path.clean(normalized, context.temp_allocator), ""
	directory := path.dir(file, context.temp_allocator)
	return path.join({directory, normalized}, context.temp_allocator), ""
}

@(private)
material_read :: proc(library: ^Material_Library, source: string) -> (mat.Instance, ^Material_Effect, string) {
	if library.storage == nil do return {}, nil, "Missing material storage"
	bytes := foster.ReadAllBytes(library.storage, source, context.temp_allocator)
	if len(bytes) == 0 || len(bytes) > 1024*1024 do return {}, nil, "Cannot read material or resource exceeds 1 MiB"
	header: struct {version: int, effect: string}
	if json.unmarshal(bytes, &header, allocator = context.temp_allocator) != nil || header.version != 2 {
		return {}, nil, "Invalid material resource"
	}
	for effect in library.effects {
		if effect.desc.name != header.effect do continue
		instance, reason := mat.instance_decode(effect.desc, effect.schemas, bytes)
		return instance, effect, reason
	}
	return {}, nil, fmt.tprintf("Unknown material effect: %s", header.effect)
}

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

// 每次 load 创建独立数值实例；底层资源在库中共享。失败返回 nil，诊断借用至本帧结束。
material_load :: proc(library: ^Material_Library, file: string) -> (^Material, string) {
	result := new(Material)
	reason := material_replace(library, result, file)
	if reason != "" {
		free(result)
		return nil, reason
	}
	append(&library.instances, result)
	return result, ""
}

// 主线程、提交绘制之外调用；整份候选成功后一次替换，所有对象材质槽指针保持有效。
// 同路径贴图复用缓存；此接口重载材质参数，不监听或重载 Shader/贴图内容。
material_reload :: proc(library: ^Material_Library, material: ^Material, file := "") -> string {
	if material == nil || material.owner != library do return "Material belongs to another library"
	return material_replace(library, material, file)
}

@(private)
material_replace :: proc(library: ^Material_Library, material: ^Material, file: string) -> string {
	source, reason := material_path("", file == "" ? material.source : file)
	if reason != "" do return reason
	next := Material{owner = library}
	next.instance, next.effect, reason = material_read(library, source)
	defer material_instance_clear(&next)
	if reason != "" do return reason
	if !material_effect_prepare(library, next.effect) do return "Cannot prepare material shaders"
	if library.white.Resource == nil {
		foster.TextureInit(&library.white, library.device, 1, 1, .Color, "material default")
		pixel := [4]u8{255, 255, 255, 255}
		if library.white.Resource == nil do return "Cannot create default material texture"
		foster.TextureSetData(&library.white, &pixel[0], 4)
	}
	next.source = strings.clone(source)
	next.bindings = make([]Material_Binding, len(next.instance.groups))
	next.samplers = make([][16]foster.BoundSampler, len(next.instance.groups))
	for group, i in next.instance.groups {
		slot := 0
		for field, j in group.schema.fields {
			if field.kind != .Texture do continue
			texture := &library.white
			if group.values[j].texture != "" {
				resolved, path_error := material_path(source, group.values[j].texture)
				if path_error != "" do return path_error
				texture, reason = material_texture(library, resolved)
				if reason != "" do return reason
			}
			next.samplers[i][slot] = {texture, foster.TextureSamplerMake(.Linear, .Clamp)}
			slot += 1
		}
		for schema, j in next.effect.schemas {
			if schema.name != group.schema.name do continue
			next.bindings[i] = {group.schema, group.values, &next.effect.gpu[j], next.samplers[i][:slot]}
		}
	}
	material_instance_clear(material)
	material^, next = next, {}
	return ""
}

// 常用业务数值修改；按稳定组名/字段 ID 定位，失败不改变任何值。
material_set_number :: proc(material: ^Material, group, field: string, value: [4]f32) -> bool {
	if material == nil do return false
	for &parameters in material.instance.groups {
		if parameters.schema.name != group do continue
		i := mat.field_index(parameters.schema, field)
		if i < 0 || parameters.schema.fields[i].kind == .Texture do return false
		f := parameters.schema.fields[i]
		for x in value {
			if math.is_nan(x) || math.is_inf(x) do return false
		}
		for c in 0..<mat.components(f.kind) {
			if value[c] < f.minimum || value[c] > f.maximum do return false
		}
		parameters.values[i].number = value
		return true
	}
	return false
}
