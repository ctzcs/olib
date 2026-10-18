# 游戏代码与 UI 热重载

桌面开发期使用 **常驻宿主 + 游戏动态库**。保存 Odin 源码后自动编译，在宿主选择的安全帧边界
替换游戏逻辑和 UI；窗口与图形设备保持存活。编译期间旧游戏继续更新，失败时保留旧模块。
这是编译后生效，默认检测和稳定等待各 250ms，再加实际编译、快照与初始化时间。

新建 Windows 游戏直接使用 [tools/new-game 模板](../../tools/new-game/README.md)：
`odin run tools/new-game -- ../MyGame MyGame`，进入新目录运行 `play.bat`。
模板已接好宿主、模块、状态快照和静态发布，以下接入细节主要用于扩展模板或接入已有项目。

模板的常驻 `src/editor/main.odin` 提供窗口内失败摘要和 `build/hotreload-last-error.txt` 完整日志；首次编译失败也能显示，旧模块仍运行时会显示版本号。提示跨等待/编译保留，只有实际安装新模块成功才清除。该 UI 是模板接入代码，纯 core 层仍只返回状态与诊断，既有项目需自行接入。

实现只依赖 Odin 标准库与 `core/devbuild`，因此放在 `core/hotreload`，不另建 Foster 生命周期封装。
`kit/ui` 无需增加另一套声明接口：把 UI 声明放在游戏模块内，每次加载重新建立该模块的 UI 上下文即可。

## 当前能力与边界

| 操作 | 行为 |
| --- | --- |
| 修改玩法、UI 声明、颜色、尺寸和布局 | 编译成功后整模块切换，下一次 render 使用新代码 |
| 保留当前局面 | 旧模块保存快照，新模块建立独立世界；动态数组等在模块内部重建 |
| 快照格式不变 | 默认 `.Compatible` 保留状态 |
| 快照格式升级 | 默认拒绝；明确用 `.Migrate` 将旧版本快照交给新 load，或 `.Reset` 重开 |
| 编译、API、快照或候选初始化失败 | 旧模块继续运行，诊断保存在 `Watch.diagnostic` / `Session.diagnostic` |
| 编译过程中继续保存、Ready 后再保存 | 丢弃观测到的过期候选，重新编译最新内容 |
| Foster/宿主协议/编译器升级 | 重建并重启宿主；不承诺底层运行时热替换 |
| Web、发布版本 | 保持原来的静态入口，不接入监听器和 DLL 加载 |

当前实际验收平台为 Windows；代码使用 `core:dynlib` / `core:os` 的原生桌面接口，
Linux/macOS 尚未做运行验收。此机制不隔离游戏崩溃，也不能回滚候选模块私自写入宿主或外部文件的副作用。

## 所有权与接入目录

模板使用 core（游戏）、core_editor（编辑器实现）、editor（常驻开发入口）、game（发布入口）四目录。`src/core_editor/module.odin` 将编辑会话和共享 core 组装为一个 DLL，游戏逻辑、游戏 UI 和编辑器工具 UI 一起热重载。`src/editor/main.odin` 保留窗口、资源、监听和最小失败提示；共享服务协议及资源函数位于 `src/core/services.odin`，没有独立 host 包。
组合快照保存游戏进度、编辑会话持久数据和待处理命令，UI/GPU 对象和瞬时输入重新建立，旧的按住输入须等松开再接收。game 静态导入 core，发布排除 core_editor、editor 和加载器。入口、共享服务协议或底层依赖修改后重启；常驻入口不创建静态游戏实例，不持有 DLL 内的业务指针。

- **宿主拥有** `foster.App`、窗口、设备、`Session`、`Watch`、稳定服务结构及其分配器。
  `StartupProc / UpdateProc / RenderProc / ShutdownProc` 始终指向宿主代码，向 Session 转发。
- **开发模块拥有**游戏和编辑会话、自己的世界、UI/Clay、Batcher、表现缓存、任务和注册项。
  可以包含指针、动态数组、map；这些对象必须在本模块卸载前释放，不能直接复制给下一版。
- **快照只包含自有数据**：数值、稳定 ID、数组内容、字符串内容和必要的格式版本。
  不保存裸指针、函数指针、`any/typeid`、分配器、GPU 句柄或 UI/Clay 内存。
  游戏可用 JSON、已有存档格式或自己的二进制编码；库不假设 World 布局。
- 外部资源可由宿主持有并通过稳定服务获取；模块引用不能超过宿主资源寿命。
  相同包分别编译进 EXE/DLL 会产生各自的全局变量，例如资源导入器注册表和 Clay 当前上下文。
  不把包全局状态当作跨模块共享服务。开发期编译监听器放在宿主，避免模块卸载时仍有编译任务。

宿主与模块须使用**同一版本 Odin、架构、编译选项和共享协议源码**。本协议采用显式 `proc "c"` 入口，
仍传递 Odin 的 Context 和 slice，不是对外稳定 C 插件 ABI。游戏自定义 `host_version` 必须覆盖
服务结构、共享 Foster 类型与库版本等边界；变更后升级它并重启。`state_version` 描述快照格式，
不描述内存布局；只要快照兼容，模块内部结构体加字段也可以自行填默认值，不必重置游戏。

## 宿主使用

以下是接线片段；`Services` 是游戏自己的稳定宿主服务结构。
`Session / Watch / Services` 的地址须稳定，通常放在宿主堆分配状态中。
所有公开接口由同一宿主线程调用；不要在模块回调内重入 reload/dispose。

```odin
import reload "olib:core/hotreload"

// Startup；init 的 allocator 必须来自常驻宿主，不能是帧临时分配器。
assert(reload.init(&host.session, HOST_VERSION, &host.services))
assert(reload.watch_init(&host.watch, {
	working_directory = project_root,
	command = {
		"odin", "build", "src/core_editor", "-build-mode:dll",
		"-collection:olib=../olib", "-collection:game=src", "-out:{output}",
	},
	roots = {"src/core", "src/core_editor"},
}))

// UpdateProc 开始，尚未生成本帧 UI、Batcher 或渲染队列。
reload.watch_update(&host.watch, dt)
if host.watch.status == .Ready {
	result := reload.watch_apply(&host.watch, &host.session)
	// result != .Success 时显示 diagnostic；现有模块仍然可用。
}
reload.update(&host.session, dt)

// RenderProc
reload.render(&host.session, dt)

// ShutdownProc；先停止游戏模块，再等待编译器结束并清理私有产物。
assert(reload.dispose(&host.session))
reload.watch_dispose(&host.watch)
```

`watch_init` 复制参数和路径，所有相对 root 按 `working_directory` 解析。
参数数组直接传给进程，不经过 shell；`{output}` 被替换为本次唯一的完整产物路径。
`command` 必须完整生成一个 DLL/shared library；不要让构建脚本在返回成功后继续后台写产物。
默认只递归监听 `.odin`，忽略隐藏目录、`build`、`Library`；不跟随符号链接。
`#load` 的数据文件、额外 import 根等须通过 `roots`（可直接指定文件）或 `extensions` 显式加入。
不自动扫描整个依赖图；不要把宿主 ABI 的改动当作只更新 DLL 就能生效。
扫描会读取并哈希内容，roots 应聚焦开发源码，以免大资产目录影响帧耗时。

内部仅有一个后台编译任务，连续编辑会合并；内容不变的失败不会每帧重编。
修复源码后自动重试；工具链/环境修复后可调用 `watch_retry`。
`watch_apply(..., .Migrate/.Reset)` 在 Ready 时明确指定策略；若此前已拒绝，用 `watch_retry` 再编译后应用。
`dispose` 会等待正在运行的编译任务，编译器挂起时退出也会等待；当前没有编译取消或超时 API。

已有外部构建系统可跳过 Watch，直接对**已经完成写入**的产物调用 `reload(&session, path)`。
Session 只复制产物，不监听这个路径；影子文件与原产物在同目录，源文件不会被 Windows 长期锁住。
运行依赖 DLL 仍需处于宿主/系统可搜索的位置；`cache_parent` 可以指定构建缓存父目录。
多个宿主会话使用独立缓存和影子文件。退出清理自身产物；崩溃留下的临时文件不会自动扫描删除。
这些隔离目录属于 [生成文件规则](../../prompts/new-project.md#生成文件与目录纪律) 的生命周期例外，
不能合并成共享输出目录。工具已有构建日志仍可放 build；需留存的诊断副本在会话停止后
归入所属项目的 library/tmp，验收截图归入 library/screenshots。

## DLL 导出协议

```odin
@(export)
olib_game_api :: proc "c" (version: u32, size: int, api: ^reload.API) -> bool {
	if version != reload.API_VERSION || size != size_of(reload.API) do return false
	api^ = {
		host_version = HOST_VERSION,
		state_version = 1,
		load = game_load,
		unload = game_unload,
		activate = game_activate, // 可为 nil
		snapshot_size = game_snapshot_size,
		save = game_save,
		update = game_update,
		render = game_render,
	}
	return true
}
```

所有回调均为 `proc "c"`，在需要 Context 时首先写 `context = call.host_context^`，
使用宿主分配器和当前帧的临时分配器。不要把这个 Context 指针保存起来。

| 回调 | 契约 |
| --- | --- |
| `load(^Call, Snapshot) -> bool` | 新建私有状态并写 `call.instance`；version=0 表示新局。输入快照只借用到返回，不可持有其切片/字符串。失败时也会调用 unload |
| `snapshot_size(^Call) -> int` | 只读地返回编码长度；负数表示失败。默认上限 64 MiB，可在 init 配置 |
| `save(^Call, []u8) -> bool` | 将完整自有状态编码到宿主提供的固定长度缓冲，必须只读旧世界；不要存地址 |
| `activate(^Call)` | 新版本提交后才注册宿主回调或启动任务；不能失败，不替换 instance |
| `update/render(^Call, f64)` | 使用当前 instance；`frame` 是宿主每次调用可选传入的短期数据，不跨帧保存 |
| `unload(^Call)` | 容忍部分初始化；取消交互，注销回调，停止并 join 任务，释放 UI、表现和世界 |

顺序为：检查候选 → 旧版保存快照 → 新版 load → 旧版 unload → 替换 → 新版 activate。
新旧私有世界短暂共存，需计入峰值内存。`load` 只创建私有资源；不要在其中改写宿主场景、注册回调、
播放音效或写存档。这些不可回滚的行为放在成功提交后。DLL 的 `@(init)` / `@(fini)` 同样不能操作外部状态。

API 检查只校验声明的版本和必需回调，不会自动验证任意游戏代码的 ABI、快照内容或资源所有权。
断言失败、访问越界和无限循环仍会影响整个宿主进程。

## UI 与 Foster 的生命周期

每个候选拥有新的、地址稳定的 `UI_Context`，在 load 中 `ui_init` 并重新注册字体，在 unload 中
先 `ui_dispose` 再释放它引用的字体/纹理。旧 Context 不跨 DLL 复用：Clay 保存错误/文字测量回调，
布局缓存也可能借用模块里的文字和配置地址。每帧在新模块里重新执行 UI 声明。

背包是否打开、选中道具、设置值等可保存到游戏快照；悬停、按住、拖动、键盘焦点等瞬时交互默认重置，
编辑事务在旧模块卸载前取消或完成，不能把拖动中的指针交给新模块。
纯 UI 样式改动会重新创建整个模块实例，但保留游戏自己写入快照的状态。

宿主仍直接调用 `foster.InitApp / Run / Exit / Dispose`，库不改这些入口。
重载前必须保证没有旧模块函数仍在调用栈、任务、音频回调、宿主主线程队列或定时器中。
回调注册需要可注销，或通过常驻宿主跳板间接调用当前模块；不要直接把 DLL proc 留在 App 中。
GPU 命令、Batcher、UI 文本和帧临时数据消费完成后才能切换。
涉及异步 GPU/资源释放时由宿主建立同步点；不确定时在重载边界等待 GPU idle，库的纯 core 层不替代设备同步。

字体与 UI 仍按 [最终像素采样约定](../../kit/ui/README.md#最终像素采样与清晰度验收) 绘制。
热重载不会改变分辨率、采样或字体质量策略，也不把游戏资源热更新自动等同于代码热更新。
HLSL 继续走 `kit/shaderdev`；宿主中的 Shader、参数生成器与游戏编译器通过 `core/devbuild` 串行启动/执行子进程，
避免当前 Odin `process_start` 的句柄继承并发问题。游戏帧不等待这个编译锁。

## 验证

```powershell
odin run tools/check -- -only:core/hotreload
odin run tools/check
```

保留无窗口单元测试与构建检查。交互示例位于同级 olib_sample，运行
`run.bat hotreload` 后可手动修改 UI/玩法体验热重载。
