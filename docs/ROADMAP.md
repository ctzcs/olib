# olib 路线图

以 DragonLib（C#/Foster，`Libs/Engine` 为主）为参照体：已移植了什么、还剩什么、哪些明确不做。
规范见 [CODE_STYLE.md](CODE_STYLE.md)；验证统一用 `odin run tools/check`。

## 现状（2026-10）

- 三层：`core/`（纯 Odin）→ `foster/`（Foster 移植，唯一运行时）→ `kit/`（扩展能力），外加 `thirdparty/`（纯 Odin clay-odin；odin-imgui 是 Dear ImGui C++ 库的绑定，只带 Windows x64 预编译库）。
- 17 个包带单元测试，共 93 个测试；示例在同级仓库 olib_sample（9 个，含 kit/ui 的截图验收）。
- 原则：foster/ 保持 Foster API 对齐，本地修改登记到 [LOCAL_CHANGES.md](../foster/docs/LOCAL_CHANGES.md)；
  扩展能力在 kit/ 拼装，kit 不封装、不别名 foster（见 CODE_STYLE「foster 与 kit 的边界」）。
- 3D 数学直接用 `core:math/linalg`；投影矩阵等少数缺口在 `kit/world` 做薄助手。

## 已完成

| 能力 | DragonLib 来源 | 落点 | 备注 |
|------|----------------|------|------|
| 句柄池 | SlotMap 系 / GrowArray | `core/handle` | array / fixed / growing / virtual 四种存储，比 SlotMap 更全 |
| 消息 | CommandQueue / BroadcastChannel | `core/messaging` | 单消费者队列 / 延迟一帧广播 |
| 模型格式数据层 | Dasset | `core/dasset` | 比特兼容 DragonLib v4，v1~v4 读兼容，坏文件防御 |
| 资源管线 v1 | Asset 管线 | `kit/asset` | .meta 管身份、Library 管派生、blob 为边界、manifest 打包零改动 |
| Sprite / 图集 | Rendering/Sprite + Atlas/* | `kit/rendering/2d` | Grid / Kenney XML 图集源 + Aseprite 构建器 |
| 存储路径策略 | GameStorage + LocalStorage | `kit/storage` | 资源根 / 用户存档路径 |
| 2D/3D 相机与场景 | World/* | `kit/world` | Camera2D/3D、Frustum3D、Ray3D、自备 Matrix4（行向量 v*M、D3D 深度）、SceneRouter |
| CLI | CliConsole | `kit/app` | `has_arg` + 后台 stdin 控制台（`cli_open`）；不提供启动模板，直接用 `foster.App` |
| 骨骼动画 | SkeletonAnimator | `kit/animation` | Step/Linear/CubicSpline 采样、palette 传播、blend、蒙皮包围盒 |
| 3D 渲染机制 | Rendering3D | `kit/rendering/3d` | Mesh 上传、泛型渲染队列（不透明前到后 / 透明后到前）、字节码按驱动选择（spv/dxil/msl，SDL_shadercross 编译）、std140 打包、DebugDraw3D、LOD；光照/材质/着色器的参考实现在 olib_sample `forward3d` |
| 音频 | Audio | `kit/audio` | 直接绑 `vendor:sdl3`（Foster 本身不含音频）：设备流、WAV 装载、音量 |
| 游戏 UI | Paper UI（替代） | `kit/ui` | clay 布局 + foster 后端：圆角/裁剪/九宫格、位图/MSDF 字体、离线多通道 MSDF 字体与旧位图兼容（`ui_font_bake`）、控件/焦点/模态/缩放 |
| JobScheduler | Threading/* | 不移植 | `core:thread.Pool` + `core:sync.Wait_Group` 已覆盖“常驻池 + 完成等待”，见下文并行一节 |

## 后续（按需启动，无固定排期）

### 3D（`kit/rendering/3d`）

- Web 目标的 3D 着色器：Web 后端是 WebGL + 手写 GLSL ES、命名 uniform、不用 UBO；
  SDL_shadercross 不输出 GLSL，3D 上 Web 时需要另写一套。

### UI 增量（`kit/ui`）

富文本与字体 fallback、空间方向导航（按二维位置选邻近控件）、文本框选区与多行、
过渡动画、圆角遮罩及完整圆角描边。单行文本输入 / 输入法候选框、下拉框、拖放、列表虚拟化与
焦点自动滚动、状态驱动动效原语（追随 / 冲击 / 进出场）已完成；过渡动画指布局尺寸与位置变化的自动过渡。只按玩家 UI 的需要排期；编辑器和开发工具用 odin-imgui，
不为它们补树、Dock 等控件。用法和兼容变更见 [UI README](../kit/ui/README.md)。

### 平台

- Web 目标：foster 已支持 `js_wasm32`（见 foster/tests/webtest）；kit 侧 asset v1 仍是 native-only，
  路线为 `storage_map` + `#load` 预烘焙 blob，前置 `core/encoding` 的 js 兼容。

### 并行

真实帧级并行需求出现时，在 `core/` 做薄封装：Wait_Group 计数 + 等待时调用线程参与执行即可复刻
DragonLib JobScheduler 的主要价值（区间分批 `ScheduleParallel`、每任务 handle 按需加）；ring buffer、异常聚合不需要。

### foster/ 演进

补齐 Foster C# API 面、同步上游新版本，在 `foster/` 内进行，流程见 [PORTING_MAP.md](../foster/docs/PORTING_MAP.md)。

### 工具链（构建期，随 3D 需求一起看）

FbxToGltf、QoaEncode、DataConfig。字体使用 msdf-atlas-gen 离线生成，见 [字体资产生成](../tools/fonts/README.md)。
ShaderCompiler 的编译部分已由 `tools/shaders` 覆盖（`odin run tools/shaders`，SDL_shadercross，HLSL → spv/dxil/msl，
`-dir:` 指定任意目录）；哈希清单需要增量编译时再加。

## 明确不做

| 项 | 理由 |
|----|------|
| ECS 全线（DragonECS / Engine.ECS / 预制体序列化） | 2026-10 决定不采用 ECS 路线；`thirdparty/oflecs` 已移除（git 历史可找回），`core/entities` 保留但无排期 |
| 库内 PBR / IBL / 阴影 / CSM / 后处理 / 天空 | 外观由游戏决定，库只做机制；参考前向渲染器见 olib_sample `src/forward3d`，DragonLib 的 DepthOnly/Tonemap/Post*/Sky3D HLSL 源见 git 历史（`dcff6d8` 之前） |
| Mathf（861 行） | `foster/utility.odin` 已覆盖 |
| Paper UI | 玩家 UI 由 `kit/ui`（clay）替代，编辑器与工具 UI 由 odin-imgui 替代 |
| Vector2Int | `core:math` 已有 |
| Roslyn Analyzers | C# 编译器机制，Odin 无对应 |
| 库内示例 / 启动模板 | 库仓库只放库代码与测试；示例在同级仓库 olib_sample，启动直接用 `foster.App`；早期根 main.odin 的环境知识见 git 历史 `1b3dc69` |
