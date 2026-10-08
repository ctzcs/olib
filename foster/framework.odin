package foster_framework

import "core:c"
import "core:fmt"
import "core:mem"
import coretime "core:time"
import "core:strings"
import SDL "vendor:sdl3"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Framework / Version — 上游版本基线
//   Spatial / Point2 — 整数坐标
//   Graphics / Enums / GraphicsDriver — 图形后端
//   App / Configuration — 应用选项
//   Utility / UpdateMode — 更新策略
//   Utility / Time — 帧计时
//   Graphics / Defaults / DefaultResources — 默认资源状态
//   Graphics / GraphicsDevice — 设备状态
//   Graphics / Defaults / DefaultResources — 生命周期
//   Graphics / Defaults / BatcherVertex — 默认批处理顶点
//   Internal / GraphicsDeviceSDL — 帧与交换链
//   Window — 窗口状态
//   App — 配置、状态与回调
//   Window / Lifecycle — 创建、属性与释放
//   App / Lifecycle — 初始化与释放
//   App / Events — 原生与 Web 事件分发
//   App / MainLoop — 更新、渲染与退出

// core:os 经 platform_native/web.odin 间接使用(js 目标无 core:os)

// ==============================================================================
// Framework / Version — 上游版本基线
// ==============================================================================
// Keep the port's public version aligned with the upstream Foster package.
FosterVersionMajor :: 0
FosterVersionMinor :: 4
FosterVersionPatch :: 2

version_string :: proc() -> string {
	return fmt.aprintf("%d.%d.%d", FosterVersionMajor, FosterVersionMinor, FosterVersionPatch)
}

sdl_version_string :: proc() -> string {
	v := SDL.GetVersion()
	return fmt.aprintf(
		"%d.%d.%d",
		SDL.VERSIONNUM_MAJOR(v),
		SDL.VERSIONNUM_MINOR(v),
		SDL.VERSIONNUM_MICRO(v),
	)
}

// ==============================================================================
// Spatial / Point2 — 整数坐标
// ==============================================================================

Point2 :: struct {
	X: int,
	Y: int,
}

Point2Zero :: Point2{0, 0}
Point2One :: Point2{1, 1}

// ==============================================================================
// Graphics / Enums / GraphicsDriver — 图形后端
// ==============================================================================

GraphicsDriver :: enum {
	None,
	Private,
	Vulkan,
	D3D12,
	Metal,
}

graphics_driver_shader_extension :: proc(driver: GraphicsDriver) -> string {
	switch driver {
	case .None:
		return ""
	case .Private, .Vulkan:
		return "spv"
	case .D3D12:
		return "dxil"
	case .Metal:
		return "msl"
	}
	return ""
}

GetShaderExtension :: graphics_driver_shader_extension

// ==============================================================================
// App / Configuration — 应用选项
// ==============================================================================

AppFlag :: enum u8 {
	GraphicsDebugging,
	MultiSampledBackBuffer,
}

AppFlags :: distinct bit_set[AppFlag;u8]

AppFlagsNone :: AppFlags{}

// ==============================================================================
// Utility / UpdateMode — 更新策略
// ==============================================================================

UpdateModeKind :: enum {
	Fixed,
	Unlocked,
}

UpdateMode :: struct {
	Mode:             UpdateModeKind,
	FixedTargetTime:  coretime.Duration,
	FixedMaxTime:     coretime.Duration,
	FixedWaitEnabled: bool,
}

fixed_step :: proc(
	target_time_per_frame: coretime.Duration,
	max_time_per_frame := coretime.Duration(0),
	wait_for_next_update := true,
) -> UpdateMode {
	max_time := max_time_per_frame
	if max_time == 0 {
		max_time = target_time_per_frame * 5
	}
	return UpdateMode {
		Mode             = .Fixed,
		FixedTargetTime  = target_time_per_frame,
		FixedMaxTime     = max_time,
		FixedWaitEnabled = wait_for_next_update,
	}
}

fixed_step_fps :: proc(fps: int, wait_for_next_update := true) -> UpdateMode {
	return fixed_step(coretime.Second / coretime.Duration(fps), 0, wait_for_next_update)
}

unlocked_step :: proc() -> UpdateMode {
	return UpdateMode {
		Mode = .Unlocked,
	}
}

FixedStep :: proc {
	fixed_step,
	fixed_step_fps,
}
UnlockedStep :: unlocked_step

// ==============================================================================
// Utility / Time — 帧计时
// ==============================================================================

Time :: struct {
	Elapsed:     coretime.Duration,
	Previous:    coretime.Duration,
	Delta:       f32,
	Frame:       u64,
	RenderFrame: u64,
}

advance_time :: proc(t: Time, delta: coretime.Duration) -> Time {
	return Time {
		Elapsed     = t.Elapsed + delta,
		Previous    = t.Elapsed,
		Delta       = f32(coretime.duration_seconds(delta)),
		Frame       = t.Frame + 1,
		RenderFrame = t.RenderFrame,
	}
}

advance_render_frame :: proc(t: Time) -> Time {
	next := t
	next.RenderFrame += 1
	return next
}

Advance :: advance_time
AdvanceRenderFrame :: advance_render_frame

// ==============================================================================
// Graphics / Defaults / DefaultResources — 默认资源状态
// ==============================================================================

DefaultResources :: struct {
	VertexShader:           Shader,
	FragmentShader:         Shader,
	TexturedVertexShader:   Shader,
	TexturedFragmentShader: Shader,
	MsdfVertexShader:       Shader,
	MsdfFragmentShader:     Shader,
	BatchMaterial:          Material,
	TexturedMaterial:       Material,
	MsdfMaterial:           Material,
	Initialized:            bool,
}

time_seconds_f :: proc(t: Time) -> f32 {
	return f32(coretime.duration_seconds(t.Elapsed))
}

time_between_interval :: proc(t: Time, interval: f64, offset: f64 = 0) -> bool {
	return BetweenIntervalCalc(coretime.duration_seconds(t.Elapsed), interval, offset)
}

TimeSecondsF :: time_seconds_f
TimeBetweenInterval :: time_between_interval

// ==============================================================================
// Graphics / GraphicsDevice — 设备状态
// ==============================================================================

GraphicsDevice :: struct {
	Driver:                GraphicsDriver,
	VSync:                 bool,
	Disposed:              bool,
	RequestedDriver:       GraphicsDriver,
	Device:                ^SDL.GPUDevice,
	Window:                ^SDL.Window,
	SwapchainFormat:       SDL.GPUTextureFormat,
	SupportsMailbox:       bool,
	ClearColor:            SDL.FColor,
	CommandBuffer:         ^SDL.GPUCommandBuffer,
	RenderPass:            ^SDL.GPURenderPass,
	SwapchainTexture:      ^SDL.GPUTexture,
	SwapchainWidth:        u32,
	SwapchainHeight:       u32,
	InFrame:               bool,
	RenderPassTarget:      DrawableTarget,
	RenderPassTargetSize:  Point2,
	RenderPassPipeline:    ^SDL.GPUGraphicsPipeline,
	RenderPassIndexBuffer: ^SDL.GPUBuffer,
	RenderPassViewport:    RectInt,
	RenderPassScissor:     RectInt,
	HasRenderPassViewport: bool,
	HasRenderPassScissor:  bool,
	SamplerCache:          map[TextureSampler]^SDL.GPUSampler,
	PipelineCache:         map[u64]^SDL.GPUGraphicsPipeline,
	FailedPipelineHashes:  map[u64]bool,
	ReportedDrawFailures:  bit_set[DrawFailure],
	UploadStaging:         ^SDL.GPUTransferBuffer,
	UploadStagingSize:     u32,
	UploadStagingCursor:   u32,
	WindowRenderTarget:    Target,
	HasWindowRenderTarget: bool,
	BackbufferTarget:      Target,
	BackbufferSize:        Point2,
	HasBackbufferTarget:   bool,
	BackbufferSampleCount: SampleCount,
	Defaults:              DefaultResources,

	DebugPipeline:       ^SDL.GPUGraphicsPipeline,
	DebugVertexShader:   ^SDL.GPUShader,
	DebugFragmentShader: ^SDL.GPUShader,
	DebugVertexBuffer:   ^SDL.GPUBuffer,
	DebugTexture:        ^SDL.GPUTexture,
	DebugSampler:        ^SDL.GPUSampler,
}

// ==============================================================================
// Graphics / Defaults / DefaultResources — 生命周期
// ==============================================================================

default_resources_init :: proc(device: ^GraphicsDevice) {
	if device == nil || device.Device == nil || device.Defaults.Initialized {
		return
	}
	init_default_batch_material(
		&device.Defaults.BatchMaterial,
		&device.Defaults.VertexShader,
		&device.Defaults.FragmentShader,
		device,
	)
	init_default_textured_material(
		&device.Defaults.TexturedMaterial,
		&device.Defaults.TexturedVertexShader,
		&device.Defaults.TexturedFragmentShader,
		device,
	)
	init_default_msdf_material(
		&device.Defaults.MsdfMaterial,
		&device.Defaults.MsdfVertexShader,
		&device.Defaults.MsdfFragmentShader,
		device,
	)
	device.Defaults.Initialized = true
}
DefaultResourcesInit :: default_resources_init

default_resources_dispose :: proc(device: ^GraphicsDevice) {
	if device == nil || !device.Defaults.Initialized {
		return
	}
	if device.Defaults.BatchMaterial.Vertex.Shader != nil {
		shader_dispose(device.Defaults.BatchMaterial.Vertex.Shader)
	}
	if device.Defaults.BatchMaterial.Fragment.Shader != nil {
		shader_dispose(device.Defaults.BatchMaterial.Fragment.Shader)
	}
	if device.Defaults.TexturedMaterial.Vertex.Shader != nil {
		shader_dispose(device.Defaults.TexturedMaterial.Vertex.Shader)
	}
	if device.Defaults.TexturedMaterial.Fragment.Shader != nil {
		shader_dispose(device.Defaults.TexturedMaterial.Fragment.Shader)
	}
	if device.Defaults.MsdfMaterial.Vertex.Shader != nil {
		shader_dispose(device.Defaults.MsdfMaterial.Vertex.Shader)
	}
	if device.Defaults.MsdfMaterial.Fragment.Shader != nil {
		shader_dispose(device.Defaults.MsdfMaterial.Fragment.Shader)
	}
	MaterialDispose(&device.Defaults.BatchMaterial)
	MaterialDispose(&device.Defaults.TexturedMaterial)
	MaterialDispose(&device.Defaults.MsdfMaterial)
	device.Defaults = {}
}
DefaultResourcesDispose :: default_resources_dispose

// Built-in shaders are vendored with the Odin package so it can be relocated.
batcher_vertex_spv :: #load("assets/shaders/Batcher.vertex.spv")
batcher_fragment_spv :: #load("assets/shaders/Batcher.fragment.spv")
batcher_vertex_dxil :: #load("assets/shaders/Batcher.vertex.dxil")
batcher_fragment_dxil :: #load("assets/shaders/Batcher.fragment.dxil")
batcher_vertex_msl :: #load("assets/shaders/Batcher.vertex.msl")
batcher_fragment_msl :: #load("assets/shaders/Batcher.fragment.msl")
textured_vertex_spv :: #load("assets/shaders/Textured.vertex.spv")
textured_fragment_spv :: #load("assets/shaders/Textured.fragment.spv")
textured_vertex_dxil :: #load("assets/shaders/Textured.vertex.dxil")
textured_fragment_dxil :: #load("assets/shaders/Textured.fragment.dxil")
textured_vertex_msl :: #load("assets/shaders/Textured.vertex.msl")
textured_fragment_msl :: #load("assets/shaders/Textured.fragment.msl")
msdf_vertex_spv :: #load("assets/shaders/Msdf.vertex.spv")
msdf_fragment_spv :: #load("assets/shaders/Msdf.fragment.spv")
msdf_vertex_dxil :: #load("assets/shaders/Msdf.vertex.dxil")
msdf_fragment_dxil :: #load("assets/shaders/Msdf.fragment.dxil")
msdf_vertex_msl :: #load("assets/shaders/Msdf.vertex.msl")
msdf_fragment_msl :: #load("assets/shaders/Msdf.fragment.msl")

// ==============================================================================
// Graphics / Defaults / BatcherVertex — 默认批处理顶点
// ==============================================================================

BatcherVertex :: struct #packed {
	Pos:  [2]f32,
	Tex:  [2]f32,
	Col:  Color,
	Mode: Color,
}

identity_matrix_4x4: [16]f32 = [16]f32 {
	1,
	0,
	0,
	0,
	0,
	1,
	0,
	0,
	0,
	0,
	1,
	0,
	0,
	0,
	0,
	1,
}

create_device :: proc(graphics_device: ^GraphicsDevice, flags: AppFlags) {
	when ODIN_OS == .JS {
		// Web: 无 SDL_GPU 设备, Device 用非 nil 占位使现有 nil 守卫成立
		graphics_device.Device = cast(^SDL.GPUDevice)&web_device_placeholder
		graphics_device.Disposed = false
		graphics_device.VSync = true
		graphics_device.ClearColor = ColorToSDL(CornflowerBlue)
		graphics_device.BackbufferSampleCount = .One
		return
	}
	_ = flags
	driver_name: cstring = nil
	#partial switch graphics_device.RequestedDriver {
	case .Private:
		driver_name = "private"
	case .Vulkan:
		driver_name = "vulkan"
	case .D3D12:
		driver_name = "direct3d12"
	case .Metal:
		driver_name = "metal"
	}

	graphics_device.Device = SDL.CreateGPUDevice(
		{.SPIRV, .DXIL, .MSL},
		.GraphicsDebugging in flags,
		driver_name,
	)
	if graphics_device.Device == nil {
		panic(create_error_from_sdl("SDL_CreateGPUDevice"))
	}
	graphics_device.Disposed = false
	graphics_device.VSync = true
	graphics_device.ClearColor = ColorToSDL(CornflowerBlue)
	graphics_device.BackbufferSampleCount = .One
	if .MultiSampledBackBuffer in flags {
		if SDL.GPUTextureSupportsSampleCount(
			graphics_device.Device,
			texture_format_to_sdl(.Color),
			._8,
		) {
			graphics_device.BackbufferSampleCount = .Eight
		} else if SDL.GPUTextureSupportsSampleCount(
			graphics_device.Device,
			texture_format_to_sdl(.Color),
			._4,
		) {
			graphics_device.BackbufferSampleCount = .Four
		} else if SDL.GPUTextureSupportsSampleCount(
			graphics_device.Device,
			texture_format_to_sdl(.Color),
			._2,
		) {
			graphics_device.BackbufferSampleCount = .Two
		}
	}
}

destroy_device :: proc(graphics_device: ^GraphicsDevice) {
	when ODIN_OS == .JS {
		graphics_device.Device = nil
		graphics_device.Disposed = true
		return
	}
	if graphics_device.Device != nil {
		SDL.DestroyGPUDevice(graphics_device.Device)
		graphics_device.Device = nil
	}
	graphics_device.Disposed = true
}

startup_graphics_device :: proc(graphics_device: ^GraphicsDevice, window: ^SDL.Window) {
	when ODIN_OS == .JS {
		// Web: GL 上下文由 foster.js 在 canvas 上创建, 无设备声明/交换链参数
		graphics_device.Window = window // JS 下恒为 nil
		graphics_device.Driver = .Private // 内部 WebGL2 后端
		graphics_device.SupportsMailbox = false
		graphics_device.SwapchainFormat = .R8G8B8A8_UNORM

		graphics_device.WindowRenderTarget = Target{}
		graphics_device.WindowRenderTarget.GraphicsDevice = graphics_device
		graphics_device.WindowRenderTarget.Name = "WindowSwapchain"
		append(
			&graphics_device.WindowRenderTarget.Attachments,
			Texture{GraphicsDevice = graphics_device, Format = .Color},
		)
		graphics_device.HasWindowRenderTarget = true

		default_resources_init(graphics_device)
		return
	}
	graphics_device.Window = window
	driver_name := string(SDL.GetGPUDeviceDriver(graphics_device.Device))
	switch driver_name {
	case "private":
		graphics_device.Driver = .Private
	case "vulkan":
		graphics_device.Driver = .Vulkan
	case "direct3d12":
		graphics_device.Driver = .D3D12
	case "metal":
		graphics_device.Driver = .Metal
	case:
		graphics_device.Driver = .None
	}

	if !SDL.ClaimWindowForGPUDevice(graphics_device.Device, window) {
		panic(create_error_from_sdl("SDL_ClaimWindowForGPUDevice"))
	}
	graphics_device.SupportsMailbox = SDL.WindowSupportsGPUPresentMode(
		graphics_device.Device,
		window,
		.MAILBOX,
	)
	_ = SDL.SetGPUAllowedFramesInFlight(graphics_device.Device, 2)
	present_mode := SDL.GPUPresentMode.VSYNC
	// MAILBOX 在部分 D3D12 驱动上存在资源增长问题, 默认使用 VSYNC
	if false && graphics_device.SupportsMailbox {
		present_mode = .MAILBOX
	}
	_ = SDL.SetGPUSwapchainParameters(graphics_device.Device, window, .SDR, present_mode)
	graphics_device.SwapchainFormat = SDL.GetGPUSwapchainTextureFormat(
		graphics_device.Device,
		window,
	)

	// 窗口渲染目标: 包装每帧获取的 swapchain 纹理, 渲染直通无 blit
	graphics_device.WindowRenderTarget = Target{}
	graphics_device.WindowRenderTarget.GraphicsDevice = graphics_device
	graphics_device.WindowRenderTarget.Name = "WindowSwapchain"
	append(
		&graphics_device.WindowRenderTarget.Attachments,
		Texture{GraphicsDevice = graphics_device, Format = .Color},
	)
	graphics_device.HasWindowRenderTarget = true

	default_resources_init(graphics_device)
}

shutdown_graphics_device :: proc(graphics_device: ^GraphicsDevice) {
	when ODIN_OS == .JS {
		graphics_device_dispose_backbuffer(graphics_device)
		graphics_device_dispose_caches(graphics_device)
		default_resources_dispose(graphics_device)
		graphics_device.Window = nil
		graphics_device.Driver = .None
		return
	}
	if graphics_device.Device != nil && graphics_device.Window != nil {
		_ = SDL.WaitForGPUIdle(graphics_device.Device)
		if graphics_device.UploadStaging != nil {
			SDL.ReleaseGPUTransferBuffer(graphics_device.Device, graphics_device.UploadStaging)
			graphics_device.UploadStaging = nil
			graphics_device.UploadStagingSize = 0
			graphics_device.UploadStagingCursor = 0
		}
		graphics_device_dispose_backbuffer(graphics_device)
		graphics_device_dispose_caches(graphics_device)
		graphics_device_dispose_debug_draw(graphics_device)
		SDL.ReleaseWindowFromGPUDevice(graphics_device.Device, graphics_device.Window)
	}
	default_resources_dispose(graphics_device)
	graphics_device.Window = nil
	graphics_device.Driver = .None
}

present :: proc(graphics_device: ^GraphicsDevice) {
	if !begin_frame(graphics_device) {
		return
	}
	end_frame(graphics_device)
}

// ==============================================================================
// Internal / GraphicsDeviceSDL — 帧与交换链
// ==============================================================================

begin_frame :: proc(graphics_device: ^GraphicsDevice) -> bool {
	when ODIN_OS == .JS {
		if graphics_device.InFrame {
			return false
		}
		if graphics_device.Device == nil {
			return false
		}

		pixel_size := web_window_size_in_pixels()
		graphics_device.CommandBuffer = cast(^SDL.GPUCommandBuffer)&web_cmd_placeholder
		graphics_device.RenderPass = nil
		graphics_device.SwapchainTexture = nil
		graphics_device.SwapchainWidth = u32(pixel_size.X)
		graphics_device.SwapchainHeight = u32(pixel_size.Y)
		graphics_device.InFrame = true
		graphics_device.RenderPassTarget = {}
		graphics_device.RenderPassTargetSize = {}
		graphics_device.RenderPassPipeline = nil
		graphics_device.RenderPassIndexBuffer = nil
		graphics_device.HasRenderPassViewport = false
		graphics_device.HasRenderPassScissor = false
		graphics_device.UploadStagingCursor = 0
		if graphics_device.HasWindowRenderTarget {
			graphics_device.WindowRenderTarget.Width = pixel_size.X
			graphics_device.WindowRenderTarget.Height = pixel_size.Y
			graphics_device.WindowRenderTarget.Bounds = RectInt{0, 0, pixel_size.X, pixel_size.Y}
		}
		// WebGL preserveDrawingBuffer 保留上一帧; 桌面交换链内容不保证保留(discard 语义)。
		// 这里先清一次以对齐桌面语义, 防止游戏未 clear 的帧残留旧画面。
		fw_clear(0, 0, 0, 0)
		return true
	}
	if graphics_device.InFrame {
		return false
	}
	if graphics_device.Device == nil || graphics_device.Window == nil {
		return false
	}

	command_buffer := SDL.AcquireGPUCommandBuffer(graphics_device.Device)
	if command_buffer == nil {
		return false
	}

	graphics_device.CommandBuffer = command_buffer
	graphics_device.RenderPass = nil
	graphics_device.SwapchainTexture = nil
	graphics_device.SwapchainWidth = 0
	graphics_device.SwapchainHeight = 0
	graphics_device.InFrame = true
	graphics_device.RenderPassTarget = {}
	graphics_device.RenderPassTargetSize = {}
	graphics_device.RenderPassPipeline = nil
	graphics_device.RenderPassIndexBuffer = nil
	graphics_device.HasRenderPassViewport = false
	graphics_device.HasRenderPassScissor = false
	graphics_device.UploadStagingCursor = 0

	// 提前获取 swapchain 纹理: 窗口渲染目标直接渲染到交换链 (无中间 blit)
	swapchain_texture: ^SDL.GPUTexture
	width, height: u32
	if !SDL.WaitAndAcquireGPUSwapchainTexture(
		command_buffer,
		graphics_device.Window,
		&swapchain_texture,
		&width,
		&height,
	) {
		graphics_device.InFrame = false
		return false
	}
	graphics_device.SwapchainTexture = swapchain_texture
	graphics_device.SwapchainWidth = width
	graphics_device.SwapchainHeight = height
	if graphics_device.HasWindowRenderTarget {
		graphics_device.WindowRenderTarget.Attachments[0].Resource = swapchain_texture
		graphics_device.WindowRenderTarget.Width = int(width)
		graphics_device.WindowRenderTarget.Height = int(height)
		graphics_device.WindowRenderTarget.Bounds = RectInt{0, 0, int(width), int(height)}
	}
	return true
}

end_frame :: proc(graphics_device: ^GraphicsDevice) {
	if !graphics_device.InFrame {
		return
	}

	when ODIN_OS == .JS {
		graphics_device.RenderPass = nil
		graphics_device.CommandBuffer = nil
		graphics_device.SwapchainTexture = nil
		graphics_device.SwapchainWidth = 0
		graphics_device.SwapchainHeight = 0
		graphics_device.InFrame = false
		graphics_device.RenderPassTarget = {}
		graphics_device.RenderPassTargetSize = {}
		graphics_device.RenderPassPipeline = nil
		graphics_device.RenderPassIndexBuffer = nil
		graphics_device.HasRenderPassViewport = false
		graphics_device.HasRenderPassScissor = false
		fw_end_pass() // 复位 GL 状态(剪刀等)
		fw_present() // WebGL2: rAF 合成即 present
		return
	}

	// 渲染已直接写入 swapchain 纹理: 无需 acquire / blit
	command_buffer := graphics_device.CommandBuffer
	graphics_device.RenderPass = nil
	graphics_device.CommandBuffer = nil
	graphics_device.SwapchainTexture = nil
	graphics_device.SwapchainWidth = 0
	graphics_device.SwapchainHeight = 0
	graphics_device.InFrame = false
	graphics_device.RenderPassTarget = {}
	graphics_device.RenderPassTargetSize = {}
	graphics_device.RenderPassPipeline = nil
	graphics_device.RenderPassIndexBuffer = nil
	graphics_device.HasRenderPassViewport = false
	graphics_device.HasRenderPassScissor = false

	if command_buffer != nil {
		if !SDL.SubmitGPUCommandBuffer(command_buffer) {
			panic(create_error_from_sdl("SDL_SubmitGPUCommandBuffer"))
		}
	}
}

GraphicsDeviceCreateDevice :: create_device
GraphicsDeviceDestroyDevice :: destroy_device
GraphicsDeviceStartup :: startup_graphics_device
GraphicsDeviceShutdown :: shutdown_graphics_device
GraphicsDeviceBeginFrame :: begin_frame
GraphicsDeviceEndFrame :: end_frame
Present :: present
BeginFrame :: begin_frame
EndFrame :: end_frame

graphics_device_dispose_backbuffer :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device == nil || !graphics_device.HasBackbufferTarget {
		return
	}
	target_dispose(&graphics_device.BackbufferTarget)
	graphics_device.BackbufferTarget = Target{}
	graphics_device.BackbufferSize = {}
	graphics_device.HasBackbufferTarget = false
}

graphics_device_ensure_backbuffer :: proc(
	graphics_device: ^GraphicsDevice,
	size: Point2,
	exact: bool,
) {
	if graphics_device == nil || graphics_device.Device == nil {
		return
	}
	if size.X <= 0 || size.Y <= 0 {
		return
	}
	graphics_device.BackbufferSize = size
	if !graphics_device.HasBackbufferTarget {
		specs := [1]TargetAttachmentSpec {
			{Format = .Color, SampleCount = graphics_device.BackbufferSampleCount},
		}
		target_init_with_attachments(
			&graphics_device.BackbufferTarget,
			graphics_device,
			size.X,
			size.Y,
			specs[:],
			"Backbuffer",
		)
		graphics_device.HasBackbufferTarget = true
		return
	}
	target := &graphics_device.BackbufferTarget
	if target.Width < size.X || target.Height < size.Y {
		fmt.println("[bb] recreating backbuffer:", size, " old:", target.Width, "x", target.Height)
		target_dispose(target)
		specs := [1]TargetAttachmentSpec {
			{Format = .Color, SampleCount = graphics_device.BackbufferSampleCount},
		}
		target_init_with_attachments(
			target,
			graphics_device,
			size.X + 64,
			size.Y + 64,
			specs[:],
			"Backbuffer",
		)
		graphics_device.HasBackbufferTarget = true
		return
	}
	if exact && (target.Width > size.X + 128 || target.Height > size.Y + 128) {
		target_dispose(target)
		specs := [1]TargetAttachmentSpec {
			{Format = .Color, SampleCount = graphics_device.BackbufferSampleCount},
		}
		target_init_with_attachments(
			target,
			graphics_device,
			size.X,
			size.Y,
			specs[:],
			"Backbuffer",
		)
		graphics_device.HasBackbufferTarget = true
	}
}

graphics_device_dispose_debug_draw :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device.Device == nil {
		return
	}

	device := graphics_device.Device

	if graphics_device.DebugSampler != nil {
		SDL.ReleaseGPUSampler(device, graphics_device.DebugSampler)
		graphics_device.DebugSampler = nil
	}
	if graphics_device.DebugTexture != nil {
		SDL.ReleaseGPUTexture(device, graphics_device.DebugTexture)
		graphics_device.DebugTexture = nil
	}
	if graphics_device.DebugVertexBuffer != nil {
		SDL.ReleaseGPUBuffer(device, graphics_device.DebugVertexBuffer)
		graphics_device.DebugVertexBuffer = nil
	}
	if graphics_device.DebugPipeline != nil {
		SDL.ReleaseGPUGraphicsPipeline(device, graphics_device.DebugPipeline)
		graphics_device.DebugPipeline = nil
	}
	if graphics_device.DebugVertexShader != nil {
		SDL.ReleaseGPUShader(device, graphics_device.DebugVertexShader)
		graphics_device.DebugVertexShader = nil
	}
	if graphics_device.DebugFragmentShader != nil {
		SDL.ReleaseGPUShader(device, graphics_device.DebugFragmentShader)
		graphics_device.DebugFragmentShader = nil
	}
}

// ------------------------------------------------------------------------------
// Internal / GraphicsDeviceSDL / DebugDraw — 默认绘制资源
// ------------------------------------------------------------------------------

graphics_device_init_debug_draw :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device.Device == nil || graphics_device.Window == nil {
		return
	}
	if graphics_device.DebugPipeline != nil {
		return
	}

	device := graphics_device.Device

	vertex_code: []u8 = nil
	fragment_code: []u8 = nil
	shader_format: SDL.GPUShaderFormat = {}
	#partial switch graphics_device.Driver {
	case .Private, .Vulkan:
		shader_format = {.SPIRV}
		vertex_code = batcher_vertex_spv
		fragment_code = batcher_fragment_spv
	case .D3D12:
		shader_format = {.DXIL}
		vertex_code = batcher_vertex_dxil
		fragment_code = batcher_fragment_dxil
	case .Metal:
		shader_format = {.MSL}
		vertex_code = batcher_vertex_msl
		fragment_code = batcher_fragment_msl
	}
	if len(vertex_code) == 0 || len(fragment_code) == 0 {
		return
	}

	vertex_shader_info := SDL.GPUShaderCreateInfo {
		code_size            = uint(len(vertex_code)),
		code                 = &vertex_code[0],
		entrypoint           = to_cstring("vertex_main"),
		format               = shader_format,
		stage                = .VERTEX,
		num_samplers         = 0,
		num_storage_textures = 0,
		num_storage_buffers  = 0,
		num_uniform_buffers  = 1,
		props                = 0,
	}
	fragment_shader_info := SDL.GPUShaderCreateInfo {
		code_size            = uint(len(fragment_code)),
		code                 = &fragment_code[0],
		entrypoint           = to_cstring("fragment_main"),
		format               = shader_format,
		stage                = .FRAGMENT,
		num_samplers         = 1,
		num_storage_textures = 0,
		num_storage_buffers  = 0,
		num_uniform_buffers  = 0,
		props                = 0,
	}

	graphics_device.DebugVertexShader = SDL.CreateGPUShader(device, vertex_shader_info)
	if graphics_device.DebugVertexShader == nil {
		panic(create_error_from_sdl("SDL_CreateGPUShader", "vertex"))
	}
	graphics_device.DebugFragmentShader = SDL.CreateGPUShader(device, fragment_shader_info)
	if graphics_device.DebugFragmentShader == nil {
		panic(create_error_from_sdl("SDL_CreateGPUShader", "fragment"))
	}

	vertex_stride := u32(size_of(BatcherVertex))
	vb_desc := [1]SDL.GPUVertexBufferDescription {
		{
			slot               = 0,
			pitch              = vertex_stride,
			input_rate         = .VERTEX,
			instance_step_rate = 0,
		},
	}
	attrs := [4]SDL.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = 8},
		{location = 2, buffer_slot = 0, format = .UBYTE4_NORM, offset = 16},
		{location = 3, buffer_slot = 0, format = .UBYTE4_NORM, offset = 20},
	}
	vertex_input := SDL.GPUVertexInputState {
		vertex_buffer_descriptions = &vb_desc[0],
		num_vertex_buffers         = 1,
		vertex_attributes          = &attrs[0],
		num_vertex_attributes      = 4,
	}

	blend_state := SDL.GPUColorTargetBlendState {
		src_color_blendfactor   = .ONE,
		dst_color_blendfactor   = .ZERO,
		color_blend_op          = .ADD,
		src_alpha_blendfactor   = .ONE,
		dst_alpha_blendfactor   = .ZERO,
		alpha_blend_op          = .ADD,
		color_write_mask        = SDL.GPUColorComponentFlags{.R, .G, .B, .A},
		enable_blend            = false,
		enable_color_write_mask = false,
	}
	color_target_desc := [1]SDL.GPUColorTargetDescription {
		{
			format      = graphics_device.SwapchainFormat,
			blend_state = blend_state,
		},
	}
	target_info := SDL.GPUGraphicsPipelineTargetInfo {
		color_target_descriptions = &color_target_desc[0],
		num_color_targets         = 1,
		depth_stencil_format      = .INVALID,
		has_depth_stencil_target  = false,
	}

	stencil_ops := SDL.GPUStencilOpState {
		fail_op       = .KEEP,
		pass_op       = .KEEP,
		depth_fail_op = .KEEP,
		compare_op    = .ALWAYS,
	}
	depth_stencil := SDL.GPUDepthStencilState {
		compare_op          = .ALWAYS,
		back_stencil_state  = stencil_ops,
		front_stencil_state = stencil_ops,
		compare_mask        = 0,
		write_mask          = 0,
		enable_depth_test   = false,
		enable_depth_write  = false,
		enable_stencil_test = false,
	}
	rasterizer := SDL.GPURasterizerState {
		fill_mode                  = .FILL,
		cull_mode                  = .NONE,
		front_face                 = .COUNTER_CLOCKWISE,
		depth_bias_constant_factor = 0,
		depth_bias_clamp           = 0,
		depth_bias_slope_factor    = 0,
		enable_depth_bias          = false,
		enable_depth_clip          = true,
	}
	multisample := SDL.GPUMultisampleState {
		sample_count             = ._1,
		sample_mask              = 0,
		enable_mask              = false,
		enable_alpha_to_coverage = false,
	}

	pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader       = graphics_device.DebugVertexShader,
		fragment_shader     = graphics_device.DebugFragmentShader,
		vertex_input_state  = vertex_input,
		primitive_type      = .TRIANGLELIST,
		rasterizer_state    = rasterizer,
		multisample_state   = multisample,
		depth_stencil_state = depth_stencil,
		target_info         = target_info,
		props               = 0,
	}

	graphics_device.DebugPipeline = SDL.CreateGPUGraphicsPipeline(device, pipeline_info)
	if graphics_device.DebugPipeline == nil {
		panic(create_error_from_sdl("SDL_CreateGPUGraphicsPipeline"))
	}

	sampler_info := SDL.GPUSamplerCreateInfo {
		min_filter        = .LINEAR,
		mag_filter        = .LINEAR,
		mipmap_mode       = .LINEAR,
		address_mode_u    = .CLAMP_TO_EDGE,
		address_mode_v    = .CLAMP_TO_EDGE,
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
	graphics_device.DebugSampler = SDL.CreateGPUSampler(device, sampler_info)
	if graphics_device.DebugSampler == nil {
		panic(create_error_from_sdl("SDL_CreateGPUSampler"))
	}

	tex_info := SDL.GPUTextureCreateInfo {
		type                 = .D2,
		format               = .R8G8B8A8_UNORM,
		usage                = SDL.GPUTextureUsageFlags{.SAMPLER},
		width                = 1,
		height               = 1,
		layer_count_or_depth = 1,
		num_levels           = 1,
		sample_count         = ._1,
		props                = 0,
	}
	graphics_device.DebugTexture = SDL.CreateGPUTexture(device, tex_info)
	if graphics_device.DebugTexture == nil {
		panic(create_error_from_sdl("SDL_CreateGPUTexture"))
	}

	vertex_data_size := u32(size_of(BatcherVertex) * 6)
	vb_info := SDL.GPUBufferCreateInfo {
		usage = SDL.GPUBufferUsageFlags{.VERTEX},
		size  = vertex_data_size,
		props = 0,
	}
	graphics_device.DebugVertexBuffer = SDL.CreateGPUBuffer(device, vb_info)
	if graphics_device.DebugVertexBuffer == nil {
		panic(create_error_from_sdl("SDL_CreateGPUBuffer"))
	}

	transfer_size := u32(512)
	transfer_info := SDL.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size  = transfer_size,
		props = 0,
	}
	transfer := SDL.CreateGPUTransferBuffer(device, transfer_info)
	if transfer == nil {
		panic(create_error_from_sdl("SDL_CreateGPUTransferBuffer"))
	}

	mapped := SDL.MapGPUTransferBuffer(device, transfer, false)
	if mapped == nil {
		SDL.ReleaseGPUTransferBuffer(device, transfer)
		panic(create_error_from_sdl("SDL_MapGPUTransferBuffer"))
	}

	mode := Color{0, 0, 255, 0}
	verts := [6]BatcherVertex {
		{Pos = [2]f32{-0.5, -0.5}, Tex = [2]f32{0, 0}, Col = Red, Mode = mode},
		{Pos = [2]f32{-0.5, 0.5}, Tex = [2]f32{0, 0}, Col = Green, Mode = mode},
		{Pos = [2]f32{0.5, 0.5}, Tex = [2]f32{0, 0}, Col = Blue, Mode = mode},
		{Pos = [2]f32{-0.5, -0.5}, Tex = [2]f32{0, 0}, Col = Red, Mode = mode},
		{Pos = [2]f32{0.5, 0.5}, Tex = [2]f32{0, 0}, Col = Blue, Mode = mode},
		{Pos = [2]f32{0.5, -0.5}, Tex = [2]f32{0, 0}, Col = White, Mode = mode},
	}

	dst := ([^]u8)(mapped)[:int(transfer_size)]
	mem.copy(raw_data(dst), raw_data(verts[:]), int(vertex_data_size))
	tex_offset := 256
	texel := [4]u8{255, 255, 255, 255}
	mem.copy(raw_data(dst[tex_offset:tex_offset + 4]), &texel[0], 4)

	SDL.UnmapGPUTransferBuffer(device, transfer)

	command_buffer := SDL.AcquireGPUCommandBuffer(device)
	if command_buffer == nil {
		SDL.ReleaseGPUTransferBuffer(device, transfer)
		return
	}

	copy_pass := SDL.BeginGPUCopyPass(command_buffer)
	if copy_pass == nil {
		_ = SDL.CancelGPUCommandBuffer(command_buffer)
		SDL.ReleaseGPUTransferBuffer(device, transfer)
		return
	}

	upload_src := SDL.GPUTransferBufferLocation {
		transfer_buffer = transfer,
		offset          = 0,
	}
	upload_dst := SDL.GPUBufferRegion {
		buffer = graphics_device.DebugVertexBuffer,
		offset = 0,
		size   = vertex_data_size,
	}
	SDL.UploadToGPUBuffer(copy_pass, upload_src, upload_dst, false)

	upload_tex_src := SDL.GPUTextureTransferInfo {
		transfer_buffer = transfer,
		offset          = u32(tex_offset),
		pixels_per_row  = 1,
		rows_per_layer  = 1,
	}
	upload_tex_dst := SDL.GPUTextureRegion {
		texture   = graphics_device.DebugTexture,
		mip_level = 0,
		layer     = 0,
		x         = 0,
		y         = 0,
		z         = 0,
		w         = 1,
		h         = 1,
		d         = 1,
	}
	SDL.UploadToGPUTexture(copy_pass, upload_tex_src, upload_tex_dst, false)

	SDL.EndGPUCopyPass(copy_pass)
	if !SDL.SubmitGPUCommandBuffer(command_buffer) {
		SDL.ReleaseGPUTransferBuffer(device, transfer)
		panic(create_error_from_sdl("SDL_SubmitGPUCommandBuffer"))
	}
	_ = SDL.WaitForGPUIdle(device)
	SDL.ReleaseGPUTransferBuffer(device, transfer)
}

draw_test_triangle :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device.Device == nil ||
	   graphics_device.RenderPass == nil ||
	   graphics_device.CommandBuffer == nil {
		return
	}
	if graphics_device.DebugPipeline == nil {
		graphics_device_init_debug_draw(graphics_device)
		if graphics_device.DebugPipeline == nil {
			return
		}
	}

	SDL.SetGPUViewport(graphics_device.RenderPass, SDL.GPUViewport {
		x         = 0,
		y         = 0,
		w         = f32(graphics_device.SwapchainWidth),
		h         = f32(graphics_device.SwapchainHeight),
		min_depth = 0,
		max_depth = 1,
	})

	SDL.PushGPUVertexUniformData(
		graphics_device.CommandBuffer,
		0,
		raw_data(identity_matrix_4x4[:]),
		64,
	)

	SDL.BindGPUGraphicsPipeline(graphics_device.RenderPass, graphics_device.DebugPipeline)

	vb_bindings := [1]SDL.GPUBufferBinding {
		{buffer = graphics_device.DebugVertexBuffer, offset = 0},
	}
	SDL.BindGPUVertexBuffers(graphics_device.RenderPass, 0, &vb_bindings[0], 1)

	ts_bindings := [1]SDL.GPUTextureSamplerBinding {
		{texture = graphics_device.DebugTexture, sampler = graphics_device.DebugSampler},
	}
	SDL.BindGPUFragmentSamplers(graphics_device.RenderPass, 0, &ts_bindings[0], 1)

	SDL.DrawGPUPrimitives(graphics_device.RenderPass, 3, 1, 0, 0)
}

DrawTestTriangle :: draw_test_triangle

draw_test_quad :: proc(graphics_device: ^GraphicsDevice) {
	if graphics_device.Device == nil ||
	   graphics_device.RenderPass == nil ||
	   graphics_device.CommandBuffer == nil {
		return
	}
	if graphics_device.DebugPipeline == nil {
		graphics_device_init_debug_draw(graphics_device)
		if graphics_device.DebugPipeline == nil {
			return
		}
	}

	SDL.SetGPUViewport(graphics_device.RenderPass, SDL.GPUViewport {
		x         = 0,
		y         = 0,
		w         = f32(graphics_device.SwapchainWidth),
		h         = f32(graphics_device.SwapchainHeight),
		min_depth = 0,
		max_depth = 1,
	})

	SDL.PushGPUVertexUniformData(
		graphics_device.CommandBuffer,
		0,
		raw_data(identity_matrix_4x4[:]),
		64,
	)

	SDL.BindGPUGraphicsPipeline(graphics_device.RenderPass, graphics_device.DebugPipeline)

	vb_bindings := [1]SDL.GPUBufferBinding {
		{buffer = graphics_device.DebugVertexBuffer, offset = 0},
	}
	SDL.BindGPUVertexBuffers(graphics_device.RenderPass, 0, &vb_bindings[0], 1)

	ts_bindings := [1]SDL.GPUTextureSamplerBinding {
		{texture = graphics_device.DebugTexture, sampler = graphics_device.DebugSampler},
	}
	SDL.BindGPUFragmentSamplers(graphics_device.RenderPass, 0, &ts_bindings[0], 1)

	SDL.DrawGPUPrimitives(graphics_device.RenderPass, 6, 1, 0, 0)
}

DrawTestQuad :: draw_test_quad

WindowCallback :: #type proc(window: ^Window)
AppCallback :: #type proc(app: ^App)

// ==============================================================================
// Window — 窗口状态
// ==============================================================================

Window :: struct {
	Handle:         ^SDL.Window,
	ID:             SDL.WindowID,
	Title:          string,
	App:            ^App,
	GraphicsDevice: ^GraphicsDevice,

	OnFocusGain:       WindowCallback,
	OnFocusLost:       WindowCallback,
	OnMouseEnter:      WindowCallback,
	OnMouseLeave:      WindowCallback,
	OnResize:          WindowCallback,
	OnRestore:         WindowCallback,
	OnMaximize:        WindowCallback,
	OnMinimize:        WindowCallback,
	OnFullscreenEnter: WindowCallback,
	OnFullscreenExit:  WindowCallback,
	OnCloseRequested:  WindowCallback,
}

// ==============================================================================
// App — 配置、状态与回调
// ==============================================================================

AppConfig :: struct {
	ApplicationName:         string,
	WindowTitle:             string,
	Width:                   int,
	Height:                  int,
	Fullscreen:              bool,
	Resizable:               bool,
	UpdateMode:              UpdateMode,
	PreferredGraphicsDriver: GraphicsDriver,
	Flags:                   AppFlags,
}

default_app_config :: proc(name: string, width, height: int) -> AppConfig {
	return AppConfig {
		ApplicationName         = name,
		WindowTitle             = name,
		Width                   = width,
		Height                  = height,
		Resizable               = true,
		UpdateMode              = fixed_step_fps(60),
		PreferredGraphicsDriver = .None,
		Flags                   = {},
	}
}

DefaultAppConfig :: default_app_config

App :: struct {
	Config:          AppConfig,
	Name:            string,
	Time:            Time,
	UpdateMode:      UpdateMode,
	Window:          Window,
	Input:           Input,
	GraphicsDevice:  GraphicsDevice,
	FileSystem:      FileSystem,
	Running:         bool,
	Exiting:         bool,
	Disposed:        bool,
	UserPath:        string,
	// Optional pointer to application-owned state. This is the Odin equivalent
	// of putting game fields on a Foster App subclass.
	UserData:        rawptr,
	OnExitRequested: AppCallback,

	StartupProc:  AppCallback,
	ShutdownProc: AppCallback,
	UpdateProc:   AppCallback,
	RenderProc:   AppCallback,

	main_thread_id:    int,
	main_thread_queue: [dynamic]AppCallback,
	timer:             coretime.Stopwatch,
	last_update_time:  coretime.Duration,
	fixed_accumulator: coretime.Duration,
}

to_cstring :: proc(s: string) -> cstring {
	cstr, _ := strings.clone_to_cstring(s, context.temp_allocator)
	return cstr
}

create_error_from_sdl :: proc(sdl_method: string, foster_info := "") -> string {
	if foster_info != "" {
		return fmt.aprintf("%s. %s failed: %s", foster_info, sdl_method, string(SDL.GetError()))
	}
	return fmt.aprintf("%s failed: %s", sdl_method, string(SDL.GetError()))
}

CreateExceptionFromSDL :: create_error_from_sdl

// ==============================================================================
// Window / Lifecycle — 创建、属性与释放
// ==============================================================================

window_init :: proc(
	window: ^Window,
	app: ^App,
	graphics_device: ^GraphicsDevice,
	config: AppConfig,
) {
	window.App = app
	window.GraphicsDevice = graphics_device
	window.Title = config.WindowTitle

	when ODIN_OS == .JS {
		// canvas 即窗口: foster.js 定位 canvas、创建 WebGL2 上下文并设置标题
		title := config.WindowTitle
		title_bytes := transmute([]byte)title
		if !fw_init(&title_bytes[0], i32(len(title_bytes))) {
			panic("foster_web init failed: canvas 或 WebGL2 上下文不可用")
		}
		window.Handle = nil
		window.ID = 1
		return
	}

	flags := SDL.WINDOW_HIGH_PIXEL_DENSITY + SDL.WINDOW_HIDDEN
	if config.Fullscreen {
		flags += SDL.WINDOW_FULLSCREEN
	}
	if config.Resizable {
		flags += SDL.WINDOW_RESIZABLE
	}

	window.Handle = SDL.CreateWindow(
		to_cstring(config.WindowTitle),
		c.int(config.Width),
		c.int(config.Height),
		flags,
	)
	if window.Handle == nil {
		panic(create_error_from_sdl("SDL_CreateWindow"))
	}

	window.ID = SDL.GetWindowID(window.Handle)
}

window_close :: proc(window: ^Window) {
	when ODIN_OS == .JS {
		// canvas 生命周期由页面管理
		_ = window
		return
	}
	if window.Handle != nil {
		SDL.DestroyWindow(window.Handle)
		window.Handle = nil
	}
}

window_show :: proc(window: ^Window) {
	when ODIN_OS == .JS {
		_ = window // canvas 始终可见
		return
	}
	if window.Handle == nil {
		return
	}
	_ = SDL.ShowWindow(window.Handle)
	_ = SDL.SetWindowBordered(window.Handle, true)
	_ = SDL.RaiseWindow(window.Handle)
	_ = SDL.ShowCursor()
}

window_hide :: proc(window: ^Window) {
	when ODIN_OS == .JS {
		_ = window
		return
	}
	if window.Handle != nil {
		_ = SDL.HideWindow(window.Handle)
	}
}

window_focus :: proc(window: ^Window) {
	when ODIN_OS == .JS {
		_ = window
		return
	}
	if window.Handle != nil {
		_ = SDL.RaiseWindow(window.Handle)
	}
}

window_size :: proc(window: ^Window) -> Point2 {
	when ODIN_OS == .JS {
		_ = window
		return web_window_size()
	}
	if window.Handle == nil {
		return Point2Zero
	}
	w, h: int
	cw, ch: c.int
	_ = SDL.GetWindowSize(window.Handle, &cw, &ch)
	w = int(cw)
	h = int(ch)
	return Point2{w, h}
}

window_size_in_pixels :: proc(window: ^Window) -> Point2 {
	when ODIN_OS == .JS {
		_ = window
		return web_window_size_in_pixels()
	}
	if window.Handle == nil {
		return Point2Zero
	}
	cw, ch: c.int
	_ = SDL.GetWindowSizeInPixels(window.Handle, &cw, &ch)
	return Point2{int(cw), int(ch)}
}

window_position :: proc(window: ^Window) -> Point2 {
	if window.Handle == nil {
		return Point2Zero
	}
	cx, cy: c.int
	_ = SDL.GetWindowPosition(window.Handle, &cx, &cy)
	return Point2{int(cx), int(cy)}
}

window_set_position :: proc(window: ^Window, value: Point2) {
	if window.Handle != nil {
		_ = SDL.SetWindowPosition(window.Handle, c.int(value.X), c.int(value.Y))
	}
}

window_set_size :: proc(window: ^Window, value: Point2) {
	when ODIN_OS == .JS {
		// Web: canvas 布局由页面控制, 逻辑尺寸跟随视口, 忽略显式设置
		_ = window
		_ = value
		return
	}
	if window.Handle != nil {
		_ = SDL.SetWindowSize(window.Handle, c.int(value.X), c.int(value.Y))
	}
}

window_focused :: proc(window: ^Window) -> bool {
	if window.Handle == nil {
		return false
	}
	flags := SDL.GetWindowFlags(window.Handle)
	return .INPUT_FOCUS in flags || .MOUSE_FOCUS in flags
}

window_fullscreen :: proc(window: ^Window) -> bool {
	when ODIN_OS == .JS {
		_ = window
		return fw_is_fullscreen() != 0
	}
	if window.Handle == nil {
		return false
	}
	return .FULLSCREEN in SDL.GetWindowFlags(window.Handle)
}

window_set_fullscreen :: proc(window: ^Window, value: bool) {
	when ODIN_OS == .JS {
		// 全屏 = 页面 Fullscreen API(需用户手势上下文, 由按键路径调用时自然满足)
		_ = window
		fw_set_fullscreen(value ? 1 : 0)
		return
	}
	if window.Handle != nil {
		_ = SDL.SetWindowFullscreen(window.Handle, value)
	}
}

window_resizable :: proc(window: ^Window) -> bool {
	if window.Handle == nil {
		return false
	}
	return .RESIZABLE in SDL.GetWindowFlags(window.Handle)
}

window_set_resizable :: proc(window: ^Window, value: bool) {
	if window.Handle != nil {
		_ = SDL.SetWindowResizable(window.Handle, value)
	}
}

window_maximized :: proc(window: ^Window) -> bool {
	if window.Handle == nil {
		return false
	}
	return .MAXIMIZED in SDL.GetWindowFlags(window.Handle)
}

window_set_title :: proc(window: ^Window, title: string) {
	window.Title = title
	if window.Handle != nil {
		_ = SDL.SetWindowTitle(window.Handle, to_cstring(title))
	}
}

window_content_scale :: proc(window: ^Window) -> f32 {
	if window.Handle == nil {
		return 1
	}
	scale := SDL.GetWindowDisplayScale(window.Handle)
	if scale <= 0 {
		return 1
	}
	return scale
}

window_display_size :: proc(window: ^Window) -> Point2 {
	if window.Handle == nil {
		return Point2Zero
	}
	display_id := SDL.GetDisplayForWindow(window.Handle)
	mode := SDL.GetCurrentDisplayMode(display_id)
	if mode == nil {
		return Point2Zero
	}
	return Point2{int(mode.w), int(mode.h)}
}

window_set_mouse_visible :: proc(window: ^Window, enabled: bool) {
	when ODIN_OS == .JS {
		fw_cursor_visible(enabled)
		return
	}
	_ = window
	if enabled == SDL.CursorVisible() {
		return
	}
	if enabled {
		_ = SDL.ShowCursor()
	} else {
		_ = SDL.HideCursor()
	}
}

window_set_mouse_relative_mode :: proc(window: ^Window, enabled: bool) {
	when ODIN_OS == .JS {
		// Pointer Lock API; 锁定时的增量由 movementX/Y 累积成虚拟坐标
		fw_set_mouse_relative(enabled ? 1 : 0)
		return
	}
	if window.Handle == nil {
		return
	}
	if enabled == SDL.GetWindowRelativeMouseMode(window.Handle) {
		return
	}
	_ = SDL.SetWindowRelativeMouseMode(window.Handle, enabled)
	size := window_size(window)
	SDL.WarpMouseInWindow(window.Handle, f32(size.X) / 2, f32(size.Y) / 2)
}

window_set_mouse_position :: proc(window: ^Window, x, y: f32) {
	if window.Handle != nil {
		SDL.WarpMouseInWindow(window.Handle, x, y)
	}
}

AppSetUserData :: proc(app: ^App, data: rawptr) {
	if app != nil {
		app.UserData = data
	}
}

AppGetUserData :: proc(app: ^App) -> rawptr {
	if app == nil {
		return nil
	}
	return app.UserData
}

window_set_mouse_cursor :: proc(window: ^Window, cursor: ^SDL.Cursor) {
	when ODIN_OS == .JS {
		_ = fw_cursor_set(web_handle_u32(cursor))
		return
	}
	_ = window
	if cursor == nil {
		_ = SDL.SetCursor(SDL.GetDefaultCursor())
	} else {
		_ = SDL.SetCursor(cursor)
	}
}

window_start_text_input :: proc(window: ^Window) {
	when ODIN_OS == .JS {
		fw_text_input(true)
		return
	}
	if window.Handle != nil && !SDL.TextInputActive(window.Handle) {
		_ = SDL.StartTextInput(window.Handle)
	}
}

window_stop_text_input :: proc(window: ^Window) {
	when ODIN_OS == .JS {
		fw_text_input(false)
		return
	}
	if window.Handle != nil && SDL.TextInputActive(window.Handle) {
		_ = SDL.StopTextInput(window.Handle)
	}
}

window_set_text_input :: proc(window: ^Window, enabled: bool) {
	if enabled {
		window_start_text_input(window)
	} else {
		window_stop_text_input(window)
	}
}

window_on_event :: proc(window: ^Window, event_type: SDL.EventType) {
	#partial switch event_type {
	case .WINDOW_FOCUS_GAINED:
		if window.OnFocusGain != nil {
			window.OnFocusGain(window)
		}
	case .WINDOW_FOCUS_LOST:
		if window.OnFocusLost != nil {
			window.OnFocusLost(window)
		}
	case .WINDOW_MOUSE_ENTER:
		if window.OnMouseEnter != nil {
			window.OnMouseEnter(window)
		}
	case .WINDOW_MOUSE_LEAVE:
		if window.OnMouseLeave != nil {
			window.OnMouseLeave(window)
		}
	case .WINDOW_RESIZED:
		if window.OnResize != nil {
			window.OnResize(window)
		}
	case .WINDOW_RESTORED:
		if window.OnRestore != nil {
			window.OnRestore(window)
		}
	case .WINDOW_MAXIMIZED:
		if window.OnMaximize != nil {
			window.OnMaximize(window)
		}
	case .WINDOW_MINIMIZED:
		if window.OnMinimize != nil {
			window.OnMinimize(window)
		}
	case .WINDOW_ENTER_FULLSCREEN:
		if window.OnFullscreenEnter != nil {
			window.OnFullscreenEnter(window)
		}
	case .WINDOW_LEAVE_FULLSCREEN:
		if window.OnFullscreenExit != nil {
			window.OnFullscreenExit(window)
		}
	case .WINDOW_CLOSE_REQUESTED:
		if window.OnCloseRequested != nil {
			window.OnCloseRequested(window)
		} else if window.App != nil {
			exit(window.App)
		}
	}
}

Width :: proc(window: ^Window) -> int {
	return window_size(window).X
}

Height :: proc(window: ^Window) -> int {
	return window_size(window).Y
}
Size :: window_size
SizeInPixels :: window_size_in_pixels
Position :: window_position
DisplaySize :: window_display_size
ContentScale :: window_content_scale
Focused :: window_focused
Fullscreen :: window_fullscreen
Resizable :: window_resizable
Maximized :: window_maximized
Show :: window_show
Hide :: window_hide
Close :: window_close
Focus :: window_focus
SetWindowSize :: window_set_size
SetWindowFullscreen :: window_set_fullscreen
SetWindowResizable :: window_set_resizable
SetMouseVisible :: window_set_mouse_visible
SetMouseRelativeMode :: window_set_mouse_relative_mode
SetMousePosition :: window_set_mouse_position
SetMouseCursor :: window_set_mouse_cursor
StartTextInput :: window_start_text_input
StopTextInput :: window_stop_text_input
SetTextInput :: window_set_text_input
OnEvent :: window_on_event

// ==============================================================================
// App / Lifecycle — 初始化与释放
// ==============================================================================

init_app :: proc(app: ^App, config: AppConfig) {
	if config.Width <= 0 || config.Height <= 0 {
		panic("Width or height is <= 0")
	}
	if strings.trim_space(config.ApplicationName) == "" {
		panic("Invalid Application Name")
	}

	app.Config = config
	app.Name = config.ApplicationName
	app.UpdateMode = config.UpdateMode
	app.GraphicsDevice.RequestedDriver = config.PreferredGraphicsDriver
	app.main_thread_id = platform_current_thread_id()

	fmt.println("Foster:", version_string())
	when ODIN_OS == .JS {
		fmt.println("SDL: web backend (js_wasm32)")
	} else {
		fmt.println("SDL:", sdl_version_string())
		_ = SDL.SetHint(SDL.HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1")

		init_flags := SDL.INIT_VIDEO + SDL.INIT_EVENTS + SDL.INIT_JOYSTICK + SDL.INIT_GAMEPAD
		if !SDL.Init(init_flags) {
			panic(create_error_from_sdl("SDL_Init"))
		}
	}

	create_device(&app.GraphicsDevice, config.Flags)
	window_init(&app.Window, app, &app.GraphicsDevice, config)
	startup_graphics_device(&app.GraphicsDevice, app.Window.Handle)
	when ODIN_OS != .JS {
		graphics_device_init_debug_draw(&app.GraphicsDevice)
	}
	file_system_init(&app.FileSystem, app)
	input_init(&app.Input, app)

	when ODIN_OS == .JS {
		app.UserPath = web_user_path(app.Name) // M4: 接虚拟文件系统
	} else {
		user_path := SDL.GetPrefPath("", to_cstring(config.ApplicationName))
		if user_path != nil {
			app.UserPath = string(cstring(user_path))
		}
	}
}

dispose_app :: proc(app: ^App) {
	if app.Disposed {
		return
	}
	if app.Running {
		panic("Cannot dispose App while running")
	}

	shutdown_graphics_device(&app.GraphicsDevice)
	input_close_devices(&app.Input)
	when ODIN_OS == .JS {
		web_storage_shutdown()
		delete(web_clipboard_callbacks)
		web_clipboard_callbacks = nil
	}
	window_close(&app.Window)
	destroy_device(&app.GraphicsDevice)
	when ODIN_OS != .JS {
		SDL.Quit()
	}
	app.Disposed = true
}

is_main_thread :: proc(app: ^App) -> bool {
	return platform_current_thread_id() == app.main_thread_id
}

run_on_main_thread :: proc(app: ^App, action: AppCallback) {
	if action == nil {
		return
	}
	if app.Running && is_main_thread(app) {
		action(app)
		return
	}
	append(&app.main_thread_queue, action)
}

drain_main_thread_queue :: proc(app: ^App) {
	for len(app.main_thread_queue) > 0 {
		action := app.main_thread_queue[0]
		ordered_remove(&app.main_thread_queue, 0)
		if action != nil {
			action(app)
		}
	}
}

// ==============================================================================
// App / Events — 原生与 Web 事件分发
// ==============================================================================

poll_events :: proc(app: ^App) {
	when ODIN_OS == .JS {
		// 事件来源替换为 foster.js 的 DOM 事件队列; 窗口事件映射为 SDL.EventType
		// 枚举值复用 window_on_event(纯枚举分派, 无 SDL 调用); 输入事件直接派发
		// 到现有 input_* 入口(Keys 值与 SDL scancode 一致, 无需伪造 SDL.Event)
		web_event: WebEvent
		for fw_poll_event(&web_event) {
			#partial switch web_event.Kind {
			case .Quit:
				if app.Running && !app.Exiting {
					if app.OnExitRequested != nil {
						app.OnExitRequested(app)
					} else {
						exit(app)
					}
				}
			case .WindowResized:
				window_on_event(&app.Window, .WINDOW_RESIZED)
			case .WindowFocusGained:
				window_on_event(&app.Window, .WINDOW_FOCUS_GAINED)
			case .WindowFocusLost:
				window_on_event(&app.Window, .WINDOW_FOCUS_LOST)
			case .KeyDown:
				if web_event.B == 0 {
					input_key(&app.Input, cast(Keys)web_event.A, true, app.Time.Elapsed)
				}
			case .KeyUp:
				if web_event.B == 0 {
					input_key(&app.Input, cast(Keys)web_event.A, false, app.Time.Elapsed)
				}
			case .MouseMove:
				position := Vec2f{web_event.F, web_event.G}
				delta := Vec2f {
					position.X - app.Input.last_mouse.X,
					position.Y - app.Input.last_mouse.Y,
				}
				if position.X != app.Input.last_mouse.X ||
				   position.Y != app.Input.last_mouse.Y ||
				   delta.X != 0 ||
				   delta.Y != 0 {
					app.Input.last_mouse = position
					input_mouse_move(&app.Input, position, delta, app.Time.Elapsed)
				}
			case .MouseButtonDown:
				// 桌面靠 input_update 轮询坐标; Web 禁用轮询, 按事件自带坐标更新位置
				position := Vec2f{web_event.F, web_event.G}
				app.Input.last_mouse = position
				input_mouse_move(&app.Input, position, Vec2f{0, 0}, app.Time.Elapsed)
				input_mouse_button(
					&app.Input,
					cast(MouseButtons)web_event.A,
					true,
					app.Time.Elapsed,
				)
			case .MouseButtonUp:
				input_mouse_button(
					&app.Input,
					cast(MouseButtons)web_event.A,
					false,
					app.Time.Elapsed,
				)
			case .MouseWheel:
				input_mouse_wheel(&app.Input, Vec2f{web_event.F, web_event.G})
			case .TextInput:
				input_text(&app.Input, web_event_text(), &app.Window)
			case .ControllerConnected:
				name := web_event_text(context.allocator)
				append(&app.Input.owned_controller_names, name)
				input_connect_controller(
					&app.Input,
					ControllerID(web_event.A),
					name,
					int(web_event.B),
					int(web_event.C),
					web_event.F != 0,
					web_event.F != 0 ? .Standard : .Unknown,
					0,
					0,
					0,
				)
			case .ControllerDisconnected:
				input_disconnect_controller(&app.Input, ControllerID(web_event.A))
			case .ControllerButtonDown, .ControllerButtonUp:
				input_controller_button(
					&app.Input,
					ControllerID(web_event.A),
					int(web_event.B),
					web_event.Kind == .ControllerButtonDown,
					app.Time.Elapsed,
				)
			case .ControllerAxis:
				input_controller_axis(
					&app.Input,
					ControllerID(web_event.A),
					int(web_event.B),
					web_event.F,
					app.Time.Elapsed,
				)
			case .DialogResult:
				web_dialog_complete(u32(web_event.A), web_event.B != 0)
			case .StorageFlushResult:
				web_storage_complete(u32(web_event.A), web_event.B != 0)
			case .ClipboardResult:
				web_clipboard_complete(u32(web_event.A), web_event.B != 0)
			}
		}
		return
	}

	SDL.PumpEvents()

	event: SDL.Event
	for SDL.PollEvent(&event) && event.type != .POLL_SENTINEL {
		#partial switch event.type {
		case .QUIT:
			if app.Running && !app.Exiting {
				if app.OnExitRequested != nil {
					app.OnExitRequested(app)
				} else {
					exit(app)
				}
			}
		case .WINDOW_FOCUS_GAINED,
		     .WINDOW_FOCUS_LOST,
		     .WINDOW_MOUSE_ENTER,
		     .WINDOW_MOUSE_LEAVE,
		     .WINDOW_RESIZED,
		     .WINDOW_RESTORED,
		     .WINDOW_MAXIMIZED,
		     .WINDOW_MINIMIZED,
		     .WINDOW_ENTER_FULLSCREEN,
		     .WINDOW_LEAVE_FULLSCREEN,
		     .WINDOW_CLOSE_REQUESTED:
			if event.window.windowID == app.Window.ID {
				window_on_event(&app.Window, event.type)
			}
		case .MOUSE_BUTTON_DOWN,
		     .MOUSE_BUTTON_UP,
		     .MOUSE_WHEEL,
		     .KEY_DOWN,
		     .KEY_UP,
		     .TEXT_INPUT,
		     .JOYSTICK_ADDED,
		     .JOYSTICK_REMOVED,
		     .JOYSTICK_BUTTON_DOWN,
		     .JOYSTICK_BUTTON_UP,
		     .JOYSTICK_AXIS_MOTION,
		     .GAMEPAD_ADDED,
		     .GAMEPAD_REMOVED,
		     .GAMEPAD_BUTTON_DOWN,
		     .GAMEPAD_BUTTON_UP,
		     .GAMEPAD_AXIS_MOTION:
			input_on_event(&app.Input, &app.Window, &event, app.Time.Elapsed)
		}
	}
}

step_app :: proc(app: ^App, delta: coretime.Duration) {
	app.Time = advance_time(app.Time, delta)

	when ODIN_OS != .JS {
		if SDL.GetWindowRelativeMouseMode(app.Window.Handle) && window_focused(&app.Window) {
			SDL.WarpMouseInWindow(
				app.Window.Handle,
				f32(Width(&app.Window)) / 2,
				f32(Height(&app.Window)) / 2,
			)
		}
	}

	input_step(&app.Input, app.Time)
	input_update(&app.Input, &app.Window, app.Time.Elapsed)
	poll_events(app)
	drain_main_thread_queue(app)

	if app.UpdateProc != nil {
		app.UpdateProc(app)
	}
}

tick_app :: proc(app: ^App) {
	delta_time: coretime.Duration
	when ODIN_OS == .JS {
		// 帧步长来自 foster.js 的 rAF 时间差(见 web.odin 的 foster_step)
		delta_time = web_take_frame_delta()
	} else {
		current_time := coretime.stopwatch_duration(app.timer)
		delta_time = current_time - app.last_update_time
		app.last_update_time = current_time
	}

	switch app.UpdateMode.Mode {
	case .Fixed:
		app.fixed_accumulator += delta_time

		when ODIN_OS != .JS {
			// JS 下 rAF 已按显示节奏驱动, 不能在 FixedWaitEnabled 里 sleep 阻塞主线程
			if app.UpdateMode.FixedWaitEnabled {
				for app.fixed_accumulator < app.UpdateMode.FixedTargetTime {
					coretime.sleep(app.UpdateMode.FixedTargetTime - app.fixed_accumulator)
					now := coretime.stopwatch_duration(app.timer)
					delta_time = now - app.last_update_time
					app.last_update_time = now
					app.fixed_accumulator += delta_time
				}
			}
		}

		if app.fixed_accumulator > app.UpdateMode.FixedMaxTime {
			app.fixed_accumulator = app.UpdateMode.FixedMaxTime
		}

		for app.fixed_accumulator >= app.UpdateMode.FixedTargetTime {
			app.fixed_accumulator -= app.UpdateMode.FixedTargetTime
			step_app(app, app.UpdateMode.FixedTargetTime)
			if app.Exiting {
				break
			}
		}
	case .Unlocked:
		step_app(app, delta_time)
	}

	app.Time = advance_render_frame(app.Time)
	if begin_frame(&app.GraphicsDevice) {
		if app.RenderProc != nil {
			app.RenderProc(app)
		}
		end_frame(&app.GraphicsDevice)
	} else if app.RenderProc != nil {
		app.RenderProc(app)
	}
	// [olib L-001] 每帧末尾清空临时分配器：Update/Render 中的临时分配到下一帧失效。
	// Startup 中的临时分配在第一帧结束时失效；清理在 RenderProc 和 end_frame 之后执行。
	free_all(context.temp_allocator)
}

// ==============================================================================
// App / MainLoop — 更新、渲染与退出
// ==============================================================================

run :: proc(app: ^App) {
	when ODIN_OS == .JS {
		// 尽早把 App 搬到堆上: StartupProc 里初始化的游戏对象(Batcher 等)
		// 会持有 &app.GraphicsDevice, 栈上 main 返回后即失效
		run_impl(web_relocate_app(app))
	} else {
		run_impl(app)
	}
}

run_impl :: proc(app: ^App) {
	if app.Disposed {
		panic("Application is disposed")
	}
	if app.Running {
		panic("Application is already running")
	}
	if app.Exiting {
		panic("Application is still exiting")
	}

	app.Running = true
	app.Time = {}
	app.last_update_time = 0
	app.fixed_accumulator = 0
	when ODIN_OS != .JS {
		coretime.stopwatch_reset(&app.timer)
		coretime.stopwatch_start(&app.timer)
	}

	poll_events(app)
	input_step(&app.Input, app.Time)
	window_show(&app.Window)

	if app.StartupProc != nil {
		app.StartupProc(app)
	}

	when ODIN_OS == .JS {
		// main 返回即"进入事件循环"; 后续帧由 foster.js 的 rAF 调用导出的 foster_step 驱动,
		// 退出时的收尾(ShutdownProc 等)在 foster_step 检测到 Exiting 后执行(见 web.odin)
		web_enter_run_loop(app)
		return
	}

	for !app.Exiting {
		tick_app(app)
	}
	run_finish(app)
}

run_finish :: proc(app: ^App) {
	drain_main_thread_queue(app)

	if app.ShutdownProc != nil {
		app.ShutdownProc(app)
	}

	window_hide(&app.Window)
	app.Running = false
	app.Exiting = false
}

exit :: proc(app: ^App) {
	if app.Running {
		app.Exiting = true
	}
}

Now :: proc(app: ^App) -> coretime.Duration {
	return coretime.stopwatch_duration(app.timer)
}

InitApp :: init_app
Dispose :: dispose_app
IsMainThread :: is_main_thread
RunOnMainThread :: run_on_main_thread
PollEvents :: poll_events
Tick :: tick_app
Run :: run
Exit :: exit
