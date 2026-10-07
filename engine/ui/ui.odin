// ui —— clay 布局引擎的 ofoster 集成 + 控件/主题层。
//
// 分层（自底向上）：
//   ui.odin          UI_Context：clay 初始化/帧流程（指针/滚动/输入边沿）、字体表
//   ui_text.odin     msdf 字体测量（clay 回调）与字形四边形生成
//   ui_backend.odin  clay RenderCommand -> UI_Op 翻译（CPU 可测）+ Batcher 发射
//   ui_input.odin    鼠标捕获 / 导航焦点 / 禁用态 / 模态 / 输入消费
//   ui_widgets.odin  主题、基础控件、图像、滑条、进度和容器
//
// clay 只做布局与交互查询，渲染由本包翻译后经 ofoster Batcher 发射；
// 支持位图/MSDF 字体、嵌套裁剪、逻辑坐标缩放与鼠标/导航输入。
package ui

import "core:mem"

import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// 分区：
//   类型 —— UI_Context
//   生命周期 —— init / dispose / 字体注册
//   帧流程 —— 输入 -> begin -> 声明 -> end
//   输入查询 —— 点击边沿 / 悬停

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

UI_Context :: struct {
	arena_memory: []u8,
	allocator: mem.Allocator,
	clay_context: ^clay.Context,

	// fontId -> 字体元数据、GPU 纹理、渲染配置，三表平行。
	fonts:          [dynamic]^foster.MsdfFont,
	font_textures: [dynamic]foster.Texture,
	font_renderers: [dynamic]UI_Font_Renderer,
	image_pool: []UI_Image_Data,
	image_len: int,
	ops: [dynamic]UI_Op,

	// 帧内 TextElementConfig bump 池：clay 把文本配置存裸指针、EndLayout
	// 才回读，调用侧栈上 config 会悬垂（v1 踩过的坑），必须由 ctx 保活。
	text_config_pool: []clay.TextElementConfig,
	text_config_len:  int,

	// 圆角渲染用的单位圆盘纹理（预乘 alpha），ui_render 首次调用时懒建。
	corner_texture:    foster.Texture,
	corner_texture_ok: bool,

	width, height: f32,
	scale: f32,
	viewport_origin: foster.Vec2,
	pointer_pixels: foster.Vec2,
	active_id, focused_id: u32,
	modal_id, scope_id: u32,
	modal_changed: bool,
	active_seen: bool,
	widgets: [dynamic]UI_Focus_Entry,
	previous_widgets: [dynamic]UI_Focus_Entry,
	scrolls: [dynamic]UI_Scroll_Entry,
	navigation: UI_Navigation,
	input: UI_Input_Capture,
	pool_overflow: bool,
	error_count: int,
	last_error: clay.ErrorType,

	pointer_x, pointer_y: f32,
	pointer_down:      bool,
	pointer_down_prev: bool, // 上一帧状态（点击边沿检测）

	scroll_delta: [2]f32, // 每帧累计，begin 时消费清零
}

// 单帧文本/图像池容量；超出则拒绝该元素并设置 pool_overflow。
UI_TEXT_CONFIG_CAP :: 1024

// ------------------------------------------------------------------------------
// 生命周期
// ------------------------------------------------------------------------------

// 初始化 clay（arena 容量按 clay 建议的最小值）。可多次 init 同一 ctx。
ui_init :: proc(ctx: ^UI_Context, width, height: f32, allocator := context.allocator) -> bool {
	if ctx.clay_context != nil {
		ui_dispose(ctx)
	}
	ctx^ = {
		width  = width,
		height = height,
		scale = 1,
		allocator = allocator,
	}

	capacity := uint(clay.MinMemorySize())
	memory, err := make([]u8, int(capacity), allocator)
	if err != .None {
		return false
	}
	ctx.arena_memory = memory

	p_pool, p_err := make([]clay.TextElementConfig, UI_TEXT_CONFIG_CAP, allocator)
	if p_err != .None {
		delete(memory, allocator)
		ctx.arena_memory = nil
		return false
	}
	ctx.text_config_pool = p_pool
	ctx.text_config_len = 0
	ctx.image_pool, p_err = make([]UI_Image_Data, UI_TEXT_CONFIG_CAP, allocator)
	if p_err != .None {
		ui_dispose(ctx)
		return false
	}
	ctx.fonts = make([dynamic]^foster.MsdfFont, allocator)
	ctx.font_textures = make([dynamic]foster.Texture, allocator)
	ctx.font_renderers = make([dynamic]UI_Font_Renderer, allocator)
	ctx.widgets = make([dynamic]UI_Focus_Entry, allocator)
	ctx.previous_widgets = make([dynamic]UI_Focus_Entry, allocator)
	ctx.scrolls = make([dynamic]UI_Scroll_Entry, allocator)
	ctx.ops = make([dynamic]UI_Op, allocator)

	arena := clay.CreateArenaWithCapacityAndMemory(capacity, raw_data(memory))
	ctx.clay_context = clay.Initialize(
		arena,
		{width, height},
		{handler = ui_error_record, userData = ctx},
	)
	clay.SetMeasureTextFunction(ui_measure_trampoline, ctx)
	return true
}

// allocator 参数保留源码兼容；释放始终使用初始化时保存的 allocator。
ui_dispose :: proc(ctx: ^UI_Context, allocator := context.allocator) {
	// context 活在 arena 里；先断开 clay 全局指针，避免下一个
	// Initialize 读到已释放的 oldContext（UB/挂死）
	if clay.GetCurrentContext() == ctx.clay_context {
		clay.SetCurrentContext(nil)
	}
	if ctx.corner_texture_ok {
		foster.TextureDispose(&ctx.corner_texture)
		ctx.corner_texture_ok = false
	}
	delete(ctx.fonts)
	delete(ctx.font_textures)
	for &renderer in ctx.font_renderers {
		if renderer.initialized {
			foster.MaterialDispose(&renderer.material)
		}
	}
	delete(ctx.font_renderers)
	delete(ctx.widgets)
	delete(ctx.previous_widgets)
	delete(ctx.scrolls)
	delete(ctx.ops)
	delete(ctx.image_pool, ctx.allocator)
	delete(ctx.text_config_pool, ctx.allocator)
	delete(ctx.arena_memory, ctx.allocator)
	ctx^ = {}
}

// 注册字体（fontId 即下标）；texture 为图集的 GPU 纹理（由调用侧上传）。
// 返回 fontId。测量在字体注册前调用会按零宽处理。
// 字体/纹理由调用者持有到 ui_dispose 之后；注册只在帧外进行。
// 默认 Bitmap 保持旧位图图集兼容；真实距离场必须显式传 .MSDF。
ui_register_font :: proc(
	ctx: ^UI_Context,
	font: ^foster.MsdfFont,
	texture: foster.Texture,
	kind: UI_Font_Kind = .Bitmap,
) -> int {
	append(&ctx.fonts, font)
	append(&ctx.font_textures, texture)
	append(&ctx.font_renderers, UI_Font_Renderer{kind = kind})
	clay.SetCurrentContext(ctx.clay_context)
	clay.ResetMeasureTextCache()
	return len(ctx.fonts) - 1
}

// ------------------------------------------------------------------------------
// 帧流程 —— 输入 -> begin -> 声明 -> end
// ------------------------------------------------------------------------------

ui_set_dimensions :: proc(ctx: ^UI_Context, width, height: f32) {
	ctx.width = width
	ctx.height = height
	clay.SetCurrentContext(ctx.clay_context)
	clay.SetLayoutDimensions({width, height})
}

// 更新指针状态（可在帧内多次调用，取最后一次）。down 的上一帧值在
// ui_end 快照——ui_clicked 的边沿依据与是否调用过本 proc 无关。
ui_set_pointer :: proc(ctx: ^UI_Context, x, y: f32, down: bool) {
	ctx.pointer_pixels = {x, y}
	ctx.pointer_down = down
}

ui_add_scroll :: proc(ctx: ^UI_Context, dx, dy: f32) {
	ctx.scroll_delta[0] += dx
	ctx.scroll_delta[1] += dy
}

// 帧开始：提交指针/滚动状态并进入布局。delta_time 驱动滚动惯性。
// 一次只允许一个 context 在 begin/end 区间内声明布局，不支持线程并发。
ui_begin :: proc(ctx: ^UI_Context, delta_time: f32) {
	clay.SetCurrentContext(ctx.clay_context)
	clay.SetLayoutDimensions({ctx.width, ctx.height})
	ctx.text_config_len = 0 // 文本配置池按帧重置（池内存跨帧保活，见结构体注释）
	ctx.image_len = 0
	ctx.pool_overflow = false
	ctx.scope_id = 0
	ctx.active_seen = false
	ctx.input = {pointer = ctx.modal_id != 0 || ctx.active_id != 0, keyboard = ctx.modal_id != 0}
	ctx.pointer_x = (ctx.pointer_pixels.x - ctx.viewport_origin.x) / ctx.scale
	ctx.pointer_y = (ctx.pointer_pixels.y - ctx.viewport_origin.y) / ctx.scale
	ui_navigation_begin(ctx)
	clay.SetPointerState({ctx.pointer_x, ctx.pointer_y}, ctx.pointer_down)
	// 拖动由控件捕获；列表使用滚轮，避免按按钮时同时拖动父滚动区。
	// 模态切换帧的命中仍基于旧布局，禁止滚轮穿过刚打开/关闭的遮罩。
	if !ctx.modal_changed {
		clay.UpdateScrollContainers(false, ctx.scroll_delta, delta_time)
	}
	ctx.modal_changed = false
	ctx.scroll_delta = {0, 0}
	// 在 BeginLayout/OpenElement 重建内部元素表之前快照滚动状态，
	// 使 if clay.UI()(ui_scroll_decl(...)) 的内联求值安全。
	for &scroll in ctx.scrolls {
		data := clay.GetScrollContainerData(clay.ElementId{id = scroll.id})
		scroll.offset = data.found ? data.scrollPosition^ : clay.Vector2{}
		scroll.seen = false
	}
	clay.BeginLayout()
}

// 从帧内池取一个存活的 TextElementConfig 指针（clay 延迟回读，栈上
// config 会悬垂）。池满返回 nil。
ui_text_config :: proc(ctx: ^UI_Context, config: clay.TextElementConfig) -> ^clay.TextElementConfig {
	if ctx.text_config_len >= len(ctx.text_config_pool) {
		ctx.pool_overflow = true
		return nil
	}
	ptr := &ctx.text_config_pool[ctx.text_config_len]
	ctx.text_config_len += 1
	ptr^ = config
	return ptr
}

// 帧结束：返回 clay 的渲染命令数组（送 ui_translate / ui_render）。
// 同时快照本帧的按住状态，作为下一帧 ui_clicked 的边沿依据。
ui_end :: proc(ctx: ^UI_Context) -> clay.ClayArray(clay.RenderCommand) {
	commands := clay.EndLayout()
	if !ctx.pointer_down || !ctx.active_seen {
		ctx.active_id = 0
	}
	focus_found := false
	for entry in ctx.widgets {
		if entry.id == ctx.focused_id {
			focus_found = true
		}
	}
	if !focus_found {
		ctx.focused_id = 0
	}
	ctx.widgets, ctx.previous_widgets = ctx.previous_widgets, ctx.widgets
	clear(&ctx.widgets)
	ctx.navigation = {}
	for i := len(ctx.scrolls) - 1; i >= 0; i -= 1 {
		if !ctx.scrolls[i].seen {
			unordered_remove(&ctx.scrolls, i)
		}
	}
	ctx.pointer_down_prev = ctx.pointer_down
	return commands
}

// ------------------------------------------------------------------------------
// 输入查询
// ------------------------------------------------------------------------------

// 本帧刚按下（点击边沿）。
ui_clicked :: proc(ctx: ^UI_Context) -> bool {
	return ctx.pointer_down && !ctx.pointer_down_prev
}

// 本帧刚松开。
ui_released :: proc(ctx: ^UI_Context) -> bool {
	return !ctx.pointer_down && ctx.pointer_down_prev
}

// ------------------------------------------------------------------------------
// 内部 —— clay 回调
// ------------------------------------------------------------------------------

// 静态文本测量入口（clay 每帧多次调用；userData 是 UI_Context）。
@(private)
ui_measure_trampoline :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	userData: rawptr,
) -> clay.Dimensions {
	ctx := (^UI_Context)(userData)
	font := ui_font_of(ctx, int(config.fontId))
	if font == nil {
		return {0, 0}
	}
	s := string(text.chars[:text.length])
	return ui_measure_text(font, s, config.fontSize, config.letterSpacing, config.lineHeight)
}

@(private)
ui_error_record :: proc "c" (error_data: clay.ErrorData) {
	ctx := cast(^UI_Context)error_data.userData
	if ctx != nil {
		ctx.error_count += 1
		ctx.last_error = error_data.errorType
	}
}

ui_font_of :: proc "contextless" (ctx: ^UI_Context, font_id: int) -> ^foster.MsdfFont {
	if font_id < 0 || font_id >= len(ctx.fonts) {
		return nil
	}
	return ctx.fonts[font_id]
}

ui_texture_of :: proc(ctx: ^UI_Context, font_id: int) -> ^foster.Texture {
	if font_id < 0 || font_id >= len(ctx.font_textures) {
		return nil
	}
	return &ctx.font_textures[font_id]
}
