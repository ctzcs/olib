# olib

Odin 游戏库集合，内置 `foster/`（Foster 框架的 Odin 移植，原 OFoster 仓库）。
结构对位 [DragonLib](https://github.com/ctzcs/DragonLib)（C#/Foster）。

让 AI 创建新游戏时，使用 [新项目创建提示词](prompts/new-project.md)：包含精简游戏模板与按需拆包的依赖约定、默认保留状态的桌面代码/UI 热重载、kit/ui 界面、Odin 编码风格与中文注释、桌面/Web 发布和验证约定。源码分为 core、core_editor、editor、game：core_editor 和 core 共用一个热重载 DLL，editor 是常驻开发入口；玩法与游戏 UI 复用于静态发布入口。新游戏默认放在 olib 的同级独立目录。日常开发中的数据布局、内容目录、模拟实例所有权、缓存失效与验证方式见 [面向数据开发约定](prompts/dod-guidelines.md)。

开发编辑器、开发面板或交互工具时，遵循 [编辑工具开发约定](prompts/editor-guidelines.md)：统一编辑会话、工具输入、编辑事务、撤销与保存。它是项目组织与接入规则，不代表库已提供编辑器框架。

新建 Windows 游戏可直接运行 `odin run tools/new-game -- ../MyGame MyGame`，进入新目录运行 `play.bat`。生成的[游戏模板](tools/new-game/README.md)已包含热重载宿主、共享 core 包、独立的 core_editor 实现与薄 editor 开发入口、可一起热重载的游戏与编辑器 UI、薄 game 发布入口、Windows/Web 静态发布、默认跨平台存储、字体资产与构建检查，无需从示例复制接线。

生成截图、图像候选和临时报告时统一遵循 [生成文件与目录纪律](prompts/new-project.md#生成文件与目录纪律)：
归入所属项目的 library 固定子目录，按需创建；目录或文档调整不额外截图。正式资源与构建产物另行维护。

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
├── hotreload/ 桌面游戏 DLL 热重载：后台编译、快照恢复、UI 重建与失败保留旧版
├── devbuild/  开发期编译子进程互斥（游戏 / Shader / 参数生成共用）
└── profiler/  作用域计时统计

foster/      Foster 框架的 Odin 移植（原 OFoster；保留 API、源码组织与 Git 历史）

kit/         扩展层（kit）：依赖 foster/ 与 core/
├── asset/       资源管线：.meta 管身份、library/assets 管派生、blob 为边界、manifest 打包零改动
├── world/       Camera2D/Camera3D + Frustum3D/Ray3D + Matrix4 / SceneRouter
├── gizmo/       2D/3D 移动、旋转、局部与等比缩放，命中与 Batcher 覆盖层，不持有场景对象
├── rendering/   Sprite / SpriteAtlas + Grid/Kenney 图集源 + Aseprite 构建器
├── rendering3d/ 3D 机制：Mesh 上传 / 泛型渲染队列 / 字节码选择 / std140 / DebugDraw3D / LOD（光照材质由游戏实现）
├── animation/   骨骼动画采样 / palette / 混合
├── material/    材质参数描述、独立实例值、稳定 ID 迁移与生成 GPU 布局
├── shaderdev/   Odin 字段标签生成参数面板数据；HLSL 热重载，2D/3D 共用
├── storage/     跨平台资源根 / 用户存储路径策略
├── app/         CLI 参数 + 调试控制台（可选 cli_open 接入 foster.App）
├── audio/       SDL3 音频（设备流 / WAV 装载 / 播放）
└── ui/          clay 布局 + 位图/MSDF/裁剪后端 + 游戏控件/输入/缩放

thirdparty/  外部移植与绑定：纯 Odin clay-odin / odin-imgui（含 Foster 后端）

prompts/     给 AI 的提示词：新项目创建 / 面向数据开发约定 / 编辑工具开发约定
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
内置 [默认图标图集](assets/icons/README.md) 提供 815 个白色图标，单张 4096×4096 PNG；
通过 `rendering.builtin_icons_load` 加载，按名称取得 Subtexture，可直接用于 UI 或 Batcher。

桌面开发期可接入 [游戏代码与 UI 热重载](core/hotreload/README.md)：常驻宿主保留窗口/设备，
保存 Odin 后后台编译游戏 DLL，在安全帧边界通过快照恢复游戏数据并重建 UI。编译或候选初始化失败
保留旧版。需要游戏实现模块入口与快照，并非给现有可执行程序加一个开关即可；发布/Web 继续静态构建。
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
odin run tools/check -- -only:kit/ui
```

Shader 的模块归属、源码与 `Compiled/` 分层及统一编译入口见 [Shader 归属与编译](tools/shaders/README.md)。

编码规范：[docs/CODE_STYLE.md](docs/CODE_STYLE.md)
移植路线图：[docs/ROADMAP.md](docs/ROADMAP.md)

可嵌入编辑器的 Shader 工具见 [kit/tools/shader_lab](kit/tools/shader_lab/README.md)，底层热重载见
[kit/shaderdev](kit/shaderdev/README.md)。在同级 olib_sample 运行 `run.bat shader_lab`，保存 HLSL 即可更新 2D/3D 预览。
