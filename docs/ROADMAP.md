# olib ← DragonLib 移植路线图

以 DragonLib（`Libs/Engine` 为主）为参照体的差距清单与排期。
当前基线：`core/`（handle/entities/encoding/tween/debug/profiler）+
`engine/`（asset/world/messaging）+ `thirdparty/`（clay-odin/odin-imgui/oflecs），
9 包 32 测试全绿。规范见 [CODE_STYLE.md](CODE_STYLE.md)。

依赖关系总览：

```
原则：foster/ 保持 Foster API 对齐；引擎侧能力优先在 engine/ 拼装。
3D 数学直接用 core:math/linalg（Matrix4 全套现成：inverse/determinant/
translate/from_trs/from_quaternion/look_at），投影矩阵等少数缺口在
engine/world 内做薄助手。
P2 SkeletonAnimator ──→ Dasset 数据层（可先行）──→ 3D 渲染栈
P2 3D 渲染栈 ──→ Camera3D（依赖 core:math/linalg）
其余各项相互独立，可按需插队
```

## P0 —— 2D 游戏支撑（近期）

目标：用 olib（含内置 foster/）能把一个 2D 游戏做起来。

| # | 项目 | DragonLib 来源 | 落点 | 规模 | 验收 |
|---|------|----------------|------|------|------|
| 1 | Sprite / SpriteAtlas | Rendering/Sprite.cs + Atlas/*（~380 行） | 新包 `engine/rendering`（sprite.odin + atlas.odin） | 中 | 图集加载/切图/Batcher 绘制单测 + 像素校验 |
| 2 | 图集源 | Atlas/AsepriteAtlasBuilder + KenneyXmlAtlasSource | 同上（atlas_aseprite.odin / atlas_kenney.odin） | 小 | 两种格式的解析单测 |
| 3 | GameStorage | Core/Storage/GameStorage + LocalStorage（~150 行） | 新包 `engine/storage`（resources + user data 路径策略） | 小 | `%APPDATA%` 路径解析、桌面读写单测 |
| 4 | ~~JobScheduler 评估~~ **已评估（2026-10，不移植）** | Threading/* | 结论：`core:thread.Pool` + `core:sync.Wait_Group` 覆盖"常驻池 + 完成等待"；相比 DragonLib 仅缺三点——等待时调用线程参与执行（工作窃取）、`ScheduleParallel` 区间分批、每任务 handle。等真实帧级并行需求出现时在 `core/thread` 做薄封装（Wait_Group 计数 + 调用线程参与即可复刻主要价值，ring buffer/异常聚合不需要） | — | — |

## P1 —— 引擎骨架补全

| # | 项目 | DragonLib 来源 | 落点 | 前置 |
|---|------|----------------|------|------|
| 5 | Camera3D / Frustum3D / Ray3D | World/（~370 行） | `engine/world`（camera3d.odin 等） | 无——3D 数学用 `core:math/linalg` 的 Matrix4；透视/正交投影做薄助手随包携带 |
| 6 | GameApp 启动模板 | GameApp.cs + CliConsole.cs | `engine/app`（CLI 参数处理、可选调试控制台） | 无 |

## P2 —— 3D 大件（单独立项，游戏侧需要时启动）

| # | 项目 | DragonLib 来源 | 说明 |
|---|------|----------------|------|
| 8 | ~~Dasset 模型格式（数据层）~~ **已完成（2026-10，`engine/dasset`）** | 比特兼容 DragonLib v4 布局的读写（贴图/骨架/蒙皮顶点/PBR 材质/动画剪辑，v1~v4 读兼容，坏文件防御） |
| 9 | ~~SkeletonAnimator~~ **已完成（2026-10，`engine/animation`）** | 采样（bind pose 填充+channel 覆盖，Step/Linear/CubicSpline、四元数最短弧）、palette 传播、advance_time、blend_poses、蒙皮包围盒 |
| 10 | ~~3D 渲染栈~~ **已完成（2026-10，`engine/rendering3d`）** | Mesh 上传、材质状态、渲染排序 + **着色器管线**（dxil/spv 入库 #load、按驱动分发）+ Renderer3D 前向主 pass（方向光/点光/**聚光灯**/透明混合/蒙皮 palette）+ **DebugDraw3D**（Line/Aabb/Sphere/Frustum/Axis/Grid/Skeleton；foster/ 无线拓扑，走朝向相机的四边形展开复用 DebugLine3D 着色器）+ **LOD**（Lod_Selector 滞回阈值 + 泛型 Model_Lod）。**剩余增量**：.msl/.glsl 平台补编、阴影 pass + CSM（DepthOnly 已备）、Tonemap/后处理（DragonLib 已有 PostBloom/Fxaa/Sky3D HLSL 源可移植）、天空盒、IBL/环境烘焙 |

## 平台与 foster/ 后续演进

- ~~**音频**~~ **已完成（2026-10，`engine/audio`）**：直接绑 `vendor:sdl3`
  （默认回放设备流 f32/队列模式、WAV 装载转换、音量缩放入队、样本级裁剪）。
- （可选）web 目标：asset v1 native-only；web 路线 = `storage_map` + `#load`
  预烘焙 blob，前置 `core/encoding` 的 js 兼容。
- Foster 移植自身的演进（如补齐 Foster C# API 面）在 `foster/` 内进行，
  引擎侧能力优先在 `engine/` 拼装（Matrix3x2 构造/乘法已在原仓库 e51ceb8 收编）。

## 工具链（Tools/，不排期，随需启动）

ShaderCompiler（HLSL→四后端+哈希清单，配 EmbeddedShaderMaterial 思路）、
FbxToGltf、QoaEncode、msdf-atlas-gen、DataConfig。
均属构建期工具，与 P2 一起看。

## UI 路线（2026-10 追加）

- **已完成**：clay v0.14 布局与 foster/ 后端；统一圆角、矩形嵌套裁剪、位图/MSDF 材质、完整贴图/裁切图集 UV、图片背景容器与对称九宫格、Unicode 字距、预乘透明色。
- **控件与输入**：Theme、Button/Label/Toggle、Image/ImageButton、ProgressBar/Slider、行/列/面板/滚动区/模态遮罩；松开确认、指针捕获、禁用态、顺序焦点导航、输入消费、模态作用域、viewport 缩放。
- **验证**：CPU 回归覆盖布局/翻译/合批与交互，`examples/game_ui` 提供遗迹场景、HUD、技能栏、格子背包、暂停菜单及自动交互验收；原设置页和距离场着色器探针保留在 `examples/ui_gallery`。用法和兼容变更见 [UI README](../engine/ui/README.md)。
- **后续增量**：文本输入/IME、Dropdown、富文本与字体 fallback、空间方向导航与焦点自动滚动、拖放、列表虚拟化、过渡动画、圆角遮罩及完整圆角描边。

## 明确不做

| 项 | 理由 |
|----|------|
| **ECS 全线**（DragonECS / Engine.ECS / 预制体序列化） | 2026-10 决定不采用 ECS 路线；`thirdparty/oflecs` 与 `core/entities` 保留但无排期 |
| Mathf（861 行） | `foster/utility.odin` 已覆盖 |
| Paper UI | clay-odin / odin-imgui 替代 |
| SlotMap 系 / GrowArray | `core/handle` 更全 |
| Vector2Int | `core:math` 已有 |
| Roslyn Analyzers | C# 编译器机制，Odin 无对应 |
| 根 main.odin / 示例 | 库仓库保持纯净（2026-10 决定）；环境知识在 git 历史 `1b3dc69` |

## 已完成

- asset 管线 v1（.meta/Library/blob/manifest，打包零改动）→ `engine/asset`
- Camera2D / SceneRouter → `engine/world`（Matrix3x2 构造/乘法用 foster/
  已提交的 API，e51ceb8）
- CommandQueue / BroadcastChannel → `engine/messaging`
- **P0-1** Sprite/SpriteAtlas + Grid/Kenney 图集源 + Aseprite 构建器 → `engine/rendering`
- **P0-2** GameStorage 路径策略 → `engine/storage`
- **P0-3** JobScheduler 评估（不移植，见 P0 表）
- **P1-4** Camera3D/Frustum3D/Ray3D + 自备 Matrix4（行向量 v*M、D3D 深度）→ `engine/world`
- **P1-5** has_arg + CliConsole（messaging 队列转主线程）→ `engine/app`
- **P2-6** Dasset 数据层 → `engine/dasset`
- **P2-7** SkeletonAnimator → `engine/animation`
- **P2-8** 3D 数据/队列层 → `engine/rendering3d`（着色器管线边界见表 10）
- **音频** → `engine/audio`（vendor:sdl3）
- 目录三层化（core/engine/thirdparty）+ 编码规范（CODE_STYLE.md）
