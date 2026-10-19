// perf_overlay 单元测试：帧时间汇总、作用域增量与 CPU 布局（无 GPU）。
#+test
package perf_overlay

import "core:testing"
import "core:time"

import profiler "olib:core/profiler"
import foster "olib:foster"
import ui "olib:kit/ui"

@(test)
summarize_frame_times :: proc(t: ^testing.T) {
	samples := make([]f32, 200, context.temp_allocator)
	for &ms in samples do ms = 10
	samples[7] = 40
	samples[150] = 20
	s := summarize(samples)
	testing.expect_value(t, s.count, 200)
	testing.expect_value(t, s.min_ms, 10)
	testing.expect_value(t, s.max_ms, 40)
	testing.expect_value(t, s.avg_ms, f32(2040) / 200)
	// 最慢 1%（2 帧）平均 30 ms。
	testing.expect_value(t, s.low1_fps, f32(1000) / 30)
	testing.expect_value(t, summarize(nil), Frame_Summary{})
}

@(test)
frame_refreshes_on_interval :: proc(t: ^testing.T) {
	o: Overlay
	defer dispose(&o)
	frame(&o, 0.010)
	testing.expect_value(t, o.summary.count, 1) // 首帧立即出数
	frame(&o, 0.020)
	testing.expect_value(t, o.summary.count, 1) // 未到刷新间隔
	for _ in 0 ..< 30 do frame(&o, 0.020)
	testing.expect(t, o.summary.count > 1)
	testing.expect_value(t, history_at(&o, 0), 20)

	for _ in 0 ..< HISTORY * 2 do frame(&o, 0.005) // 刷新时环形缓冲已全部替换
	testing.expect_value(t, o.count, HISTORY)
	testing.expect_value(t, o.summary.max_ms, 5)
}

@(test)
scopes_report_deltas :: proc(t: ^testing.T) {
	o: Overlay
	defer dispose(&o)
	stats := make(map[string]profiler.Profile_Stat, context.temp_allocator)
	stats["update"] = {count = 10, total = 20 * time.Millisecond}
	stats["render"] = {count = 10, total = 50 * time.Millisecond}
	stats["idle"] = {count = 3, total = time.Millisecond}
	scopes_collect(&o, stats, 10)
	testing.expect_value(t, o.scope_count, 3)
	testing.expect_value(t, o.scopes[0].name, "render")
	testing.expect_value(t, o.scopes[0].ms_per_frame, 5)
	testing.expect_value(t, o.scopes[1].calls_per_frame, 1)

	// 只统计增量；没有新调用的作用域不显示。
	stats["update"] = {count = 30, total = 80 * time.Millisecond}
	scopes_collect(&o, stats, 20)
	testing.expect_value(t, o.scope_count, 1)
	testing.expect_value(t, o.scopes[0].name, "update")
	testing.expect_value(t, o.scopes[0].ms_per_frame, 3)

	// 统计表被重建后计数回退，按新值从零计算。
	stats["update"] = {count = 2, total = 4 * time.Millisecond}
	scopes_collect(&o, stats, 2)
	testing.expect_value(t, o.scopes[0].ms_per_frame, 2)
}

@(test)
scopes_keep_slowest :: proc(t: ^testing.T) {
	o: Overlay
	defer dispose(&o)
	names := [?]string{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j"}
	stats := make(map[string]profiler.Profile_Stat, context.temp_allocator)
	for name, i in names do stats[name] = {count = 1, total = time.Duration(i + 1) * time.Millisecond}
	scopes_collect(&o, stats, 1)
	testing.expect_value(t, o.scope_count, MAX_SCOPES)
	testing.expect_value(t, o.scopes[0].name, "j")
	testing.expect_value(t, o.scopes[MAX_SCOPES - 1].name, "c")
}

@(test)
layout_builds_without_errors :: proc(t: ^testing.T) {
	font := new(foster.MsdfFont)
	defer free(font)
	font.Size = 32
	font.Ascent = 24
	font.Descent = -8
	font.LineHeight = 36
	font.Image = foster.Image{Width = 64, Height = 64}
	append(&font.Characters, foster.MsdfCharacter{Codepoint = '1', SourceRect = {0, 0, 16, 20}, Advance = 18})
	defer delete(font.Characters)

	o: Overlay
	defer dispose(&o)
	o.visible = true
	o.corner = .Bottom_Left
	for _ in 0 ..< 200 do frame(&o, 0.016)
	stats := make(map[string]profiler.Profile_Stat, context.temp_allocator)
	stats["111"] = {count = 4, total = 8 * time.Millisecond}
	scopes_collect(&o, stats, 4)

	testing.expect(t, ui.ui_init(&o.ctx, 800, 600))
	o.theme = ui.UI_THEME_DARK
	o.theme.body_font_id = u16(ui.ui_register_font(&o.ctx, font, {}))
	ui.ui_begin(&o.ctx, 0)
	panel_layout(&o)
	ops := ui.ui_translate(&o.ctx, ui.ui_end(&o.ctx))
	defer delete(ops)
	testing.expect_value(t, o.ctx.error_count, 0)
	ui.ui_dispose(&o.ctx)
	quads := 0
	for op in ops do if op.kind == .Quad do quads += 1
	// 面板背景 + 曲线背景 + 每帧一根柱 + 60 FPS 线。
	testing.expectf(t, quads >= GRAPH_BARS + 3, "quad 数: %d", quads)
}
