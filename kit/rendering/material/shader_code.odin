package material

// 预编译 Shader 字节码：按图形驱动选择格式，并用 ShaderLab 生成的清单一次登记整个效果。
// 分区：驱动与字节码选择 / 清单登记。
import "core:encoding/json"

import foster "../../../foster"

// ------------------------------------------------------------------------------
// 驱动与字节码选择
// ------------------------------------------------------------------------------

// 同一份着色器由 tools/shaders 编译出的三种后端格式；通常三个字段都来自 #load。
// Metal 驱动需要 msl，没有时 shader_pick 返回空切片。
Shader_Binaries :: struct {
	spv, dxil, msl: []u8,
}

// 一个 Pass 的顶点与片元字节码，顺序与 Effect 声明里的 Schema（参数组）一致。
// instanced_vertex 是 instanced 精灵效果的缓冲变体顶点（tools/shaders 产出的 <组名>.instanced.vertex.*），其余效果留空。
Pass_Binaries :: struct {
	vertex, fragment: Shader_Binaries,
	instanced_vertex: Shader_Binaries,
}

// 驱动是否走预编译字节码（SPIR-V / DXIL / MSL）。Web（WebGL2）只有 foster 默认 Shader 的手写 GLSL，
// 原生的 Private 驱动需要平台私有格式，两者都不在此列；内置效果借用 foster 默认 Shader，不经过这里。
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

// ------------------------------------------------------------------------------
// 清单登记
// ------------------------------------------------------------------------------

// 清单版本即生成代码与宿主的绑定约定版本，约定变化时递增，旧产物登记时报错而不是画错。
// 2：精灵记录首项为两条轴；精灵缓冲变体顶点 b1 为变换栈；顶点 b0 在投影/矩阵后接 Clock。
MANIFEST_VERSION :: 2

// 清单由 tools/shaders 生成（schemas + effect），passes 与 schemas 一一对应。
// 内部完成选择后端、解析、material_register 与临时数据释放；库深复制效果，字节码借用至
// material_library_dispose。返回空串表示成功，诊断文本借用至本帧结束。
material_register_manifest :: proc(library: ^Material_Library, manifest: []u8,
	passes: []Pass_Binaries) -> string {
	if library.device == nil do return "Missing graphics device"
	driver := library.device.Driver
	if !shader_driver_supported(driver) do return "Unsupported shader backend"
	parsed: struct {version: int, schemas: []Schema, effect: Effect_Desc}
	defer {
		for &schema in parsed.schemas do schema_dispose(&schema)
		delete(parsed.schemas)
		effect_dispose(&parsed.effect)
	}
	if json.unmarshal(manifest, &parsed) != nil do return "Invalid compiled shader manifest"
	if parsed.version != MANIFEST_VERSION {
		return "Compiled shader manifest is outdated; re-run tools/shaders"
	}
	code := make([]Material_Shader_Code, len(passes), context.temp_allocator)
	for pass, i in passes {
		code[i] = {shader_pick(driver, pass.vertex), shader_pick(driver, pass.fragment), shader_pick(driver, pass.instanced_vertex)}
	}
	return material_register(library, parsed.effect, parsed.schemas, code)
}
