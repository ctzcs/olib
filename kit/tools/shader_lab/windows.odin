package shader_lab

// 控制窗口：播放控制、工作区、Shader 选择、Pass 流程、参数 / 预览设置与诊断。
// 选择参数不会隐式切换预览输出；布局、滚动和停靠交给宿主的 ImGui。
// 分区：控件封装 / 控制窗口 / 预览设置与诊断。
import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"

import imgui "olib:thirdparty/odin-imgui"
import imgui_foster "olib:thirdparty/odin-imgui/imgui_impl_ofoster"

// 界面用到的内置图标；init 时挑出来缩成 ICON_CELL 像素的小图标表（约为绘制尺寸的 2 倍）。
@(rodata)
ICON_NAMES := [?]string{
	"media/play", "media/pause", "media/next-frame", "ui/refresh", "media/image", "media/pc-host",
	"ui/slider", "ui/settings", "media/display", "ui/visible", "media/camera", "media/code",
	"media/folder", "ui/save", "media/import", "editing/undo", "media/clapper", "symbols/plus",
}
ICON_CELL :: 40

ERROR_COLOR :: imgui.Vec4{1, 0.48, 0.45, 1}

// ImGui 屏幕坐标（窗口逻辑坐标，与鼠标输入相同）。
Widget_Rect :: struct {
	min, max: [2]f32,
}

// ==============================================================================
// 控件封装：图标按钮、复选框与控件矩形登记
// ==============================================================================

@(private)
widget_key :: proc(id: string) -> u64 {
	return hash.fnv64a(transmute([]u8)id)
}

// 登记上一个控件的矩形，宿主或外部检查可按稳定 ID 定位（例如注入点击）。
track :: proc(s: ^Session, id: string) {
	s.widgets[widget_key(id)] = {imgui.GetItemRectMin(), imgui.GetItemRectMax()}
}

// 最近一次 draw 登记的控件矩形；该帧没有画出这个控件时 found=false。
widget_rect :: proc(s: ^Session, id: string) -> (rect: Widget_Rect, found: bool) {
	rect, found = s.widgets[widget_key(id)]
	return
}

cstr :: proc(text: string) -> cstring {
	return strings.clone_to_cstring(text, context.temp_allocator)
}

lab_button :: proc(s: ^Session, id, label: string, selected := false, grow := false, icon := "") -> bool {
	clicked := imgui_foster.IconButton(&s.icons, id, icon, label, selected, grow ? -1 : 0)
	track(s, id)
	return clicked
}

lab_checkbox :: proc(s: ^Session, id: string, checked: bool) -> bool {
	value := checked
	clicked := imgui.Checkbox(fmt.ctprintf("##%s", id), &value)
	track(s, id)
	return clicked
}

lab_text :: proc(text: string) {
	imgui.TextUnformatted(cstr(text))
}

lab_dim :: proc(text: string) {
	imgui.PushStyleColor(.Text, imgui.GetColorU32(.TextDisabled))
	imgui.TextUnformatted(cstr(text))
	imgui.PopStyleColor()
}

// 编译器路径常没有空格；ImGui 在宽度不够时按字符换行，完整原文仍输出到控制台。
lab_error :: proc(text: string) {
	imgui.PushStyleColorImVec4(.Text, ERROR_COLOR)
	imgui.PushTextWrapPos(0)
	imgui.TextUnformatted(cstr(text))
	imgui.PopTextWrapPos()
	imgui.PopStyleColor()
}

// 下一个图标按钮放得下就接在同一行，否则换行；宽度与 IconButton 的计算一致。
lab_same_line :: proc(label: string, icon := true) {
	style := imgui.GetStyle()
	width := imgui.CalcTextSize(cstr(label)).x + style.FramePadding.x*2
	if icon do width += math.round(imgui.GetFontSize()*1.25) + (label != "" ? style.ItemInnerSpacing.x : 0)
	right := imgui.GetCursorScreenPos().x + imgui.GetContentRegionAvail().x
	if imgui.GetItemRectMax().x + style.ItemSpacing.x + width <= right do imgui.SameLine()
}

// 把下一个控件推到当前行最右，宽度 width。
align_right :: proc(width: f32) {
	imgui.SameLine()
	imgui.SetCursorPosX(imgui.GetCursorPosX() + max(0, imgui.GetContentRegionAvail().x - width))
}

// ==============================================================================
// 控制窗口
// ==============================================================================

control_window :: proc(s: ^Session) {
	imgui.SetNextWindowSize({360, 680}, .FirstUseEver)
	visible := imgui.Begin(CONTROL_WINDOW)
	defer imgui.End()
	if !visible do return
	if lab_button(s, "pause", s.paused ? "播放" : "暂停", icon = s.paused ? "media/play" : "media/pause") {
		s.paused = !s.paused
	}
	if s.selected_shader >= 0 {
		lab_same_line("单步")
		if lab_button(s, "shader-step", "单步", icon = "media/next-frame") do step(s)
		lab_same_line("重置反馈")
		if lab_button(s, "shader-reset", "重置反馈", icon = "ui/refresh") do reset_history(s)
	}
	failed := s.bank_error != "" || s.parameter_watch.status == .Error
	if failed {
		imgui.TextColored(ERROR_COLOR, "编译失败 · 保留上次结果")
	} else {
		lab_dim(s.pending_bank != nil ? "正在编译" : "LIVE · 保存源码即更新")
	}
	imgui.Separator()
	if lab_button(s, "workspace:2d", "2D", s.workspace == 0, icon = "media/image") do select_workspace(s, 0)
	imgui.SameLine()
	if lab_button(s, "workspace:3d", "3D", s.workspace == 1, icon = "media/pc-host") do select_workspace(s, 1)
	shader_selector(s)
	if s.selected_shader >= 0 {
		lab_dim("处理流程 · 勾选启用，点击编辑")
		rows := clamp(f32(len(s.shaders[s.selected_shader].order)), 1, 6)
		height := rows*imgui.GetFrameHeightWithSpacing() + imgui.GetStyle().WindowPadding.y*2
		if imgui.BeginChild("passes", {0, height}, {.Borders}) do passes_panel(s)
		imgui.EndChild()
	}
	if lab_button(s, "inspector-parameters", "参数", !s.preview_settings, icon = "ui/slider") {
		cancel(s)
		s.preview_settings = false
	}
	lab_same_line("预览设置")
	if lab_button(s, "preview-settings", "预览设置", s.preview_settings, icon = "ui/settings") {
		cancel(s)
		s.preview_settings = true
	}
	// 详情区单独滚动，切换参数 / 预览设置不移动上方的选择区。
	if imgui.BeginChild("inspector", {0, 0}, {.Borders}) {
		if s.preview_settings {
			preview_options(s)
		} else {
			inspector_panel(s)
		}
		lab_diagnostics(s)
	}
	imgui.EndChild()
	track(s, "inspector")
}

// ==============================================================================
// 预览设置与诊断
// ==============================================================================

preview_options :: proc(s: ^Session) {
	if s.workspace_empty || s.program_count == 0 do return
	lab_dim("预览载体 · 不会切换 Shader")
	model3d := s.selected_shader >= 0 ? shader_has_3d(s, s.selected_shader) : s.parameters[s.selected].live.preview == "3d"
	first := true
	for id, i in ([4]string{"2D / Fullscreen", "2D / Sprite", "3D / Sphere", "3D / Cube"}) {
		if model3d != (i >= 2) do continue
		names := [4]string{"全屏", "精灵", "球体", "立方体"}
		if !first do lab_same_line(names[i], icon = false)
		first = false
		if lab_button(s, id, names[i], s.mode == i) do s.mode = i
	}
	if s.preview_hooks.record != nil {
		if lab_button(s, "preview-host", "使用宿主模型", s.custom_preview) do s.custom_preview = !s.custom_preview
	}
	if model3d {
		lab_dim("预览上右键拖动旋转 / 滚轮缩放")
		if lab_button(s, "reset-camera", "重置相机", icon = "media/camera") {
			s.yaw = 0.4
			s.pitch = 0.25
			s.distance = 4
		}
	}
	if s.selected_shader >= 0 {
		if lab_button(s, "settings-step", "单步", icon = "media/next-frame") do step(s)
		lab_same_line("重置反馈")
		if lab_button(s, "settings-reset", "重置反馈", icon = "ui/refresh") do reset_history(s)
	}
	if lab_button(s, "retry", "重新编译", icon = "media/code") {
		s.parameter_watch.has_attempted = false
	}
}

lab_diagnostics :: proc(s: ^Session) {
	if s.bank_error != "" do lab_error(s.bank_error)
	if s.parameter_watch.diagnostic != "" do lab_error(s.parameter_watch.diagnostic)
	if s.program_count > 0 && s.programs[s.selected].diagnostic != "" {
		if imgui.BeginChild("diagnostic", {0, 170}, {.Borders}) {
			message, _ := strings.replace_all(s.programs[s.selected].diagnostic, s.source_root,
				"shaders", context.temp_allocator)
			lab_error(message)
		}
		imgui.EndChild()
	}
}
