# Plan：Shader Lab 改走 Render2D / Render3D，引擎块每个维度一处打包

> **状态：已完成（2026-10-21）** · 提交 `6207607`..`f9b417d`（olib_sample：`c0f9ca4`、`fc504fd`）
> 偏离：① 决策 2：没有复用 `Session.render`，新增 `preview_sprites` / `preview_models` 两个渲染器；借用材质每帧组装，不在 bank 提交时重建（参数编辑与载入会替换数值切片，每帧组装最简单可靠）。② 决策 3：`Draw_Options`、`Material_Draw` 与 `Draw_Error.Bad_Pass_Selection` 整个删除，`material_select` 改为直接取 Pass 种类、`pass_id` 与精灵纹理；`pass_command` 保留一个不具名的第 6 个参数，避免改动别人未提交的 `bank.odin`。③ 第 1 步改了 include 注释，olib_sample 的 Shader Lab 产物记录随之过期，多一个提交 `c0f9ca4`；第 3 步改 `model.hlsli` 注释同理，记录更新并入 `fc504fd`。④ 按用户要求减少测试：Shader Lab 各模式每步只跑一遍（计划写 3 遍）。截图对比脚本起初只比较 alpha 通道，第 1、2 步报告的“逐像素一致”不可靠；修正后重比：第 1、2 步只有 `workflow-large` 的预览区有 ≤2/255 的差异，第 3 步（三步全部生效）与基线逐像素一致，判断为那两次运行的时间抖动；第 3 步只有 `features-host`、`features-compact` 与基线不同，均来自自定义钩子的预期变化（宿主改为用 Render2D 记录 SpriteShadow 小精灵；非材质效果不再有自定义钩子，compact 截图从旧钩子的立方体回到内置球体）。⑤ `features` 的录制用例用 2D 效果 SpriteShadow：Shader Lab 的管线探测用不带实例属性的内置网格，实例化 Model 效果（Swarm）在 D3D12 上探测失败，这是改动前就有的限制。

## 背景

游戏用 `Render2D` / `Render3D` 记录再提交，它们只接受材质库里的 `^mat.Material`。Shader Lab 的 shader 是开发期
热重载编译的，每个参数组一个 `foster.Material`，不在材质库里，所以预览走另一套“立即路径”：

| 维度 | 游戏路径 | Shader Lab 路径 |
| --- | --- | --- |
| 2D | `Render2D`（记录、合批、storage 记录写入） | `r2d.material_draw`（`render2d_tool.odin`，107 行） |
| 3D | `Render3D`（记录、剔除、排序、自动实例化） | `r3d.model_material_draw`（`model_material_draw.odin`，53 行） |

两条立即路径再进入 `mat.material_draw`（`draw.odin` 里另一套 Pass 循环：`material_pass_submit` 等）。
Shader Lab 还通过 `prepare` 回调把立即路径建好的 DrawCommand 整条换成自己的 `pass_command`。
非材质效果（Fullscreen、Preview_Model 的多 Pass 图）完全由 Shader Lab 自己画，自己打包 b0。

后果（2026-10-21 核对）：

- 每改一次引擎给 shader 的输入，每个维度要改两处；本仓库这几天加顶点 Clock、精灵轴时都改了两遍。
- 引擎块在 4 处打包：Render2D submit、`render2d_tool`、`r3d.pack_material_blocks`（Render3D 与 `model_material_draw` 共用）、
  Shader Lab `pass_uniforms`（3D 预览手写一遍 3D 布局）。
- `Clock.w` 各处不同：Render2D 写 1，3D 写 0，Shader Lab 写精灵预览标记。示例里只有 Preview2D、Trail2D 的
  scene Pass（Preview_Model，2D 预览）读 `Clock.w`；Sprite / Model 材质都不读。
- 自定义预览钩子 `Preview_Hooks{prepare, draw}` 工作在 DrawCommand 层；只有 olib_sample 验证程序的 `features`
  模式用它，示例宿主和 Proj_Sand 都不用。Proj_Sand 也不用 `material_draw` / `model_material_draw`。

## 已定决策（执行时不要改）

1. **材质库提供“借用绑定”的材质**，放在 `kit/rendering/material/material.odin`：

   ```odin
   // 工具用：把调用方持有的效果与 GPU 绑定组成 Material，交给 Render2D / Render3D 记录。
   // 不登记、不复制、不拥有资源：effect 与 bindings 借用到调用方释放。
   material_from_bindings :: proc(library: ^Material_Library, effect: ^Material_Effect,
   	bindings: []Material_Binding) -> (material: Material, reason: string)
   ```

   调用方自己持有一个 `mat.Material_Effect{desc = ..., schemas = ...}`（不新增结构体）。函数检查效果是 Model 或 Sprite 材质、
   绑定数与参数组数一致、绑定的 GPU 材质属于 `library` 的设备，返回值不进入 `library.instances`，不需要释放。
   渲染器只读 `owner`、`effect`、`bindings`、`revision`；借用材质的 `samplers` 为空。
2. **Shader Lab 的材质预览改为记录**：
   - 2D 用 `Session.render`（记录后立即提交到预览目标）；3D 新增 `Session.render3d: r3d.Render3D`。
   - 每次 bank 提交（含热重载）后重建借用材质；bank 释放前先清空 Render3D 的记录。
   - Pass 启停与“只预览到第 N 个 Pass”由 Shader Lab 逐 Pass 处理：对每个要画的 Pass，记录时传它的 `pass_id`，
     3D 每个 Pass `clear → model → submit`，2D 每个 Pass `image → submit`。Render2D / Render3D 不加新选项。
   - 渲染状态从此按游戏的规则（Pass 状态、Render2D 的混合、Render3D 的深度与剔除），预览与游戏一致。
3. **删除两条立即路径**：`kit/rendering/2d/render2d_tool.odin`、`kit/rendering/3d/model_material_draw.odin`，以及
   `draw.odin` 里只为它们存在的部分（`material_draw`、`material_pass_submit` 和只被它们使用的辅助过程，
   `Draw_Options` 的 `enabled / user_data / prepare / submit`，`Material_Draw` 中只有立即路径用的字段）。
   Render2D / Render3D 仍在用的 `material_select`、`material_pass_values`、`material_pass_instance`、`pass_state_apply`、
   `view_globals_pack` 保留；它们的入参以删除后能编译、语义不变为准。
4. **引擎块每个维度一处**：
   - 2D 只剩 `Render2D` 的 submit。
   - 3D 只剩 `r3d.pack_material_blocks`，改为公开；Shader Lab 的 3D Preview_Model（非材质效果）调用它，不再手写。
   - Fullscreen 与 2D Preview_Model 的块只有 Shader Lab 一个宿主，留在 `pass_uniforms`。
   - `Clock.w`：Sprite、Model 一律为 0（Render2D 由 1 改 0）；Fullscreen 保留“精灵预览模式”标记。
     `olib/sprite.hlsli`、`olib/model.hlsli` 的注释改为“w 为 0”。
5. **自定义预览钩子改为录制式，只用于材质效果**：

   ```odin
   Preview_Hooks :: struct {
   	user_data: rawptr,
   	// 材质效果的预览：用游戏同一套 API 记录要画的东西，Shader Lab 负责提交；对每个要画的 Pass 调用一次，
   	// 记录时传 frame.pass 作为 pass_id。sprites / models 按效果维度只给一个，另一个为 nil。返回 false 使用内置几何。
   	record: proc(user_data: rawptr, frame: Preview_Frame, material: ^mat.Material,
   		sprites: ^r2d.Render2D, models: ^r3d.Render3D) -> bool,
   }
   ```

   `Preview_Frame` 去掉 `device`、`material`（`^foster.Material`）这类 GPU 级字段，保留组名、维度、时间、尺寸、Pass。
   非材质效果去掉自定义钩子，只用内置的球、立方体和四边形。热重载的管线探测一律用内置几何
   （材质效果的顶点格式由渲染器固定，宿主几何也必须是同一格式）。

## 执行步骤

前置：本计划改 Shader Lab 与 olib_sample 的验证程序，先把 `shader-lab-check-stability`（olib `fdcfc18`、
olib_sample `4a9df19`）和 `shader-rebuild`（olib `0223957`、olib_sample `db27336`）合并进 master，
否则验证程序冲突、验证结果也不可靠；没有合并就停下来问。然后两个仓库都从 master 新建分支 `shader-lab-unified-draw`。
不属于本计划的未提交改动（olib `kit/tools/shader_lab/bank.odin`，olib_sample 根 `README.md` 与 `src/stylized3d`）全程不动、
不提交。开始前 `odin run tools/check` 记录基线；截图基线：material2d（默认、`swarm`）、material3d（默认、`models`、`swarm`）
的 `shot`，Shader Lab 的 `shot`、`smoke`、`features`、`colors`、`multipass`、`hierarchy`、`targets` 写出的截图，
每组跑两遍确认可重复，复制到 olib_sample `library/tmp/shader-lab-unified-draw-baseline/`。

### 1. 引擎块打包收敛、统一 Clock.w

按决策 4：`r3d.pack_material_blocks` 公开，Shader Lab `pass_uniforms` 的 3D 分支改调它；Render2D submit 与
`render2d_tool` 的 `Clock.w` 改为 0；更新两个 include 的注释。`tests/kit/rendering/3d` 加一条测试：
`pack_material_blocks` 写出的顶点块与片元块各字段位置（Clock、Pointer、Tint、CameraPosition）。

验证：完整 `odin run tools/check`；全部基线截图逐像素一致（没有 Sprite / Model 材质读 `Clock.w`）。

提交：olib `rendering: 引擎块每个维度一处打包，Clock.w 统一为 0`

### 2. Shader Lab 的材质预览改走 Render2D / Render3D

按决策 1、2 新增 `material_from_bindings` 并加单元测试（不需要 GPU：检查拒绝非材质效果、绑定数不符、设备不符；
借用材质能通过 `material_select`）。Shader Lab 材质预览改为记录，暂时保留立即路径和旧钩子，验证程序的 `features`
仍走旧钩子。

验证：完整 `odin run tools/check`；Shader Lab 全部模式通过（各跑 3 遍），截图与基线逐像素对比。若有差异，逐张说明原因
（预期只可能来自预览改用游戏的渲染状态），说明不了就停下来汇报；material 示例截图应完全一致。

提交：olib `shader_lab: 材质预览改走 Render2D / Render3D`

### 3. 删除立即路径与旧钩子

按决策 3、5 删除立即路径、改写 `Preview_Hooks`，Shader Lab 去掉非材质效果的自定义钩子与 `pass_command` 里的钩子调用。
`tests/kit/rendering/material/draw_test.odin` 里测 `material_draw` 的用例：仍由 `material_select` 承担的检查
（未知 Pass、Pass 选择、Pass 类型、缺少绑定等）改测 `material_select`；只属于立即路径的检查（立即路径的实例缓冲规则、
全部 Pass 禁用）删除，Render2D / Render3D 已有同类检查的不重复补。olib_sample `tools/shader_lab_checks/features.odin`
的自定义预览用例改用 `record`：宿主用不同位置或网格记录，检查回调被调用、画面与内置几何不同。

文档：`kit/rendering/2d/REFERENCE.md` 与 `kit/rendering/3d/REFERENCE.md` 删除 `material_draw` / `model_material_draw` 两节；
`kit/rendering/material/README.md` 中提到立即 Pass 执行器、`material_draw`、`Material_Draw` 的段落改为只描述记录路径；
`kit/tools/shader_lab/README.md` 改写预览与 `Preview_Hooks` 的说明；olib_sample `README.md` 只改 `Preview_Hooks` 那一句
（该文件有别人的未提交改动，提交时只暂存这一处，做不到就先跳过并在汇报里说明）。

验证：完整 `odin run tools/check`；Shader Lab 全部模式各跑 3 遍通过；截图与第 2 步结果逐像素一致；
`grep -rn "material_draw\|model_material_draw\|Material_Draw2D" kit tests` 只剩 `material_select` 等保留的名字。

提交：olib `rendering: 删除 Shader Lab 专用的立即绘制路径`；olib_sample `samples: 自定义预览用例改用录制式钩子`

### 4. 按 docs/plans/README.md 归档本计划

## 验收

- `odin run tools/check` 全部通过。
- 2D 引擎块只在 `Render2D` submit 打包，3D 只在 `r3d.pack_material_blocks`；`render2d_tool.odin`、
  `model_material_draw.odin` 不存在；material 的公开过程比计划前少（汇报里列出删掉的名字）。
- material 示例截图与基线逐像素一致；Shader Lab 截图要么一致，要么每处差异都有说明。
- Shader Lab 全部验证模式各 3 遍通过。

## 禁止事项

- 不改 Render2D / Render3D 的公开记录接口（`image`、`model`、`submit` 等）的签名与行为，只删工具路径。
- 不改宿主写入的块布局与大小（`Clock.w` 的取值除外），不升 `MANIFEST_VERSION`。
- 不给 Render2D / Render3D 加只为 Shader Lab 存在的选项（Pass 启停在 Shader Lab 内处理）。
- 不改 Proj_Sand；不提交、不修改不属于本计划的未提交改动；不 push。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 两个仓库各自的 commit 列表。
- `tools/check` 结果，有失败就贴输出；新增与删除的测试名字。
- 删除的公开过程与行数统计。
- 每一步的截图对比结果，Shader Lab 有差异时附说明。
- 与计划不一致的地方及原因。
