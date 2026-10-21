# olib 新项目创建提示词

本文件是用 olib 创建新游戏项目的指南。它约定使用 olib 时的工程目录、包划分与依赖方向、默认桌面热重载、kit/ui 界面、Odin 编码风格、中文注释、桌面/Web 发布和验证方式，不依赖其他游戏仓库。这里的游戏目录是推荐模板，olib 本身并不强制应用采用这些目录名。

本文件放在 olib 的 `prompts/` 目录。可以直接让 AI 阅读本文件并附上项目需求，也可以填写下方模板后复制“提示词开始”到“提示词结束”之间的内容。复制到其他位置时，应明确提供 olib 的实际路径；文末链接均相对本文件。

例如：“阅读 olib 的 prompts/new-project.md，按其中约定在同级目录创建 MyGame。玩法是……，第一版需要……。”

## 提示词开始

请直接在指定目录创建一个可编译、可运行、便于继续开发的 Odin 游戏项目，遵守以下约定。先检查工作目录和依赖，再完成最小玩法闭环、UI 和必要验证；不要只给方案或一批无法编译的代码片段。

### 项目需求

```text
项目名称：<填写英文工程名>
创建位置：<填写新项目的绝对路径>
olib 位置：<本文件上一级的 olib 根目录；复制提示词时填写实际路径>
游戏类型与视角：<例如俯视角经营、动作、解谜>
核心玩法：<玩家做什么，如何获得反馈，如何完成一局>
第一版必须完成：<列出 3～5 个可以实际操作和验证的功能>
视觉风格：<填写；未指定时采用简洁的 2D 图形和与世界协调的 HUD>
目标平台：<默认 Windows x64；需要 Web 时明确填写，见“桌面与 Web 发布入口”的限制>
是否需要调试/编辑工具：<默认带可收起的运行时编辑面板；额外场景/内容编辑需求另行说明>
语言：<默认游戏 UI 支持中文和英文，代码标识符用英文，注释用中文>
明确不做的内容：<可留空>
```

如果项目名称、创建位置或核心玩法缺失且无法从对话中确定，集中询问这些必要信息。其余可逆的实现细节自行选择，简要说明假设后继续。已有文件和用户改动应当保留。新游戏默认不生成 smoke/shot 模式或冒烟脚本；其他文档的相关示例不作为新项目的强制接入项。

### 技术栈和依赖

1. 使用 Odin 与 olib。olib 当前以 `dev-2026-07-nightly` 验证；创建前运行 `odin version` 核对本地编译器，版本差异导致编译失败时如实报告，不要改 olib 迁就。
2. olib 以 collection 方式引用：`-collection:olib=<olib 路径>`。游戏自己的源码也作为 collection：`-collection:game=src`，包之间用 `"game:core/data"` 这类路径导入，不用 `../` 相对路径。
3. olib 分三层，按层选用：
   - `olib:foster` —— **唯一运行时**：App 生命周期、窗口、输入、图形、基础类型（`Color`、`Vec2`、`Rect`……）、存储。直接调用，不要再包一层“引擎类”。
   - `olib:kit/*` —— foster 没有的扩展能力：`kit/ui`（clay 布局的游戏 UI）、`kit/asset`（资源管线）、`kit/world`（相机/场景）、`kit/rendering/material`（材质库、材质加载与每实例的值）、`kit/rendering/2d`（Sprite/图集）、`kit/rendering/3d`（3D 机制：Mesh 上传/排序队列/字节码选择/std140/调试线；光照与材质由游戏自己写）、`kit/animation`、`kit/audio`、`kit/storage`（默认跨平台资源根与用户存储）、`kit/app`（`has_arg` 与调试控制台）。
   - `olib:core/*` —— 纯 Odin 数据结构与格式：`core/handle`（代数句柄池）、`core/messaging`（命令队列/广播）、`core/encoding`（JSON/CSV）、`core/tween` 等。
4. 先读 olib 根目录的 `README.md`、`docs/CODE_STYLE.md`，以及要用到的包源码和 README（`kit/ui/README.md`、`core/handle/README.md`、`kit/asset/README.md`、`kit/rendering/3d/README.md`（自写着色器的完整流程）），按真实签名写调用代码；不要凭印象编造 API。可运行示例在与 olib 同级的 olib_sample 仓库（`src/game_ui` 是完整的 kit/ui 用法；`src/forward3d` 是参考前向渲染器，3D 游戏可以把它复制进来按画风改写），只作参考，不是新游戏的依赖。
5. 新游戏默认建在 olib 的同级独立目录。不要因为当前工作目录在 olib 就把游戏业务写进库，也不要复制 olib 源码进游戏。
6. **不得 import `olib:foster/internal/...`**，这是 olib 的硬规则，对游戏同样适用。需要的能力在 foster 公开 API 或 kit 中找；确实缺失时说明缺口，不要绕道内部包。
7. 默认不用 ECS：按数据形状选容器（见 `prompts/dod-guidelines.md` 第 1 节）。网格用扁平数组，没人跨帧引用的批量数据用 `#soa[dynamic]`，只有会被跨帧引用的实体才用 `core/handle` 句柄池 + SoA 行。`core/entities` 存在但不是默认方案。
8. 调试界面需要时可用 `thirdparty/odin-imgui`（含 foster 后端），只用于桌面调试工具，不用于玩家 UI。需要编辑器或开发工具时先读 olib 的 `prompts/editor-guidelines.md`，按统一的会话、输入和编辑事务约定接入；该文档是项目实现约定，不代表库已有编辑器框架。
9. 物理、音频、多线程、自定义 Shader 等按实际需求添加，不因库中存在某个模块就全部接入。
10. 如果依赖缺失，说明缺少的具体路径和受影响的步骤，继续完成不依赖它的工作；不要创建同名空壳冒充真实库，也不要声称已构建成功。
11. **桌面开发版默认支持保留状态的游戏代码、游戏 UI 与编辑器 UI 热重载**，除非用户明确关闭。新建 Windows 项目先用 [tools/new-game](../tools/new-game/README.md) 生成已接通的底座，再实现玩法；不再从示例复制或重新手写宿主接线。先读 `core/hotreload/README.md` 和实际 API。模板已验证 Windows 和 Chromium Web 静态发布；Web 不接热重载/editor，其他桌面平台和新增玩法的 Web 能力仍需单独验证。

### 先生成可运行底座

在 olib 根目录执行（项目名和目录按需求替换）：

```powershell
odin run tools/new-game -- ../MyGame MyGame
cd ../MyGame
.\play.bat
```

目标目录必须不存在；已存在的项目先检查现状，不能用生成器覆盖。生成器自带源码、离线字体及许可，无需 olib_sample。生成后先运行 `odin run tools/check` 和 `play.bat` 确认底座正常，再替换 `core/world.odin`、`core/rules.odin`、`core/ui.odin` 的最小业务。保留宿主、模块适配与静态入口的共享 core 包，按新玩法更新必要的单元测试。

模板是可运行起点，包含可热重载的运行时编辑面板，尚未包含场景文档、具体玩法、本地化系统、资产管线；这些仍按需求和下文约定补齐。运行脚本默认使用生成时的 olib 路径，支持 `OLIB` 覆盖；搬动库目录后同步 OLS 配置。

### 目录结构

先区分库目录和新游戏目录：

```text
<Workspace>/
├─ olib/                         库，不放新游戏业务代码
│  ├─ prompts/                   AI 提示词文档（本文件所在目录）
│  ├─ core/  foster/  kit/  thirdparty/
├─ olib_sample/                  可选，olib 的可运行示例
└─ <ProjectName>/                新建的独立游戏项目
```

新项目默认使用精简模板：业务集中在 `core` 包内按文件区分职责，只为热重载、编辑器隔离和独立入口保留目录。Odin 一个目录就是一个包，包名与目录名一致（入口为 `package main`）。不要为了套用五层架构预建 `def/data/logic/view/session/platform`；功能增长到确实需要独立依赖边界时，再按 dod-guidelines 第 2 节在 `src/core/` 内拆包。旧五层布局的职责对应也见该节，不能把旧示例的顶层业务目录与当前模板混用。

```text
<ProjectName>/
├─ AGENTS.md / README.md / .gitignore / ols.json
├─ play.bat                      开发启动，参数透传
├─ publish.bat                   Windows 发布
├─ publish_web.bat / index.html   Web 静态发布与网页入口
├─ src/                          collection game
│  ├─ core/                      game/editor 共用的业务（package core）
│  │  ├─ world.odin              状态与操作类型、存储生命周期
│  │  ├─ rules.odin              规则与运行时属性校验
│  │  ├─ ui.odin                 UI 与绘制
│  │  ├─ core.odin               实例、更新、快照与恢复
│  │  ├─ core_test.odin          状态单元测试
│  │  ├─ services.odin           共享服务协议、资源与跨平台 storage
│  │  └─ args_native.odin        桌面参数（Web 排除）
│  ├─ core_editor/               可热替换的编辑器实现（package core_editor）
│  │  ├─ editor.odin             开发面板、编辑会话与输入归属
│  │  └─ module.odin             DLL 接入，组合游戏与编辑器快照
│  ├─ editor/                    薄开发入口（package main），常驻
│  │  └─ main.odin               窗口、资源、监听、模块切换与失败提示
│  └─ game/                      Windows/Web 薄发布入口（package main）
├─ assets/fonts/                 离线字体与许可
└─ tools/check/                  单元测试、依赖检查和编译
```

生成后 `src` 只有四个子目录，平时主要修改 `core` 和 `core_editor`。`build/` 由脚本生成并忽略；内容、音频、Shader、文档或独立工具按实际需求增加，不预建空目录。职责与修改入口写在根 README，不额外复制一份目录说明。这里的 core 是项目共享业务（`game:core`），可包含 UI；olib 自身的 `olib:core/*` 仍是纯 Odin 库，两者不是同一个包。collection 名 `game` 指向整个 src，不代表发布入口包。

开发入口 `src/editor` 编译成常驻 EXE，运行时把 `src/core_editor` 及它导入的 core 编译成一个 DLL。游戏代码放 core，编辑器实现放 core_editor，两个入口 editor/game 只负责启动与生命周期；不另建 host、editor/play、src/tools/editor 或根目录宿主。普通玩法和工具 UI 不需要逐函数导出。静态发布入口 `src/game` 只导入 core；仅做 Web 时可省略 editor 与 core_editor，保留 game/core。

`src/core_editor/editor.odin` 提供 F1 收起/打开的编辑面板，游戏与编辑器 UI 一起热重载。DLL 拥有游戏实例、编辑会话、UI 与待处理命令，常驻入口只保留窗口、资源和不透明模块实例。组合快照保留游戏状态、面板开关与待处理命令；UI 对象和瞬时输入重建，按住的鼠标须先松开才允许新操作。监听 core_editor 与 core（含子包）；editor 入口、core/services.odin 的服务协议/资源初始化、core/args_native.odin、olib 或工具链变化需重启。服务协议结构变化还须升级 SERVICES_VERSION。core 和 game 不导入 core_editor 或 editor；任何包都不能导入入口。内容文档、保存和撤销遵循 [编辑工具开发约定](editor-guidelines.md)。

文件装载起步可按文件放在 `core`；需要给独立工具复用时再提取配置和装载包，依赖方向按 dod-guidelines 第 2 节。根目录 `tools/` 保留给无界面的构建期工具；独立交互工具入口需要时放 `src/tools/<name>`。

`ols.json` 至少声明两个 collection，让编辑器能解析导入：

```json
{
	"collections": [
		{ "name": "olib", "path": "../olib" },
		{ "name": "game", "path": "src" }
	]
}
```

把 `build/`、`library/`、`*.exe`、`*.pdb`、`.olib-reload-*`、IDE 缓存和临时文件加入忽略规则。动态库及编译缓存写到 `build/` 或监听器的私有临时目录。资源和预编译 Shader 不能被当作构建缓存删除。

### 生成文件与目录纪律

本节是 olib 本仓库、示例与游戏项目的生成文件规则来源。AI 代理和开发工具产生的、需要留存的
非正式产物统一归档到所属项目根的 `library/`；按需创建固定子目录，不预建空目录。
`library/` 不进入版本控制，也不整体复制到发布包；其中需要发布的派生资源按下文单独挑选。

| 产物 | 固定位置 |
| --- | --- |
| 画面验收截图 | `library/screenshots/` |
| AI 图像生成的候选图、参考图、提示词与交付前压缩包 | `library/imagegen/` |
| 临时验证脚本、报告及一次性诊断日志 | `library/tmp/` |
| 资产导入器的可重建 blob/manifest | `library/assets/`，与截图和候选素材隔离 |
| Shader 热重载等工具缓存 | `library/` 下该工具的固定目录，例如 `library/shader_dev/` |

- 不随任务在项目根新建 `output/`、`screenshots/`、`artifacts/` 或日期、任务名目录。复用固定位置；同一验收场景采用稳定文件名覆盖，仅在确需保留对比时使用明确的变体名。
- 仅在用户要求或画面/输入变化确需验收时生成截图，并查看必要结果。目录、文档和任务配置修改不额外截图，不顺带生成无关尺寸、语言或状态的整套图片；此约定不要求接入 shot 模式或自动交互测试。
- 从发布目录验证时，显式把诊断输出指向项目根的 `library/`，不要因当前工作目录不同在发布包内再生成截图树。项目若有截图入口，应提供明确的输出目录配置，并在 README 写出实际用法。
- `build/` 留给构建、测试和发布产物及已有工具构建日志（例如 `build/hotreload-last-error.txt`）。长期维护的测试与报告仍放项目约定的源码或文档位置，不塞进临时目录。
- 正式采用并被游戏引用的美术资源移入 `assets/`，连同来源或许可维护。预编译 Shader 仍放所属模块的 `shaders/Compiled/`，字体子集及图集保留为正式资源；不能因为它们是生成文件就忽略或清理。
- `library/` 不是可整体删除的纯缓存：候选图、参考图和提示词可能无法精确再生成。资源管线只可按自身生命周期重建 `library/assets/` 等明确属于它的派生目录；发布时只复制所需 blob/manifest 到分发目录的资源位置并配置加载根，不复制截图、候选素材或工具缓存。
- 生命周期例外：无窗口测试在系统私有临时目录自建自清，编译器快照、DLL 影子文件和并发会话使用工具管理的隔离目录，原子保存的临时文件必须位于目标文件同目录。这些不迁进共享目录，也不创建项目根的临时文件夹；清理仅限各自拥有的文件。故障后需留存的诊断副本归入 `library/tmp/`，先确保相关进程已停止。
- 整理已有项目时先检查引用与用途；保留已有素材，不覆盖同名文件，不未经明确要求批量删除。工具约定的默认输出位置与本节不一致时，任务结束前把项目产物归入上述位置并更新引用。

项目 AGENTS.md 和 README 应写明这些输出位置；生成器模板同步包含规则和 `library/` 忽略项，
后续代理无需依赖当前对话才能遵守。

### 桌面与 Web 发布入口

所有脚本从自身所在目录运行（`cd /d "%~dp0"`）。模板自动记录创建时的 olib 路径，允许用环境变量 `OLIB` 覆盖；不要另行硬编码其他开发者的路径。可能含空格的路径加引号。失败返回非零退出码，只有成功后才显示完成消息和产物位置。发布表示生成分发包，不自动上传或部署。

**开发运行 `play.bat`**

```bat
odin build src/editor -collection:olib=..\olib -collection:game=src -debug -out:build\dev\<ProjectName>.exe
```

脚本创建输出目录，构建宿主并运行，将参数透传给游戏（例如 `play.bat vulkan`，或需要时的 `play.bat cli`）。宿主启动后由 Watch 完成首次模块编译、加载及后续自动重载；在入口已成功编译启动的前提下，首次 DLL 编译失败也保留窗口并显示诊断，修复源码后能自动恢复。明确关闭热重载或仅做 Web 时，开发构建改用 `src/game`。

宿主传给 Watch 的参数数组以项目根为工作目录，等价于下面的构建命令；`{output}` 由 Watch 替换为唯一产物路径，不要在脚本中硬编码反复覆盖一个已加载的 DLL：

```text
odin build src/core_editor -build-mode:dll -collection:olib=<olib 路径> -collection:game=src -debug -out:{output}
```

所有构建入口使用相同的 collection、编译器和共享类型相关选项；宿主传入配置后的实际 olib 路径，支持 `OLIB` 覆盖和带空格路径。需要 Shader 后台编译时与游戏编译共用 `core/devbuild` 的进程入口，遵循 hotreload 文档的并发约束。

**桌面发布 `publish.bat`**

- `odin build src/game -collection:olib=..\olib -collection:game=src -o:speed -subsystem:windows -out:build\publish\win-x64\<ProjectName>.exe`。
- 把 SDL3 运行库拷到 exe 旁：`odin root` 输出的目录下 `vendor\sdl3\SDL3.dll`。不要依赖 PATH 上可能更旧的 SDL3.dll。
- 运行时资源：优先 `#load` 编译进 exe（字体、小贴图、默认配置），无需随包分发；需要玩家可改的文件（配置、关卡）拷到 `build\publish\win-x64\assets`，运行时用 `kit/storage` 的 `resources_root_release` 定位。
- 分发的是整个发布目录。README 写明压缩包范围，避免只发 exe 丢掉 SDL3.dll 或资源。
- 发布入口直接调用共享 `core` 包，其可达代码不得包含 Watch、DLL 加载、编译器进程或开发面板；不能只在运行时关闭监听。发布包不依赖 Odin 编译器、游戏源码或开发期游戏 DLL。

**Web 静态发布 `publish_web.bat`（模板默认提供）**

模板已从同一静态入口接通 `js_wasm32`，Web 不编入 editor、core_editor、热重载或 DLL，更新后刷新新开一局。平台差异放现有目录中的 game/main_native.odin 和 core/args_native.odin，不额外创建平台目录。Foster Web 有硬约束，接入前完整阅读 olib 的 `foster/docs/WEB_TARGET_REQUIREMENTS.md` 第 12 节：

- 构建：`odin build src/game -collection:olib=..\olib -collection:game=src -target:js_wasm32 -define:SDL3_WASM_LIB=SDL3 -o:speed -out:build\publish\web\<ProjectName>.wasm`。
- 产物目录：`<ProjectName>.wasm`、`odin.js`（`odin root` 下 `core\sys\wasm\js\odin.js`）、`foster.js`（olib `foster\internal\web\foster.js`）、`index.html`（参照 `foster/tests/webtest/index.html`）。
- **`core:os` 在 js 目标上一 import 就编译失败**。以下 olib 包目前仅限桌面，Web 构建的可达代码里不能出现：`kit/app`、`kit/audio`、`kit/asset`、`kit/rendering/2d` 的 Aseprite 部分、`core/encoding`，以及开发专用的 `core/hotreload` / `core/devbuild`。游戏自己的文件读写收口到成对平台文件（`#+build !js` / `#+build js wasm32, js wasm64p32`）；模板默认通过 `kit/storage` 选择用户根，读写直接使用 Foster 存储容器（Web 上落到 localStorage），不另写浏览器专用的存档路径。
- 新版 Odin 的 SDL 绑定默认链接 env.o；模板用 `-define:SDL3_WASM_LIB=SDL3` 仅保留类型依赖，不能有任何 SDL 函数进入 WASM 导入。tools/check 编译桌面和 Web 并检查实际依赖；浏览器运行仍需验证。
- 资源全部 `#load` 内嵌；字体按文本实际用到的字符集裁剪后内嵌。
- 游戏状态放在独立结构体中，堆分配（在 ShutdownProc 中释放）或使用全局变量，
  再用 `AppSetUserData` 挂到 App，回调用 `AppGetUserDataAs` 取回。
  Web 上 `Run` 会把 App 拷贝到堆上并立即返回，但不会搬移状态，所以状态不能放在 `main` 的栈上，
  也不要内嵌 App；回调使用收到的 `^foster.App`，不要缓存 `Run` 前的 App 指针。
- 发布后检查 wasm 中没有 SDL 导入（`strings <ProjectName>.wasm | findstr SDL3` 应无输出），用 HTTP 预览（`python -m http.server`），不能双击 `index.html` 验证。`publish_web.bat serve` 发布后用 Python 在 http://127.0.0.1:8138/ 启动本地预览，Ctrl+C 停止；普通发布无需 Python。

在 README 中说明以下入口、前置依赖和对应输出：

```powershell
.\play.bat
odin run tools/check
.\publish.bat
.\publish_web.bat
.\publish_web.bat serve
```

### 默认跨平台存储

所有新游戏沿用模板的 `kit/storage` 接入，完整策略见 [存储说明](../kit/storage/README.md)。共享协议与资源函数放在 core/services.odin，由 editor/game 入口调用 resources_init 并持有资源根、用户根及 Foster 容器，通过 `Services.assets` 和 `Services.user_storage` 借给业务，退出时调用 resources_dispose；热重载候选不重新创建或释放入口资源。core 不依赖热重载加载器，业务读写使用跨平台容器，不另造 host 包。

- 使用稳定的 `STORAGE_ID`，不要使用可变窗口标题。桌面开发版和发布版共用系统用户目录，Web 使用当前源下 `/foster/<ID>/` 的 localStorage 虚拟目录。
- 读写直接调用 Foster 的 Storage API；读取用 `ReadAllBytes`，存档、配置和编辑文档保存优先用 `WriteAllBytesAtomic / WriteAllTextAtomic`，检查返回值。普通直接写入仍可用 `WriteAllBytes`。不另做 API 别名或跨平台读写包装；拆出的纯模拟包仍不依赖存储，core 或内容装载层接收容器并负责 IO。平台语义与 Web 外部文件确认见 [存储约定](../kit/storage/README.md)。
- Web 的资源根是虚拟 FS 根，不是站点 URL；未内嵌的资源需要先加载/挂载，不能把 HTTP 路径当成本地文件读取。
- 默认初始化存储不等于自动保存游戏。存档和设置的字段、校验、版本、保存/恢复时机由具体业务实现；处理打开与写入失败，不静默退回工作目录。不要在候选 load 或模块 unload 中写盘，避免失败候选或热切换覆盖存档。

### 默认热重载与业务代码边界

默认同时支持游戏 UI 与编辑器工具 UI 热重载。四目录分别承担游戏实现、编辑器实现、开发入口和发布入口；core_editor 与 core 共用一个热重载 DLL，避免两个 DLL 之间的业务 ABI 和同步切换。

以下机制已由 `tools/new-game` 模板接通，创建者在它之上扩展并维护，普通玩法和 UI 继续写普通 Odin proc。热重载的实际时延是检测、后台编译和切换所需时间，不承诺保存源码后零延迟。

**接入层一次完成**

- `src/editor/main.odin` 直接使用 Foster 生命周期，构建为常驻 EXE；通过 core 的资源函数持有资源、服务、Session、Watch 与最小失败提示，不创建或调用静态游戏实例。监听 `core_editor` 与 `core`，递归覆盖子包。`#load` 文件显式列入监听根或扩展名；入口、core/services.odin、core/args_native.odin、olib 和工具链变化需重启。
- `core_editor/module.odin` 集中导出 `olib_game_api`，校验 API 版本和结构大小，实现 load、save、snapshot_size、unload、update、render；按需增加 activate。每个需要 Context 的 `proc "c"` 回调先恢复 `call.host_context^`。模块组装 core 和编辑器 UI；编辑命令在模块内经 core 规则处理，候选 load 不修改宿主、旧会话或持久存储。
- `core/core.odin` 集中实现实例创建/释放、操作队列、模拟调度和快照恢复，静态入口与 DLL 入口共用。游戏包不依赖 `core/hotreload`、editor 或动态库入口；伤害、收入等规则写在 `core/rules.odin` 或相应功能文件。
- 模块拥有独立的世界、UI/Clay、Batcher、缓存和任务。UI 上下文每次加载重建并重新注册字体；宿主持有的共享字体等资源只借用。失败的候选也能释放部分初始化资源。load 只创建私有候选，外部注册和任务启动放到成功提交后的 activate；unload 注销回调、停止并 join 任务、释放模块资源。
- 宿主在尚未生成新一帧 UI/绘制命令的安全边界应用候选，确保旧模块调用和 GPU 使用结束；需要时等待设备 idle。编译、快照、版本或初始化失败保留旧局面并显示诊断，修复后自动重试，提供手动 retry。不能留下指向旧 DLL 的回调、任务或资源释放函数。
- 沿用 `src/editor/main.odin` 内的常驻失败提示；首次未加载与旧版仍运行分别说明，编译失败和加载拒绝都显示摘要，完整错误写入终端和 `build/hotreload-last-error.txt`。Waiting/Compiling/Ready 不能清除失败提示，只有 `watch_apply == .Success` 才清除。反馈 UI 不属于 DLL、不暂停旧游戏，桌面/Web 静态发布排除它。

**状态集中保存，规则与 UI 无需逐个注册**

- 用一个明确的快照结构/编码入口保存权威世界状态及需要保留的会话状态：进度、实体与稳定身份、随机数进度、计时器、暂停/倍速、相机、选中项和持久 UI 设置。动态数组、map、字符串编码内容，在候选实例中独立分配；不得保存裸指针、proc、`any/typeid`、分配器、GPU 句柄或 Clay 内存，也不能用 `mem.copy(World)` 冒充快照。
- 一次点击产生的待处理命令不得因重载丢失或重复：在快照前的安全更新边界恰好消费一次，或把纯数据命令纳入快照。游戏和编辑器队列都适用；面板开关、选中项等持久会话状态进入编辑器快照。模块内的悬停、按住、焦点、拖动等瞬时交互默认重置，已有按住输入必须等松开再启用。以后接入文档/撤销时，快照须保留文档与历史，并在安全边界完成或取消活动事务；不能靠丢掉会话实现重载。实体句柄需恢复代数及引用一致性，或使用稳定 ID 完成重映射。
- 派生规则、索引和表现缓存由新模块重建，不能用旧快照覆盖新代码默认值或新规则。玩家运行中修改的配置覆盖应显式保存，并按“新默认值 → 内容配置 → 当前覆盖”重新安装、校验与构建派生数据；权威进度继续保留。
- 普通开发只需修改 `core/rules.odin` 中接收状态和 dt 的函数、`core/ui.odin` 中的 UI/绘制声明，`core_editor/editor.odin` 中的面板，以及 `core/world.odin` 中的实例字段。不为每个函数写导出、回调表或热重载分支，不把需保留的进度放进可变包全局变量。新增可序列化字段优先复用集中编码；创建者负责缺省值恢复和往返验证，不要求业务调用点关心 DLL。
- 修改快照结构时检查缺省值、校验及迁移；新增字段不会自动获得正确语义。`state_version` 表示快照格式，默认 `.Compatible`；不兼容时拒绝切换并保留旧版，有已验证迁移才用 `.Migrate`。`.Reset` 仅用于明确的重开操作，不得静默丢失进度。宿主服务或共享 ABI 改动升级 `core.SERVICES_VERSION`（传入 API 的 host_version）并重启。 模板把 `core.STATE_VERSION` 与 `EDITOR_STATE_VERSION` 合成模块版本，任一格式不兼容都必须拒绝切换或显式迁移；不保存 UI 内存。

把上述入口、可热改文件、需要重启的范围和状态扩展步骤写进新项目 README。热重载快照服务于当前进程内切换；磁盘存档、资产热更新、Shader 热重载按需求单独实现，不能宣称已随代码监听自动完成。

### 分层和依赖方向

先在 `core` 内按文件表达状态、规则、绘制和生命周期职责。只有出现实际复用或独立依赖限制时才在 core 内拆子包；不要为几行声明新增目录。默认包边界与扩展后的分层规则统一见 `prompts/dod-guidelines.md` 第 2 节。

- 规则函数显式接收状态、命令和 dt，不读取全局输入或 App；可以直接用 `odin test src/core` 无窗口测试。core 包内的绘制文件可依赖 foster，不等于规则函数应依赖运行窗口。
- 沿用模板的 `tools/check`：检查默认包边界和编译器实际发布依赖，保证 editor/加载器不可达。core 内子包与 vet 包名自动发现，拆出的 def/data/logic 保持纯模拟边界，view 仅可引用 logic/query；新增依赖类别时才扩展检查规则。
- 不为每个功能增加接口、转发包或回调注册表；显式传参即可。

### 状态和规则如何写

下文的 data、logic、view 表示职责：精简模板分别对应 core 内的 world、rules、ui 文件，只有拆包后才成为独立目录。以下为要点；内容目录与能力字段、模拟实例所有权与派生缓存、变化事件、按配置计算期望值等完整约定见 olib 的 `prompts/dod-guidelines.md`，开始写玩法前一并阅读。

- `data` 保存真正的对局进度，例如生命、资源、冷却、任务和已探索区域。允许维护存储一致性，不负责决定攻击目标、收入或放置是否合法。
- `logic` 根据规则直接修改传入的数据；需要维护列、句柄或缓存版本一致性时调用 `data` 的存储操作，不要求为每个字段新增 setter。
- `logic` 的 proc 显式接收状态指针、操作参数和 `dt`，例如 `step(world: ^data.World, dt: f32)`；不读取全局输入、foster 时钟或 App。
- foster 的 `DefaultAppConfig` 默认固定 60 Hz 调用 `UpdateProc`，`app.Time.Delta` 即模拟步长。暂停和倍速由 `core` 决定本次调用几次 `logic`。UI 动画时间与模拟时间按用途区分；固定步长不自动保证确定性，需要重放时还要控制随机种子与迭代顺序。
- kit/ui 每帧在 `RenderProc` 中声明（与 olib_sample 的 game_ui 一致）。控件返回的确认事件写入操作请求队列（可用 `core/messaging` 的 `Command_Queue`），由下一次 `UpdateProc` 交给 `logic`；固定步长下两次渲染之间可能有零次或多次更新，验证一次点击只执行一次。合法性、费用扣除和结果修改集中在 `logic`；禁用按钮只是反馈，不能替代规则校验。
- 先按数据形状选容器：单个值放普通字段，网格用一维数组（下标 `y*w + x`），没人跨帧引用的弹道、粒子、事件用 `#soa[dynamic]` + 交换删除。只有会被跨帧引用的实体才用 `core/handle/array` 的 `Pool` + `distinct ha.Handle`，属性存成 `#soa` 行（槽位对齐起步，热点时换紧凑布局）；跨帧引用只存句柄，使用前检查有效。不要为每个单位创建带 update 回调的结构体。
- 新增实体属性就是在 `#soa` 行结构中加字段，所有列随追加、删除、扩容一起变化；生成时整行赋值，避免旧数据留给复用槽位的新实体，重开时检查释放。
- 配置中的静态类型信息与实例状态分开保存。价格、攻击方式等由目录定义；实例只保存 1 字节类型编号和自身变化的数据。根据能力编写规则，不在多处按具体内容 ID 堆分支；ID 常量放在可选的 `ids` 包，`def / data / logic / view` 的非测试文件不 import 它。
- 数值从已校验的配置快照读取，不在每帧解析 JSON。默认值、全局配置和关卡覆盖的优先级应明确，UI 和规则使用同一份生效数值。
- 空间索引、路径和统计缓存的结构与存储放在 `data`，按模拟实例持有，重建、更新与查询算法放在 `logic`；渲染、图标和地图显示缓存放在 `view`。每个缓存注明输入、失效条件、重建时机和释放责任，不以缓存替代权威状态，存档不必保存可重建的缓存。
- 先保证正确性，再依据测量优化热点。热循环避免重复全表扫描、每帧临时集合和堆分配；并行仅在规模需要时引入（`core:thread.Pool` + `core:sync.Wait_Group`），工作线程只写各自结果区间，由主线程有序提交。

### 内存与资源所有权

Odin 没有 GC，所有权必须显式：

- 每种资源配一对 `xxx_init` / `xxx_destroy`（或 `_dispose`），在注释里写明谁分配、谁释放、生命周期多长。foster 资源（Texture、Batcher、Font、Target……）同样由明确的所有者在 `ShutdownProc` 中释放。
- 长期数据用 `context.allocator`；一帧内用完的字符串、临时数组用 `context.temp_allocator`。foster 在每帧末尾（`Tick` 结束时，`RenderProc` 与 `GraphicsDeviceEndFrame` 之后）清空临时分配器；临时分配只在本帧有效，不要跨帧持有。`StartupProc` 中的临时分配在第一帧结束时失效。
- 返回切片或字符串的 proc 在签名或注释中说明由谁 `delete`；接收 `allocator := context.allocator` 参数的 proc 按调用方传入的分配器分配。
- 指针稳定性：`core/handle/array` 的 `get` 返回的指针在 `add` / `remove` 后可能失效，不要跨越结构变更持有；需要稳定地址时选 `core/handle/growing` 或 `virtual`（见 `core/handle/README.md`）。`kit/ui` 的 `UI_Context` 必须地址稳定、不可按值复制。
- 开发构建用 `core:mem` 的 `Tracking_Allocator` 检查泄漏（olib `core/debug` 有现成包装），退出时打印未释放的分配。

### UI 用什么以及如何接入

玩家 UI 使用 **`kit/ui`**：clay 负责布局，kit/ui 提供控件、交互和 foster Batcher 后端。接入前完整阅读 olib 的 `kit/ui/README.md`，并对照 olib_sample 的 `src/game_ui`。

**先查 kit/ui 是否已有对应控件，再决定是否自定义。** 自定义控件用 `ui_interact` 复用悬停/按下/焦点/禁用状态，不从零重写交互。

| 界面需求 | 优先查看 |
| --- | --- |
| 按钮与开关 | `ui_button` / `ui_button_ex`、`ui_toggle`、`ui_image_button` |
| 数值 | `ui_slider`、`ui_progress_bar` |
| 文本 | `ui_heading`、`ui_label`、`ui_label_dim`、`ui_label_ex` |
| 布局与容器 | `ui_row_decl`、`ui_column_decl`、`ui_panel_decl`、`ui_scroll_decl`、`ui_modal_decl` |
| 图片与皮肤 | `ui_image`、`ui_image_decl`、`ui_nine_slice_decl` |

kit/ui 目前**没有**文本输入/IME、Dropdown、富文本、拖放和列表虚拟化（见 olib `docs/ROADMAP.md`）。第一版需要这些时，先评估能否用现有控件组合替代；调试工具可改用 odin-imgui。不要假定它们存在。

帧流程（在 `RenderProc` 中）：设置 viewport 与指针 → `ui_set_navigation` → `ui_begin` → 声明 UI → 绘制世界 → `ui_draw` 叠加 UI → `ui_input_capture` 决定本帧鼠标/键盘是否还交给世界。读取 capture 之后再处理世界点击，避免穿透。

- 字体：统一使用离线生成的真正 MSDF 图集（PNG＋JSON），直接用 `foster.MsdfFontLoadFiles` 加载并以 `.MSDF` 注册；生成时固定 `-type msdf -yorigin top`，`-size 48 -pxrange 8` 是起点，完整命令见 `tools/fonts/README.md`。不再使用已删除的 `ui_font_bake_sdf`，也不能把灰度距离复制到 RGB 冒充 MSDF。字符集必须包含本地化和动态文本用到的全部字符，中文需显式纳入；增加字符后重新生成并打包资产。MSDF 不保证任意小字号都清晰，完整采样与验收步骤见 `kit/ui/README.md` 的“最终像素采样与清晰度验收”。
- 控件 ID 全局唯一且跨帧稳定；动态列表用内容 ID，不用会随排序变化的位置。
- 主题集中在 `view` 的 theme 文件中，从 `ui.UI_THEME_DARK` 复制后调整；不要在每个控件里分别写颜色和尺寸。
- 缩放：`ui_set_viewport(&ctx, rect, scale)` 的矩形与指针都是渲染目标像素，布局尺寸是逻辑像素。绘制、点击判定、相机预留区域和测试点击位置使用同一套布局结果。
- 最终像素：低分辨率世界先缩放/合成到窗口实际 drawable 像素，再绘制 UI；或者让包含 UI 的离屏目标本身等于最终像素尺寸，再 1:1 输出。**禁止先把 UI 画入固定低分辨率场景纹理，再整体缩放窗口**。SDF 解码后也是像素图，后续缩放仍会发虚。高 DPI 下核对实际像素与逻辑窗口尺寸，不能只改布局 scale。
- 声明函数返回 `clay.ElementDeclaration`，可以修改后再传给 `clay.UI()`；不要把 `clay.UI()` 包进普通函数返回，它依赖 deferred 调用的作用域关闭元素。

在 `view` 中拆出以下职责，名称可随项目调整：

| 文件 | 职责 |
| --- | --- |
| `theme.odin` | UI_Theme 配置，以及自定义 HUD 共用的颜色与字号 |
| `hud_layout.odin` | 布局位置、尺寸、锚点和窄屏策略 |
| `hud.odin` | 对局信息、交互入口、悬停提示 |
| `menu.odin` | 主菜单、暂停、设置和结算 |
| `ui_art.odin` | 需要时生成或缓存图标与柔边纹理 |

不要为每帧重新加载字体或生成相同纹理。

### UI 视觉和文字约定

1. 对局 HUD 以世界画面为主，常驻内容保持少量数字、图标和短句。详细解释放入悬停提示或按需展开区域；文字在复杂背景上用投影和柔和底衬保证可读。
2. 控件图标与游戏美术一致。主题未指定时采用简洁、克制的表现；颜色、按钮形状和装饰根据新游戏题材确定。
3. 对局 HUD、模态菜单和调试工具的需求不同，设置和结算界面允许使用清晰的面板、边框和滚动区域。
4. kit/ui 支持统一圆角、矩形裁剪、九宫格和位图/MSDF 字体；**不支持**渐变画刷、阴影和圆角遮罩。柔光、渐变和阴影用预先烘焙的纹理加 tint 实现。贴图上传前转为预乘 alpha（`ImagePremultiply`）。
5. 字体是游戏资源，放在 `assets/fonts` 并保留许可，不假定 olib 提供游戏字体。中文字体必须包含所需字形。
6. 玩家可见文字从 `assets/locale/zh.json` 和 `en.json` 按键读取，使用完整句子和格式占位符；不要在代码中拼接翻译片段。
7. 按本次 UI 改动检查相关窗口、缩放、长文本与控件状态；首次接入或修改全局布局/字体采样时覆盖默认窗口、窄窗口、非整数缩放和中英文。英文变长时应换行、适配或调整布局。截图只保存必要场景，遵循“生成文件与目录纪律”，不每次生成整套图片。
8. 文字验收必须读取 **UI 绘制之后的最终输出**，PNG 尺寸与实际渲染像素一致；不能只截固定 720p 中间纹理。检查默认窗口、窄窗口、非整数缩放（如 125%）、运行中 resize 和中英文，记录实际像素及 UI scale；先 1:1 看可读性，再放大检查笔画。发虚时按“最终缩放链路 → 字形实际像素大小/像素对齐 → 图集与 SDF 参数 → 字体字重”排查，不能只加粗或增大图集就宣称修复。
9. 字重、字号和采样分别检查。使用可变字体时核对实际 `wght`，需要固定字重时先实例化再裁剪，不假定默认轴值为 Regular。常规中文正文优先保证约 14～16 个实际像素的可读性，窄窗口不能无条件缩小所有文字；更小字号必须实测，不以改字重代替采样修复。
10. 3D 画面单独验收：记录场景渲染目标尺寸及抗锯齿方案。固定 1280×720 场景放大到大窗口会放大锯齿；没有抗锯齿时，斜墙沿、细线与小物体容易出现台阶或闪烁。按画风和性能选择原生分辨率、MSAA 或后处理抗锯齿，并检查相机移动时的细线稳定性；不要把 UI 的线性采样当作 3D 抗锯齿。后处理放在 UI 叠加前，避免再次模糊文字。

### Odin 编码风格

遵循 olib 的 `docs/CODE_STYLE.md`，要点：

- Tab 缩进（宽 4），行宽约 100 字符。函数体、分支、struct 字段一律多行；只允许 `if cond do return` 这类 Odin 惯用单语句。
- 命名：类型用 `Ada_Case`（`Unit_Columns`、`Building_Rules`）；proc、变量、字段用 `snake_case`；常量用 `SCREAMING_SNAKE_CASE`；包名小写、与目录名一致。包内 proc 按主题加前缀（`unit_spawn`、`income_step`），与 olib 的 `ui_button`、`cli_open` 风格一致。
- imports 按库分组、组内字母序：`base:` < `core:` < `olib:` < `game:`，别名紧跟（`import ha "olib:core/handle/array"`）。
- 用明确的职责名称（`combat`、`unit_columns`、`world_renderer`），不建立无边界的 `utils`、`common`、`manager` 大杂烩包。
- 用 `distinct` 区分不同含义的整数和句柄（`Unit_Handle :: distinct ha.Handle`），用 `enum` + enumerated array（`[Resource_Kind]int`）表达固定映射，用 `bit_set` 表达标志集合。
- 错误处理用多返回值：`(value, ok: bool)` 或 `(value, err: Error_Enum)`，配合 `or_return` / `or_else`。配置和文件属于输入边界，错误要能定位到具体文件和字段。业务拒绝（不能放置、金币不足）返回明确的结果枚举，不用 `panic`；`assert` 只用于程序员错误。
- proc 字面量没有闭包：回调需要状态时用 `proc(..., userdata: rawptr)` + userdata（参考 `core/messaging` 的 `queue_drain`）。
- 优先用早返回减少嵌套；按业务动作拆 proc，保持更新顺序和副作用清楚。不要把复杂状态变更压成难以调试的一行。
- `using` 只用于确实需要字段提升的嵌入，不为省字数滥用。包内辅助 proc 用 `@(private)` 或 `@(private="file")`。

### 中文注释怎么写

注释帮助下一位开发者理解职责、约束和原因。不要逐行翻译代码，不需要给每个自解释的字段和局部变量补注释。

- **注释块格式遵循 olib `docs/CODE_STYLE.md` 第 2～5 节**（该文件开头写明这几节适用于游戏项目）。要点：
  - **包文档**写在包主文件的 `package` 上方，说明本包职责和不负责什么；其余文件在 `package` 之后用普通注释写**文件头**，说明本文件职责。
  - **多主题文件**在文件头之后列出分区导航，正文用 80 字符宽的单线框分区，顺序与导航一致；大模块用双线框。只有一个主题的小文件只写文件头。

    ```odin
    package data

    // 单位存储（紧凑布局）：所有单位行连续存放，句柄经 index 映射到行号。
    // 不变式：rows 的 0..<len 全部存活。所有权：由 World 持有，units_destroy 释放。
    //
    // 分区：
    //   类型 —— Unit / Units
    //   生命周期 —— unit_spawn / unit_remove / units_destroy
    //   查询 —— unit_row

    // ------------------------------------------------------------------------------
    // 单位 / 类型 — 行结构与句柄映射
    // ------------------------------------------------------------------------------
    ```

  - 函数内部的局部阶段用单行短注释（`// ---- 第一遍：收集 ----`），不加线框；分区标题用真实语义，不写“其他”“杂项”。
- **类型和关键 proc** 在声明上方用 `//` 说明负责什么以及必要的边界；参数有单位、范围、坐标空间或所有权约定时写清楚，返回值有特殊含义时说明。
- **状态字段**重点解释单位、哨兵值、有效期和槽位对应关系，例如“秒”“世界格坐标”“无目标时为零值句柄”。
- **实现内部**用 `//` 解释“为什么这样做”：算法前提、排序要求、缓存失效、线程边界、平台限制。修改行为时同步更新注释。

下面是业务增长后拆包的可选示例，用来说明注释与职责，不是创建目录清单。新项目先在 core 包内按文件写，不要求包含周期收入玩法。

```odin
// 文件：src/core/data/income.odin
package data

// 收入存储：周期收入的余额与计时进度；推进与结算规则在 logic/economy。

// 一个模拟实例的收入状态，随 World 创建与重开。
Income :: struct {
	coins:           int,
	// 距上次结算累计的模拟秒数；暂停不增加，重开时清零。
	elapsed_seconds: f32,
}

World :: struct {
	income: Income,
}
```

```odin
// 文件：src/core/logic/economy/economy.odin
// economy —— 按显式传入的模拟时间结算收入，不读取窗口或 UI 状态。
package economy

import "game:core/data"

// 推进计时并结算完整周期，剩余时间留待下次调用。
// dt：模拟秒数，调用方保证有限且非负；interval_seconds 来自已校验配置，必须大于零。
income_step :: proc(income: ^data.Income, dt: f32, interval_seconds: f32, coins_per_cycle: int) {
	income.elapsed_seconds += dt

	// 一次推进可能跨过多个周期；逐次扣除保留余量，避免漏结算或计时漂移。
	for income.elapsed_seconds >= interval_seconds {
		income.elapsed_seconds -= interval_seconds
		income.coins += coins_per_cycle
	}
}
```

```odin
// 文件：src/core/logic/economy/economy_test.odin
#+test
package economy

import "core:testing"

import "game:core/data"

@(test)
income_step_settles_multiple_cycles :: proc(t: ^testing.T) {
	income: data.Income
	income_step(&income, 5, 2, 3)
	testing.expect_value(t, income.coins, 2 * 3)
	testing.expect_value(t, income.elapsed_seconds, 1)
}
```

表现资源骨架（`src/core/view/view.odin`）。实际绘制时由 `core` 传入所需模拟数据或查询结果，以下只演示资源生命周期：

```odin
// 文件：src/core/view/view.odin
package view

import foster "olib:foster"
import mat "olib:kit/rendering/material"
import r2d "olib:kit/rendering/2d"
import ui "olib:kit/ui"

View :: struct {
	materials: mat.Material_Library,
	renderer: r2d.Render2D,
	ui_ctx: ui.UI_Context, // 初始化后地址保持稳定。
}

view_init :: proc(v: ^View, app: ^foster.App) -> string {
	v.materials.device = &app.GraphicsDevice
	if reason := r2d.init(&v.renderer, &v.materials); reason != "" do return reason
	ui.ui_init(&v.ui_ctx, 1280, 720)
	return ""
}

view_draw :: proc(v: ^View, app: ^foster.App) -> mat.Draw_Error {
	target := foster.DrawableTargetFromWindow(&app.Window)
	foster.GraphicsDeviceClear(&app.GraphicsDevice, target, {24, 28, 36, 255})
	// 记录世界，再按 kit/ui README 声明 UI，用 ui_draw 叠加。
	return r2d.submit(&v.renderer, {target = target})
}

view_destroy :: proc(v: ^View) {
	ui.ui_dispose(&v.ui_ctx)
	r2d.dispose(&v.renderer)
	mat.material_library_dispose(&v.materials)
}

```

入口代码以可运行模板为准，不再另放一份把业务组装写进 game 的 App 骨架：

- [`src/core/core.odin`](../tools/new-game/template/src/core/core.odin.in) 持有游戏实例，集中创建/释放、输入转命令、更新、绘制与快照。拆包后仍由这里调用 core 内的 data/logic/view。
- [`src/game/main.odin`](../tools/new-game/template/src/game/main.odin.in) 是 Windows/Web 发布入口，只管理 App、共享资源和对 core 的生命周期转发；不直接更新某个玩法系统，也不复制 World 或 UI 的组装逻辑。
- [`src/editor/main.odin`](../tools/new-game/template/src/editor/main.odin.in) 是常驻开发入口；[`core_editor/module.odin`](../tools/new-game/template/src/core_editor/module.odin.in) 在 DLL 内组装 core 与编辑面板。修改游戏规则、游戏 UI 或编辑器 UI 都可保留状态热重载；共享服务在 [`core/services.odin`](../tools/new-game/template/src/core/services.odin.in)，无需独立 host 包。

Web 的 Run 返回后仍需要游戏状态；沿用模板的堆分配与 shutdown 释放路径，不能在 main 返回时释放。普通玩法改 core，编辑工具改 editor，不能分别在两个入口实现同一套业务。

其他适合写注释的地方：

```odin
// 建筑位置改变会使空间索引失效，必须经 building_set_position 更新版本号。
// 工作线程只记录候选结果；实体删除和伤害结算在主线程按槽位顺序提交。
// 返回的切片由 context.temp_allocator 分配，本帧结束前有效。
```

避免 `// 增加计时器`、`// 遍历列表` 这类复述代码的注释。临时方案需要写明原因和移除条件；不要留下没有范围和行动说明的 `TODO: 优化`。设计推导、长篇流程和使用教程放在 `docs`，源码只保留就地需要的信息。

### 创建与验证流程

1. 阅读目标目录已有的 `AGENTS.md`、README 和脚本，检查 Git 状态及 olib 位置。先读 olib 的 `README.md`、`docs/CODE_STYLE.md`、`kit/ui/README.md` 和要用的包源码；遇到 API 不确定时先查源码。
2. 默认 Windows 项目运行 `tools/new-game` 生成底座，运行自带检查并启动游戏确认窗口、中文文本、按钮及热重载正常，再扩展 core 内的功能文件。不要重新从示例复制接线。明确关闭热重载或仅做 Web 时使用静态入口，适配平台代码，跳过 DLL 相关步骤并在交付中说明。
3. 完成一个贯穿各层的功能：输入 → 操作请求 → `logic` 校验与状态变更 → 画面反馈。再补完需求中约定的第一版玩法闭环和重开。
4. 需要调试/编辑工具时，按 `prompts/editor-guidelines.md` 在 `src/editor/` 集中实现，入口 main.odin 与编辑器实现同属 package main；禁止再生成 src/tools/editor 或第二套编辑器入口。真正独立的其他工具进程才使用 src/tools/<name>。按实际能力验收事务、取消、撤销重做、输入捕获和保存；发布入口 src/game 不能依赖 editor 或开发加载器。
5. 目标平台包含 Web 时，按“桌面与 Web 发布入口”的约束拆出平台文件，核对资源内嵌、用户存储和 HTTP 预览，不直接复制桌面文件系统假设。
6. 沿用并按需求扩展 `publish.bat` 与 `publish_web.bat`，验证实际产物；不能以开发构建能启动代替发布包可运行。
7. 为 `core` 中关键状态与规则及实际拆出的包写 `*_test.odin`（`#+test` + `@(test)`），用 `odin test` 无窗口运行；画面与输入直接运行游戏检查，不默认生成自动点击、改源码或截图的冒烟脚本。
8. 编写 `tools/check`（Odin package main，只依赖 `core:*`，用 `odin run tools/check` 运行，跨平台）：自动发现并运行所有含 `@(test)` 的包、运行层间依赖检查、编译桌面静态游戏、Web WASM、开发宿主和 Play 动态库；任何一项失败返回非零退出码（可参考 olib 根目录的 `tools/check`）。状态单元测试覆盖快照往返和版本拒绝，不默认接入运行真实游戏或 DLL 的冒烟套件。
9. 完成根 README 中的职责说明和简短 AGENTS.md。README 写明脚本用法、输出目录及依赖；新文档加入 `docs/README.md`，说明真实实现与尚未实现的内容。AGENTS.md 写明编码风格与注释遵循 olib 的 `docs/CODE_STYLE.md` 第 2～5 节，数据布局与分层遵循 olib 的 `prompts/dod-guidelines.md`（写出 olib 的相对路径），并写入计划归档规则：多步改动计划放 `docs/plans/`，完成并验收后由执行者 `git mv` 到 `docs/plans/archive/`、在标题下写完成日期、commit 范围与偏离，单独提交（规则原文见 olib 的 `docs/plans/README.md`）。

项目 AGENTS.md 另写明：“新增或修改编辑器、开发面板和交互工具前，阅读并遵循 olib 的 `prompts/editor-guidelines.md`。”同样写出 olib 的实际相对路径，使后续新增工具能找到约定；不复制维护另一份事务规则。

项目 AGENTS.md 同时写明：“桌面开发默认保留状态热重载；接入与状态迁移遵循 olib 的 `prompts/new-project.md` 热重载章节及 `core/hotreload/README.md`。玩法与 UI 留在可重载模块，新增持久状态同步检查快照和缺省值/迁移，发布与 Web 不依赖开发加载器。”使用实际相对路径，并列出本项目真实的接入文件和检查命令。

至少验证以下内容：

- 构建成功，游戏能够启动，默认场景可以操作并重开。
- 在同一宿主进程中实际保存 UI 源码和玩法源码，看到新布局与新规则生效，验证进度、实体、暂停和已声明保留的会话状态连续。注入一次编译错误，确认旧版继续运行，修复后自动恢复；重复重载无泄漏，resize/DPI 后点击正确。按需手动检查即可，不为此给游戏新增测试模式或自动修改源码的逻辑。
- 规则函数可无窗口测试，覆盖正常路径及关键拒绝条件；涉及缓存或句柄时验证失效和复用。
- 依赖检查覆盖 dod-guidelines 第 2 节的精简布局边界、发布隔离及禁止导入 `olib:foster/internal`；实际在 core 内拆包后由模板自动应用对应子包规则，不为检查而创建空包。
- 有编辑工具时，同时检查 dod-guidelines 第 2 节的编辑器依赖边界、发布隔离，并按 editor-guidelines 第 9 节验收已实现的工具；不以 gizmo 能绘制或编辑器能编译代替完整交互验收。
- 游戏用 `-vet` 编译通过，检查游戏及其可达依赖；olib 的 `tools/check` 已对所有第一方包启用 vet。
- UI 的文字、按钮和输入命中正确，点击不会穿透；文字在各缩放下锐利，窗口缩放和语言切换不会导致明显溢出。
- 配置出错能定位原因；涉及保存时，写入和重新读取的内容一致。
- 开发构建用 Tracking_Allocator 运行一局并退出，没有未释放的分配。
- 桌面发布包可从发布目录启动，SDL3.dll 和资源齐全；Web 包无 SDL 导入并可通过本地 HTTP 打开完成基本交互。环境缺失的发布模式如实标为未验证。

仅运行已创建且与本次改动相关的检查。画面检查需要真实图形环境，保存截图后实际查看；不能用“构建成功”代替视觉验收。性能测试使用 `-o:speed`，并报告场景规模和测量条件。

完成后从新仓库根目录运行，例如：

```powershell
.\play.bat
odin run tools/check
odin test src/core -collection:olib=..\olib -collection:game=src
```

上面的占位名称需要替换为实际项目。不要报告不存在的命令，也不要把 olib 或 olib_sample 的测试和示例当作新游戏已经实现的功能和检查。

### 最终交付

交付可运行的项目文件及对应平台的发布脚本，并简要说明：实现了哪些玩法、代码主要放在哪些包、如何启动和发布、产物保存在哪里、实际执行了哪些验证、还有哪些明确限制。没有运行的检查或缺少环境的步骤应如实列出。

遇到实现失败时修复到可验证状态；无法完成的部分给出具体原因。不要把空 proc、固定假数据或尚未连接的按钮描述为已经完成的功能。

## 提示词结束

## olib 内的参考入口

这些链接均可从本文件直接打开。游戏的目录、命名和注释规则是新项目约定，不要求修改 olib 历史代码或第三方源码以统一格式。

| 主题 | 库内入口 |
| --- | --- |
| 仓库结构、使用方式与一键验证 | [README](../README.md)、[tools/check](../tools/check/main.odin) |
| 编码规范与 foster/kit 边界 | [CODE_STYLE.md](../docs/CODE_STYLE.md) |
| 已有能力与后续计划 | [ROADMAP.md](../docs/ROADMAP.md) |
| 运行时（App、窗口、输入、图形、存储） | [foster README](../foster/README.md)、[移植映射与 API 差异](../foster/docs/PORTING_MAP.md) |
| Web 目标的约束与发布 | [WEB_TARGET_REQUIREMENTS.md](../foster/docs/WEB_TARGET_REQUIREMENTS.md)、[webtest 示例](../foster/tests/webtest/) |
| 游戏 UI | [kit/ui README](../kit/ui/README.md) |
| 资源管线 | [kit/asset README](../kit/asset/README.md) |
| 实体基础存储与句柄 | [core/handle README](../core/handle/README.md)、[array 实现](../core/handle/array/) |
| 资源根与存档路径 | [kit/storage](../kit/storage/README.md) |
| 调试控制台与命令行参数 | [kit/app](../kit/app/cli_console.odin) |
| 命令队列与广播 | [core/messaging](../core/messaging/messaging.odin) |
| 配置读写 | [core/encoding](../core/encoding/) |
| 面向数据的开发约定 | [dod-guidelines.md](dod-guidelines.md) |
| 编辑工具开发约定 | [editor-guidelines.md](editor-guidelines.md) |
| 桌面开发默认的游戏代码与 UI 热重载 | [core/hotreload/README.md](../core/hotreload/README.md) |
| 可直接生成的新游戏模板 | [tools/new-game](../tools/new-game/README.md) |

可运行示例位于独立的 olib_sample 仓库，默认与 olib 同级（`run.bat <示例名>`）。它们用于参考库 API；新项目的业务、资源和验证应保存在新游戏自己的仓库中。
