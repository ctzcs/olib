// atlas —— 核心图集：若干页纹理 + 「名字 -> 页号与页内像素矩形」映射。
//
// 与来源格式无关：矩形表由各来源（网格/Kenney XML/Aseprite 打包/自定义 proc）产出，
// 经 atlas_from_rects（单页）或 atlas_from_pages（多页）注入。一页放不下时打包器开新页；
// 同一页的精灵可以合批，换页像换图集一样断批。纹理上传与裁剪按需进行——atlas_upload
// 传 device 后 subtexture/crop 才可用（CPU 模式可先做矩形查询）。
package rendering2d

import "core:fmt"
import "core:mem"
import "core:strings"

import foster "olib:foster"

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 图集的一页：源像素与上传后的纹理。源像素在 atlas_crop 之外用不到，上传后可以释放。
Atlas_Page :: struct {
	image:   foster.Image,
	texture: foster.Texture,
}

// 名字对应的区域：所在页、页内像素矩形（裁边后的内容），以及裁边前的原始帧
// （Foster 的 Subtexture.Frame 约定：x、y 为内容相对原始帧的负偏移；零值表示没有裁边）。
Atlas_Region :: struct {
	page:  int,
	rect:  foster.RectInt,
	frame: foster.RectInt,
}

Sprite_Atlas :: struct {
	// 构造时一次分配，之后页数不变：atlas_subtexture 返回的 Subtexture 指向页纹理，地址须长期有效。
	pages: []Atlas_Page,

	// 名字 -> 区域。键为克隆字符串。
	regions: map[string]Atlas_Region,

	has_upload: bool,

	// 裁剪缓存：把某页的某个矩形裁成独立小纹理（九宫格角/边/中块用，
	// 绕开 UV 方向坑走整图绘制路径）。
	crop_cache:  map[string]foster.Texture,
	owned_crops: [dynamic]foster.Texture,
}

// ------------------------------------------------------------------------------
// 构造与释放
// ------------------------------------------------------------------------------

// 单页：从源图 + 矩形表构造（CPU 形态，不碰 GPU）。图集接管 image；rects 的键会被克隆。
// 需要绘制时再 atlas_upload(&atlas, device)。
atlas_from_rects :: proc(atlas: ^Sprite_Atlas, image: foster.Image, rects: map[string]foster.RectInt) {
	atlas^ = {
		pages   = make([]Atlas_Page, 1),
		regions = make(map[string]Atlas_Region, len(rects)),
	}
	atlas.pages[0].image = image
	for name, rect in rects {
		owned, _ := strings.clone(name, context.allocator)
		atlas.regions[owned] = {page = 0, rect = rect}
	}
}

// 多页：图集接管 images（每页一张）；regions 的键会被克隆，页号须在 images 范围内，越界的区域丢弃。
atlas_from_pages :: proc(atlas: ^Sprite_Atlas, images: []foster.Image, regions: map[string]Atlas_Region) {
	atlas^ = {
		pages   = make([]Atlas_Page, len(images)),
		regions = make(map[string]Atlas_Region, len(regions)),
	}
	for image, i in images do atlas.pages[i].image = image
	for name, region in regions {
		if region.page < 0 || region.page >= len(images) do continue
		owned, _ := strings.clone(name, context.allocator)
		atlas.regions[owned] = region
	}
}

// 上传全部页（幂等）；任何一页失败则释放已上传的页并返回 false。没有 device 的测试/工具流程可以永不上传。
atlas_upload :: proc(atlas: ^Sprite_Atlas, device: ^foster.GraphicsDevice) -> bool {
	if atlas.has_upload do return true
	if device == nil || len(atlas.pages) == 0 do return false
	for &page, i in atlas.pages {
		if page.image.Width > 0 do page.texture = foster.TextureFromImage(device, &page.image, "SpriteAtlas")
		if page.texture.Resource == nil {
			for &uploaded in atlas.pages[:i] do foster.TextureDispose(&uploaded.texture)
			return false
		}
	}
	atlas.has_upload = true
	return true
}

// 释放全部资源（页纹理/裁剪缓存/源图/区域表）。终止态调用。
atlas_dispose :: proc(atlas: ^Sprite_Atlas) {
	for &crop in atlas.owned_crops {
		if crop.Resource != nil do foster.TextureDispose(&crop)
	}
	delete(atlas.owned_crops)
	delete(atlas.crop_cache) // 纹理本体在 owned_crops 里已逐个释放
	for &page in atlas.pages {
		if page.texture.Resource != nil do foster.TextureDispose(&page.texture)
		delete(page.image.Pixels)
	}
	delete(atlas.pages)
	for name in atlas.regions {
		delete(name, context.allocator)
	}
	delete(atlas.regions)
	atlas^ = {}
}

// ------------------------------------------------------------------------------
// 查询
// ------------------------------------------------------------------------------

atlas_get :: proc(atlas: ^Sprite_Atlas, name: string) -> (Atlas_Region, bool) {
	region, ok := atlas.regions[name]
	return region, ok
}

atlas_has :: proc(atlas: ^Sprite_Atlas, name: string) -> bool {
	return name in atlas.regions
}

// 名字列表（temp 分配，仅枚举调试用）。
atlas_names :: proc(atlas: ^Sprite_Atlas, allocator := context.temp_allocator) -> []string {
	names := make([dynamic]string, 0, len(atlas.regions), allocator = allocator)
	for name in atlas.regions {
		append(&names, name)
	}
	return names[:]
}

// 按名字取可绘制子图，指向区域所在页的纹理；裁边的区域带上原始帧，绘制原点与未裁边时一致。
// 未上传纹理或名字缺失返回 SubtextureEmpty / false。
atlas_subtexture :: proc(atlas: ^Sprite_Atlas, name: string) -> (foster.Subtexture, bool) {
	region, ok := atlas.regions[name]
	if !ok || !atlas.has_upload do return foster.SubtextureEmpty, false
	texture := &atlas.pages[region.page].texture
	src := foster.Rect{f32(region.rect.X), f32(region.rect.Y), f32(region.rect.Width), f32(region.rect.Height)}
	if region.frame.Width <= 0 || region.frame.Height <= 0 {
		// 图集坐标只用于采样；未裁边子图的绘制原点始终是本地 (0, 0)。
		return foster.SubtextureFromSource(texture, src), true
	}
	frame := foster.Rect{f32(region.frame.X), f32(region.frame.Y), f32(region.frame.Width), f32(region.frame.Height)}
	return foster.SubtextureMake(texture, src, frame), true
}

// ------------------------------------------------------------------------------
// 裁剪 —— 独立小纹理（带缓存）
// ------------------------------------------------------------------------------

// 把图集某页的某矩形裁成独立纹理（九宫格角/边/中块用）。基于该页源像素，
// 首次裁剪后缓存；atlas_dispose 统一释放。
atlas_crop :: proc(atlas: ^Sprite_Atlas, device: ^foster.GraphicsDevice, page: int, src: foster.RectInt) -> (foster.Texture, bool) {
	if page < 0 || page >= len(atlas.pages) do return {}, false
	key := atlas_crop_key(page, src)
	if tex, ok := atlas.crop_cache[key]; ok {
		delete(key, context.allocator)
		return tex, true
	}

	image := &atlas.pages[page].image
	if device == nil || src.Width <= 0 || src.Height <= 0 ||
	   src.X < 0 || src.Y < 0 || src.X + src.Width > image.Width || src.Y + src.Height > image.Height {
		delete(key, context.allocator)
		return {}, false
	}

	cropped := foster.ImageMake(src.Width, src.Height, foster.Color{0, 0, 0, 0})
	for row in 0..<src.Height {
		dst_start := row * src.Width
		src_start := (src.Y + row) * image.Width + src.X
		mem.copy(
			raw_data(cropped.Pixels[dst_start:dst_start + src.Width]),
			raw_data(image.Pixels[src_start:src_start + src.Width]),
			src.Width * size_of(foster.Color),
		)
	}

	tex := foster.TextureFromImage(device, &cropped, key)
	delete(cropped.Pixels)
	if tex.Resource == nil {
		delete(key, context.allocator)
		return {}, false
	}

	atlas.crop_cache[key] = tex
	append(&atlas.owned_crops, tex)
	return tex, true
}

@(private)
atlas_crop_key :: proc(page: int, src: foster.RectInt) -> string {
	return fmt.aprintf("%d:%d,%d,%d,%d", page, src.X, src.Y, src.Width, src.Height, allocator = context.allocator)
}
