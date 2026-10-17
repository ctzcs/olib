package shader_lab

// 参数预览由 Session 持有；值不写入项目文件。声明/Shader 成功后一起切换。
// 分区：候选描述 / 纹理与绑定 / 自动面板。
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import foster "olib:foster"
import mat "olib:kit/material"
import dev "olib:kit/shaderdev"
import ui "olib:kit/ui"
import clay "olib:thirdparty/clay-odin"

Parameter_State :: struct {
	name: string,
	live, pending: mat.Schema,
	values: []mat.Value,
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
	mat.schema_dispose(&p.live)
	mat.schema_dispose(&p.pending)
	mat.values_dispose(p.values)
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
	if len(build.schemas) == 0 do return
	if len(build.schemas) > 16 || len(build.effects) > 16 {
		bank_error(s, "Shader Lab supports 16 parameter groups and 16 effects")
		return
	}
	if s.generated_directory != "" {
		if error := dev.parameters_write_headers(build.schemas, s.generated_directory); error != "" {
			bank_error(s, error)
			delete(error)
			return
		}
	}
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
	if !mat.pack(p.live, p.values, p.buffer) do return
	stage := &s.materials[index].Fragment
	foster.MaterialStageSetUniformBuffer(stage, p.buffer, 1)
	slot := 0
	for f in p.live.fields {
		if f.kind != .Texture do continue
		texture := p.textures[slot].Resource != nil ? &p.textures[slot] : &s.texture
		stage.Samplers[slot] = {texture, foster.TextureSamplerMake(.Linear, .Clamp)}
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
	if p.error != "" do ui.ui_label(&s.ctx, &s.theme, wrap_diagnostic(p.error))
	for f, i in p.live.fields {
		override, overridden := effect_value(s, index, f.id)
		bound_texture, binding_label := effect_input(s, index, f.id)
		if clay.UI()(ui.ui_row_decl(4)) {
			ui.ui_label(&s.ctx, &s.theme, f.label)
			ui.ui_spacer()
			if overridden do ui.ui_label_dim(&s.ctx, &s.small_theme, fmt.tprintf("%v", override[:mat.components(f.kind)]))
			if f.kind == .Scalar && !overridden do ui.ui_label_ex(&s.ctx, &s.theme,
				fmt.tprintf("%.2f", overridden ? override[0] : p.values[i].number[0]), s.theme.accent, 14)
			if !overridden && binding_label == "" {
				if lab_button(s, fmt.tprintf("reset:%s:%s", p.name, f.id), "R") do _ = reset_defaults(s, index, i)
			}
		}
		if overridden do continue
		value := &p.values[i]
		if f.kind == .Texture {
			if binding_label != "" {
				if clay.UI()(ui.ui_row_decl(8)) {
					if bound_texture != nil {
						scale := f32(40)/f32(max(1, max(bound_texture.Width, bound_texture.Height)))
						ui.ui_image(&s.ctx, foster.SubtextureFromTexture(bound_texture), f32(bound_texture.Width)*scale, f32(bound_texture.Height)*scale)
					}
					ui.ui_label_dim(&s.ctx, &s.small_theme, binding_label)
				}
				continue
			}
			button := fmt.tprintf("texture:%s:%s", p.name, f.id)
			if parameter_texture_card(s, p, i, button) {
				delete(p.texture_picker)
				p.texture_picker = strings.clone(f.id)
			}
			if p.texture_picker == f.id {
				if s.file_dialogs && lab_button(s, "texture-browse", "Browse file...") do request_file(s, index, .Texture, f.id)
				if lab_button(s, "texture-default", "Clear / checker") {
					parameter_texture_set(s, index, i, "")
				}
				entries, _ := os.read_all_directory_by_path(fmt.tprintf("%s/textures", s.source_root), context.temp_allocator)
				for entry in entries {
					ext := strings.to_lower(filepath.ext(entry.name), context.temp_allocator)
					if entry.type != .Regular || (ext != ".png" && ext != ".jpg" && ext != ".jpeg" && ext != ".qoi") do continue
					if lab_button(s, entry.fullpath, entry.name) {
						parameter_texture_set(s, index, i, fmt.tprintf("textures/%s", entry.name))
					}
				}
				ui.ui_label_dim(&s.ctx, &s.small_theme, "Add images to shaders/textures")
				if lab_button(s, "texture-cancel", "Close") {
					delete(p.texture_picker)
					p.texture_picker = ""
				}
			}
			continue
		}
		if f.kind == .Color {
			if color_swatch(s, fmt.tprintf("%s:%s:color", p.name, f.id),
				color_normalize(value.number, f.minimum, f.maximum), panel_width(s)) {
				color_picker_open(s, p, i)
			}
			continue
		}
		count := mat.components(f.kind)
		for c in 0..<count {
			id := count == 1 ? fmt.tprintf("%s:%s", p.name, f.id) : fmt.tprintf("%s:%s:%d", p.name, f.id, c)
			components := [4]string{"X", "Y", "Z", "W"}
			label := count == 1 ? f.label : components[c]
			if count > 1 {
				if clay.UI()(ui.ui_row_decl(4)) {
					ui.ui_label(&s.ctx, &s.theme, label)
					ui.ui_spacer()
					ui.ui_label_ex(&s.ctx, &s.theme, fmt.tprintf("%.2f", value.number[c]), s.theme.accent, 14)
				}
			}
			lab_slider(s, id, &value.number[c], f.minimum, f.maximum, f.step)
		}
	}
}

// 卡片显示当前绑定的实际纹理；路径仍是 Odin 配置中的持久化表示。
parameter_texture_card :: proc(s: ^Session, p: ^Parameter_State, field: int, id: string) -> bool {
	state := ui.ui_interact(&s.ctx, id)
	if state.hovered && !state.disabled && s.input.focused && len(s.input.dropped_files) > 0 {
		parameter_texture_set(s, s.selected, field, s.input.dropped_files[0])
	}
	label := p.values[field].texture == "" ? "Built-in checker" : filepath.base(p.values[field].texture)
	// 后面的清空/选择按钮可在同帧替换路径，布局文本使用帧内副本。
	label = strings.clone(label, context.temp_allocator)
	slot := 0
	for f in p.live.fields[:field] do slot += int(f.kind == .Texture)
	texture := p.textures[slot].Resource != nil ? &p.textures[slot] : &s.texture
	decl := ui.ui_row_decl(10)
	decl.id = clay.ID(id)
	decl.layout.sizing.width = clay.SizingFixed(panel_width(s))
	decl.layout.padding = clay.PaddingAll(6)
	decl.backgroundColor = ui.ui_clay_color(state.hovered ? s.theme.button_hover : s.theme.button)
	decl.border = {color = ui.ui_clay_color(state.focused ? s.theme.accent : s.theme.panel_border),
		width = {left = 1, right = 1, top = 1, bottom = 1}}
	if clay.UI()(decl) {
		preview := ui.ui_row_decl(0)
		preview.layout.sizing = {width = clay.SizingFixed(48), height = clay.SizingFixed(48)}
		preview.layout.childAlignment = {x = .Center, y = .Center}
		preview.backgroundColor = ui.ui_clay_color(s.theme.window_bg)
		if clay.UI()(preview) {
			scale := f32(48)/f32(max(1, max(texture.Width, texture.Height)))
			ui.ui_image(&s.ctx, foster.SubtextureFromTexture(texture), f32(texture.Width)*scale, f32(texture.Height)*scale)
		}
		if clay.UI()(ui.ui_column_decl(4)) {
			ui.ui_label(&s.ctx, &s.theme, label)
			ui.ui_label_dim(&s.ctx, &s.small_theme, "Click / drop image")
		}
	}
	return state.clicked
}

parameter_texture_set :: proc(s: ^Session, index, field: int, path: string) {
	if index < 0 || index >= s.shader_count do return
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

// 图片卡片已经排入 Clay 后，Clear/替换不能销毁它仍借用的纹理。
// 将旧资源移到稳定地址，修正本帧图片引用，等最终 UI 提交后再释放。
parameter_texture_replace :: proc(s: ^Session, destination: ^foster.Texture, texture: foster.Texture) {
	if s.panel_active && destination.Resource != nil {
		retired := new(foster.Texture)
		retired^ = destination^
		append(&s.retired_textures, retired)
		for &image in s.ctx.image_pool[:s.ctx.image_len] {
			if image.sub.Texture == destination do image.sub.Texture = retired
		}
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

// 离线字符集固定；热改标签后报告缺字，要求更新共享图集并重新构建。
validate_parameter_fonts :: proc(s: ^Session) {
	s.fonts_dirty = false
	for p in s.parameters[:s.shader_count] {
		validate_label_font(s, display_name(p.live.label, p.name))
		validate_label_font(s, p.live.folder)
		for f in p.live.fields {
			validate_label_font(s, f.label)
		}
	}
	for e in s.effects {
		validate_label_font(s, display_name(e.desc.label, e.desc.name))
		for p in e.desc.passes do validate_label_font(s, display_name(p.label, string(p.id)))
	}
}

validate_label_font :: proc(s: ^Session, label: string) {
	for cp in label {
		_, found := foster.MsdfFontFindCharacter(s.font, int(cp))
		if !found do fmt.eprintfln("MSDF missing U+%04X in %s; regenerate the host MSDF atlas and rebuild", cp, label)
	}
}
