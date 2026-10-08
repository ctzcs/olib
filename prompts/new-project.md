# olib 新项目创建提示词

本文件是用 olib 创建新游戏项目的指南。它约定使用 olib 时的工程目录、包划分与依赖方向、kit/ui 界面、Odin 编码风格、中文注释、桌面/Web 发布和验证方式，不依赖其他游戏仓库。这里的游戏目录是推荐模板，olib 本身并不强制应用采用这些目录名。

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
是否需要调试/编辑工具：<默认暂不需要；需要时说明编辑哪些内容>
语言：<默认游戏 UI 支持中文和英文，代码标识符用英文，注释用中文>
明确不做的内容：<可留空>
```

如果项目名称、创建位置或核心玩法缺失且无法从对话中确定，集中询问这些必要信息。其余可逆的实现细节自行选择，简要说明假设后继续。已有文件和用户改动应当保留。

### 技术栈和依赖

1. 使用 Odin 与 olib。olib 当前以 `dev-2026-07-nightly` 验证；创建前运行 `odin version` 核对本地编译器，版本差异导致编译失败时如实报告，不要改 olib 迁就。
2. olib 以 collection 方式引用：`-collection:olib=<olib 路径>`。游戏自己的源码也作为 collection：`-collection:game=src`，包之间用 `"game:state"` 这类路径导入，不用 `../` 相对路径。
3. olib 分三层，按层选用：
   - `olib:foster` —— **唯一运行时**：App 生命周期、窗口、输入、图形、基础类型（`Color`、`Vec2`、`Rect`……）、存储。直接调用，不要再包一层“引擎类”。
   - `olib:kit/*` —— foster 没有的扩展能力：`kit/ui`（clay 布局的游戏 UI）、`kit/asset`（资源管线）、`kit/world`（相机/场景）、`kit/rendering`（Sprite/图集）、`kit/rendering3d`、`kit/animation`、`kit/audio`、`kit/storage`（资源根与存档路径）、`kit/app`（`has_arg` 与调试控制台）。
   - `olib:core/*` —— 纯 Odin 数据结构与格式：`core/handle`（代数句柄池）、`core/messaging`（命令队列/广播）、`core/encoding`（JSON/CSV）、`core/tween` 等。
4. 先读 olib 根目录的 `README.md`、`docs/CODE_STYLE.md`，以及要用到的包源码和 README（`kit/ui/README.md`、`core/handle/README.md`、`kit/asset/README.md`），按真实签名写调用代码；不要凭印象编造 API。可运行示例在与 olib 同级的 OFoster_Sample 仓库（`src/game_ui` 是完整的 kit/ui 用法），只作参考，不是新游戏的依赖。
5. 新游戏默认建在 olib 的同级独立目录。不要因为当前工作目录在 olib 就把游戏业务写进库，也不要复制 olib 源码进游戏。
6. **不得 import `olib:foster/internal/...`**，这是 olib 的硬规则，对游戏同样适用。需要的能力在 foster 公开 API 或 kit 中找；确实缺失时说明缺口，不要绕道内部包。
7. 默认不用 ECS：大量同类实体用 `core/handle` 句柄池 + 游戏自己的 SoA 属性列（见 `prompts/dod-guidelines.md`）。`core/entities` 存在但不是默认方案。
8. 调试界面需要时可用 `thirdparty/odin-imgui`（含 foster 后端），只用于桌面调试工具，不用于玩家 UI。
9. 物理、音频、多线程、自定义 Shader 等按实际需求添加，不因库中存在某个模块就全部接入。
10. 如果依赖缺失，说明缺少的具体路径和受影响的步骤，继续完成不依赖它的工作；不要创建同名空壳冒充真实库，也不要声称已构建成功。

### 目录结构

先区分库目录和新游戏目录：

```text
<Workspace>/
├─ olib/                         库，不放新游戏业务代码
│  ├─ prompts/                   AI 提示词文档（本文件所在目录）
│  ├─ core/  foster/  kit/  thirdparty/
├─ OFoster_Sample/               可选，olib 的可运行示例
└─ <ProjectName>/                新建的独立游戏项目
```

Odin 一个目录就是一个包，包名与目录名一致。采用以下结构；`tools/`、`shaders/`、`publish_web.bat` 和各层子包按功能需要创建，不预先堆放空包或占位实现。

```text
<ProjectName>/
├─ AGENTS.md                     简短、可执行的项目开发约定
├─ README.md                     启动、操作、依赖与开发入口
├─ .gitignore
├─ ols.json                      OLS 语言服务器配置（olib 与 game 两个 collection）
├─ play.bat                      构建并运行开发版（参数透传给游戏）
├─ check.ps1                     全部测试 + 层间依赖检查 + 编译
├─ publish.bat                   Windows Release 发布入口
├─ publish_web.bat               可选，Web 发布入口，支持 serve
├─ src/                          collection `game`
│  ├─ authoring/                 package authoring：配置类型、默认值、校验、JSON 读写、版本迁移
│  ├─ defs/                      package defs：枚举、固定映射（enumerated array）、共享 distinct 类型、操作请求类型
│  ├─ state/                     package state：本局权威数据——句柄池、SoA 列、对局状态、版本号
│  ├─ logic/
│  │  ├─ <feature>/              每个玩法模块一个包，按实际玩法拆分
│  │  └─ queries/                可重建的查询索引与算法缓存
│  ├─ view/                      package view：UI、世界绘制、音频播放、显示缓存（可按需拆 view/ui 等子包）
│  └─ game/                      package main：App 回调、输入映射、固定步调度、系统执行顺序、诊断命令
├─ assets/
│  ├─ balance/                   数值与内容目录 JSON
│  ├─ worlds/                    场景或关卡文件
│  ├─ locale/                    zh.json 和 en.json
│  ├─ fonts/                     字体及许可文件
│  ├─ textures/                  按需添加贴图
│  └─ audio/                     按需添加音频
├─ shaders/                      可选，Shader 源码
│  └─ compiled/                  运行所需的预编译产物（随仓库提交，`#load` 嵌入）
├─ tools/                        构建、资源处理和检查脚本（如 check_layers.ps1）
├─ docs/
│  ├─ README.md                  文档索引
│  ├─ gameplay/  design/  tech/  records/  archive/
└─ build/                        全部可再生成产物（忽略）
   ├─ dev/                       开发构建
   ├─ test/                      测试可执行文件
   ├─ shots/                     截图与冒烟输出
   └─ publish/
      ├─ win-x64/                桌面可分发目录
      └─ web/                    Web 可分发目录
```

`<feature>` 等名称是模板，需要替换成准确的职责名称；玩法子包按新项目的实际需求建立，不预设塔防、经营、战斗或关卡编辑等特定玩法。

`ols.json` 至少声明两个 collection，让编辑器能解析导入：

```json
{
	"collections": [
		{ "name": "olib", "path": "../olib" },
		{ "name": "game", "path": "src" }
	]
}
```

把 `build/`、`*.exe`、`*.pdb`、IDE 缓存和临时文件加入忽略规则。资源和预编译 Shader 不能被当作构建缓存删除。

### 桌面与 Web 发布入口

所有脚本从自身所在目录运行（`cd /d "%~dp0"`），不写死开发者的绝对路径；olib 位置默认 `..\olib`，可用环境变量 `OLIB` 覆盖。可能含空格的路径加引号。失败返回非零退出码，只有成功后才显示完成消息和产物位置。发布表示生成分发包，不自动上传或部署。

**开发运行 `play.bat`**

```bat
odin build src/game -collection:olib=..\olib -collection:game=src -debug -out:build\dev\<ProjectName>.exe
```

示例名之后的参数透传给游戏（`play.bat shot`、`play.bat cli`），参考 OFoster_Sample 的 `run.bat`。

**桌面发布 `publish.bat`**

- `odin build src/game -collection:olib=..\olib -collection:game=src -o:speed -subsystem:windows -out:build\publish\win-x64\<ProjectName>.exe`。
- 把 SDL3 运行库拷到 exe 旁：`odin root` 输出的目录下 `vendor\sdl3\SDL3.dll`。不要依赖 PATH 上可能更旧的 SDL3.dll。
- 运行时资源：优先 `#load` 编译进 exe（字体、小贴图、默认配置），无需随包分发；需要玩家可改的文件（配置、关卡）拷到 `build\publish\win-x64\assets`，运行时用 `kit/storage` 的 `resources_root_release` 定位。
- 分发的是整个发布目录。README 写明压缩包范围，避免只发 exe 丢掉 SDL3.dll 或资源。

**Web 发布 `publish_web.bat`（仅在目标平台包含 Web 时创建）**

foster 支持 `js_wasm32`，但有硬约束，接入前完整阅读 olib 的 `foster/docs/WEB_TARGET_REQUIREMENTS.md` 第 12 节：

- 构建：`odin build src/game -collection:olib=..\olib -collection:game=src -target:js_wasm32 -o:speed -out:build\publish\web\<ProjectName>.wasm`。
- 产物目录：`<ProjectName>.wasm`、`odin.js`（`odin root` 下 `core\sys\wasm\js\odin.js`）、`foster.js`（olib `foster\internal\web\foster.js`）、`index.html`（参照 `foster/tests/webtest/index.html`）。
- **`core:os` 在 js 目标上一 import 就编译失败**。以下 olib 包目前仅限桌面，Web 构建的可达代码里不能出现：`kit/storage`、`kit/app`、`kit/audio`、`kit/asset`、`kit/rendering` 的 Aseprite 部分、`core/encoding`。游戏自己的文件读写收口到成对平台文件（`#+build !js` / `#+build js wasm32, js wasm64p32`）；存档用 foster 的 `OpenUserStorage`（Web 上落到 localStorage）。
- 资源全部 `#load` 内嵌；字体按文本实际用到的字符集裁剪后内嵌。
- App 与游戏状态必须是包级全局变量：Web 上 `main` 返回后栈会被复用，框架会把 App 搬到堆上，但 `main` 里的局部变量不会。
- 发布后检查 wasm 中没有 SDL 导入（`strings <ProjectName>.wasm | findstr SDL3` 应无输出），用 HTTP 预览（`python -m http.server`），不能双击 `index.html` 验证。`serve` 参数在发布成功后启动预览。

在 README 中说明以下入口、前置依赖和对应输出：

```powershell
.\play.bat
.\check.ps1
.\publish.bat
.\publish_web.bat
.\publish_web.bat serve
```

### 分层和依赖方向

先按职责确定代码所在的包，再在层内按玩法拆子包。Odin 的 import 是显式字符串，且编译器禁止循环导入，所以层界可以直接由包结构和 import 行保证：

| 包 | 负责什么 | 可以 import |
| --- | --- | --- |
| `authoring` | 配置类型、默认值、校验、JSON 读写、版本迁移、场景生成 | `core:*`、`olib:core/*`；不 import 游戏其他包、foster、kit |
| `defs` | 共享枚举、固定映射、distinct 类型、UI 发给规则的操作请求类型 | `authoring` |
| `state` | 本局权威数据、句柄池、SoA 列、扩容、版本号 | `defs`、`authoring`、`olib:core/*` |
| `logic/*` | 状态转换、玩法规则、导航、可重建查询缓存 | `state`、`defs`、`authoring`、`olib:core/*`、`core:math/linalg` 等；**不 import foster、kit、vendor、view、game** |
| `view` | UI、绘制、动画、音频、显示缓存 | `state`、`defs`、`olib:foster`、`olib:kit/*`；可调用 `logic` 的只读查询，不调用改状态的 proc |
| `game`（package main） | 读取输入和时间、生命周期、系统组装与执行顺序 | 全部；不实现伤害、收入等玩法公式 |

- `logic` 不依赖 foster，才能在 `odin test` 里无窗口运行；向量用 `[2]f32` 或 `core:math/linalg`，需要和 foster 类型互转的地方放在 `game` 或 `view`。
- `view` 不修改 `state`：点击形成 `defs` 里的操作请求，交给 `game` 在下一次更新时调用 `logic` 处理。
- 用 `tools/check_layers.ps1` 解析每个包的 `import` 行，按上表验证；Odin 的 import 只能写在文件顶部且必须是字符串字面量，按行解析是可靠的。把它接进 `check.ps1`。
- 不为每个功能增加“接口”或回调注册表来规避依赖方向；没有实际复用需求时，显式传参即可。

### 状态和规则如何写

以下为要点；内容目录与能力字段、唯一全局状态与派生缓存、变化事件、按配置计算期望值等完整约定见 olib 的 `prompts/dod-guidelines.md`，开始写玩法前一并阅读。

- `state` 保存真正的对局进度，例如生命、资源、冷却、任务和已探索区域。允许维护存储一致性，不负责决定攻击目标、收入或放置是否合法。
- `logic` 的 proc 显式接收状态指针、操作参数和 `dt`，例如 `step(world: ^state.World, dt: f32)`；不读取全局输入、foster 时钟或 App。
- foster 的 `DefaultAppConfig` 默认固定 60 Hz 调用 `UpdateProc`，`app.Time.Delta` 即模拟步长。暂停和倍速由 `game` 决定本次调用几次 `logic`。UI 动画时间与模拟时间按用途区分；固定步长不自动保证确定性，需要重放时还要控制随机种子与迭代顺序。
- kit/ui 每帧在 `RenderProc` 中声明（与 OFoster_Sample 的 game_ui 一致）。控件返回的确认事件写入操作请求队列（可用 `core/messaging` 的 `Command_Queue`），由下一次 `UpdateProc` 交给 `logic`；固定步长下两次渲染之间可能有零次或多次更新，验证一次点击只执行一次。合法性、费用扣除和结果修改集中在 `logic`；禁用按钮只是反馈，不能替代规则校验。
- 大量同类实体用 `core/handle/array` 的 `Pool` + `distinct ha.Handle`，专有属性按槽位下标存成 SoA 列；跨帧引用只存句柄，使用前 `ha.valid` 或判断 `ha.get` 是否为 nil。不要为每个单位创建带 update 回调的结构体。
- 新增实体字段时同步检查分配、初始化、扩容、移除、槽位复用和重开，避免旧数据留给新实体。
- 配置中的静态类型信息与实例状态分开保存。价格、攻击方式等由目录定义；实例只保存 1 字节类型编号和自身变化的数据。根据能力编写规则，不在多处按具体内容 ID 堆分支。
- 数值从已校验的配置快照读取，不在每帧解析 JSON。默认值、全局配置和关卡覆盖的优先级应明确，UI 和规则使用同一份生效数值。
- 空间索引、路径和统计缓存放在 `logic/queries`；渲染、图标和地图显示缓存放在 `view`。每个缓存注明输入、失效条件、重建时机和释放责任，不以缓存替代权威状态。
- 先保证正确性，再依据测量优化热点。热循环避免重复全表扫描、每帧临时集合和堆分配；并行仅在规模需要时引入（`core:thread.Pool` + `core:sync.Wait_Group`），工作线程只写各自结果区间，由主线程有序提交。

### 内存与资源所有权

Odin 没有 GC，所有权必须显式：

- 每种资源配一对 `xxx_init` / `xxx_destroy`（或 `_dispose`），在注释里写明谁分配、谁释放、生命周期多长。foster 资源（Texture、Batcher、Font、Target……）同样由明确的所有者在 `ShutdownProc` 中释放。
- 长期数据用 `context.allocator`；一帧内用完的字符串、临时数组用 `context.temp_allocator`。foster 在每帧末尾（`tick_app` 结束时，`RenderProc` 与 `end_frame` 之后）清空临时分配器；临时分配只在本帧有效，不要跨帧持有。`StartupProc` 中的临时分配在第一帧结束时失效。
- 返回切片或字符串的 proc 在签名或注释中说明由谁 `delete`；接收 `allocator := context.allocator` 参数的 proc 按调用方传入的分配器分配。
- 指针稳定性：`core/handle/array` 的 `get` 返回的指针在 `add` / `remove` 后可能失效，不要跨越结构变更持有；需要稳定地址时选 `core/handle/growing` 或 `virtual`（见 `core/handle/README.md`）。`kit/ui` 的 `UI_Context` 必须地址稳定、不可按值复制。
- 开发构建用 `core:mem` 的 `Tracking_Allocator` 检查泄漏（olib `core/debug` 有现成包装），退出时打印未释放的分配。

### UI 用什么以及如何接入

玩家 UI 使用 **`kit/ui`**：clay 负责布局，kit/ui 提供控件、交互和 foster Batcher 后端。接入前完整阅读 olib 的 `kit/ui/README.md`，并对照 OFoster_Sample 的 `src/game_ui`。

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

- 字体：`foster.FontLoadFile` 或 `FontMake` 读取 TTF，`ui.ui_font_bake` 烘焙成位图图集，再 `ui_register_font`。**默认只烘焙 ASCII 32..126**；中文必须把实际用到的字符（本地化文本中的全部字符）作为 `codepoints` 传入，否则中文不显示。
- 控件 ID 全局唯一且跨帧稳定；动态列表用内容 ID，不用会随排序变化的位置。
- 主题集中在 `view` 的 theme 文件中，从 `ui.UI_THEME_DARK` 复制后调整；不要在每个控件里分别写颜色和尺寸。
- 缩放：`ui_set_viewport(&ctx, rect, scale)` 的矩形与指针都是渲染目标像素，布局尺寸是逻辑像素。绘制、点击判定、相机预留区域和测试点击位置使用同一套布局结果。
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
7. 检查默认窗口、窄窗口、缩放、中英文长文本、悬停和禁用状态。英文变长时应换行、适配或调整布局，不能仅验证中文截图。

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

- **包文档**写在包主文件的 `package` 上方，说明本包职责和不负责什么；多主题文件在 `package` 之后列出分区导航（见 olib CODE_STYLE 第 2、3 节的分节线框与导航格式）。
- **类型和关键 proc** 在声明上方用 `//` 说明负责什么以及必要的边界；参数有单位、范围、坐标空间或所有权约定时写清楚，返回值有特殊含义时说明。
- **状态字段**重点解释单位、哨兵值、有效期和槽位对应关系，例如“秒”“世界格坐标”“无目标时为零值句柄”。
- **实现内部**用 `//` 解释“为什么这样做”：算法前提、排序要求、缓存失效、线程边界、平台限制。修改行为时同步更新注释。

下面是注释与分层的简化示例，用来说明写法，不要求新项目一定包含周期收入玩法。

```odin
// 文件：src/state/income.odin
package state

// 周期收入的余额与累计进度；计时推进与结算规则在 logic/economy。
Income :: struct {
	coins:           int,
	// 距上次结算累计的模拟秒数；暂停不增加，重开时清零。
	elapsed_seconds: f32,
}
```

```odin
// 文件：src/logic/economy/economy.odin
// economy —— 按显式传入的模拟时间结算收入，不读取窗口或 UI 状态。
package economy

import "game:state"

// 推进计时并结算完整周期，剩余时间留待下次调用。
// dt：模拟秒数，调用方保证有限且非负；interval_seconds 来自已校验配置，必须大于零。
income_step :: proc(income: ^state.Income, dt: f32, interval_seconds: f32, coins_per_cycle: int) {
	income.elapsed_seconds += dt

	// 一次推进可能跨过多个周期；逐次扣除保留余量，避免漏结算或计时漂移。
	for income.elapsed_seconds >= interval_seconds {
		income.elapsed_seconds -= interval_seconds
		income.coins += coins_per_cycle
	}
}
```

```odin
// 文件：src/logic/economy/economy_test.odin
#+test
package economy

import "core:testing"

import "game:state"

@(test)
income_step_settles_multiple_cycles :: proc(t: ^testing.T) {
	income: state.Income
	income_step(&income, 5, 2, 3)
	testing.expect_value(t, income.coins, 2 * 3)
	testing.expect_value(t, income.elapsed_seconds, 1)
}
```

App 骨架（`src/game/main.odin`）：

```odin
package main

import foster "olib:foster"
import ui "olib:kit/ui"

import "game:logic/economy"
import "game:state"

// App 与游戏状态放在包级：Web 目标上 main 返回后栈会被复用。
game:    foster.App
batcher: foster.Batcher
ui_ctx:  ui.UI_Context
income:  state.Income

main :: proc() {
	foster.InitApp(&game, foster.DefaultAppConfig("MyGame", 1280, 720))
	defer foster.Dispose(&game)
	game.StartupProc = startup
	game.UpdateProc = update
	game.RenderProc = render
	game.ShutdownProc = shutdown
	foster.Run(&game)
}

startup :: proc(app: ^foster.App) {
	foster.BatcherInit(&batcher, &app.GraphicsDevice, "game")
	ui.ui_init(&ui_ctx, 1280, 720)
}

// 默认固定 60 Hz；Delta 即模拟步长。
update :: proc(app: ^foster.App) {
	economy.income_step(&income, app.Time.Delta, 2, 3)
}

render :: proc(app: ^foster.App) {

	target := foster.DrawableTargetFromWindow(&app.Window)
	foster.GraphicsDeviceClear(&app.GraphicsDevice, target, foster.Color{24, 28, 36, 255})
	foster.BatcherClear(&batcher)
	// 绘制世界，再按 kit/ui README 的最小帧流程声明 UI 并 ui_draw 叠加。
	foster.BatcherRender(&batcher, target)
}

// 先释放 UI，再释放字体、贴图和 Batcher。
shutdown :: proc(app: ^foster.App) {
	ui.ui_dispose(&ui_ctx)
	foster.BatcherDispose(&batcher)
}
```

其他适合写注释的地方：

```odin
// 建筑位置改变会使空间索引失效，必须经 building_set_position 更新版本号。
// 工作线程只记录候选结果；实体删除和伤害结算在主线程按槽位顺序提交。
// 返回的切片由 context.temp_allocator 分配，本帧结束前有效。
```

避免 `// 增加计时器`、`// 遍历列表` 这类复述代码的注释。临时方案需要写明原因和移除条件；不要留下没有范围和行动说明的 `TODO: 优化`。设计推导、长篇流程和使用教程放在 `docs`，源码只保留就地需要的信息。

### 创建与验证流程

1. 阅读目标目录已有的 `AGENTS.md`、README 和脚本，检查 Git 状态及 olib 位置。先读 olib 的 `README.md`、`docs/CODE_STYLE.md`、`kit/ui/README.md` 和要用的包源码；遇到 API 不确定时先查源码。
2. 建立 `src/` 各层包、`ols.json`、`play.bat`，先让空窗口、中文文本和一个可交互的 kit/ui 按钮正常运行。
3. 完成一个贯穿各层的功能：输入 → 操作请求 → `logic` 校验与状态变更 → 画面反馈。再补完需求中约定的第一版玩法闭环和重开。
4. 需要调试/编辑工具时，作为 `src/` 下另一个 package main（如 `src/tools/editor`）或游戏内的调试面板（odin-imgui），不进入发布构建的可达代码。
5. 目标平台包含 Web 时，按“桌面与 Web 发布入口”的约束拆出平台文件，核对资源内嵌、用户存储和 HTTP 预览，不直接复制桌面文件系统假设。
6. 实现 `publish.bat`（和需要时的 `publish_web.bat`），验证实际产物；不能以开发构建能启动代替发布包可运行。
7. 为每个 `logic` 包写 `*_test.odin`（`#+test` + `@(test)`），用 `odin test` 无窗口运行；画面与输入用游戏 exe 的 `shot` / `smoke` 参数验证（参考 OFoster_Sample 的 game_ui：注入点击、渲染一帧、写 PNG 后退出）。
8. 编写 `check.ps1`：自动发现并运行所有含 `@(test)` 的包、运行 `tools/check_layers.ps1`、编译游戏；任何一项失败返回非零退出码（可参考 olib 根目录的 `check.ps1`）。
9. 完成 README、`src/` 分层说明和简短 AGENTS.md。README 写明脚本用法、输出目录及依赖；新文档加入 `docs/README.md`，说明真实实现与尚未实现的内容。

至少验证以下内容：

- 构建成功，游戏能够启动，默认场景可以操作并重开。
- `logic` 可无窗口测试，覆盖正常路径及关键拒绝条件；涉及缓存或句柄时验证失效和复用。
- 层间依赖检查覆盖上表的禁止导入（尤其 `logic` 不得 import foster/kit/view），以及任何代码不得 import `olib:foster/internal`。
- 游戏用 `-vet` 编译通过，检查游戏及其可达依赖；olib 的 `check.ps1` 已对所有第一方包启用 vet。
- UI 的文字、按钮和输入命中正确，点击不会穿透；窗口缩放和语言切换不会导致明显溢出。
- 配置出错能定位原因；涉及保存时，写入和重新读取的内容一致。
- 开发构建用 Tracking_Allocator 运行一局并退出，没有未释放的分配。
- 桌面发布包可从发布目录启动，SDL3.dll 和资源齐全；Web 包无 SDL 导入并可通过本地 HTTP 打开完成基本交互。环境缺失的发布模式如实标为未验证。

仅运行已创建且与本次改动相关的检查。画面检查需要真实图形环境，保存截图后实际查看；不能用“构建成功”代替视觉验收。性能测试使用 `-o:speed`，并报告场景规模和测量条件。

完成后从新仓库根目录运行，例如：

```powershell
.\play.bat
.\check.ps1
odin test src/logic/<feature> -collection:olib=..\olib -collection:game=src
.\play.bat shot
```

上面的占位名称需要替换为实际项目。不要报告不存在的命令，也不要把 olib 或 OFoster_Sample 的测试和示例当作新游戏已经实现的功能和检查。

### 最终交付

交付可运行的项目文件及对应平台的发布脚本，并简要说明：实现了哪些玩法、代码主要放在哪些包、如何启动和发布、产物保存在哪里、实际执行了哪些验证、还有哪些明确限制。没有运行的检查或缺少环境的步骤应如实列出。

遇到实现失败时修复到可验证状态；无法完成的部分给出具体原因。不要把空 proc、固定假数据或尚未连接的按钮描述为已经完成的功能。

## 提示词结束

## olib 内的参考入口

这些链接均可从本文件直接打开。游戏的目录、命名和注释规则是新项目约定，不要求修改 olib 历史代码或第三方源码以统一格式。

| 主题 | 库内入口 |
| --- | --- |
| 仓库结构、使用方式与一键验证 | [README](../README.md)、[check.ps1](../check.ps1) |
| 编码规范与 foster/kit 边界 | [CODE_STYLE.md](../docs/CODE_STYLE.md) |
| 已有能力与后续计划 | [ROADMAP.md](../docs/ROADMAP.md) |
| 运行时（App、窗口、输入、图形、存储） | [foster README](../foster/README.md)、[移植映射与 API 差异](../foster/docs/PORTING_MAP.md) |
| Web 目标的约束与发布 | [WEB_TARGET_REQUIREMENTS.md](../foster/docs/WEB_TARGET_REQUIREMENTS.md)、[webtest 示例](../foster/tests/webtest/) |
| 游戏 UI | [kit/ui README](../kit/ui/README.md) |
| 资源管线 | [kit/asset README](../kit/asset/README.md) |
| 实体基础存储与句柄 | [core/handle README](../core/handle/README.md)、[array 实现](../core/handle/array/) |
| 资源根与存档路径 | [kit/storage](../kit/storage/storage.odin) |
| 调试控制台与命令行参数 | [kit/app](../kit/app/cli_console.odin) |
| 命令队列与广播 | [core/messaging](../core/messaging/messaging.odin) |
| 配置读写 | [core/encoding](../core/encoding/) |
| 面向数据的开发约定 | [dod-guidelines.md](dod-guidelines.md) |

可运行示例位于独立的 OFoster_Sample 仓库，默认与 olib 同级（`run.bat <示例名>`）。它们用于参考库 API；新项目的业务、资源和验证应保存在新游戏自己的仓库中。
