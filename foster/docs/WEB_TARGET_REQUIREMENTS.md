# OFoster Web 目标（js_wasm32）后端需求

> 需求方背景：vehicles 项目（Odin + OFoster）要跑进浏览器。本文档是给 OFoster 增加 Web 后端的需求说明，基于 2026-09-09 对 OFoster 当前代码和 web-spike 验证结果的审计。

## 2026-10-06 状态更新

历史 M0–M4 记录保留如下，但其中“无目录枚举”“纹理下载恒返回 nil”及
“Blit 非目标”的描述已被新实现替代。当前桥支持空目录标记、子项枚举与递归删除，
支持离屏颜色及深度/模板目标、深度/模板状态、RGBA8/R8/RG8/RGBA32F GPU 读回、
区域上传、GPU Clone 与缩放 Blit。`tests/port_regression` 已在 Chromium 通过
RGBA8 像素、模板裁剪、深度比较与 ZIP/目录存储回归。

后续补齐标准和原始手柄映射、按下/释放与震动请求，UTF-8/IME 文本输入、同帧累计，
CSS/自定义图像光标、异步剪贴板、PNG 导出、文件/目录导入及保存完成回调。
`tests/port_regression/?debug=1&input-tests=1` 通过新增模拟设备和文件句柄回归，
并以真实 TTF 验证增量图集、pixel-perfect 字形和资源释放。

Compute、SSBO、离屏 MSAA、线框填充属于当前 WebGL2 后端限制。剪贴板/文件选择
还受浏览器权限、API 支持和用户激活限制；选择器不可用会回调取消结果。选中文件
导入虚拟路径，保存的磁盘写入用 `FlushStorageFileAsync` 确认。真实硬件/系统 IME/
权限对话框尚需人工验证。完整 API 差异和测试边界见 [PORTING_MAP.md](PORTING_MAP.md)。

## 0. 已验证事实（不要推翻，直接利用）

- **Odin 不经过 Emscripten**：`-target:js_wasm32` 用 Odin 自带 wasm-ld + JS runtime（`odin.js`）。Odin 的 `vendor:sdl3` 没有 wasm 链接路径（`sdl3__foreign.odin` 只有 `SDL3.lib` / `system:SDL3`），SDL 不可链。所有 SDL 调用点必须走条件编译替换。
- **编译期分支**：`when ODIN_OS == .JS`（Odin core 内部就是这么用的，如 `core/c/libc/stdio.odin:93`）。
- **Odin 自带的 JS 侧设施**（`D:\Lib\odin\core\sys\wasm\js\`，包名 `wasm_js_interface`，`#+build js wasm32`）：`odin.js` runtime、`dom.odin`（少量 DOM helper）、`events.odin`、`memory_js.odin`。能力有限，复杂桥接仍需自写。
- **web-spike 已验证的桥接模式**（vehicles/web-spike/）：
  - Odin 侧：`foreign import webgl_lib "webgl_bridge"` + `@(default_calling_convention="contextless")` foreign 块声明函数，参数用原始类型（f32/i32/rawptr）。
  - JS 侧：**手动实例化** wasm（不用 `odin.runWasm`，因为要持有 `memory` 给 `rawptr` 传参用），`imports.webgl_bridge = {...}` 注入实现。
  - 帧循环：导出 `step`，JS 侧 `requestAnimationFrame` 驱动。
  - stb_truetype 在 wasm 上正常工作（中文字形烘焙已验证）。

### M0(2026-09-09)新增已验证事实

- **死代码消除与 SDL 导入表**：未被静态可达调用链引用的 SDL foreign proc 不进 wasm 导入表；**文件级 proc 别名（`XXX :: yyy_proc`）不强制产出代码**。因此无需拆分 SDL 文件：保留全部 `import SDL "vendor:sdl3"`，只在内联 `when ODIN_OS == .JS` 分支替换调用点即可（SDL 类型如 `^SDL.Window` 字段在 .JS 下可继续使用）。
- **core:os 在 js 目标是编译期 #panic**（`core/os/wasm.odin`，**仅 import 不使用也会触发**）；`core:path/filepath` 的 `path.odin` 无条件依赖 core:os，同样不可用。已引入平台文件收口：`platform_thread_native/web.odin`、`storage_os_native/web.odin`、`storage_path_native/web.odin`（`#+build !js` / `#+build js wasm32, js wasm64p32`；负向 tag 语义已实测有效）。**core:compress/zlib、core:path/slashpath、core:time 均为 js 安全**。
- **§7 风险项已有结论**：core:os 在 js 下完全不可用 → vehicles 直接使用 `os.read_entire_file_from_path` 等的存档代码**必须**走 `when ODIN_OS == .JS` 分流到虚拟 FS 桥（不是可选项）。
- **栈上 App 的生命周期陷阱**：.JS 下 `main()` 在 `Run` 注册帧循环后立即返回，游戏在 `main` 里声明的**栈上 `App` 结构会被后续调用复用覆写**（实测第 ~120 帧被 `fmt.println` 调用链打穿）。框架在 **`run()` 入口**经 `web_relocate_app` 把 App **堆拷贝并修正内部回指针**（Window/Input/FileSystem/RenderTarget；放在入口是因为 StartupProc 在 run 内部执行，其中初始化的 Batcher 等会持有 `&app.GraphicsDevice`）。**约束：游戏经 `AppSetUserData` 传入的状态在 web 上必须是全局变量或堆分配，不能是 main() 局部变量**（vehicles 需要检查这一点）。
- **rAF 与页面可见性**：浏览器对 hidden 页面暂停 requestAnimationFrame（符合预期，省电）；`pagehide → Quit` 事件已接通。IAB/无头测试环境里页面恒为 hidden，验收时需手动驱动 `foster_step`（webtest 已验证此法）。
- **M0 验收结果**（webtest，Chrome IAB 实测）：600 帧长跑无中断、计时精确（2/4/6/8/10s）、画布像素读回游戏驱动的清屏色、resize 事件正常消费、Quit 干净走 `run_finish`、退出后防重入；桌面（Windows）构建回归通过。产物：`web.odin`（Odin 桥）、`internal/web/foster.js`（JS 桥）、`tests/webtest/`（验收程序 + 构建脚本）。

### M2/M3/M4(2026-09-10)新增已验证事实

- **输入不伪造 SDL.Event**:Keys 枚举值与 SDL scancode 一致(`cast(Keys)scancode`),Web 事件在 poll_events 的 .JS 分支直接派发到现有 `input_key/input_mouse_button/input_mouse_move/input_mouse_wheel` 入口,复用全部现有状态机(双缓冲、stamp、Enabled 门控)。JS 侧维护 `e.code → scancode` 映射表;鼠标坐标 = `(clientX-rect.left) × (clientWidth/rect.width) × DPR`(见 vehicles 接入事实, offsetX 方案已被证伪)。
- **该环境 WebGL2 的 7 参 texSubImage2D 绑定不可用**(连 null 都 Overload resolution failed),必须用 9 参形式(带 width/height)—— `fw_gl_upload_texture` 已带宽高。
- **新增 SDL 可达性坑**:`OpenUserStorage` 会把 `SDL.GetPrefPath` 拉进可达集(即使运行时走不到),`file_system_open_user/title_storage` 已加 .JS 分支。游戏每接入一个新框架路径都要复查导入表(`strings wasm | grep SDL3` 应为 0)。
- **M4 虚拟 FS 设计**:localStorage 每文件一键(`fosterfs:<绝对路径>`,base64 载荷,二进制安全,同步 API 无需异步桥)。扁平 FS 无目录概念(`is_directory` 恒 false、`enumerate` 暂不支持)。**vehicles 侧直接用 core:os 的存档代码仍需 5 行分流** —— 但若改走 `OpenUserStorage + ReadAllText/WriteAllText` 公共 API 则零改动。
- **M2 验收**:棋盘纹理四边形(Textured 管线)像素 `[120,220,160]` 精确;stb 中文烘焙 20 字形,文本行 87 个采样点命中;两纹理均经 9 参 texSubImage2D 上传。
- **M3 验收**:合成 KeyboardEvent(ArrowRight)驱动标记每帧 +4 像素精确移动;滚轮/空格/鼠标事件链路无异常;`OnResize` 回调触发(resize → WindowResized 事件 → window_on_event)。
- **M4 验收**:visits 计数经 OpenUserStorage→WriteAllText 写入 localStorage,刷新页面后读回递增(1→2)并经 stb 字形渲染到画面。
- 桌面(Windows)构建+运行回归通过(字形烘焙、存档、渲染无 panic)。

### vehicles 接入(2026-09-10)新增已验证事实

- **鼠标坐标必须按 rect 归一**:`clientX - rect.left` 直接乘 DPR 在页面被 zoom/transform 时错位(实测 245 → 163.33,恰 2/3);正确公式 `(clientX-rect.left) × (clientWidth/rect.width) × DPR`。合成 PointerEvent 的 `offsetX` 不可信。**`<script src>` 会被浏览器缓存** —— 调试 JS 改动不生效时,先给 index.html 的引用加 `?v=N`。
- **WebGL preserveDrawingBuffer 保留上一帧**,桌面交换链是 discard 语义 → 框架在 begin_frame(.JS)先清一次屏对齐桌面行为,防止游戏未 clear 的帧残留残影。
- **游戏侧接入清单(vehicles 已全部落地)**:core:os → 平台文件收口(game_args/io_read_file/io_write_file/io_remove);字体 → 源码字符集子集化(pyftsubset,17.8MB→486KB)`#load` 内嵌;音频 → WebAudio 桥(foster.js 的 `FOSTER_EXTRA_IMPORTS` 钩子注入,游戏侧 `audio_platform_web.odin` 每次 update 泵 1/60s 样本,AudioBufferSourceNode 顺序调度 + 前瞻缓冲);存档 → io_* 直通 storage_os 虚拟 FS,桌面行为不变。
- **框架为此补的分支**:`window_set_fullscreen/fullscreen`(页面 Fullscreen API)、`window_set_size`(no-op,canvas 随视口)、`target_dispose`(离屏目标释放)、`texture_download_data`(返回 nil,截图类功能 Web 暂不支持,`texture_get_data` 自动退回 CPU 像素副本)。**MouseButtonDown 事件需同时更新鼠标位置**(桌面靠轮询,Web 禁用轮询)。
- **vehicles 验收结果**:完整启动(内嵌字体 495 字形烘焙 + WebAudio 初始化)、300 帧 0.33ms/帧、合成点击 Deploy 成功切换车库场景、settings 持久化 localStorage、wasm 导入表零 SDL;桌面(Windows)回归通过(随包字体路径不受影响)。产物:`web/vehicles.js`(音频桥)、`web/index.html`、`build_web.bat`。
- **itch 发布路径**:`build_web.bat` 产物(build/web/ 全部文件)打 zip → itch 新建项目选 HTML 类型上传 → 勾选"在浏览器中运行"。

### M1(2026-09-09)新增已验证事实

- **着色器语义以 SPIR-V 反编译为准**:本机 VulkanSDK 的 spirv-cross 可直接把 assets/shaders/*.spv 反编译成 GLSL(`spirv-cross --es --version 310 x.spv`)。Batcher 片元 = `(tex·mode.x)·color + color·(mode.y·tex.a) + color·mode.z`(Normal/Wash/Fill);三个顶点着色器都是 `Matrix * vec4(pos,0,1)`,Matrix 为 64 字节列主序。已产出 6 个 `*.glsl`(GLSL ES 300,命名式 uniform:`u_matrix`/`u_tex`/`u_distance_range`)。
- **§11 uniform 决策已定**:逐 draw 设 `uniformMatrix4fv`/`uniform1f`,不用 UBO(我们自控全部 GLSL,uniform 命名约定在握;Batcher 每 draw 恰好推一次矩阵)。
- **GL 对象走句柄表**:JS 侧 `Map<索引, GL对象>`,Odin 把 u32 句柄 cast 进 `^SDL.GPUXxx` 字段;`web_handle_ptr/u32` 互转。管线缓存/采样器缓存沿用 Odin 侧 map(键不变)。
- **viewport/scissor 需 Y 翻转**:SDL_GPU 左上原点 → `gl.viewport(x, fbH-y-h, w, h)`;正交矩阵本身已含 Y 翻转,不用动。
- **`ofoster:Graphics` 会连带 `ofoster:Images`**(Texture.odin/SpriteFont.odin 引用)→ Images 包的 core:os 依赖必须一并收口(已做:四个文件的 `os.read/write` 改走根包 `storage_os_*`)。另:**Odin 对 js 目标定义 `NO_STDIO`**,vendor:stb 的 `write_png` 等 stdio 写入函数被条件排除 —— `ImageWritePng` 已加 .JS 分支(恒 false,文件写盘非目标)。
- **浏览器 wasm 缓存坑**:软 reload 可能继续跑旧 wasm(症状:行为停留在旧版本)。foster.js 的 `fetch` 已加 `{cache:"no-cache"}`;调试"改动没生效"时优先怀疑缓存。
- **FillMode.Line 在 WebGL2 无法表达**(无 polygonMode),Web 后端恒按填充绘制 —— 已知差异,游戏侧避免依赖。
- **M1 验收结果**(webtest,像素级):清屏色/纯色矩形(呼吸动画理论值精确吻合)/圆/四角渐变/粗线/圆环全部渲染正确;管线哈希缓存命中(每批 1 次创建);顶点缓冲扩容正常;90+ 帧零中断;桌面(Windows)构建+运行回归通过。

## 1. 目标

vehicles 以 `odin build src -target:js_wasm32 -collection:olib=..\olib` 构建，产物 + `odin.js` + `foster.js` + `index.html` 在 Chrome/Edge/Firefox/Safari 直接可玩。

**硬性约束：OFoster 公共 API（App/Window/Graphics/Input/Storage 对外的 proc 与 struct 签名）不变；vehicles 游戏代码零改动（仅 build 脚本层面的差异可接受）。**

### 验收标准

1. 空窗口（canvas 清屏）+ rAF 帧循环跑通。
2. Batcher 管线渲染彩色矩形。
3. Textured 管线渲染贴图 + 中文文本（stb 路径）。
4. 键盘、鼠标（含滚轮）输入可用，游戏可操作。
5. canvas resize 后渲染正确（viewport / 逻辑坐标）。
6. 存档/设置读写持久化（刷新页面后保留）。
7. 稳定 60fps（rAF 节流），无明显内存增长。

### Phase 1 非目标（可 stub 或 panic，留 TODO）

- GPU compute（`graphics.odin`（compute 一节）；vehicles 未使用——审计确认）
- `BlitGPUTexture` / `DownloadFromGPUTexture`（vehicles 未使用）
- Gamepad（`input.odin` 里的 SDL.IsGamepad / AddGamepadMapping 等）
- 文件对话框（`storage.odin:382-406`）
- 全屏 API、文本输入（SDL textinput）
- MSAA、多窗口

## 2. 架构总则

1. 公共 API 冻结；所有平台差异收进各 runtime 文件内部的 `when ODIN_OS == .JS` 分支，或新建 `internal/web/`（Odin 侧）+ `foster.js`（JS 侧，单文件，与 odin.js 一起加载）。
2. JS 桥命名沿用 spike 模式：`foreign import foster_web_lib "foster_web"`，全部 `contextless`，参数只用 i32/f32/rawptr/bool 等原始类型；字符串传 `rawptr+len`，JS 侧从 `memory` 读。
3. 事件模型：**保持 framework.odin 现有的事件处理 switch 不动，只替换事件来源**。JS 侧把 DOM 事件写进一个双向环形队列（wasm 内存中的固定结构，或 JS 数组 + 逐条取），Odin 侧 `PumpEvents/PollEvent` 的等价物从队列取出并填入现有 SDL.Event 形状的结构（或在 JS 分支下用 Foster 内部事件枚举——二选一，倾向后者，避免假扮 SDL 结构）。
4. 帧模型：`App.Run` 在 .JS 下**不得阻塞**——完成初始化后注册导出 `foster_step(f32 dt)`，每帧 = 消费事件队列 → `OnUpdate` → `OnRender` → present（rAF 合成）。`main` 返回即视为"进入事件循环"。

## 3. SDL 平台面替换清单（审计自当前代码，含位置）

| 功能 | 现状（文件:行） | Web 实现要求 |
|---|---|---|
| 启动初始化 | framework.odin:1244 `SDL.Init` | no-op（GL 上下文由 JS 创建 canvas 时取得） |
| 窗口创建 | framework.odin:948 `SDL.CreateWindow` | canvas 元素即窗口；尺寸/标题（`document.title`）/flags 忽略或映射 |
| 事件循环 | framework.odin:1303-1306 `PumpEvents/PollEvent` | 消费 JS 事件队列（见 §2.3） |
| 相对鼠标 | framework.odin:1114-1117、input.odin:685 | Pointer Lock API；`WarpMouseInWindow` 在锁定模式下 no-op |
| 光标 | input.odin（CreateSystemCursor/CreateColorCursor/SetCursor/CursorVisible） | CSS `cursor` 样式映射；CursorVisible ↔ 隐藏/显示 |
| 剪贴板 | input.odin:704-709, 904-905 | `navigator.clipboard`。注意 Foster API 是同步的：GetClipboardText 返回 JS 侧缓存的最近值，SetClipboardText fire-and-forget |
| 偏好路径 | storage.odin:337 `SDL.GetPrefPath` | 返回虚拟 FS 前缀（见 §7） |
| 基路径 | storage.odin:349 `SDL.GetBasePath` | 返回虚拟 FS 的内嵌资产前缀（见 §7） |
| 文件对话框 | storage.odin:382-406 `ShowFileDialogWithProperties` | Phase 1：回调立即失败/返回 not-supported；后续可桥 `<input type=file>` |
| 关窗/焦点 | `SDL.GetWindowFlags`（4 处） | 映射 visibilitychange / blur / pagehide 事件 |

## 4. 图形后端：WebGL2（Phase 1 决策）

**选 WebGL2，不选 WebGPU**，理由：

- spike 已验证整条 WebGL2 桥接链路；
- 浏览器覆盖 100%（含 Safari）；
- vehicles 审计未用 compute / MSAA / blit / render-target 特性，SDL_GPU 的即时式语义可以在 GL 状态机上模拟；
- WebGPU 与 SDL_GPU 语义 1:1（SDL_GPU 的 web 后端本来就是 WebGPU），未来要 compute 时再迁移，届时 Foster API 不用动。

### 需要覆盖的 SDL_GPU 子集（来自 graphics_*.odin 审计）

- Device：`CreateGPUDevice`（framework.odin:257，着色器格式 {.SPIRV,.DXIL,.MSL} 需加 .JS 分支）、`ClaimWindowForGPUDevice`（:300）、`WaitForGPUIdle`、`DestroyGPUDevice`。
- 命令缓冲：`AcquireGPUCommandBuffer` / `SubmitGPUCommandBuffer` / `CancelGPUCommandBuffer` —— Phase 1 直接映射为即时 GL 调用（Acquire 返回哑句柄，Submit 交由 rAF 合成），保持 API 形状。
- Transfer buffer：Create/Map/Unmap/Release、`UploadToGPUBuffer`、`UploadToGPUTexture`（经 `BeginGPUCopyPass/EndGPUCopyPass`）→ GL 的 `bufferSubData` / `texSubImage2D`。
- Texture / Sampler：Create/Release、`GPUTextureSupportsSampleCount`（Phase 1 恒返回 1x 支持与否的假值）。
- Graphics pipeline：Create/Release + `GPUStencilOpState/BlendFactor/BlendOp/CullMode/FillMode/CompareOp/Filter/AddressMode` 等状态枚举 → GL 对应状态（预编译 GL program + 状态集）。
- Render pass：`BeginGPURenderPass/EndGPURenderPass`、`BindGPUGraphicsPipeline`、`SetGPUViewport`、`BindGPUVertexSampler(s)`、`BindGPUIndexBuffer`、`PushGPUVertexUniformData`/fragment uniform（→ UBO 或 uniform 直接设值）、`DrawGPUIndexedPrimitives`。
- Present：`SDL.GPUPresentMode` → rAF（MAILBOX/_FIFO 差异文档标注为无效设置）。

**桩/panic（Phase 1）**：compute pipeline & compute pass、`BlitGPUTexture`、`DownloadFromGPUTexture`、`BindGPUFragmentStorageBuffers`（若 GL 3.0 无对应，用 uniform/纹理替代或 panic——按实际用到的定）。

## 5. 着色器

- 现状：framework.odin:210-219 以 `#load` 内嵌预编译 SPIRV/DXIL/MSL（Batcher、Textured 等）。
- 需求：新增 GLSL ES 3.00 源码版本（`.glsl` 文件，`#load` 为字符串），用 `when ODIN_OS == .JS` 分支选择；JS/Odin 侧用 `gl.shaderSource` 编译。顶点布局、绑定槽位与现有管线一致。**着色器翻译要覆盖 OFoster 内全部 #load 的着色器，缺一个运行时就 panic。**

## 6. 帧循环与生命周期（对照 spike 已验证模式）

- `App.Run`：.JS 分支下初始化后直接 return，实际工作在导出的 `foster_step(dt)` 里；JS 侧 rAF 驱动（参考 web-spike/main.js:164-178 的 step loop）。
- resize：`ResizeObserver`/window resize → 事件入队 → 更新 Window 尺寸 + GL viewport；DPR 缩放（canvas.width = cssSize * devicePixelRatio）。
- 页面隐藏（visibilitychange）：暂停 rAF 或继续由实现定，验收只要求不崩、不丢输入。
- `SDL.Delay`/时间：用 `performance.now()`，Odin 侧已有时间源则验证 js_wasm32 下可用。

## 7. 存储与资产

- **内嵌资产（GetBasePath）**：Phase 1 推荐把必要资产用 `#load`/`@(data)` 直接编进 wasm（vehicles 的字体走 stb 路径，已验证）；虚拟 FS 的 base 前缀指向内存表。
- **用户数据（GetPrefPath）**：JS 侧虚拟 FS（localStorage 存 JSON 或 IndexedDB 存 blob），提供 open/read/write/remove 的桥函数；Odin 侧暴露与 `core:os` 文件 IO 同形的内部 proc。
- **⚠️ 已知风险**：vehicles 目前直接用 `core:os` 的 `os.read_entire_file_from_path` / `os.write_entire_file` / `os.remove`（vehicles/src/settings.odin:27,44、meta.odin:272,301,306）。需要验证 js_wasm32 下 core:os 的行为：
  - 若 core:os 在 .JS 下映射到 odin.js 的虚拟文件系统且可持久化 → 虚拟 FS 只需接在那个机制上；
  - 若不可用 → 本需求 §7 的桥即为兜底，vehicles 侧需要一个 5 行的 `when ODIN_OS == .JS` 分流（游戏侧改动，见 §9）。

## 8. 输入映射

- 键盘：JS `e.code` → Foster 内部 scancode 的映射表（美式布局 code 是稳定的）；keydown/keyup/重复。
- 鼠标：pointerdown/up/move（换算 canvas 内坐标与 DPR）、wheel（deltaY 归一化为现有滚轮事件粒度）、多键。
- 相对鼠标：Pointer Lock（进入 = 请求锁定；`movementX/Y` 进队列）；退出锁定要同步 Foster 的 RelativeMouseMode 状态，避免状态漂移。

## 9. 游戏侧（vehicles）依赖清单 —— 不属于本需求，但需要知晓

- 音频：vehicles/src/audio_platform_windows.odin / _linux.odin 动态加载 SDL3.dll 用 SDL audio。Web 需要第三个 `audio_platform_web.odin`：WebAudio 桥（JS AudioContext + PCM 队列），模式与 webgl_bridge 相同。
- 存档 IO：见 §7 风险项，可能需要 `when ODIN_OS == .JS` 分流到虚拟 FS。
- 构建：`build.bat` 加 web 目标分支（-target:js_wasm32、拷贝 odin.js/foster.js/index.html、-o:speed）。

## 10. 里程碑（建议实现顺序）

| 里程碑 | 内容 | 验证 |
|---|---|---|
| M0 ✅ | 桥骨架：foster.js + foreign 声明 + canvas 清屏 + step 帧循环 | 验收 1（2026-09-09 通过，见 §0 M0 事实） |
| M1 ✅ | Batcher 矩形：GLSL 着色器 + pipeline/pass 最小实现 | 验收 2（2026-09-09 通过，见 §0 M1 事实） |
| M2 ✅ | 纹理 + Textured 管线 + transfer buffer 上传 | 验收 3（2026-09-10 通过，见 §0 M2-M4 事实） |
| M3 ✅ | 键鼠输入 + resize + 相对鼠标 | 验收 4、5（2026-09-10 通过） |
| M4 ✅ | 虚拟 FS 存档持久化 | 验收 6（2026-09-10 通过） |
| M5（浏览器能力） | 剪贴板、光标、gamepad、文本输入、文件选择 | 2026-10-06 模拟接口回归通过；真实设备/权限待人工验收，WebGPU 未实现 |

## 11. 风险与注意

- `rawptr` 传参依赖 JS 持有 wasm `memory`——必须沿用 spike 的手动实例化（web-spike/main.js:147-152 有注释说明 `odin.runWasm` 不回传 exports 的原因）。
- WebGL2 的 uniform/push-constant 语义与 SDL_GPU 的 PushGPUVertexUniformData 不同（无 push constant），实现时选 UBO 或逐 draw 设 uniform，注意 Batcher 的每帧 uniform 频率。
- 同步 API（剪贴板）与异步浏览器能力的错配已在 §3 给出策略，勿阻塞主线程。
- 每帧从 JS 读 wasm 内存构造字符串的开销：日志路径少用字符串桥。

## 12. 导出与发布指南（OFoster 游戏 → 浏览器/itch.io）

以 vehicles 为参考实现（`vehicles/build_web.bat|sh`、`vehicles/run_web.bat|sh`、`vehicles/web/`，另有游戏侧说明 `vehicles/web/README.md`）。

### 12.1 一次性接入（游戏侧，新增游戏时逐项过）

- **平台文件拆分**：游戏里所有 `core:os` / `core:path/filepath` 调用点收口到成对平台文件（`#+build !js` / `#+build js wasm32, js wasm64p32`），参考 `vehicles/src/platform_io_native.odin|_web.odin`。验收手段：`strings xxx.wasm | grep SDL3` 必须为 0，否则 `WebAssembly.instantiate` 直接失败（静态可达即中毒，见 §0 M0）。
- **存档**：走框架 `OpenUserStorage` 即可，.JS 下自动落到 localStorage 虚拟 FS；不要绕过框架直接 `os.write`。
- **字体**：浏览器不能读盘 → `when ODIN_OS == .JS` 分支用 `#load` 内嵌字体子集（pyftsubset 从源码字符集生成；vehicles 全量 17.8MB → 486KB）。文案新增字符后需重新生成。
- **音频**：SDL audio 在 web 不可用 → 游戏自己的 JS 桥接 `FOSTER_EXTRA_IMPORTS` 钩子（foster.js 预留），Odin 侧每帧 pump 一块 PCM（`vehicles/web/vehicles.js` + `src/audio_platform_web.odin`）。
- **用户数据必须是全局/堆变量**：web 上 App 由框架堆拷贝，`main()` 局部变量会在帧循环期间被栈复用覆写（见 §0 M0）。

### 12.2 构建

```
odin build src -collection:olib=<olib路径> -target:js_wasm32 -o:speed -out:build/web/<游戏名>.wasm
```

产物目录共 5 个文件（资产须全部 `#load` 内嵌进 wasm，不落盘）：

| 文件 | 来源 |
|---|---|
| `<游戏名>.wasm` | 上面的构建命令 |
| `odin.js` | `<odin安装>/core/sys/wasm/js/odin.js`（Odin 官方 wasm 运行时） |
| `foster.js` | `olib/foster/internal/web/foster.js`（OFoster 桥） |
| 游戏桥 `*.js`（可选） | 游戏自己的 JS（如音频桥），经 `FOSTER_EXTRA_IMPORTS` 挂载 |
| `index.html` | 照抄 `vehicles/web/index.html`：`<canvas id="foster">`、`window.FOSTER_WASM = "<游戏名>.wasm"`、按序引游戏桥 → odin.js → foster.js |

### 12.3 本地运行

**必须走 http，不能 file://**（fetch 拿不到 wasm，CORS 拦截）。一键脚本 `run_web.bat|sh`（起服务+开浏览器+退出自动清理），或手动：

```
python -m http.server 8138     # 在仓库根目录
# 打开 http://localhost:8138/build/web/
```

### 12.4 发布到 itch.io

1. 把 `build/web/` 里**全部文件**打成一个 zip（不要包外层文件夹）。
2. itch 项目 → Upload new patch → Kind of project 选 **HTML**。
3. 勾选 **"This file will be played in the browser"**（itch 内嵌 iframe 运行，等同本地 http 服务）。

### 12.5 发布前检查清单

- [ ] `strings <游戏名>.wasm | grep SDL3` 输出为空（无 SDL 导入中毒）。
- [ ] 桌面构建回归通过（同一份代码双端可跑）。
- [ ] 改过 `*.js` 后 `index.html` 里对应 `?v=N` 版本号 +1（浏览器脚本缓存，症状是"改动不生效"）。
- [ ] 音频：首次需一次用户手势（autoplay 策略），确认点击后 BGM 正常。
- [ ] 已知限制可接受：compute/SSBO/离屏 MSAA 不可用、`FillMode.Line` 按填充绘制；GPU 读回已支持，浮点目标取决于扩展（见顶部状态更新）。
- [ ] 调试日志默认隐藏；自查时 URL 加 `?debug=1`，出错自动弹出，F12 始终有完整输出。
