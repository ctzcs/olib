package shader_lab

// 每帧入口与预览窗口：Pass 直接渲染进自己的目标，预览窗口按最终输出像素 1:1 显示，
// UI 由宿主的 ImGui 在全部 Pass 之后绘制，不进入模糊/反馈链。
import "core:fmt"
import "core:math"
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import imgui "olib:thirdparty/odin-imgui"
import imgui_foster "olib:thirdparty/odin-imgui/imgui_impl_ofoster"

// 在宿主的 ImGui 帧里（BeginRender 与 EndRender 之间）每帧调用一次：切换候选包、按预览窗口尺寸
// 渲染当前 Shader，并提交控制窗口、预览窗口和调色板。dropped_files 是本帧拖入的文件，只借用到返回；
// drop_position 是拖放位置（ImGui 坐标，即窗口逻辑坐标），落在纹理卡片上才替换。
draw :: proc(s: ^Session, dropped_files: []string = nil, drop_position: [2]f32 = {}) {
	if !s.initialized do return
	// 上一帧的绘制列表已由宿主 EndRender 提交，这时才释放它借用的旧纹理和未选中 Shader 的目标；
	// 本帧新选中的 Shader 在下一帧开始时创建目标。
	texture_retire_flush(s)
	shader_targets_trim(s.bank, s.selected_shader)
	if s.pending_bank != nil do shader_targets_trim(s.pending_bank, bank_selected_shader(s, s.pending_bank))
	clear(&s.widgets)
	s.dropped_files = dropped_files
	s.drop_position = drop_position
	s.drawing = true
	defer {
		s.drawing = false
		s.dropped_files = nil
	}
	if s.pending_bank != nil && bank_apply(s, s.pending_bank, bank_selected_shader(s, s.pending_bank)) do bank_commit(s)
	// 新布局尚未整体通过时，只准备旧包当前 Shader，不分批应用新的 HLSL。
	_ = bank_apply(s, s.bank, s.selected_shader, s.pending_bank == nil)
	if s.fonts_dirty do validate_parameter_fonts(s)
	if imgui.IsKeyPressed(.Escape, false) {
		cancel(s)
		s.shader_menu = false
	}
	control_window(s)
	image: ^foster.Texture
	if s.selected_shader >= 0 && s.shaders[s.selected_shader].ready {
		image = shader_render(s, &s.shaders[s.selected_shader])
	} else {
		s.step_requested = false
	}
	preview_window(s, image)
	color_picker_popup(s)
	s.render_serial += 1
}

// 预览图占满窗口内容区（留一行状态）；区域原点和尺寸取整到最终输出像素，Pass 目标在下一帧按它分配。
preview_window :: proc(s: ^Session, image: ^foster.Texture) {
	imgui.SetNextWindowSize({760, 600}, .FirstUseEver)
	visible := imgui.Begin(PREVIEW_WINDOW, nil, {.NoScrollbar, .NoScrollWithMouse})
	defer imgui.End()
	if !visible do return
	if s.selected_shader >= 0 && len(s.shaders[s.selected_shader].desc.passes) > 1 {
		if lab_button(s, "shader-final", "最终效果", s.preview_pass < 0, icon = "media/display") do s.preview_pass = -1
		lab_same_line("当前 Pass")
		if lab_button(s, "pass-preview", "当前 Pass", s.preview_pass >= 0, icon = "ui/visible") do s.preview_pass = s.inspect_pass
		if s.preview_pass >= 0 {
			p := s.shaders[s.selected_shader].desc.passes[s.preview_pass]
			imgui.SameLine()
			lab_dim(display_name(p.label, string(p.id)))
		}
	} else {
		lab_text("最终效果")
	}
	io := imgui.GetIO()
	scale := io.DisplayFramebufferScale
	origin := imgui.GetCursorScreenPos()
	avail := imgui.GetContentRegionAvail()
	size := imgui.Vec2{max(1, avail.x), max(1, avail.y - imgui.GetTextLineHeightWithSpacing())}
	s.viewport = {math.floor(origin.x*scale.x), math.floor(origin.y*scale.y),
		max(1, math.floor(size.x*scale.x)), max(1, math.floor(size.y*scale.y))}
	if image != nil {
		imgui.Image(imgui_foster.Texture(image), size)
	} else {
		// 空工作区或 Shader 尚未就绪时只画背景，不分配替代场景目标。
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), origin, {origin.x + size.x, origin.y + size.y},
			imgui.GetColorU32ImVec4({17.0/255, 21.0/255, 26.0/255, 1}))
		imgui.Dummy(size)
	}
	imgui.SetCursorScreenPos(origin)
	imgui.InvisibleButton("##preview-area", size, {.MouseButtonLeft, .MouseButtonRight})
	track(s, "preview-area")
	s.pointer = {io.MousePos.x*scale.x, io.MousePos.y*scale.y}
	// 右键轨道旋转只在预览上开始，ImGui 的激活状态保持捕获到松开。
	if s.mode >= 2 {
		if imgui.IsItemActive() && imgui.IsMouseDown(.Right) && !s.color_picker.open do s.orbiting = true
		if !imgui.IsMouseDown(.Right) do s.orbiting = false
		if s.orbiting {
			s.yaw -= io.MouseDelta.x*scale.x*0.008
			s.pitch = math.clamp(s.pitch + io.MouseDelta.y*scale.y*0.008, -1.4, 1.4)
		}
		if imgui.IsItemHovered() && io.MouseWheel != 0 do s.distance = math.clamp(s.distance - io.MouseWheel*0.25, 2, 10)
	}
	time := s.selected_shader >= 0 ? s.shaders[s.selected_shader].time : s.clock
	lab_dim(fmt.tprintf("%.2fs   %s", time, preview_size_label(s)))
}

quad :: proc(r: ^r2d.Render2D, texture: ^foster.Texture, rect: foster.Rect) {
	r2d.quad_texture(r, texture, {rect.X, rect.Y}, {(rect.X+rect.Width), rect.Y},
		{(rect.X+rect.Width), (rect.Y+rect.Height)}, {rect.X, (rect.Y+rect.Height)}, {0, 0}, {1, 0}, {1, 1}, {0, 1}, foster.White)
}
