package foster_framework

import SDL "vendor:sdl3"
import "core:fmt"
import "core:mem"
import "core:math"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Graphics / Enums & Structs — 图形类型与状态
//   Graphics / GraphicsDevice / Validation — 绘制诊断
//   Graphics / Interfaces / IDrawableTarget — 可绘制目标
//   Graphics / Target — 离屏目标与附件
//   Graphics / Material — 着色器阶段与材质
//   Graphics / Mesh — 网格与顶点、索引数据
//   Graphics / Structs / DrawCommand — 绘制命令
//   Graphics / GraphicsDevice / RenderPass — 渲染通道
//   Graphics / Defaults / Materials — 默认材质
//   Graphics / IGraphicResource — 资源操作
//   Graphics / Texture — 创建、上传、读回与复制
//   Graphics / Shader — 创建、重建与释放
//   Graphics / GraphicsBuffer — 图形缓冲
//   Graphics / Defaults / DefaultResources — 默认资源
//   Graphics / Structs / ComputeCommand — 计算调度
//   Graphics / Defaults / Vertices — 默认顶点与类型化助手
//   Graphics / UniformBuffer — Uniform 数据
//   Graphics / Structs / VertexFormat — 顶点布局
//   Graphics / Batcher — 二维批处理绘制
//   Graphics / Structs / Subtexture — 子纹理

// ==============================================================================
// Graphics / Enums & Structs — 图形类型与状态
// ==============================================================================

// ------------------------------------------------------------------------------
// Graphics / Enums / TextureFormat
// ------------------------------------------------------------------------------

TextureFormat :: enum {
	R8G8B8A8,
	R8,
	R8G8,
	Depth24Stencil8,
	Depth32Stencil8,
	Depth16,
	Depth24,
	Depth32,
	R16G16B16A16_FLOAT,
	R32G32B32A32_FLOAT,
	R11G11B10_UFLOAT,
	Color = R8G8B8A8,
}

texture_format_size :: proc(format: TextureFormat) -> int {
	switch format {
	case .R8G8B8A8:
		return 4
	case .R8:
		return 1
	case .R8G8:
		return 2
	case .R16G16B16A16_FLOAT:
		return 8
	case .R32G32B32A32_FLOAT:
		return 16
	case .R11G11B10_UFLOAT:
		return 4
	case .Depth24Stencil8:
		return 4
	case .Depth32Stencil8:
		return 5
	case .Depth16:
		return 2
	case .Depth24:
		return 3
	case .Depth32:
		return 4
	}
	panic("Invalid TextureFormat")
}

texture_format_is_color_format :: proc(format: TextureFormat) -> bool {
	switch format {
	case .R8G8B8A8, .R8, .R8G8, .R16G16B16A16_FLOAT, .R32G32B32A32_FLOAT, .R11G11B10_UFLOAT:
		return true
	case .Depth24Stencil8, .Depth32Stencil8, .Depth16, .Depth24, .Depth32:
		return false
	}
	panic("Invalid TextureFormat")
}

texture_format_to_sdl :: proc(format: TextureFormat) -> SDL.GPUTextureFormat {
	switch format {
	case .R8G8B8A8:
		return .R8G8B8A8_UNORM
	case .R8:
		return .R8_UNORM
	case .R8G8:
		return .R8G8_UNORM
	case .R16G16B16A16_FLOAT:
		return .R16G16B16A16_FLOAT
	case .R32G32B32A32_FLOAT:
		return .R32G32B32A32_FLOAT
	case .R11G11B10_UFLOAT:
		return .R11G11B10_UFLOAT
	case .Depth24Stencil8:
		return .D24_UNORM_S8_UINT
	case .Depth32Stencil8:
		return .D32_FLOAT_S8_UINT
	case .Depth16:
		return .D16_UNORM
	case .Depth24:
		return .D24_UNORM
	case .Depth32:
		return .D32_FLOAT
	}
	panic("Invalid TextureFormat")
}

// ------------------------------------------------------------------------------
// Graphics / Enums / SampleCount & IndexFormat
// ------------------------------------------------------------------------------

SampleCount :: enum {
	One,
	Two,
	Four,
	Eight,
}

sample_count_to_sdl :: proc(samples: SampleCount) -> SDL.GPUSampleCount {
	#partial switch samples {
	case .One:
		return ._1
	case .Two:
		return ._2
	case .Four:
		return ._4
	case .Eight:
		return ._8
	}
	return ._1
}

IndexFormat :: enum {
	Sixteen,
	ThirtyTwo,
}

index_format_size_in_bytes :: proc(format: IndexFormat) -> int {
	#partial switch format {
	case .Sixteen:
		return 2
	case .ThirtyTwo:
		return 4
	}
	return 0
}

index_format_to_sdl :: proc(format: IndexFormat) -> SDL.GPUIndexElementSize {
	#partial switch format {
	case .Sixteen:
		return ._16BIT
	case .ThirtyTwo:
		return ._32BIT
	}
	return ._16BIT
}

// ------------------------------------------------------------------------------
// Graphics / Enums / ShaderStage
// ------------------------------------------------------------------------------

ShaderStage :: enum {
	Vertex,
	Fragment,
	Compute,
}

shader_stage_to_sdl :: proc(stage: ShaderStage) -> SDL.GPUShaderStage {
	#partial switch stage {
	case .Vertex:
		return .VERTEX
	case .Fragment:
		return .FRAGMENT
	case .Compute:
		// The bundled SDL3 bindings currently expose graphics shader stages
		// only; compute dispatch remains a backend extension.
		return .VERTEX
	}
	return .VERTEX
}

// ------------------------------------------------------------------------------
// Graphics / Structs / ShaderCreateInfo
// ------------------------------------------------------------------------------

ShaderCreateInfo :: struct {
	Stage:                                    ShaderStage,
	Code:                                     []u8,
	SamplerCount:                             int,
	UniformBufferCount:                       int,
	StorageBufferCount:                       int,
	ReadOnlyStorageTextureCount:              int,
	ReadOnlyStorageBufferCount:               int,
	ReadWriteStorageTextureCount:             int,
	ReadWriteStorageBufferCount:              int,
	EntryPoint:                               string,
	ThreadCountX, ThreadCountY, ThreadCountZ: int,
}

default_shader_create_info :: proc(stage: ShaderStage, code: []u8) -> ShaderCreateInfo {
	return ShaderCreateInfo {
		Stage              = stage,
		Code               = code,
		SamplerCount       = 0,
		UniformBufferCount = 0,
		StorageBufferCount = 0,
		EntryPoint         = "main",
		ThreadCountX       = 1,
		ThreadCountY       = 1,
		ThreadCountZ       = 1,
	}
}

TextureFormatSize :: texture_format_size
TextureFormatIsColorFormat :: texture_format_is_color_format
TextureFormatToSDL :: texture_format_to_sdl
SampleCountToSDL :: sample_count_to_sdl
IndexFormatSizeInBytes :: index_format_size_in_bytes
IndexFormatToSDL :: index_format_to_sdl
ShaderStageToSDL :: shader_stage_to_sdl
DefaultShaderCreateInfo :: default_shader_create_info

// ------------------------------------------------------------------------------
// Graphics / Enums / BlendFactor, BlendOp & BlendMask
// ------------------------------------------------------------------------------

BlendFactor :: enum {
	Zero,
	One,
	SrcColor,
	OneMinusSrcColor,
	DstColor,
	OneMinusDstColor,
	SrcAlpha,
	OneMinusSrcAlpha,
	DstAlpha,
	OneMinusDstAlpha,
	ConstantColor,
	OneMinusConstantColor,
	SrcAlphaSaturate,
}

BlendOp :: enum {
	Add,
	Subtract,
	ReverseSubtract,
	Min,
	Max,
}

BlendMask :: enum u8 {
	None  = 0,
	Red   = 1,
	Green = 2,
	Blue  = 4,
	Alpha = 8,
	RGB   = 7,
	RGBA  = 15,
}

// ------------------------------------------------------------------------------
// Graphics / Structs / BlendMode
// ------------------------------------------------------------------------------

BlendMode :: struct {
	ColorOperation:   BlendOp,
	ColorSource:      BlendFactor,
	ColorDestination: BlendFactor,
	AlphaOperation:   BlendOp,
	AlphaSource:      BlendFactor,
	AlphaDestination: BlendFactor,
	Mask:             BlendMask,
	Color:            Color,
}

blend_mode_make :: proc(operation: BlendOp, source, destination: BlendFactor) -> BlendMode {
	return BlendMode {
		ColorOperation   = operation,
		ColorSource      = source,
		ColorDestination = destination,
		AlphaOperation   = operation,
		AlphaSource      = source,
		AlphaDestination = destination,
		Mask             = .RGBA,
		Color            = White,
	}
}

blend_mode_make_full :: proc(
	color_operation: BlendOp,
	color_source, color_destination: BlendFactor,
	alpha_operation: BlendOp,
	alpha_source, alpha_destination: BlendFactor,
	mask: BlendMask,
	color: Color,
) -> BlendMode {
	return BlendMode {
		ColorOperation   = color_operation,
		ColorSource      = color_source,
		ColorDestination = color_destination,
		AlphaOperation   = alpha_operation,
		AlphaSource      = alpha_source,
		AlphaDestination = alpha_destination,
		Mask             = mask,
		Color            = color,
	}
}

// Full replacement. This exact value disables hardware blending; it is also
// equal to BlendModeMake(.Add, .One, .Zero).
BlendModeDisabled :: BlendMode {
	ColorOperation   = .Add,
	ColorSource      = .One,
	ColorDestination = .Zero,
	AlphaOperation   = .Add,
	AlphaSource      = .One,
	AlphaDestination = .Zero,
	Mask             = .RGBA,
	Color            = White,
}

BlendModePremultiply :: BlendMode {
	ColorOperation   = .Add,
	ColorSource      = .One,
	ColorDestination = .OneMinusSrcAlpha,
	AlphaOperation   = .Add,
	AlphaSource      = .One,
	AlphaDestination = .OneMinusSrcAlpha,
	Mask             = .RGBA,
	Color            = White,
}
BlendModeNonPremultiplied :: BlendMode {
	ColorOperation   = .Add,
	ColorSource      = .SrcAlpha,
	ColorDestination = .OneMinusSrcAlpha,
	AlphaOperation   = .Add,
	AlphaSource      = .SrcAlpha,
	AlphaDestination = .OneMinusSrcAlpha,
	Mask             = .RGBA,
	Color            = White,
}
BlendModeAdd :: BlendMode {
	ColorOperation   = .Add,
	ColorSource      = .One,
	ColorDestination = .DstAlpha,
	AlphaOperation   = .Add,
	AlphaSource      = .One,
	AlphaDestination = .DstAlpha,
	Mask             = .RGBA,
	Color            = White,
}
BlendModeSubtract :: BlendMode {
	ColorOperation   = .ReverseSubtract,
	ColorSource      = .One,
	ColorDestination = .One,
	AlphaOperation   = .Add,
	AlphaSource      = .One,
	AlphaDestination = .One,
	Mask             = .RGBA,
	Color            = White,
}
BlendModeMultiply :: BlendMode {
	ColorOperation   = .Add,
	ColorSource      = .DstColor,
	ColorDestination = .OneMinusSrcAlpha,
	AlphaOperation   = .Add,
	AlphaSource      = .DstColor,
	AlphaDestination = .OneMinusSrcAlpha,
	Mask             = .RGBA,
	Color            = White,
}
BlendModeScreen :: BlendMode {
	ColorOperation   = .Add,
	ColorSource      = .One,
	ColorDestination = .OneMinusSrcColor,
	AlphaOperation   = .Add,
	AlphaSource      = .One,
	AlphaDestination = .OneMinusSrcColor,
	Mask             = .RGBA,
	Color            = White,
}

// ------------------------------------------------------------------------------
// Graphics / Enums / CullMode, DepthCompare & FillMode
// ------------------------------------------------------------------------------

CullMode :: enum {
	None,
	Front,
	Back,
}

DepthCompare :: enum {
	Always,
	Never,
	Less,
	Equal,
	LessOrEqual,
	Greater,
	NotEqual,
	GreatorOrEqual,
}

FillMode :: enum {
	Fill,
	Line,
}

// ------------------------------------------------------------------------------
// Graphics / Enums / StencilOp & Structs / StencilState
// ------------------------------------------------------------------------------

StencilOp :: enum {
	Invalid,
	Keep,
	Zero,
	Replace,
	IncrementAndClamp,
	DecrementAndClamp,
	Invert,
	IncrementAndWrap,
	DecrementAndWrap,
}

StencilState :: struct {
	FailOp:      StencilOp,
	PassOp:      StencilOp,
	DepthFailOp: StencilOp,
	CompareOp:   DepthCompare,
}

StencilStateMake :: proc(op: StencilOp, compare: DepthCompare) -> StencilState {
	return StencilState{FailOp = op, PassOp = op, DepthFailOp = op, CompareOp = compare}
}

// ------------------------------------------------------------------------------
// Graphics / Enums / TextureFlags & ClearMask
// ------------------------------------------------------------------------------

TextureFlag :: enum u8 {
	ComputeRead,
	ComputeWrite,
}

TextureFlags :: distinct bit_set[TextureFlag;u8]
TextureFlagsNone :: TextureFlags{}

ClearMask :: enum u8 {
	None    = 0,
	Color   = 1,
	Depth   = 2,
	Stencil = 4,
	All     = 7,
}

BlendModeMake :: proc {
	blend_mode_make,
	blend_mode_make_full,
}

// ==============================================================================
// Graphics / GraphicsDevice / Validation — 绘制诊断
// ==============================================================================

DrawFailure :: enum {
	InvalidCommand,
	MissingMaterial,
	InvalidVertexBuffer,
	InvalidStorageBuffer,
	MissingShader,
	MissingShaderResource,
	ForeignTarget,
	MissingTarget,
	MissingColorTarget,
	RenderPass,
}

report_draw_failure :: proc(
	device: ^GraphicsDevice,
	failure: DrawFailure,
	message: cstring,
	sdl_error: bool = false,
) {
	if device == nil || failure in device.ReportedDrawFailures {
		return
	}
	device.ReportedDrawFailures += {failure}
	when ODIN_OS == .JS {
		web_log(fmt.aprintf("OFoster: %s", message))
	} else {
		if sdl_error {
			SDL.LogError(i32(SDL.LogCategory.GPU), "OFoster: %s: %s", message, SDL.GetError())
		} else {
			SDL.LogError(i32(SDL.LogCategory.GPU), "OFoster: %s", message)
		}
	}
}

// ==============================================================================
// Graphics / Interfaces / IDrawableTarget — 可绘制目标
// ==============================================================================

DrawableTarget :: struct {
	GraphicsDevice: ^GraphicsDevice,
	Surface:        rawptr,
	WidthInPixels:  int,
	HeightInPixels: int,
	IsWindow:       bool,
}

drawable_target_from_window :: proc(window: ^Window) -> DrawableTarget {
	if window == nil {
		return DrawableTarget{}
	}
	return DrawableTarget {
		GraphicsDevice = window.GraphicsDevice,
		Surface        = window,
		WidthInPixels  = Width(window),
		HeightInPixels = Height(window),
		IsWindow       = true,
	}
}

drawable_target_from_target :: proc(target: ^Target) -> DrawableTarget {
	if target == nil {
		return DrawableTarget{}
	}
	return DrawableTarget {
		GraphicsDevice = target.GraphicsDevice,
		Surface        = target,
		WidthInPixels  = target.Width,
		HeightInPixels = target.Height,
		IsWindow       = false,
	}
}

drawable_target_size_in_pixels :: proc(target: DrawableTarget) -> Point2 {
	return Point2{target.WidthInPixels, target.HeightInPixels}
}

drawable_target_bounds_in_pixels :: proc(target: DrawableTarget) -> RectInt {
	return RectInt{0, 0, target.WidthInPixels, target.HeightInPixels}
}

DrawableTargetFromWindow :: drawable_target_from_window
DrawableTargetFromTarget :: drawable_target_from_target
DrawableTargetSizeInPixels :: drawable_target_size_in_pixels
DrawableTargetBoundsInPixels :: drawable_target_bounds_in_pixels

// ==============================================================================
// Graphics / Target — 离屏目标与附件
// ==============================================================================

TargetAttachmentSpec :: struct {
	Format:      TextureFormat,
	SampleCount: SampleCount,
}

default_target_attachment_specs :: [1]TargetAttachmentSpec{{Format = .Color, SampleCount = .One}}

Target :: struct {
	GraphicsDevice: ^GraphicsDevice,
	Name:           string,
	Width:          int,
	Height:         int,
	Bounds:         RectInt,
	Attachments:    [dynamic]Texture,
	Disposed:       bool,
}

target_init_with_attachments :: proc(
	target: ^Target,
	graphics_device: ^GraphicsDevice,
	width, height: int,
	attachments: []TargetAttachmentSpec,
	name: string = "",
) {
	if width <= 0 || height <= 0 {
		panic("Target width and height must be larger than 0")
	}
	if len(attachments) <= 0 {
		panic("Target needs at least 1 color attachment")
	}

	target.GraphicsDevice = graphics_device
	target.Name = name
	target.Width = width
	target.Height = height
	target.Bounds = RectInt{0, 0, width, height}
	target.Disposed = false
	target.Attachments = nil

	for attachment, index in attachments {
		usage: SDL.GPUTextureUsageFlags
		if texture_format_is_color_format(attachment.Format) {
			usage = SDL.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET}
		} else {
			usage = SDL.GPUTextureUsageFlags{.DEPTH_STENCIL_TARGET}
		}

		attachment_name := name
		if attachment_name != "" {
			attachment_name = fmt.aprintf("%s-Attachment%d", name, index)
		}

		tex: Texture
		texture_init_ex(
			&tex,
			graphics_device,
			width,
			height,
			attachment.Format,
			attachment.SampleCount,
			usage,
			true,
			attachment_name,
		)
		append(&target.Attachments, tex)
	}
}

target_init :: proc(
	target: ^Target,
	graphics_device: ^GraphicsDevice,
	width, height: int,
	name: string = "",
) {
	default_attachments := default_target_attachment_specs
	target_init_with_attachments(
		target,
		graphics_device,
		width,
		height,
		default_attachments[:],
		name,
	)
}

target_dispose :: proc(target: ^Target) {
	if target == nil || target.Disposed {
		return
	}

	when ODIN_OS == .JS {
		for i := 0; i < len(target.Attachments); i += 1 {
			if target.Attachments[i].GraphicsDevice != nil &&
			   target.Attachments[i].GraphicsDevice.Device != nil {
				if target.Attachments[i].Resource != nil {
					fw_gl_release_texture(web_handle_u32(rawptr(target.Attachments[i].Resource)))
				}
				if target.Attachments[i].ResolveResource != nil {
					fw_gl_release_texture(
						web_handle_u32(rawptr(target.Attachments[i].ResolveResource)),
					)
				}
			}
			target.Attachments[i].Disposed = true
		}
		delete(target.Attachments)
		target.Disposed = true
		return
	}

	for i := 0; i < len(target.Attachments); i += 1 {
		if target.Attachments[i].GraphicsDevice != nil &&
		   target.Attachments[i].GraphicsDevice.Device != nil &&
		   target.Attachments[i].Resource != nil {
			SDL.ReleaseGPUTexture(
				target.Attachments[i].GraphicsDevice.Device,
				target.Attachments[i].Resource,
			)
			target.Attachments[i].Resource = nil
		}
		if target.Attachments[i].GraphicsDevice != nil &&
		   target.Attachments[i].GraphicsDevice.Device != nil &&
		   target.Attachments[i].ResolveResource != nil {
			SDL.ReleaseGPUTexture(
				target.Attachments[i].GraphicsDevice.Device,
				target.Attachments[i].ResolveResource,
			)
			target.Attachments[i].ResolveResource = nil
		}
		target.Attachments[i].Disposed = true
	}
	delete(target.Attachments)
	target.Disposed = true
}

target_attachment :: proc(target: ^Target, index: int = 0) -> ^Texture {
	if target == nil || index < 0 || index >= len(target.Attachments) {
		return nil
	}
	return &target.Attachments[index]
}

TargetInit :: proc {
	target_init,
	target_init_with_attachments,
}
TargetDispose :: target_dispose
TargetAttachment :: target_attachment

// ------------------------------------------------------------------------------
// Graphics / Structs / BoundSampler — 纹理与采样器绑定
// ------------------------------------------------------------------------------

BoundSampler :: struct {
	Texture: ^Texture,
	Sampler: TextureSampler,
}

// ==============================================================================
// Graphics / Material — 着色器阶段与材质
// ==============================================================================

MaterialStage :: struct {
	Shader:               ^Shader,
	Samplers:             [16]BoundSampler,
	UniformBuffers:       [8][dynamic]u8,
	UniformBufferObjects: [8]UniformBuffer,
	Stage:                ShaderStage,
}

material_stage_init :: proc(stage: ^MaterialStage, shader_stage: ShaderStage) {
	stage.Stage = shader_stage
	stage.Shader = nil
	for i := 0; i < len(stage.UniformBuffers); i += 1 {
		stage.UniformBuffers[i] = nil
		uniform_buffer_init(&stage.UniformBufferObjects[i])
	}
}

material_stage_set_shader :: proc(stage: ^MaterialStage, shader: ^Shader) {
	if shader != nil && shader.Stage != stage.Stage {
		panic("Invalid Shader Stage")
	}
	stage.Shader = shader
}

material_stage_set_uniform_buffer :: proc(stage: ^MaterialStage, data: []u8, slot: int = 0) {
	if slot < 0 || slot >= len(stage.UniformBuffers) {
		panic("Uniform buffer slot out of range")
	}
	delete(stage.UniformBuffers[slot])
	stage.UniformBuffers[slot] = nil
	append(&stage.UniformBuffers[slot], ..data)
	uniform_buffer_clear(&stage.UniformBufferObjects[slot])
	uniform_buffer_set(&stage.UniformBufferObjects[slot], data)
}

material_stage_get_uniform_buffer :: proc(stage: ^MaterialStage, slot: int = 0) -> []u8 {
	if slot < 0 || slot >= len(stage.UniformBuffers) {
		return nil
	}
	return stage.UniformBuffers[slot][:]
}

material_stage_copy_to :: proc(stage: ^MaterialStage, to: ^MaterialStage) {
	if stage == to {
		return
	}
	to.Stage = stage.Stage
	to.Shader = stage.Shader
	to.Samplers = stage.Samplers
	for i := 0; i < len(stage.UniformBuffers); i += 1 {
		delete(to.UniformBuffers[i])
		to.UniformBuffers[i] = nil
		append(&to.UniformBuffers[i], ..stage.UniformBuffers[i][:])
		uniform_buffer_dispose(&to.UniformBufferObjects[i])
		uniform_buffer_init(&to.UniformBufferObjects[i])
		uniform_buffer_set(&to.UniformBufferObjects[i], stage.UniformBufferObjects[i].Data[:])
	}
}

MaterialStageInit :: material_stage_init
MaterialStageSetShader :: material_stage_set_shader
MaterialStageSetUniformBuffer :: material_stage_set_uniform_buffer
MaterialStageGetUniformBuffer :: material_stage_get_uniform_buffer

MaterialStageGetUniformBufferObject :: proc(
	stage: ^MaterialStage,
	slot: int = 0,
) -> ^UniformBuffer {
	if stage == nil || slot < 0 || slot >= len(stage.UniformBufferObjects) {
		return nil
	}
	return &stage.UniformBufferObjects[slot]
}
MaterialStageCopyTo :: material_stage_copy_to

MaterialStageMaxUniformBuffers :: proc(stage: ^MaterialStage) -> int {
	if stage == nil {
		return 0
	}
	return len(stage.UniformBuffers)
}

MaterialStageMaxSamplers :: proc(stage: ^MaterialStage) -> int {
	if stage == nil {
		return 0
	}
	return len(stage.Samplers)
}

MaterialStageSetSampler :: proc(
	stage: ^MaterialStage,
	index: int,
	texture: ^Texture,
	sampler: TextureSampler,
) {
	if stage == nil || index < 0 || index >= len(stage.Samplers) {
		return
	}
	stage.Samplers[index] = BoundSampler {
		Texture = texture,
		Sampler = sampler,
	}
}

MaterialStageGetSampler :: proc(stage: ^MaterialStage, index: int) -> BoundSampler {
	if stage == nil || index < 0 || index >= len(stage.Samplers) {
		return {}
	}
	return stage.Samplers[index]
}

Material :: struct {
	Vertex:   MaterialStage,
	Fragment: MaterialStage,
}

material_init_with_shaders :: proc(
	material: ^Material,
	vertex_shader: ^Shader,
	fragment_shader: ^Shader,
) {
	material_stage_init(&material.Vertex, .Vertex)
	material_stage_init(&material.Fragment, .Fragment)
	material_stage_set_shader(&material.Vertex, vertex_shader)
	material_stage_set_shader(&material.Fragment, fragment_shader)
}

material_init :: proc(material: ^Material) {
	material_init_with_shaders(material, nil, nil)
}

material_copy_to :: proc(material: ^Material, to: ^Material) {
	material_stage_copy_to(&material.Vertex, &to.Vertex)
	material_stage_copy_to(&material.Fragment, &to.Fragment)
}

material_copy_from :: proc(material: ^Material, from: ^Material) {
	material_copy_to(from, material)
}

material_clone :: proc(material: ^Material) -> Material {
	clone: Material
	material_init(&clone)
	material_copy_to(material, &clone)
	return clone
}

MaterialInit :: proc {
	material_init,
	material_init_with_shaders,
}
MaterialCopyTo :: material_copy_to
MaterialCopyFrom :: material_copy_from
MaterialClone :: material_clone

MaterialStageDispose :: proc(stage: ^MaterialStage) {
	if stage == nil {
		return
	}
	for i in 0 ..< len(stage.UniformBuffers) {
		delete(stage.UniformBuffers[i])
		UniformBufferDispose(&stage.UniformBufferObjects[i])
	}
	stage^ = {}
}

// Shaders and sampled textures are borrowed; only uniform data is owned.

MaterialDispose :: proc(material: ^Material) {
	if material == nil {
		return
	}
	MaterialStageDispose(&material.Vertex)
	MaterialStageDispose(&material.Fragment)
}

// ==============================================================================
// Graphics / Mesh — 网格与顶点、索引数据
// ==============================================================================

Mesh :: struct {
	GraphicsDevice:    ^GraphicsDevice,
	Name:              string,
	VertexData:        VertexBuffer,
	IndexData:         IndexBuffer,
	InstanceData:      VertexBuffer,
	HasInstanceBuffer: bool,
}

mesh_init_with_format :: proc(
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	vertex_format: VertexFormat,
	index_format: IndexFormat,
	name: string = "",
) {
	mesh.GraphicsDevice = graphics_device
	mesh.Name = name
	vertex_name := ""
	index_name := ""
	if name != "" {
		vertex_name = fmt.aprintf("%s-Vertices", name)
		index_name = fmt.aprintf("%s-Indices", name)
	}
	vertex_buffer_init_with_format(&mesh.VertexData, graphics_device, vertex_format, vertex_name)
	index_buffer_init(&mesh.IndexData, graphics_device, index_format, index_name)
	mesh.HasInstanceBuffer = false
}

mesh_init :: proc(
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	vertex_stride: int,
	index_format: IndexFormat,
	name: string = "",
) {
	mesh_init_with_format(
		mesh,
		graphics_device,
		vertex_format_make(nil, vertex_stride),
		index_format,
		name,
	)
}

mesh_init_instanced_with_format :: proc(
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	vertex_format, instance_format: VertexFormat,
	index_format: IndexFormat,
	name: string = "",
) {
	mesh_init_with_format(mesh, graphics_device, vertex_format, index_format, name)
	instance_name := ""
	if name != "" {
		instance_name = fmt.aprintf("%s-Instances", name)
	}
	vertex_buffer_init_with_format(
		&mesh.InstanceData,
		graphics_device,
		instance_format,
		instance_name,
	)
	mesh.HasInstanceBuffer = true
}

mesh_init_instanced :: proc(
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	vertex_stride, instance_stride: int,
	index_format: IndexFormat,
	name: string = "",
) {
	mesh_init_instanced_with_format(
		mesh,
		graphics_device,
		vertex_format_make(nil, vertex_stride),
		vertex_format_make(nil, instance_stride),
		index_format,
		name,
	)
}

mesh_clear :: proc(mesh: ^Mesh) {
	vertex_buffer_clear(&mesh.VertexData)
	index_buffer_clear(&mesh.IndexData)
	if mesh.HasInstanceBuffer {
		vertex_buffer_clear(&mesh.InstanceData)
	}
}

mesh_set_index_count :: proc(mesh: ^Mesh, count: int) {
	index_buffer_clear(&mesh.IndexData)
	IndexBufferReserve(&mesh.IndexData, count)
}

mesh_set_vertex_count :: proc(mesh: ^Mesh, count: int) {
	vertex_buffer_clear(&mesh.VertexData)
	VertexBufferReserve(&mesh.VertexData, count)
}

mesh_set_instance_count :: proc(mesh: ^Mesh, count: int) {
	if !mesh.HasInstanceBuffer {
		panic("Mesh does not contain an instance buffer")
	}
	vertex_buffer_clear(&mesh.InstanceData)
	VertexBufferReserve(&mesh.InstanceData, count)
}

mesh_set_indices :: proc(mesh: ^Mesh, data: rawptr, count: int, offset: int = 0) {
	index_buffer_upload(&mesh.IndexData, data, count, offset)
}

mesh_set_vertices :: proc(mesh: ^Mesh, data: rawptr, count: int, offset: int = 0) {
	vertex_buffer_upload(&mesh.VertexData, data, count, offset)
}

mesh_set_instances :: proc(mesh: ^Mesh, data: rawptr, count: int, offset: int = 0) {
	if !mesh.HasInstanceBuffer {
		panic("Mesh does not contain an instance buffer")
	}
	vertex_buffer_upload(&mesh.InstanceData, data, count, offset)
}

mesh_dispose :: proc(mesh: ^Mesh) {
	vertex_buffer_dispose(&mesh.VertexData)
	index_buffer_dispose(&mesh.IndexData)
	if mesh.HasInstanceBuffer {
		vertex_buffer_dispose(&mesh.InstanceData)
	}
}

MeshInit :: proc {
	mesh_init,
	mesh_init_with_format,
}
MeshInitInstanced :: proc {
	mesh_init_instanced,
	mesh_init_instanced_with_format,
}
MeshClear :: mesh_clear
MeshSetIndexCount :: mesh_set_index_count
MeshSetVertexCount :: mesh_set_vertex_count
MeshSetInstanceCount :: mesh_set_instance_count
MeshSetIndices :: mesh_set_indices
MeshSetVertices :: mesh_set_vertices
MeshSetInstances :: mesh_set_instances
MeshDispose :: mesh_dispose

MeshVertexCount :: proc(mesh: ^Mesh) -> int {
	if mesh == nil {
		return 0
	}
	return mesh.VertexData.Base.Count
}

MeshIndexCount :: proc(mesh: ^Mesh) -> int {
	if mesh == nil {
		return 0
	}
	return mesh.IndexData.Base.Count
}

MeshInstanceCount :: proc(mesh: ^Mesh) -> int {
	if mesh == nil || !mesh.HasInstanceBuffer {
		return 0
	}
	return mesh.InstanceData.Base.Count
}

MeshIsDisposed :: proc(mesh: ^Mesh) -> bool {
	return mesh == nil || mesh.VertexData.Base.Disposed
}

MeshName :: proc(mesh: ^Mesh) -> string {
	if mesh == nil {
		return ""
	}
	return mesh.Name
}

// ==============================================================================
// Graphics / Structs / DrawCommand — 绘制命令
// ==============================================================================

VertexBufferBinding :: struct {
	Buffer:            ^VertexBuffer,
	InstanceInputRate: bool,
}

DrawCommand :: struct {
	Target:                 DrawableTarget,
	Material:               ^Material,
	VertexBuffers:          [dynamic]VertexBufferBinding,
	VertexStorageBuffers:   [dynamic]^StorageBuffer,
	FragmentStorageBuffers: [dynamic]^StorageBuffer,
	IndexBuffer:            ^IndexBuffer,
	IndexOffset:            int,
	IndexCount:             int,
	VertexOffset:           int,
	VertexCount:            int,
	InstanceCount:          int,
	BlendMode:              BlendMode,
	CullMode:               CullMode,
	DepthCompare:           DepthCompare,
	FillMode:               FillMode,
	BackStencilState:       StencilState,
	FrontStencilState:      StencilState,
	StencilCompareMask:     u8,
	StencilWriteMask:       u8,
	StencilReferenceValue:  u8,
	StencilTestEnabled:     bool,
	DepthTestEnabled:       bool,
	DepthWriteEnabled:      bool,
	Viewport:               RectInt,
	HasViewport:            bool,
	Scissor:                RectInt,
	HasScissor:             bool,
}

draw_command_init :: proc(command: ^DrawCommand) {
	command.Target = DrawableTarget{}
	command.Material = nil
	command.VertexBuffers = nil
	command.VertexStorageBuffers = nil
	command.FragmentStorageBuffers = nil
	command.IndexBuffer = nil
	command.IndexOffset = 0
	command.IndexCount = 0
	command.VertexOffset = 0
	command.VertexCount = 0
	command.InstanceCount = 1
	command.BlendMode = BlendModePremultiply
	command.CullMode = .None
	command.DepthCompare = .Less
	command.FillMode = .Fill
	command.BackStencilState = StencilStateMake(.Keep, .Always)
	command.FrontStencilState = StencilStateMake(.Keep, .Always)
	command.StencilCompareMask = 0xff
	command.StencilWriteMask = 0xff
	command.StencilReferenceValue = 0
	command.StencilTestEnabled = false
	command.DepthTestEnabled = false
	command.DepthWriteEnabled = false
	command.HasViewport = false
	command.HasScissor = false
}

draw_command_from_mesh :: proc(
	command: ^DrawCommand,
	target: DrawableTarget,
	mesh: ^Mesh,
	material: ^Material,
) {
	draw_command_init(command)
	command.Target = target
	command.Material = material
	append(
		&command.VertexBuffers,
		VertexBufferBinding{Buffer = &mesh.VertexData, InstanceInputRate = false},
	)

	if mesh.HasInstanceBuffer {
		append(
			&command.VertexBuffers,
			VertexBufferBinding{Buffer = &mesh.InstanceData, InstanceInputRate = true},
		)
		command.InstanceCount = mesh.InstanceData.Base.Count
	}

	if mesh.IndexData.Base.Count > 0 {
		command.IndexBuffer = &mesh.IndexData
		command.IndexCount = mesh.IndexData.Base.Count
	} else {
		command.VertexCount = mesh.VertexData.Base.Count
	}
}

draw_command_from_vertex_buffer :: proc(
	command: ^DrawCommand,
	target: DrawableTarget,
	vertex_buffer: ^VertexBuffer,
	material: ^Material,
) {
	draw_command_init(command)
	command.Target = target
	command.Material = material
	append(
		&command.VertexBuffers,
		VertexBufferBinding{Buffer = vertex_buffer, InstanceInputRate = false},
	)
	command.VertexCount = vertex_buffer.Base.Count
}

draw_command_dispose :: proc(command: ^DrawCommand) {
	delete(command.VertexBuffers)
	delete(command.VertexStorageBuffers)
	delete(command.FragmentStorageBuffers)
	command.VertexBuffers = nil
	command.VertexStorageBuffers = nil
	command.FragmentStorageBuffers = nil
}

DrawCommandInit :: draw_command_init
DrawCommandFromMesh :: draw_command_from_mesh
DrawCommandFromVertexBuffer :: draw_command_from_vertex_buffer
DrawCommandDispose :: draw_command_dispose

drawable_target_matches :: proc(a, b: DrawableTarget) -> bool {
	if a.GraphicsDevice != b.GraphicsDevice || a.IsWindow != b.IsWindow {
		return false
	}
	if a.IsWindow {
		return a.GraphicsDevice != nil
	}
	return a.Surface == b.Surface
}

resolve_drawable_target :: proc(
	graphics_device: ^GraphicsDevice,
	target: DrawableTarget,
) -> DrawableTarget {
	if graphics_device == nil {
		return target
	}
	if target.GraphicsDevice == nil {
		size := graphics_device.BackbufferSize
		if size.X <= 0 || size.Y <= 0 {
			size = Point2 {
				int(graphics_device.SwapchainWidth),
				int(graphics_device.SwapchainHeight),
			}
		}
		return DrawableTarget {
			GraphicsDevice = graphics_device,
			Surface        = graphics_device.Window,
			WidthInPixels  = size.X,
			HeightInPixels = size.Y,
			IsWindow       = true,
		}
	}
	if target.IsWindow && (target.WidthInPixels <= 0 || target.HeightInPixels <= 0) {
		resolved := target
		size := graphics_device.BackbufferSize
		if size.X <= 0 || size.Y <= 0 {
			size = Point2 {
				int(graphics_device.SwapchainWidth),
				int(graphics_device.SwapchainHeight),
			}
		}
		resolved.WidthInPixels = size.X
		resolved.HeightInPixels = size.Y
		return resolved
	}
	return target
}

drawable_target_backing_target :: proc(
	graphics_device: ^GraphicsDevice,
	target: DrawableTarget,
) -> (
	^Target,
	Point2,
) {
	resolved := resolve_drawable_target(graphics_device, target)
	if resolved.IsWindow {
		if graphics_device != nil && graphics_device.HasWindowRenderTarget {
			return &graphics_device.WindowRenderTarget, Point2{int(graphics_device.SwapchainWidth), int(graphics_device.SwapchainHeight)}
		}
		if graphics_device == nil || !graphics_device.HasBackbufferTarget {
			return nil, {}
		}
		return &graphics_device.BackbufferTarget, graphics_device.BackbufferSize
	}
	target_ptr := cast(^Target)resolved.Surface
	if target_ptr == nil {
		return nil, {}
	}
	return target_ptr, Point2{target_ptr.Width, target_ptr.Height}
}

// ==============================================================================
// Graphics / GraphicsDevice / RenderPass — 渲染通道
// ==============================================================================

end_render_pass :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device == nil {
		return
	}
	if graphics_device.RenderPass != nil {
		when ODIN_OS == .JS {
			fw_end_pass()
		} else {
			SDL.EndGPURenderPass(graphics_device.RenderPass)
		}
	}
	graphics_device.RenderPass = nil
	graphics_device.RenderPassTarget = {}
	graphics_device.RenderPassTargetSize = {}
	graphics_device.RenderPassPipeline = nil
	graphics_device.RenderPassIndexBuffer = nil
	graphics_device.HasRenderPassViewport = false
	graphics_device.HasRenderPassScissor = false
}

begin_render_pass_ex :: proc(
	graphics_device: ^GraphicsDevice,
	target: DrawableTarget,
	clear_colors: []Color,
	clear_depth: bool,
	depth: f32,
	clear_stencil: bool,
	stencil: int,
) -> bool {
	if graphics_device == nil || !graphics_device.InFrame || graphics_device.CommandBuffer == nil {
		return false
	}

	resolved_target := resolve_drawable_target(graphics_device, target)
	if resolved_target.GraphicsDevice != nil && resolved_target.GraphicsDevice != graphics_device {
		report_draw_failure(
			graphics_device,
			.ForeignTarget,
			"render target belongs to another GraphicsDevice",
		)
		return false
	}
	if graphics_device.RenderPass != nil &&
	   drawable_target_matches(graphics_device.RenderPassTarget, resolved_target) &&
	   len(clear_colors) == 0 &&
	   !clear_depth &&
	   !clear_stencil {
		return true
	}

	when ODIN_OS == .JS {
		end_render_pass(graphics_device)
		if !resolved_target.IsWindow {
			target_ptr := cast(^Target)resolved_target.Surface
			if target_ptr == nil || target_ptr.Disposed {
				return false
			}
			colors: [dynamic]u32
			defer delete(colors)
			depth_handle: u32
			for i in 0 ..< len(target_ptr.Attachments) {
				texture := &target_ptr.Attachments[i]
				if texture_format_is_color_format(texture.Format) {
					append(&colors, web_handle_u32(rawptr(texture.Resource)))
				} else {
					depth_handle = web_handle_u32(rawptr(texture.Resource))
				}
			}
			if !fw_begin_target(
				raw_data(colors),
				i32(len(colors)),
				depth_handle,
				raw_data(clear_colors),
				i32(len(clear_colors)),
				clear_depth,
				depth,
				clear_stencil,
				i32(stencil),
			) {
				return false
			}
		} else if len(clear_colors) > 0 {
			cc := ColorToSDL(clear_colors[0])
			fw_begin_pass(0, cc.r, cc.g, cc.b, cc.a, 1)
		} else {
			fw_begin_pass(0, 0, 0, 0, 0, 0)
		}
		graphics_device.RenderPass = cast(^SDL.GPURenderPass)&web_renderpass_placeholder
		graphics_device.RenderPassTarget = resolved_target
		graphics_device.RenderPassTargetSize = drawable_target_size_in_pixels(resolved_target)
		graphics_device.RenderPassPipeline = nil
		graphics_device.RenderPassIndexBuffer = nil
		graphics_device.HasRenderPassViewport = false
		graphics_device.HasRenderPassScissor = false
		return true
	}

	end_render_pass(graphics_device)

	target_ptr, target_size := drawable_target_backing_target(graphics_device, resolved_target)
	if target_ptr == nil || len(target_ptr.Attachments) <= 0 {
		report_draw_failure(graphics_device, .MissingTarget, "render target has no attachments")
		return false
	}

	color_targets := make(
		[]SDL.GPUColorTargetInfo,
		len(target_ptr.Attachments),
		context.temp_allocator,
	)
	color_count := 0
	depth_target_value := SDL.GPUDepthStencilTargetInfo{}
	depth_target_ptr: ^SDL.GPUDepthStencilTargetInfo = nil

	for i := 0; i < len(target_ptr.Attachments); i += 1 {
		attachment := target_ptr.Attachments[i]
		if attachment.Resource == nil {
			continue
		}

		if texture_format_is_color_format(attachment.Format) {
			color_target := SDL.GPUColorTargetInfo {
				texture              = attachment.Resource,
				mip_level            = 0,
				layer_or_depth_plane = 0,
				load_op              = .LOAD,
				store_op             = .STORE,
				cycle                = len(clear_colors) > 0,
			}
			if attachment.ResolveResource != nil {
				color_target.store_op = .RESOLVE
				color_target.resolve_texture = attachment.ResolveResource
				color_target.resolve_mip_level = 0
				color_target.resolve_layer = 0
				color_target.cycle_resolve_texture = false
			}
			if len(clear_colors) > 0 {
				clear_color := Transparent
				if color_count < len(clear_colors) {
					clear_color = clear_colors[color_count]
				}
				color_target.clear_color = ColorToSDL(clear_color)
				color_target.load_op = .CLEAR
			}
			color_targets[color_count] = color_target
			color_count += 1
		} else {
			depth_target_value = SDL.GPUDepthStencilTargetInfo {
				texture          = attachment.Resource,
				clear_depth      = depth,
				load_op          = .LOAD,
				store_op         = .STORE,
				stencil_load_op  = .LOAD,
				stencil_store_op = .STORE,
				cycle            = clear_depth || clear_stencil,
				clear_stencil    = u8(stencil),
			}
			if clear_depth {
				depth_target_value.load_op = .CLEAR
			}
			if clear_stencil {
				depth_target_value.stencil_load_op = .CLEAR
			}
			depth_target_ptr = &depth_target_value
		}
	}

	color_target_ptr: ^SDL.GPUColorTargetInfo = nil
	if color_count > 0 {
		color_target_ptr = &color_targets[0]
	}

	graphics_device.RenderPass = SDL.BeginGPURenderPass(
		graphics_device.CommandBuffer,
		color_target_ptr,
		u32(color_count),
		depth_target_ptr,
	)
	graphics_device.RenderPassTargetSize = target_size

	if graphics_device.RenderPass == nil {
		report_draw_failure(graphics_device, .RenderPass, "SDL_BeginGPURenderPass failed", true)
		return false
	}

	graphics_device.RenderPassTarget = resolved_target
	graphics_device.RenderPassPipeline = nil
	graphics_device.RenderPassIndexBuffer = nil
	graphics_device.HasRenderPassViewport = false
	graphics_device.HasRenderPassScissor = false
	return true
}

begin_render_pass :: proc(graphics_device: ^GraphicsDevice, target: DrawableTarget) -> bool {
	return begin_render_pass_ex(graphics_device, target, nil, false, 0, false, 0)
}

blend_factor_to_sdl :: proc(factor: BlendFactor) -> SDL.GPUBlendFactor {
	#partial switch factor {
	case .Zero:
		return .ZERO
	case .One:
		return .ONE
	case .SrcColor:
		return .SRC_COLOR
	case .OneMinusSrcColor:
		return .ONE_MINUS_SRC_COLOR
	case .DstColor:
		return .DST_COLOR
	case .OneMinusDstColor:
		return .ONE_MINUS_DST_COLOR
	case .SrcAlpha:
		return .SRC_ALPHA
	case .OneMinusSrcAlpha:
		return .ONE_MINUS_SRC_ALPHA
	case .DstAlpha:
		return .DST_ALPHA
	case .OneMinusDstAlpha:
		return .ONE_MINUS_DST_ALPHA
	case .ConstantColor:
		return .CONSTANT_COLOR
	case .OneMinusConstantColor:
		return .ONE_MINUS_CONSTANT_COLOR
	case .SrcAlphaSaturate:
		return .SRC_ALPHA_SATURATE
	}
	return .ONE
}

blend_op_to_sdl :: proc(op: BlendOp) -> SDL.GPUBlendOp {
	#partial switch op {
	case .Add:
		return .ADD
	case .Subtract:
		return .SUBTRACT
	case .ReverseSubtract:
		return .REVERSE_SUBTRACT
	case .Min:
		return .MIN
	case .Max:
		return .MAX
	}
	return .ADD
}

blend_mask_to_sdl :: proc(mask: BlendMask) -> SDL.GPUColorComponentFlags {
	flags: SDL.GPUColorComponentFlags = {}
	mask_bits := u8(mask)
	if (mask_bits & u8(BlendMask.Red)) != 0 {
		flags += {.R}
	}
	if (mask_bits & u8(BlendMask.Green)) != 0 {
		flags += {.G}
	}
	if (mask_bits & u8(BlendMask.Blue)) != 0 {
		flags += {.B}
	}
	if (mask_bits & u8(BlendMask.Alpha)) != 0 {
		flags += {.A}
	}
	return flags
}

cull_mode_to_sdl :: proc(mode: CullMode) -> SDL.GPUCullMode {
	#partial switch mode {
	case .None:
		return .NONE
	case .Front:
		return .FRONT
	case .Back:
		return .BACK
	}
	return .NONE
}

fill_mode_to_sdl :: proc(mode: FillMode) -> SDL.GPUFillMode {
	#partial switch mode {
	case .Fill:
		return .FILL
	case .Line:
		return .LINE
	}
	return .FILL
}

stencil_op_to_sdl :: proc(op: StencilOp) -> SDL.GPUStencilOp {
	#partial switch op {
	case .Keep:
		return .KEEP
	case .Zero:
		return .ZERO
	case .Replace:
		return .REPLACE
	case .IncrementAndClamp:
		return .INCREMENT_AND_CLAMP
	case .DecrementAndClamp:
		return .DECREMENT_AND_CLAMP
	case .Invert:
		return .INVERT
	case .IncrementAndWrap:
		return .INCREMENT_AND_WRAP
	case .DecrementAndWrap:
		return .DECREMENT_AND_WRAP
	case .Invalid:
		return .INVALID
	}
	return .KEEP
}

stencil_state_to_sdl :: proc(state: StencilState) -> SDL.GPUStencilOpState {
	return SDL.GPUStencilOpState {
		fail_op       = stencil_op_to_sdl(state.FailOp),
		pass_op       = stencil_op_to_sdl(state.PassOp),
		depth_fail_op = stencil_op_to_sdl(state.DepthFailOp),
		compare_op    = depth_compare_to_sdl(state.CompareOp),
	}
}

depth_compare_to_sdl :: proc(compare: DepthCompare) -> SDL.GPUCompareOp {
	#partial switch compare {
	case .Always:
		return .ALWAYS
	case .Never:
		return .NEVER
	case .Less:
		return .LESS
	case .Equal:
		return .EQUAL
	case .LessOrEqual:
		return .LESS_OR_EQUAL
	case .Greater:
		return .GREATER
	case .NotEqual:
		return .NOT_EQUAL
	case .GreatorOrEqual:
		return .GREATER_OR_EQUAL
	}
	return .ALWAYS
}

texture_filter_to_sdl :: proc(filter: TextureFilter) -> SDL.GPUFilter {
	#partial switch filter {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}
	return .LINEAR
}

texture_wrap_to_sdl :: proc(wrap: TextureWrap) -> SDL.GPUSamplerAddressMode {
	#partial switch wrap {
	case .Repeat:
		return .REPEAT
	case .MirroredRepeat:
		return .MIRRORED_REPEAT
	case .Clamp:
		return .CLAMP_TO_EDGE
	}
	return .CLAMP_TO_EDGE
}

create_sampler_from_texture_sampler :: proc(
	graphics_device: ^GraphicsDevice,
	sampler: TextureSampler,
) -> ^SDL.GPUSampler {
	if graphics_device == nil || graphics_device.Device == nil {
		return nil
	}
	if graphics_device.SamplerCache == nil {
		graphics_device.SamplerCache = make(map[TextureSampler]^SDL.GPUSampler)
	}
	if cached, ok := graphics_device.SamplerCache[sampler]; ok && cached != nil {
		return cached
	}
	when ODIN_OS == .JS {
		handle := fw_gl_create_sampler(
			web_texture_filter(sampler.Filter),
			web_texture_wrap(sampler.WrapX),
			web_texture_wrap(sampler.WrapY),
		)
		if handle != 0 {
			created := cast(^SDL.GPUSampler)(web_handle_ptr(handle))
			graphics_device.SamplerCache[sampler] = created
			return created
		}
		return nil
	}
	info := SDL.GPUSamplerCreateInfo {
		min_filter        = texture_filter_to_sdl(sampler.Filter),
		mag_filter        = texture_filter_to_sdl(sampler.Filter),
		mipmap_mode       = .LINEAR,
		address_mode_u    = texture_wrap_to_sdl(sampler.WrapX),
		address_mode_v    = texture_wrap_to_sdl(sampler.WrapY),
		address_mode_w    = .CLAMP_TO_EDGE,
		mip_lod_bias      = 0,
		max_anisotropy    = 1,
		compare_op        = .ALWAYS,
		min_lod           = 0,
		max_lod           = 0,
		enable_anisotropy = false,
		enable_compare    = false,
		props             = 0,
	}
	created := SDL.CreateGPUSampler(graphics_device.Device, info)
	if created != nil {
		graphics_device.SamplerCache[sampler] = created
	}
	return created
}

hash_mix_u64 :: proc(h, v: u64) -> u64 {
	x := h ~ v
	x *= 1099511628211
	return x
}

hash_color_u32 :: proc(c: Color) -> u32 {
	return u32(c.R) | (u32(c.G) << 8) | (u32(c.B) << 16) | (u32(c.A) << 24)
}

hash_blend_mode :: proc(seed: u64, bm: BlendMode) -> u64 {
	h := seed
	h = hash_mix_u64(h, u64(bm.ColorOperation))
	h = hash_mix_u64(h, u64(bm.ColorSource))
	h = hash_mix_u64(h, u64(bm.ColorDestination))
	h = hash_mix_u64(h, u64(bm.AlphaOperation))
	h = hash_mix_u64(h, u64(bm.AlphaSource))
	h = hash_mix_u64(h, u64(bm.AlphaDestination))
	h = hash_mix_u64(h, u64(bm.Mask))
	h = hash_mix_u64(h, u64(hash_color_u32(bm.Color)))
	return h
}

shader_register_pipeline_hash :: proc(shader: ^Shader, hash: u64) {
	if shader == nil {
		return
	}
	for h in shader.PipelineHashes {
		if h == hash {
			return
		}
	}
	append(&shader.PipelineHashes, hash)
}

graphics_device_release_pipeline_hashes :: proc(
	graphics_device: ^GraphicsDevice,
	hashes: ^[dynamic]u64,
) {
	if graphics_device == nil || graphics_device.Device == nil || hashes == nil {
		return
	}
	for h in hashes^ {
		delete_key(&graphics_device.FailedPipelineHashes, h)
		if graphics_device.PipelineCache != nil {
			if pipeline, ok := graphics_device.PipelineCache[h]; ok {
				if pipeline != nil {
					when ODIN_OS == .JS {
						fw_gl_release_pipeline(web_handle_u32(rawptr(pipeline)))
					} else {
						SDL.ReleaseGPUGraphicsPipeline(graphics_device.Device, pipeline)
					}
				}
				delete_key(&graphics_device.PipelineCache, h)
			}
		}
	}
	delete(hashes^)
	hashes^ = nil
}

graphics_device_dispose_caches :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device == nil || graphics_device.Device == nil {
		return
	}
	delete(graphics_device.FailedPipelineHashes)
	graphics_device.FailedPipelineHashes = nil
	graphics_device.ReportedDrawFailures = {}
	if graphics_device.PipelineCache != nil {
		for _, pipeline in graphics_device.PipelineCache {
			if pipeline != nil {
				when ODIN_OS == .JS {
					fw_gl_release_pipeline(web_handle_u32(rawptr(pipeline)))
				} else {
					SDL.ReleaseGPUGraphicsPipeline(graphics_device.Device, pipeline)
				}
			}
		}
		delete(graphics_device.PipelineCache)
		graphics_device.PipelineCache = nil
	}
	if graphics_device.SamplerCache != nil {
		for _, sampler in graphics_device.SamplerCache {
			if sampler != nil {
				when ODIN_OS == .JS {
					fw_gl_release_sampler(web_handle_u32(rawptr(sampler)))
				} else {
					SDL.ReleaseGPUSampler(graphics_device.Device, sampler)
				}
			}
		}
		delete(graphics_device.SamplerCache)
		graphics_device.SamplerCache = nil
	}
}

// ------------------------------------------------------------------------------
// Graphics / GraphicsDevice / Pipeline — 管线缓存与创建
// ------------------------------------------------------------------------------

create_pipeline_for_draw_command :: proc(
	graphics_device: ^GraphicsDevice,
	command: ^DrawCommand,
) -> ^SDL.GPUGraphicsPipeline {
	if graphics_device == nil ||
	   graphics_device.Device == nil ||
	   command == nil ||
	   command.Material == nil ||
	   command.Material.Vertex.Shader == nil ||
	   command.Material.Fragment.Shader == nil {
		report_draw_failure(
			graphics_device,
			.InvalidCommand,
			"cannot create pipeline: device, command, material or shader is missing",
		)
		return nil
	}
	if command.Material.Vertex.Shader.Resource == nil ||
	   command.Material.Fragment.Shader.Resource == nil {
		report_draw_failure(
			graphics_device,
			.MissingShaderResource,
			"draw shader has no GPU resource (uninitialized or disposed)",
		)
		return nil
	}
	target := resolve_drawable_target(graphics_device, command.Target)
	if graphics_device.PipelineCache == nil {
		graphics_device.PipelineCache = make(map[u64]^SDL.GPUGraphicsPipeline)
	}
	if len(command.VertexBuffers) <= 0 {
		report_draw_failure(
			graphics_device,
			.InvalidVertexBuffer,
			"draw requires a vertex buffer with a valid format and GPU resource",
		)
		return nil
	}
	vertex_buffer_count := len(command.VertexBuffers)
	total_attributes := 0
	for i := 0; i < vertex_buffer_count; i += 1 {
		vb := command.VertexBuffers[i].Buffer
		if vb == nil || vb.Stride <= 0 || vb.Base.Resource == nil {
			report_draw_failure(
				graphics_device,
				.InvalidVertexBuffer,
				"draw requires a vertex buffer with a valid format and GPU resource",
			)
			return nil
		}
		total_attributes += len(vb.Format.Elements)
	}
	if total_attributes <= 0 {
		report_draw_failure(
			graphics_device,
			.InvalidVertexBuffer,
			"draw vertex format has no attributes",
		)
		return nil
	}
	vb_desc := make([]SDL.GPUVertexBufferDescription, vertex_buffer_count, context.temp_allocator)
	attrs := make([]SDL.GPUVertexAttribute, total_attributes, context.temp_allocator)
	attr_index := 0
	for i := 0; i < vertex_buffer_count; i += 1 {
		vb := command.VertexBuffers[i].Buffer
		vb_desc[i] = SDL.GPUVertexBufferDescription {
			slot               = u32(i),
			pitch              = u32(vb.Stride),
			input_rate         = .VERTEX,
			instance_step_rate = 0,
		}
		if command.VertexBuffers[i].InstanceInputRate {
			vb_desc[i].input_rate = .INSTANCE
		}
		offset := 0
		for element in vb.Format.Elements {
			attrs[attr_index] = SDL.GPUVertexAttribute {
				location    = u32(element.Index),
				buffer_slot = u32(i),
				format      = vertex_type_to_sdl(element.Type, element.Normalized),
				offset      = u32(offset),
			}
			offset += vertex_type_size_in_bytes(element.Type)
			attr_index += 1
		}
	}
	vertex_input := SDL.GPUVertexInputState {
		vertex_buffer_descriptions = &vb_desc[0],
		num_vertex_buffers         = u32(len(vb_desc)),
		vertex_attributes          = &attrs[0],
		num_vertex_attributes      = u32(len(attrs)),
	}

	blend_state := SDL.GPUColorTargetBlendState {
		src_color_blendfactor   = blend_factor_to_sdl(command.BlendMode.ColorSource),
		dst_color_blendfactor   = blend_factor_to_sdl(command.BlendMode.ColorDestination),
		color_blend_op          = blend_op_to_sdl(command.BlendMode.ColorOperation),
		src_alpha_blendfactor   = blend_factor_to_sdl(command.BlendMode.AlphaSource),
		dst_alpha_blendfactor   = blend_factor_to_sdl(command.BlendMode.AlphaDestination),
		alpha_blend_op          = blend_op_to_sdl(command.BlendMode.AlphaOperation),
		color_write_mask        = blend_mask_to_sdl(command.BlendMode.Mask),
		enable_blend            = command.BlendMode != BlendModeDisabled,
		enable_color_write_mask = true,
	}
	color_target_desc := [8]SDL.GPUColorTargetDescription{}
	color_target_count := 0
	depth_stencil_format := SDL.GPUTextureFormat.INVALID
	sample_count := SDL.GPUSampleCount._1
	target_ptr, _ := drawable_target_backing_target(graphics_device, target)
	if target_ptr == nil {
		report_draw_failure(
			graphics_device,
			.MissingTarget,
			"cannot create pipeline: render target is missing",
		)
		return nil
	}
	for i := 0; i < len(target_ptr.Attachments); i += 1 {
		attachment := target_ptr.Attachments[i]
		attachment_format := texture_format_to_sdl(attachment.Format)
		attachment_sample_count := sample_count_to_sdl(attachment.SampleCount)
		if attachment_sample_count > sample_count {
			sample_count = attachment_sample_count
		}
		if texture_format_is_color_format(attachment.Format) {
			color_target_desc[color_target_count] = SDL.GPUColorTargetDescription {
				format      = attachment_format,
				blend_state = blend_state,
			}
			color_target_count += 1
		} else {
			depth_stencil_format = attachment_format
		}
	}
	if color_target_count <= 0 {
		report_draw_failure(
			graphics_device,
			.MissingColorTarget,
			"draw pipeline requires a color attachment",
		)
		return nil
	}

	hash: u64 = 1469598103934665603
	hash = hash_mix_u64(hash, u64(uintptr(command.Material.Vertex.Shader.Resource)))
	hash = hash_mix_u64(hash, u64(uintptr(command.Material.Fragment.Shader.Resource)))
	hash = hash_blend_mode(hash, command.BlendMode)
	hash = hash_mix_u64(hash, command.BlendMode == BlendModeDisabled ? 0 : 1)
	hash = hash_mix_u64(hash, u64(command.CullMode))
	hash = hash_mix_u64(hash, u64(command.FillMode))
	hash = hash_mix_u64(hash, u64(command.BackStencilState.FailOp))
	hash = hash_mix_u64(hash, u64(command.BackStencilState.PassOp))
	hash = hash_mix_u64(hash, u64(command.BackStencilState.DepthFailOp))
	hash = hash_mix_u64(hash, u64(command.BackStencilState.CompareOp))
	hash = hash_mix_u64(hash, u64(command.FrontStencilState.FailOp))
	hash = hash_mix_u64(hash, u64(command.FrontStencilState.PassOp))
	hash = hash_mix_u64(hash, u64(command.FrontStencilState.DepthFailOp))
	hash = hash_mix_u64(hash, u64(command.FrontStencilState.CompareOp))
	hash = hash_mix_u64(hash, u64(command.StencilCompareMask))
	hash = hash_mix_u64(hash, u64(command.StencilWriteMask))
	if command.StencilTestEnabled {
		hash = hash_mix_u64(hash, 1)
	} else {
		hash = hash_mix_u64(hash, 0)
	}
	hash = hash_mix_u64(hash, u64(command.DepthCompare))
	if command.DepthTestEnabled {
		hash = hash_mix_u64(hash, 1)
	} else {
		hash = hash_mix_u64(hash, 0)
	}
	if command.DepthWriteEnabled {
		hash = hash_mix_u64(hash, 1)
	} else {
		hash = hash_mix_u64(hash, 0)
	}
	hash = hash_mix_u64(hash, u64(color_target_count))
	for i := 0; i < color_target_count; i += 1 {
		hash = hash_mix_u64(hash, u64(color_target_desc[i].format))
	}
	hash = hash_mix_u64(hash, u64(depth_stencil_format))
	hash = hash_mix_u64(hash, u64(sample_count))
	if command.IndexBuffer != nil {
		hash = hash_mix_u64(hash, u64(command.IndexBuffer.Format))
	} else {
		hash = hash_mix_u64(hash, 0)
	}
	for i := 0; i < len(command.VertexBuffers); i += 1 {
		vb := command.VertexBuffers[i].Buffer
		hash = hash_mix_u64(hash, u64(vb.Stride))
		if command.VertexBuffers[i].InstanceInputRate {
			hash = hash_mix_u64(hash, 1)
		} else {
			hash = hash_mix_u64(hash, 0)
		}
		for element in vb.Format.Elements {
			hash = hash_mix_u64(hash, u64(element.Index))
			hash = hash_mix_u64(hash, u64(element.Type))
			if element.Normalized {
				hash = hash_mix_u64(hash, 1)
			} else {
				hash = hash_mix_u64(hash, 0)
			}
		}
	}

	if cached, ok := graphics_device.PipelineCache[hash]; ok && cached != nil {
		return cached
	}

	when ODIN_OS == .JS {
		blend_enable := u32(0)
		if command.BlendMode != BlendModeDisabled {
			blend_enable = 1
		}
		handle := fw_gl_create_pipeline(
			web_handle_u32(rawptr(command.Material.Vertex.Shader.Resource)),
			web_handle_u32(rawptr(command.Material.Fragment.Shader.Resource)),
			blend_enable,
			web_blend_factor(command.BlendMode.ColorSource),
			web_blend_factor(command.BlendMode.ColorDestination),
			web_blend_op(command.BlendMode.ColorOperation),
			web_blend_factor(command.BlendMode.AlphaSource),
			web_blend_factor(command.BlendMode.AlphaDestination),
			web_blend_op(command.BlendMode.AlphaOperation),
			u32(u8(command.BlendMode.Mask)),
			web_cull_mode(command.CullMode),
			web_fill_mode(command.FillMode),
		)
		if handle != 0 {
			fw_gl_pipeline_depth_stencil(
				handle,
				command.DepthTestEnabled,
				command.DepthWriteEnabled,
				u32(command.DepthCompare),
				command.StencilTestEnabled,
				u32(command.StencilCompareMask),
				u32(command.StencilWriteMask),
				u32(command.FrontStencilState.FailOp),
				u32(command.FrontStencilState.PassOp),
				u32(command.FrontStencilState.DepthFailOp),
				u32(command.FrontStencilState.CompareOp),
				u32(command.BackStencilState.FailOp),
				u32(command.BackStencilState.PassOp),
				u32(command.BackStencilState.DepthFailOp),
				u32(command.BackStencilState.CompareOp),
			)
			graphics_device.PipelineCache[hash] = cast(^SDL.GPUGraphicsPipeline)(web_handle_ptr(
					handle,
				))
		} else if !graphics_device.FailedPipelineHashes[hash] {
			if graphics_device.FailedPipelineHashes == nil {
				graphics_device.FailedPipelineHashes = make(map[u64]bool)
			}
			graphics_device.FailedPipelineHashes[hash] = true
			web_log("OFoster: web pipeline creation failed")
		}
		shader_register_pipeline_hash(command.Material.Vertex.Shader, hash)
		shader_register_pipeline_hash(command.Material.Fragment.Shader, hash)
		if handle != 0 {
			return graphics_device.PipelineCache[hash]
		}
		return nil
	}

	target_info := SDL.GPUGraphicsPipelineTargetInfo {
		color_target_descriptions = &color_target_desc[0],
		num_color_targets         = u32(color_target_count),
		depth_stencil_format      = depth_stencil_format,
		has_depth_stencil_target  = depth_stencil_format != .INVALID,
	}

	depth_stencil := SDL.GPUDepthStencilState {
		compare_op          = depth_compare_to_sdl(command.DepthCompare),
		back_stencil_state  = stencil_state_to_sdl(command.BackStencilState),
		front_stencil_state = stencil_state_to_sdl(command.FrontStencilState),
		compare_mask        = command.StencilCompareMask,
		write_mask          = command.StencilWriteMask,
		enable_depth_test   = command.DepthTestEnabled,
		enable_depth_write  = command.DepthWriteEnabled,
		enable_stencil_test = command.StencilTestEnabled,
	}
	rasterizer := SDL.GPURasterizerState {
		fill_mode                  = fill_mode_to_sdl(command.FillMode),
		cull_mode                  = cull_mode_to_sdl(command.CullMode),
		front_face                 = .COUNTER_CLOCKWISE,
		depth_bias_constant_factor = 0,
		depth_bias_clamp           = 0,
		depth_bias_slope_factor    = 0,
		enable_depth_bias          = false,
		enable_depth_clip          = true,
	}
	multisample := SDL.GPUMultisampleState {
		sample_count             = sample_count,
		sample_mask              = 0,
		enable_mask              = false,
		enable_alpha_to_coverage = false,
	}

	pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader       = command.Material.Vertex.Shader.Resource,
		fragment_shader     = command.Material.Fragment.Shader.Resource,
		vertex_input_state  = vertex_input,
		primitive_type      = .TRIANGLELIST,
		rasterizer_state    = rasterizer,
		multisample_state   = multisample,
		depth_stencil_state = depth_stencil,
		target_info         = target_info,
		props               = 0,
	}
	pipeline := SDL.CreateGPUGraphicsPipeline(graphics_device.Device, pipeline_info)
	if pipeline != nil {
		graphics_device.PipelineCache[hash] = pipeline
		delete_key(&graphics_device.FailedPipelineHashes, hash)
	} else if !graphics_device.FailedPipelineHashes[hash] {
		if graphics_device.FailedPipelineHashes == nil {
			graphics_device.FailedPipelineHashes = make(map[u64]bool)
		}
		graphics_device.FailedPipelineHashes[hash] = true
		vertex_name := command.Material.Vertex.Shader.Name
		fragment_name := command.Material.Fragment.Shader.Name
		if len(vertex_name) == 0 {
			vertex_name = "<unnamed>"
		}
		if len(fragment_name) == 0 {
			fragment_name = "<unnamed>"
		}
		SDL.LogError(
			i32(SDL.LogCategory.GPU),
			"OFoster: SDL_CreateGPUGraphicsPipeline failed (vertex='%.*s', fragment='%.*s'): %s",
			i32(len(vertex_name)),
			raw_data(vertex_name),
			i32(len(fragment_name)),
			raw_data(fragment_name),
			SDL.GetError(),
		)
	}
	// Include failed attempts so disposal/reloading also clears their diagnostics.
	shader_register_pipeline_hash(command.Material.Vertex.Shader, hash)
	shader_register_pipeline_hash(command.Material.Fragment.Shader, hash)
	return pipeline
}

// ------------------------------------------------------------------------------
// Graphics / GraphicsDevice / Draw — 资源绑定与提交
// ------------------------------------------------------------------------------

graphics_device_draw :: proc(graphics_device: ^GraphicsDevice, command: ^DrawCommand) {
	if graphics_device == nil {
		return
	}
	if command == nil {
		report_draw_failure(graphics_device, .InvalidCommand, "draw command is nil")
		return
	}
	if command.Material == nil {
		report_draw_failure(graphics_device, .MissingMaterial, "draw material is nil")
		return
	}
	if !graphics_device.InFrame || graphics_device.CommandBuffer == nil {
		return
	}
	target := resolve_drawable_target(graphics_device, command.Target)
	if target.GraphicsDevice != nil && target.GraphicsDevice != graphics_device {
		report_draw_failure(
			graphics_device,
			.ForeignTarget,
			"render target belongs to another GraphicsDevice",
		)
		return
	}
	if len(command.VertexBuffers) <= 0 ||
	   command.VertexBuffers[0].Buffer == nil ||
	   command.VertexBuffers[0].Buffer.Base.Resource == nil {
		report_draw_failure(
			graphics_device,
			.InvalidVertexBuffer,
			"draw requires a vertex buffer with a valid format and GPU resource",
		)
		return
	}
	if command.Material.Vertex.Shader == nil || command.Material.Fragment.Shader == nil {
		report_draw_failure(
			graphics_device,
			.MissingShader,
			"draw requires both vertex and fragment shaders",
		)
		return
	}
	if command.Material.Vertex.Shader.Resource == nil ||
	   command.Material.Fragment.Shader.Resource == nil {
		report_draw_failure(
			graphics_device,
			.MissingShaderResource,
			"draw shader has no GPU resource (uninitialized or disposed)",
		)
		return
	}
	if !begin_render_pass(graphics_device, target) || graphics_device.RenderPass == nil {
		return
	}

	pipeline := create_pipeline_for_draw_command(graphics_device, command)
	if pipeline == nil {
		return
	}
	if graphics_device.RenderPassPipeline != pipeline {
		when ODIN_OS == .JS {
			fw_bind_pipeline(web_handle_u32(rawptr(pipeline)))
		} else {
			SDL.BindGPUGraphicsPipeline(graphics_device.RenderPass, pipeline)
		}
		graphics_device.RenderPassPipeline = pipeline
	}
	when ODIN_OS == .JS {
		fw_set_stencil_reference(u32(command.StencilReferenceValue))
	} else {
		SDL.SetGPUStencilReference(graphics_device.RenderPass, command.StencilReferenceValue)
	}

	viewport := RectInt {
		0,
		0,
		graphics_device.RenderPassTargetSize.X,
		graphics_device.RenderPassTargetSize.Y,
	}
	if command.HasViewport {
		viewport = command.Viewport
	}
	if !graphics_device.HasRenderPassViewport || graphics_device.RenderPassViewport != viewport {
		when ODIN_OS == .JS {
			fw_set_viewport(
				i32(viewport.X),
				i32(viewport.Y),
				i32(viewport.Width),
				i32(viewport.Height),
				i32(graphics_device.RenderPassTargetSize.Y),
			)
		} else {
			SDL.SetGPUViewport(graphics_device.RenderPass, SDL.GPUViewport {
				x         = f32(viewport.X),
				y         = f32(viewport.Y),
				w         = f32(viewport.Width),
				h         = f32(viewport.Height),
				min_depth = 0,
				max_depth = 1,
			})
		}
		graphics_device.RenderPassViewport = viewport
		graphics_device.HasRenderPassViewport = true
	}

	scissor := viewport
	if command.HasScissor {
		scissor = command.Scissor
	}
	if !graphics_device.HasRenderPassScissor || graphics_device.RenderPassScissor != scissor {
		when ODIN_OS == .JS {
			fw_set_scissor(
				i32(scissor.X),
				i32(scissor.Y),
				i32(scissor.Width),
				i32(scissor.Height),
				i32(graphics_device.RenderPassTargetSize.Y),
			)
		} else {
			SDL.SetGPUScissor(graphics_device.RenderPass, SDL.Rect {
				x = i32(scissor.X),
				y = i32(scissor.Y),
				w = i32(scissor.Width),
				h = i32(scissor.Height),
			})
		}
		graphics_device.RenderPassScissor = scissor
		graphics_device.HasRenderPassScissor = true
	}

	vertex_info := command.Material.Vertex.Shader.CreateInfo
	fragment_info := command.Material.Fragment.Shader.CreateInfo

	if vertex_info.SamplerCount > 0 {
		when ODIN_OS == .JS {
			for i := 0; i < vertex_info.SamplerCount; i += 1 {
				texture_handle := u32(0) // 0 = JS 侧 1x1 白纹理占位
				sampler_handle := u32(0)
				if command.Material.Vertex.Samplers[i].Texture != nil {
					texture_handle = web_handle_u32(
						rawptr(
							texture_sample_resource(command.Material.Vertex.Samplers[i].Texture),
						),
					)
					if cached := create_sampler_from_texture_sampler(
						graphics_device,
						command.Material.Vertex.Samplers[i].Sampler,
					); cached != nil {
						sampler_handle = web_handle_u32(rawptr(cached))
					}
				}
				fw_bind_texture(u32(i), texture_handle, sampler_handle)
			}
		} else {
			vb := make(
				[]SDL.GPUTextureSamplerBinding,
				vertex_info.SamplerCount,
				context.temp_allocator,
			)
			for i := 0; i < len(vb); i += 1 {
				texture := graphics_device.DebugTexture
				sampler := graphics_device.DebugSampler
				if command.Material.Vertex.Samplers[i].Texture != nil {
					texture = texture_sample_resource(command.Material.Vertex.Samplers[i].Texture)
					cached := create_sampler_from_texture_sampler(
						graphics_device,
						command.Material.Vertex.Samplers[i].Sampler,
					)
					if cached != nil {
						sampler = cached
					}
				}
				vb[i] = SDL.GPUTextureSamplerBinding {
					texture = texture,
					sampler = sampler,
				}
			}
			SDL.BindGPUVertexSamplers(graphics_device.RenderPass, 0, &vb[0], u32(len(vb)))
		}
	}

	if fragment_info.SamplerCount > 0 {
		when ODIN_OS == .JS {
			for i := 0; i < fragment_info.SamplerCount; i += 1 {
				texture_handle := u32(0)
				sampler_handle := u32(0)
				if command.Material.Fragment.Samplers[i].Texture != nil {
					texture_handle = web_handle_u32(
						rawptr(
							texture_sample_resource(command.Material.Fragment.Samplers[i].Texture),
						),
					)
					if cached := create_sampler_from_texture_sampler(
						graphics_device,
						command.Material.Fragment.Samplers[i].Sampler,
					); cached != nil {
						sampler_handle = web_handle_u32(rawptr(cached))
					}
				}
				fw_bind_texture(u32(i), texture_handle, sampler_handle)
			}
		} else {
			fb := make(
				[]SDL.GPUTextureSamplerBinding,
				fragment_info.SamplerCount,
				context.temp_allocator,
			)
			for i := 0; i < len(fb); i += 1 {
				texture := graphics_device.DebugTexture
				sampler := graphics_device.DebugSampler
				if command.Material.Fragment.Samplers[i].Texture != nil {
					texture = texture_sample_resource(
						command.Material.Fragment.Samplers[i].Texture,
					)
					cached := create_sampler_from_texture_sampler(
						graphics_device,
						command.Material.Fragment.Samplers[i].Sampler,
					)
					if cached != nil {
						sampler = cached
					}
				}
				fb[i] = SDL.GPUTextureSamplerBinding {
					texture = texture,
					sampler = sampler,
				}
			}
			SDL.BindGPUFragmentSamplers(graphics_device.RenderPass, 0, &fb[0], u32(len(fb)))
		}
	}

	for i := 0; i < vertex_info.UniformBufferCount; i += 1 {
		uniform := material_stage_get_uniform_buffer(&command.Material.Vertex, i)
		when ODIN_OS == .JS {
			// M1 决策: 逐 draw 设 uniform(非 UBO)。顶点 slot0 = 64 字节列主序 mat4
			if len(uniform) >= 64 {
				fw_set_matrix4(0, u32(i), raw_data(uniform))
			} else {
				fw_set_matrix4(0, u32(i), raw_data(identity_matrix_4x4[:]))
			}
		} else {
			if len(uniform) > 0 {
				SDL.PushGPUVertexUniformData(
					graphics_device.CommandBuffer,
					u32(i),
					raw_data(uniform),
					u32(len(uniform)),
				)
			} else if i == 0 {
				SDL.PushGPUVertexUniformData(
					graphics_device.CommandBuffer,
					u32(i),
					raw_data(identity_matrix_4x4[:]),
					64,
				)
			}
		}
	}

	for i := 0; i < fragment_info.UniformBufferCount; i += 1 {
		uniform := material_stage_get_uniform_buffer(&command.Material.Fragment, i)
		when ODIN_OS == .JS {
			// M1: 已知着色器的片元 uniform 仅 Msdf 的 DistanceRange(4 字节 float)
			if len(uniform) >= 4 {
				bits :=
					u32(uniform[0]) |
					(u32(uniform[1]) << 8) |
					(u32(uniform[2]) << 16) |
					(u32(uniform[3]) << 24)
				fw_set_float(1, u32(i), transmute(f32)bits)
			}
		} else {
			if len(uniform) > 0 {
				SDL.PushGPUFragmentUniformData(
					graphics_device.CommandBuffer,
					u32(i),
					raw_data(uniform),
					u32(len(uniform)),
				)
			}
		}
	}

	when ODIN_OS == .JS {
		for i := 0; i < len(command.VertexBuffers); i += 1 {
			vb := command.VertexBuffers[i].Buffer
			fw_bind_vertex_buffer(u32(i), web_handle_u32(rawptr(vb.Base.Resource)), i32(vb.Stride))
			attr_offset := 0
			for element in vb.Format.Elements {
				normalized := u32(0)
				if element.Normalized {
					normalized = 1
				}
				fw_vertex_attribute(
					u32(element.Index),
					u32(i),
					web_vertex_type(element.Type),
					normalized,
					i32(vb.Stride),
					i32(attr_offset),
				)
				attr_offset += vertex_type_size_in_bytes(element.Type)
			}
		}
	} else {
		buffer_bindings := make(
			[]SDL.GPUBufferBinding,
			len(command.VertexBuffers),
			context.temp_allocator,
		)
		for i := 0; i < len(command.VertexBuffers); i += 1 {
			buffer_bindings[i] = SDL.GPUBufferBinding {
				buffer = command.VertexBuffers[i].Buffer.Base.Resource,
				offset = 0,
			}
		}
		SDL.BindGPUVertexBuffers(
			graphics_device.RenderPass,
			0,
			raw_data(buffer_bindings),
			u32(len(buffer_bindings)),
		)
	}

	if vertex_info.StorageBufferCount > 0 && len(command.VertexStorageBuffers) > 0 {
		when ODIN_OS == .JS {
			report_draw_failure(
				graphics_device,
				.InvalidStorageBuffer,
				"vertex storage buffers are not supported on web (M1)",
			)
			return
		}
		storage_count := Min(len(command.VertexStorageBuffers), vertex_info.StorageBufferCount)
		buffers := make([]^SDL.GPUBuffer, storage_count, context.temp_allocator)
		for i := 0; i < storage_count; i += 1 {
			sb := command.VertexStorageBuffers[i]
			if sb == nil || sb.Base.Resource == nil {
				report_draw_failure(
					graphics_device,
					.InvalidStorageBuffer,
					"draw storage buffer has no GPU resource",
				)
				return
			}
			buffers[i] = sb.Base.Resource
		}
		SDL.BindGPUVertexStorageBuffers(
			graphics_device.RenderPass,
			0,
			raw_data(buffers),
			u32(len(buffers)),
		)
	}

	if fragment_info.StorageBufferCount > 0 && len(command.FragmentStorageBuffers) > 0 {
		when ODIN_OS == .JS {
			report_draw_failure(
				graphics_device,
				.InvalidStorageBuffer,
				"fragment storage buffers are not supported on web (M1)",
			)
			return
		}
		storage_count := Min(len(command.FragmentStorageBuffers), fragment_info.StorageBufferCount)
		buffers := make([]^SDL.GPUBuffer, storage_count, context.temp_allocator)
		for i := 0; i < storage_count; i += 1 {
			sb := command.FragmentStorageBuffers[i]
			if sb == nil || sb.Base.Resource == nil {
				report_draw_failure(
					graphics_device,
					.InvalidStorageBuffer,
					"draw storage buffer has no GPU resource",
				)
				return
			}
			buffers[i] = sb.Base.Resource
		}
		SDL.BindGPUFragmentStorageBuffers(
			graphics_device.RenderPass,
			0,
			raw_data(buffers),
			u32(len(buffers)),
		)
	}

	if command.IndexBuffer != nil &&
	   command.IndexBuffer.Base.Resource != nil &&
	   command.IndexCount > 0 {
		when ODIN_OS == .JS {
			fw_bind_index_buffer(web_handle_u32(rawptr(command.IndexBuffer.Base.Resource)))
			graphics_device.RenderPassIndexBuffer = command.IndexBuffer.Base.Resource
			byte_offset :=
				i32(command.IndexOffset) * web_index_type_size(command.IndexBuffer.Format)
			fw_draw_elements(
				i32(command.IndexCount),
				web_index_type(command.IndexBuffer.Format),
				byte_offset,
				i32(Max(command.InstanceCount, 1)),
			)
		} else {
			index_binding := SDL.GPUBufferBinding {
				buffer = command.IndexBuffer.Base.Resource,
				offset = u32(command.IndexOffset * command.IndexBuffer.Base.ElementSizeInBytes),
			}
			SDL.BindGPUIndexBuffer(
				graphics_device.RenderPass,
				index_binding,
				index_format_to_sdl(command.IndexBuffer.Format),
			)
			graphics_device.RenderPassIndexBuffer = command.IndexBuffer.Base.Resource
			SDL.DrawGPUIndexedPrimitives(
				graphics_device.RenderPass,
				u32(command.IndexCount),
				u32(Max(command.InstanceCount, 1)),
				0,
				i32(command.VertexOffset),
				0,
			)
		}
	} else if command.VertexCount > 0 {
		when ODIN_OS == .JS {
			fw_draw_arrays(
				i32(command.VertexCount),
				i32(command.VertexOffset),
				i32(Max(command.InstanceCount, 1)),
			)
		} else {
			SDL.DrawGPUPrimitives(
				graphics_device.RenderPass,
				u32(command.VertexCount),
				u32(Max(command.InstanceCount, 1)),
				u32(command.VertexOffset),
				0,
			)
		}
	}
}

GraphicsDeviceDraw :: graphics_device_draw

graphics_device_is_texture_format_supported :: proc(
	device: ^GraphicsDevice,
	format: TextureFormat,
) -> bool {
	if device == nil || device.Device == nil {
		return false
	}
	when ODIN_OS == .JS {
		return fw_gl_texture_supported(u32(format))
	}
	usage: SDL.GPUTextureUsageFlags = {.SAMPLER}
	if texture_format_is_color_format(format) {
		usage += {.COLOR_TARGET}
	} else {
		usage += {.DEPTH_STENCIL_TARGET}
	}
	return SDL.GPUTextureSupportsFormat(device.Device, texture_format_to_sdl(format), .D2, usage)
}

graphics_device_is_texture_multisample_supported :: proc(
	device: ^GraphicsDevice,
	format: TextureFormat,
	samples: SampleCount,
) -> bool {
	if device == nil || device.Device == nil {
		return false
	}
	when ODIN_OS == .JS {
		return samples == .One && fw_gl_texture_supported(u32(format))
	}
	return SDL.GPUTextureSupportsSampleCount(
		device.Device,
		texture_format_to_sdl(format),
		sample_count_to_sdl(samples),
	)
}

graphics_device_resource_handle :: proc(device: ^GraphicsDevice) -> rawptr {
	if device == nil {
		return nil
	}
	return rawptr(device.Device)
}

graphics_device_origin_bottom_left :: proc(device: ^GraphicsDevice) -> bool {
	_ = device
	return false
}
GraphicsDeviceIsTextureFormatSupported :: graphics_device_is_texture_format_supported
GraphicsDeviceIsTextureMultiSampleSupported :: graphics_device_is_texture_multisample_supported
GraphicsDeviceResourceHandle :: graphics_device_resource_handle
GraphicsDeviceOriginBottomLeft :: graphics_device_origin_bottom_left

graphics_device_clear_mask :: proc(
	graphics_device: ^GraphicsDevice,
	target: DrawableTarget,
	colors: []Color,
	depth: f32,
	stencil: int,
	mask: ClearMask,
) {
	if graphics_device == nil || !graphics_device.InFrame {
		return
	}
	mask_bits := u8(mask)
	if mask_bits == 0 {
		return
	}
	clear_colors: []Color = nil
	if (mask_bits & u8(ClearMask.Color)) != 0 {
		clear_colors = colors
	}
	clear_depth := (mask_bits & u8(ClearMask.Depth)) != 0
	clear_stencil := (mask_bits & u8(ClearMask.Stencil)) != 0
	_ = begin_render_pass_ex(
		graphics_device,
		target,
		clear_colors,
		clear_depth,
		depth,
		clear_stencil,
		stencil,
	)
}

graphics_device_clear_color :: proc(
	graphics_device: ^GraphicsDevice,
	target: DrawableTarget,
	color: Color,
) {
	colors := [1]Color{color}
	graphics_device_clear_mask(graphics_device, target, colors[:], 0, 0, .Color)
}

GraphicsDeviceClear :: proc {
	graphics_device_clear_color,
	graphics_device_clear_mask,
}

// ==============================================================================
// Graphics / Defaults / Materials — 默认材质
// ==============================================================================

init_default_batch_material :: proc(
	material: ^Material,
	vertex_shader: ^Shader,
	fragment_shader: ^Shader,
	graphics_device: ^GraphicsDevice,
) {
	vertex_code: []u8 = nil
	fragment_code: []u8 = nil
	when ODIN_OS == .JS {
		vertex_code = batcher_vertex_glsl
		fragment_code = batcher_fragment_glsl
	} else {
		#partial switch graphics_device.Driver {
		case .Private, .Vulkan:
			vertex_code = batcher_vertex_spv
			fragment_code = batcher_fragment_spv
		case .D3D12:
			vertex_code = batcher_vertex_dxil
			fragment_code = batcher_fragment_dxil
		case .Metal:
			vertex_code = batcher_vertex_msl
			fragment_code = batcher_fragment_msl
		case .None:
		}
	}

	vertex_info := ShaderCreateInfo {
		Stage              = .Vertex,
		Code               = vertex_code,
		SamplerCount       = 0,
		UniformBufferCount = 1,
		StorageBufferCount = 0,
		EntryPoint         = "vertex_main",
	}
	fragment_info := ShaderCreateInfo {
		Stage              = .Fragment,
		Code               = fragment_code,
		SamplerCount       = 1,
		UniformBufferCount = 0,
		StorageBufferCount = 0,
		EntryPoint         = "fragment_main",
	}

	shader_init(vertex_shader, graphics_device, vertex_info, "BatcherVertex")
	shader_init(fragment_shader, graphics_device, fragment_info, "BatcherFragment")
	material_init_with_shaders(material, vertex_shader, fragment_shader)
}

InitDefaultBatchMaterial :: init_default_batch_material

init_default_textured_material :: proc(
	material: ^Material,
	vertex_shader: ^Shader,
	fragment_shader: ^Shader,
	graphics_device: ^GraphicsDevice,
) {
	vertex_code: []u8 = nil
	fragment_code: []u8 = nil
	when ODIN_OS == .JS {
		vertex_code = textured_vertex_glsl
		fragment_code = textured_fragment_glsl
	} else {
		#partial switch graphics_device.Driver {
		case .Private, .Vulkan:
			vertex_code = textured_vertex_spv
			fragment_code = textured_fragment_spv
		case .D3D12:
			vertex_code = textured_vertex_dxil
			fragment_code = textured_fragment_dxil
		case .Metal:
			vertex_code = textured_vertex_msl
			fragment_code = textured_fragment_msl
		case .None:
		}
	}
	shader_init(vertex_shader, graphics_device, ShaderCreateInfo {
			Stage              = .Vertex,
			Code               = vertex_code,
			SamplerCount       = 0,
			UniformBufferCount = 1,
			StorageBufferCount = 0,
			EntryPoint         = "vertex_main",
		}, "TexturedVertex")
	shader_init(fragment_shader, graphics_device, ShaderCreateInfo {
			Stage              = .Fragment,
			Code               = fragment_code,
			SamplerCount       = 1,
			UniformBufferCount = 0,
			StorageBufferCount = 0,
			EntryPoint         = "fragment_main",
		}, "TexturedFragment")
	material_init_with_shaders(material, vertex_shader, fragment_shader)
}

init_default_msdf_material :: proc(
	material: ^Material,
	vertex_shader: ^Shader,
	fragment_shader: ^Shader,
	graphics_device: ^GraphicsDevice,
) {
	vertex_code: []u8 = nil
	fragment_code: []u8 = nil
	when ODIN_OS == .JS {
		vertex_code = msdf_vertex_glsl
		fragment_code = msdf_fragment_glsl
	} else {
		#partial switch graphics_device.Driver {
		case .Private, .Vulkan:
			vertex_code = msdf_vertex_spv
			fragment_code = msdf_fragment_spv
		case .D3D12:
			vertex_code = msdf_vertex_dxil
			fragment_code = msdf_fragment_dxil
		case .Metal:
			vertex_code = msdf_vertex_msl
			fragment_code = msdf_fragment_msl
		case .None:
		}
	}
	shader_init(vertex_shader, graphics_device, ShaderCreateInfo {
			Stage              = .Vertex,
			Code               = vertex_code,
			SamplerCount       = 0,
			UniformBufferCount = 1,
			StorageBufferCount = 0,
			EntryPoint         = "vertex_main",
		}, "MsdfVertex")
	shader_init(fragment_shader, graphics_device, ShaderCreateInfo {
			Stage              = .Fragment,
			Code               = fragment_code,
			SamplerCount       = 1,
			UniformBufferCount = 1,
			StorageBufferCount = 0,
			EntryPoint         = "fragment_main",
		}, "MsdfFragment")
	material_init_with_shaders(material, vertex_shader, fragment_shader)
}

InitDefaultTexturedMaterial :: init_default_textured_material
InitDefaultMsdfMaterial :: init_default_msdf_material

// ==============================================================================
// Graphics / IGraphicResource — 资源操作
// ==============================================================================

GraphicResource :: enum {
	None,
	Texture,
	Shader,
	Buffer,
	Sampler,
	Pipeline,
}

graphics_device_destroy_resource :: proc(
	graphics_device: ^GraphicsDevice,
	kind: GraphicResource,
	resource: rawptr,
) {
	if graphics_device == nil || graphics_device.Device == nil || resource == nil {
		return
	}

	when ODIN_OS == .JS {
		handle := web_handle_u32(resource)
		switch kind {
		case .Texture:
			fw_gl_release_texture(handle)
		case .Shader:
			fw_gl_release_shader(handle)
		case .Buffer:
			fw_gl_release_buffer(handle)
		case .Sampler:
			fw_gl_release_sampler(handle)
		case .Pipeline:
			fw_gl_release_pipeline(handle)
		case .None:
		}
		return
	}

	device := graphics_device.Device

	#partial switch kind {
	case .Texture:
		SDL.ReleaseGPUTexture(device, cast(^SDL.GPUTexture)resource)
	case .Shader:
		SDL.ReleaseGPUShader(device, cast(^SDL.GPUShader)resource)
	case .Buffer:
		SDL.ReleaseGPUBuffer(device, cast(^SDL.GPUBuffer)resource)
	case .Sampler:
		SDL.ReleaseGPUSampler(device, cast(^SDL.GPUSampler)resource)
	case .Pipeline:
		SDL.ReleaseGPUGraphicsPipeline(device, cast(^SDL.GPUGraphicsPipeline)resource)
	case .None:
	}
}

GraphicsDeviceDestroyResource :: graphics_device_destroy_resource

graphics_device_upload_to_buffer :: proc(
	graphics_device: ^GraphicsDevice,
	buffer: ^SDL.GPUBuffer,
	data: rawptr,
	data_size: u32,
	dest_offset: u32,
) {
	if graphics_device == nil ||
	   graphics_device.Device == nil ||
	   buffer == nil ||
	   data == nil ||
	   data_size == 0 {
		return
	}

	when ODIN_OS == .JS {
		// Web: 立即式 bufferSubData(句柄表记录缓冲类型)
		fw_gl_upload_buffer(web_handle_u32(rawptr(buffer)), data, i32(data_size), i32(dest_offset))
		return
	}

	device := graphics_device.Device

	// 帧内快速路径: 把上传记录进本帧命令缓冲的暂存缓冲分区 (免每帧创建/销毁与 GPU 空等)
	if graphics_device.CommandBuffer != nil && graphics_device.RenderPass == nil {
		cursor := graphics_device.UploadStagingCursor
		required := data_size
		need_total := cursor + required
		if graphics_device.UploadStaging == nil || graphics_device.UploadStagingSize < need_total {
			if graphics_device.UploadStaging != nil {
				SDL.ReleaseGPUTransferBuffer(device, graphics_device.UploadStaging)
				graphics_device.UploadStaging = nil
			}
			next := graphics_device.UploadStagingSize
			if next <= 0 {
				next = 1 << 20
			}
			for next < need_total {
				next *= 2
			}
			transfer_info := SDL.GPUTransferBufferCreateInfo {
				usage = .UPLOAD,
				size  = next,
				props = 0,
			}
			transfer := SDL.CreateGPUTransferBuffer(device, transfer_info)
			if transfer == nil {
				panic(create_error_from_sdl("SDL_CreateGPUTransferBuffer"))
			}
			graphics_device.UploadStaging = transfer
			graphics_device.UploadStagingSize = next
		}
		transfer := graphics_device.UploadStaging
		mapped := SDL.MapGPUTransferBuffer(device, transfer, false)
		if mapped == nil {
			panic(create_error_from_sdl("SDL_MapGPUTransferBuffer"))
		}
		dst := ([^]byte)(mapped)
		mem.copy(raw_data(dst[cursor:int(cursor) + int(required)]), data, int(data_size))
		SDL.UnmapGPUTransferBuffer(device, transfer)
		copy_pass := SDL.BeginGPUCopyPass(graphics_device.CommandBuffer)
		if copy_pass == nil {
			return
		}
		upload_src := SDL.GPUTransferBufferLocation {
			transfer_buffer = transfer,
			offset          = cursor,
		}
		upload_dst := SDL.GPUBufferRegion {
			buffer = buffer,
			offset = dest_offset,
			size   = data_size,
		}
		SDL.UploadToGPUBuffer(copy_pass, upload_src, upload_dst, false)
		SDL.EndGPUCopyPass(copy_pass)
		graphics_device.UploadStagingCursor = cursor + required
		return
	}

	// 帧外回退路径: 独立命令缓冲 + 上传后等待完成
	transfer_size := u32(256) + data_size
	transfer_info := SDL.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size  = transfer_size,
		props = 0,
	}
	transfer := SDL.CreateGPUTransferBuffer(device, transfer_info)
	if transfer == nil {
		panic(create_error_from_sdl("SDL_CreateGPUTransferBuffer"))
	}
	defer SDL.ReleaseGPUTransferBuffer(device, transfer)

	mapped := SDL.MapGPUTransferBuffer(device, transfer, false)
	if mapped == nil {
		panic(create_error_from_sdl("SDL_MapGPUTransferBuffer"))
	}
	mem.copy(mapped, data, int(data_size))
	SDL.UnmapGPUTransferBuffer(device, transfer)

	command_buffer := SDL.AcquireGPUCommandBuffer(device)
	if command_buffer == nil {
		return
	}

	copy_pass := SDL.BeginGPUCopyPass(command_buffer)
	if copy_pass == nil {
		_ = SDL.CancelGPUCommandBuffer(command_buffer)
		return
	}

	upload_src := SDL.GPUTransferBufferLocation {
		transfer_buffer = transfer,
		offset          = 0,
	}
	upload_dst := SDL.GPUBufferRegion {
		buffer = buffer,
		offset = dest_offset,
		size   = data_size,
	}
	SDL.UploadToGPUBuffer(copy_pass, upload_src, upload_dst, false)

	SDL.EndGPUCopyPass(copy_pass)
	if !SDL.SubmitGPUCommandBuffer(command_buffer) {
		panic(create_error_from_sdl("SDL_SubmitGPUCommandBuffer"))
	}
	_ = SDL.WaitForGPUIdle(device)
}

GraphicsDeviceUploadToBuffer :: graphics_device_upload_to_buffer

// ==============================================================================
// Graphics / Texture — 创建、上传、读回与复制
// ==============================================================================

Texture :: struct {
	GraphicsDevice:     ^GraphicsDevice,
	Name:               string,
	Width:              int,
	Height:             int,
	Format:             TextureFormat,
	SampleCount:        SampleCount,
	IsTargetAttachment: bool,
	Resource:           ^SDL.GPUTexture,
	ResolveResource:    ^SDL.GPUTexture,
	Pixels:             [dynamic]u8,
	Flags:              TextureFlags,
	Disposed:           bool,
}

texture_memory_size :: proc(tex: ^Texture) -> int {
	if tex == nil {
		return 0
	}
	return tex.Width * tex.Height * texture_format_size(tex.Format)
}

TextureMemorySize :: texture_memory_size

texture_init_ex :: proc(
	tex: ^Texture,
	graphics_device: ^GraphicsDevice,
	width, height: int,
	format: TextureFormat,
	sample_count: SampleCount,
	usage: SDL.GPUTextureUsageFlags,
	is_target_attachment: bool,
	name: string = "",
) {
	if width <= 0 || height <= 0 {
		panic("Texture must have a size larger than 0")
	}
	if graphics_device == nil || graphics_device.Device == nil {
		panic("GraphicsDevice is nil")
	}

	when ODIN_OS == .JS {
		if sample_count != .One {
			panic("WebGL2 texture attachments currently require SampleCount.One")
		}
		handle := fw_gl_create_texture(i32(width), i32(height), u32(format))
		if handle == 0 {
			panic("foster_web: create_texture failed")
		}
		tex.GraphicsDevice = graphics_device
		tex.Name = name
		tex.Width = width
		tex.Height = height
		tex.Format = format
		tex.SampleCount = sample_count
		tex.IsTargetAttachment = is_target_attachment
		tex.Resource = cast(^SDL.GPUTexture)(web_handle_ptr(handle))
		tex.ResolveResource = nil
		tex.Flags = TextureFlags{}
		delete(tex.Pixels)
		tex.Pixels = nil
		resize(&tex.Pixels, width * height * texture_format_size(format))
		tex.Disposed = false
		return
	}

	sdl_format := texture_format_to_sdl(format)
	info := SDL.GPUTextureCreateInfo {
		type                 = .D2,
		format               = sdl_format,
		usage                = usage,
		width                = u32(width),
		height               = u32(height),
		layer_count_or_depth = 1,
		num_levels           = 1,
		sample_count         = sample_count_to_sdl(sample_count),
		props                = 0,
	}

	resource := SDL.CreateGPUTexture(graphics_device.Device, info)
	if resource == nil {
		panic(create_error_from_sdl("SDL_CreateGPUTexture"))
	}

	resolve_resource: ^SDL.GPUTexture = nil
	if is_target_attachment && sample_count != .One && texture_format_is_color_format(format) {
		resolve_info := SDL.GPUTextureCreateInfo {
			type                 = .D2,
			format               = sdl_format,
			usage                = SDL.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET},
			width                = u32(width),
			height               = u32(height),
			layer_count_or_depth = 1,
			num_levels           = 1,
			sample_count         = ._1,
			props                = 0,
		}
		resolve_resource = SDL.CreateGPUTexture(graphics_device.Device, resolve_info)
		if resolve_resource == nil {
			SDL.ReleaseGPUTexture(graphics_device.Device, resource)
			panic(create_error_from_sdl("SDL_CreateGPUTexture", "resolve"))
		}
	}

	tex.GraphicsDevice = graphics_device
	tex.Name = name
	tex.Width = width
	tex.Height = height
	tex.Format = format
	tex.SampleCount = sample_count
	tex.IsTargetAttachment = is_target_attachment
	tex.Resource = resource
	tex.ResolveResource = resolve_resource
	tex.Flags = TextureFlags{}
	delete(tex.Pixels)
	tex.Pixels = nil
	resize(&tex.Pixels, width * height * texture_format_size(format))
	tex.Disposed = false
}

texture_init :: proc(
	tex: ^Texture,
	graphics_device: ^GraphicsDevice,
	width, height: int,
	format: TextureFormat = .Color,
	name: string = "",
) {
	texture_init_ex(
		tex,
		graphics_device,
		width,
		height,
		format,
		.One,
		SDL.GPUTextureUsageFlags{.SAMPLER},
		false,
		name,
	)
}

texture_init_flags :: proc(
	tex: ^Texture,
	graphics_device: ^GraphicsDevice,
	width, height: int,
	format: TextureFormat,
	flags: TextureFlags,
	name: string = "",
) {
	usage := SDL.GPUTextureUsageFlags{.SAMPLER}
	if .ComputeRead in flags {
		usage += {.COMPUTE_STORAGE_READ}
	}
	if .ComputeWrite in flags {
		usage += {.COMPUTE_STORAGE_WRITE}
	}
	texture_init_ex(tex, graphics_device, width, height, format, .One, usage, false, name)
	tex.Flags = flags
}

texture_dispose :: proc(tex: ^Texture) {
	if tex == nil || tex.Disposed {
		return
	}
	if tex.GraphicsDevice != nil &&
	   tex.GraphicsDevice.Device != nil &&
	   tex.Resource != nil &&
	   !tex.IsTargetAttachment {
		when ODIN_OS == .JS {
			fw_gl_release_texture(web_handle_u32(rawptr(tex.Resource)))
		} else {
			SDL.ReleaseGPUTexture(tex.GraphicsDevice.Device, tex.Resource)
		}
	}
	if tex.GraphicsDevice != nil &&
	   tex.GraphicsDevice.Device != nil &&
	   tex.ResolveResource != nil {
		when ODIN_OS == .JS {
			fw_gl_release_texture(web_handle_u32(rawptr(tex.ResolveResource)))
		} else {
			SDL.ReleaseGPUTexture(tex.GraphicsDevice.Device, tex.ResolveResource)
		}
	}
	tex.Resource = nil
	tex.ResolveResource = nil
	delete(tex.Pixels)
	tex.Pixels = nil
	tex.Disposed = true
}

texture_sample_resource :: proc(tex: ^Texture) -> ^SDL.GPUTexture {
	if tex == nil {
		return nil
	}
	if tex.ResolveResource != nil {
		return tex.ResolveResource
	}
	return tex.Resource
}

// Data contains native texel bits, not converted RGBA8 colors: float formats
// use f16/f32 components, and R11G11B10_UFLOAT uses packed unsigned float bits.

texture_set_data :: proc(tex: ^Texture, data: rawptr, length: int) {
	if tex == nil ||
	   tex.Disposed ||
	   tex.GraphicsDevice == nil ||
	   tex.GraphicsDevice.Device == nil ||
	   tex.Resource == nil {
		panic("Resource is Disposed")
	}

	mem_size := texture_memory_size(tex)
	if length < mem_size {
		panic("Data Buffer is smaller than the Size of the Texture")
	}

	when ODIN_OS == .JS {
		if mem_size > 0 {
			fw_gl_upload_texture(
				web_handle_u32(rawptr(tex.Resource)),
				i32(tex.Width),
				i32(tex.Height),
				data,
				i32(mem_size),
			)
			mem.copy(raw_data(tex.Pixels[:]), data, mem_size)
		}
		return
	}

	device := tex.GraphicsDevice.Device

	transfer_size := u32(256) + u32(mem_size)
	transfer_info := SDL.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size  = transfer_size,
		props = 0,
	}
	transfer := SDL.CreateGPUTransferBuffer(device, transfer_info)
	if transfer == nil {
		panic(create_error_from_sdl("SDL_CreateGPUTransferBuffer"))
	}
	defer SDL.ReleaseGPUTransferBuffer(device, transfer)

	mapped := SDL.MapGPUTransferBuffer(device, transfer, false)
	if mapped == nil {
		panic(create_error_from_sdl("SDL_MapGPUTransferBuffer"))
	}
	mem.copy(mapped, data, mem_size)
	if mem_size > 0 {
		mem.copy(raw_data(tex.Pixels[:]), data, mem_size)
	}
	SDL.UnmapGPUTransferBuffer(device, transfer)

	command_buffer := SDL.AcquireGPUCommandBuffer(device)
	if command_buffer == nil {
		return
	}

	copy_pass := SDL.BeginGPUCopyPass(command_buffer)
	if copy_pass == nil {
		_ = SDL.CancelGPUCommandBuffer(command_buffer)
		return
	}

	src := SDL.GPUTextureTransferInfo {
		transfer_buffer = transfer,
		offset          = 0,
		pixels_per_row  = u32(tex.Width),
		rows_per_layer  = u32(tex.Height),
	}
	dst := SDL.GPUTextureRegion {
		texture   = tex.Resource,
		mip_level = 0,
		layer     = 0,
		x         = 0,
		y         = 0,
		z         = 0,
		w         = u32(tex.Width),
		h         = u32(tex.Height),
		d         = 1,
	}
	SDL.UploadToGPUTexture(copy_pass, src, dst, false)

	SDL.EndGPUCopyPass(copy_pass)
	if !SDL.SubmitGPUCommandBuffer(command_buffer) {
		panic(create_error_from_sdl("SDL_SubmitGPUCommandBuffer"))
	}
	_ = SDL.WaitForGPUIdle(device)
}

TextureInit :: texture_init
TextureInitEx :: texture_init_ex
TextureInitFlags :: texture_init_flags
TextureDispose :: texture_dispose
TextureSetData :: texture_set_data
TextureSampleResource :: texture_sample_resource

// Returns native texel bits in the texture's format; the caller decodes them.

texture_download_data :: proc(tex: ^Texture, allocator := context.allocator) -> []byte {
	if tex == nil ||
	   tex.Disposed ||
	   tex.GraphicsDevice == nil ||
	   tex.GraphicsDevice.Device == nil ||
	   tex.Resource == nil {
		return nil
	}
	when ODIN_OS == .JS {
		web_result := make([]byte, texture_memory_size(tex), allocator)
		if !fw_gl_download_texture(
			web_handle_u32(rawptr(texture_sample_resource(tex))),
			raw_data(web_result),
			i32(len(web_result)),
		) {
			delete(web_result)
			return nil
		}
		return web_result
	}
	mem_size := texture_memory_size(tex)
	if mem_size <= 0 {
		return nil
	}
	transfer := SDL.CreateGPUTransferBuffer(
		tex.GraphicsDevice.Device,
		SDL.GPUTransferBufferCreateInfo{usage = .DOWNLOAD, size = u32(mem_size), props = 0},
	)
	if transfer == nil {
		return nil
	}
	defer SDL.ReleaseGPUTransferBuffer(tex.GraphicsDevice.Device, transfer)
	command_buffer := SDL.AcquireGPUCommandBuffer(tex.GraphicsDevice.Device)
	if command_buffer == nil {
		return nil
	}
	copy_pass := SDL.BeginGPUCopyPass(command_buffer)
	if copy_pass == nil {
		_ = SDL.CancelGPUCommandBuffer(command_buffer)
		return nil
	}
	SDL.DownloadFromGPUTexture(copy_pass, SDL.GPUTextureRegion {
		texture   = texture_sample_resource(tex),
		mip_level = 0,
		layer     = 0,
		x         = 0,
		y         = 0,
		z         = 0,
		w         = u32(tex.Width),
		h         = u32(tex.Height),
		d         = 1,
	}, SDL.GPUTextureTransferInfo {
		transfer_buffer = transfer,
		offset          = 0,
		pixels_per_row  = u32(tex.Width),
		rows_per_layer  = u32(tex.Height),
	})
	SDL.EndGPUCopyPass(copy_pass)
	if !SDL.SubmitGPUCommandBuffer(command_buffer) {
		return nil
	}
	if !SDL.WaitForGPUIdle(tex.GraphicsDevice.Device) {
		return nil
	}
	// Read the completed download, preserving the transfer buffer's contents.
	mapped := SDL.MapGPUTransferBuffer(tex.GraphicsDevice.Device, transfer, false)
	if mapped == nil {
		return nil
	}
	result := make([]byte, mem_size, allocator)
	mem.copy(raw_data(result), mapped, mem_size)
	SDL.UnmapGPUTransferBuffer(tex.GraphicsDevice.Device, transfer)
	return result
}

texture_get_data :: proc(tex: ^Texture, allocator := context.allocator) -> []byte {
	if tex == nil || tex.Disposed {
		return nil
	}
	if tex.GraphicsDevice != nil && tex.GraphicsDevice.Device != nil && tex.Resource != nil {
		if data := texture_download_data(tex, allocator); data != nil {
			return data
		}
	}
	result := make([]byte, len(tex.Pixels), allocator)
	copy(result, tex.Pixels[:])
	return result
}

texture_set_data_region :: proc(tex: ^Texture, data: []u8, x, y, width, height: int) {
	if tex == nil || tex.Disposed || x < 0 || y < 0 || width <= 0 || height <= 0 {
		return
	}
	if x + width > tex.Width || y + height > tex.Height {
		return
	}
	bpp := texture_format_size(tex.Format)
	if len(data) < width * height * bpp {
		return
	}
	for row := 0; row < height; row += 1 {
		src := row * width * bpp
		dst := ((y + row) * tex.Width + x) * bpp
		mem.copy(raw_data(tex.Pixels[dst:]), raw_data(data[src:]), width * bpp)
	}
	when ODIN_OS == .JS {
		fw_gl_upload_texture_region(
			web_handle_u32(rawptr(tex.Resource)),
			i32(x),
			i32(y),
			i32(width),
			i32(height),
			raw_data(data),
			i32(width * height * bpp),
		)
		return
	}
	device := tex.GraphicsDevice
	if device == nil || device.Device == nil || tex.Resource == nil {
		return
	}
	end_render_pass(device)
	transfer := SDL.CreateGPUTransferBuffer(
		device.Device,
		{usage = .UPLOAD, size = u32(width * height * bpp)},
	)
	if transfer == nil {
		return
	}
	defer SDL.ReleaseGPUTransferBuffer(device.Device, transfer)
	mapped := SDL.MapGPUTransferBuffer(device.Device, transfer, false)
	if mapped == nil {
		return
	}
	mem.copy(mapped, raw_data(data), width * height * bpp)
	SDL.UnmapGPUTransferBuffer(device.Device, transfer)
	cb := device.CommandBuffer
	owned := cb == nil
	if owned {
		cb = SDL.AcquireGPUCommandBuffer(device.Device)
	}
	if cb == nil {
		return
	}
	pass := SDL.BeginGPUCopyPass(cb)
	if pass == nil {
		if owned {
			_ = SDL.CancelGPUCommandBuffer(cb)
		}
		return
	}
	SDL.UploadToGPUTexture(
		pass,
		{transfer_buffer = transfer, pixels_per_row = u32(width), rows_per_layer = u32(height)},
		{texture = tex.Resource, x = u32(x), y = u32(y), w = u32(width), h = u32(height), d = 1},
		false,
	)
	SDL.EndGPUCopyPass(pass)
	if owned {
		_ = SDL.SubmitGPUCommandBuffer(cb)
	}
}

texture_set_data_region_rect :: proc(tex: ^Texture, data: []u8, region: RectInt) {
	texture_set_data_region(tex, data, region.X, region.Y, region.Width, region.Height)
}

texture_clone :: proc(tex: ^Texture, name: string = "") -> Texture {
	result: Texture
	if tex == nil || tex.Disposed || tex.GraphicsDevice == nil {
		return result
	}
	usage := SDL.GPUTextureUsageFlags{.SAMPLER}
	if .ComputeRead in tex.Flags {
		usage += {.COMPUTE_STORAGE_READ}
	}
	if .ComputeWrite in tex.Flags {
		usage += {.COMPUTE_STORAGE_WRITE}
	}
	texture_init_ex(
		&result,
		tex.GraphicsDevice,
		tex.Width,
		tex.Height,
		tex.Format,
		.One,
		usage,
		false,
		name,
	)
	result.Flags = tex.Flags
	texture_blit(
		tex,
		&result,
		RectInt{0, 0, tex.Width, tex.Height},
		RectInt{0, 0, tex.Width, tex.Height},
	)
	return result
}

texture_blit :: proc(
	source, destination: ^Texture,
	source_rect, destination_rect: RectInt,
	filter: TextureFilter = .Nearest,
) {
	if source == nil || destination == nil || source.Disposed || destination.Disposed {
		return
	}
	bpp := texture_format_size(source.Format)
	if bpp != texture_format_size(destination.Format) ||
	   source_rect.Width <= 0 ||
	   source_rect.Height <= 0 {
		return
	}
	if source_rect.X < 0 ||
	   source_rect.Y < 0 ||
	   source_rect.X + source_rect.Width > source.Width ||
	   source_rect.Y + source_rect.Height > source.Height {
		return
	}
	if destination_rect.X < 0 ||
	   destination_rect.Y < 0 ||
	   destination_rect.Width <= 0 ||
	   destination_rect.Height <= 0 ||
	   destination_rect.X + destination_rect.Width > destination.Width ||
	   destination_rect.Y + destination_rect.Height > destination.Height {
		return
	}
	if source == destination || source.GraphicsDevice != destination.GraphicsDevice {
		return
	}
	when ODIN_OS == .JS {
		end_render_pass(source.GraphicsDevice)
		fw_gl_blit_texture(
			web_handle_u32(rawptr(texture_sample_resource(source))),
			web_handle_u32(rawptr(texture_sample_resource(destination))),
			i32(source_rect.X),
			i32(source_rect.Y),
			i32(source_rect.Width),
			i32(source_rect.Height),
			i32(destination_rect.X),
			i32(destination_rect.Y),
			i32(destination_rect.Width),
			i32(destination_rect.Height),
			u32(filter),
		)
		return
	}
	if source.GraphicsDevice != nil &&
	   source.GraphicsDevice.Device != nil &&
	   source.Resource != nil &&
	   destination.Resource != nil {
		end_render_pass(source.GraphicsDevice)
		command_buffer := source.GraphicsDevice.CommandBuffer
		owned := command_buffer == nil
		if owned {
			command_buffer = SDL.AcquireGPUCommandBuffer(source.GraphicsDevice.Device)
		}
		if command_buffer != nil {
			if source_rect.Width == destination_rect.Width &&
			   source_rect.Height == destination_rect.Height &&
			   source.Format == destination.Format {
				pass := SDL.BeginGPUCopyPass(command_buffer)
				if pass == nil {
					if owned {
						_ = SDL.CancelGPUCommandBuffer(command_buffer)
					}
					return
				}
				SDL.CopyGPUTextureToTexture(pass, {
						texture = texture_sample_resource(source),
						x       = u32(source_rect.X),
						y       = u32(source_rect.Y),
					}, {
						texture = texture_sample_resource(destination),
						x       = u32(destination_rect.X),
						y       = u32(destination_rect.Y),
					}, u32(source_rect.Width), u32(source_rect.Height), 1, false)
				SDL.EndGPUCopyPass(pass)
			} else {
				// Blit destinations must support COLOR_TARGET, unlike a plain sampled
				// texture. Use a temporary target, then copy its result to the destination.
				temporary: Texture
				texture_init_ex(
					&temporary,
					source.GraphicsDevice,
					destination_rect.Width,
					destination_rect.Height,
					destination.Format,
					.One,
					{.SAMPLER, .COLOR_TARGET},
					false,
				)
				defer texture_dispose(&temporary)
				SDL.BlitGPUTexture(command_buffer, SDL.GPUBlitInfo {
					source = SDL.GPUBlitRegion {
						texture = texture_sample_resource(source),
						x       = u32(source_rect.X),
						y       = u32(source_rect.Y),
						w       = u32(source_rect.Width),
						h       = u32(source_rect.Height),
					},
					destination = SDL.GPUBlitRegion {
						texture = temporary.Resource,
						w       = u32(destination_rect.Width),
						h       = u32(destination_rect.Height),
					},
					load_op = .DONT_CARE,
					flip_mode = .NONE,
					filter = texture_filter_to_sdl(filter),
					cycle = false,
				})
				pass := SDL.BeginGPUCopyPass(command_buffer)
				if pass == nil {
					if owned {
						_ = SDL.CancelGPUCommandBuffer(command_buffer)
					}
					return
				}
				SDL.CopyGPUTextureToTexture(pass, {texture = temporary.Resource}, {
						texture = texture_sample_resource(destination),
						x       = u32(destination_rect.X),
						y       = u32(destination_rect.Y),
					}, u32(destination_rect.Width), u32(destination_rect.Height), 1, false)
				SDL.EndGPUCopyPass(pass)
			}
			if owned {
				_ = SDL.SubmitGPUCommandBuffer(command_buffer)
			}
		}
	}
}

TextureGetData :: texture_get_data
TextureDownloadData :: texture_download_data
TextureSetDataRegion :: texture_set_data_region
TextureSetDataRegionRect :: texture_set_data_region_rect
TextureClone :: texture_clone
TextureBlit :: texture_blit

// ==============================================================================
// Graphics / Shader — 创建、重建与释放
// ==============================================================================

Shader :: struct {
	GraphicsDevice:  ^GraphicsDevice,
	Stage:           ShaderStage,
	Name:            string,
	CreateInfo:      ShaderCreateInfo,
	Resource:        ^SDL.GPUShader,
	ComputeResource: ^SDL.GPUComputePipeline,
	PipelineHashes:  [dynamic]u64,
	Disposed:        bool,
}

shader_init :: proc(
	shader: ^Shader,
	graphics_device: ^GraphicsDevice,
	create_info: ShaderCreateInfo,
	name: string = "",
) {
	if graphics_device == nil || graphics_device.Device == nil {
		panic("GraphicsDevice is nil")
	}
	if len(create_info.Code) == 0 {
		panic("Shader code is empty")
	}
	entrypoint := create_info.EntryPoint
	if entrypoint == "" {
		entrypoint = "main"
	}

	when ODIN_OS == .JS {
		if create_info.Stage == .Compute {
			panic("foster_web: compute shaders are not supported on web (M1 非目标)")
		}
		stage := u32(1)
		if create_info.Stage == .Vertex {
			stage = 0
		}
		code := create_info.Code
		if len(code) == 0 || &code[0] == nil {
			panic("foster_web: shader code is empty")
		}
		handle := fw_gl_create_shader(stage, &code[0], i32(len(code)))
		if handle == 0 {
			panic("foster_web: GLSL shader compile failed (详见页面日志)")
		}
		shader.GraphicsDevice = graphics_device
		shader.Stage = create_info.Stage
		shader.Name = name
		shader.CreateInfo = create_info
		shader.Resource = cast(^SDL.GPUShader)(web_handle_ptr(handle))
		shader.ComputeResource = nil
		delete(shader.PipelineHashes)
		shader.PipelineHashes = nil
		shader.Disposed = false
		return
	}

	sdl_stage := shader_stage_to_sdl(create_info.Stage)

	format := SDL.GPU_SHADERFORMAT_INVALID
	#partial switch graphics_device.Driver {
	case .Private:
		format = {.PRIVATE}
	case .Vulkan:
		format = {.SPIRV}
	case .D3D12:
		format = {.DXIL}
	case .Metal:
		format = {.MSL}
	case .None:
	}

	info := SDL.GPUShaderCreateInfo {
		code_size            = uint(len(create_info.Code)),
		code                 = &create_info.Code[0],
		entrypoint           = to_cstring(entrypoint),
		format               = format,
		stage                = sdl_stage,
		num_samplers         = u32(create_info.SamplerCount),
		num_storage_textures = 0,
		num_storage_buffers  = u32(create_info.StorageBufferCount),
		num_uniform_buffers  = u32(create_info.UniformBufferCount),
		props                = 0,
	}
	if create_info.Stage == .Compute {
		compute_info := SDL.GPUComputePipelineCreateInfo {
			code_size                      = uint(len(create_info.Code)),
			code                           = &create_info.Code[0],
			entrypoint                     = to_cstring(entrypoint),
			format                         = format,
			num_samplers                   = u32(create_info.SamplerCount),
			num_readonly_storage_textures  = u32(create_info.ReadOnlyStorageTextureCount),
			num_readonly_storage_buffers   = u32(
				max(create_info.ReadOnlyStorageBufferCount, create_info.StorageBufferCount),
			),
			num_readwrite_storage_textures = u32(create_info.ReadWriteStorageTextureCount),
			num_readwrite_storage_buffers  = u32(create_info.ReadWriteStorageBufferCount),
			num_uniform_buffers            = u32(create_info.UniformBufferCount),
			threadcount_x                  = u32(max(1, create_info.ThreadCountX)),
			threadcount_y                  = u32(max(1, create_info.ThreadCountY)),
			threadcount_z                  = u32(max(1, create_info.ThreadCountZ)),
			props                          = 0,
		}
		compute_resource := SDL.CreateGPUComputePipeline(graphics_device.Device, compute_info)
		if compute_resource == nil {
			panic(create_error_from_sdl("SDL_CreateGPUComputePipeline"))
		}
		shader.GraphicsDevice = graphics_device
		shader.Stage = create_info.Stage
		shader.Name = name
		shader.CreateInfo = create_info
		shader.Resource = nil
		shader.ComputeResource = compute_resource
		delete(shader.PipelineHashes)
		shader.PipelineHashes = nil
		shader.Disposed = false
		return
	}

	res := SDL.CreateGPUShader(graphics_device.Device, info)
	if res == nil {
		panic(create_error_from_sdl("SDL_CreateGPUShader"))
	}

	shader.GraphicsDevice = graphics_device
	shader.Stage = create_info.Stage
	shader.Name = name
	shader.CreateInfo = create_info
	shader.Resource = res
	shader.ComputeResource = nil
	delete(shader.PipelineHashes)
	shader.PipelineHashes = nil
	shader.Disposed = false
}

shader_recreate :: proc(shader: ^Shader, create_info: ShaderCreateInfo) {
	if shader == nil ||
	   shader.Disposed ||
	   shader.GraphicsDevice == nil ||
	   shader.GraphicsDevice.Disposed {
		panic("Cannot recreate a disposed Shader")
	}
	if create_info.Stage != shader.Stage {
		panic("Cannot recreate the Shader with a different stage")
	}

	if shader.Resource != nil {
		graphics_device_release_pipeline_hashes(shader.GraphicsDevice, &shader.PipelineHashes)
		when ODIN_OS == .JS {
			fw_gl_release_shader(web_handle_u32(rawptr(shader.Resource)))
		} else {
			SDL.ReleaseGPUShader(shader.GraphicsDevice.Device, shader.Resource)
		}
		shader.Resource = nil
	}
	if shader.ComputeResource != nil {
		when ODIN_OS != .JS {
			SDL.ReleaseGPUComputePipeline(shader.GraphicsDevice.Device, shader.ComputeResource)
		}
		shader.ComputeResource = nil
	}
	shader_init(shader, shader.GraphicsDevice, create_info, shader.Name)
}

shader_dispose :: proc(shader: ^Shader) {
	if shader == nil || shader.Disposed {
		return
	}
	if shader.GraphicsDevice != nil &&
	   shader.GraphicsDevice.Device != nil &&
	   shader.Resource != nil {
		graphics_device_release_pipeline_hashes(shader.GraphicsDevice, &shader.PipelineHashes)
		when ODIN_OS == .JS {
			fw_gl_release_shader(web_handle_u32(rawptr(shader.Resource)))
		} else {
			SDL.ReleaseGPUShader(shader.GraphicsDevice.Device, shader.Resource)
		}
	}
	if shader.GraphicsDevice != nil &&
	   shader.GraphicsDevice.Device != nil &&
	   shader.ComputeResource != nil {
		when ODIN_OS != .JS {
			SDL.ReleaseGPUComputePipeline(shader.GraphicsDevice.Device, shader.ComputeResource)
		}
	}
	shader.Resource = nil
	shader.ComputeResource = nil
	delete(shader.PipelineHashes)
	shader.PipelineHashes = nil
	shader.Disposed = true
}

ShaderInit :: shader_init
ShaderRecreate :: shader_recreate
ShaderDispose :: shader_dispose

// ==============================================================================
// Graphics / GraphicsBuffer — 图形缓冲
// ==============================================================================

BufferType :: enum {
	Vertex,
	Index,
	Storage,
	Compute,
}

GraphicsBuffer :: struct {
	GraphicsDevice:     ^GraphicsDevice,
	Name:               string,
	ElementSizeInBytes: int,
	Count:              int,
	ByteSize:           int,
	Type:               BufferType,
	IndexFormat:        IndexFormat,
	Resource:           ^SDL.GPUBuffer,
	Disposed:           bool,
}

graphics_buffer_init :: proc(
	buf: ^GraphicsBuffer,
	graphics_device: ^GraphicsDevice,
	element_size_in_bytes: int,
	buffer_type: BufferType,
	index_format: IndexFormat = .Sixteen,
	name: string = "",
) {
	if graphics_device == nil || graphics_device.Device == nil {
		panic("GraphicsDevice is nil")
	}
	if element_size_in_bytes <= 0 {
		panic("ElementSizeInBytes must be > 0")
	}

	initial_size := element_size_in_bytes
	if initial_size < 256 {
		initial_size = 256
	}

	when ODIN_OS == .JS {
		type_code := u32(0)
		switch buffer_type {
		case .Vertex:
			type_code = 0
		case .Index:
			type_code = 1
		case .Storage, .Compute:
			type_code = 2
		}
		handle := fw_gl_create_buffer(type_code, i32(initial_size))
		if handle == 0 {
			panic("foster_web: create_buffer failed")
		}
		buf.GraphicsDevice = graphics_device
		buf.Name = name
		buf.ElementSizeInBytes = element_size_in_bytes
		buf.Count = 0
		buf.ByteSize = initial_size
		buf.Type = buffer_type
		buf.IndexFormat = index_format
		buf.Resource = cast(^SDL.GPUBuffer)(web_handle_ptr(handle))
		buf.Disposed = false
		return
	}

	usage: SDL.GPUBufferUsageFlags = {}
	#partial switch buffer_type {
	case .Vertex:
		usage = SDL.GPUBufferUsageFlags{.VERTEX}
	case .Index:
		usage = SDL.GPUBufferUsageFlags{.INDEX}
	case .Storage:
		usage = {.GRAPHICS_STORAGE_READ, .COMPUTE_STORAGE_READ}
	case .Compute:
		usage = {.GRAPHICS_STORAGE_READ, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE}
	}

	info := SDL.GPUBufferCreateInfo {
		usage = usage,
		size  = u32(initial_size),
		props = 0,
	}

	res := SDL.CreateGPUBuffer(graphics_device.Device, info)
	if res == nil {
		panic(create_error_from_sdl("SDL_CreateGPUBuffer"))
	}

	buf.GraphicsDevice = graphics_device
	buf.Name = name
	buf.ElementSizeInBytes = element_size_in_bytes
	buf.Count = 0
	buf.ByteSize = initial_size
	buf.Type = buffer_type
	buf.IndexFormat = index_format
	buf.Resource = res
	buf.Disposed = false
}

graphics_buffer_ensure_size :: proc(buf: ^GraphicsBuffer, required_bytes: int) {
	if buf == nil ||
	   buf.Disposed ||
	   buf.GraphicsDevice == nil ||
	   buf.GraphicsDevice.Device == nil {
		return
	}
	if required_bytes <= buf.ByteSize {
		return
	}

	next_size := buf.ByteSize
	if next_size <= 0 {
		next_size = 256
	}
	for next_size < required_bytes {
		next_size *= 2
	}

	when ODIN_OS == .JS {
		if buf.Resource != nil {
			fw_gl_release_buffer(web_handle_u32(rawptr(buf.Resource)))
			buf.Resource = nil
		}
		type_code := u32(0)
		switch buf.Type {
		case .Vertex:
			type_code = 0
		case .Index:
			type_code = 1
		case .Storage, .Compute:
			type_code = 2
		}
		handle := fw_gl_create_buffer(type_code, i32(next_size))
		if handle == 0 {
			panic("foster_web: create_buffer (resize) failed")
		}
		buf.Resource = cast(^SDL.GPUBuffer)(web_handle_ptr(handle))
		buf.ByteSize = next_size
		return
	}

	usage: SDL.GPUBufferUsageFlags = {}
	#partial switch buf.Type {
	case .Vertex:
		usage = SDL.GPUBufferUsageFlags{.VERTEX}
	case .Index:
		usage = SDL.GPUBufferUsageFlags{.INDEX}
	case .Storage:
		usage = {.GRAPHICS_STORAGE_READ, .COMPUTE_STORAGE_READ}
	case .Compute:
		usage = {.GRAPHICS_STORAGE_READ, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE}
	}

	if buf.Resource != nil {
		SDL.ReleaseGPUBuffer(buf.GraphicsDevice.Device, buf.Resource)
		buf.Resource = nil
	}

	info := SDL.GPUBufferCreateInfo {
		usage = usage,
		size  = u32(next_size),
		props = 0,
	}
	buf.Resource = SDL.CreateGPUBuffer(buf.GraphicsDevice.Device, info)
	if buf.Resource == nil {
		panic(create_error_from_sdl("SDL_CreateGPUBuffer"))
	}
	buf.ByteSize = next_size
}

graphics_buffer_upload :: proc(
	buf: ^GraphicsBuffer,
	data: rawptr,
	element_count: int,
	element_offset: int = 0,
) {
	if buf == nil ||
	   buf.Disposed ||
	   buf.GraphicsDevice == nil ||
	   buf.GraphicsDevice.Device == nil ||
	   buf.Resource == nil {
		panic("Trying to upload to a disposed DrawBuffer")
	}

	if element_count <= 0 {
		return
	}

	next_count := element_offset + element_count
	if next_count > buf.Count {
		buf.Count = next_count
	}

	data_size := u32(element_count * buf.ElementSizeInBytes)
	dest_offset := u32(element_offset * buf.ElementSizeInBytes)
	required := int(dest_offset + data_size)
	graphics_buffer_ensure_size(buf, required)
	graphics_device_upload_to_buffer(
		buf.GraphicsDevice,
		buf.Resource,
		data,
		data_size,
		dest_offset,
	)
}

graphics_buffer_clear :: proc(buf: ^GraphicsBuffer) {
	if buf != nil {
		buf.Count = 0
	}
}

graphics_buffer_dispose :: proc(buf: ^GraphicsBuffer) {
	if buf == nil || buf.Disposed {
		return
	}
	if buf.GraphicsDevice != nil && buf.GraphicsDevice.Device != nil && buf.Resource != nil {
		when ODIN_OS == .JS {
			fw_gl_release_buffer(web_handle_u32(rawptr(buf.Resource)))
		} else {
			SDL.ReleaseGPUBuffer(buf.GraphicsDevice.Device, buf.Resource)
		}
	}
	buf.Resource = nil
	buf.Disposed = true
}

GraphicsBufferInit :: graphics_buffer_init

graphics_buffer_reserve :: proc(buf: ^GraphicsBuffer, count: int) {
	if buf == nil || buf.Disposed {
		return
	}
	count_value := count
	if count_value < 0 {
		count_value = 0
	}
	buf.Count = count_value
	graphics_buffer_ensure_size(buf, count_value * buf.ElementSizeInBytes)
}

GraphicsBufferReserve :: graphics_buffer_reserve
GraphicsBufferUpload :: graphics_buffer_upload
GraphicsBufferClear :: graphics_buffer_clear
GraphicsBufferDispose :: graphics_buffer_dispose

GraphicsBufferCount :: proc(buf: ^GraphicsBuffer) -> int {
	if buf == nil {
		return 0
	}
	return buf.Count
}

GraphicsBufferFormat :: proc(buf: ^GraphicsBuffer) -> IndexFormat {
	if buf == nil {
		return .Sixteen
	}
	return buf.IndexFormat
}

GraphicsBufferIsDisposed :: proc(buf: ^GraphicsBuffer) -> bool {
	return buf == nil || buf.Disposed
}

GraphicsBufferName :: proc(buf: ^GraphicsBuffer) -> string {
	if buf == nil {
		return ""
	}
	return buf.Name
}

// ------------------------------------------------------------------------------
// Graphics / GraphicsBuffer / VertexBuffer
// ------------------------------------------------------------------------------

VertexBuffer :: struct {
	Base:   GraphicsBuffer,
	Stride: int,
	Format: VertexFormat,
}

vertex_buffer_init_with_format :: proc(
	vb: ^VertexBuffer,
	graphics_device: ^GraphicsDevice,
	format: VertexFormat,
	name: string = "",
) {
	vb.Stride = format.Stride
	vb.Format = vertex_format_clone(format)
	graphics_buffer_init(&vb.Base, graphics_device, format.Stride, .Vertex, .Sixteen, name)
}

vertex_buffer_init :: proc(
	vb: ^VertexBuffer,
	graphics_device: ^GraphicsDevice,
	stride: int,
	name: string = "",
) {
	format: VertexFormat
	if stride == size_of(BatcherVertex) {
		format = default_batcher_vertex_format()
	} else {
		format = vertex_format_make(nil, stride)
	}
	vertex_buffer_init_with_format(vb, graphics_device, format, name)
	vertex_format_dispose(&format)
}

vertex_buffer_upload :: proc(vb: ^VertexBuffer, data: rawptr, vertex_count: int, offset: int = 0) {
	graphics_buffer_upload(&vb.Base, data, vertex_count, offset)
}

vertex_buffer_clear :: proc(vb: ^VertexBuffer) {
	graphics_buffer_clear(&vb.Base)
}

vertex_buffer_dispose :: proc(vb: ^VertexBuffer) {
	vertex_format_dispose(&vb.Format)
	graphics_buffer_dispose(&vb.Base)
}

VertexBufferInit :: proc {
	vertex_buffer_init,
	vertex_buffer_init_with_format,
}

VertexBufferReserve :: proc(vb: ^VertexBuffer, count: int) {
	graphics_buffer_reserve(&vb.Base, count)
}
VertexBufferUpload :: vertex_buffer_upload
VertexBufferClear :: vertex_buffer_clear
VertexBufferDispose :: vertex_buffer_dispose

// ------------------------------------------------------------------------------
// Graphics / GraphicsBuffer / IndexBuffer
// ------------------------------------------------------------------------------

IndexBuffer :: struct {
	Base:   GraphicsBuffer,
	Format: IndexFormat,
}

index_buffer_init :: proc(
	ib: ^IndexBuffer,
	graphics_device: ^GraphicsDevice,
	format: IndexFormat,
	name: string = "",
) {
	ib.Format = format
	graphics_buffer_init(
		&ib.Base,
		graphics_device,
		index_format_size_in_bytes(format),
		.Index,
		format,
		name,
	)
}

index_buffer_upload :: proc(ib: ^IndexBuffer, data: rawptr, index_count: int, offset: int = 0) {
	graphics_buffer_upload(&ib.Base, data, index_count, offset)
}

index_buffer_clear :: proc(ib: ^IndexBuffer) {
	graphics_buffer_clear(&ib.Base)
}

index_buffer_dispose :: proc(ib: ^IndexBuffer) {
	graphics_buffer_dispose(&ib.Base)
}

IndexBufferInit :: index_buffer_init

IndexBufferReserve :: proc(ib: ^IndexBuffer, count: int) {
	graphics_buffer_reserve(&ib.Base, count)
}
IndexBufferUpload :: index_buffer_upload
IndexBufferClear :: index_buffer_clear
IndexBufferDispose :: index_buffer_dispose

// ------------------------------------------------------------------------------
// Graphics / GraphicsBuffer / StorageBuffer
// ------------------------------------------------------------------------------

StorageBuffer :: struct {
	Base: GraphicsBuffer,
}

storage_buffer_init :: proc(
	sb: ^StorageBuffer,
	graphics_device: ^GraphicsDevice,
	element_size_in_bytes: int,
	name: string = "",
) {
	graphics_buffer_init(
		&sb.Base,
		graphics_device,
		element_size_in_bytes,
		.Storage,
		.Sixteen,
		name,
	)
}

storage_buffer_upload :: proc(
	sb: ^StorageBuffer,
	data: rawptr,
	element_count: int,
	offset: int = 0,
) {
	graphics_buffer_upload(&sb.Base, data, element_count, offset)
}

storage_buffer_clear :: proc(sb: ^StorageBuffer) {
	graphics_buffer_clear(&sb.Base)
}

storage_buffer_dispose :: proc(sb: ^StorageBuffer) {
	graphics_buffer_dispose(&sb.Base)
}

StorageBufferInit :: storage_buffer_init

StorageBufferReserve :: proc(sb: ^StorageBuffer, count: int) {
	graphics_buffer_reserve(&sb.Base, count)
}
StorageBufferUpload :: storage_buffer_upload
StorageBufferClear :: storage_buffer_clear
StorageBufferDispose :: storage_buffer_dispose

// Same layout as StorageBuffer so writable compute results can also be read
// by graphics shaders. The backing buffer carries the compute-write usage.
ComputeStorageBuffer :: StorageBuffer

ComputeStorageBufferInit :: proc(
	buffer: ^ComputeStorageBuffer,
	device: ^GraphicsDevice,
	element_size: int,
	name: string = "",
) {
	graphics_buffer_init(&buffer.Base, device, element_size, .Compute, .Sixteen, name)
}

ComputeStorageBufferInitTyped :: proc(
	$T: typeid,
	buffer: ^ComputeStorageBuffer,
	device: ^GraphicsDevice,
	name: string = "",
) {
	ComputeStorageBufferInit(buffer, device, size_of(T), name)
}
ComputeStorageBufferReserve :: StorageBufferReserve
ComputeStorageBufferUpload :: StorageBufferUpload
ComputeStorageBufferUploadTyped :: storage_buffer_upload_typed
ComputeStorageBufferClear :: StorageBufferClear
ComputeStorageBufferDispose :: StorageBufferDispose

// ==============================================================================
// Graphics / Defaults / DefaultResources — 默认资源
// ==============================================================================

DefaultResourcesAvailable :: proc(device: ^GraphicsDevice) -> bool {
	return device != nil && device.Defaults.Initialized
}

// ==============================================================================
// Graphics / Structs / ComputeCommand — 计算调度
// ==============================================================================

ComputeCommand :: struct {
	Shader:                                ^Shader,
	Samplers:                              [dynamic]BoundSampler,
	ReadOnlyStorageBuffers:                [dynamic]^StorageBuffer,
	ReadOnlyStorageTextures:               [dynamic]^Texture,
	ReadWriteStorageBuffers:               [dynamic]^ComputeStorageBuffer,
	ReadWriteStorageTextures:              [dynamic]^Texture,
	// Compatibility names for the original read-write bindings.
	StorageBuffers:                        [dynamic]^StorageBuffer,
	StorageTextures:                       [dynamic]^Texture,
	UniformBuffers:                        [dynamic]UniformBuffer,
	GroupCountX, GroupCountY, GroupCountZ: int,
}

compute_command_init :: proc(command: ^ComputeCommand) {
	if command == nil {
		return
	}
	command.Shader = nil
	delete(command.Samplers)
	delete(command.ReadOnlyStorageBuffers)
	delete(command.ReadOnlyStorageTextures)
	delete(command.ReadWriteStorageBuffers)
	delete(command.ReadWriteStorageTextures)
	delete(command.StorageBuffers)
	delete(command.StorageTextures)
	delete(command.UniformBuffers)
	command.GroupCountX = 1
	command.GroupCountY = 1
	command.GroupCountZ = 1
}

compute_command_dispose :: proc(command: ^ComputeCommand) {
	if command == nil {
		return
	}
	delete(command.Samplers)
	delete(command.ReadOnlyStorageBuffers)
	delete(command.ReadOnlyStorageTextures)
	delete(command.ReadWriteStorageBuffers)
	delete(command.ReadWriteStorageTextures)
	delete(command.StorageBuffers)
	delete(command.StorageTextures)
	delete(command.UniformBuffers)
}

compute_command_set_groups :: proc(command: ^ComputeCommand, x, y, z: int) {
	if command == nil {
		return
	}
	command.GroupCountX = x
	command.GroupCountY = y
	command.GroupCountZ = z
}

graphics_device_dispatch :: proc(device: ^GraphicsDevice, command: ^ComputeCommand) -> bool {
	if device == nil ||
	   device.Disposed ||
	   device.Device == nil ||
	   command == nil ||
	   command.Shader == nil {
		return false
	}
	when ODIN_OS == .JS {
		return false
	} // WebGL2 has no compute stage.
	if command.GroupCountX <= 0 || command.GroupCountY <= 0 || command.GroupCountZ <= 0 {
		return false
	}
	shader := command.Shader
	if shader.Disposed ||
	   shader.Stage != .Compute ||
	   shader.GraphicsDevice != device ||
	   shader.ComputeResource == nil {
		return false
	}
	info := shader.CreateInfo
	rw_buffers := command.ReadWriteStorageBuffers[:]
	rw_textures := command.ReadWriteStorageTextures[:]
	if len(rw_buffers) == 0 {
		rw_buffers = command.StorageBuffers[:]
	}
	if len(rw_textures) == 0 {
		rw_textures = command.StorageTextures[:]
	}
	if len(rw_buffers) != info.ReadWriteStorageBufferCount ||
	   len(rw_textures) != info.ReadWriteStorageTextureCount ||
	   len(command.ReadOnlyStorageBuffers) !=
		   max(info.ReadOnlyStorageBufferCount, info.StorageBufferCount) ||
	   len(command.ReadOnlyStorageTextures) != info.ReadOnlyStorageTextureCount ||
	   len(command.Samplers) != info.SamplerCount ||
	   len(command.UniformBuffers) < info.UniformBufferCount {
		return false
	}
	for buffer in rw_buffers {
		if buffer == nil ||
		   buffer.Base.Disposed ||
		   buffer.Base.GraphicsDevice != device ||
		   buffer.Base.Resource == nil ||
		   buffer.Base.Type != .Compute {
			return false
		}
	}
	for buffer in command.ReadOnlyStorageBuffers {
		if buffer == nil ||
		   buffer.Base.Disposed ||
		   buffer.Base.GraphicsDevice != device ||
		   buffer.Base.Resource == nil ||
		   (buffer.Base.Type != .Storage && buffer.Base.Type != .Compute) {
			return false
		}
	}
	for texture in rw_textures {
		if texture == nil ||
		   texture.Disposed ||
		   texture.GraphicsDevice != device ||
		   texture.Resource == nil ||
		   .ComputeWrite not_in texture.Flags ||
		   .ComputeRead not_in texture.Flags {
			return false
		}
	}
	for texture in command.ReadOnlyStorageTextures {
		if texture == nil ||
		   texture.Disposed ||
		   texture.GraphicsDevice != device ||
		   texture.Resource == nil ||
		   .ComputeRead not_in texture.Flags {
			return false
		}
	}
	for sampler in command.Samplers {
		if sampler.Texture == nil ||
		   sampler.Texture.Disposed ||
		   sampler.Texture.GraphicsDevice != device ||
		   sampler.Texture.Resource == nil {
			return false
		}
	}
	for i in 0 ..< info.UniformBufferCount {
		if len(command.UniformBuffers[i].Data) == 0 {
			return false
		}
	}
	end_render_pass(device)
	command_buffer := device.CommandBuffer
	own_command_buffer := false
	if command_buffer == nil {
		command_buffer = SDL.AcquireGPUCommandBuffer(device.Device)
		own_command_buffer = true
	}
	if command_buffer == nil {
		return false
	}
	buffer_bindings := make(
		[]SDL.GPUStorageBufferReadWriteBinding,
		len(rw_buffers),
		context.temp_allocator,
	)
	for buffer, i in rw_buffers {
		if buffer == nil || buffer.Base.Resource == nil {
			if own_command_buffer {
				_ = SDL.CancelGPUCommandBuffer(command_buffer)
			}
			return false
		}
		buffer_bindings[i] = SDL.GPUStorageBufferReadWriteBinding {
			buffer = buffer.Base.Resource,
			cycle  = false,
		}
	}
	texture_bindings := make(
		[]SDL.GPUStorageTextureReadWriteBinding,
		len(rw_textures),
		context.temp_allocator,
	)
	for texture, i in rw_textures {
		if texture == nil || texture.Resource == nil {
			if own_command_buffer {
				_ = SDL.CancelGPUCommandBuffer(command_buffer)
			}
			return false
		}
		texture_bindings[i] = SDL.GPUStorageTextureReadWriteBinding {
			texture   = texture.Resource,
			mip_level = 0,
			layer     = 0,
			cycle     = false,
		}
	}
	pass := SDL.BeginGPUComputePass(
		command_buffer,
		raw_data(texture_bindings),
		u32(len(texture_bindings)),
		raw_data(buffer_bindings),
		u32(len(buffer_bindings)),
	)
	if pass == nil {
		if own_command_buffer {
			_ = SDL.CancelGPUCommandBuffer(command_buffer)
		}
		return false
	}
	SDL.BindGPUComputePipeline(pass, command.Shader.ComputeResource)
	samplers := make([]SDL.GPUTextureSamplerBinding, len(command.Samplers), context.temp_allocator)
	for sampler, i in command.Samplers {
		samplers[i] = {
			texture = texture_sample_resource(sampler.Texture),
			sampler = create_sampler_from_texture_sampler(device, sampler.Sampler),
		}
	}
	if len(samplers) > 0 {
		SDL.BindGPUComputeSamplers(pass, 0, raw_data(samplers), u32(len(samplers)))
	}
	ro_buffers := make(
		[]^SDL.GPUBuffer,
		len(command.ReadOnlyStorageBuffers),
		context.temp_allocator,
	)
	for buffer, i in command.ReadOnlyStorageBuffers {
		ro_buffers[i] = buffer.Base.Resource
	}
	if len(ro_buffers) > 0 {
		SDL.BindGPUComputeStorageBuffers(pass, 0, raw_data(ro_buffers), u32(len(ro_buffers)))
	}
	ro_textures := make(
		[]^SDL.GPUTexture,
		len(command.ReadOnlyStorageTextures),
		context.temp_allocator,
	)
	for texture, i in command.ReadOnlyStorageTextures {
		ro_textures[i] = texture.Resource
	}
	if len(ro_textures) > 0 {
		SDL.BindGPUComputeStorageTextures(pass, 0, raw_data(ro_textures), u32(len(ro_textures)))
	}
	for uniform, i in command.UniformBuffers[:info.UniformBufferCount] {
		if len(uniform.Data) > 0 {
			SDL.PushGPUComputeUniformData(
				command_buffer,
				u32(i),
				raw_data(uniform.Data[:]),
				u32(len(uniform.Data)),
			)
		}
	}
	SDL.DispatchGPUCompute(
		pass,
		u32(command.GroupCountX),
		u32(command.GroupCountY),
		u32(command.GroupCountZ),
	)
	SDL.EndGPUComputePass(pass)
	if own_command_buffer {
		return SDL.SubmitGPUCommandBuffer(command_buffer)
	}
	return true
}

ComputeCommandInit :: compute_command_init
ComputeCommandDispose :: compute_command_dispose
ComputeCommandSetGroups :: compute_command_set_groups
GraphicsDeviceDispatch :: graphics_device_dispatch

// ==============================================================================
// Graphics / Defaults / Vertices — 默认顶点与类型化助手
// ==============================================================================

PosTexColVertex :: struct #packed {
	Pos: [2]f32,
	Tex: [2]f32,
	Col: Color,
}

make_pos_tex_col_vertex :: proc(position, texcoord: [2]f32, color: Color) -> PosTexColVertex {
	return PosTexColVertex {
		Pos = position,
		Tex = texcoord,
		Col = color,
	}
}

make_batcher_vertex :: proc(position, texcoord: [2]f32, color, mode: Color) -> BatcherVertex {
	return BatcherVertex {
		Pos  = position,
		Tex  = texcoord,
		Col  = color,
		Mode = mode,
	}
}

vertex_format_of :: proc($T: typeid) -> VertexFormat {
	when T == BatcherVertex {
		return default_batcher_vertex_format()
	} else when T == PosTexColVertex {
		return default_pos_tex_col_vertex_format()
	} else {
		return vertex_format_make(nil, size_of(T))
	}
}

index_format_of :: proc($T: typeid) -> IndexFormat {
	when T == u16 || T == i16 {
		return .Sixteen
	} else when T == u32 || T == i32 {
		return .ThirtyTwo
	} else {
		panic("Unsupported index type")
	}
}

mesh_init_typed :: proc(
	$TVertex: typeid,
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	index_format: IndexFormat,
	name: string = "",
) {
	format := vertex_format_of(TVertex)
	defer vertex_format_dispose(&format)
	mesh_init_with_format(mesh, graphics_device, format, index_format, name)
}

mesh_init_instanced_typed :: proc(
	$TVertex, $TInstance: typeid,
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	index_format: IndexFormat,
	name: string = "",
) {
	vertex_format := vertex_format_of(TVertex)
	instance_format := vertex_format_of(TInstance)
	defer vertex_format_dispose(&vertex_format)
	defer vertex_format_dispose(&instance_format)
	mesh_init_instanced_with_format(
		mesh,
		graphics_device,
		vertex_format,
		instance_format,
		index_format,
		name,
	)
}

mesh_init_typed_indexed :: proc(
	$TVertex, $TIndex: typeid,
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	name: string = "",
) {
	mesh_init_typed(TVertex, mesh, graphics_device, index_format_of(TIndex), name)
}

mesh_init_instanced_typed_indexed :: proc(
	$TVertex, $TInstance, $TIndex: typeid,
	mesh: ^Mesh,
	graphics_device: ^GraphicsDevice,
	name: string = "",
) {
	mesh_init_instanced_typed(
		TVertex,
		TInstance,
		mesh,
		graphics_device,
		index_format_of(TIndex),
		name,
	)
}

mesh_set_vertices_typed :: proc($T: typeid, mesh: ^Mesh, data: []T, offset: int = 0) {
	if len(data) <= 0 {
		return
	}
	mesh_set_vertices(mesh, raw_data(data), len(data), offset)
}

mesh_set_instances_typed :: proc($T: typeid, mesh: ^Mesh, data: []T, offset: int = 0) {
	if len(data) <= 0 {
		return
	}
	mesh_set_instances(mesh, raw_data(data), len(data), offset)
}

mesh_set_indices_typed :: proc($T: typeid, mesh: ^Mesh, data: []T, offset: int = 0) {
	if len(data) <= 0 {
		return
	}
	mesh_set_indices(mesh, raw_data(data), len(data), offset)
}

vertex_buffer_init_typed :: proc(
	$T: typeid,
	vb: ^VertexBuffer,
	graphics_device: ^GraphicsDevice,
	name: string = "",
) {
	format := vertex_format_of(T)
	defer vertex_format_dispose(&format)
	vertex_buffer_init_with_format(vb, graphics_device, format, name)
}

vertex_buffer_upload_typed :: proc($T: typeid, vb: ^VertexBuffer, data: []T, offset: int = 0) {
	if len(data) <= 0 {
		return
	}
	vertex_buffer_upload(vb, raw_data(data), len(data), offset)
}

index_buffer_init_typed :: proc(
	$T: typeid,
	ib: ^IndexBuffer,
	graphics_device: ^GraphicsDevice,
	name: string = "",
) {
	index_buffer_init(ib, graphics_device, index_format_of(T), name)
}

index_buffer_upload_typed :: proc($T: typeid, ib: ^IndexBuffer, data: []T, offset: int = 0) {
	if len(data) <= 0 {
		return
	}
	index_buffer_upload(ib, raw_data(data), len(data), offset)
}

storage_buffer_init_typed :: proc(
	$T: typeid,
	sb: ^StorageBuffer,
	graphics_device: ^GraphicsDevice,
	name: string = "",
) {
	storage_buffer_init(sb, graphics_device, size_of(T), name)
}

storage_buffer_upload_typed :: proc($T: typeid, sb: ^StorageBuffer, data: []T, offset: int = 0) {
	if len(data) <= 0 {
		return
	}
	storage_buffer_upload(sb, raw_data(data), len(data), offset)
}

MakePosTexColVertex :: make_pos_tex_col_vertex
MakeBatcherVertex :: make_batcher_vertex
VertexFormatOf :: vertex_format_of
IndexFormatOf :: index_format_of
MeshInitTyped :: proc {
	mesh_init_typed,
	mesh_init_typed_indexed,
}
MeshInitInstancedTyped :: proc {
	mesh_init_instanced_typed,
	mesh_init_instanced_typed_indexed,
}
MeshSetVerticesTyped :: mesh_set_vertices_typed
MeshSetInstancesTyped :: mesh_set_instances_typed
MeshSetIndicesTyped :: mesh_set_indices_typed
VertexBufferInitTyped :: vertex_buffer_init_typed
VertexBufferUploadTyped :: vertex_buffer_upload_typed
IndexBufferInitTyped :: index_buffer_init_typed
IndexBufferUploadTyped :: index_buffer_upload_typed
StorageBufferInitTyped :: storage_buffer_init_typed
StorageBufferUploadTyped :: storage_buffer_upload_typed

// ==============================================================================
// Graphics / UniformBuffer — Uniform 数据
// ==============================================================================

UniformBuffer :: struct {
	Data: [dynamic]u8,
}

uniform_buffer_init :: proc(buffer: ^UniformBuffer, size: int = 0) {
	if buffer == nil {
		return
	}
	delete(buffer.Data)
	buffer.Data = nil
	if size > 0 {
		resize(&buffer.Data, size)
	}
}

uniform_buffer_set :: proc(buffer: ^UniformBuffer, data: []u8, offset: int = 0) {
	if buffer == nil || offset < 0 {
		return
	}
	needed := offset + len(data)
	if needed > len(buffer.Data) {
		resize(&buffer.Data, needed)
	}
	if len(data) > 0 {
		mem.copy(raw_data(buffer.Data[offset:]), raw_data(data), len(data))
	}
}

uniform_buffer_set_value :: proc(buffer: ^UniformBuffer, value: $T, offset: int = 0) {
	data := make([]u8, size_of(T), context.temp_allocator)
	copy_value := value
	mem.copy(raw_data(data), &copy_value, size_of(T))
	uniform_buffer_set(buffer, data, offset)
}

uniform_buffer_get :: proc(buffer: ^UniformBuffer) -> []u8 {
	if buffer == nil {
		return nil
	}
	return buffer.Data[:]
}

uniform_buffer_clear :: proc(buffer: ^UniformBuffer) {
	if buffer == nil {
		return
	}
	resize(&buffer.Data, 0)
}

uniform_buffer_dispose :: proc(buffer: ^UniformBuffer) {
	if buffer == nil {
		return
	}
	delete(buffer.Data)
	buffer.Data = nil
}

UniformBufferInit :: uniform_buffer_init
UniformBufferSet :: uniform_buffer_set
UniformBufferSetValue :: uniform_buffer_set_value
UniformBufferGet :: uniform_buffer_get
UniformBufferClear :: uniform_buffer_clear
UniformBufferDispose :: uniform_buffer_dispose

// ==============================================================================
// Graphics / Structs / VertexFormat — 顶点布局
// ==============================================================================

VertexType :: enum {
	None,
	Float,
	Float2,
	Float3,
	Float4,
	Byte4,
	UByte4,
	Short2,
	UShort2,
	Short4,
	UShort4,
}

vertex_type_size_in_bytes :: proc(t: VertexType) -> int {
	#partial switch t {
	case .Float:
		return 4
	case .Float2:
		return 8
	case .Float3:
		return 12
	case .Float4:
		return 16
	case .Byte4, .UByte4:
		return 4
	case .Short2, .UShort2:
		return 4
	case .Short4, .UShort4:
		return 8
	case .None:
	}
	return 0
}

vertex_type_to_sdl :: proc(t: VertexType, normalized: bool) -> SDL.GPUVertexElementFormat {
	#partial switch t {
	case .Float:
		return .FLOAT
	case .Float2:
		return .FLOAT2
	case .Float3:
		return .FLOAT3
	case .Float4:
		return .FLOAT4
	case .Byte4:
		if normalized {
			return .BYTE4_NORM
		}
		return .BYTE4
	case .UByte4:
		if normalized {
			return .UBYTE4_NORM
		}
		return .UBYTE4
	case .Short2:
		if normalized {
			return .SHORT2_NORM
		}
		return .SHORT2
	case .UShort2:
		if normalized {
			return .USHORT2_NORM
		}
		return .USHORT2
	case .Short4:
		if normalized {
			return .SHORT4_NORM
		}
		return .SHORT4
	case .UShort4:
		if normalized {
			return .USHORT4_NORM
		}
		return .USHORT4
	case .None:
	}
	return .FLOAT
}

VertexElement :: struct {
	Index:      int,
	Type:       VertexType,
	Normalized: bool,
}

VertexFormat :: struct {
	Elements: [dynamic]VertexElement,
	Stride:   int,
}

vertex_format_init :: proc(format: ^VertexFormat, elements: []VertexElement, stride: int = 0) {
	format.Elements = nil
	format.Stride = 0
	for element in elements {
		append(&format.Elements, element)
		format.Stride += vertex_type_size_in_bytes(element.Type)
	}
	if stride != 0 {
		format.Stride = stride
	}
}

vertex_format_make :: proc(elements: []VertexElement, stride: int = 0) -> VertexFormat {
	format: VertexFormat
	vertex_format_init(&format, elements, stride)
	return format
}

vertex_format_clone :: proc(format: VertexFormat) -> VertexFormat {
	clone: VertexFormat
	clone.Stride = format.Stride
	append(&clone.Elements, ..format.Elements[:])
	return clone
}

vertex_format_dispose :: proc(format: ^VertexFormat) {
	if format == nil {
		return
	}
	delete(format.Elements)
	format.Elements = nil
	format.Stride = 0
}

vertex_format_equals :: proc(a, b: VertexFormat) -> bool {
	if a.Stride != b.Stride || len(a.Elements) != len(b.Elements) {
		return false
	}
	for i := 0; i < len(a.Elements); i += 1 {
		ae := a.Elements[i]
		be := b.Elements[i]
		if ae.Index != be.Index || ae.Type != be.Type || ae.Normalized != be.Normalized {
			return false
		}
	}
	return true
}

default_batcher_vertex_format :: proc() -> VertexFormat {
	elements := [4]VertexElement {
		{Index = 0, Type = .Float2, Normalized = false},
		{Index = 1, Type = .Float2, Normalized = false},
		{Index = 2, Type = .UByte4, Normalized = true},
		{Index = 3, Type = .UByte4, Normalized = true},
	}
	return vertex_format_make(elements[:], size_of(BatcherVertex))
}

default_pos_tex_col_vertex_format :: proc() -> VertexFormat {
	elements := [3]VertexElement {
		{Index = 0, Type = .Float2, Normalized = false},
		{Index = 1, Type = .Float2, Normalized = false},
		{Index = 2, Type = .UByte4, Normalized = true},
	}
	return vertex_format_make(elements[:])
}

VertexTypeSizeInBytes :: vertex_type_size_in_bytes
VertexTypeToSDL :: vertex_type_to_sdl
VertexFormatInit :: proc {
	vertex_format_init,
	vertex_format_make,
}
VertexFormatClone :: vertex_format_clone
VertexFormatDispose :: vertex_format_dispose
VertexFormatEquals :: vertex_format_equals
BatcherVertexFormat :: default_batcher_vertex_format
PosTexColVertexFormat :: default_pos_tex_col_vertex_format

// ==============================================================================
// Graphics / Batcher — 二维批处理绘制
// ==============================================================================

BatcherMode :: enum {
	Normal,
	Wash,
	Fill,
}

BatcherModeState :: struct {
	Mode:  BatcherMode,
	Color: Color,
}

BatcherStencil :: struct {
	Enabled:                                bool,
	State:                                  StencilState,
	ReferenceValue, CompareMask, WriteMask: u8,
}

BatcherStencilMake :: proc(enabled: bool, state: StencilState = {
		FailOp      = .Keep,
		PassOp      = .Keep,
		DepthFailOp = .Keep,
		CompareOp   = .Always,
	}, reference: u8 = 0, compare_mask: u8 = 255, write_mask: u8 = 255) -> BatcherStencil {
	return {enabled, state, reference, compare_mask, write_mask}
}

BatcherPushStencil :: proc(b: ^Batcher, stencil: BatcherStencil) {
	append(&b.StencilStack, b.Stencil)
	b.Stencil = stencil
}

BatcherPopStencil :: proc(b: ^Batcher) {
	if len(b.StencilStack) > 0 {
		b.Stencil = b.StencilStack[len(b.StencilStack) - 1]
		resize(&b.StencilStack, len(b.StencilStack) - 1)
	}
}

batcher_apply_stencil :: proc(command: ^DrawCommand, stencil: BatcherStencil) {
	command.StencilTestEnabled = stencil.Enabled
	command.FrontStencilState = stencil.State
	command.BackStencilState = stencil.State
	command.StencilReferenceValue = stencil.ReferenceValue
	command.StencilCompareMask = stencil.CompareMask
	command.StencilWriteMask = stencil.WriteMask
}

BatcherBatch :: struct {
	Stencil:    BatcherStencil,
	IndexStart: int,
	IndexCount: int,
	Material:   ^Material,
	Texture:    ^Texture,
	Sampler:    TextureSampler,
	Blend:      BlendMode,
	Layer:      int,
	Scissor:    RectInt,
	HasScissor: bool,
}

Batcher :: struct {
	Stencil:                BatcherStencil,
	StencilStack:           [dynamic]BatcherStencil,
	Vertices:               [dynamic]BatcherVertex,
	Indices:                [dynamic]int,
	Matrix:                 [16]f32,
	Mode:                   BatcherMode,
	ModeColor:              Color,
	Texture:                ^Texture,
	Sampler:                TextureSampler,
	Blend:                  BlendMode,
	Layer:                  int,
	Scissor:                RectInt,
	HasScissor:             bool,
	MatrixStack:            [dynamic][16]f32,
	SamplerStack:           [dynamic]TextureSampler,
	BlendStack:             [dynamic]BlendMode,
	LayerStack:             [dynamic]int,
	ScissorStack:           [dynamic]RectInt,
	ScissorEnabledStack:    [dynamic]bool,
	MaterialStack:          [dynamic]^Material,
	ModeStack:              [dynamic]BatcherModeState,
	VertexStorageBuffers:   [dynamic]^StorageBuffer,
	FragmentStorageBuffers: [dynamic]^StorageBuffer,
	Batches:                [dynamic]BatcherBatch,
	GraphicsDevice:         ^GraphicsDevice,
	Mesh:                   Mesh,
	VertexShader:           Shader,
	FragmentShader:         Shader,
	Material:               Material,
	HasGPU:                 bool,
	HasMaterial:            bool,
}

// ------------------------------------------------------------------------------
// Graphics / Batcher / Batches — 顶点构建与批次管理
// ------------------------------------------------------------------------------

batcher_identity :: proc() -> [16]f32 {
	return [16]f32{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
}

BatcherMake :: proc() -> Batcher {
	return Batcher {
		Matrix    = batcher_identity(),
		Mode      = .Normal,
		ModeColor = Color{255, 0, 0, 0},
		Sampler   = TextureSamplerMake(TextureFilter.Nearest, TextureWrap.Clamp),
		Blend     = BlendModePremultiply,
	}
}

batcher_transform :: proc(b: ^Batcher, p: Vec2) -> Vec2 {
	m := b.Matrix
	return Vec2{p[0] * m[0] + p[1] * m[4] + m[12], p[0] * m[1] + p[1] * m[5] + m[13]}
}

batcher_mode_color :: proc(mode: BatcherMode) -> Color {
	switch mode {
	case .Normal:
		return Color{255, 0, 0, 0}
	case .Wash:
		return Color{0, 255, 0, 0}
	case .Fill:
		return Color{0, 0, 255, 0}
	}
	return Color{255, 0, 0, 0}
}

batcher_clone_material :: proc(source: ^Material) -> ^Material {
	if source == nil {
		return nil
	}
	result := new(Material)
	MaterialInit(result)
	MaterialCopyTo(source, result)
	return result
}

batcher_free_material :: proc(material: ^Material) {
	if material == nil {
		return
	}
	MaterialDispose(material)
	free(material)
}

batcher_free_batches :: proc(b: ^Batcher) {
	for batch in b.Batches {
		batcher_free_material(batch.Material)
	}
}

batcher_ensure_batch :: proc(b: ^Batcher) {
	start := len(b.Indices)
	if len(b.Batches) > 0 {
		last := &b.Batches[len(b.Batches) - 1]
		if last.Stencil == b.Stencil &&
		   last.Texture == b.Texture &&
		   last.Sampler == b.Sampler &&
		   last.Blend == b.Blend &&
		   last.Layer == b.Layer &&
		   last.HasScissor == b.HasScissor &&
		   (!b.HasScissor || last.Scissor == b.Scissor) &&
		   last.Material != nil {
			return
		}
		last.IndexCount = start - last.IndexStart
	}
	append(&b.Batches, BatcherBatch {
		Stencil    = b.Stencil,
		IndexStart = start,
		IndexCount = 0,
		Material   = batcher_clone_material(&b.Material),
		Texture    = b.Texture,
		Sampler    = b.Sampler,
		Blend      = b.Blend,
		Layer      = b.Layer,
		Scissor    = b.Scissor,
		HasScissor = b.HasScissor,
	})
}

batcher_push_vertex :: proc(b: ^Batcher, p: Vec2, uv: [2]f32, color: Color) {
	batcher_ensure_batch(b)
	append(
		&b.Vertices,
		BatcherVertex{Pos = batcher_transform(b, p), Tex = uv, Col = color, Mode = b.ModeColor},
	)
}

batcher_push_tri :: proc(b: ^Batcher, a, bp, c: Vec2, color: Color, uv0, uv1, uv2: [2]f32) {
	base := len(b.Vertices)
	batcher_push_vertex(b, a, uv0, color)
	batcher_push_vertex(b, bp, uv1, color)
	batcher_push_vertex(b, c, uv2, color)
	append(&b.Indices, base, base + 1, base + 2)
}

BatcherTriangleCount :: proc(b: ^Batcher) -> int {
	return len(b.Indices) / 3
}

BatcherVertexCount :: proc(b: ^Batcher) -> int {
	return len(b.Vertices)
}

BatcherIndexCount :: proc(b: ^Batcher) -> int {
	return len(b.Indices)
}

BatcherBatchCount :: proc(b: ^Batcher) -> int {
	if b == nil {
		return 0
	}
	return len(b.Batches)
}

BatcherClear :: proc(b: ^Batcher) {
	clear(&b.Vertices)
	clear(&b.Indices)
	batcher_free_batches(b)
	clear(&b.Batches)
	clear(&b.VertexStorageBuffers)
	clear(&b.FragmentStorageBuffers)
	for material in b.MaterialStack {
		batcher_free_material(material)
	}
	clear(&b.MaterialStack)
	clear(&b.ModeStack)
	b.Stencil = {}
	clear(&b.StencilStack)
	b.Matrix = batcher_identity()
	b.Mode = .Normal
	b.ModeColor = batcher_mode_color(.Normal)
	b.Texture = nil
	b.Layer = 0
	b.HasScissor = false
	clear(&b.MatrixStack)
	clear(&b.SamplerStack)
	clear(&b.BlendStack)
	clear(&b.LayerStack)
	clear(&b.ScissorStack)
	clear(&b.ScissorEnabledStack)
}

// ------------------------------------------------------------------------------
// Graphics / Batcher / Lifecycle & Render — 生命周期与渲染
// ------------------------------------------------------------------------------

BatcherInit :: proc(b: ^Batcher, device: ^GraphicsDevice, name: string = "") {
	b^ = BatcherMake()
	b.GraphicsDevice = device
	if device != nil {
		MeshInitTyped(BatcherVertex, &b.Mesh, device, IndexFormat.ThirtyTwo, name)
		InitDefaultBatchMaterial(&b.Material, &b.VertexShader, &b.FragmentShader, device)
		b.HasGPU = true
		b.HasMaterial = true
	}
}

BatcherDispose :: proc(b: ^Batcher) {
	if b == nil {
		return
	}
	if b.HasGPU {
		MeshDispose(&b.Mesh)
	}
	ShaderDispose(&b.VertexShader)
	ShaderDispose(&b.FragmentShader)
	MaterialDispose(&b.Material)
	batcher_free_batches(b)
	for material in b.MaterialStack {
		batcher_free_material(material)
	}
	delete(b.Vertices)
	delete(b.Indices)
	delete(b.Batches)
	delete(b.StencilStack)
	delete(b.MatrixStack)
	delete(b.SamplerStack)
	delete(b.BlendStack)
	delete(b.LayerStack)
	delete(b.ScissorStack)
	delete(b.ScissorEnabledStack)
	delete(b.MaterialStack)
	delete(b.ModeStack)
	delete(b.VertexStorageBuffers)
	delete(b.FragmentStorageBuffers)
	b^ = BatcherMake()
}

BatcherUpload :: proc(b: ^Batcher) {
	if !b.HasGPU || len(b.Vertices) == 0 || len(b.Indices) == 0 {
		return
	}
	MeshClear(&b.Mesh)
	MeshSetVerticesTyped(BatcherVertex, &b.Mesh, b.Vertices[:])
	indices: [dynamic]i32 = {}
	for v in b.Indices {
		append(&indices, i32(v))
	}
	MeshSetIndicesTyped(i32, &b.Mesh, indices[:])
	delete(indices)
}

batcher_sort_batches :: proc(b: ^Batcher) {
	for i := 1; i < len(b.Batches); i += 1 {
		current := b.Batches[i]
		j := i - 1
		for j >= 0 && b.Batches[j].Layer < current.Layer {
			b.Batches[j + 1] = b.Batches[j]
			j -= 1
		}
		b.Batches[j + 1] = current
	}
}

batcher_render_with_matrix :: proc(b: ^Batcher, target: DrawableTarget, matrix_arg: [16]f32) {
	if !b.HasGPU || b.GraphicsDevice == nil || len(b.Indices) == 0 {
		return
	}
	BatcherUpload(b)
	m := matrix_arg
	uniform: [size_of([16]f32)]u8
	mem.copy(raw_data(uniform[:]), &m, size_of(m))
	if len(b.Batches) == 0 {
		batcher_ensure_batch(b)
	}
	if len(b.Batches) > 0 {
		b.Batches[len(b.Batches) - 1].IndexCount =
			len(b.Indices) - b.Batches[len(b.Batches) - 1].IndexStart
	}
	batcher_sort_batches(b)
	for i := 0; i < len(b.Batches); i += 1 {
		batch := b.Batches[i]
		count := batch.IndexCount
		if count <= 0 {
			continue
		}
		mat := batch.Material
		if mat == nil {
			mat = &b.Material
		}
		MaterialStageSetUniformBuffer(&mat.Vertex, uniform[:], 0)
		mat.Fragment.Samplers[0] = BoundSampler {
			Texture = batch.Texture,
			Sampler = batch.Sampler,
		}
		cmd: DrawCommand
		DrawCommandFromMesh(&cmd, target, &b.Mesh, mat)
		cmd.IndexOffset = batch.IndexStart
		cmd.IndexCount = count
		cmd.VertexCount = 0
		batcher_apply_stencil(&cmd, batch.Stencil)
		cmd.BlendMode = batch.Blend
		cmd.HasScissor = batch.HasScissor
		cmd.Scissor = batch.Scissor
		append(&cmd.VertexStorageBuffers, ..b.VertexStorageBuffers[:])
		append(&cmd.FragmentStorageBuffers, ..b.FragmentStorageBuffers[:])
		GraphicsDeviceDraw(b.GraphicsDevice, &cmd)
		DrawCommandDispose(&cmd)
	}
}

batcher_render_default :: proc(b: ^Batcher, target: DrawableTarget) {
	w := f32(target.WidthInPixels)
	h := f32(target.HeightInPixels)
	if w <= 0 || h <= 0 {
		return
	}
	m := [16]f32{2 / w, 0, 0, 0, 0, -2 / h, 0, 0, 0, 0, 1, 0, -1, 1, 0, 1}
	batcher_render_with_matrix(b, target, m)
}

batcher_render_options :: proc(b: ^Batcher, target: DrawableTarget, viewport, scissor: RectInt) {
	if !b.HasGPU || b.GraphicsDevice == nil || len(b.Indices) == 0 {
		return
	}
	BatcherUpload(b)
	w := f32(target.WidthInPixels)
	h := f32(target.HeightInPixels)
	if w <= 0 || h <= 0 {
		return
	}
	m := [16]f32{2 / w, 0, 0, 0, 0, -2 / h, 0, 0, 0, 0, 1, 0, -1, 1, 0, 1}
	uniform: [size_of([16]f32)]u8
	mem.copy(raw_data(uniform[:]), &m, size_of(m))
	if len(b.Batches) == 0 {
		batcher_ensure_batch(b)
	}
	if len(b.Batches) > 0 {
		b.Batches[len(b.Batches) - 1].IndexCount =
			len(b.Indices) - b.Batches[len(b.Batches) - 1].IndexStart
	}
	batcher_sort_batches(b)
	for i := 0; i < len(b.Batches); i += 1 {
		batch := b.Batches[i]
		count := batch.IndexCount
		if count <= 0 {
			continue
		}
		mat := batch.Material
		if mat == nil {
			mat = &b.Material
		}
		MaterialStageSetUniformBuffer(&mat.Vertex, uniform[:], 0)
		mat.Fragment.Samplers[0] = BoundSampler {
			Texture = batch.Texture,
			Sampler = batch.Sampler,
		}
		cmd: DrawCommand
		DrawCommandFromMesh(&cmd, target, &b.Mesh, mat)
		cmd.IndexOffset = batch.IndexStart
		cmd.IndexCount = count
		cmd.HasViewport = true
		cmd.Viewport = viewport
		cmd.HasScissor = true
		cmd.Scissor = scissor
		batcher_apply_stencil(&cmd, batch.Stencil)
		cmd.BlendMode = batch.Blend
		append(&cmd.VertexStorageBuffers, ..b.VertexStorageBuffers[:])
		append(&cmd.FragmentStorageBuffers, ..b.FragmentStorageBuffers[:])
		GraphicsDeviceDraw(b.GraphicsDevice, &cmd)
		DrawCommandDispose(&cmd)
	}
}
BatcherRender :: proc {
	batcher_render_default,
	batcher_render_with_matrix,
	batcher_render_options,
}

// ------------------------------------------------------------------------------
// Graphics / Batcher / Primitives — 图元绘制
// ------------------------------------------------------------------------------

batcher_triangle_solid :: proc(b: ^Batcher, a, bp, c: Vec2, color: Color) {
	batcher_push_tri(b, a, bp, c, color, {}, {}, {})
}

batcher_triangle_gradient :: proc(b: ^Batcher, a, bp, c: Vec2, c0, c1, c2: Color) {
	base := len(b.Vertices)
	batcher_push_vertex(b, a, {}, c0)
	batcher_push_vertex(b, bp, {}, c1)
	batcher_push_vertex(b, c, {}, c2)
	append(&b.Indices, base, base + 1, base + 2)
}
BatcherTriangle :: proc {
	batcher_triangle_solid,
	batcher_triangle_gradient,
}

batcher_triangle_texture_solid :: proc(
	b: ^Batcher,
	texture: ^Texture,
	a, bp, c: Vec2,
	uv0, uv1, uv2: [2]f32,
	color: Color,
) {
	b.Texture = texture
	batcher_push_tri(b, a, bp, c, color, uv0, uv1, uv2)
}

batcher_triangle_texture_gradient :: proc(
	b: ^Batcher,
	texture: ^Texture,
	a, bp, c: Vec2,
	uv0, uv1, uv2: [2]f32,
	c0, c1, c2: Color,
) {
	b.Texture = texture
	base := len(b.Vertices)
	batcher_push_vertex(b, a, uv0, c0)
	batcher_push_vertex(b, bp, uv1, c1)
	batcher_push_vertex(b, c, uv2, c2)
	append(&b.Indices, base, base + 1, base + 2)
}
BatcherTriangleTexture :: proc {
	batcher_triangle_texture_solid,
	batcher_triangle_texture_gradient,
}

batcher_quad_points_solid :: proc(b: ^Batcher, a, bp, c, d: Vec2, color: Color) {
	base := len(b.Vertices)
	batcher_push_vertex(b, a, {}, color)
	batcher_push_vertex(b, bp, {}, color)
	batcher_push_vertex(b, c, {}, color)
	batcher_push_vertex(b, d, {}, color)
	append(&b.Indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

batcher_quad_points_gradient :: proc(b: ^Batcher, a, bp, c, d: Vec2, c0, c1, c2, c3: Color) {
	base := len(b.Vertices)
	batcher_push_vertex(b, a, {}, c0)
	batcher_push_vertex(b, bp, {}, c1)
	batcher_push_vertex(b, c, {}, c2)
	batcher_push_vertex(b, d, {}, c3)
	append(&b.Indices, base, base + 1, base + 2, base, base + 2, base + 3)
}
BatcherQuadPoints :: proc {
	batcher_quad_points_solid,
	batcher_quad_points_gradient,
}

batcher_quad_rect_solid :: proc(b: ^Batcher, rect: Rect, color: Color) {
	batcher_quad_points_solid(
		b,
		RectTopLeft(rect),
		RectTopRight(rect),
		RectBottomRight(rect),
		RectBottomLeft(rect),
		color,
	)
}

batcher_quad_shape_solid :: proc(b: ^Batcher, quad: Quad, color: Color) {
	batcher_quad_points_solid(b, quad.A, quad.B, quad.C, quad.D, color)
}

batcher_quad_rect_gradient :: proc(b: ^Batcher, rect: Rect, c0, c1, c2, c3: Color) {
	batcher_quad_points_gradient(
		b,
		RectTopLeft(rect),
		RectTopRight(rect),
		RectBottomRight(rect),
		RectBottomLeft(rect),
		c0,
		c1,
		c2,
		c3,
	)
}

batcher_quad_shape_gradient :: proc(b: ^Batcher, quad: Quad, c0, c1, c2, c3: Color) {
	batcher_quad_points_gradient(b, quad.A, quad.B, quad.C, quad.D, c0, c1, c2, c3)
}
BatcherQuad :: proc {
	batcher_quad_rect_solid,
	batcher_quad_shape_solid,
	batcher_quad_rect_gradient,
	batcher_quad_shape_gradient,
}

batcher_quad_texture_solid :: proc(
	b: ^Batcher,
	texture: ^Texture,
	a, bp, c, d: Vec2,
	uv0, uv1, uv2, uv3: [2]f32,
	color: Color,
) {
	b.Texture = texture
	base := len(b.Vertices)
	batcher_push_vertex(b, a, uv0, color)
	batcher_push_vertex(b, bp, uv1, color)
	batcher_push_vertex(b, c, uv2, color)
	batcher_push_vertex(b, d, uv3, color)
	append(&b.Indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

batcher_quad_texture_gradient :: proc(
	b: ^Batcher,
	texture: ^Texture,
	a, bp, c, d: Vec2,
	uv0, uv1, uv2, uv3: [2]f32,
	c0, c1, c2, c3: Color,
) {
	b.Texture = texture
	base := len(b.Vertices)
	batcher_push_vertex(b, a, uv0, c0)
	batcher_push_vertex(b, bp, uv1, c1)
	batcher_push_vertex(b, c, uv2, c2)
	batcher_push_vertex(b, d, uv3, c3)
	append(&b.Indices, base, base + 1, base + 2, base, base + 2, base + 3)
}
BatcherQuadTexture :: proc {
	batcher_quad_texture_solid,
	batcher_quad_texture_gradient,
}

batcher_line_solid :: proc(b: ^Batcher, from, to: Vec2, thickness: f32, color: Color) {
	d := Vec2{to[0] - from[0], to[1] - from[1]}
	l := math.sqrt(d[0] * d[0] + d[1] * d[1])
	if l <= 0 {
		return
	}
	n := Vec2{-d[1] / l * thickness * .5, d[0] / l * thickness * .5}
	batcher_quad_points_solid(
		b,
		Vec2{from[0] + n[0], from[1] + n[1]},
		Vec2{to[0] + n[0], to[1] + n[1]},
		Vec2{to[0] - n[0], to[1] - n[1]},
		Vec2{from[0] - n[0], from[1] - n[1]},
		color,
	)
}

batcher_line_gradient :: proc(
	b: ^Batcher,
	from, to: Vec2,
	thickness: f32,
	from_color, to_color: Color,
) {
	d := Vec2{to[0] - from[0], to[1] - from[1]}
	l := math.sqrt(d[0] * d[0] + d[1] * d[1])
	if l <= 0 {
		return
	}
	n := Vec2{-d[1] / l * thickness * .5, d[0] / l * thickness * .5}
	batcher_quad_points_gradient(
		b,
		Vec2{from[0] + n[0], from[1] + n[1]},
		Vec2{to[0] + n[0], to[1] + n[1]},
		Vec2{to[0] - n[0], to[1] - n[1]},
		Vec2{from[0] - n[0], from[1] - n[1]},
		from_color,
		to_color,
		to_color,
		from_color,
	)
}
BatcherLine :: proc {
	batcher_line_solid,
	batcher_line_gradient,
}

batcher_rect_solid :: proc(b: ^Batcher, rect: Rect, color: Color) {
	batcher_quad_rect_solid(b, rect, color)
}

batcher_rect_gradient :: proc(b: ^Batcher, rect: Rect, c0, c1, c2, c3: Color) {
	batcher_quad_rect_gradient(b, rect, c0, c1, c2, c3)
}
BatcherRect :: proc {
	batcher_rect_solid,
	batcher_rect_gradient,
}

BatcherRectLine :: proc(b: ^Batcher, rect: Rect, thickness: f32, color: Color) {
	BatcherLine(b, RectTopLeft(rect), RectTopRight(rect), thickness, color)
	BatcherLine(b, RectTopRight(rect), RectBottomRight(rect), thickness, color)
	BatcherLine(b, RectBottomRight(rect), RectBottomLeft(rect), thickness, color)
	BatcherLine(b, RectBottomLeft(rect), RectTopLeft(rect), thickness, color)
}

batcher_circle_solid :: proc(b: ^Batcher, center: Vec2, radius: f32, steps: int, color: Color) {
	if steps < 3 {
		return
	}
	for i in 0 ..< steps {
		a0 := f32(i) / f32(steps) * f32(math.TAU)
		a1 := f32(i + 1) / f32(steps) * f32(math.TAU)
		BatcherTriangle(
			b,
			center,
			Vec2{center[0] + math.cos(a0) * radius, center[1] + math.sin(a0) * radius},
			Vec2{center[0] + math.cos(a1) * radius, center[1] + math.sin(a1) * radius},
			color,
		)
	}
}

batcher_circle_gradient :: proc(
	b: ^Batcher,
	center: Vec2,
	radius: f32,
	steps: int,
	center_color, edge_color: Color,
) {
	if steps < 3 {
		return
	}
	for i in 0 ..< steps {
		a0 := f32(i) / f32(steps) * f32(math.TAU)
		a1 := f32(i + 1) / f32(steps) * f32(math.TAU)
		BatcherTriangle(
			b,
			center,
			Vec2{center[0] + math.cos(a0) * radius, center[1] + math.sin(a0) * radius},
			Vec2{center[0] + math.cos(a1) * radius, center[1] + math.sin(a1) * radius},
			center_color,
			edge_color,
			edge_color,
		)
	}
}
BatcherCircle :: proc {
	batcher_circle_solid,
	batcher_circle_gradient,
}

BatcherCircleLine :: proc(
	b: ^Batcher,
	center: Vec2,
	radius, thickness: f32,
	steps: int,
	color: Color,
) {
	if steps < 3 {
		return
	}
	inner := radius - thickness
	if inner <= 0 {
		batcher_circle_solid(b, center, radius, steps, color)
		return
	}
	for i in 0 ..< steps {
		a0 := f32(i) / f32(steps) * f32(math.TAU)
		a1 := f32(i + 1) / f32(steps) * f32(math.TAU)
		o0 := Vec2{center[0] + math.cos(a0) * radius, center[1] + math.sin(a0) * radius}
		o1 := Vec2{center[0] + math.cos(a1) * radius, center[1] + math.sin(a1) * radius}
		i0 := Vec2{center[0] + math.cos(a0) * inner, center[1] + math.sin(a0) * inner}
		i1 := Vec2{center[0] + math.cos(a1) * inner, center[1] + math.sin(a1) * inner}
		BatcherQuadPoints(b, i0, o0, o1, i1, color)
	}
}

batcher_push_matrix_raw :: proc(
	b: ^Batcher,
	matrix_arg: [16]f32,
	relative: bool = true,
) -> [16]f32 {
	old := b.Matrix
	append(&b.MatrixStack, old)
	if !relative {
		b.Matrix = matrix_arg
		return b.Matrix
	}
	a := old
	c := matrix_arg
	out: [16]f32 = {}
	for col in 0 ..< 4 {
		for row in 0 ..< 4 {
			out[col * 4 + row] =
				c[0 * 4 + row] * a[col * 4 + 0] +
				c[1 * 4 + row] * a[col * 4 + 1] +
				c[2 * 4 + row] * a[col * 4 + 2] +
				c[3 * 4 + row] * a[col * 4 + 3]
		}
	}
	b.Matrix = out
	return b.Matrix
}

batcher_matrix_from_3x2 :: proc(m: Matrix3x2) -> [16]f32 {
	return [16]f32{m.M11, m.M12, 0, 0, m.M21, m.M22, 0, 0, 0, 0, 1, 0, m.M31, m.M32, 0, 1}
}

BatcherPushMatrixRaw :: proc(b: ^Batcher, matrix_arg: [16]f32, relative: bool = true) -> [16]f32 {
	return batcher_push_matrix_raw(b, matrix_arg, relative)
}

BatcherPushMatrixPosition :: proc(b: ^Batcher, position: Vec2, relative: bool = true) -> [16]f32 {
	return batcher_push_matrix_raw(
		b,
		batcher_matrix_from_3x2(Matrix3x2{1, 0, 0, 1, position[0], position[1]}),
		relative,
	)
}

BatcherPushMatrixTransform :: proc(
	b: ^Batcher,
	transform: Transform,
	relative: bool = true,
) -> [16]f32 {
	t := transform
	return batcher_push_matrix_raw(b, batcher_matrix_from_3x2(TransformMatrix(&t)), relative)
}

BatcherPushMatrixTRS :: proc(
	b: ^Batcher,
	position, scale: Vec2,
	rotation: f32,
	relative: bool = true,
) -> [16]f32 {
	return batcher_push_matrix_raw(
		b,
		batcher_matrix_from_3x2(TransformCreateMatrix(position, {}, scale, rotation)),
		relative,
	)
}

BatcherPushMatrixOrigin :: proc(
	b: ^Batcher,
	position, origin, scale: Vec2,
	rotation: f32,
	relative: bool = true,
) -> [16]f32 {
	return batcher_push_matrix_raw(
		b,
		batcher_matrix_from_3x2(TransformCreateMatrix(position, origin, scale, rotation)),
		relative,
	)
}
// ------------------------------------------------------------------------------
// Graphics / Batcher / State — 变换与状态栈
// ------------------------------------------------------------------------------

BatcherPushMatrix :: proc {
	BatcherPushMatrixRaw,
	BatcherPushMatrixPosition,
	BatcherPushMatrixTransform,
	BatcherPushMatrixTRS,
	BatcherPushMatrixOrigin,
}

BatcherPopMatrix :: proc(b: ^Batcher) -> [16]f32 {
	old := b.Matrix
	if len(b.MatrixStack) > 0 {
		b.Matrix = b.MatrixStack[len(b.MatrixStack) - 1]
		resize(&b.MatrixStack, len(b.MatrixStack) - 1)
	}
	return old
}

BatcherPushMode :: proc(b: ^Batcher, mode: BatcherMode) {
	append(&b.ModeStack, BatcherModeState{b.Mode, b.ModeColor})
	b.Mode = mode
	b.ModeColor = batcher_mode_color(mode)
}

BatcherPushModeColor :: proc(b: ^Batcher, mode: Color) {
	append(&b.ModeStack, BatcherModeState{b.Mode, b.ModeColor})
	b.ModeColor = mode
}

BatcherPopMode :: proc(b: ^Batcher) {
	if b == nil || len(b.ModeStack) == 0 {
		return
	}
	state := b.ModeStack[len(b.ModeStack) - 1]
	b.Mode = state.Mode
	b.ModeColor = state.Color
	resize(&b.ModeStack, len(b.ModeStack) - 1)
}

BatcherPushLayer :: proc(b: ^Batcher, delta: int) {
	append(&b.LayerStack, b.Layer)
	b.Layer += delta
}

BatcherPopLayer :: proc(b: ^Batcher) {
	if len(b.LayerStack) > 0 {
		b.Layer = b.LayerStack[len(b.LayerStack) - 1]
		resize(&b.LayerStack, len(b.LayerStack) - 1)
	}
}

BatcherPushSampler :: proc(b: ^Batcher, sampler: TextureSampler) {
	append(&b.SamplerStack, b.Sampler)
	b.Sampler = sampler
}

BatcherPopSampler :: proc(b: ^Batcher) {
	if len(b.SamplerStack) > 0 {
		b.Sampler = b.SamplerStack[len(b.SamplerStack) - 1]
		resize(&b.SamplerStack, len(b.SamplerStack) - 1)
	}
}

BatcherPushBlend :: proc(b: ^Batcher, blend: BlendMode) {
	append(&b.BlendStack, b.Blend)
	b.Blend = blend
}

BatcherPopBlend :: proc(b: ^Batcher) {
	if len(b.BlendStack) > 0 {
		b.Blend = b.BlendStack[len(b.BlendStack) - 1]
		resize(&b.BlendStack, len(b.BlendStack) - 1)
	}
}

BatcherPushScissor :: proc(b: ^Batcher, scissor: RectInt) {
	append(&b.ScissorStack, b.Scissor)
	append(&b.ScissorEnabledStack, b.HasScissor)
	b.Scissor = scissor
	b.HasScissor = true
}

BatcherPopScissor :: proc(b: ^Batcher) {
	if len(b.ScissorStack) > 0 {
		b.Scissor = b.ScissorStack[len(b.ScissorStack) - 1]
		resize(&b.ScissorStack, len(b.ScissorStack) - 1)
		b.HasScissor = b.ScissorEnabledStack[len(b.ScissorEnabledStack) - 1]
		resize(&b.ScissorEnabledStack, len(b.ScissorEnabledStack) - 1)
	}
}
// ------------------------------------------------------------------------------
// Graphics / Batcher / Materials — 材质与存储缓冲
// ------------------------------------------------------------------------------

BatcherPushMaterial :: proc(b: ^Batcher, material: ^Material) {
	if material == nil {
		return
	}
	saved := new(Material)
	MaterialInit(saved)
	MaterialCopyTo(&b.Material, saved)
	append(&b.MaterialStack, saved)
	MaterialCopyTo(material, &b.Material)
	b.HasMaterial = true
}

BatcherPopMaterial :: proc(b: ^Batcher) {
	if b == nil || len(b.MaterialStack) == 0 {
		return
	}
	saved := b.MaterialStack[len(b.MaterialStack) - 1]
	resize(&b.MaterialStack, len(b.MaterialStack) - 1)
	MaterialCopyTo(saved, &b.Material)
	batcher_free_material(saved)
}

BatcherPushMatrix2D :: proc(
	b: ^Batcher,
	position, scale: Vec2,
	rotation: f32,
	relative: bool = true,
) -> [16]f32 {
	return BatcherPushMatrixTRS(b, position, scale, rotation, relative)
}

BatcherPushMatrix2DOrigin :: proc(
	b: ^Batcher,
	position, origin, scale: Vec2,
	rotation: f32,
	relative: bool = true,
) -> [16]f32 {
	return BatcherPushMatrixOrigin(b, position, origin, scale, rotation, relative)
}

BatcherPopMatrixStack :: proc(b: ^Batcher) -> [16]f32 {
	return BatcherPopMatrix(b)
}

batcher_image_sub_pos :: proc(b: ^Batcher, sub: Subtexture, position: Vec2, color: Color = White) {
	if sub.Texture == nil {
		return
	}
	d := sub.DrawCoords
	p := position
	BatcherQuadTexture(
		b,
		sub.Texture,
		Vec2{p[0] + d[0][0], p[1] + d[0][1]},
		Vec2{p[0] + d[1][0], p[1] + d[1][1]},
		Vec2{p[0] + d[2][0], p[1] + d[2][1]},
		Vec2{p[0] + d[3][0], p[1] + d[3][1]},
		sub.TexCoords[0],
		sub.TexCoords[1],
		sub.TexCoords[2],
		sub.TexCoords[3],
		color,
	)
}

batcher_image_sub_color :: proc(b: ^Batcher, sub: Subtexture, color: Color) {
	batcher_image_sub_pos(b, sub, {}, color)
}

batcher_image_texture_color :: proc(b: ^Batcher, texture: ^Texture, color: Color) {
	if texture == nil {
		return
	}
	batcher_image_sub_color(b, SubtextureFromTexture(texture), color)
}

batcher_image_texture_pos :: proc(b: ^Batcher, texture: ^Texture, position: Vec2, color: Color) {
	if texture == nil {
		return
	}
	batcher_image_sub_pos(b, SubtextureFromTexture(texture), position, color)
}

batcher_image_sub_transform :: proc(
	b: ^Batcher,
	sub: Subtexture,
	position, origin, scale: Vec2,
	rotation: f32,
	color: Color,
) {
	if sub.Texture == nil {
		return
	}
	BatcherPushMatrix2DOrigin(b, position, origin, scale, rotation, true)
	batcher_image_sub_color(b, sub, color)
	BatcherPopMatrixStack(b)
}

batcher_image_sub_justified :: proc(
	b: ^Batcher,
	sub: Subtexture,
	position, justify: Vec2,
	color: Color,
) {
	batcher_image_sub_pos(b, sub, Vec2 {
			position[0] - SubtextureWidth(sub) * justify[0],
			position[1] - SubtextureHeight(sub) * justify[1],
		}, color)
}

batcher_image_sub_justified_scale :: proc(
	b: ^Batcher,
	sub: Subtexture,
	position, justify: Vec2,
	scale: f32,
	color: Color,
) {
	batcher_image_sub_transform(b, sub, Vec2 {
			position[0] - SubtextureWidth(sub) * scale * justify[0],
			position[1] - SubtextureHeight(sub) * scale * justify[1],
		}, Vec2{}, Vec2{scale, scale}, 0, color)
}

batcher_image_stretch :: proc(b: ^Batcher, sub: Subtexture, rect: Rect, color: Color) {
	if sub.Texture == nil {
		return
	}
	BatcherQuadTexture(
		b,
		sub.Texture,
		RectTopLeft(rect),
		RectTopRight(rect),
		RectBottomRight(rect),
		RectBottomLeft(rect),
		sub.TexCoords[0],
		sub.TexCoords[1],
		sub.TexCoords[2],
		sub.TexCoords[3],
		color,
	)
}

batcher_image_fit :: proc(
	b: ^Batcher,
	sub: Subtexture,
	rect: Rect,
	justify: Vec2,
	color: Color,
	flip_x, flip_y: bool,
) {
	if sub.Texture == nil || SubtextureWidth(sub) <= 0 || SubtextureHeight(sub) <= 0 {
		return
	}
	bounds := rect
	if bounds.Width == 0 {
		bounds.Width = SubtextureWidth(sub)
	}
	if bounds.Height == 0 {
		bounds.Height = SubtextureHeight(sub)
	}
	scale := math.min(bounds.Width / SubtextureWidth(sub), bounds.Height / SubtextureHeight(sub))
	at := Vec2{bounds.X + bounds.Width * justify[0], bounds.Y + bounds.Height * justify[1]}
	orig := Vec2{SubtextureWidth(sub) * justify[0], SubtextureHeight(sub) * justify[1]}
	sx := scale
	if flip_x {
		sx = -sx
	}
	sy := scale
	if flip_y {
		sy = -sy
	}
	batcher_image_sub_transform(b, sub, at, orig, Vec2{sx, sy}, 0, color)
}
BatcherImage :: proc {
	batcher_image_sub_pos,
	batcher_image_sub_color,
	batcher_image_texture_color,
	batcher_image_texture_pos,
	batcher_image_sub_transform,
	batcher_image_sub_justified,
	batcher_image_sub_justified_scale,
	batcher_image_stretch,
	batcher_image_fit,
}

BatcherLineDashed :: proc(b: ^Batcher, from, to: Vec2, weight, dash, offset: f32, color: Color) {
	d := Vec2{to[0] - from[0], to[1] - from[1]}
	length := math.sqrt(d[0] * d[0] + d[1] * d[1])
	if length <= 0 || dash <= 0 {
		return
	}
	axis := Vec2{d[0] / length, d[1] / length}
	phase := offset - math.floor(offset)
	start := dash * phase * 2
	if start > dash {
		start -= dash * 2
	}
	for at := start; at < length; at += dash * 2 {
		a := math.max(at, 0)
		z := math.min(at + dash, length)
		BatcherLine(
			b,
			Vec2{from[0] + axis[0] * a, from[1] + axis[1] * a},
			Vec2{from[0] + axis[0] * z, from[1] + axis[1] * z},
			weight,
			color,
		)
	}
}

BatcherQuadLine :: proc(b: ^Batcher, a, bp, c, d: Vec2, weight: f32, color: Color) {
	BatcherLine(b, a, bp, weight, color)
	BatcherLine(b, bp, c, weight, color)
	BatcherLine(b, c, d, weight, color)
	BatcherLine(b, d, a, weight, color)
}

BatcherTriangleLine :: proc(b: ^Batcher, a, bp, c: Vec2, weight: f32, color: Color) {
	BatcherLine(b, a, bp, weight, color)
	BatcherLine(b, bp, c, weight, color)
	BatcherLine(b, c, a, weight, color)
}

BatcherRectDashed :: proc(b: ^Batcher, r: Rect, weight, dash, offset: f32, color: Color) {
	BatcherLineDashed(b, RectTopLeft(r), RectTopRight(r), weight, dash, offset, color)
	BatcherLineDashed(b, RectTopRight(r), RectBottomRight(r), weight, dash, offset, color)
	BatcherLineDashed(b, RectBottomRight(r), RectBottomLeft(r), weight, dash, offset, color)
	BatcherLineDashed(b, RectBottomLeft(r), RectTopLeft(r), weight, dash, offset, color)
}

batcher_rounded_points :: proc(r: Rect, radius: f32, segments: int) -> [dynamic]Vec2 {
	points: [dynamic]Vec2 = {}
	if segments < 1 {
		return points
	}
	rr := math.max(0, math.min(radius, math.min(math.abs(r.Width), math.abs(r.Height)) * 0.5))
	if rr <= 0 {
		append(&points, RectTopLeft(r), RectTopRight(r), RectBottomRight(r), RectBottomLeft(r))
		return points
	}
	centers := [4]Vec2 {
		Vec2{r.X + rr, r.Y + rr},
		Vec2{RectRight(r) - rr, r.Y + rr},
		Vec2{RectRight(r) - rr, RectBottom(r) - rr},
		Vec2{r.X + rr, RectBottom(r) - rr},
	}
	starts := [4]f32{f32(math.PI), f32(math.PI * 1.5), 0, f32(math.PI * 0.5)}
	for corner in 0 ..< 4 {
		for step in 0 ..= segments {
			a := starts[corner] + f32(step) / f32(segments) * f32(math.PI * 0.5)
			append(
				&points,
				Vec2{centers[corner][0] + math.cos(a) * rr, centers[corner][1] + math.sin(a) * rr},
			)
		}
	}
	return points
}

batcher_rect_rounded_uniform :: proc(b: ^Batcher, r: Rect, radius: f32, color: Color) {
	points := batcher_rounded_points(r, radius, 8)
	defer delete(points)
	if len(points) < 3 {
		return
	}
	center := RectCenter(r)
	for i := 0; i < len(points); i += 1 {
		BatcherTriangle(b, center, points[i], points[(i + 1) % len(points)], color)
	}
}

batcher_rect_rounded_corners :: proc(b: ^Batcher, r: Rect, r0, r1, r2, r3: f32, color: Color) {
	radii := [4]f32{r0, r1, r2, r3}
	max_radius := math.min(math.abs(r.Width), math.abs(r.Height)) * 0.5
	for i := 0; i < 4; i += 1 {
		radii[i] = math.max(0, math.min(radii[i], max_radius))
	}
	points: [dynamic]Vec2 = {}
	defer delete(points)
	centers := [4]Vec2 {
		Vec2{r.X + radii[0], r.Y + radii[0]},
		Vec2{RectRight(r) - radii[1], r.Y + radii[1]},
		Vec2{RectRight(r) - radii[2], RectBottom(r) - radii[2]},
		Vec2{r.X + radii[3], RectBottom(r) - radii[3]},
	}
	starts := [4]f32{f32(math.PI), f32(math.PI * 1.5), 0, f32(math.PI * 0.5)}
	for corner in 0 ..< 4 {
		for step in 0 ..= 8 {
			a := starts[corner] + f32(step) / 8 * f32(math.PI * 0.5)
			append(&points, Vec2 {
				centers[corner][0] + math.cos(a) * radii[corner],
				centers[corner][1] + math.sin(a) * radii[corner],
			})
		}
	}
	center := RectCenter(r)
	for i := 0; i < len(points); i += 1 {
		BatcherTriangle(b, center, points[i], points[(i + 1) % len(points)], color)
	}
}
BatcherRectRounded :: proc {
	batcher_rect_rounded_uniform,
	batcher_rect_rounded_corners,
}

batcher_rect_rounded_line_uniform :: proc(
	b: ^Batcher,
	r: Rect,
	radius, weight: f32,
	color: Color,
) {
	points := batcher_rounded_points(r, radius, 8)
	defer delete(points)
	if len(points) < 2 {
		return
	}
	for i := 0; i < len(points); i += 1 {
		BatcherLine(b, points[i], points[(i + 1) % len(points)], weight, color)
	}
}

batcher_rect_rounded_line_corners :: proc(
	b: ^Batcher,
	r: Rect,
	r0, r1, r2, r3, weight: f32,
	color: Color,
) {
	radii := [4]f32{r0, r1, r2, r3}
	max_radius := math.min(math.abs(r.Width), math.abs(r.Height)) * 0.5
	for i := 0; i < 4; i += 1 {
		radii[i] = math.max(0, math.min(radii[i], max_radius))
	}
	points: [dynamic]Vec2 = {}
	defer delete(points)
	centers := [4]Vec2 {
		Vec2{r.X + radii[0], r.Y + radii[0]},
		Vec2{RectRight(r) - radii[1], r.Y + radii[1]},
		Vec2{RectRight(r) - radii[2], RectBottom(r) - radii[2]},
		Vec2{r.X + radii[3], RectBottom(r) - radii[3]},
	}
	starts := [4]f32{f32(math.PI), f32(math.PI * 1.5), 0, f32(math.PI * 0.5)}
	for corner in 0 ..< 4 {
		for step in 0 ..= 8 {
			a := starts[corner] + f32(step) / 8 * f32(math.PI * 0.5)
			append(&points, Vec2 {
				centers[corner][0] + math.cos(a) * radii[corner],
				centers[corner][1] + math.sin(a) * radii[corner],
			})
		}
	}
	for i := 0; i < len(points); i += 1 {
		BatcherLine(b, points[i], points[(i + 1) % len(points)], weight, color)
	}
}
BatcherRectRoundedLine :: proc {
	batcher_rect_rounded_line_uniform,
	batcher_rect_rounded_line_corners,
}

batcher_semi_circle_solid :: proc(
	b: ^Batcher,
	center: Vec2,
	start, end, radius: f32,
	steps: int,
	color: Color,
) {
	if steps < 1 {
		return
	}
	for i in 0 ..< steps {
		a0 := start + (end - start) * f32(i) / f32(steps)
		a1 := start + (end - start) * f32(i + 1) / f32(steps)
		BatcherTriangle(
			b,
			center,
			Vec2{center[0] + math.cos(a0) * radius, center[1] + math.sin(a0) * radius},
			Vec2{center[0] + math.cos(a1) * radius, center[1] + math.sin(a1) * radius},
			color,
		)
	}
}

batcher_semi_circle_gradient :: proc(
	b: ^Batcher,
	center: Vec2,
	start, end, radius: f32,
	steps: int,
	center_color, edge_color: Color,
) {
	if steps < 1 {
		return
	}
	for i in 0 ..< steps {
		a0 := start + (end - start) * f32(i) / f32(steps)
		a1 := start + (end - start) * f32(i + 1) / f32(steps)
		BatcherTriangle(
			b,
			center,
			Vec2{center[0] + math.cos(a0) * radius, center[1] + math.sin(a0) * radius},
			Vec2{center[0] + math.cos(a1) * radius, center[1] + math.sin(a1) * radius},
			center_color,
			edge_color,
			edge_color,
		)
	}
}
BatcherSemiCircle :: proc {
	batcher_semi_circle_solid,
	batcher_semi_circle_gradient,
}

BatcherSemiCircleLine :: proc(
	b: ^Batcher,
	center: Vec2,
	start, end, radius, weight: f32,
	steps: int,
	color: Color,
) {
	if steps < 1 {
		return
	}
	for i in 0 ..< steps {
		a0 := start + (end - start) * f32(i) / f32(steps)
		a1 := start + (end - start) * f32(i + 1) / f32(steps)
		BatcherLine(
			b,
			Vec2{center[0] + math.cos(a0) * radius, center[1] + math.sin(a0) * radius},
			Vec2{center[0] + math.cos(a1) * radius, center[1] + math.sin(a1) * radius},
			weight,
			color,
		)
	}
}

BatcherCircleDashed :: proc(
	b: ^Batcher,
	center: Vec2,
	radius, weight, dash, offset: f32,
	steps: int,
	color: Color,
) {
	if steps < 3 || dash <= 0 {
		return
	}
	last := Vec2{center[0] + radius, center[1]}
	da := f32(math.TAU) / f32(steps)
	dx := radius - radius * math.cos(da)
	dy := radius * math.sin(da)
	segment_length := math.sqrt(dx * dx + dy * dy)
	phase := offset
	for i := 1; i <= steps; i += 1 {
		a := f32(i) / f32(steps) * f32(math.TAU)
		next := Vec2{center[0] + math.cos(a) * radius, center[1] + math.sin(a) * radius}
		BatcherLineDashed(b, last, next, weight, dash, phase, color)
		phase += segment_length
		last = next
	}
}

BatcherRadialBar :: proc(b: ^Batcher, position: Vec2, percent, inner, outer: f32, color: Color) {
	if percent <= 0 || outer <= inner {
		return
	}
	segments := 64
	single := f32(1) / f32(segments)
	bar_radius := (outer - inner) * 0.5
	if percent < single {
		scale := math.clamp(percent / single, 0, 1)
		BatcherCircle(b, position, bar_radius * scale, 16, color)
		return
	}
	for i := 0; i < segments; i += 1 {
		prev := f32(i) / f32(segments)
		next := math.min(percent, f32(i + 1) / f32(segments))
		a0 := prev * f32(math.TAU)
		a1 := next * f32(math.TAU)
		p0 := Vec2{math.cos(a0), math.sin(a0)}
		p1 := Vec2{math.cos(a1), math.sin(a1)}
		if percent < 0.99 && prev <= 0 {
			BatcherCircle(b, Vec2 {
					position[0] + p0[0] * (inner + outer) * 0.5,
					position[1] + p0[1] * (inner + outer) * 0.5,
				}, bar_radius, 16, color)
		}
		BatcherQuadPoints(
			b,
			Vec2{position[0] + p0[0] * inner, position[1] + p0[1] * inner},
			Vec2{position[0] + p0[0] * outer, position[1] + p0[1] * outer},
			Vec2{position[0] + p1[0] * outer, position[1] + p1[1] * outer},
			Vec2{position[0] + p1[0] * inner, position[1] + p1[1] * inner},
			color,
		)
		if next >= percent {
			if percent < 0.99 {
				BatcherCircle(b, Vec2 {
						position[0] + p1[0] * (inner + outer) * 0.5,
						position[1] + p1[1] * (inner + outer) * 0.5,
					}, bar_radius, 16, color)
			}
			break
		}
	}
}

BatcherCheckeredPattern :: proc(b: ^Batcher, bounds: Rect, cell_w, cell_h: f32, a, bcolor: Color) {
	if cell_w <= 0 || cell_h <= 0 {
		return
	}
	rows := int(math.ceil(bounds.Height / cell_h))
	cols := int(math.ceil(bounds.Width / cell_w))
	for y in 0 ..< rows {
		for x in 0 ..< cols {
			c := a
			if (x + y) % 2 != 0 {
				c = bcolor
			}
			BatcherRect(b, Rect {
					bounds.X + f32(x) * cell_w,
					bounds.Y + f32(y) * cell_h,
					math.min(cell_w, bounds.Width - f32(x) * cell_w),
					math.min(cell_h, bounds.Height - f32(y) * cell_h),
				}, c)
		}
	}
}

// ==============================================================================
// Graphics / Structs / Subtexture — 子纹理
// ==============================================================================
CoordinateBuffer :: [4]Vec2

Subtexture :: struct {
	Texture:    ^Texture,
	Source:     Rect,
	Frame:      Rect,
	TexCoords:  CoordinateBuffer,
	DrawCoords: CoordinateBuffer,
}

SubtextureEmpty :: Subtexture{}

SubtextureMake :: proc(texture: ^Texture, source, frame: Rect) -> Subtexture {
	result := Subtexture {
		Texture = texture,
		Source  = source,
		Frame   = frame,
	}
	result.DrawCoords = CoordinateBuffer {
		{-frame.X, -frame.Y},
		{-frame.X + source.Width, -frame.Y},
		{-frame.X + source.Width, -frame.Y + source.Height},
		{-frame.X, -frame.Y + source.Height},
	}
	if texture != nil && texture.Width > 0 && texture.Height > 0 {
		px := 1.0 / f32(texture.Width)
		py := 1.0 / f32(texture.Height)
		tx0 := source.X * px
		ty0 := source.Y * py
		tx1 := RectRight(source) * px
		ty1 := RectBottom(source) * py
		result.TexCoords = CoordinateBuffer{{tx0, ty0}, {tx1, ty0}, {tx1, ty1}, {tx0, ty1}}
	}
	return result
}

SubtextureFromTexture :: proc(texture: ^Texture) -> Subtexture {
	if texture == nil {
		return Subtexture{}
	}
	bounds := Rect{0, 0, f32(texture.Width), f32(texture.Height)}
	return SubtextureMake(texture, bounds, bounds)
}

SubtextureFromSource :: proc(texture: ^Texture, source: Rect) -> Subtexture {
	return SubtextureMake(texture, source, Rect{0, 0, source.Width, source.Height})
}

SubtextureWidth :: proc(subtexture: Subtexture) -> f32 {
	return subtexture.Frame.Width
}

SubtextureHeight :: proc(subtexture: Subtexture) -> f32 {
	return subtexture.Frame.Height
}

SubtextureSize :: proc(subtexture: Subtexture) -> Vec2 {
	return RectSize(subtexture.Frame)
}

SubtextureIsEmpty :: proc(subtexture: Subtexture) -> bool {
	return(
		subtexture.Texture == nil ||
		subtexture.Source.Width == 0 ||
		subtexture.Source.Height == 0 \
	)
}

SubtextureGetClip :: proc(subtexture: Subtexture, clip: Rect) -> (source, frame: Rect) {
	source_position := RectPosition(subtexture.Source)
	frame_position := RectPosition(subtexture.Frame)
	offset := Vec2{source_position[0] + frame_position[0], source_position[1] + frame_position[1]}
	source = RectIntersection(RectTranslate(clip, offset), subtexture.Source)
	frame = Rect {
		math.min(f32(0), subtexture.Frame.X + clip.X),
		math.min(f32(0), subtexture.Frame.Y + clip.Y),
		clip.Width,
		clip.Height,
	}
	return
}

SubtextureGetClipSubtexture :: proc(subtexture: Subtexture, clip: Rect) -> Subtexture {
	source, frame := SubtextureGetClip(subtexture, clip)
	return SubtextureMake(subtexture.Texture, source, frame)
}

BatcherImageJustified :: proc {
	batcher_image_sub_justified,
	batcher_image_sub_justified_scale,
}
BatcherImageStretch :: batcher_image_stretch
BatcherImageFit :: batcher_image_fit

TextureFormatIsDepthStencilFormat :: proc(format: TextureFormat) -> bool {
	return !texture_format_is_color_format(format)
}

TextureFormatIsSupported :: proc(format: TextureFormat, device: ^GraphicsDevice) -> bool {
	return GraphicsDeviceIsTextureFormatSupported(device, format)
}

GraphicsDeviceInsertDebugLabel :: proc(device: ^GraphicsDevice, label: string) {
	if device == nil || device.CommandBuffer == nil {
		return
	}
	when ODIN_OS == .JS {
		web_log(label)
	} else {
		SDL.InsertGPUDebugLabel(device.CommandBuffer, to_cstring(label))
	}
}

UniformBufferEqualTo :: proc(a, b: ^UniformBuffer) -> bool {
	if a == nil || b == nil {
		return a == b
	}
	if len(a.Data) != len(b.Data) {
		return false
	}
	for value, i in a.Data {
		if value != b.Data[i] {
			return false
		}
	}
	return true
}

MaterialEqualTo :: proc(a, b: ^Material) -> bool {
	if a == nil || b == nil {
		return a == b
	}
	for stage_index in 0 ..< 2 {
		left := stage_index == 0 ? &a.Vertex : &a.Fragment
		right := stage_index == 0 ? &b.Vertex : &b.Fragment
		if left.Shader != right.Shader || left.Samplers != right.Samplers {
			return false
		}
		for i in 0 ..< 8 {
			if !UniformBufferEqualTo(
				&left.UniformBufferObjects[i],
				&right.UniformBufferObjects[i],
			) {
				return false
			}
		}
	}
	return true
}
