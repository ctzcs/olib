// atlas —— 核心图集：一张纹理 + 「名字 -> 像素矩形」映射。
//
// 与来源格式无关：矩形表由各来源（网格/Kenney XML/自定义 proc）产出，
// 经 atlas_from_rects 注入。纹理上传与裁剪按需进行——atlas_upload 传
// device 后 subtexture/crop 才可用（CPU 模式可先做矩形查询）。
package rendering

import "core:fmt"
import "core:mem"
import "core:strings"

import foster "olib:foster"

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

Sprite_Atlas :: struct {
	// 纹理像素源。atlas_upload 用它建纹理、atlas_crop 用它裁剪；
	// 生命周期归图集，dispose 时释放。
	image: foster.Image,

	// 名字 -> 图集内像素矩形（已裁剪后的内容区域）。键为克隆字符串。
	rects: map[string]foster.RectInt,

	// 上传后的整图纹理（nil = 尚未上传，CPU 模式）。
	texture:    foster.Texture,
	has_upload: bool,

	// 裁剪缓存：把某个矩形裁成独立小纹理（九宫格角/边/中块用，
	// 绕开 UV 方向坑走整图绘制路径）。
	crop_cache:  map[string]foster.Texture,
	owned_crops: [dynamic]foster.Texture,
}

// ------------------------------------------------------------------------------
// 构造与释放
// ------------------------------------------------------------------------------

// 从源图 + 矩形表构造（CPU 形态，不碰 GPU）。rects 的键会被克隆。
// 需要绘制时再 atlas_upload(&atlas, device)。
atlas_from_rects :: proc(atlas: ^Sprite_Atlas, image: foster.Image, rects: map[string]foster.RectInt) {
	atlas^ = {
		image = image,
		rects = make(map[string]foster.RectInt, len(rects)),
	}
	for name, rect in rects {
		owned, _ := strings.clone(name, context.allocator)
		atlas.rects[owned] = rect
	}
}

// 上传整图纹理（幂等）。没有 device 的测试/工具流程可以永不上传。
atlas_upload :: proc(atlas: ^Sprite_Atlas, device: ^foster.GraphicsDevice) -> bool {
	if atlas.has_upload do return true
	if device == nil || atlas.image.Width <= 0 do return false
	atlas.texture = foster.TextureFromImage(device, &atlas.image, "SpriteAtlas")
	atlas.has_upload = atlas.texture.Resource != nil
	return atlas.has_upload
}

// 释放全部资源（纹理/裁剪缓存/源图/矩形表）。终止态调用。
atlas_dispose :: proc(atlas: ^Sprite_Atlas) {
	for &crop in atlas.owned_crops {
		if crop.Resource != nil do foster.TextureDispose(&crop)
	}
	clear(&atlas.owned_crops)
	delete(atlas.crop_cache) // 纹理本体在 owned_crops 里已逐个释放
	if atlas.has_upload && atlas.texture.Resource != nil {
		foster.TextureDispose(&atlas.texture)
	}
	delete(atlas.image.Pixels)
	for name in atlas.rects {
		delete(name, context.allocator)
	}
	delete(atlas.rects)
	atlas^ = {}
}

// ------------------------------------------------------------------------------
// 查询
// ------------------------------------------------------------------------------

atlas_get :: proc(atlas: ^Sprite_Atlas, name: string) -> (foster.RectInt, bool) {
	rect, ok := atlas.rects[name]
	return rect, ok
}

atlas_has :: proc(atlas: ^Sprite_Atlas, name: string) -> bool {
	return name in atlas.rects
}

// 名字列表（temp 分配，仅枚举调试用）。
atlas_names :: proc(atlas: ^Sprite_Atlas, allocator := context.temp_allocator) -> []string {
	names := make([dynamic]string, 0, len(atlas.rects), allocator = allocator)
	for name in atlas.rects {
		append(&names, name)
	}
	return names[:]
}

// 按名字取可绘制子图。未上传纹理或名字缺失返回 SubtextureEmpty / false。
atlas_subtexture :: proc(atlas: ^Sprite_Atlas, name: string) -> (foster.Subtexture, bool) {
	rect, ok := atlas.rects[name]
	if !ok || !atlas.has_upload do return foster.SubtextureEmpty, false
	src := foster.Rect{
		f32(rect.X), f32(rect.Y), f32(rect.Width), f32(rect.Height),
	}
	return foster.SubtextureMake(&atlas.texture, src, src), true
}

// ------------------------------------------------------------------------------
// 裁剪 —— 独立小纹理（带缓存）
// ------------------------------------------------------------------------------

// 把图集内某矩形裁成独立纹理（九宫格角/边/中块用）。基于源图像素，
// 首次裁剪后缓存；atlas_dispose 统一释放。
atlas_crop :: proc(atlas: ^Sprite_Atlas, device: ^foster.GraphicsDevice, src: foster.RectInt) -> (foster.Texture, bool) {
	key := atlas_crop_key(src)
	if tex, ok := atlas.crop_cache[key]; ok {
		delete(key, context.allocator)
		return tex, true
	}

	if device == nil || src.Width <= 0 || src.Height <= 0 do return {}, false
	if src.X < 0 || src.Y < 0 ||
	   src.X + src.Width > atlas.image.Width ||
	   src.Y + src.Height > atlas.image.Height {
		return {}, false
	}

	cropped := foster.ImageMake(src.Width, src.Height, foster.Color{0, 0, 0, 0})
	for row in 0..<src.Height {
		dst_start := row * src.Width
		src_start := (src.Y + row) * atlas.image.Width + src.X
		mem.copy(
			raw_data(cropped.Pixels[dst_start:dst_start + src.Width]),
			raw_data(atlas.image.Pixels[src_start:src_start + src.Width]),
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
atlas_crop_key :: proc(src: foster.RectInt) -> string {
	return fmt.aprintf("%d,%d,%d,%d", src.X, src.Y, src.Width, src.Height, allocator = context.allocator)
}
