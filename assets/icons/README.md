# 默认图标图集

Game Icon Pack v1.4 的 `padding/128px/white`：815 个图标，12 个分类，
统一打包为 `game-icons.png`（4096×4096）和 Kenney/Starling 格式的 `game-icons.xml`。
PNG 使用无损索引色与 straight alpha，加载后解码为 RGBA8；XML 名称为
`分类/文件名`，例如 `game/action-points`。
去掉原分类目录的数字排序前缀，不保留 `.png` 后缀。

原图的 128×128 画布与留白完整保留，每边另加 2px 边缘扩展。
坐标指向原图区域，不包含扩展边缘。排列顺序不是 API，调用方应按名字查询。
XML 中额外记录原始相对路径与 SHA-256，供更新核对；不要手动修改生成文件。

## 加载与绘制

```odin
import r2d "olib:kit/rendering/2d"
import ui "olib:kit/ui"

// 图集应放在地址稳定的游戏状态中；在 GraphicsDevice 初始化后加载一次。
icons: r2d.Sprite_Atlas
ok := r2d.builtin_icons_load(&icons, &game.GraphicsDevice)
assert(ok)

// UI 声明阶段；名字列表可通过 r2d.atlas_names(&icons) 获取。
sub, found := r2d.atlas_subtexture(&icons, "game/action-points")
if found {
	ui.ui_image(&ctx, sub, 32, 32, {120, 200, 255, 255})
}

// shutdown：在所有使用结束后、GraphicsDevice 释放前执行。
r2d.atlas_dispose(&icons)
```

`builtin_icons_load` 用 `#load` 嵌入资源，不依赖进程工作目录，也不自动初始化 GPU。
调用目标必须为零值；重复加载已使用的目标会失败且保留原内容。
已加载图集不可复制/移动，返回的 Subtexture 引用图集内的纹理地址。
加载失败会清理本次分配并返回 false。

纹理为 RGBA8、无 mipmap，显存约 64 MiB；PNG 文件大小不等于显存占用。
上传后释放 CPU 图像，额外的约 64 MiB 解码像素只在加载期间存在。
采用普通线性采样、预乘 alpha 混合；白色图标通过 tint 改色。
UI 在最终像素目标绘制，小尺寸与非整数缩放仍需在项目最终输出中验收。

也可自行读取 PNG/XML，调用 `kenney_build_rects → atlas_from_rects → atlas_upload`。
此路径须自己调用一次 `foster.ImagePremultiply`，并管理 CPU 像素生命周期。

## 来源与许可记录

来源：用户提供的 `Game-Icon-Pack-v1.4-PNG/padding/128px/white` 本地资源包。
当前提供的目录没有附带原作者、下载页面或许可证；这些信息尚待补齐。
此记录不是许可证，也不声称图标适用 olib 代码的许可。对外发布或再分发前应补齐
原包许可与要求的署名。此次只生成本地仓库资源，未发布。

原始的 815 个 PNG 不重复存入仓库；重建时提供原包目录。
生成命令和完整像素校验见 [打包工具](../../tools/icons/README.md)。

## 在 ImGui 中使用

ImGui 的 sdlgpu3 管线按 straight alpha 混合，且工具只用到几十个图标，不直接借用上面预乘后的 4096 图集。
用 `r2d.builtin_icons_decode()` 取 CPU 原图与名称表，交给 ImGui 后端的 `IconsInit` 挑出需要的名字、
面积平均缩放成小图标表，再用 `Icon` / `IconButton` 绘制：

```odin
import r2d "olib:kit/rendering/2d"
import imgui_foster "olib:thirdparty/odin-imgui/imgui_impl_ofoster"

image, rects, ok := r2d.builtin_icons_decode()
if ok {
	defer delete(image.Pixels)
	defer r2d.kenney_rects_dispose(rects)
	// 格子取绘制尺寸的约 2 倍；icons 地址稳定，在 Shutdown 与设备释放前 IconsDispose。
	imgui_foster.IconsInit(&icons, device, image, rects^, {"media/play", "ui/settings"}, 40)
}
if imgui_foster.IconButton(&icons, "play", "media/play", "播放") {
	// ...
}
```

解码每次约 64 MiB 临时像素，用完即释放；图标表只占几十 KB 显存。
