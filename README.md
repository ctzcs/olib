# olib

Odin 游戏库集合，内置 `foster/`（Foster 框架的 Odin 移植，原 OFoster 仓库）。
结构对位 [DragonLib](https://github.com/ctzcs/DragonLib)（C#/Foster）。

## 布局

```
core/        基础库（无引擎依赖）
├── handle/    代数句柄池：array（可扩容）/ fixed（定容）/ growing（arena）/ virtual（虚存）
├── entities/  轻量实体容器（union 变体 + 按组件迭代，Ravn 同源）
├── encoding/  json（Value 树 + struct）/ csv（表驱动配置）
├── messaging/ CommandQueue（单消费者）/ BroadcastChannel（延迟一帧广播）
├── dasset/    .dasset 模型格式数据层（比特兼容 DragonLib v4，无渲染依赖）
├── tween/     补间系统（manager / sequence / 插值原语）
├── debug/     Tracking_Allocator 的 defer 包装
└── profiler/  作用域计时统计

foster/      Foster 框架的 Odin 移植（原 OFoster；保留 API、源码组织与 Git 历史）

kit/         扩展层（kit）：依赖 foster/ 与 core/
├── asset/       资源管线：.meta 管身份、Library 管派生、blob 为边界、manifest 打包零改动
├── world/       Camera2D/Camera3D + Frustum3D/Ray3D + Matrix4 / SceneRouter
├── rendering/   Sprite / SpriteAtlas + Grid/Kenney 图集源 + Aseprite 构建器
├── rendering3d/ 3D 数据与队列层：Mesh 上传 / 材质状态 / 渲染排序
├── animation/   骨骼动画采样 / palette / 混合
├── storage/     资源根 / 用户存档路径策略
├── app/         CLI 参数 + 调试控制台（可选 cli_open 接入 foster.App）
├── audio/       SDL3 音频（设备流 / WAV 装载 / 播放）
└── ui/          clay 布局 + 位图/MSDF/裁剪后端 + 游戏控件/输入/缩放

thirdparty/  外部绑定：clay-odin / odin-imgui（含 Foster 后端）/ oflecs
```

## 使用

基础能力（App、窗口、输入、图形、基础类型）直接用 `olib:foster`，
扩展能力用 `olib:kit/*`，通用数据结构和格式用 `olib:core/*`。

以 collection 方式引用（olib 根 = 仓库根）：

```sh
odin build <app> -collection:olib=<olib 路径>
```

```odin
import ha    "olib:core/handle/array"
import msg   "olib:core/messaging"
import foster "olib:foster"
import asset "olib:kit/asset"
import world "olib:kit/world"
```

最小启动示例直接注册 Foster 回调；传 `cli` 参数时可选开启控制台：

```odin
package main

import "core:os"

import foster "olib:foster"
import app "olib:kit/app"

game: foster.App
console: app.Cli_Console

startup :: proc(g: ^foster.App) {
    if app.has_arg(os.args, "cli") {
        _ = app.cli_open(&console, g)
    }
}

update :: proc(g: ^foster.App) {
    app.cli_update(&console)
}

shutdown :: proc(g: ^foster.App) {
    app.cli_dispose(&console)
}

main :: proc() {
    foster.InitApp(&game, foster.DefaultAppConfig("My Game", 1280, 720))
    defer foster.Dispose(&game)
    game.StartupProc = startup
    game.UpdateProc = update
    game.ShutdownProc = shutdown
    foster.Run(&game)
}
```

退出统一调用 `foster.Exit`。`cli_update` 和 `cli_dispose` 对零值控制台及开启失败后的
控制台也安全；`examples/game_ui` 可用 `cli` 参数试用 `help`、`quit`。

各模块文档见包内注释、[资源管线](kit/asset/README.md)与 [游戏 UI](kit/ui/README.md)。
游戏 UI 示例见 `examples/game_ui`（遗迹场景、HUD、技能冷却、格子背包、暂停菜单）；
基础控件验收页见 `examples/ui_gallery`。

## 测试

```sh
odin test core/handle/array -collection:olib=.
odin test core/messaging
odin test core/dasset
# 其余包同理：core/entities core/tween kit/asset kit/world ...
```

编码规范：[docs/CODE_STYLE.md](docs/CODE_STYLE.md)
移植路线图：[docs/ROADMAP.md](docs/ROADMAP.md)
