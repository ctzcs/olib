package shader_lab

// 参数预览由 Session 持有；值不写入项目文件。声明/Shader 成功后一起切换。
// 分区：候选描述 / 纹理与绑定 / 自动面板。
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import foster "olib:foster"
import sh "olib:kit/rendering/shader"
import dev "olib:kit/rendering/shader/dev"
import imgui "olib:thirdparty/odin-imgui"
import imgui_foster "olib:thirdparty/odin-imgui/imgui_impl_ofoster"

Parameter_State :: struct {
	name: string,
	live, pending: sh.Schema,
	values: []sh.Value,
	textures: [16]foster.Texture,
	buffer: []u8,
	has_pending, available: bool,
	folder_closed: bool,
	error: string,
	texture_picker: string,
	generation: u64,
	texture_stamps, texture_pending: [16]Texture_Stamp,
}

parameter_dispose :: proc(p: ^Parameter_State) {
	sh.schema_dispose(&p.live)
	sh.schema_dispose(&p.pending)
	sh.values_dispose(p.values)
	for &texture in p.textures do foster.TextureDispose(&texture)
	delete(p.name)
	delete(p.error)
	delete(p.buffer)
	delete(p.texture_picker)
	p^ = {}
}

parameters_update :: proc(s: ^Session) {
	dev.parameters_update(&s.parameter_watch, f64(s.delta_time))
	if s.parameter_watch.status != .Ready do return
	build := dev.parameters_take(&s.parameter_watch)
	defer dev.parameter_build_dispose(&build)
	if s.parameter_watch.status != .Live do return
	bank_dispose(s.pending_bank)
	s.pending_bank = bank_make(s, build)
	bank_error(s, "")
}

parameter_error :: proc(p: ^Parameter_State, message: string) {
	delete(p.error)
	p.error = strings.clone(message)
	if message != "" do fmt.eprintln(message)
}

load_parameter_texture :: proc(s: ^Session, device: ^foster.GraphicsDevice, path: string) -> (foster.Texture, bool) {
	if path == "" do return {}, true // 空路径使用工具内置棋盘纹理。
	fullpath := filepath.is_abs(path) ? path : fmt.tprintf("%s/%s", s.source_root, path)
	image := foster.ImageLoadFile(fullpath)
	defer foster.ImageDispose(&image)
	if image.Width == 0 || image.Height == 0 do return {}, false
	foster.ImagePremultiply(&image)
	texture := foster.TextureFromImage(device, &image, "parameter texture")
	return texture, texture.Resource != nil
}

parameters_bind :: proc(s: ^Session, index: int) {
	p := &s.parameters[index]
	if !sh.pack(p.live, p.values, p.buffer) do return
	stage := &s.materials[index].Fragment
	foster.MaterialStageSetUniformBuffer(stage, p.buffer, 1)
	slot := 0
	for f in p.live.fields {
		if f.kind != .Texture do continue
		texture := p.textures[slot].Resource != nil ? &p.textures[slot] : &s.texture
		stage.Samplers[slot] = {texture, sh.field_sampler(f)}
		slot += 1
	}
}

parameter_number :: proc(s: ^Session, index: int, id: string) -> f32 {
	p := &s.parameters[index]
	for f, i in p.live.fields {
		if f.id == id do return p.values[i].number[0]
	}
	return 0
}

// ==============================================================================
// 自动面板：数值/向量滑条、RGBA、纹理目录选择；参数值仅用于本次预览
// ==============================================================================

parameters_panel :: proc(s: ^Session, index: int) {
	p := &s.parameters[index]
	if p.error != "" do lab_error(p.error)
	style := imgui.GetStyle()
	reset_width := imgui.CalcTextSize("R").x + style.FramePadding.x*2
	// 属性表：标签列约占 35%，控件填满中间，行尾是单项重置 R。
	label_width := imgui.GetContentRegionAvail().x*0.35
	for f, i in p.live.fields {
		override, overridden := shader_value(s, index, f.id)
		bound_texture, binding_label := shader_input(s, index, f.id)
		resettable := !overridden && binding_label == ""
		value := &p.values[i]
		count := sh.components(f.kind)
		field_label(f.label, label_width)
		if overridden {
			lab_dim(fmt.tprintf("Pass 覆盖 %v", override[:count]))
			continue
		}
		reset := fmt.tprintf("reset:%s:%s", p.name, f.id)
		widget_width := -(reset_width + style.ItemSpacing.x)
		switch {
		case f.kind == .Texture && binding_label != "":
			if bound_texture != nil {
				scale := imgui.GetFrameHeight()/f32(max(1, max(bound_texture.Width, bound_texture.Height)))
				imgui.Image(imgui_foster.Texture(bound_texture), {f32(bound_texture.Width)*scale, f32(bound_texture.Height)*scale})
				imgui.SameLine()
			}
			lab_dim(binding_label)
		case f.kind == .Texture:
			lab_dim(p.values[i].texture == "" ? "Built-in checker" : filepath.base(p.values[i].texture))
		case f.kind == .Color:
			id := fmt.tprintf("%s:%s:color", p.name, f.id)
			color := color_normalize(value.number, f.minimum, f.maximum)
			if imgui.ColorButton(fmt.ctprintf("##%s", id), color, {.AlphaPreviewHalf},
				{imgui.GetContentRegionAvail().x - reset_width - style.ItemSpacing.x, imgui.GetFrameHeight()}) {
				color_picker_open(s, p, i)
			}
			track(s, id)
		case count == 1:
			id := fmt.tprintf("%s:%s", p.name, f.id)
			imgui.SetNextItemWidth(widget_width)
			imgui.SliderFloat(fmt.ctprintf("##%s", id), &value.number[0], f.minimum, f.maximum, "%.2f", imgui.SliderFlags_AlwaysClamp)
			track(s, id)
		case:
			imgui.Dummy({max(1, imgui.GetContentRegionAvail().x - reset_width - style.ItemSpacing.x), imgui.GetFrameHeight()})
		}
		if resettable {
			align_right(reset_width)
			if imgui.Button(fmt.ctprintf("R##%s", reset)) do _ = reset_defaults(s, index, i)
			track(s, reset)
		}
		if f.kind == .Texture && binding_label == "" {
			button := fmt.tprintf("texture:%s:%s", p.name, f.id)
			if parameter_texture_card(s, index, i, button) {
				delete(p.texture_picker)
				p.texture_picker = strings.clone(f.id)
			}
			if p.texture_picker == f.id do texture_picker(s, index, i)
		}
		if count > 1 && f.kind != .Color && f.kind != .Texture {
			components := [4]string{"X", "Y", "Z", "W"}
			for c in 0..<count {
				id := fmt.tprintf("%s:%s:%d", p.name, f.id, c)
				field_label(components[c], label_width, indent = true)
				imgui.SetNextItemWidth(widget_width)
				imgui.SliderFloat(fmt.ctprintf("##%s", id), &value.number[c], f.minimum, f.maximum, "%.2f", imgui.SliderFlags_AlwaysClamp)
				track(s, id)
			}
		}
	}
}

// 标签与同行控件按框架内边距对齐；过长时截断显示，悬停看全名。
field_label :: proc(label: string, width: f32, indent := false) {
	imgui.AlignTextToFramePadding()
	start := imgui.GetCursorPosX()
	text := cstr(label)
	if indent do imgui.SetCursorPosX(start + imgui.GetStyle().IndentSpacing*0.5)
	clip := imgui.GetCursorScreenPos()
	imgui.PushClipRect(clip, {clip.x + width - imgui.GetStyle().ItemSpacing.x, clip.y + imgui.GetFrameHeight()}, true)
	imgui.TextUnformatted(text)
	imgui.PopClipRect()
	if imgui.IsItemHovered() && imgui.CalcTextSize(text).x > width do imgui.SetTooltip("%s", text)
	imgui.SameLine(start + width)
}

texture_picker :: proc(s: ^Session, index, field: int) {
	p := &s.parameters[index]
	if s.file_dialogs && lab_button(s, "texture-browse", "Browse file...", grow = true) {
		request_file(s, index, .Texture, p.live.fields[field].id)
	}
	if lab_button(s, "texture-default", "Clear / checker", grow = true) {
		parameter_texture_set(s, index, field, "")
	}
	entries, _ := os.read_all_directory_by_path(fmt.tprintf("%s/textures", s.source_root), context.temp_allocator)
	for entry in entries {
		ext := strings.to_lower(filepath.ext(entry.name), context.temp_allocator)
		if entry.type != .Regular || (ext != ".png" && ext != ".jpg" && ext != ".jpeg" && ext != ".qoi") do continue
		if lab_button(s, entry.fullpath, entry.name, grow = true, icon = "media/image") {
			parameter_texture_set(s, index, field, fmt.tprintf("textures/%s", entry.name))
		}
	}
	lab_dim("Add images to shaders/textures")
	if lab_button(s, "texture-cancel", "Close", grow = true) {
		delete(p.texture_picker)
		p.texture_picker = ""
	}
}

// 卡片显示当前绑定的实际纹理；路径仍是 Properties 声明中的持久化表示。拖入的文件落在卡片上才替换。
parameter_texture_card :: proc(s: ^Session, index, field: int, id: string) -> bool {
	p := &s.parameters[index]
	label := p.values[field].texture == "" ? "Built-in checker" : filepath.base(p.values[field].texture)
	// 后面的清空/选择按钮可在同帧替换路径，文本使用帧内副本。
	text := strings.clone_to_cstring(label, context.temp_allocator)
	slot := 0
	for f in p.live.fields[:field] do slot += int(f.kind == .Texture)
	texture := p.textures[slot].Resource != nil ? &p.textures[slot] : &s.texture
	thumb := f32(48)
	pad := imgui.GetStyle().FramePadding.y
	clicked := imgui.Button(fmt.ctprintf("##%s", id), {imgui.GetContentRegionAvail().x, thumb + pad*2})
	track(s, id)
	rect_min := imgui.GetItemRectMin()
	rect_max := imgui.GetItemRectMax()
	draw := imgui.GetWindowDrawList()
	box := imgui.Vec2{rect_min.x + pad, rect_min.y + pad}
	imgui.DrawList_AddRectFilled(draw, box, {box.x + thumb, box.y + thumb}, imgui.GetColorU32(.WindowBg))
	scale := thumb/f32(max(1, max(texture.Width, texture.Height)))
	w, h := f32(texture.Width)*scale, f32(texture.Height)*scale
	corner := imgui.Vec2{box.x + (thumb-w)/2, box.y + (thumb-h)/2}
	imgui.DrawList_AddImage(draw, imgui_foster.Texture(texture), corner, {corner.x + w, corner.y + h})
	x := box.x + thumb + imgui.GetStyle().ItemInnerSpacing.x*2
	imgui.DrawList_AddText(draw, {x, box.y + 4}, imgui.GetColorU32(.Text), text)
	imgui.DrawList_AddText(draw, {x, box.y + thumb/2 + 4}, imgui.GetColorU32(.TextDisabled), "Click / drop image")
	drop := s.drop_position
	if len(s.dropped_files) > 0 && drop.x >= rect_min.x && drop.x < rect_max.x && drop.y >= rect_min.y && drop.y < rect_max.y {
		parameter_texture_set(s, index, field, s.dropped_files[0])
	}
	return clicked
}

parameter_texture_set :: proc(s: ^Session, index, field: int, path: string) {
	if index < 0 || index >= s.program_count do return
	p := &s.parameters[index]
	if !p.available || field < 0 || field >= len(p.live.fields) || p.live.fields[field].kind != .Texture do return
	texture, ok := load_parameter_texture(s, s.device, path)
	if !ok {
		parameter_error(p, "Image load failed; previous texture retained")
		return
	}
	slot := 0
	for f in p.live.fields[:field] do slot += int(f.kind == .Texture)
	parameter_texture_replace(s, &p.textures[slot], texture)
	owned_path := strings.clone(path)
	delete(p.values[field].texture)
	p.values[field].texture = owned_path
	texture_stamps_reset(s, p)
	delete(p.texture_picker)
	p.texture_picker = ""
	parameter_error(p, "")
}

// draw 期间本帧的 ImGui 绘制列表可能已引用旧纹理（缩略图、预览）；宿主 EndRender 之后才提交，
// 所以旧资源先留着，下一次 draw 开始时再释放。
parameter_texture_replace :: proc(s: ^Session, destination: ^foster.Texture, texture: foster.Texture) {
	if s.drawing && destination.Resource != nil {
		retired := new(foster.Texture)
		retired^ = destination^
		append(&s.retired_textures, retired)
	} else {
		foster.TextureDispose(destination)
	}
	destination^ = texture
}

texture_retire_flush :: proc(s: ^Session) {
	for texture in s.retired_textures {
		foster.TextureDispose(texture)
		free(texture)
	}
	clear(&s.retired_textures)
}

// ImGui 按需光栅化字形，但 olib 字体只含 ASCII、Latin-1 与 GB2312；热改标签后报告缺字。
// 在 ImGui 帧内调用。
validate_parameter_fonts :: proc(s: ^Session) {
	s.fonts_dirty = false
	s.missing_glyphs = 0
	for p in s.parameters[:s.program_count] {
		validate_label_font(s, display_name(p.live.label, p.name))
		validate_label_font(s, p.live.folder)
		for f in p.live.fields {
			validate_label_font(s, f.label)
		}
	}
	for e in s.shaders {
		validate_label_font(s, display_name(e.desc.label, e.desc.name))
		for p in e.desc.passes do validate_label_font(s, display_name(p.label, string(p.id)))
	}
}

validate_label_font :: proc(s: ^Session, label: string) {
	font := imgui.GetFont()
	for cp in label {
		if cp <= 0xFFFF && imgui.Font_IsGlyphInFont(font, imgui.Wchar(cp)) do continue
		s.missing_glyphs += 1
		fmt.eprintfln("ImGui font missing U+%04X in %s; the olib UI font covers ASCII, Latin-1 and GB2312", cp, label)
	}
}
