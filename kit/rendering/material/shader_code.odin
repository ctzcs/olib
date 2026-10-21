package material

// 预编译 Shader 字节码：按图形驱动选择格式，并用 tools/shaders 生成的清单登记 Shader；
// 可以用 #load_directory 一次登记整个产物目录。
// 分区：驱动与字节码选择 / 清单登记。
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

import foster "../../../foster"
import sh "../shader"

// ------------------------------------------------------------------------------
// 驱动与字节码选择
// ------------------------------------------------------------------------------

// 同一份着色器由 tools/shaders 编译出的三种后端格式；通常三个字段都来自 #load。
// Metal 驱动需要 msl，没有时 shader_pick 返回空切片。
Shader_Binaries :: struct {
	spv, dxil, msl: []u8,
}

// 一个 Pass 的顶点与片元字节码，顺序与 Shader 声明里的 Schema（参数组）一致。
// instanced_vertex 是 instanced 精灵 Shader 的缓冲变体顶点（tools/shaders 产出的 <组名>.instanced.vertex.*），其余 Shader 留空。
Pass_Binaries :: struct {
	vertex, fragment: Shader_Binaries,
	instanced_vertex: Shader_Binaries,
}

// 驱动是否走预编译字节码（SPIR-V / DXIL / MSL）。Web（WebGL2）只有 foster 默认 Shader 的手写 GLSL，
// 原生的 Private 驱动需要平台私有格式，两者都不在此列；内置 Shader 借用 foster 默认 Shader，不经过这里。
shader_driver_supported :: proc(driver: foster.GraphicsDriver) -> bool {
	when ODIN_OS == .JS {
		return false
	} else {
		#partial switch driver {
		case .Vulkan, .D3D12, .Metal:
			return true
		case:
			return false
		}
	}
}

// 按驱动取代码；借用调用方的切片，不复制。未知驱动和缺失格式都返回空切片。
shader_pick :: proc(driver: foster.GraphicsDriver, binaries: Shader_Binaries) -> []u8 {
	#partial switch driver {
	case .D3D12:
		return binaries.dxil
	case .Metal:
		return binaries.msl
	case .Vulkan:
		return binaries.spv
	case:
		return nil
	}
}

// 产物文件的格式扩展名，与 shader_pick 的选择一致；未知驱动返回空串。
@(private)
shader_format :: proc(driver: foster.GraphicsDriver) -> string {
	#partial switch driver {
	case .D3D12:
		return "dxil"
	case .Metal:
		return "msl"
	case .Vulkan:
		return "spv"
	case:
		return ""
	}
}

// ------------------------------------------------------------------------------
// 清单登记
// ------------------------------------------------------------------------------

// 清单版本即生成代码与宿主的绑定约定版本，约定变化时递增，旧产物登记时报错而不是画错。
// 2：精灵记录首项为两条轴；精灵缓冲变体顶点 b1 为变换栈；顶点 b0 在投影/矩阵后接 Clock。
MANIFEST_VERSION :: 2

// 登记 tools/shaders 产物目录里的全部材质 Shader。files 直接传 #load_directory("<目录>/Compiled")，
// 它必须作参数或变量初始化（写成 :: 常量编译不过）。每个 *.shader.json 按参数组名找当前后端的
// <组名>.vertex / .fragment，instanced 精灵再找 <组名>.instanced.vertex；其他文件忽略。
// 首个 Pass 不是 Model / Sprite 的 Shader 只供 Shader Lab 预览，跳过。遇到第一个错误即返回，
// 诊断以文件名开头，之前已登记的 Shader 保留；一个清单都没有时报错（多半是目录写错）。
// 字节码借用嵌入数据，不复制。返回空串表示成功，诊断文本借用至本帧结束。
material_register_directory :: proc(library: ^Material_Library, files: []runtime.Load_Directory_File) -> string {
	if reason := shader_backend_check(library); reason != "" do return reason
	format := shader_format(library.device.Driver)
	manifests := 0
	for file in files {
		if !strings.has_suffix(file.name, ".shader.json") do continue
		manifests += 1
		parsed: Compiled_Manifest
		defer compiled_manifest_dispose(&parsed)
		if reason := compiled_manifest_parse(file.data, &parsed); reason != "" {
			return fmt.tprintf("%s: %s", file.name, reason)
		}
		if !sh.shader_is_material(parsed.shader) do continue
		instanced := parsed.shader.instanced && sh.shader_is_sprite(parsed.shader)
		code := make([]Material_Program_Code, len(parsed.schemas), context.temp_allocator)
		for schema, i in parsed.schemas {
			vertex, fragment, instanced_vertex: []u8
			missing: string
			vertex, missing = compiled_file(files, schema.name, "vertex", format)
			if missing == "" do fragment, missing = compiled_file(files, schema.name, "fragment", format)
			if missing == "" && instanced {
				instanced_vertex, missing = compiled_file(files, schema.name, "instanced.vertex", format)
			}
			if missing != "" do return fmt.tprintf("%s: missing compiled shader; re-run tools/shaders", missing)
			code[i] = {vertex, fragment, instanced_vertex}
		}
		if reason := material_register(library, parsed.shader, parsed.schemas, code); reason != "" {
			return fmt.tprintf("%s: %s", file.name, reason)
		}
	}
	if manifests == 0 do return "No compiled shader manifest (*.shader.json) in directory"
	return ""
}

// 清单由 tools/shaders 生成（schemas + shader），passes 与 schemas 一一对应。
// 内部完成选择后端、解析、material_register 与临时数据释放；库深复制 Shader，字节码借用至
// material_library_dispose。返回空串表示成功，诊断文本借用至本帧结束。
// 字节码就在 tools/shaders 的产物目录里时，用 material_register_directory 一次登记整个目录；
// 这里用于字节码来自别处（自定义打包等）的情况。
material_register_manifest :: proc(library: ^Material_Library, manifest: []u8,
	passes: []Pass_Binaries) -> string {
	if reason := shader_backend_check(library); reason != "" do return reason
	parsed: Compiled_Manifest
	defer compiled_manifest_dispose(&parsed)
	if reason := compiled_manifest_parse(manifest, &parsed); reason != "" do return reason
	driver := library.device.Driver
	code := make([]Material_Program_Code, len(passes), context.temp_allocator)
	for pass, i in passes {
		code[i] = {shader_pick(driver, pass.vertex), shader_pick(driver, pass.fragment), shader_pick(driver, pass.instanced_vertex)}
	}
	return material_register(library, parsed.shader, parsed.schemas, code)
}

// tools/shaders 写出的清单：各参数组的 Schema 与 Shader。
@(private)
Compiled_Manifest :: struct {
	version: int,
	schemas: []sh.Schema,
	shader: sh.Shader_Desc `json:"effect"`, // 清单里的键仍是 "effect"
}

// 两种登记共用：设备与后端在解析清单之前检查。
@(private)
shader_backend_check :: proc(library: ^Material_Library) -> string {
	if library.device == nil do return "Missing graphics device"
	if !shader_driver_supported(library.device.Driver) do return "Unsupported shader backend"
	return ""
}

// 解析并检查版本；无论成败都用 compiled_manifest_dispose 释放。两种登记共用这里的诊断文本。
@(private)
compiled_manifest_parse :: proc(data: []u8, parsed: ^Compiled_Manifest) -> string {
	if json.unmarshal(data, parsed) != nil do return "Invalid compiled shader manifest"
	if parsed.version != MANIFEST_VERSION do return "Compiled shader manifest is outdated; re-run tools/shaders"
	return ""
}

@(private)
compiled_manifest_dispose :: proc(parsed: ^Compiled_Manifest) {
	for &schema in parsed.schemas do sh.schema_dispose(&schema)
	delete(parsed.schemas)
	sh.shader_dispose(&parsed.shader)
}

// 在嵌入的目录里找 <组名>.<阶段>.<格式>；找不到时返回期望的文件名，供诊断使用。
@(private)
compiled_file :: proc(files: []runtime.Load_Directory_File, group, stage, format: string) -> (data: []u8, missing: string) {
	name := fmt.tprintf("%s.%s.%s", group, stage, format)
	for file in files {
		if file.name == name do return file.data, ""
	}
	return nil, name
}
