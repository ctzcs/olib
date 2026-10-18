// rendering —— 公共材质资源、2D 精灵与图集。
//
// 分层：
//   atlas.odin          核心图集：纹理 + 「名字 -> 像素矩形」，与来源格式无关
//   atlas_grid.odin     等分网格来源（tilesheet，无坐标文件）
//   atlas_kenney.odin   Kenney/Starling XML 坐标来源
//   atlas_aseprite.odin .aseprite 目录 -> 单张图集的构建器（打包侧）
//   material_library.odin 2D/3D 共用材质加载、缓存与重载
//   material_draw.odin    公共对象多 Pass 执行
//   material_sprite.odin  材质 Sprite 实例与立即绘制
//   sprite.odin         帧动画集合（图集子图 + 时长 + 命名动画）
//
// 渲染底座全部用 Foster 现成能力：Subtexture / Packer / Aseprite / Batcher。
package rendering

import "core:strings"


// ------------------------------------------------------------------------------
// 包内共享辅助 —— 字符串克隆 / 路径拼接（context.allocator，调用方持有）
// ------------------------------------------------------------------------------

@(private)
clone_owned :: proc(s: string) -> string {
	out, _ := strings.clone(s, context.allocator)
	return out
}

@(private)
join_owned :: proc(a, b: string) -> string {
	if a == "" do return clone_owned(b)
	return strings.join({a, b}, "/", context.allocator)
}
