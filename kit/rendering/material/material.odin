package material

// 对象材质实例：每次 load 创建独立数值实例，GPU Shader 与贴图在 Material_Library 中共享。
// 分区：类型 / 加载与替换 / 数值修改。
import "core:encoding/json"
import "core:fmt"
import "core:math"
import path "core:path/slashpath"
import "core:strings"

import foster "../../../foster"

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 返回的指针借用至 material_library_dispose；reload 保持地址不变，模型不需要重新接线。
// 不直接修改这些字段；数值使用 material_set_number，资源变更通过 material_reload。
Material :: struct {
	owner: ^Material_Library,
	effect: ^Material_Effect,
	instance: Instance,
	source: string,
	bindings: []Material_Binding,
	samplers: [][MAX_TEXTURES]foster.BoundSampler,
}

@(private)
material_instance_clear :: proc(material: ^Material) {
	instance_dispose(&material.instance)
	delete(material.source)
	delete(material.bindings)
	delete(material.samplers)
	material^ = {}
}

// ------------------------------------------------------------------------------
// 加载与替换 —— JSON、贴图都走同一 StorageContainer。
// ------------------------------------------------------------------------------

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

// 读取并解码材质文件：返回实例数值与它所属的 Effect，不创建 GPU 资源。
@(private)
material_read :: proc(library: ^Material_Library, source: string) -> (Instance, ^Material_Effect, string) {
	if library.storage == nil do return {}, nil, "Missing material storage"
	bytes := foster.ReadAllBytes(library.storage, source, context.temp_allocator)
	if len(bytes) == 0 || len(bytes) > MAX_RESOURCE_BYTES do return {}, nil, "Cannot read material or resource exceeds 1 MiB"
	header: struct {version: int, effect: string}
	if json.unmarshal(bytes, &header, allocator = context.temp_allocator) != nil || header.version != 2 {
		return {}, nil, "Invalid material resource"
	}
	for effect in library.effects {
		if effect.desc.name != header.effect do continue
		instance, reason := instance_decode(effect.desc, effect.schemas, bytes)
		return instance, effect, reason
	}
	return {}, nil, fmt.tprintf("Unknown material effect: %s", header.effect)
}

// 确保库内有 1x1 白色默认贴图，供没有指定图片的 Texture 字段使用。
@(private)
material_white_texture :: proc(library: ^Material_Library) -> string {
	if library.white.Resource != nil do return ""
	foster.TextureInit(&library.white, library.device, 1, 1, .Color, "material default")
	if library.white.Resource == nil do return "Cannot create default material texture"
	pixel := [4]u8{255, 255, 255, 255}
	foster.TextureSetData(&library.white, &pixel[0], 4)
	return ""
}

// 为一个参数组解析全部 Texture 字段，返回按字段顺序排列的采样器数量；缺省贴图用白图。
@(private)
material_group_samplers :: proc(library: ^Material_Library, source: string, group: Instance_Group,
	samplers: ^[MAX_TEXTURES]foster.BoundSampler) -> (count: int, reason: string) {
	for field, j in group.schema.fields {
		if field.kind != .Texture do continue
		texture := &library.white
		if group.values[j].texture != "" {
			resolved: string
			resolved, reason = material_path(source, group.values[j].texture)
			if reason != "" do return 0, reason
			texture, reason = material_texture(library, resolved)
			if reason != "" do return 0, reason
		}
		samplers[count] = {texture, foster.TextureSamplerMake(.Linear, .Clamp)}
		count += 1
	}
	return count, ""
}

@(private)
material_replace :: proc(library: ^Material_Library, material: ^Material, file: string) -> string {
	source, reason := material_path("", file == "" ? material.source : file)
	if reason != "" do return reason
	next := Material{owner = library}
	next.instance, next.effect, reason = material_read(library, source)
	defer material_instance_clear(&next)
	if reason != "" do return reason
	if reason = material_bind(library, &next, source); reason != "" do return reason
	material_instance_clear(material)
	material^, next = next, {}
	return ""
}

// 用默认参数值在代码里创建材质实例，不读材质文件；内置效果（BUILTIN_SPRITE / BUILTIN_TEXT）首次使用时自动登记。
// 数值用 material_set_number 修改；没有来源文件，material_reload 会返回错误。指针借用至 material_library_dispose。
material_create :: proc(library: ^Material_Library, effect_name: string) -> (^Material, string) {
	if library == nil do return nil, "Missing material library"
	if builtin_is(effect_name) {
		if reason := builtin_register(library, effect_name); reason != "" do return nil, reason
	}
	effect: ^Material_Effect
	for candidate in library.effects {
		if candidate.desc.name == effect_name do effect = candidate
	}
	if effect == nil do return nil, fmt.tprintf("Unknown material effect: %s", effect_name)
	next := Material{owner = library, effect = effect}
	reason: string
	next.instance, reason = instance_make(effect.desc, effect.schemas)
	if reason == "" do reason = material_bind(library, &next, "")
	if reason != "" {
		material_instance_clear(&next)
		return nil, reason
	}
	result := new(Material)
	result^ = next
	append(&library.instances, result)
	return result, ""
}

// 准备效果的 GPU 资源并按参数组建立绑定；贴图路径相对于 source（为空时相对于容器根）。
@(private)
material_bind :: proc(library: ^Material_Library, material: ^Material, source: string) -> string {
	if !material_effect_prepare(library, material.effect) do return "Cannot prepare material shaders"
	if reason := material_white_texture(library); reason != "" do return reason
	material.source = strings.clone(source)
	material.bindings = make([]Material_Binding, len(material.instance.groups))
	material.samplers = make([][MAX_TEXTURES]foster.BoundSampler, len(material.instance.groups))
	for group, i in material.instance.groups {
		count, reason := material_group_samplers(library, source, group, &material.samplers[i])
		if reason != "" do return reason
		for schema, j in material.effect.schemas {
			if schema.name != group.schema.name do continue
			material.bindings[i] = {group.schema, group.values, &material.effect.gpu[j], material.samplers[i][:count]}
		}
	}
	return ""
}

// ------------------------------------------------------------------------------
// 数值修改
// ------------------------------------------------------------------------------

// 常用业务数值修改；按稳定组名/字段 ID 定位，失败不改变任何值。
material_set_number :: proc(material: ^Material, group, field: string, value: [4]f32) -> bool {
	if material == nil do return false
	for &parameters in material.instance.groups {
		if parameters.schema.name != group do continue
		i := field_index(parameters.schema, field)
		if i < 0 || parameters.schema.fields[i].kind == .Texture do return false
		f := parameters.schema.fields[i]
		for x in value {
			if math.is_nan(x) || math.is_inf(x) do return false
		}
		for c in 0..<components(f.kind) {
			if value[c] < f.minimum || value[c] > f.maximum do return false
		}
		parameters.values[i].number = value
		return true
	}
	return false
}
