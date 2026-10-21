package shader_lab

// 调色板会话持有稳定组名/字段 ID；打开时记下原色，实时预览，取消完整恢复。
// 切换目标、字段重载、Escape 或宿主 cancel（离焦、隐藏）时取消。只编辑临时预览值，不创建材质存档。
// 分区：颜色转换 / 会话 / ImGui 弹窗。
import "core:fmt"
import "core:math"
import "core:strings"

import foster "olib:foster"
import sh "olib:kit/rendering/shader"
import imgui "olib:thirdparty/odin-imgui"

Color_Picker :: struct {
	open: bool,
	group, field, label: string,
	original: [4]f32,
	color: [4]f32, // 归一化 RGBA，ColorPicker4 直接编辑
	minimum, maximum: f32,
}

COLOR_POPUP :: "调色板###color-picker"
COLOR_PRESETS :: [8][3]f32{{1, 1, 1}, {0, 0, 0}, {1, 0.2, 0.2}, {1, 0.65, 0.1},
	{0.3, 0.9, 0.4}, {0.1, 0.75, 1}, {0.4, 0.3, 1}, {1, 0.3, 0.7}}

color_hsv_to_rgb :: proc(hsv: [3]f32) -> [3]f32 {
	h := (hsv[0] - math.floor(hsv[0]))*6
	c := hsv[2]*hsv[1]
	x := c*(1-abs(math.mod(h, 2)-1))
	m := hsv[2]-c
	rgb: [3]f32
	switch int(h) {
	case 0: rgb = {c, x, 0}
	case 1: rgb = {x, c, 0}
	case 2: rgb = {0, c, x}
	case 3: rgb = {0, x, c}
	case 4: rgb = {x, 0, c}
	case: rgb = {c, 0, x}
	}
	return {rgb[0]+m, rgb[1]+m, rgb[2]+m}
}

color_rgb_to_hsv :: proc(rgb: [3]f32) -> [3]f32 {
	hi := max(rgb[0], rgb[1], rgb[2])
	lo := min(rgb[0], rgb[1], rgb[2])
	delta := hi-lo
	h: f32
	if delta > 0.00001 {
		if hi == rgb[0] {
			h = (rgb[1]-rgb[2])/delta
		} else if hi == rgb[1] {
			h = 2+(rgb[2]-rgb[0])/delta
		} else {
			h = 4+(rgb[0]-rgb[1])/delta
		}
		h /= 6
		if h < 0 do h += 1
	}
	return {h, hi > 0 ? delta/hi : 0, hi}
}

color_rgba :: proc(value: [4]f32) -> foster.Color {
	return {u8(math.clamp(value[0], 0, 1)*255+0.5), u8(math.clamp(value[1], 0, 1)*255+0.5),
		u8(math.clamp(value[2], 0, 1)*255+0.5), u8(math.clamp(value[3], 0, 1)*255+0.5)}
}

color_normalize :: proc(value: [4]f32, minimum, maximum: f32) -> [4]f32 {
	result: [4]f32
	for v, i in value do result[i] = math.clamp((v-minimum)/max(maximum-minimum, 0.00001), 0, 1)
	return result
}

// ==============================================================================
// 会话：不跨帧借用参数切片内的指针
// ==============================================================================

color_picker_target :: proc(s: ^Session) -> ^sh.Value {
	p := &s.color_picker
	for &group in s.parameters[:s.program_count] {
		if !group.available || group.name != p.group do continue
		for f, i in group.live.fields {
			if f.id == p.field && f.kind == .Color do return &group.values[i]
		}
	}
	return nil
}

color_picker_close :: proc(s: ^Session, accept: bool) {
	p := &s.color_picker
	if !p.open do return
	if !accept {
		if value := color_picker_target(s); value != nil do value.number = p.original
	}
	p.open = false
	delete(p.group)
	delete(p.field)
	delete(p.label)
	p.group = ""
	p.field = ""
	p.label = ""
}

color_picker_dispose :: proc(s: ^Session) {
	color_picker_close(s, false)
}

color_picker_open :: proc(s: ^Session, group: ^Parameter_State, field: int) {
	color_picker_close(s, false)
	p := &s.color_picker
	f := group.live.fields[field]
	p.group = strings.clone(group.name)
	p.field = strings.clone(f.id)
	p.label = strings.clone(f.label)
	p.original = group.values[field].number
	p.minimum = f.minimum
	p.maximum = f.maximum
	p.color = color_normalize(p.original, p.minimum, p.maximum)
	p.open = true
	s.orbiting = false
}

// ==============================================================================
// ImGui 弹窗：模态，应用 / 取消；ColorPicker4 的色域、色相和透明度区域按 ImGui 1.92 的布局登记矩形
// ==============================================================================

color_picker_popup :: proc(s: ^Session) {
	p := &s.color_picker
	if p.open && !imgui.IsPopupOpen(COLOR_POPUP) do imgui.OpenPopup(COLOR_POPUP)
	if !imgui.BeginPopupModal(COLOR_POPUP, nil, {.AlwaysAutoResize, .NoSavedSettings}) do return
	defer imgui.EndPopup()
	value := color_picker_target(s)
	if !p.open || value == nil || s.parameters[s.selected].name != p.group {
		color_picker_close(s, false)
		imgui.CloseCurrentPopup()
		return
	}
	style := imgui.GetStyle()
	lab_text(p.label)
	imgui.SetNextItemWidth(imgui.GetFontSize()*17)
	origin := imgui.GetCursorScreenPos()
	width := imgui.CalcItemWidth()
	imgui.ColorPicker4("##color", &p.color, {.AlphaBar, .NoSidePreview, .PickerHueBar, .AlphaPreviewHalf})
	bar := imgui.GetFrameHeight()
	square := max(bar, width - 2*(bar + style.ItemInnerSpacing.x))
	hue := origin.x + square + style.ItemInnerSpacing.x
	alpha := hue + bar + style.ItemInnerSpacing.x
	s.widgets[widget_key("color-sv")] = {origin, {origin.x + square, origin.y + square}}
	s.widgets[widget_key("color-hue")] = {{hue, origin.y}, {hue + bar, origin.y + square}}
	s.widgets[widget_key("color-alpha")] = {{alpha, origin.y}, {alpha + bar, origin.y + square}}
	for preset, i in COLOR_PRESETS {
		if i > 0 do imgui.SameLine()
		id := fmt.tprintf("color-preset:%d", i)
		if imgui.ColorButton(fmt.ctprintf("##%s", id), {preset[0], preset[1], preset[2], 1}, {}, {bar, bar}) {
			p.color = {preset[0], preset[1], preset[2], p.color[3]}
		}
		track(s, id)
	}
	original := color_normalize(p.original, p.minimum, p.maximum)
	lab_dim("原色 / 当前")
	if imgui.ColorButton("##color-original", original, {.AlphaPreviewHalf}, {bar*3, bar}) do p.color = original
	track(s, "color-original")
	imgui.SameLine()
	_ = imgui.ColorButton("##color-current", p.color, {.AlphaPreviewHalf}, {bar*3, bar})
	color := color_rgba(p.color)
	imgui.SameLine()
	lab_text(fmt.tprintf("#%02X%02X%02X%02X", color.R, color.G, color.B, color.A))
	accept := lab_button(s, "color-apply", "应用")
	imgui.SameLine()
	close := lab_button(s, "color-cancel", "取消") || accept
	for v, i in p.color do value.number[i] = p.minimum+v*(p.maximum-p.minimum)
	if close {
		color_picker_close(s, accept)
		imgui.CloseCurrentPopup()
	}
}
