#+build !js
// atlas:aseprite —— .aseprite 目录 -> 图集的构建器（对位 DragonLib AsepriteAtlasBuilder）。
//
// 解析 .aseprite 二进制（Foster 的 Aseprite），拍平可见图层渲染每一帧
// （bg/shadow 这类预览图层默认跳过），frame tag 变成命名动画、帧时长毫秒
// 转秒；装箱用 Foster 的 Packer（二叉树 + 透明裁剪 + 边缘出血 + 重复帧
// 合并）。一页放不下 max_size 时自动开新页。PingPong 标签展开帧列表（a b c -> a b c b），Reverse 反转帧序。
//
// 注意：构建器固定 Trim=true（PackerAdd 立即拷贝像素，渲染帧当轮释放）；
// 本文件只在 native 目标可用（目录枚举依赖 core:os）。
package rendering2d

import "core:fmt"
import "core:os"
import "core:strings"

import foster "olib:foster"

// ------------------------------------------------------------------------------
// 类型 —— 打包产物
// ------------------------------------------------------------------------------

// 一条自动生成的动画：controller 来自 .aseprite 文件名，name 来自 frame tag。
Built_Clip :: struct {
	controller: string,
	name:       string,
	frames:     []string, // 区域名列表（克隆，随 clip 释放）
	durations:  []f32,    // 与 frames 一一对应（秒）
	loop:       bool,
}

// 打包产物：每页的图集像素 + 区域表（页号、页内矩形、裁边帧）+ 自动生成的动画剪辑。
// 所有字符串均为克隆（context.allocator），built_atlas_dispose 统一释放；atlas_from_built 接管页与区域。
Built_Atlas :: struct {
	pages:        []foster.Image,
	regions:      map[string]Atlas_Region,
	clips:        [dynamic]Built_Clip,
	source_count: int, // 参与打包的 .aseprite 文件数
}

// ------------------------------------------------------------------------------
// 构建配置
// ------------------------------------------------------------------------------

Aseprite_Build_Config :: struct {
	padding:     int,      // 区域间距（>=2 时启用边缘出血）
	max_size:    int,      // 每页最大边长；放不下时开新页
	skip_layers: []string, // 拍平时跳过的图层名（大小写不敏感）
}

ASEPRITE_BUILD_DEFAULT :: Aseprite_Build_Config{
	padding     = 2,
	max_size    = 8192,
	skip_layers = {"bg", "shadow"},
}

// ------------------------------------------------------------------------------
// 构建
// ------------------------------------------------------------------------------

// 扫描目录（递归）里的所有 .aseprite，渲染帧并装箱成图集（一页或多页）。
// 没有源文件时返回 false。
aseprite_build :: proc(root: string, config := ASEPRITE_BUILD_DEFAULT) -> (Built_Atlas, bool) {
	files: [dynamic]string
	defer {
		for f in files do delete(f)
		delete(files)
	}
	aseprite_collect(root, "", &files)
	if len(files) == 0 do return {}, false
	aseprite_sort_files(&files) // 稳定打包顺序

	packer := foster.Packer{
		Trim              = true,
		Padding           = config.padding,
		MaxSize           = config.max_size,
		DuplicateEdges    = config.padding >= 2,
		CombineDuplicates = true,
	}
	defer delete(packer.Sources)

	clips: [dynamic]Built_Clip
	clips_moved := false // 所有权转移进产物后，defer 不再释放
	defer if !clips_moved {
		for &clip in clips do built_clip_dispose(&clip)
		delete(clips)
	}

	source_count := 0
	for path in files {
		if aseprite_pack_file(&packer, &clips, path, config.skip_layers) do source_count += 1
	}

	output := foster.PackerPack(&packer)
	if len(output.Pages) == 0 {
		delete(output.Pages)
		delete(output.Entries)
		return {}, false
	}

	clips_moved = true // clips 从这里起归产物所有
	result := Built_Atlas{
		pages        = make([]foster.Image, len(output.Pages)), // 接管每页像素
		regions      = make(map[string]Atlas_Region, len(output.Entries)),
		clips        = clips,
		source_count = source_count,
	}
	copy(result.pages, output.Pages[:])
	for &entry in output.Entries {
		key, _ := strings.clone(entry.Name, context.allocator)
		result.regions[key] = Atlas_Region{page = entry.Page, rect = entry.Source, frame = entry.Frame}
	}
	delete(output.Pages)
	delete(output.Entries)
	return result, true
}

// 释放打包产物（字符串/切片/图集像素）。
built_atlas_dispose :: proc(built: ^Built_Atlas) {
	for &clip in built.clips do built_clip_dispose(&clip)
	delete(built.clips)
	for key in built.regions {
		delete(key, context.allocator)
	}
	delete(built.regions)
	for &page in built.pages do foster.ImageDispose(&page)
	delete(built.pages)
	built^ = {}
}

// 用打包产物构造图集：图集接管每页像素与区域表（built 里随之清空），动画剪辑仍归 built。
// 之后照常 atlas_upload；built 仍须 built_atlas_dispose 释放剪辑。
atlas_from_built :: proc(atlas: ^Sprite_Atlas, built: ^Built_Atlas) {
	atlas^ = {pages = make([]Atlas_Page, len(built.pages)), regions = built.regions}
	for image, i in built.pages do atlas.pages[i].image = image
	delete(built.pages)
	built.pages = nil
	built.regions = nil
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

// AsepriteLayerFilter 无 userdata 参数，跳过图层表经 context.user_ptr 传入
// （指向 []string，仅在 aseprite_pack_file 的渲染调用期间有效）。
@(private)
aseprite_layer_filter :: proc(layer: foster.AsepriteLayer) -> bool {
	if layer.Name == "" do return true
	skip_layers := (cast(^[]string)context.user_ptr)^
	lower, _ := strings.to_lower(layer.Name, context.temp_allocator)
	for s in skip_layers {
		if lower == s do return false
	}
	return true
}

// 渲染并装箱一个 .aseprite 文件，把它的动画追加到 clips。
// 文件读不出或没有帧时返回 false，不影响已有结果。
@(private)
aseprite_pack_file :: proc(packer: ^foster.Packer, clips: ^[dynamic]Built_Clip, path: string,
	skip_layers: []string) -> bool {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return false
	doc := foster.AsepriteLoad(data)
	defer foster.AsepriteDispose(&doc)
	if len(doc.Frames) == 0 do return false

	controller := aseprite_slug(aseprite_base_name(path))
	defer delete(controller)

	// 拍平渲染：跳过预览图层。
	skip := skip_layers
	context.user_ptr = &skip
	rendered := foster.AsepriteRenderAllFrames(&doc, aseprite_layer_filter)
	defer {
		for &frame in rendered do delete(frame.Pixels)
		delete(rendered)
	}

	region_names := make([]string, len(rendered), context.allocator)
	defer delete(region_names)
	durations := make([]f32, len(doc.Frames), context.allocator)
	defer delete(durations)

	for i in 0..<len(rendered) {
		region_names[i] = fmt.aprintf("%s/%d", controller, i, allocator = context.allocator)
		foster.PackerAdd(packer, region_names[i], rendered[i]) // Trim=true：立即拷贝
	}
	for i in 0..<len(doc.Frames) {
		// 帧时长毫秒 -> 秒；至少 1ms 防 0 时长卡死采样
		durations[i] = max(doc.Frames[i].Duration, 1) / 1000.0
	}

	if len(doc.Tags) == 0 {
		append(clips, aseprite_make_clip(controller, "default", region_names, durations, true))
		return true
	}
	for &tag in doc.Tags {
		name := aseprite_slug(tag.Name != "" ? tag.Name : "clip")
		defer delete(name)
		frames, durs := aseprite_expand_tag(region_names, durations, tag.From, tag.To, tag.Direction)
		clip := aseprite_make_clip(controller, name, frames, durs, true)
		delete(frames)
		delete(durs)
		append(clips, clip)
	}
	return true
}

@(private)
built_clip_dispose :: proc(clip: ^Built_Clip) {
	delete(clip.controller)
	delete(clip.name)
	for name in clip.frames do delete(name) // 区域名是 aseprite_make_clip 克隆的
	delete(clip.frames)
	delete(clip.durations)
}

// 复制全部入参：clip 独立拥有 controller / name / 区域名 / 时长，由 built_clip_dispose 释放。
@(private)
aseprite_make_clip :: proc(controller, name: string, frames: []string, durations: []f32, loop: bool) -> Built_Clip {
	owned_frames := make([]string, len(frames), context.allocator)
	owned_durs := make([]f32, len(durations), context.allocator)
	for i in 0..<len(frames) {
		owned_frames[i], _ = strings.clone(frames[i], context.allocator)
		owned_durs[i] = durations[i]
	}
	return Built_Clip{
		controller = clone_owned(controller),
		name       = clone_owned(name),
		frames     = owned_frames,
		durations  = owned_durs,
		loop       = loop,
	}
}

// 展开一个 frame tag 的帧区间（含 Reverse / PingPong / PingPongReverse）。
// 返回新分配的切片（context.allocator，调用方释放）。
aseprite_expand_tag :: proc(
	regions: []string,
	durations: []f32,
	from, to: int,
	direction: foster.AsepriteLoopDir,
) -> ([]string, []f32) {
	indices: [dynamic]int
	defer delete(indices)

	for i := from; i <= to; i += 1 {
		if i >= 0 && i < len(regions) do append(&indices, i)
	}
	#partial switch direction {
	case .Reverse:
		reverse_indices(indices[:])
	case .PingPong, .PingPongReverse:
		// a b c -> a b c b（PingPongReverse 先反转再补回程）
		if direction == .PingPongReverse {
			reverse_indices(indices[:])
		}
		for i := len(indices) - 2; i >= 1; i -= 1 {
			append(&indices, indices[i])
		}
	case:
	}

	frames := make([]string, len(indices), context.allocator)
	durs := make([]f32, len(indices), context.allocator)
	// 注意切片双变量迭代是 (值, 下标)
	for region_index, position in indices {
		frames[position] = regions[region_index]
		durs[position] = durations[region_index]
	}
	return frames, durs
}

@(private)
reverse_indices :: proc(indices: []int) {
	for i := 0; i < len(indices) / 2; i += 1 {
		indices[i], indices[len(indices) - 1 - i] = indices[len(indices) - 1 - i], indices[i]
	}
}

// 把子图名字清洗成稳定标识符（小写、非字母数字归为下划线）。
// 超长名字截断到 256 字符。
aseprite_slug :: proc(name: string) -> string {
	buf: [256]u8
	n := 0
	last_underscore := true // 前导不产生下划线
	for c in name {
		if n >= len(buf) do break
		alnum := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		if alnum {
			lower := c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c
			buf[n] = u8(lower)
			n += 1
			last_underscore = false
		} else if !last_underscore {
			buf[n] = '_'
			n += 1
			last_underscore = true
		}
	}
	for n > 0 && buf[n - 1] == '_' {
		n -= 1
	}
	return clone_owned(string(buf[:n]))
}

@(private)
aseprite_base_name :: proc(path: string) -> string {
	slash := strings.last_index(path, "/")
	back := strings.last_index(path, "\\")
	sep := max(slash, back)
	base := sep >= 0 ? path[sep + 1:] : path
	dot := strings.last_index(base, ".")
	return dot > 0 ? base[:dot] : base
}

@(private)
aseprite_collect :: proc(root, rel: string, out: ^[dynamic]string) {
	dir := rel == "" ? root : join_owned(root, rel)
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return
	defer os.file_info_slice_delete(infos, context.temp_allocator)

	for info in infos {
		if info.name == "." || info.name == ".." do continue
		child_rel := rel == "" ? join_owned("", info.name) : join_owned(rel, info.name)
		if info.type == .Directory {
			aseprite_collect(root, child_rel, out)
			delete(child_rel)
			continue
		}
		lower, _ := strings.to_lower(info.name, context.temp_allocator)
		if strings.has_suffix(lower, ".aseprite") {
			append(out, join_owned(root, child_rel)) // 完整路径，随 out 释放
		}
		delete(child_rel)
	}
}

// 插入排序：文件名有序保证打包结果稳定。
@(private)
aseprite_sort_files :: proc(files: ^[dynamic]string) {
	for i in 1..<len(files) {
		f := files[i]
		j := i
		for j > 0 && files[j - 1] > f {
			files[j] = files[j - 1]
			j -= 1
		}
		files[j] = f
	}
}
