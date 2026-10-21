package shader_lab

// 渲染到工具自己的原生像素目标，再合成到宿主分配的区域。
import "core:math"
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import ui "olib:kit/ui"

// ==============================================================================
// 绘制：世界原生分辨率 + 4x MSAA；UI 在最终输出原生像素绘制
// ==============================================================================

// region 使用目标最终像素，输出 1:1 合成，不清空宿主目标。返回本帧输入消费。
// 在宿主自己的 ui_begin/ui_end 区间之外调用；多个 Session 可顺序绘制。
render :: proc(s: ^Session, target: foster.DrawableTarget, region: foster.Rect, input: Input) -> ui.UI_Input_Capture {
	if !s.initialized do return {}
	w := int(region.Width)
	h := int(region.Height)
	if w < 320 || h <= 180 {
		cancel(s)
		return {}
	}
	s.region = {math.floor(region.X), math.floor(region.Y), f32(w), f32(h)}
	s.input = input
	s.input.pointer = {input.pointer.x-s.region.X, input.pointer.y-s.region.Y}
	layout_update(s, f32(w), f32(h))
	device := s.device
	if s.output.Width != w || s.output.Height != h {
		foster.TargetDispose(&s.output)
		foster.TargetInit(&s.output, device, w, h)
	}
	if s.pending_bank != nil && bank_apply(s, s.pending_bank, bank_selected_effect(s, s.pending_bank)) do bank_commit(s)
	// 新布局尚未整体通过时，只准备旧包当前效果，不分批应用新的 HLSL。
	_ = bank_apply(s, s.bank, s.selected_effect, s.pending_bank == nil)
	if s.fonts_dirty do validate_parameter_fonts(s)
	panel(s, f32(w), f32(h))
	image: ^foster.Texture
	if s.selected_effect >= 0 && s.effects[s.selected_effect].ready {
		image = effect_render(s, &s.effects[s.selected_effect])
	} else {
		s.step_requested = false
	}
	output := foster.DrawableTargetFromTarget(&s.output)
	foster.GraphicsDeviceClear(device, output, s.theme.window_bg)
	// panel 已生成 UI 命令；先单独合成场景，再叠加 UI，避免缩放文字。
	if image != nil {
		quad(&s.render, image, s.viewport)
	} else {
		// 空工作区直接画到最终输出，不分配替代场景目标。
		r2d.rect(&s.render, s.viewport, foster.Color{17, 21, 26, 255})
	}
	r2d.submit(&s.render, {target = output})
	r2d.submit(&s.batch, {target = output})
	quad(&s.render, foster.TargetAttachment(&s.output), s.region)
	r2d.submit(&s.render, {target = target})
	texture_retire_flush(s)
	// UI 可能刚切换效果；等本帧缩略图与合成命令提交完，再释放旧引用。
	// 新选中项在下一帧开始时创建目标，避免 UI 尚在引用旧纹理时销毁。
	effect_targets_trim(s.bank, s.selected_effect)
	if s.pending_bank != nil do effect_targets_trim(s.pending_bank, bank_selected_effect(s, s.pending_bank))
	s.render_serial += 1
	return s.capture
}

quad :: proc(r: ^r2d.Render2D, texture: ^foster.Texture, rect: foster.Rect) {
	r2d.quad_texture(r, texture, {rect.X, rect.Y}, {(rect.X+rect.Width), rect.Y},
		{(rect.X+rect.Width), (rect.Y+rect.Height)}, {rect.X, (rect.Y+rect.Height)}, {0, 0}, {1, 0}, {1, 1}, {0, 1}, foster.White)
}

