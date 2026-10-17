package rendering

// 默认图标资源：编译时嵌入 PNG/XML，显式上传一次；不经过项目资产导入管线。
// 分区：
//   加载 —— 内置解码 / 名称表 / GPU 上传与 CPU 像素释放

import foster "olib:foster"

// atlas 必须为零值，地址稳定并存活到全部 Subtexture 使用结束；禁止复制已加载图集。
// device 必须已初始化。成功后由调用方在 device 销毁前 atlas_dispose。
// 默认释放 CPU 像素（约 64 MiB），仅保留纹理与名称表；需要 atlas_crop 时传 true。
// 失败不保留分配。重复调用已使用的 atlas 返回 false，不覆盖其内容。
builtin_icons_load :: proc(
	atlas: ^Sprite_Atlas,
	device: ^foster.GraphicsDevice,
	keep_pixels := false,
) -> bool {
	if atlas == nil || device == nil do return false
	if atlas.has_upload || atlas.texture.Resource != nil || atlas.image.Width != 0 ||
		len(atlas.image.Pixels) != 0 || atlas.rects != nil || atlas.crop_cache != nil ||
		len(atlas.owned_crops) != 0 {
		return false
	}
	rects := kenney_build_rects(#load("../../assets/icons/game-icons.xml"))
	if rects == nil do return false
	defer kenney_rects_dispose(rects)

	image := foster.ImageFromEncoded(#load("../../assets/icons/game-icons.png"))
	if image.Width != 4096 || image.Height != 4096 {
		delete(image.Pixels)
		return false
	}
	// PNG 保持普通 straight alpha，解码后只做一次预乘。
	foster.ImagePremultiply(&image)
	atlas_from_rects(atlas, image, rects^)
	if !atlas_upload(atlas, device) {
		atlas_dispose(atlas)
		return false
	}
	if !keep_pixels {
		delete(atlas.image.Pixels)
		atlas.image = {}
	}
	return true
}
