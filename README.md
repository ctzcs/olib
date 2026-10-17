# olib

Odin 游戏库集合，内置 `foster/`（Foster 框架的 Odin 移植，原 OFoster 仓库）。
结构对位 [DragonLib](https://github.com/ctzcs/DragonLib)（C#/Foster）。

让 AI 创建新游戏时，使用 [新项目创建提示词](prompts/new-project.md)：包含 def/data/logic/view/game 五层目录与依赖方向、kit/ui 界面、Odin 编码风格与中文注释、桌面/Web 发布和验证约定。新游戏默认放在 olib 的同级独立目录。日常开发中的数据布局、内容目录、模拟实例所有权、缓存失效与验证方式见 [面向数据开发约定](prompts/dod-guidelines.md)。

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
├── rendering3d/ 3D 机制：Mesh 上传 / 泛型渲染队列 / 字节码选择 / std140 / DebugDraw3D / LOD（光照材质由游戏实现）
├── animation/   骨骼动画采样 / palette / 混合
├── storage/     资源根 / 用户存档路径策略
├── app/         CLI 参数 + 调试控制台（可选 cli_open 接入 foster.App）
├── audio/       SDL3 音频（设备流 / WAV 装载 / 播放）
└── ui/          clay 布局 + 位图/MSDF/裁剪后端 + 游戏控件/输入/缩放

thirdparty/  外部移植与绑定：纯 Odin clay-odin / odin-imgui（含 Foster 后端）

prompts/     给 AI 的提示词：新项目创建 / 面向数据开发约定
```

可运行示例在独立仓库 [olib_sample](https://github.com/ctzcs/olib_sample)（与 olib 同级检出，`run.bat <示例名>`）。

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

App 生命周期直接使用 Foster。游戏状态放在独立结构体中，通过 `AppSetUserData` 挂到 App，
回调中用 `AppGetUserDataAs` 按类型取回；它不做类型校验，取回的类型必须与挂载的指针一致。

下面的桌面启动示例直接注册 Foster 回调，传 `cli` 参数时可选开启控制台：

```odin
package main

import "core:os"

import foster "olib:foster"
import app "olib:kit/app"

Game_State :: struct {
	console: app.Cli_Console,
}

startup :: proc(g: ^foster.App) {
	state := foster.AppGetUserDataAs(g, Game_State)
	if app.has_arg(os.args, "cli") {
		_ = app.cli_open(&state.console, g)
	}
}

update :: proc(g: ^foster.App) {
	state := foster.AppGetUserDataAs(g, Game_State)
	app.cli_update(&state.console)
}

shutdown :: proc(g: ^foster.App) {
	state := foster.AppGetUserDataAs(g, Game_State)
	app.cli_dispose(&state.console)
	free(state)
	foster.AppSetUserData(g, nil)
}

main :: proc() {
	game: foster.App
	foster.InitApp(&game, foster.DefaultAppConfig("My Game", 1280, 720))
	defer foster.Dispose(&game)
	foster.AppSetUserData(&game, new(Game_State))
	game.StartupProc = startup
	game.UpdateProc = update
	game.ShutdownProc = shutdown
	foster.Run(&game)
}
```

退出统一调用 `foster.Exit`。`cli_update` 和 `cli_dispose` 对零值控制台及开启失败后的
控制台也安全；示例仓库中 `run.bat game_ui cli` 可试用 `help`、`quit`。

游戏状态应堆分配（如上面的 `new(Game_State)`，在 `shutdown` 中释放），也可使用全局变量。
Web 上 `Run` 会把 App 拷贝到堆上并立即返回，但不会搬移游戏状态；因此状态不能放在 `main` 的栈上，
也不要在状态结构体中内嵌 App。回调应使用收到的 `^foster.App`，不要缓存 `Run` 前的 App 指针。
上面的 CLI 示例依赖 `core:os` 与 `kit/app`，仅限桌面；跨平台的状态组合示例见
[Foster App 用法](foster/README.md#app-usage)与示例仓库的 `app_composition`。

各模块文档见包内注释、[资源管线](kit/asset/README.md)与 [游戏 UI](kit/ui/README.md)。
游戏 UI 示例见 [olib_sample](https://github.com/ctzcs/olib_sample) 的 `game_ui`（遗迹场景、HUD、技能冷却、格子背包、暂停菜单）；
基础控件验收页见同仓库的 `ui_gallery`。

## 测试

提交前运行一键验证（任何一项失败即以非零退出码结束）。工具用 Odin 写成，只依赖 `core:*`，
Windows / macOS / Linux 通用，可在任意目录运行：

```bash
odin run tools/check                    # 全部检查
odin run tools/check -- -no-samples     # 跳过同级 olib_sample 示例的编译与测试
odin run tools/check -- -only:kit/ui    # 只运行名称含该子串的检查项
```

它会自动发现并运行 `core/`、`kit/` 下所有含 `@(test)` 的包，检查 `foster` 包、编译 foster 自带回归程序与
odin-imgui 的 foster 后端示例、校验 foster 本地修改清单；同级存在 olib_sample 时再编译全部示例。

单独测一个包：

```sh
odin test kit/ui -collection:olib=.
```

Shader 的模块归属、源码与 `Compiled/` 分层及统一编译入口见 [Shader 归属与编译](tools/shaders/README.md)。

编码规范：[docs/CODE_STYLE.md](docs/CODE_STYLE.md)
移植路线图：[docs/ROADMAP.md](docs/ROADMAP.md)
