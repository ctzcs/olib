// perf_imgui —— 用 Dear ImGui 画 perf_overlay 的悬浮性能面板。
//
// 采样仍由 perf_overlay.Overlay 负责：宿主每帧调用 perf.frame，不需要 perf.init（那是 kit/ui 版的
// 字体与渲染器）。本包只在宿主的 ImGui 帧里提交一个窗口，不初始化 ImGui、不读取 foster 输入。
// 窗口不接收鼠标、不抢焦点、不保存布局，输入分配仍由宿主按 WantCaptureMouse 决定。
//
// 分区：
//   绘制 —— draw / 面板内容
//   曲线与表格
package perf_imgui

import "core:fmt"

import foster "olib:foster"
import perf "olib:kit/tools/perf_overlay"
import imgui "olib:thirdparty/odin-imgui"

// ------------------------------------------------------------------------------
// 绘制
// ------------------------------------------------------------------------------

WINDOW :: "Perf##olib_perf_overlay"
MARGIN :: 12 // 与视口工作区边缘的距离（逻辑像素，随 ImGui 缩放）
GRAPH_BAR_WIDTH :: 2
GRAPH_HEIGHT :: 48
BG_ALPHA :: 0.88

// 在 imgui_foster.BeginRender 与 EndRender 之间调用；visible 为 false 时不提交窗口。
// 面板贴在主视口工作区的 o.corner 角，尺寸跟随 ImGui 的界面缩放。
draw :: proc(o: ^perf.Overlay) {
	if !o.visible do return
	scale := ui_scale()
	viewport := imgui.GetMainViewport()
	right := o.corner == .Top_Right || o.corner == .Bottom_Right
	bottom := o.corner == .Bottom_Right || o.corner == .Bottom_Left
	margin := MARGIN * scale
	pos := viewport.WorkPos
	pos.x += right ? viewport.WorkSize.x - margin : margin
	pos.y += bottom ? viewport.WorkSize.y - margin : margin
	imgui.SetNextWindowPos(pos, .Always, {right ? 1 : 0, bottom ? 1 : 0})
	imgui.SetNextWindowBgAlpha(BG_ALPHA)
	flags := imgui.WindowFlags_NoDecoration | imgui.WindowFlags_NoInputs |
		{.AlwaysAutoResize, .NoSavedSettings, .NoFocusOnAppearing, .NoMove, .NoDocking}
	if imgui.Begin(WINDOW, nil, flags) do contents(o, scale)
	imgui.End()
}

// GetFontSize 已包含 DPI 与界面缩放；与基础字号之比用于缩放曲线尺寸。
@(private)
ui_scale :: proc() -> f32 {
	base := imgui.GetStyle().FontSizeBase
	return base > 0 ? imgui.GetFontSize() / base : 1
}

@(private)
contents :: proc(o: ^perf.Overlay, scale: f32) {
	s := o.summary
	base := imgui.GetStyle().FontSizeBase
	imgui.PushFontFloat(nil, base * 1.25)
	text_colored(fmt.tprintf("%.0f FPS", s.fps), perf.rating_color(s.avg_ms))
	imgui.PopFont()
	imgui.SameLine()
	imgui.TextUnformatted(fmt.ctprintf("%.2f ms", s.avg_ms))
	imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
	imgui.TextUnformatted(fmt.ctprintf("min %.1f  max %.1f ms  1%% low %.0f FPS", s.min_ms, s.max_ms, s.low1_fps))
	imgui.PopStyleColor()
	graph(o, scale)
	scopes(o)
}

// ------------------------------------------------------------------------------
// 曲线与表格
// ------------------------------------------------------------------------------

// 与 kit/ui 版一致：最近 GRAPH_BARS 帧，最新在右；纵轴至少 33 ms，更长的帧出现时整体压缩；细线为 60 FPS。
@(private)
graph :: proc(o: ^perf.Overlay, scale: f32) {
	bar_w := GRAPH_BAR_WIDTH * scale
	size := imgui.Vec2{perf.GRAPH_BARS * bar_w, GRAPH_HEIGHT * scale}
	origin := imgui.GetCursorScreenPos()
	imgui.Dummy(size)
	list := imgui.GetWindowDrawList()
	bottom := origin.y + size.y
	imgui.DrawList_AddRectFilled(list, origin, origin + size, imgui.ColorConvertFloat4ToU32({0, 0, 0, 0.35}))
	bars := min(o.count, perf.GRAPH_BARS)
	top: f32 = 2 * perf.TARGET_MS
	for i in 0 ..< bars do top = max(top, perf.history_at(o, i))
	for i in 0 ..< bars {
		ms := perf.history_at(o, i)
		x := origin.x + size.x - f32(i + 1) * bar_w
		h := max(1, ms / top * size.y)
		imgui.DrawList_AddRectFilled(list, {x, bottom - h}, {x + bar_w, bottom}, color_u32(perf.rating_color(ms)))
	}
	y := bottom - perf.TARGET_MS / top * size.y
	imgui.DrawList_AddLine(list, {origin.x, y}, {origin.x + size.x, y},
		imgui.ColorConvertFloat4ToU32({1, 1, 1, 0.43}), max(1, scale))
}

@(private)
scopes :: proc(o: ^perf.Overlay) {
	if o.scope_count == 0 do return
	if !imgui.BeginTable("##scopes", 3, imgui.TableFlags_SizingFixedFit) do return
	imgui.TableSetupColumn("scope", {.WidthStretch})
	imgui.TableSetupColumn("ms/frame")
	imgui.TableSetupColumn("calls")
	imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
	imgui.TableHeadersRow()
	imgui.PopStyleColor()
	for row in o.scopes[:o.scope_count] {
		imgui.TableNextRow()
		imgui.TableNextColumn()
		imgui.TextUnformatted(fmt.ctprintf("%s", row.name))
		imgui.TableNextColumn()
		right_aligned(fmt.ctprintf("%.2f", row.ms_per_frame))
		imgui.TableNextColumn()
		right_aligned(fmt.ctprintf("%.1f", row.calls_per_frame))
	}
	imgui.EndTable()
}

@(private)
right_aligned :: proc(text: cstring) {
	offset := imgui.GetContentRegionAvail().x - imgui.CalcTextSize(text).x
	if offset > 0 do imgui.SetCursorPosX(imgui.GetCursorPosX() + offset)
	imgui.TextUnformatted(text)
}

@(private)
text_colored :: proc(text: string, color: foster.Color) {
	imgui.PushStyleColor(.Text, color_u32(color))
	imgui.TextUnformatted(fmt.ctprintf("%s", text))
	imgui.PopStyleColor()
}

// foster.Color 是 RGBA8，与 ImGui 的 IM_COL32 打包顺序（R 在最低字节）一致。
@(private)
color_u32 :: proc(c: foster.Color) -> u32 {
	return u32(c.R) | u32(c.G) << 8 | u32(c.B) << 16 | u32(c.A) << 24
}
