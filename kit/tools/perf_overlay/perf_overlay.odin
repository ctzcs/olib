// perf_overlay —— 悬浮性能面板：FPS、帧时间统计与曲线、core/profiler 作用域耗时。
//
// 宿主每帧调用 frame 记录帧时间，用自己的按键切换 visible，最后在所有 UI 之上调用 draw。
// 面板是被动浮层：不读取窗口输入、不捕获指针，也不影响宿主的输入分配。
//
// 分区：
//   数据 —— Overlay 与统计结果
//   生命周期 —— init / dispose
//   采样 —— frame / 帧时间汇总 / 作用域增量
//   绘制 —— draw / 面板布局
package perf_overlay

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"

import profiler "olib:core/profiler"
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import mat "olib:kit/rendering/material"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

// ------------------------------------------------------------------------------
// 数据
// ------------------------------------------------------------------------------

HISTORY :: 240 // 统计窗口（帧）
GRAPH_BARS :: 120 // 曲线显示最近的帧数
REFRESH_INTERVAL :: 0.5 // 数字与作用域表的刷新间隔（秒），避免逐帧跳动
MAX_SCOPES :: 8

Corner :: enum {
	Top_Right,
	Top_Left,
	Bottom_Right,
	Bottom_Left,
}

Frame_Summary :: struct {
	fps, avg_ms, min_ms, max_ms: f32,
	low1_fps: f32, // 最慢 1% 帧的平均 FPS
	count: int,
}

Scope_Row :: struct {
	name: string, // 借用 Overlay.previous 中复制的名字
	ms_per_frame, calls_per_frame: f32,
}

// 上次刷新时的累计值；name 复制自 profiler 的键，防止键字符串随热重载 DLL 卸载失效。
Scope_Previous :: struct {
	name: string,
	stat: profiler.Profile_Stat,
}

// 初始化后不得搬动（Render2D 与 UI_Context 要求地址稳定）。
Overlay :: struct {
	visible: bool,
	corner: Corner,
	history: [HISTORY]f32, // 毫秒，环形缓冲
	head, count: int,
	elapsed: f32,
	window_frames: int,
	summary: Frame_Summary,
	scopes: [MAX_SCOPES]Scope_Row,
	scope_count: int,
	previous: map[string]Scope_Previous, // 键与 name 为同一份复制
	ctx: ui.UI_Context,
	materials: mat.Material_Library,
	renderer: r2d.Render2D, // 借用 materials
	theme: ui.UI_Theme,
	initialized: bool,
}

// ------------------------------------------------------------------------------
// 生命周期
// ------------------------------------------------------------------------------

// font / font_texture 借用至 dispose，须为真正的 MSDF 图集。
init :: proc(o: ^Overlay, device: ^foster.GraphicsDevice, font: ^foster.MsdfFont, font_texture: foster.Texture) -> bool {
	if o.initialized || device == nil || font == nil do return false
	if !ui.ui_init(&o.ctx, 960, 720) do return false
	o.materials = {device = device}
	if reason := r2d.init(&o.renderer, &o.materials); reason != "" {
		fmt.eprintln("Perf overlay:", reason)
		ui.ui_dispose(&o.ctx)
		mat.material_library_dispose(&o.materials)
		return false
	}
	o.theme = ui.UI_THEME_DARK
	o.theme.body_font_id = u16(ui.ui_register_font(&o.ctx, font, font_texture, .MSDF))
	o.initialized = true
	return true
}

dispose :: proc(o: ^Overlay) {
	if o.initialized {
		ui.ui_dispose(&o.ctx)
		r2d.dispose(&o.renderer)
		mat.material_library_dispose(&o.materials)
	}
	for _, entry in o.previous do delete(entry.name)
	delete(o.previous)
	o^ = {}
}

// ------------------------------------------------------------------------------
// 采样
// ------------------------------------------------------------------------------

// 每帧调用一次，隐藏时也要调用，打开面板时才有完整历史。
// delta_time 是整帧间隔（含垂直同步等待）；CPU 各阶段耗时用 profiler.profile_scope 标记。
frame :: proc(o: ^Overlay, delta_time: f32) {
	dt := max(0, delta_time)
	o.history[o.head] = dt * 1000
	o.head = (o.head + 1) % HISTORY
	o.count = min(o.count + 1, HISTORY)
	o.window_frames += 1
	o.elapsed += dt
	if o.elapsed < REFRESH_INTERVAL && o.summary.count > 0 do return
	o.summary = summarize(o.history[:o.count])
	scopes_collect(o, profiler.profile_stats, o.window_frames)
	o.elapsed = 0
	o.window_frames = 0
}

// 帧时间（毫秒）汇总；顺序无关。
summarize :: proc(samples: []f32) -> Frame_Summary {
	if len(samples) == 0 do return {}
	s := Frame_Summary{min_ms = samples[0], max_ms = samples[0], count = len(samples)}
	total: f32
	for ms in samples {
		total += ms
		s.min_ms = min(s.min_ms, ms)
		s.max_ms = max(s.max_ms, ms)
	}
	s.avg_ms = total / f32(len(samples))
	s.fps = s.avg_ms > 0 ? 1000 / s.avg_ms : 0
	sorted := slice.clone(samples, context.temp_allocator)
	slice.sort(sorted)
	worst := max(1, len(sorted) / 100)
	slow: f32
	for ms in sorted[len(sorted) - worst:] do slow += ms
	slow /= f32(worst)
	s.low1_fps = slow > 0 ? 1000 / slow : 0
	return s
}

// 按上次刷新以来的增量统计每帧耗时与调用次数，按耗时降序保留前 MAX_SCOPES 项。
// profile_init 重建统计表导致计数回退时，从零重新计算。
scopes_collect :: proc(o: ^Overlay, current: map[string]profiler.Profile_Stat, frames: int) {
	o.scope_count = 0
	if frames <= 0 do return
	rows := make([dynamic]Scope_Row, 0, len(current), context.temp_allocator)
	for name, stat in current {
		entry, found := o.previous[name]
		if !found do entry.name = strings.clone(name)
		prev := entry.stat
		if stat.count < prev.count do prev = {}
		entry.stat = stat
		o.previous[entry.name] = entry
		calls := stat.count - prev.count
		if calls <= 0 do continue
		append(&rows, Scope_Row{
			name = entry.name,
			ms_per_frame = f32(time.duration_milliseconds(stat.total - prev.total)) / f32(frames),
			calls_per_frame = f32(calls) / f32(frames),
		})
	}
	slice.sort_by(rows[:], proc(a, b: Scope_Row) -> bool {
		return a.ms_per_frame > b.ms_per_frame
	})
	o.scope_count = min(len(rows), MAX_SCOPES)
	copy(o.scopes[:], rows[:o.scope_count])
}

// ------------------------------------------------------------------------------
// 绘制
// ------------------------------------------------------------------------------

GRAPH_BAR_WIDTH :: 2
GRAPH_HEIGHT :: 48
PANEL_PADDING :: 10
PANEL_WIDTH :: GRAPH_BARS * GRAPH_BAR_WIDTH + PANEL_PADDING * 2
TARGET_MS :: 1000.0 / 60
PANEL_Z :: 1000

// 在 target 上叠加面板；放在宿主所有 UI 之后调用。scale 与宿主 UI 比例一致，
// 面板在最终像素尺寸绘制，不随低分辨率场景放大。
draw :: proc(o: ^Overlay, target: foster.DrawableTarget, scale: f32 = 1) {
	if !o.initialized || !o.visible do return
	if target.WidthInPixels <= 0 || target.HeightInPixels <= 0 do return
	ui.ui_set_viewport(&o.ctx, {0, 0, f32(target.WidthInPixels), f32(target.HeightInPixels)}, scale)
	ui.ui_set_pointer(&o.ctx, -10000, -10000, false)
	ui.ui_begin(&o.ctx, 0)
	panel_layout(o)
	ui.ui_draw(&o.ctx, &o.renderer)
	if err := r2d.submit(&o.renderer, {target = target}); err != .None {
		fmt.eprintln("Perf overlay:", err)
	}
}

// 在 ui_begin 与 ui_end 之间声明面板。
@(private)
panel_layout :: proc(o: ^Overlay) {
	attach: clay.FloatingAttachPointType
	offset: clay.Vector2
	switch o.corner {
	case .Top_Right:    attach, offset = .RightTop, {-12, 12}
	case .Top_Left:     attach, offset = .LeftTop, {12, 12}
	case .Bottom_Right: attach, offset = .RightBottom, {-12, -12}
	case .Bottom_Left:  attach, offset = .LeftBottom, {12, -12}
	}
	panel := ui.ui_column_decl(6)
	panel.layout.padding = clay.PaddingAll(PANEL_PADDING)
	panel.layout.sizing.width = clay.SizingFixed(PANEL_WIDTH)
	panel.backgroundColor = ui.ui_clay_color({16, 18, 24, 225})
	panel.cornerRadius = clay.CornerRadiusAll(6)
	panel.floating = {attachTo = .Root, attachment = {element = attach, parent = attach},
		offset = offset, zIndex = PANEL_Z, pointerCaptureMode = .Passthrough}
	if clay.UI()(panel) do panel_contents(o)
}

@(private)
panel_contents :: proc(o: ^Overlay) {
	s := o.summary
	if clay.UI()(ui.ui_row_decl()) {
		ui.ui_label_ex(&o.ctx, &o.theme, fmt.tprintf("%.0f FPS", s.fps), rating_color(s.avg_ms), 20)
		ui.ui_spacer()
		ui.ui_label_ex(&o.ctx, &o.theme, fmt.tprintf("%.2f ms", s.avg_ms), o.theme.text, 16)
	}
	ui.ui_label_dim(&o.ctx, &o.theme, fmt.tprintf("min %.1f  max %.1f ms  1%% low %.0f FPS",
		s.min_ms, s.max_ms, s.low1_fps))
	graph(o)
	if o.scope_count == 0 do return
	if clay.UI()(ui.ui_row_decl(4)) {
		cell(o, "scope", 0, o.theme.text_dim)
		cell(o, "ms/frame", 64, o.theme.text_dim)
		cell(o, "calls", 44, o.theme.text_dim)
	}
	for row in o.scopes[:o.scope_count] {
		if clay.UI()(ui.ui_row_decl(4)) {
			cell(o, row.name, 0, o.theme.text)
			cell(o, fmt.tprintf("%.2f", row.ms_per_frame), 64, o.theme.text)
			cell(o, fmt.tprintf("%.1f", row.calls_per_frame), 44, o.theme.text_dim)
		}
	}
}

// 最近 GRAPH_BARS 帧，最新在右；纵轴至少 33 ms，出现更长的帧时整体压缩。细线为 60 FPS。
@(private)
graph :: proc(o: ^Overlay) {
	bars := min(o.count, GRAPH_BARS)
	top: f32 = 2 * TARGET_MS
	for i in 0 ..< bars do top = max(top, history_at(o, i))
	if clay.UI()(clay.ElementDeclaration{
		layout = {
			sizing = {width = clay.SizingFixed(GRAPH_BARS * GRAPH_BAR_WIDTH), height = clay.SizingFixed(GRAPH_HEIGHT)},
			childAlignment = {x = .Right, y = .Bottom},
		},
		backgroundColor = ui.ui_clay_color({0, 0, 0, 90}),
	}) {
		graph_bars(o, bars, top)
	}
}

@(private)
graph_bars :: proc(o: ^Overlay, bars: int, top: f32) {
	for i := bars - 1; i >= 0; i -= 1 {
		ms := history_at(o, i)
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(GRAPH_BAR_WIDTH),
				height = clay.SizingFixed(max(1, ms / top * GRAPH_HEIGHT))}},
			backgroundColor = ui.ui_clay_color(rating_color(ms)),
		}) {}
	}
	if clay.UI()(clay.ElementDeclaration{
		layout = {sizing = {width = clay.SizingFixed(GRAPH_BARS * GRAPH_BAR_WIDTH), height = clay.SizingFixed(1)}},
		backgroundColor = ui.ui_clay_color({255, 255, 255, 110}),
		floating = {attachTo = .Parent, attachment = {element = .LeftBottom, parent = .LeftBottom},
			offset = {0, -TARGET_MS / top * GRAPH_HEIGHT}, zIndex = PANEL_Z + 1, pointerCaptureMode = .Passthrough},
	}) {}
}

// 第 age 帧之前的帧时间，0 为最新。
@(private)
history_at :: proc(o: ^Overlay, age: int) -> f32 {
	return o.history[(o.head - 1 - age + HISTORY * 2) % HISTORY]
}

// width=0 占满剩余宽度（左对齐、裁剪溢出）；否则固定宽度右对齐。
@(private)
cell :: proc(o: ^Overlay, text: string, width: f32, color: foster.Color) {
	decl := clay.ElementDeclaration{
		layout = {sizing = {width = width > 0 ? clay.SizingFixed(width) : clay.SizingGrow({})},
			childAlignment = {x = width > 0 ? .Right : .Left}},
		clip = {horizontal = width == 0},
	}
	if clay.UI()(decl) {
		ui.ui_label_ex(&o.ctx, &o.theme, text, color, o.theme.small_font_size + 1)
	}
}

@(private)
rating_color :: proc(ms: f32) -> foster.Color {
	if ms <= TARGET_MS * 1.05 do return {96, 214, 120, 255}
	if ms <= TARGET_MS * 2.05 do return {236, 196, 82, 255}
	return {236, 92, 84, 255}
}
