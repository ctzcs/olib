# 游戏代码与 UI 热重载

桌面开发期用 **常驻宿主 + 游戏动态库**：保存 Odin 源码，后台自动编译，成功后在安全的帧边界替换游戏，
窗口和图形设备不重启，当前局面保留。编译期间旧游戏继续运行，编译失败则保留旧版。
这是"编译后生效"，不是解释执行：检测和稳定等待各约 250ms，再加编译、快照和初始化时间。

## 最快接入：宿主 4 个调用，游戏一张回调表

**宿主**（`Hot` 包装了会话、监听、编译、替换）：

```odin
import reload "olib:core/hotreload"

// Startup（host.hot 放在堆上，地址必须稳定）
reload.hot_init(&host.hot, {
	source = "src/game", collections = {"olib=../olib"},   // 游戏 DLL 的包目录，相对 working_directory
	services = &host.services, host_version = HOST_VERSION,
	before_swap = wait_for_gpu, user_data = app,           // 替换前等 GPU 空闲（可选）
})
reload.hot_update(&host.hot, dt)   // UpdateProc：检查编译、必要时替换，再转发游戏的 update
reload.hot_render(&host.hot, dt)   // RenderProc
reload.hot_dispose(&host.hot)      // Shutdown
```

`hot_error(&host.hot)` 返回最近一次失败原因（供 UI 显示），`hot_retry` 重新尝试编译；默认会往终端打印
`LIVE version N` 和编译错误（`quiet = true` 关闭）。

**游戏**（`Game_Hooks`：一个 `State` 加几个回调）：

```odin
State :: struct {
	position: [2]f32,
	trail: [dynamic][2]f32,      // 数组、map、堆上的对象都可以放
	materials: mat.Material_Library,
	renderer: r2d.Render2D,     // 资源字段也可以放，在 start 里重新创建
}

hooks := reload.Game_Hooks(State, Services){
	reset = reset, update = update, render = render,      // 必填
	start = start, stop = stop, drop = drop,              // 可选，不需要就不写
	host_version = HOST_VERSION,
}

@(export)
olib_game_api :: proc "c" (version: u32, size: int, api: ^reload.API) -> bool {
	return reload.simple_api(version, size, api, &hooks)
}
```

| 回调 | 何时调用 |
| --- | --- |
| `reset` | 第一次启动时初始化 State；热重载时不调用 |
| `start` / `stop` | 每次加载 / 卸载一个版本：创建 / 释放这个版本的资源（Render2D、材质库、UI 等）。热重载时旧版本的 `stop` 在新版本 `start` 之后执行 |
| `drop` | 游戏真正结束时调用一次：释放 State 拥有的堆数据。热重载换版本时不调用 |
| `update` / `render` | 每帧调用 |

**State 的交接规则**：热重载时 State 整体交给新版本（按字节搬过去，不复制它指向的内存），所以：

- 可以放：普通数据；用宿主分配器分配的堆数据（动态数组、map、`strings.clone` 的字符串、`new` 的对象，
  回调里的 `context.allocator` 就是宿主的），新旧版本共用同一份，由 `drop` 释放；资源字段在 `start`
  里重新创建（`r2d.init` 会覆盖整个字段），在 `stop` 里释放。
- 不能放：字符串字面量、函数指针、指向 DLL 包级变量或常量的指针。旧 DLL 卸载后它们就失效，新版本再用会崩溃；
  需要字符串就 `strings.clone`，需要回调就存 ID。
- 改了 State 的字段布局（大小不同）时新版本会被拒绝：提高 `state_version` 并选择重开，
  或改用下面的完整接口，自己用 JSON 等格式编码，可以跨字段变化保留局面。

完整可运行的版本是 olib_sample 的 `run.bat hotreload`（宿主约 90 行含窗口样板，游戏约 70 行，
`State` 里放了拖尾数组、材质库和 Render2D）。需要自定义编译命令、`.Migrate` / `.Reset` 策略时，用下面的完整接口。

## 从哪里开始

| 你想要 | 看这里 |
| --- | --- |
| 新建一个带热重载的游戏 | [tools/new-game 模板](../../tools/new-game/README.md)：`odin run tools/new-game -- ../MyGame MyGame`，进入目录运行 `play.bat`。宿主、模块、状态快照、失败提示都已接好 |
| 看最小的可运行示例 | 同级 olib_sample：`run.bat hotreload`，代码在 `src/hotreload/`（宿主 `main.odin` + 游戏 `game/game.odin`） |
| 把热重载接进已有项目 | 上面的"最快接入"；要更多控制看 [宿主接线](#宿主接线) 和 [游戏模块](#游戏模块dll) |
| 排查"为什么没生效 / 为什么崩了" | [必须遵守的规则](#必须遵守的规则)、[能力与边界](#能力与边界) 和 [REFERENCE](REFERENCE.md) |

## 必须遵守的规则

1. **宿主和模块版本一致**：同一版本 Odin、同一架构和编译选项、同一份共享协议源码。
   协议或共享类型变了，升级 `host_version` 并重启宿主。
2. **宿主拥有，模块借用**：`foster.App`、窗口、设备、`Session`、`Watch` 和服务结构（地址须稳定）属于宿主；
   世界、UI/Clay、Render2D、表现缓存、任务属于模块，卸载前必须全部释放。
3. **快照只放自有数据**：数值、稳定 ID、数组和字符串的内容、格式版本。
   不放指针、函数指针、`any/typeid`、分配器、GPU 句柄、UI/Clay 内存。可以用 JSON、存档格式或二进制。
4. **`load` 只建私有对象**：不改宿主场景、不注册回调、不播音效、不写存档；这些放到成功提交后的 `activate`。
5. **切换前不能有旧模块的残留**：旧 DLL 的函数不能还留在调用栈、任务、音频回调、定时器或 App 回调里；
   GPU 工作要等完成（不确定就在重载边界等 GPU idle）。
6. **改宿主、协议或底层依赖要重启**：热重载只替换游戏 DLL，不替换宿主入口、Foster、编译器。

## 能力与边界

| 操作 | 行为 |
| --- | --- |
| 修改玩法、UI 声明、颜色、尺寸、布局 | 编译成功后整模块切换，下一次 render 用新代码 |
| 保留当前局面 | 旧模块保存快照，新模块建立独立世界；动态数组等在模块内部重建 |
| 快照格式不变 | 默认 `.Compatible` 保留状态 |
| 快照格式升级 | 默认拒绝；用 `.Migrate` 把旧版本快照交给新 load，或 `.Reset` 重开 |
| 编译、API、快照或候选初始化失败 | 旧模块继续运行，诊断在 `Watch.diagnostic` / `Session.diagnostic` |
| 编译中继续保存、Ready 后再保存 | 丢弃过期候选，重新编译最新内容 |
| 源码监听 | 后台线程按大小和修改时间增量扫描，只读变化的文件，不占游戏帧 |
| 不想保存即编译、项目很大 | `mode = .Manual`：不扫描源码，`hot_retry` / `watch_retry` 或修改 `trigger_file` 时才编译 |
| Foster / 宿主协议 / 编译器升级 | 重建并重启宿主 |
| Web、发布版本 | 保持静态入口，不接监听器和 DLL 加载 |

当前实际验收平台是 Windows（用 `core:dynlib` / `core:os`）；Linux/macOS 尚未做运行验收。
不隔离游戏崩溃：断言失败、越界、死循环仍会拖垮整个宿主；也不能回滚候选模块私自写到外部的副作用。

## 宿主接线（完整接口）

`Hot` 就是对下面这些调用的封装。`Session / Watch / Services` 地址须稳定（放在宿主堆上），所有接口由宿主同一线程调用，
不要在模块回调里重入 reload/dispose。以下是接线片段，`Services` 是游戏自己定义的宿主服务结构。

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

// UpdateProc 开始，尚未生成本帧 UI、Render2D 记录或渲染队列。
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

宿主的 `StartupProc / UpdateProc / RenderProc / ShutdownProc` 始终指向宿主代码，再向 Session 转发；
宿主仍直接调用 `foster.InitApp / Run / Exit / Dispose`。
Watch 的配置细节、外部构建系统和缓存见 [REFERENCE](REFERENCE.md#watch-的配置要点)。

## 游戏模块（完整接口）

`simple_api` 是对下面协议的封装。DLL 导出一个 `olib_game_api`，把回调填进 `reload.API`：

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

所有回调都是 `proc "c"`，需要 Context 时先写 `context = call.host_context^`（使用宿主分配器和当前帧临时分配器，
不要保存这个指针）。

| 回调 | 契约 |
| --- | --- |
| `load(^Call, Snapshot) -> bool` | 新建私有状态并写 `call.instance`；`version == 0` 表示新局。输入快照只借用到返回，不可持有其切片/字符串。失败时也会调用 `unload` |
| `snapshot_size(^Call) -> int` | 只读地返回编码长度；负数表示失败。默认上限 64 MiB，可在 `init` 配置 |
| `save(^Call, []u8) -> bool` | 把完整自有状态编码到宿主提供的定长缓冲，只读旧世界，不存地址 |
| `activate(^Call)` | 新版本提交后才注册宿主回调或启动任务；不能失败，不替换 instance |
| `update / render(^Call, f64)` | 使用当前 instance；`frame` 是宿主每次调用可选传入的短期数据，不跨帧保存 |
| `unload(^Call)` | 容忍部分初始化；取消交互、注销回调、停止并 join 任务，释放 UI、表现和世界 |

顺序：检查候选 → 旧版保存快照 → 新版 `load` → 旧版 `unload` → 替换 → 新版 `activate`。
新旧私有世界短暂共存，峰值内存要算上两份。DLL 里的 `@(init)` / `@(fini)` 同样不能操作外部状态。
`state_version` 描述快照格式而不是内存布局：只要快照兼容，模块里的结构体加字段、填默认值即可，不必重置游戏。
API 检查只验证版本和必需回调，不会验证游戏代码的 ABI、快照内容或资源所有权。

## 更多

[REFERENCE.md](REFERENCE.md)：Watch 配置、外部构建与缓存、与 UI / Foster / 资源的配合、模板目录和失败提示。

## 验证

```powershell
odin run tools/check -- -only:core/hotreload
odin run tools/check
```

包含无窗口单元测试和构建检查；交互体验见 olib_sample 的 `run.bat hotreload`。
