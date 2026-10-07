// atlas:aseprite —— .aseprite 目录 -> 单张图集的构建器（对位 DragonLib AsepriteAtlasBuilder）。
//
// 解析 .aseprite 二进制（Foster 的 Aseprite），拍平可见图层渲染每一帧
// （bg/shadow 这类预览图层默认跳过），frame tag 变成命名动画、帧时长毫秒
// 转秒；装箱用 Foster 的 Packer（二叉树 + 透明裁剪 + 边缘出血 + 重复帧
// 合并）。PingPong 标签展开帧列表（a b c -> a b c b），Reverse 反转帧序。
//
// 注意：构建器固定 Trim=true（PackerAdd 立即拷贝像素，渲染帧当轮释放）；
// 本文件只在 native 目标可用（目录枚举依赖 core:os）。
package rendering

import "core:fmt"
import "core:os"
import "core:strings"

import foster "olib:foster"

// ------------------------------------------------------------------------------
// 类型 —— 打包产物
// ------------------------------------------------------------------------------

// 打包区域：Source = 图集内的（已裁剪）像素矩形；Frame = 裁剪内容在未裁剪
// 帧内的位置与原始帧尺寸（Subtexture 的 frame 用）。
Atlas_Region_Placement :: struct {
	Source: foster.RectInt,
	Frame:  foster.RectInt,
}

// 一条自动生成的动画：Controller 来自 .aseprite 文件名，Name 来自 frame tag。
Built_Clip :: struct {
	Controller: string,
	Name:       string,
	Frames:     []string, // 区域名列表（克隆，随 clip 释放）
	Durations:  []f32,    // 与 Frames 一一对应（秒）
	Loop:       bool,
}

// 打包产物：合成后的图集像素 + 区域表 + 自动生成的动画剪辑。
// 所有字符串均为克隆（context.allocator），built_atlas_dispose 统一释放。
Built_Atlas :: struct {
	Image:       foster.Image,
	Regions:     map[string]Atlas_Region_Placement,
	Clips:       [dynamic]Built_Clip,
	SourceCount: int, // 参与打包的 .aseprite 文件数
}

// ------------------------------------------------------------------------------
// 构建配置
// ------------------------------------------------------------------------------

Aseprite_Build_Config :: struct {
	Padding:    int,       // 区域间距（>=2 时启用边缘出血）
	MaxSize:    int,       // 图集最大边长
	SkipLayers: []string,  // 拍平时跳过的图层名（大小写不敏感）
}

ASEPRITE_BUILD_DEFAULT :: Aseprite_Build_Config{
	Padding    = 2,
	MaxSize    = 8192,
	SkipLayers = {"bg", "shadow"},
}

// ------------------------------------------------------------------------------
// 构建
// ------------------------------------------------------------------------------

// 扫描目录（递归）里的所有 .aseprite，渲染帧并装箱成一张图集。
// 失败（无源文件 / 单页装不下）返回 false。
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
		Padding           = config.Padding,
		MaxSize           = config.MaxSize,
		DuplicateEdges    = config.Padding >= 2,
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
		data, err := os.read_entire_file_from_path(path, context.allocator)
		if err != nil do continue
		doc := foster.AsepriteLoad(data)
		defer foster.AsepriteDispose(&doc)
		if len(doc.Frames) == 0 do continue
		source_count += 1

		controller := aseprite_slug(aseprite_base_name(path))

		// 拍平渲染：跳过预览图层（filter 走包级状态，见 build_skip_layers）
		build_skip_layers = config.SkipLayers
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
			foster.PackerAdd(&packer, region_names[i], rendered[i]) // Trim=true：立即拷贝
		}
		for i in 0..<len(doc.Frames) {
			// 帧时长毫秒 -> 秒；至少 1ms 防 0 时长卡死采样
			durations[i] = max(doc.Frames[i].Duration, 1) / 1000.0
		}

		if len(doc.Tags) == 0 {
			append(&clips, aseprite_make_clip(controller, "default", region_names, durations, true))
			continue
		}
		for &tag in doc.Tags {
			name := aseprite_slug(tag.Name != "" ? tag.Name : "clip")
			frames, durs := aseprite_expand_tag(region_names, durations, tag.From, tag.To, tag.Direction)
			clip := aseprite_make_clip(controller, name, frames, durs, true)
			delete(frames)
			delete(durs)
			append(&clips, clip)
		}
	}
	build_skip_layers = nil

	output := foster.PackerPack(&packer)
	if len(output.Pages) != 1 {
		// 项目图集是单纹理的；多页说明 MaxSize 不够
		for &page in output.Pages do foster.ImageDispose(&page)
		delete(output.Pages)
		delete(output.Entries)
		return {}, false
	}

	clips_moved = true // clips 从这里起归产物所有
	result := Built_Atlas{
		Image       = output.Pages[0], // 转移第 0 页所有权
		Regions     = make(map[string]Atlas_Region_Placement, len(output.Entries)),
		Clips       = clips,
		SourceCount = source_count,
	}
	for &entry in output.Entries {
		key, _ := strings.clone(entry.Name, context.allocator)
		result.Regions[key] = Atlas_Region_Placement{Source = entry.Source, Frame = entry.Frame}
	}
	delete(output.Pages)
	delete(output.Entries)
	return result, true
}

// 释放打包产物（字符串/切片/图集像素）。
built_atlas_dispose :: proc(built: ^Built_Atlas) {
	for &clip in built.Clips do built_clip_dispose(&clip)
	delete(built.Clips)
	for key in built.Regions {
		delete(key, context.allocator)
	}
	delete(built.Regions)
	foster.ImageDispose(&built.Image)
	built^ = {}
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

// AsepriteLayerFilter 无 userdata 参数，跳过图层表走包级状态。
// 仅在 aseprite_build 的同步执行期间有效；该构建器不可重入。
@(private)
build_skip_layers: []string

@(private)
aseprite_layer_filter :: proc(layer: foster.AsepriteLayer) -> bool {
	if layer.Name == "" do return true
	lower, _ := strings.to_lower(layer.Name, context.temp_allocator)
	for s in build_skip_layers {
		if lower == s do return false
	}
	return true
}

@(private)
built_clip_dispose :: proc(clip: ^Built_Clip) {
	delete(clip.Controller)
	delete(clip.Name)
	delete(clip.Frames)
	delete(clip.Durations)
}

@(private)
aseprite_make_clip :: proc(controller, name: string, frames: []string, durations: []f32, loop: bool) -> Built_Clip {
	owned_frames := make([]string, len(frames), context.allocator)
	owned_durs := make([]f32, len(durations), context.allocator)
	for i in 0..<len(frames) {
		owned_frames[i], _ = strings.clone(frames[i], context.allocator)
		owned_durs[i] = durations[i]
	}
	return Built_Clip{
		Controller = controller,
		Name       = name,
		Frames     = owned_frames,
		Durations  = owned_durs,
		Loop       = loop,
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
