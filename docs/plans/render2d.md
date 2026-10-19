# Plan：2D 统一到 r2d.Render2D（含 UI 迁移）

## 背景

2D 现在有两套绘制：

| | 用途 | 问题 |
| --- | --- | --- |
| `r2d.Sprite_Renderer` + `sprite_draw` | olib 材质精灵 | 要建 renderer、`begin/end/flush`；中途提交的时机调用方控制不了；普通效果的 tint 在 uniform 里，颜色不同就断批；多 Pass 交错提交几乎合不了批 |
| `foster.Batcher` | kit/ui、gizmo2d、Shader Lab 面板、示例与游戏的 HUD | 不认 olib 材质（多 Pass、`[Instance]`、Clock）；切换材质不分批，kit/ui 靠 `ui_material_boundary` 手工往 `Batches` 里插批次 |

讨论（2026-10-19～20）后的结论：2D 只保留一套，在 foster 的 Mesh + Material + DrawCommand 上实现 `r2d.Render2D`，用法与 foster Batcher 一致（先记录、最后 submit、矩阵栈），原生使用 olib 材质；kit 内的 2D 绘制（含 UI）全部迁移过来。3D 按同样模式做 `r3d.Render3D`，另写计划（本计划不动 3D）。

调用方（2026-10-20 核对，不含 build/ 副本）：

- olib：`kit/ui/ui_backend.odin`、`kit/gizmo/transform2d.odin`、`kit/tools/shader_lab/`（effects / panel / preview / session / material_preview / config / theme）、`kit/asset/asset.odin`（仅注释）、`tools/new-game/template/`（`core/ui.odin.in`、`core_editor/editor.odin.in`、`editor/main.odin.in`、`README.md.in`）、`tests/kit/rendering/2d/`、`tests/new_game/`。
- olib_sample：使用 foster Batcher 的 basic、batcher、book_ui、feature、forward3d、game_ui、gizmo2d、hotreload、material3d、spatial、ui_gallery、ui_motion；使用 r2d 精灵的 material2d；2D 材质效果只有 `src/shader_lab/shaders/SpriteShadow.oshader`。
- Proj_Sand：`src/game/main.odin`、`src/view/ui.odin`、`src/view/view.odin`（当前在 `creature-prototype` 分支，有 2 个未提交改动）。
- olib_web_preview：`src/editor/editor.odin`、`src/game/ui.odin`（不是 git 仓库；Web 发布用 `publish_web.bat`）。
- 帧动画容器 `Sprite` / `sprite_*` 在上述仓库里没有外部调用方。

foster 的约束（核对过源码）：

- 默认材质 Batcher、Textured、Msdf 带手写 GLSL（`foster/assets/shaders/*.glsl`），Web 可用。Batcher 顶点格式为 `BatcherVertex`（位置、UV、颜色 UByte4、mode UByte4），Shader 的 `Type`（mode）选择 Normal / Wash / Fill。
- Web 后端（`foster/internal/web/foster.js`）只支持两种 uniform：顶点槽 0 的 64 字节矩阵（`u_matrix`）和片元槽 0 的一个 float（`u_distance_range`），不支持 storage buffer。
- `DrawCommand` 有 `VertexStorageBuffers` / `FragmentStorageBuffers`；`StorageBufferInit / UploadTyped` 可用；Shader 需声明 `StorageBufferCount`。

## 已定决策（执行时不要改）

1. **`r2d.Render2D` 是 2D 唯一的绘制入口**，放在 `kit/rendering/2d/render2d.odin`，基于 `foster.Mesh` + `foster.Material` + `foster.DrawCommand`，不使用 `foster.Batcher`。foster 的 Batcher 保留在 foster 里，不改不删。
2. **记录与提交**：绘制调用只记录，`submit` 是唯一的提交点：上传顶点与实例数值、按记录顺序画完、清空。没有 `begin / end / flush`。
3. **命名**：`Render2D` 的操作不带前缀；包里其他类型仍带前缀（`atlas_*`、`sprite_buffer_*`、`animation_set_*`）。接口如下（参数细节由执行者按 foster Batcher 对应函数定，保持同样的语义和默认值）：

   ```odin
   r2d.init(r: ^Render2D, library: ^mat.Material_Library) -> string   // "" 为成功；设备取自 library
   r2d.dispose(r)
   r2d.push_matrix(r, m: foster.Matrix3x2, relative := true) / r2d.push_matrix_trs(...) / r2d.pop_matrix(r)
   r2d.push_scissor / pop_scissor、push_blend / pop_blend、push_sampler / pop_sampler、push_mode / pop_mode
   r2d.image(r, frame: foster.Subtexture, transform, color, origin = {}, material: ^mat.Material = nil,
       values: ^mat.Instance_Values = nil, pass_id = "") -> mat.Draw_Error
   r2d.texture(r, texture: ^foster.Texture, transform, color, ...同 image)
   r2d.quad / quad_texture / rect / line / circle / triangle   // 覆盖 kit/ui、gizmo2d、Shader Lab 用到的图元；可选 material
   r2d.buffer(r, material, buf: ^Sprite_Buffer, count, texture) -> mat.Draw_Error   // 常驻实例缓冲，按记录顺序提交
   r2d.submit(r, view: r2d.View) -> mat.Draw_Error
   View :: struct { target: foster.DrawableTarget, time, delta_time: f32, frame: u64, pointer: [2]f32 }
   ```

   记录时能查出的错误（材质未加载、不是 2D 效果、`pass_id` 不存在、设备不一致）就地返回；只能在提交时发现的错误由 `submit` 返回第一个。
4. **顶点格式与 foster 的 `BatcherVertex` 一致**（直接用 `foster.BatcherVertex` / `foster.BatcherVertexFormat()`）。**tint 放在顶点颜色**。mode 字节：默认材质表示 Normal / Wash / Fill；带 `[Instance]` 字段的 olib 效果表示这个精灵在实例数值 buffer 里的 32 位下标。
5. **材质统一为 `^mat.Material`**：
   - `mat.Shader_Binaries` 增加可选 `glsl`；Web 驱动选 glsl，没有时该效果在 Web 上不可用（加载或绘制返回明确错误，不崩溃）。
   - 材质库首次需要时自动登记两个内置效果：`Sprite_Default`（foster Batcher Shader）与 `Text_Msdf`（foster Msdf Shader），四种字节码与 GLSL 都取自 foster 现有资产，不重新编译。
   - 内置效果沿用 foster 的 uniform 布局（顶点 b0 = 64 字节矩阵；`Text_Msdf` 片元 b0 = distance range），在 `Effect_Desc` 上标记，`Render2D` 按标记写 uniform；其余效果按 olib 约定（片元 b0 = Clock / Pointer / Tint，b1 = 参数）。
   - 新增 `mat.material_create(library, effect_name) -> (^Material, string)`，在代码里创建材质实例（每种字体一个 `Text_Msdf` 实例）。`material = nil` 时用库的 `Sprite_Default`。
6. **2D 效果的 Shader 约定由 lang 统一提供**：lang 生成 `OlibSpriteInput` 与 `olib_sprite(input)`（返回位置、UV、顶点色、实例数值），作者写 `struct Input { OlibSpriteInput Sprite; };`，不再自己写顶点输入布局。tools/shaders 为 2D 效果编译：
   - **批量变体**（总是生成）：`BatcherVertex` 输入；`[Instance]` 字段从顶点 storage buffer（`StructuredBuffer<float4>`，SDL GPU 约定的顶点 storage buffer 寄存器）按 mode 下标读取，不插值传给片元；
   - **缓冲变体**（效果声明 `Instanced` 时生成）：单位四边形角点 + 实例记录，供 `r2d.buffer` 使用。
   清单与 `Material_Effect` 同时保存两组变体。2D 效果的 `[Instance]` 字段不再要求 `Instanced`；3D 规则不变。
7. **实例数值**：`Render2D` 自持一个 storage buffer。带 `[Instance]` 字段的效果，每个精灵写入完整的一组值（材质值 + `values` 覆盖），下标从 1 开始，0 保留。`submit` 时上传一次。带实例字段的效果在 Web 上不可用。
8. **合批**：同一批的条件是 target、材质（指针相同且 uniform / 贴图相同）、帧贴图、采样器、混合、裁剪、mode 类别一致，并设单批上限。索引缓冲在初始化时一次建好（参考 foster-samples Froggymark 的 `RenderBatchCustom`）。材质切换总会正确分批，`ui_material_boundary` 删除。
9. **多 Pass**：`submit` 时对连续使用同一材质的一段记录，按 Pass 顺序整段提交（先全部 pass1，再全部 pass2），应用各 Pass 的状态。`pass_id` 只画该 Pass。2D 效果默认按单 Pass 写，不为多 Pass 增加其他接口。
10. **Clock 在 `submit` 时写入**（olib 效果的片元 b0，来自 `View`），调用方不再每帧设时间。
11. **Shader Lab 保留一个立即绘制的工具入口**：`r2d.material_draw(r, effect, bindings, draw)`（取代 `sprite_material_draw`，借用 `Render2D` 的 GPU 资源，保留 `pass_limit`、启用列表、prepare / submit 回调），写进 REFERENCE.md，不出现在 README 正文。
12. **删除**：`Sprite_Renderer`、`Sprite_View`、`sprite_draw`、`sprite_draw_texture`、`sprite_begin / end / flush`、`sprite_draw_buffer`、`Sprite_Material_Draw`、`sprite_material_draw`，以及旧的精灵合批与自动实例化实现。不保留过渡别名。
13. **帧动画改名**：`Sprite` → `Animation_Set`，`Sprite_Animation` → `Animation`，`Sprite_Frame` → `Animation_Frame`，`sprite_*` → `animation_set_*`；文件 `sprite.odin` → `animation_set.odin`。
14. **初始化返回原因**：`r2d.init`、`sprite_buffer_init` 返回 `string`（"" 为成功）。`model_buffer_init` 留给 3D 计划。
15. **`Sprite_Item.padding` 不再作为可用字段暴露**：Odin 支持时改为空白字段 `_`，否则保留并在注释里说明，由执行者核实后选择。
16. **kit/ui 迁移**：`ui_draw` / `ui_render` 改接 `^r2d.Render2D`；文字用 `Text_Msdf` 材质实例（从 `Render2D` 持有的材质库创建），UI 的初始化接口尽量不变。
17. **规则写进文档**：`docs/CODE_STYLE.md` 的 foster 与 kit 边界一节加一条：kit 内 2D 绘制统一使用 `r2d.Render2D`，不使用 `foster.Batcher`；理由是要原生支持 olib 材质、`[Instance]` 与常驻实例缓冲；foster Batcher 留给直接使用 foster 的代码。

## 执行步骤

前置：
- olib、olib_sample 工作区干净，从各自 master 新建分支 `render2d`；`odin run tools/check` 全部通过。
- Proj_Sand 当前在 `creature-prototype` 分支且有未提交改动：**先停下问用户**在哪个分支上改、未提交改动如何处理，得到答复前不动 Proj_Sand。
- olib_web_preview 不是 git 仓库：改动无法提交，汇报时列出改过的文件。
- 截改动前的基准图到各仓库的 `library/screenshots/`（同名覆盖），另把副本放 `library/tmp/render2d-before/` 供对比，验收后删除：material2d（普通与 `swarm`）、ui_gallery、game_ui、gizmo2d、book_ui、Shader Lab 的 2D 预览；Web：`publish_web.bat` 后用内置浏览器打开 olib_web_preview 截一张。

### 1. 材质：GLSL 字节码、内置效果、代码创建实例

按决策 5：`Shader_Binaries.glsl`、`shader_pick` 支持 Web 驱动；`Sprite_Default` / `Text_Msdf` 内置效果（foster uniform 布局标记）；`material_create`。此步不改任何调用方。测试：Web 驱动选 glsl、缺 glsl 时的错误、内置效果登记一次、`material_create` 的成功与失败。

提交：olib `material: 支持 GLSL 字节码、内置 Sprite_Default / Text_Msdf 效果与代码创建材质`

### 2. Render2D 核心（默认材质）

按决策 1～4、8、10、14 实现 `render2d.odin`：记录、矩阵 / 裁剪 / 混合 / 采样器 / mode 栈、全部图元、合批、`submit`。此步只支持内置材质（olib 效果在下一步接入），旧的 `Sprite_Renderer` 暂时并存。测试：栈的压入弹出、记录错误码、合批边界（材质、贴图、裁剪、混合切换）、单批上限、空提交。

提交：olib `rendering2d: 新增 Render2D（记录后统一提交，默认材质）`

### 3. 2D 效果切换到新约定（一次性切换）

着色器布局一变，旧的精灵路径就无法运行，所以这一步整体完成：
- lang 与 tools/shaders 按决策 6 生成和编译两种变体；shader/dev 热重载支持 storage buffer 与变体；`effect_validate` 放开 2D 的 `[Instance]`。
- `Render2D` 接入 olib 效果：实例数值 buffer（决策 7）、多 Pass 分组（决策 9）、`r2d.buffer`、`r2d.material_draw`（决策 11）。
- 删除决策 12 列出的旧接口；`sprite_buffer_init` 改为返回原因并接材质。
- 迁移 `SpriteShadow.oshader` 与 olib_sample material2d（含 swarm），重新编译 shader_lab 示例着色器；Shader Lab 的 2D 预览改用 `r2d.material_draw`。
- 测试：实例数值的下标与默认值填充、多 Pass 分组顺序、两种变体的清单、旧接口已删除。

提交：olib `rendering2d: 2D 效果改用 Batcher 顶点布局与 storage buffer 实例数值，删除 Sprite_Renderer`；olib_sample `material2d/shader_lab: 迁移到 Render2D 与新的 2D 效果约定`

### 4. kit 内 Batcher 使用方迁移

按决策 16：kit/ui（删除 `ui_material_boundary`）、kit/gizmo `transform2d.odin`、Shader Lab 的面板与预览、`kit/asset/asset.odin` 注释、`tools/new-game/template/`。同步迁移 olib_sample 里使用 kit/ui 或 gizmo 的示例（basic、batcher 两个 foster 演示示例保持 foster Batcher）。复查：`grep -rn "foster\.Batcher" --include=*.odin kit tools` 没有结果（`tools/new-game/template` 的 `.in` 文件一并检查）。

提交：olib `kit: UI、gizmo2d 与 Shader Lab 改用 Render2D`；olib_sample `samples: 跟随 kit/ui 与 gizmo 改用 Render2D`

### 5. 外部项目迁移

- Proj_Sand：按前置里用户的答复在指定分支修改，跑它自己的 `check.ps1`，单独提交 `view: 改用 r2d.Render2D`。
- olib_web_preview：修改后 `play.bat` 运行一次，并 `publish_web.bat` 构建 Web 版本（不提交，汇报改动文件）。

### 6. 帧动画改名与 Sprite_Item

按决策 13、15。更新测试与所有引用。

提交：olib `rendering2d: 帧动画 Sprite 改名 Animation_Set，Sprite_Item 不暴露填充字段`

### 7. 文档

- `kit/rendering/2d/README.md` 重写为业务向（Render2D 用法、材质与 `[Instance]`、常驻缓冲、帧动画、图集），工具入口与 Shader 约定细节放新文件 `REFERENCE.md`。
- 更新 `kit/rendering/README.md`（最小示例与 API 速查）、`material/README.md`（GLSL、内置效果、`material_create`）、`shader/lang/README.md`（2D 约定与两种变体）、`kit/tools/shader_lab/README.md`、`kit/ui/README.md`、`tools/shaders/README.md`、`prompts/new-project.md`，以及决策 17 的 `docs/CODE_STYLE.md`。
- 复查：`grep -rn "Sprite_Renderer\|sprite_draw\|sprite_begin\|sprite_material_draw\|Sprite_View\|foster\.Batcher" --include=*.md . ../olib_sample` 只允许出现在 `docs/plans/archive/`、CODE_STYLE 的规则说明，以及 basic / batcher 示例的说明里。

提交：olib `docs(rendering2d): Render2D 文档与 kit 不用 foster Batcher 的规则`；olib_sample 有文档改动时单独提交

### 8. 按 docs/plans/README.md 归档本计划

## 验收

- `odin run tools/check` 全部通过（含 olib_sample 的编译与测试、new_game 回归）。Proj_Sand 的 `check.ps1` 通过。
- 截图与基准对比（UI 按 [UI 像素与采样约定](../../kit/ui/README.md#最终像素采样与清晰度验收) 取最终输出）：ui_gallery、game_ui、book_ui、gizmo2d 与改动前一致；material2d、Shader Lab 2D 预览效果一致；不一致处逐一说明原因。
- material2d：记录每帧 Draw 数，混合不同 tint 的普通精灵应合成一批；swarm 仍是 1 次 Draw，CPU 耗时与改动前同量级。
- Web：olib_web_preview 的 UI 文字、纯色、贴图正常显示；带 `[Instance]` 的效果在 Web 上返回明确错误而不崩溃。
- 第 4、7 步的 grep 复查符合要求。

## 禁止事项

- 不改 3D 绘制接口（`model_draw`、`Model_Buffer` 等），只改 3D 与材质共用、且本计划必须改的部分。
- 不修改或删除 foster 的 Batcher；不改 foster。若 Web 验证证明必须改 foster（如 uniform 映射），停下汇报，经用户同意后按 LOCAL_CHANGES 规则登记。
- 不新增本计划以外的渲染功能：自定义网格、四边形外扩、跨材质重排、Web 上的 storage buffer 替代方案都不做。
- 不统一图集来源（aseprite / kenney / grid）的入口，留作后续。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 各仓库的 commit 列表；olib_web_preview 改动的文件列表。
- `odin run tools/check` 与 Proj_Sand `check.ps1` 结果，失败就贴输出。
- 截图对比结论与 material2d 的 Draw 数、CPU 耗时。
- Web 验证结果。
- 与计划不一致的地方及原因。
