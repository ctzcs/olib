# Plan：effect 改叫 Shader，补后处理模板与做法说明

## 背景

`.oshader` 文件里写的是 `Shader "Trail2D" { ... }`，代码和文档里同一个东西却叫 effect / 效果（`fx.Effect_Desc`、
`effect_order`、`mat.Material_Effect`、`Material.effect`、Shader Lab 的“效果”菜单）。而代码里的 shader 一词又指每个参数组
编译出的 GPU 程序（Shader Lab 的 `s.shaders`、`dev.Session`）。同一个东西两个名字，同一个名字两样东西，读代码和文档都要先换算。

对照 Unity：Shader（资源，内含多个 Pass）→ Material（参数值）。olib 只有一条渲染路径，后端差异由 shadercross 处理，
用不上 Unity 按平台 / 管线 / 画质挑选实现的 SubShader，因此不加这一层，层级是 Shader → Pass。

另外，游戏里做全屏后处理的方式（场景画到 Target，再用一个 Sprite 材质铺满屏幕画出去）目前只有 stylized3d 的代码可参考，
没有模板和文档；本计划顺带补上。不新增多 Pass 图执行器。

改名范围（不含 stylized3d 与 build）：含 effect 的标识符约 1100 处，其中局部变量 `effect` / `effects` / `selected_effect`
占大半，集中在 Shader Lab 与它的验证程序；中文“效果”约 150 处，集中在 material、Shader Lab 与 shader 的 README。

## 已定决策（执行时不要改）

1. **术语表**（代码、注释、文档、界面统一按此）：

   | 词 | 指什么 |
   | --- | --- |
   | Shader | 一个 `.oshader`（`Shader "Name"`）：`sh.Shader_Desc` + 参数组 + 每个参数组一份 HLSL。分两类见下 |
   | 材质 Shader | Pass 全是 `Sprite` 或全是 `Model`，用 `mat.Material` 挂在物体上画（原“材质效果”） |
   | 全屏 Shader | Pass 是 `Fullscreen` / `Preview_Model` 的多 Pass 图，目前只在 Shader Lab 里运行（原“图像效果”） |
   | Pass、参数组（Schema）、Material | 不变 |
   | program | 每个参数组编译出的 GPU 顶点 + 片元程序；类型仍是 `foster.Shader` / `dev.Session` |
   | 后处理 | 游戏里的全屏处理：一个 `Draw Sprite` 的材质 Shader 画在场景 Target 上 |

2. **包搬家**：`kit/rendering/shader/effect`（package effect，别名 `fx`）并进 `kit/rendering/shader` 本身（package shader，
   import 别名 `sh`）；`effect.odin` 改名 `shader.odin`。测试 `tests/kit/rendering/shader/effect/` 移到 `tests/kit/rendering/shader/`。
   `shader/lang`、`shader/dev` 改为相对 import `..`（tools/shaders 不带 collection 编译，路径保持相对）。

3. **改名表**：

   | 现在 | 改成 |
   | --- | --- |
   | `fx.Effect_Desc` | `sh.Shader_Desc` |
   | `effect_order / effect_validate / effect_sort / effect_clone / effect_dispose` | `shader_order / shader_validate / shader_sort / shader_clone / shader_dispose` |
   | `effect_is_material / effect_is_model / effect_is_sprite / effect_instancing` | `shader_is_material / shader_is_model / shader_is_sprite / shader_instancing` |
   | `lang.Document.effect` | `lang.Document.shader` |
   | `mat.Material_Effect`、`Material.effect`、`material_from_bindings` 的 `effect` 参数 | `mat.Material_Shader`、`Material.shader`、`shader` |
   | `mat.Material_Shader_Code` | `mat.Material_Program_Code` |
   | `Draw_Error.Not_Material_Effect / Not_Instanced_Effect` | `Not_Material_Shader / Not_Instanced_Shader`（序号不变） |
   | Shader Lab：`s.shaders`、`shader_count`、`shader_used`（GPU 程序） | `s.programs`、`program_count`、`program_used` |
   | Shader Lab：`s.effects`、`selected_effect`、`Effect_Runtime`、`select_effect`、`effect_*` | `s.shaders`、`selected_shader`、`Shader_Runtime`、`select_shader`、`shader_*` |
   | Shader Lab 文件 `effects.odin`、`effect_panel.odin` | `shader_runtime.odin`、`shader_panel.odin` |
   | 界面“效果”“选择效果” | “Shader”“选择 Shader” |
   | 错误文本里的 effect（如 `Unknown material effect`） | shader；断言这些文本的测试同步改 |

   局部变量一并改：指资源的 `effect` → `shader`；原来指 GPU 程序的 `shader` 先改成 `program`，保证同一文件里一个词一个意思。
   含义无关的名字不动（`sidebar_effective`、消息测试里的 `Spawn_Effect`）。

4. **不变的**：`.oshader` 语法；编译清单与材质文件 JSON 里的 `"effect"` 键（Odin 字段改名，用 `json:"effect"` 标签保留原键）；
   `MANIFEST_VERSION`；`Shader_Binaries`、`Pass_Binaries`、`shader_pick`、`shader_driver_supported`（它们说的就是编译产物，
   也是 stylized3d 未提交代码正在用的名字）；`mat.Pass_Id`（改为 `sh.Pass_Id` 的别名）；编译产物不需要重新生成。

5. **后处理模板**：`kit/tools/shader_lab/templates/Post_Process.oshader`，`Shader_Template.Post_Process`，2D 工作区菜单“新建后处理”。
   内容：`Draw Sprite`、`SpriteTexture _image`（场景颜色，`[Filter(Linear)]`）、`Blend Opaque`，示范暗角、饱和度与色调三个参数，
   没有 `[Instance]` 字段；Output 只有位置与 UV（满足 D3D12 规则）。

6. **做法说明**写在 `kit/rendering/material/README.md` 新的“全屏后处理”一节：场景画到 Target → `r2d.texture` 把它铺满窗口并套上
   后处理材质 → submit；需要深度时 `material_set_texture` 绑深度附件（不能是正在写的深度目标）；两遍处理多建一张中间 Target；
   需要上一帧时游戏保留两张 Target 交替；精灵纹理的采样规则。`kit/rendering/README.md` 的速查加一行指过去。

## 执行步骤

前置：本计划基于 rendering-usability 分支（尚未合并 master），两个仓库都从它新建分支 `shader-rename`。
不属于本计划的未提交改动（olib `kit/tools/shader_lab/bank.odin`，olib_sample 根 `README.md` 与 `src/stylized3d`）不提交；
`bank.odin` 和 `README.md` 里需要改名的行，提交时用“HEAD 版本套同一改名”的内容暂存，工作区保留别人的改动。
stylized3d 的工作区代码必须一直能编译（tools/check 会编译它）。开始前 `odin run tools/check` 记录基线；截图基线：
material2d / material3d 的 `shot`，Shader Lab 的 `shot`、`features`、`multipass`、`targets`，复制到 olib_sample
`library/tmp/shader-rename-baseline/`。

### 1. 描述层搬家与改名

按决策 2、3 移动包并改描述层的类型与过程名，全仓库同时改引用（material、2d、3d、lang、dev、Shader Lab、tools、tests、示例）；
JSON 键按决策 4 保留。

验证：完整 `odin run tools/check`。

提交：olib `shader: 效果描述层并进 kit/rendering/shader，Effect_Desc 改叫 Shader_Desc`

### 2. 材质库与渲染器的 effect 改名

`Material_Effect`、`Material.effect`、`Material_Shader_Code`、`Draw_Error` 两个值、`material_from_bindings` 参数、
r2d / r3d / lang / dev 里指资源的字段与局部变量、错误文本。

验证：完整 `odin run tools/check`。

提交：olib `rendering: 材质库与渲染器里的 effect 改叫 shader`

### 3. Shader Lab 改名

先把指 GPU 程序的 shader 改成 program，再把指资源的 effect 改成 shader；文件改名；界面文字。olib_sample 的验证程序
（`tools/shader_lab_checks`）与 `src/shader_lab` 跟随。

验证：完整 `odin run tools/check`；Shader Lab 各模式各跑一遍通过。

提交：olib `shader_lab: effect 改叫 shader，编译程序改叫 program`；olib_sample `samples: Shader Lab 验证程序跟随改名`

### 4. 文档与注释统一术语

全部 README / REFERENCE / 注释按决策 1 的术语表改；`kit/rendering/shader/README.md`（原 effect 的 README）开头写清
“一个 `.oshader` 就是一个 Shader”和两类 Shader；`kit/rendering/README.md` 目录表与依赖方向更新；`prompts/new-project.md`
里提到 material 的一句如有涉及同步。

验证：`grep` 确认 kit、tools、tests、prompts 与 olib_sample（stylized3d 除外）里不再有指资源的 effect / 效果
（`docs/plans/archive/` 不改）。

提交：olib `docs: 统一用 Shader 称呼 .oshader`；olib_sample 有改动则 `samples: 文档跟随 Shader 改名`

### 5. 后处理模板与做法说明

按决策 5、6 加模板、菜单项与文档；`tests/kit/tools/shader_lab/templates_test.odin` 覆盖新模板；
olib_sample 的 `features` 检查新建模板的步骤加上后处理。

验证：完整 `odin run tools/check`；`shader_lab features` 通过；最后一轮截图与基线逐像素对比（改名不应改变任何画面），
新模板的预览截一张看效果。

提交：olib `shader_lab: 后处理模板与做法说明`；olib_sample `samples: features 检查新建后处理模板`

### 6. 按 docs/plans/README.md 归档本计划

## 验收

- `odin run tools/check` 全部通过；stylized3d 未提交代码仍能编译。
- 代码里不再有 `Effect_Desc`、`Material_Effect`、`effect_order` 等旧名；`kit/rendering/shader/effect/` 不存在。
- 编译产物与 JSON 格式不变，没有重新生成的 Compiled 文件。
- 截图与基线逐像素一致；后处理模板能新建、编译并预览。

## 禁止事项

- 不加 SubShader，不改 `.oshader` 语法，不升 `MANIFEST_VERSION`，不改 JSON 键。
- 不改 `Shader_Binaries`、`Pass_Binaries`、`shader_pick`、`shader_driver_supported` 等 stylized3d 在用的名字。
- 不新增多 Pass 图执行器或其他新功能；改名之外的行为不变。
- 不改 Proj_Sand；不提交、不修改不属于本计划的未提交改动；不 push；不合并 master。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 两个仓库各自的 commit 列表。
- `tools/check` 结果，有失败就贴输出。
- 改名表的实际执行情况与残留（如有意保留的旧名）。
- 截图对比结果与后处理模板的预览截图。
- 与计划不一致的地方及原因。
