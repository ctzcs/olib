# olib 路线图

以 DragonLib（C#/Foster，`Libs/Engine` 为主）为参照体：已移植了什么、还剩什么、哪些明确不做。
规范见 [CODE_STYLE.md](CODE_STYLE.md)；验证统一用根目录 `check.ps1`。

## 现状（2026-10）

- 三层：`core/`（纯 Odin）→ `foster/`（Foster 移植，唯一运行时）→ `kit/`（扩展能力），外加 `thirdparty/`（clay-odin / odin-imgui）。
- 17 个包带单元测试，共 93 个测试；示例在同级仓库 OFoster_Sample（9 个，含 kit/ui 的截图验收）。
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
| Sprite / 图集 | Rendering/Sprite + Atlas/* | `kit/rendering` | Grid / Kenney XML 图集源 + Aseprite 构建器 |
| 存储路径策略 | GameStorage + LocalStorage | `kit/storage` | 资源根 / 用户存档路径 |
| 2D/3D 相机与场景 | World/* | `kit/world` | Camera2D/3D、Frustum3D、Ray3D、自备 Matrix4（行向量 v*M、D3D 深度）、SceneRouter |
| CLI | CliConsole | `kit/app` | `has_arg` + 后台 stdin 控制台（`cli_open`）；不提供启动模板，直接用 `foster.App` |
| 骨骼动画 | SkeletonAnimator | `kit/animation` | Step/Linear/CubicSpline 采样、palette 传播、blend、蒙皮包围盒 |
| 3D 渲染栈 | Rendering3D | `kit/rendering3d` | Mesh/材质/排序、着色器管线（dxil/spv `#load`）、前向主 pass（方向/点/聚光、透明、蒙皮）、DebugDraw3D、LOD |
| 音频 | Audio | `kit/audio` | 直接绑 `vendor:sdl3`（Foster 本身不含音频）：设备流、WAV 装载、音量 |
| 游戏 UI | Paper UI（替代） | `kit/ui` | clay 布局 + foster 后端：圆角/裁剪/九宫格、位图/MSDF 字体、运行时 SDF 字体（`ui_font_bake_sdf`）与位图烘焙（`ui_font_bake`）、控件/焦点/模态/缩放 |
| JobScheduler | Threading/* | 不移植 | `core:thread.Pool` + `core:sync.Wait_Group` 已覆盖“常驻池 + 完成等待”，见下文并行一节 |

## 后续（按需启动，无固定排期）

### 3D 渲染增量（`kit/rendering3d`）

- `.msl` / `.glsl` 平台补编：目前只有 dxil/spv，Metal 与 WebGL 目标的着色器分发返回 false。
- 阴影 pass + CSM：`DepthOnly` / `DepthOnlySkinned` 着色器已编译入库。
- 后处理与天空：`Tonemap` / `PostBloom` / `PostFxaa` / `PostDepth` / `Sky3D` 的 HLSL 源已拷入
  `kit/rendering3d/shaders/`，尚未编译、未接入 Renderer3D。
- IBL / 环境烘焙。

### UI 增量（`kit/ui`）

文本输入 / IME、Dropdown、富文本与字体 fallback、空间方向导航与焦点自动滚动、拖放、列表虚拟化、
过渡动画、圆角遮罩及完整圆角描边。用法和兼容变更见 [UI README](../kit/ui/README.md)。

### 平台

- Web 目标：foster 已支持 `js_wasm32`（见 foster/tests/webtest）；kit 侧 asset v1 仍是 native-only，
  路线为 `storage_map` + `#load` 预烘焙 blob，前置 `core/encoding` 的 js 兼容。

### 并行

真实帧级并行需求出现时，在 `core/` 做薄封装：Wait_Group 计数 + 等待时调用线程参与执行即可复刻
DragonLib JobScheduler 的主要价值（区间分批 `ScheduleParallel`、每任务 handle 按需加）；ring buffer、异常聚合不需要。

### foster/ 演进

补齐 Foster C# API 面、同步上游新版本，在 `foster/` 内进行，流程见 [PORTING_MAP.md](../foster/docs/PORTING_MAP.md)。

### 工具链（构建期，随 3D 需求一起看）

ShaderCompiler（HLSL → 四后端 + 哈希清单）、FbxToGltf、QoaEncode、msdf-atlas-gen（需要尖角质量时再做）、DataConfig。
目前 `kit/rendering3d/shaders/build_shaders.ps1` 只覆盖 dxil/spv。

## 明确不做

| 项 | 理由 |
|----|------|
| ECS 全线（DragonECS / Engine.ECS / 预制体序列化） | 2026-10 决定不采用 ECS 路线；`thirdparty/oflecs` 已移除（git 历史可找回），`core/entities` 保留但无排期 |
| Mathf（861 行） | `foster/utility.odin` 已覆盖 |
| Paper UI | 由 `kit/ui`（clay）与 odin-imgui 替代 |
| Vector2Int | `core:math` 已有 |
| Roslyn Analyzers | C# 编译器机制，Odin 无对应 |
| 库内示例 / 启动模板 | 库仓库只放库代码与测试；示例在同级仓库 OFoster_Sample，启动直接用 `foster.App`；早期根 main.odin 的环境知识见 git 历史 `1b3dc69` |
