// ui —— clay 布局引擎的 ofoster 集成 + 控件/主题层。
//
// 分层（自底向上）：
//   ui.odin          UI_Context：clay 初始化/帧流程（指针/滚动/输入边沿）、字体表
//   ui_text.odin     msdf 字体测量（clay 回调）与字形四边形生成
//   ui_backend.odin  clay RenderCommand -> UI_Quad_Op 翻译（CPU 可测）+ Batcher 发射
//   ui_widgets.odin  Theme + Button/Label/Toggle（hover/按下态；clay v0.14 无文本
//                    输入，输入框为后续自建项）
//
// clay 只做布局与交互查询，渲染由本包翻译后经 ofoster Batcher 发射；
// 圆角与 msdf 抗锯齿文本是渲染端后续增量（v1 为直角+图集直采样）。
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

	// fontId -> 字体（msdf 图集）与其 GPU 纹理，两表平行。
	fonts:          [dynamic]^foster.MsdfFont,
	font_textures: [dynamic]foster.Texture,

	// 帧内 TextElementConfig bump 池：clay 把文本配置存裸指针、EndLayout
	// 才回读，调用侧栈上 config 会悬垂（v1 踩过的坑），必须由 ctx 保活。
	text_config_pool: []clay.TextElementConfig,
	text_config_len:  int,

	// 圆角渲染用的单位圆盘纹理（预乘 alpha），ui_render 首次调用时懒建。
	corner_texture:    foster.Texture,
	corner_texture_ok: bool,

	width, height: f32,

	pointer_x, pointer_y: f32,
	pointer_down:      bool,
	pointer_down_prev: bool, // 上一帧状态（点击边沿检测）

	scroll_delta: [2]f32, // 每帧累计，begin 时消费清零
}

// 单帧文本配置池容量（超出则拒绝并返回 nil，UI 退化为该文本不显示）。
UI_TEXT_CONFIG_CAP :: 1024

// ------------------------------------------------------------------------------
// 生命周期
// ------------------------------------------------------------------------------

// 初始化 clay（arena 容量按 clay 建议的最小值）。可多次 init 同一 ctx。
ui_init :: proc(ctx: ^UI_Context, width, height: f32, allocator := context.allocator) -> bool {
	ctx^ = {
		width  = width,
		height = height,
	}

	capacity := uint(clay.MinMemorySize())
	memory, err := make([]u8, int(capacity), allocator)
	if err != .None { return false }
	ctx.arena_memory = memory

	p_pool, p_err := make([]clay.TextElementConfig, UI_TEXT_CONFIG_CAP, allocator)
	if p_err != .None {
		delete(memory, allocator)
		ctx.arena_memory = nil
		return false
	}
	ctx.text_config_pool = p_pool
	ctx.text_config_len = 0

	arena := clay.CreateArenaWithCapacityAndMemory(capacity, raw_data(memory))
	clay.Initialize(
		arena,
		{width, height},
		{handler = ui_error_noop, userData = nil},
	)
	clay.SetMeasureTextFunction(ui_measure_trampoline, ctx)
	return true
}

ui_dispose :: proc(ctx: ^UI_Context, allocator := context.allocator) {
	// context 活在 arena 里；先断开 clay 全局指针，避免下一个
	// Initialize 读到已释放的 oldContext（UB/挂死）
	clay.SetCurrentContext(nil)
	if ctx.corner_texture_ok {
		foster.TextureDispose(&ctx.corner_texture)
		ctx.corner_texture_ok = false
	}
	delete(ctx.fonts)
	delete(ctx.font_textures)
	delete(ctx.text_config_pool)
	delete(ctx.arena_memory, allocator)
	ctx^ = {}
}

// 注册字体（fontId 即下标）；texture 为图集的 GPU 纹理（由调用侧上传）。
// 返回 fontId。测量在字体注册前调用会按零宽处理。
ui_register_font :: proc(ctx: ^UI_Context, font: ^foster.MsdfFont, texture: foster.Texture) -> int {
	append(&ctx.fonts, font)
	append(&ctx.font_textures, texture)
	return len(ctx.fonts) - 1
}

// ------------------------------------------------------------------------------
// 帧流程 —— 输入 -> begin -> 声明 -> end
// ------------------------------------------------------------------------------

ui_set_dimensions :: proc(ctx: ^UI_Context, width, height: f32) {
	ctx.width = width
	ctx.height = height
	clay.SetLayoutDimensions({width, height})
}

// 更新指针状态（可在帧内多次调用，取最后一次）。down 的上一帧值在
// ui_end 快照——ui_clicked 的边沿依据与是否调用过本 proc 无关。
ui_set_pointer :: proc(ctx: ^UI_Context, x, y: f32, down: bool) {
	ctx.pointer_x = x
	ctx.pointer_y = y
	ctx.pointer_down = down
}

ui_add_scroll :: proc(ctx: ^UI_Context, dx, dy: f32) {
	ctx.scroll_delta[0] += dx
	ctx.scroll_delta[1] += dy
}

// 帧开始：提交指针/滚动状态并进入布局。delta_time 驱动滚动惯性。
// 注意：down 的边沿快照在 ui_set_pointer 里做（调用侧通常在 begin 前
// 已采好本帧输入）；begin 只提交状态给 clay。
ui_begin :: proc(ctx: ^UI_Context, delta_time: f32) {
	ctx.text_config_len = 0 // 文本配置池按帧重置（池内存跨帧保活，见结构体注释）
	clay.SetPointerState({ctx.pointer_x, ctx.pointer_y}, ctx.pointer_down)
	clay.UpdateScrollContainers(true, ctx.scroll_delta, delta_time)
	ctx.scroll_delta = {0, 0}
	clay.BeginLayout()
}

// 从帧内池取一个存活的 TextElementConfig 指针（clay 延迟回读，栈上
// config 会悬垂）。池满返回 nil。
ui_text_config :: proc(ctx: ^UI_Context, config: clay.TextElementConfig) -> ^clay.TextElementConfig {
	if ctx.text_config_len >= len(ctx.text_config_pool) { return nil }
	ptr := &ctx.text_config_pool[ctx.text_config_len]
	ctx.text_config_len += 1
	ptr^ = config
	return ptr
}

// 帧结束：返回 clay 的渲染命令数组（送 ui_translate / ui_render）。
// 同时快照本帧的按住状态，作为下一帧 ui_clicked 的边沿依据。
ui_end :: proc(ctx: ^UI_Context) -> clay.ClayArray(clay.RenderCommand) {
	commands := clay.EndLayout()
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
ui_error_noop :: proc "c" (error_data: clay.ErrorData) {
	// 静默处理：UI 出错不崩游戏（clay 的错误多为布局警告）
	_ = error_data
}

ui_font_of :: proc "contextless" (ctx: ^UI_Context, font_id: int) -> ^foster.MsdfFont {
	if font_id < 0 || font_id >= len(ctx.fonts) { return nil }
	return ctx.fonts[font_id]
}

ui_texture_of :: proc(ctx: ^UI_Context, font_id: int) -> ^foster.Texture {
	if font_id < 0 || font_id >= len(ctx.font_textures) { return nil }
	return &ctx.font_textures[font_id]
}
