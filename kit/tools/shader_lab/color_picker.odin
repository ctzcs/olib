package shader_lab

// 调色板会话持有稳定组名/字段 ID；打开时记下原色，实时预览，取消完整恢复。
// 切换目标、字段重载或离焦时取消。只编辑临时预览值，不创建材质存档。
// 分区：颜色转换 / 会话与纹理 / 色块与调色板。
import "core:fmt"
import "core:math"
import "core:strings"

import foster "olib:foster"
import mat "olib:kit/material"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

Color_Picker :: struct {
	open: bool,
	group, field, label: string,
	original: [4]f32,
	hsv: [3]f32,
	alpha, minimum, maximum: f32,
	sv, hue, transparency: foster.Texture,
	texture_hue: f32,
	texture_rgb: [3]f32,
	textures_ready: bool,
}

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

color_picker_value :: proc(p: ^Color_Picker) -> [4]f32 {
	rgb := color_hsv_to_rgb(p.hsv)
	return {rgb[0], rgb[1], rgb[2], p.alpha}
}

// ==============================================================================
// 会话与纹理：不跨帧借用参数切片内的指针
// ==============================================================================

color_picker_target :: proc(s: ^Session) -> ^mat.Value {
	p := &s.color_picker
	for &group in s.parameters[:s.shader_count] {
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
	foster.TextureDispose(&s.color_picker.sv)
	foster.TextureDispose(&s.color_picker.hue)
	foster.TextureDispose(&s.color_picker.transparency)
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
	rgba := color_normalize(p.original, p.minimum, p.maximum)
	p.hsv = color_rgb_to_hsv({rgba[0], rgba[1], rgba[2]})
	p.alpha = rgba[3]
	p.open = true
	s.orbiting = false
	ui.ui_set_modal(&s.ctx, "color-picker")
}

color_checker :: proc(color: [4]f32, x, y: int) -> foster.Color {
	bg: f32 = (x/8+y/8)%2 == 0 ? 0.7 : 0.4
	return color_rgba({color[0]*color[3]+bg*(1-color[3]), color[1]*color[3]+bg*(1-color[3]),
		color[2]*color[3]+bg*(1-color[3]), 1})
}

color_picker_textures :: proc(p: ^Color_Picker, device: ^foster.GraphicsDevice) {
	WIDTH :: 264
	if !p.textures_ready {
		foster.TextureInit(&p.sv, device, WIDTH, 180, name = "saturation value")
		foster.TextureInit(&p.hue, device, WIDTH, 20, name = "hue spectrum")
		foster.TextureInit(&p.transparency, device, WIDTH, 20, name = "alpha checker")
		pixels: [WIDTH*20]foster.Color
		for &pixel, i in pixels {
			rgb := color_hsv_to_rgb({f32(i%WIDTH)/f32(WIDTH-1), 1, 1})
			pixel = color_rgba({rgb[0], rgb[1], rgb[2], 1})
		}
		foster.TextureSetData(&p.hue, &pixels, size_of(pixels))
	}
	if !p.textures_ready || p.texture_hue != p.hsv[0] {
		pixels := make([]foster.Color, WIDTH*180, context.temp_allocator)
		for &pixel, i in pixels {
			rgb := color_hsv_to_rgb({p.hsv[0], f32(i%WIDTH)/f32(WIDTH-1), 1-f32(i/WIDTH)/179})
			pixel = color_rgba({rgb[0], rgb[1], rgb[2], 1})
		}
		foster.TextureSetData(&p.sv, raw_data(pixels), len(pixels)*size_of(foster.Color))
		p.texture_hue = p.hsv[0]
	}
	rgb := color_hsv_to_rgb(p.hsv)
	if !p.textures_ready || rgb != p.texture_rgb {
		pixels: [WIDTH*20]foster.Color
		for &pixel, i in pixels {
			pixel = color_checker({rgb[0], rgb[1], rgb[2], f32(i%WIDTH)/f32(WIDTH-1)}, i%WIDTH, i/WIDTH)
		}
		foster.TextureSetData(&p.transparency, &pixels, size_of(pixels))
		p.texture_rgb = rgb
	}
	p.textures_ready = true
}

// ==============================================================================
// 色块与调色板：复用 UI 捕获，拖出色域后仍能收尾；背景不响应输入
// ==============================================================================

color_swatch :: proc(s: ^Session, id: string, value: [4]f32, width: f32) -> bool {
	interaction := ui.ui_interact(&s.ctx, id)
	decl := ui.ui_column_decl(0)
	decl.id = clay.ID(id)
	decl.layout.sizing = {width = clay.SizingFixed(width), height = clay.SizingFixed(24)}
	decl.border = {color = ui.ui_clay_color(interaction.focused ? s.theme.accent : s.theme.text_dim),
		width = {left = 1, right = 1, top = 1, bottom = 1}}
	if clay.UI()(decl) {
		for y in 0..<2 {
			if clay.UI()(ui.ui_row_decl(0)) {
				for x in 0..<16 {
					if clay.UI()(clay.ElementDeclaration{
						layout = {sizing = {width = clay.SizingFixed(width/16), height = clay.SizingFixed(12)}},
						backgroundColor = ui.ui_clay_color(color_checker(value, x*8, y*8)),
					}) {}
				}
			}
		}
	}
	return interaction.clicked
}

// position 为 0..1，纵向坐标向下。方向键可调色相/透明度；SV 支持左右与上下。
color_picker_area :: proc(s: ^Session, id: string, texture: ^foster.Texture,
	height: f32, position: ^[2]f32, vertical_adjust: f32 = 0) -> bool {
	before := position^
	state := ui.ui_interact(&s.ctx, id)
	box := clay.GetElementData(clay.ID(id))
	if !state.disabled && box.found {
		if state.active || state.released {
			position[0] = math.clamp((s.ctx.pointer_x-box.boundingBox.x)/max(box.boundingBox.width, 1), 0, 1)
			position[1] = math.clamp((s.ctx.pointer_y-box.boundingBox.y)/max(box.boundingBox.height, 1), 0, 1)
		}
		if state.focused {
			position[0] = math.clamp(position[0]+s.ctx.navigation.adjust*0.01, 0, 1)
			position[1] = math.clamp(position[1]+vertical_adjust*0.01, 0, 1)
		}
	}
	decl := ui.ui_image_decl(&s.ctx, foster.SubtextureFromTexture(texture))
	decl.id = clay.ID(id)
	decl.layout.sizing = {width = clay.SizingFixed(264), height = clay.SizingFixed(height)}
	if clay.UI()(decl) {
		marker := height > 30 ? f32(10) : f32(4)
		marker_height := height > 30 ? f32(10) : height
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(marker), height = clay.SizingFixed(marker_height)}},
			backgroundColor = {0, 0, 0, 0.5},
			border = {color = {1, 1, 1, 1}, width = {left = 2, right = 2, top = 2, bottom = 2}},
			cornerRadius = clay.CornerRadiusAll(height > 30 ? 5 : 0),
			floating = {attachTo = .Parent, zIndex = 102, pointerCaptureMode = .Passthrough,
				offset = {math.clamp(position[0]*264-marker/2, 0, 264-marker),
					height > 30 ? math.clamp(position[1]*height-5, 0, height-10) : 0}},
		}) {}
	}
	return before != position^
}

color_picker_panel :: proc(s: ^Session) {
	p := &s.color_picker
	if !p.open do return
	value := color_picker_target(s)
	if value == nil || s.parameters[s.selected].name != p.group {
		color_picker_close(s, false)
		return
	}
	color_picker_textures(p, s.device)
	ui.ui_set_scope(&s.ctx, "color-picker")
	defer ui.ui_set_scope(&s.ctx, "")
	modal := ui.ui_modal_decl(&s.ctx, "color-picker")
	modal.backgroundColor = {0, 0, 0, 0.12}
	modal.layout.childAlignment = {x = .Left, y = .Top}
	modal.layout.padding = {left = u16(max(12, min(280, s.ctx.width-308))),
		top = u16(max(12, min(140, s.ctx.height-560)))}
	close, accept: bool
	if clay.UI()(modal) {
		if clay.UI()(ui.ui_panel_decl(&s.theme, 8, 296)) {
			ui.ui_heading(&s.ctx, &s.heading_theme, p.label)
			hue := [2]f32{p.hsv[0], 0}
			ui.ui_label_dim(&s.ctx, &s.small_theme, "Hue")
			_ = color_picker_area(s, "color-hue", &p.hue, 20, &hue)
			p.hsv[0] = hue[0]
			// Hue 和色域使用同一帧颜色，避免拖动色相时滞后一帧。
			color_picker_textures(p, s.device)
			sv := [2]f32{p.hsv[1], 1-p.hsv[2]}
			dy := s.input.focused ? s.input.vertical_adjust : 0
			_ = color_picker_area(s, "color-sv", &p.sv, 180, &sv, dy)
			p.hsv[1] = sv[0]
			p.hsv[2] = 1-sv[1]
			color_picker_textures(p, s.device)
			ui.ui_label_dim(&s.ctx, &s.small_theme, "Opacity")
			alpha := [2]f32{p.alpha, 0}
			_ = color_picker_area(s, "color-alpha", &p.transparency, 20, &alpha)
			p.alpha = alpha[0]
			if clay.UI()(ui.ui_row_decl(4)) {
				for preset, i in ([8][3]f32{{1, 1, 1}, {0, 0, 0}, {1, 0.2, 0.2}, {1, 0.65, 0.1},
					{0.3, 0.9, 0.4}, {0.1, 0.75, 1}, {0.4, 0.3, 1}, {1, 0.3, 0.7}}) {
					if color_swatch(s, fmt.tprintf("color-preset:%d", i), {preset[0], preset[1], preset[2], 1}, 29.5) {
						p.hsv = color_rgb_to_hsv(preset)
					}
				}
			}
			rgba := color_picker_value(p)
			color := color_rgba(rgba)
			ui.ui_label(&s.ctx, &s.theme, fmt.tprintf("#%02X%02X%02X%02X", color.R, color.G, color.B, color.A))
			ui.ui_label_dim(&s.ctx, &s.small_theme, "Original                 Current")
			if clay.UI()(ui.ui_row_decl(8)) {
				if color_swatch(s, "color-original", color_normalize(p.original, p.minimum, p.maximum), 128) {
					rgba = color_normalize(p.original, p.minimum, p.maximum)
					p.hsv = color_rgb_to_hsv({rgba[0], rgba[1], rgba[2]})
					p.alpha = rgba[3]
				}
				_ = color_swatch(s, "color-current", rgba, 128)
			}
			if clay.UI()(ui.ui_row_decl(8)) {
				accept = ui.ui_button_ex(&s.ctx, &s.theme, "color-apply", "Apply", .Primary)
				close = ui.ui_button(&s.ctx, &s.theme, "color-cancel", "Cancel") || accept
			}
		}
	}
	rgba := color_picker_value(p)
	for v, i in rgba do value.number[i] = p.minimum+v*(p.maximum-p.minimum)
	if close do color_picker_close(s, accept)
}
