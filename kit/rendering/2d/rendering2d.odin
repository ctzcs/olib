// rendering2d —— 2D 精灵、帧动画与图集。
//
// 分层：
//   atlas.odin          核心图集：纹理 + 「名字 -> 像素矩形」，与来源格式无关
//   atlas_grid.odin     等分网格来源（tilesheet，无坐标文件）
//   atlas_kenney.odin   Kenney/Starling XML 坐标来源
//   atlas_aseprite.odin .aseprite 目录 -> 单张图集的构建器（打包侧）
//   render2d.odin       Render2D：2D 唯一的绘制入口（记录后统一提交，olib 材质，含 UI）
//   sprite_buffer.odin  常驻显存的精灵实例缓冲（r2d.buffer 绘制）
//   animation_set.odin  帧动画集合（图集子图 + 时长 + 命名动画）
//
// 图集与帧动画用 Foster 的 Subtexture / Packer / Aseprite；绘制不使用 foster.Batcher。
package rendering2d

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
