package ui

import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   输入 —— 逻辑坐标 / 导航动作 / 游戏输入消费
//   交互 —— 稳定 ID 的捕获、焦点、禁用态与模态隔离

UI_Input_Capture :: struct {
	pointer, keyboard: bool,
}

// 由游戏输入映射生成的单帧动作，ui_end 消费并清空。
// next: Tab/Shift+Tab 或方向导航；adjust: 滑条左右步数；activate: 确认边沿。
UI_Navigation :: struct {
	next: int,
	adjust: f32,
	activate, cancel: bool,
}

UI_Focus_Entry :: struct {
	id, scope: u32,
}

UI_Trigger :: enum {
	Release,
	Press,
}

UI_Widget_Options :: struct {
	disabled: bool,
	trigger: UI_Trigger,
}

UI_Interaction :: struct {
	hovered, active, focused, disabled: bool,
	pressed, released, clicked: bool,
}

// viewport 与指针都使用渲染目标像素；逻辑尺寸 = viewport / scale。
// 高 DPI 窗口需调用者先将窗口坐标转换为渲染目标像素。
ui_set_viewport :: proc(ctx: ^UI_Context, viewport: foster.Rect, scale: f32 = 1) {
	ctx.scale = max(scale, 0.01)
	ctx.viewport_origin = {viewport.X, viewport.Y}
	ui_set_dimensions(ctx, max(viewport.Width, 0) / ctx.scale, max(viewport.Height, 0) / ctx.scale)
}

ui_set_navigation :: proc(ctx: ^UI_Context, navigation: UI_Navigation) {
	ctx.navigation = navigation
}

// 在本帧声明完成后查询，再决定是否把输入交给游戏世界。
ui_input_capture :: proc(ctx: ^UI_Context) -> UI_Input_Capture {
	return ctx.input
}

// 帧开始前指定模态作用域；空字符串关闭。模态期间背景控件不接受输入。
// 打开/关闭会取消当前捕获和焦点，避免弹窗关闭后确认落到背景按钮。
ui_set_modal :: proc(ctx: ^UI_Context, id: string) {
	modal := len(id) > 0 ? clay.ID(id).id : 0
	if ctx.modal_id != modal {
		ctx.active_id = 0
		ctx.focused_id = 0
		ctx.modal_id = modal
		ctx.modal_changed = true
	}
}

// modal 内容声明前进入同名 scope，离开时设回空字符串。
ui_set_scope :: proc(ctx: ^UI_Context, id: string) {
	ctx.scope_id = len(id) > 0 ? clay.ID(id).id : 0
}

// 非交互面板也应挡住世界点击；声明前按上一帧的布局查询。
ui_block_pointer :: proc(ctx: ^UI_Context, id: string) {
	if (ctx.modal_id == 0 || ctx.scope_id == ctx.modal_id) && clay.PointerOver(clay.ID(id)) {
		ctx.input.pointer = true
	}
}

// 最近一次 ui_end 的布局矩形（逻辑坐标，不含 ui_set_visual 变换）；元素未声明过时 ok=false。
// 声明前调用：浮动元素跟随布局槽位、拖放目标命中等需要先知道别处的位置。
ui_element_rect :: proc(ctx: ^UI_Context, id: string) -> (rect: foster.Rect, ok: bool) {
	clay.SetCurrentContext(ctx.clay_context)
	data := clay.GetElementData(clay.ID(id))
	bb := data.boundingBox
	return {bb.x, bb.y, bb.width, bb.height}, bool(data.found)
}

// 设置焦点；包含它的滚动区在下一次 ui_begin 滚到能看见它。
ui_focus :: proc(ctx: ^UI_Context, id: string) {
	ctx.focused_id = clay.ID(id).id
	ctx.focus_scroll = true
}

// 按上一帧布局，把包含焦点控件的滚动区滚到刚好完整可见（只调纵向）；控件已可见时不动。
// 判断包含关系用矩形：控件横向落在容器内、纵向落在容器的内容范围内。
@(private)
ui_focus_scroll :: proc(ctx: ^UI_Context) {
	if !ctx.focus_scroll || ctx.focused_id == 0 {
		ctx.focus_scroll = false
		return
	}
	ctx.focus_scroll = false
	target := clay.GetElementData(clay.ElementId{id = ctx.focused_id})
	if !target.found {
		return
	}
	bb := target.boundingBox
	for scroll in ctx.scrolls {
		container := clay.GetElementData(clay.ElementId{id = scroll.id})
		data := clay.GetScrollContainerData(clay.ElementId{id = scroll.id})
		if !container.found || !data.found || data.scrollPosition == nil {
			continue
		}
		view := container.boundingBox
		top := view.y + data.scrollPosition.y
		if bb.x < view.x - 0.5 || bb.x + bb.width > view.x + view.width + 0.5 ||
		   bb.y < top - 0.5 || bb.y + bb.height > top + data.contentDimensions.height + 0.5 {
			continue
		}
		next := data.scrollPosition.y
		if bb.y < view.y {
			next += view.y - bb.y
		} else if bb.y + bb.height > view.y + view.height {
			next -= bb.y + bb.height - (view.y + view.height)
		}
		data.scrollPosition.y = clamp(next, -max(0, data.contentDimensions.height - view.height), 0)
	}
}

@(private)
ui_navigation_begin :: proc(ctx: ^UI_Context) {
	if ctx.navigation.cancel {
		ctx.active_id = 0
		ctx.focused_id = 0
		ctx.dropdown_id = 0
		ctx.drag = {}
		ctx.input.keyboard = true
		return
	}
	count, current := 0, -1
	for entry in ctx.previous_widgets {
		if ctx.modal_id != 0 && entry.scope != ctx.modal_id {
			continue
		}
		if entry.id == ctx.focused_id {
			current = count
		}
		count += 1
	}
	if ctx.navigation.next == 0 || count == 0 {
		return
	}
	direction := ctx.navigation.next > 0 ? 1 : -1
	index := current < 0 ? (direction > 0 ? 0 : count - 1) : (current + direction + count) % count
	ctx.input.keyboard = true
	i := 0
	for entry in ctx.previous_widgets {
		if ctx.modal_id != 0 && entry.scope != ctx.modal_id {
			continue
		}
		if i == index {
			ctx.focused_id = entry.id
			ctx.focus_scroll = true
			break
		}
		i += 1
	}
}

// 自定义控件也可复用；每个 ID 每帧只调用一次，且 ID 必须唯一、帧间稳定。
ui_interact :: proc(ctx: ^UI_Context, id: string, options: UI_Widget_Options = {}) -> UI_Interaction {
	element := clay.ID(id)
	allowed := ctx.modal_id == 0 || ctx.scope_id == ctx.modal_id
	state := UI_Interaction{disabled = options.disabled || !allowed}
	state.hovered = allowed && clay.PointerOver(element)
	if state.hovered {
		ctx.input.pointer = true
	}
	if state.disabled {
		if ctx.active_id == element.id {
			ctx.active_id = 0
		}
		return state
	}
	append(&ctx.widgets, UI_Focus_Entry{element.id, ctx.scope_id})
	if state.hovered && ui_clicked(ctx) && ctx.active_id == 0 && !ctx.navigation.cancel {
		ctx.active_id = element.id
		ctx.focused_id = element.id
		state.pressed = true
	}
	state.focused = ctx.focused_id == element.id
	if ctx.active_id == element.id {
		ctx.active_seen = true
		ctx.input.pointer = true
		state.active = ctx.pointer_down
		state.released = ui_released(ctx)
		state.clicked = options.trigger == .Press ? state.pressed : state.released && state.hovered
		// 拖动结束的那次松开是放置，不算点击。
		if ctx.drag.dragging && ctx.drag.source == element.id {
			state.clicked = state.clicked && options.trigger == .Press
		}
	}
	if state.focused && (ctx.navigation.activate || ctx.navigation.adjust != 0) {
		ctx.input.keyboard = true
		state.clicked = state.clicked || ctx.navigation.activate
	}
	return state
}
