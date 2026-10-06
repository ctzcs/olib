# olib ← DragonLib 移植路线图

以 DragonLib（`Libs/Engine` 为主）为参照体的差距清单与排期。
当前基线：`core/`（handle/entities/encoding/tween/debug/profiler）+
`engine/`（asset/world/messaging）+ `thirdparty/`（clay-odin/odin-imgui/oflecs），
9 包 32 测试全绿。规范见 [CODE_STYLE.md](CODE_STYLE.md)。

依赖关系总览：

```
原则：不改 OFoster —— 引擎侧能力全部在 olib 内拼装。
3D 数学直接用 core:math/linalg（Matrix4 全套现成：inverse/determinant/
translate/from_trs/from_quaternion/look_at），投影矩阵等少数缺口在
engine/world 内做薄助手。
P2 SkeletonAnimator ──→ Dasset 数据层（可先行）──→ 3D 渲染栈
P2 3D 渲染栈 ──→ Camera3D（依赖 core:math/linalg）
其余各项相互独立，可按需插队
```

## P0 —— 2D 游戏支撑（近期）

目标：用 olib + ofoster 能把一个 2D 游戏做起来。

| # | 项目 | DragonLib 来源 | 落点 | 规模 | 验收 |
|---|------|----------------|------|------|------|
| 1 | Sprite / SpriteAtlas | Rendering/Sprite.cs + Atlas/*（~380 行） | 新包 `engine/rendering`（sprite.odin + atlas.odin） | 中 | 图集加载/切图/Batcher 绘制单测 + 像素校验 |
| 2 | 图集源 | Atlas/AsepriteAtlasBuilder + KenneyXmlAtlasSource | 同上（atlas_aseprite.odin / atlas_kenney.odin） | 小 | 两种格式的解析单测 |
| 3 | GameStorage | Core/Storage/GameStorage + LocalStorage（~150 行） | 新包 `engine/storage`（resources + user data 路径策略） | 小 | `%APPDATA%` 路径解析、桌面读写单测 |
| 4 | JobScheduler 评估 | Threading/*（~330 行） | 先出结论再决定：`core:thread`/`core:sync` 够用则薄封装进 `core/thread`，否则完整移植 | 评估 | 评估记录写进本文档；若实现：并行任务单测 |

## P1 —— 引擎骨架补全

| # | 项目 | DragonLib 来源 | 落点 | 前置 |
|---|------|----------------|------|------|
| 5 | Camera3D / Frustum3D / Ray3D | World/（~370 行） | `engine/world`（camera3d.odin 等） | 无——3D 数学用 `core:math/linalg` 的 Matrix4；透视/正交投影做薄助手随包携带 |
| 6 | GameApp 启动模板 | GameApp.cs + CliConsole.cs | `engine/app`（CLI 参数处理、可选调试控制台） | 无 |

## P2 —— 3D 大件（单独立项，游戏侧需要时启动）

| # | 项目 | DragonLib 来源 | 说明 |
|---|------|----------------|------|
| 8 | Dasset 模型格式（数据层） | Assets/Dasset/*（读写/模型/蒙皮，~8 文件） | 纯数据层不依赖渲染，可先做；blob 进 asset 管线（自定义 Importer） |
| 9 | SkeletonAnimator | Animation/SkeletonAnimator.cs（~180 行） | 依赖 #8 的蒙皮数据 |
| 10 | 3D 渲染栈 | Rendering/ 主体（Renderer3D/ShadowMap/CSM/Tonemap/材质/顶点，~15 文件）+ MeshGenerator | 依赖 #5 和 ofoster 的着色器/渲染目标能力；最大的单块 |

## olib 之外但卡脖子（不改 OFoster 前提下）

- **音频**：OFoster 没有音频模块（2026-10 核实）。按"不改 OFoster"原则，
  路线是 olib 侧新包直接绑定后端（SDL3 audio 或 miniaudio），native 起步。
- （可选）web 目标：asset v1 native-only；web 路线 = `storage_map` + `#load`
  预烘焙 blob，前置 `core/encoding` 的 js 兼容。
- OFoster 自身的演进（如补齐 Foster C# API 面）由 OFoster 仓库自行决定，
  olib 只消费其已提交的 API（Matrix3x2 构造/乘法已在 e51ceb8 收编）。

## 工具链（Tools/，不排期，随需启动）

ShaderCompiler（HLSL→四后端+哈希清单，配 EmbeddedShaderMaterial 思路）、
FbxToGltf、QoaEncode、msdf-atlas-gen、DataConfig。
均属构建期工具，与 P2 一起看。

## 明确不做

| 项 | 理由 |
|----|------|
| **ECS 全线**（DragonECS / Engine.ECS / 预制体序列化） | 2026-10 决定不采用 ECS 路线；`thirdparty/oflecs` 与 `core/entities` 保留但无排期 |
| Mathf（861 行） | ofoster `utility.odin` 已覆盖 |
| Paper UI | clay-odin / odin-imgui 替代 |
| SlotMap 系 / GrowArray | `core/handle` 更全 |
| Vector2Int | `core:math` 已有 |
| Roslyn Analyzers | C# 编译器机制，Odin 无对应 |
| 根 main.odin / 示例 | 库仓库保持纯净（2026-10 决定）；环境知识在 git 历史 `1b3dc69` |

## 已完成

- asset 管线 v1（.meta/Library/blob/manifest，打包零改动）→ `engine/asset`
- Camera2D / SceneRouter → `engine/world`（Matrix3x2 构造/乘法用 ofoster
  已提交的 API，e51ceb8）
- CommandQueue / BroadcastChannel → `engine/messaging`
- 目录三层化（core/engine/thirdparty）+ 编码规范（CODE_STYLE.md）
