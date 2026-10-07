#+build js wasm32, js wasm64p32

package foster_framework

// Web 后端桥：生命周期、WebGL2、输入、剪贴板、文件选择与虚拟存储。
// 桥接模式沿用 vehicles/web-spike 已验证方案:
//   - foreign import "foster_web" + contextless 声明, 参数只用原始类型
//   - JS 侧手动实例化 wasm 并持有 memory(见 internal/web/foster.js)
//   - 帧循环由 JS requestAnimationFrame 驱动导出的 foster_step
// 桌面平台不编译本文件; framework.odin 里的 `when ODIN_OS == .JS`
// 分支引用此处符号, 分支外代码永不触碰 SDL 调用(未调用的 SDL proc 不进 wasm 导入表)。

import "core:fmt"
import "core:strings"
import json "core:encoding/json"
import coretime "core:time"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Platform / Web / Imports — JavaScript 桥接口
//   Platform / Web / Graphics — 图形句柄与枚举转换
//   Platform / Web / Events — 事件桥
//   Platform / Web / Lifecycle — App 生命周期与帧循环

// ==============================================================================
// Platform / Web / Imports — JavaScript 桥接口
// ==============================================================================

foreign import foster_web_lib "foster_web"

@(default_calling_convention = "contextless")
foreign foster_web_lib {
	fw_init :: proc(title_ptr: rawptr, title_len: i32) -> bool ---
	fw_canvas_size :: proc(w: ^i32, h: ^i32) ---
	fw_canvas_pixel_size :: proc(w: ^i32, h: ^i32) ---
	fw_set_title :: proc(title_ptr: rawptr, title_len: i32) ---
	fw_clear :: proc(r, g, b, a: f32) ---
	fw_present :: proc() ---
	fw_poll_event :: proc(ev: ^WebEvent) -> bool ---
	fw_log :: proc(msg_ptr: rawptr, msg_len: i32) ---
	fw_event_text :: proc(destination: rawptr, capacity: i32) -> i32 ---
	fw_text_input :: proc(enabled: bool) ---
	fw_cursor_system :: proc(kind: u32) -> u32 ---
	fw_cursor_image :: proc(pixels: rawptr, width, height, x, y: i32) -> u32 ---
	fw_cursor_set :: proc(handle: u32) -> bool ---
	fw_cursor_release :: proc(handle: u32) ---
	fw_cursor_visible :: proc(visible: bool) ---
	fw_rumble :: proc(id: u32, low, high, duration: f32) ---
	fw_clipboard_cached :: proc(destination: rawptr, capacity: i32) -> i32 ---
	fw_image_write_png :: proc(path: rawptr, length, width, height: i32, pixels: rawptr) -> bool ---
	fw_dialog_start :: proc(request, kind: u32, filters: rawptr, length: i32) ---
	fw_fs_flush :: proc(request: u32, path: rawptr, length: i32) ---
	fw_clipboard_read :: proc(request: u32) ---
	fw_clipboard_write :: proc(request: u32, text: rawptr, length: i32) -> bool ---
}

// ------------------------------------------------------------------------------
// Platform / Web / Imports / Graphics — WebGL2 图形桥
// ------------------------------------------------------------------------------
// GL 对象在 foster.js 的句柄表里, 句柄 = 表索引(1 起, 0 = 空)。
// Odin 侧把句柄存进 SDL 的 ^GPUXxx 指针字段(u32 值转指针)。

// 保留较长桥接口的参数分组，避免格式化器将 foreign proc 参数合并为一行。


// odinfmt: disable
@(default_calling_convention = "contextless")
foreign foster_web_lib {
	fw_gl_create_shader :: proc(stage: u32, code_ptr: rawptr, code_len: i32) -> u32 ---
	fw_gl_release_shader :: proc(handle: u32) ---
	fw_gl_create_pipeline :: proc(
		vs, fs: u32,
		blend_enable: u32,
		color_src, color_dst, color_op: u32,
		alpha_src, alpha_dst, alpha_op: u32,
		color_mask: u32,
		cull_mode: u32,
		fill_mode: u32,
	) -> u32 ---
	fw_gl_release_pipeline :: proc(handle: u32) ---
	fw_gl_pipeline_depth_stencil :: proc(
		handle: u32,
		depth_test, depth_write: bool,
		depth_compare: u32,
		stencil_test: bool,
		compare_mask, write_mask: u32,
		front_fail, front_pass, front_depth_fail, front_compare,
		back_fail, back_pass, back_depth_fail, back_compare: u32,
	) ---
	fw_set_stencil_reference :: proc(reference: u32) ---
	fw_gl_create_buffer :: proc(buffer_type: u32, byte_size: i32) -> u32 ---
	fw_gl_upload_buffer :: proc(handle: u32, data: rawptr, size: i32, offset: i32) ---
	fw_gl_release_buffer :: proc(handle: u32) ---
	fw_gl_create_texture :: proc(width, height: i32, format: u32) -> u32 ---
	fw_gl_upload_texture :: proc(handle: u32, width, height: i32, data: rawptr, size: i32) ---
	fw_gl_upload_texture_region :: proc(handle: u32, x, y, width, height: i32, data: rawptr, size: i32) ---
	fw_gl_download_texture :: proc(handle: u32, data: rawptr, size: i32) -> bool ---
	fw_gl_blit_texture :: proc(source, destination: u32, sx, sy, sw, sh, dx, dy, dw, dh: i32, filter: u32) ---
	fw_gl_texture_supported :: proc(format: u32) -> bool ---
	fw_gl_release_texture :: proc(handle: u32) ---
	fw_gl_create_sampler :: proc(filter: u32, wrap_x: u32, wrap_y: u32) -> u32 ---
	fw_gl_release_sampler :: proc(handle: u32) ---

	fw_begin_pass :: proc(fbo_texture: u32, clear_r, clear_g, clear_b, clear_a: f32, do_clear: u32) ---
	fw_begin_target :: proc(
		textures: ^u32,
		count: i32,
		depth_texture: u32,
		colors: rawptr,
		color_count: i32,
		clear_depth: bool,
		depth: f32,
		clear_stencil: bool,
		stencil: i32,
	) -> bool ---
	fw_end_pass :: proc() ---
	fw_bind_pipeline :: proc(handle: u32) ---
	fw_set_matrix4 :: proc(stage: u32, slot: u32, data: rawptr) ---
	fw_set_float :: proc(stage: u32, slot: u32, value: f32) ---
	fw_bind_texture :: proc(unit: u32, texture: u32, sampler: u32) ---
	fw_bind_vertex_buffer :: proc(slot: u32, buffer: u32, stride: i32) ---
	fw_vertex_attribute :: proc(location: u32, slot: u32, type_ordinal: u32, normalized: u32, stride: i32, offset: i32) ---
	fw_bind_index_buffer :: proc(buffer: u32) ---
	fw_draw_elements :: proc(count: i32, index_type: u32, byte_offset: i32, instances: i32) ---
	fw_draw_arrays :: proc(count: i32, offset: i32, instances: i32) ---
	fw_set_viewport :: proc(x, y, w, h: i32, fb_height: i32) ---
	fw_set_scissor :: proc(x, y, w, h: i32, fb_height: i32) ---

	// ---- M3: 输入 ----
	fw_set_mouse_relative :: proc(enabled: u32) ---

	// ---- 窗口(全屏) ----
	fw_set_fullscreen :: proc(enabled: u32) ---
	fw_is_fullscreen :: proc() -> u32 ---

	// ---- M4: 虚拟文件系统(localStorage) ----
	fw_fs_exists :: proc(path_ptr: rawptr, path_len: i32) -> u32 ---
	fw_fs_size :: proc(path_ptr: rawptr, path_len: i32) -> i32 ---
	fw_fs_read :: proc(path_ptr: rawptr, path_len: i32, buf: rawptr, buf_len: i32) -> i32 ---
	fw_fs_write :: proc(path_ptr: rawptr, path_len: i32, data_ptr: rawptr, data_len: i32) -> u32 ---
	fw_fs_remove :: proc(path_ptr: rawptr, path_len: i32) -> u32 ---
	fw_fs_is_directory :: proc(path_ptr: rawptr, path_len: i32) -> bool ---
	fw_fs_make_directory :: proc(path_ptr: rawptr, path_len: i32) -> bool ---
	fw_fs_enumerate :: proc(path_ptr: rawptr, path_len: i32, destination: rawptr, capacity: i32) -> i32 ---
}

// odinfmt: enable

// 内建 GLSL 着色器源码(与 spv/dxil/msl 同语义, spirv-cross 反编译校对)
batcher_vertex_glsl :: #load("assets/shaders/Batcher.vertex.glsl")
batcher_fragment_glsl :: #load("assets/shaders/Batcher.fragment.glsl")
textured_vertex_glsl :: #load("assets/shaders/Textured.vertex.glsl")
textured_fragment_glsl :: #load("assets/shaders/Textured.fragment.glsl")
msdf_vertex_glsl :: #load("assets/shaders/Msdf.vertex.glsl")
msdf_fragment_glsl :: #load("assets/shaders/Msdf.fragment.glsl")

// 句柄转换: u32 <-> SDL 指针字段

// ==============================================================================
// Platform / Web / Graphics — 图形句柄与枚举转换
// ==============================================================================

web_handle_ptr :: proc(h: u32) -> rawptr {
	if h == 0 {
		return nil
	}
	return rawptr(uintptr(h))
}

web_handle_u32 :: proc(p: rawptr) -> u32 {
	if p == nil {
		return 0
	}
	return u32(uintptr(p))
}

// CommandBuffer / RenderPass 的非 nil 占位(现有 nil 守卫依赖)
web_cmd_placeholder: u64
web_renderpass_placeholder: u64

// 枚举 → 序号(JS 侧按序号映射 GL 常量)。序号与各 enum 声明顺序一致。

web_blend_factor :: proc(f: BlendFactor) -> u32 {
	return u32(f)
}

web_blend_op :: proc(op: BlendOp) -> u32 {
	return u32(op)
}

web_cull_mode :: proc(m: CullMode) -> u32 {
	return u32(m)
}

web_fill_mode :: proc(m: FillMode) -> u32 {
	return u32(m)
}

web_texture_filter :: proc(f: TextureFilter) -> u32 {
	return u32(f)
}

web_texture_wrap :: proc(w: TextureWrap) -> u32 {
	return u32(w)
}

web_shader_stage :: proc(s: ShaderStage) -> u32 {
	return u32(s)
}

web_index_type :: proc(f: IndexFormat) -> u32 {
	// 0 = UNSIGNED_SHORT, 1 = UNSIGNED_INT
	switch f {
	case .Sixteen:
		return 0
	case .ThirtyTwo:
		return 1
	}
	return 1
}

web_index_type_size :: proc(f: IndexFormat) -> i32 {
	switch f {
	case .Sixteen:
		return 2
	case .ThirtyTwo:
		return 4
	}
	return 4
}

web_vertex_type :: proc(t: VertexType) -> u32 {
	// 与 VertexType 枚举序号一致; JS 侧映射为 (size, gl_type)
	return u32(t)
}

// Foster 内部 Web 事件。不假扮 SDL.Event 结构; 窗口事件在 poll_events 的
// .JS 分支里映射为 SDL.EventType 枚举值复用现有 window_on_event, 输入事件
// 直接派发到 input_key/input_mouse_* 等现有入口。
// 结构布局被 foster.js 按小端写入(24 字节), 改字段必须两侧同步。
// ==============================================================================
// Platform / Web / Events — 事件桥
// ==============================================================================

WebEventKind :: enum u32 {
	Quit, // 浏览器侧请求退出(pagehide)
	WindowResized, // A = CSS 宽, B = CSS 高
	WindowFocusGained,
	WindowFocusLost,
	KeyDown, // A = scancode(Keys 值同 SDL), B = repeat
	KeyUp, // A = scancode
	MouseMove, // F = x 像素, G = y 像素
	MouseButtonDown, // A = 按钮(1左/2中/3右), F/G = x/y
	MouseButtonUp, // A = 按钮, F/G = x/y
	MouseWheel, // F = dx, G = dy(向上为正)
	TextInput, // 文本通过 fw_event_text 读取，保留整次 UTF-8 提交。
	ControllerConnected, // A = ID, B/C = buttons/axes, F = standard mapping。
	ControllerDisconnected,
	ControllerButtonDown,
	ControllerButtonUp,
	ControllerAxis, // A = ID, B = axis, F = value。
	ClipboardResult, // A = 请求 ID, B = 成功；文本通过 fw_event_text 读取。
	DialogResult, // A = 请求 ID, B = 成功；NUL 分隔的虚拟路径。
	StorageFlushResult, // A = 请求 ID, B = 成功。
}

WebEvent :: struct {
	Kind: WebEventKind,
	A:    i32,
	B:    i32,
	C:    i32,
	F:    f32,
	G:    f32,
}

// ------------------------------------------------------------------------------
// Platform / Web / Helpers — 字符串传参辅助
// ------------------------------------------------------------------------------

web_string_bytes :: proc(s: string) -> (ptr: rawptr, length: i32) {
	if len(s) == 0 {
		return nil, 0
	}
	bytes := transmute([]byte)s
	return &bytes[0], i32(len(bytes))
}

web_event_text :: proc(allocator := context.temp_allocator) -> string {
	length := fw_event_text(nil, 0)
	if length <= 0 {
		return ""
	}
	data := make([]u8, int(length), allocator)
	_ = fw_event_text(raw_data(data), length)
	return string(data)
}

web_clipboard_callbacks: map[u32]ClipboardCallback
web_clipboard_next_request: u32

web_clipboard_register :: proc(callback: ClipboardCallback) -> u32 {
	if callback == nil {
		return 0
	}
	if web_clipboard_callbacks == nil {
		web_clipboard_callbacks = make(map[u32]ClipboardCallback)
	}
	web_clipboard_next_request += 1
	web_clipboard_callbacks[web_clipboard_next_request] = callback
	return web_clipboard_next_request
}

web_clipboard_complete :: proc(request: u32, succeeded: bool) {
	if callback, ok := web_clipboard_callbacks[request]; ok {
		delete_key(&web_clipboard_callbacks, request)
		callback(web_event_text(), succeeded)
	}
}

// ------------------------------------------------------------------------------
// Platform / Web / Events / Storage — 文件选择与异步写入完成
// ------------------------------------------------------------------------------

web_dialog_requests: map[u32]^DialogRequest
web_dialog_next_request: u32
web_storage_callbacks: map[u32]StorageFileCallback
web_storage_next_request: u32

web_dialog_start :: proc(request: ^DialogRequest, filters: []DialogFilter) {
	if web_dialog_requests == nil {
		web_dialog_requests = make(map[u32]^DialogRequest)
	}
	web_dialog_next_request += 1
	web_dialog_requests[web_dialog_next_request] = request
	data, _ := json.marshal(filters)
	defer delete(data)
	fw_dialog_start(web_dialog_next_request, u32(request.Kind), raw_data(data), i32(len(data)))
}

web_dialog_complete :: proc(id: u32, succeeded: bool) {
	request, ok := web_dialog_requests[id]
	if !ok {
		return
	}
	delete_key(&web_dialog_requests, id)
	defer storage_dialog_dispose(request)
	payload := web_event_text()
	files: []string
	if succeeded && payload != "" {
		files = strings.split(payload, "\x00", context.temp_allocator)
	}
	if request.Kind == .OpenFiles {
		request.FilesCallback(DialogResult{Files = files, Cancelled = !succeeded})
	} else {
		request.SingleCallback(len(files) > 0 ? files[0] : "")
	}
}

web_storage_flush :: proc(path: string, callback: StorageFileCallback) {
	if web_storage_callbacks == nil {
		web_storage_callbacks = make(map[u32]StorageFileCallback)
	}
	web_storage_next_request += 1
	web_storage_callbacks[web_storage_next_request] = callback
	fw_fs_flush(web_storage_next_request, raw_data(path), i32(len(path)))
}

web_storage_complete :: proc(id: u32, succeeded: bool) {
	if callback, ok := web_storage_callbacks[id]; ok {
		delete_key(&web_storage_callbacks, id)
		callback(succeeded)
	}
}

web_storage_shutdown :: proc() {
	for _, request in web_dialog_requests {
		storage_dialog_dispose(request)
	}
	delete(web_dialog_requests)
	web_dialog_requests = nil
	delete(web_storage_callbacks)
	web_storage_callbacks = nil
}

web_app: ^App

web_frame_delta: coretime.Duration

// Device 句柄的非 nil 占位: 让 GraphicsDevice 现有的 nil 守卫照常成立,
// 但该指针永远不会被传给任何 SDL 调用(JS 分支不触碰 SDL)。
web_device_placeholder: u64

// ==============================================================================
// Platform / Web / Lifecycle — App 生命周期与帧循环
// ==============================================================================

web_relocate_app :: proc(app: ^App) -> ^App {
	// main() 在 .JS 下于 Run 返回后立即返回, 其栈帧(含调用方声明的 App 结构)会被
	// 后续调用复用。在 run() 入口把 App 拷贝到堆上并修正内部回指针, 之后的一切
	// (含 StartupProc 里初始化的 Batcher 等)都指向堆副本。
	// 注意: 经 AppSetUserData 传入的状态仍应是全局变量或堆分配(见文档 §0)。
	heap_app := new(App)
	heap_app^ = app^

	heap_app.Window.App = heap_app
	heap_app.Window.GraphicsDevice = &heap_app.GraphicsDevice
	heap_app.Input.App = heap_app
	heap_app.FileSystem.App = heap_app

	device := &heap_app.GraphicsDevice
	if device.HasWindowRenderTarget {
		device.WindowRenderTarget.GraphicsDevice = device
		for i in 0 ..< len(device.WindowRenderTarget.Attachments) {
			device.WindowRenderTarget.Attachments[i].GraphicsDevice = device
		}
	}
	if device.HasBackbufferTarget {
		device.BackbufferTarget.GraphicsDevice = device
		for i in 0 ..< len(device.BackbufferTarget.Attachments) {
			device.BackbufferTarget.Attachments[i].GraphicsDevice = device
		}
	}

	return heap_app
}

web_enter_run_loop :: proc(app: ^App) {
	web_app = app
}

web_take_frame_delta :: proc() -> coretime.Duration {
	delta := web_frame_delta
	web_frame_delta = 0
	return delta
}

web_log :: proc(message: string) {
	if len(message) > 0 {
		bytes := transmute([]byte)message
		fw_log(&bytes[0], i32(len(bytes)))
	}
}

// 用户路径返回应用自己的虚拟前缀，存储由 localStorage 文件/目录键持久化。

web_user_path :: proc(name: string) -> string {
	return fmt.aprintf("/foster/%s/", name)
}

web_window_size :: proc() -> Point2 {
	// M1: 与像素尺寸一致(矩阵/视口/帧缓冲统一用绘制缓冲像素, DPR>1 也正确);
	// M3 接输入时再区分 CSS 逻辑坐标与像素坐标
	return web_window_size_in_pixels()
}

web_window_size_in_pixels :: proc() -> Point2 {
	w, h: i32
	fw_canvas_pixel_size(&w, &h)
	return Point2{int(w), int(h)}
}

// run() 在 .JS 下返回后, 每帧由 foster.js 的 requestAnimationFrame 调用。
@(export)

foster_step :: proc(dt: f64) -> (keep_going: bool) {
	app := web_app
	if app == nil || !app.Running {
		web_log("foster_step: stop (no app / not running)")
		return false
	}
	clamped := dt
	if clamped > 0.25 {
		clamped = 0.25 // 页面隐藏后恢复时钳制首帧步长
	}
	web_frame_delta = coretime.Duration(clamped * 1e9)

	tick_app(app)

	if app.Exiting {
		web_log("foster_step: exiting -> run_finish")
		run_finish(app)
		return false
	}
	return true
}
