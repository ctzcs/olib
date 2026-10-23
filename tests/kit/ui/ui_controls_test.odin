// 下拉框、虚拟列表、拖放与焦点自动滚动：真实 clay 布局，按帧驱动指针与导航（全 CPU）。
#+test
package ui

import "core:fmt"
import "core:sync"
import "core:testing"

import clay "olib:thirdparty/clay-odin"

// ------------------------------------------------------------------------------
// 焦点自动滚动
// ------------------------------------------------------------------------------

@(private)
focus_scroll_frame :: proc(ctx: ^UI_Context, nav: UI_Navigation = {}) {
	ui_set_navigation(ctx, nav)
	ui_begin(ctx, 1.0 / 60)
	if clay.UI()(ui_scroll_decl(ctx, "rows", 100, 200, gap = 0)) {
		for i in 0..<20 {
			id := fmt.tprintf("row-%d", i)
			_ = ui_interact(ctx, id)
			if clay.UI()(clay.ElementDeclaration{
				id = clay.ID(id),
				layout = {sizing = {width = clay.SizingFixed(200), height = clay.SizingFixed(20)}},
			}) {}
		}
	}
	ui_end(ctx)
}

@(private)
focus_scroll_y :: proc(ctx: ^UI_Context) -> f32 {
	return clay.GetScrollContainerData(clay.ID("rows")).scrollPosition.y
}

@(test)
focus_change_scrolls_container_to_show_widget :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 400, 300))
	defer ui_dispose(&ctx)
	focus_scroll_frame(&ctx)
	focus_scroll_frame(&ctx)
	testing.expect_value(t, focus_scroll_y(&ctx), f32(0))
	// 第 15 行（300..320）在 100 高的视口下方：滚到底边对齐。
	ui_focus(&ctx, "row-15")
	focus_scroll_frame(&ctx)
	focus_scroll_frame(&ctx)
	testing.expect_value(t, focus_scroll_y(&ctx), f32(-220))
	// 已可见的控件不动滚动。
	ui_focus(&ctx, "row-13")
	focus_scroll_frame(&ctx)
	focus_scroll_frame(&ctx)
	testing.expect_value(t, focus_scroll_y(&ctx), f32(-220))
	// 导航回到上方：顶边对齐。
	ui_focus(&ctx, "row-2")
	focus_scroll_frame(&ctx)
	focus_scroll_frame(&ctx)
	testing.expect_value(t, focus_scroll_y(&ctx), f32(-40))
	// Tab 从第 0 行往回绕到最后一行，滚到底。
	ui_focus(&ctx, "row-0")
	focus_scroll_frame(&ctx)
	focus_scroll_frame(&ctx, {next = -1})
	focus_scroll_frame(&ctx)
	testing.expect(t, ctx.focused_id == clay.ID("row-19").id)
	testing.expect_value(t, focus_scroll_y(&ctx), f32(-300))
}

// ------------------------------------------------------------------------------
// 下拉框
// ------------------------------------------------------------------------------

@(private)
dropdown_frame :: proc(ctx: ^UI_Context, selected: ^int, x, y: f32, down: bool, nav: UI_Navigation = {}) -> bool {
	options := []string{"Low", "Medium", "High"}
	theme := UI_THEME_DARK
	ui_set_pointer(ctx, x, y, down)
	ui_set_navigation(ctx, nav)
	ui_begin(ctx, 1.0 / 60)
	changed := ui_dropdown(ctx, &theme, "quality", options, selected, 160)
	ui_end(ctx)
	return changed
}

@(private)
center_of :: proc(id: string) -> (x, y: f32) {
	bb := clay.GetElementData(clay.ID(id)).boundingBox
	return bb.x + bb.width/2, bb.y + bb.height/2
}

@(test)
dropdown_opens_selects_and_closes :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 400, 300))
	defer ui_dispose(&ctx)
	selected := 0
	dropdown_frame(&ctx, &selected, -1, -1, false)
	bx, by := center_of("quality")
	dropdown_frame(&ctx, &selected, bx, by, false)
	dropdown_frame(&ctx, &selected, bx, by, true)
	dropdown_frame(&ctx, &selected, bx, by, false)
	testing.expect(t, ctx.dropdown_id == clay.ID("quality").id, "release on the button opens the list")
	dropdown_frame(&ctx, &selected, bx, by, false)
	ox, oy := center_of("quality#2")
	testing.expect(t, oy > by, "options float below the button")
	dropdown_frame(&ctx, &selected, ox, oy, false)
	dropdown_frame(&ctx, &selected, ox, oy, true)
	changed := dropdown_frame(&ctx, &selected, ox, oy, false)
	testing.expect(t, changed && selected == 2 && ctx.dropdown_id == 0, "clicking an option selects it and closes")
	// 再打开，点外面关闭且不改值。
	dropdown_frame(&ctx, &selected, bx, by, true)
	dropdown_frame(&ctx, &selected, bx, by, false)
	testing.expect(t, ctx.dropdown_id != 0)
	dropdown_frame(&ctx, &selected, 390, 290, false)
	dropdown_frame(&ctx, &selected, 390, 290, true)
	testing.expect(t, ctx.dropdown_id == 0 && selected == 2, "pressing outside closes without changing")
	dropdown_frame(&ctx, &selected, 390, 290, false)
	// 键盘：焦点在按钮上按确认打开，焦点落到当前项且不被同一次确认选中；cancel 关闭。
	ui_focus(&ctx, "quality")
	dropdown_frame(&ctx, &selected, -1, -1, false, {activate = true})
	testing.expect(t, ctx.dropdown_id != 0 && ctx.focused_id == clay.ID("quality#2").id && selected == 2)
	dropdown_frame(&ctx, &selected, -1, -1, false, {next = -1})
	changed = dropdown_frame(&ctx, &selected, -1, -1, false, {activate = true})
	testing.expect(t, changed && selected == 1 && ctx.dropdown_id == 0, "navigation picks the previous option")
	dropdown_frame(&ctx, &selected, -1, -1, false, {activate = true})
	dropdown_frame(&ctx, &selected, -1, -1, false, {cancel = true})
	testing.expect(t, ctx.dropdown_id == 0 && selected == 1)
}

// ------------------------------------------------------------------------------
// 虚拟列表
// ------------------------------------------------------------------------------

@(private)
virtual_frame :: proc(ctx: ^UI_Context, scroll: f32 = 0) -> UI_Virtual_Range {
	ui_set_pointer(ctx, 50, 50, false)
	ui_add_scroll(ctx, 0, scroll)
	ui_begin(ctx, 1.0 / 60)
	r := ui_virtual_range(ctx, "big", 1000, 20, 100, overscan = 1)
	if clay.UI()(ui_scroll_decl(ctx, "big", 100, 200, gap = 0)) {
		ui_virtual_spacer(r.before)
		for _ in r.first..<r.last {
			if clay.UI()(clay.ElementDeclaration{
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(20)}},
			}) {}
		}
		ui_virtual_spacer(r.after)
	}
	ui_end(ctx)
	return r
}

@(test)
virtual_list_declares_only_visible_rows :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 400, 300))
	defer ui_dispose(&ctx)
	r := virtual_frame(&ctx)
	testing.expect_value(t, r, UI_Virtual_Range{0, 6, 0, 994*20})
	virtual_frame(&ctx)
	data := clay.GetScrollContainerData(clay.ID("big"))
	testing.expect_value(t, data.contentDimensions.height, f32(1000*20))
	// 直接把滚动位置放到第 500 行，下一帧只声明附近几行。
	data.scrollPosition.y = -10000
	r = virtual_frame(&ctx)
	testing.expect_value(t, r, UI_Virtual_Range{499, 506, 499*20, 494*20})
	virtual_frame(&ctx)
	testing.expect_value(t, clay.GetScrollContainerData(clay.ID("big")).contentDimensions.height, f32(1000*20))
	empty := ui_virtual_range(&ctx, "big", 0, 20, 100)
	testing.expect_value(t, empty, UI_Virtual_Range{})
}

// ------------------------------------------------------------------------------
// 拖放
// ------------------------------------------------------------------------------

Drag_Test_Result :: struct {
	clicked, dragging, dropped: bool,
	payload: int,
}

@(private)
drag_frame :: proc(ctx: ^UI_Context, x, y: f32, down: bool) -> (result: Drag_Test_Result) {
	ui_set_pointer(ctx, x, y, down)
	ui_begin(ctx, 1.0 / 60)
	if clay.UI()(ui_row_decl(40)) {
		state := ui_interact(ctx, "slot-a")
		result.clicked = state.clicked
		result.dragging = ui_drag_source(ctx, "slot-a", state, 7)
		if clay.UI()(clay.ElementDeclaration{
			id = clay.ID("slot-a"),
			layout = {sizing = {width = clay.SizingFixed(50), height = clay.SizingFixed(50)}},
		}) {}
		payload, _, dropped := ui_drop_target(ctx, "slot-b")
		result.dropped = dropped
		result.payload = payload
		if clay.UI()(clay.ElementDeclaration{
			id = clay.ID("slot-b"),
			layout = {sizing = {width = clay.SizingFixed(50), height = clay.SizingFixed(50)}},
		}) {}
	}
	ui_end(ctx)
	return
}

@(test)
drag_threshold_click_and_drop :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 400, 300))
	defer ui_dispose(&ctx)
	drag_frame(&ctx, -1, -1, false)
	// 移动不足阈值：仍是点击。
	drag_frame(&ctx, 20, 20, false)
	drag_frame(&ctx, 20, 20, true)
	small := drag_frame(&ctx, 22, 21, true)
	testing.expect(t, !small.dragging)
	click := drag_frame(&ctx, 22, 21, false)
	testing.expect(t, click.clicked && !click.dropped)
	// 拖过阈值到 slot-b（x 90..140）松开：放置，不算点击。
	drag_frame(&ctx, 20, 20, true)
	moved := drag_frame(&ctx, 60, 20, true)
	testing.expect(t, moved.dragging)
	payload, ok := ui_dragging(&ctx)
	testing.expect(t, ok && payload == 7)
	drag_frame(&ctx, 110, 25, true)
	drop := drag_frame(&ctx, 110, 25, false)
	testing.expect(t, drop.dropped && drop.payload == 7 && !drop.clicked)
	_, ok = ui_dragging(&ctx)
	testing.expect(t, !ok, "drag ends after the release frame")
	// 拖到空白处松开：没有放置，也不算点击。
	drag_frame(&ctx, 20, 20, true)
	drag_frame(&ctx, 20, 120, true)
	miss := drag_frame(&ctx, 20, 120, false)
	testing.expect(t, !miss.dropped && !miss.clicked)
	// cancel 中途取消拖动。
	drag_frame(&ctx, 20, 20, true)
	drag_frame(&ctx, 60, 20, true)
	ui_set_navigation(&ctx, {cancel = true})
	cancelled := drag_frame(&ctx, 110, 25, true)
	testing.expect(t, !cancelled.dragging)
}
