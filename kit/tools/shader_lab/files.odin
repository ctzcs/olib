package shader_lab

// 文件对话框由宿主执行；请求绑定组名、字段 ID 和布局版本，异步返回不误写其他目标。
// 分区：请求协议 / 纹理路径与热更新。
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import mat "olib:kit/rendering/material"

File_Action :: enum { None, Texture, Save_Preset, Load_Preset }
File_Request :: struct {
	id, generation: u64,
	action: File_Action,
	group, field: string,
	effect: string, // 模型材质请求绑定整个效果，切换选中项不会重定向保存/载入。
}

// 返回借用描述；宿主只需保留 id/action，路径在主线程通过 file_reply 交回。
file_request :: proc(s: ^Session) -> File_Request {
	return s.request
}

file_request_clear :: proc(s: ^Session) {
	delete(s.request.group)
	delete(s.request.field)
	delete(s.request.effect)
	s.request = {}
}

request_file :: proc(s: ^Session, index: int, action: File_Action, field := "") {
	if !s.file_dialogs || s.request.id != 0 || index < 0 || index >= s.shader_count do return
	p := &s.parameters[index]
	if !p.available do return
	color_picker_close(s, true)
	s.request_serial += 1
	s.request = {id = s.request_serial, generation = p.generation, action = action,
		group = strings.clone(p.name), field = strings.clone(field)}
	if action != .Texture && s.selected_effect >= 0 && mat.effect_is_material(s.effects[s.selected_effect].desc) {
		s.request.effect = strings.clone(s.effects[s.selected_effect].desc.name)
	}
}

// 空路径代表取消；旧请求或已改变的布局被丢弃。只能在工具没有排队绘制时调用。
file_reply :: proc(s: ^Session, id: u64, path: string) -> bool {
	if id == 0 || s.request.id != id do return false
	request := s.request
	defer file_request_clear(s)
	if path == "" do return true
	for &p, index in s.parameters[:s.shader_count] {
		if !p.available || p.name != request.group || p.generation != request.generation do continue
		if request.effect != "" {
			for e, i in s.effects {
				if e.desc.name != request.effect do continue
				if request.action == .Save_Preset do return save_material(s, i, path)
				if request.action == .Load_Preset do return load_material(s, i, path)
			}
			return false
		}
		switch request.action {
		case .Save_Preset: return save_preset(s, index, path)
		case .Load_Preset: return load_preset(s, index, path)
		case .Texture:
			for f, i in p.live.fields {
				if f.id == request.field && f.kind == .Texture {
					parameter_texture_set(s, index, i, path)
					return p.error == ""
				}
			}
		case .None:
		}
	}
	return false
}

Texture_Stamp :: struct {
	modified: time.Time,
	size: i64,
	exists: bool,
}

texture_path :: proc(s: ^Session, path: string) -> string {
	return filepath.is_abs(path) ? path : fmt.tprintf("%s/%s", s.source_root, path)
}

texture_stamp :: proc(s: ^Session, path: string) -> Texture_Stamp {
	if path == "" do return {}
	info, err := os.stat(texture_path(s, path), context.temp_allocator)
	if err != nil do return {}
	return {info.modification_time, info.size, true}
}

texture_stamps_reset :: proc(s: ^Session, p: ^Parameter_State) {
	slot := 0
	for f, i in p.live.fields {
		if f.kind != .Texture do continue
		p.texture_stamps[slot] = texture_stamp(s, p.values[i].texture)
		p.texture_pending[slot] = p.texture_stamps[slot]
		slot += 1
	}
}

textures_update :: proc(s: ^Session) {
	s.texture_poll += s.delta_time
	if s.texture_poll < 0.25 do return
	s.texture_poll = 0
	for &p in s.parameters[:s.shader_count] {
		if !p.available do continue
		slot := 0
		for f, i in p.live.fields {
			if f.kind != .Texture do continue
			current := texture_stamp(s, p.values[i].texture)
			if current != p.texture_stamps[slot] {
				if current == p.texture_pending[slot] {
					// 两次轮询稳定后再加载；失败保留旧图，等下一次文件变化再尝试。
					p.texture_stamps[slot] = current
					texture, ok := load_parameter_texture(s, s.device, p.values[i].texture)
					if ok {
						parameter_texture_replace(s, &p.textures[slot], texture)
						parameter_error(&p, "")
					} else {
						parameter_error(&p, "Texture reload failed; previous image retained")
					}
				} else {
					p.texture_pending[slot] = current
				}
			}
			slot += 1
		}
	}
}
