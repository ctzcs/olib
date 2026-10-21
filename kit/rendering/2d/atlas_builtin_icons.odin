package rendering2d

// 默认图标资源：编译时嵌入 PNG/XML，显式上传一次；不经过项目资产导入管线。
// 分区：
//   加载 —— 内置解码 / 名称表 / GPU 上传与 CPU 像素释放

import foster "olib:foster"

// atlas 必须为零值，地址稳定并存活到全部 Subtexture 使用结束；禁止复制已加载图集。
// device 必须已初始化。成功后由调用方在 device 销毁前 atlas_dispose。
// 上传后释放 CPU 像素（约 64 MiB），只保留纹理与名称表。
// 失败不保留分配。重复调用已使用的 atlas 返回 false，不覆盖其内容。
builtin_icons_load :: proc(
	atlas: ^Sprite_Atlas,
	device: ^foster.GraphicsDevice,
) -> bool {
	if atlas == nil || device == nil do return false
	if atlas.has_upload || atlas.pages != nil || atlas.regions != nil {
		return false
	}
	image, rects, ok := builtin_icons_decode()
	if !ok do return false
	defer kenney_rects_dispose(rects)

	// PNG 保持普通 straight alpha，解码后只做一次预乘。
	foster.ImagePremultiply(&image)
	atlas_from_rects(atlas, image, rects^)
	if !atlas_upload(atlas, device) {
		atlas_dispose(atlas)
		return false
	}
	return true
}

// CPU 原图（4096×4096 RGBA，straight alpha，不预乘、不上传）与名称表，供另建纹理的工具使用，
// 例如只取几十个图标缩放成小图标表。成功后调用方 delete(image.Pixels) 并 kenney_rects_dispose(rects)；
// 失败不保留分配。每次调用都重新解码，约 64 MiB 临时像素。
builtin_icons_decode :: proc() -> (image: foster.Image, rects: ^map[string]foster.RectInt, ok: bool) {
	rects = kenney_build_rects(#load("../../../assets/icons/game-icons.xml"))
	if rects == nil do return {}, nil, false
	image = foster.ImageFromEncoded(#load("../../../assets/icons/game-icons.png"))
	if image.Width != 4096 || image.Height != 4096 {
		delete(image.Pixels)
		kenney_rects_dispose(rects)
		return {}, nil, false
	}
	return image, rects, true
}
