package shader_lab

// 布局只影响预览工作区，不写入材质预设。分隔条拖动可取消；窄面板采用覆盖式侧栏。
import "core:math"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

panel_width :: proc(s: ^Session) -> f32 {
	return max(160, s.sidebar_effective-24-s.parameter_inset)
}

layout_update :: proc(s: ^Session, pixel_w, pixel_h: f32) {
	// 按窗口大小调整逻辑 UI 比例；MSDF 仍直接绘制到最终像素，不缩放已渲染的 UI。
	s.ui_scale = math.clamp(min(pixel_w/1280, pixel_h/800), 1, 1.6)
	w := pixel_w/s.ui_scale
	h := pixel_h/s.ui_scale
	s.compact = w < 760
	s.sidebar_effective = math.clamp(s.sidebar_width, 272, max(272, w-320))
	if s.compact do s.sidebar_effective = min(w-16, s.sidebar_effective)
	x: f32 = 8
	if !s.sidebar_collapsed && !s.compact do x = s.sidebar_effective+16
	s.viewport = {x*s.ui_scale, 96*s.ui_scale, max(1, w-x-8)*s.ui_scale, max(1, h-128)*s.ui_scale}
}

splitter :: proc(s: ^Session, h: f32) {
	state := ui.ui_interact(&s.ctx, "sidebar-splitter")
	if state.pressed {
		s.splitter_original = s.sidebar_width
		s.splitting = true
	}
	if state.active && s.splitting {
		s.sidebar_width = math.clamp(s.ctx.pointer_x-12, 272, max(272, s.ctx.width-320))
	}
	if state.released do s.splitting = false
	decl := clay.ElementDeclaration{
		id = clay.ID("sidebar-splitter"),
		layout = {sizing = {width = clay.SizingFixed(8), height = clay.SizingFixed(h-84)}},
		floating = {attachTo = .Parent, offset = {s.sidebar_effective+8, 52}},
		backgroundColor = ui.ui_clay_color(state.active || state.hovered ? s.theme.primary : s.theme.window_bg),
	}
	if clay.UI()(decl) {}
}
