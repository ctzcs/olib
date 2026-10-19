# Plan：重做 kit/rendering/3d 的公开 API

> **状态：已完成（2026-10-19）** · 提交 `45cfdbd`..`adc5dfb`（olib_sample：`03af8a9`..`fa29fcd`）
> 偏离：① 前置步骤要提交的实例缓冲改动已由用户以另一种实现提交为 `5525113`（单缓冲按块拼接），本计划没有再提交；改动前的基准检查与截图是在该提交之前的工作区上跑的。② `mat.std140_write_matrix` 改为接受任意 64 字节矩阵（`$M where size_of(M) == 64`）：material 被 `tools/shaders` 以相对路径引用，不能 import `kit/world`。③ LOD：只变换 min/max 对平移、旋转、均匀缩放其实是正确的（包围球的球心和半对角线都保留），只有“旋转 + 非均匀缩放”会低估；修法改为用 8 个角点求变换后的包围球（新增私有 `lod_world_sphere` / `lod_sphere_screen_height`），而不是计划写的 8 角点 AABB。④ 顺带把 `debug_draw_expand`、`debug_line_format` 也改为私有。⑤ `model_draw` 没有另加 nil 网格检查，`mat.material_draw` 已返回 `.Missing_Mesh`。⑥ 文档复查：`model_material_draw` 除 REFERENCE.md 外，还作为底层入口的指引保留在 3D README 文件表、2D README、material README 与 shader_lab README。⑦ material2d 的 `swarm_init` 去掉了用不到的 device 参数。⑧ 截图：material3d_swarm 与 forward3d 与改动前逐像素一致；material3d 的颜色随真实帧时间变化，同一版本两次运行的差异像素数也相同，肉眼对比一致。

## 背景

`kit/rendering/3d` 经过“只保留机制”（archive/rendering3d-mechanism-only.md）和材质系统接入两轮改动后，
公开 API 是两代设计叠在一起，README 316 行，比 2D 复杂得多。问题出在接口本身：

| 问题 | 现状 |
| --- | --- |
| 纯转发的别名 | `shader3d_driver_supported` / `shader3d_pick_code` 只是转调 `mat.shader_driver_supported` / `mat.shader_pick`，同一件事两个名字 |
| 通用工具放在 3D 包 | `std140_write_vec4` / `std140_write_matrix` 与 3D 无关，kit/gizmo、shader_lab、forward3d 都为它 import 3D 包 |
| 名字里重复“3d” | 包已是 `r3d`，还叫 `r3d.mesh3d_upload`、`r3d.shader3d_pick_code`；文件也叫 `mesh3d.odin`、`queue3d.odin` |
| `Model` 名不副实 | `Model{mesh, material}` 只是一个 primitive 的材质槽，README 要专门解释“不是模型导入器”；按值传入，只为凑参数 |
| 2D/3D 不对称 | 2D：`sprite_draw(renderer, material, frame, transform, view)`；3D：`model_draw(Model{mesh, material}, transform, view)` |
| 预览参数混进业务结构 | `Model_View.pass_limit` 只有 Shader Lab 用；`Model_Material_Draw` 又把 View 的字段全抄一遍 |
| 槽数要手工对齐 | `model_buffer_init(..., slots = SLOTS)` 让调用方定义一个必须等于效果 `[Instance]` 字段数的常量，错了到绘制时才报 `.Instance_Mismatch` |
| 错误码不准 | `model_draw_buffer` 传 nil 缓冲返回 `.Instance_Mismatch` |
| 能上传、不能画 | `mesh3d_upload` 接受蒙皮 primitive，但 `model_draw` 只支持静态顶点格式，画蒙皮网格得到错乱结果而不是错误 |
| 内部类型公开 | `Shader3D_Debug_Line_Pair` / `shader3d_debug_line_init` 只给 debug_draw 用；`Vertex_Matrix_Block` 结构体没有任何调用方 |
| LOD 包围盒 bug | `model_lod_select` 注释说“取 8 角点变换后的盒”，实际只变换了 min/max，旋转后包围盒错误 |

调用方（2026-10-19 核对，不含 build/ 下的副本）：

- olib：`kit/gizmo/render3d.odin`（pick/driver/std140）、`kit/tools/shader_lab/`（`effects.odin` std140 与 `pack_vertex_matrix_block`、`material_preview.odin` 的 `model_material_draw`、`session.odin` / `shapes.odin` 的 `mesh3d_upload`）、`tests/kit/rendering/3d/rendering3d_test.odin`。
- olib_sample：`src/forward3d/`（手写 HLSL 路径：pick/driver/std140/`pack_vertex_matrix_block`/`pack_joint_palette`/队列/调试线/`mesh3d_*`）、`src/book_ui/renderer3d.odin`（pick/driver/`pack_vertex_matrix_block`）、`src/material3d/`（`Model`/`Model_View`/`model_draw`/`Model_Buffer`）。
- 其他仓库（Proj_Sand、Proj_TD、Proj_Cell、olib_*_preview、olib_template_validation）没有 import 3D 包。
- 文档：`kit/rendering/{README,2d/README,3d/README,material/README}.md`、`kit/tools/shader_lab/README.md`、`olib_sample/src/material3d/README.md`。

## 目标 API

业务代码（材质路径）只需要这些：

```odin
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"

// 网格：dasset primitive -> foster.Mesh
r3d.mesh_upload(&mesh, device, &primitive, "hero") -> bool
r3d.mesh_dispose(&mesh)

// 每帧一份视图
view := r3d.View{target = scene, view_projection = world.camera3d_view_projection(&camera),
	time = t, delta_time = dt, frame = n}

// 逐个绘制（与 sprite_draw 同序：材质在前，几何其次，变换，视图，可选 pass_id）
err := r3d.model_draw(material, &mesh, transform, view)            // mat.Draw_Error
err  = r3d.model_draw(material, &mesh, transform, view, "outline")

// 实例化：槽数从材质读，调用方不再定义常数
buffer: r3d.Model_Buffer
r3d.model_buffer_init(&buffer, material, capacity = 1_000_000) -> bool
values := make([][4]f32, count*buffer.slots)
hue := mat.instance_slot(material, "hue")
mat.instance_array_set(values, buffer.slots, i, hue, {0.7, 0, 0, 0})
r3d.model_buffer_upload(&buffer, items, values = values) -> bool
err = r3d.model_draw_buffer(material, &mesh, &buffer, count, view)
r3d.model_buffer_dispose(&buffer)
```

机制工具（手写 HLSL 的渲染器、gizmo、Shader Lab 用）：

```odin
// 移到 material 包（与 shader_pick 放在一起）
mat.std140_write_vec4(buf, offset, v)
mat.std140_write_matrix(buf, offset, m)
mat.shader_driver_supported(driver)                  // 已有，删除 r3d 转发
mat.shader_pick(driver, {spv, dxil, msl})            // 已有，删除 r3d 转发

// 留在 r3d：3D 顶点 b0 与骨骼约定
r3d.VERTEX_MATRIX_BLOCK_SIZE
r3d.pack_vertex_matrix_block(buf, wvp, world) -> bool
r3d.pack_joint_palette(buf0, buf1, palette) -> bool

// 留在 r3d，名字不变
r3d.Render_Queue($T) / queue_submit / queue_sort / queue_clear / queue_dispose / queue_view_depth
r3d.Lod_Selector / lod_selector_* / lod_screen_height / Model_Lod($T) / model_lod_*
r3d.Debug_Draw_3D / debug_draw_*
r3d.mesh_static_format() / r3d.mesh_skin_format()

// Shader Lab 专用的底层入口（写进 REFERENCE.md，不在 README 正文）
r3d.Model_Material_Draw{mesh, world_matrix, view: View, pointer, pass_limit, options, instances, instance_count}
r3d.model_material_draw(device, effect, bindings, draw) -> mat.Draw_Error
```

## 已定决策（执行时不要改）

1. **删除 `Model` 结构体。** `model_draw` / `model_draw_buffer` 直接接 `material: ^mat.Material, mesh: ^foster.Mesh`，参数顺序同 2D：材质、几何、（变换 / 缓冲与数量）、视图、`pass_id`。入口处检查 `mesh == nil` 返回 `.Missing_Mesh`（若 `mat.material_draw` 已检查则不重复）。
2. **`Model_View` 改名 `View`，去掉 `pass_limit`。** `pass_limit` 只留在 `Model_Material_Draw`。`Model_Material_Draw` 内嵌 `view: View`，不再逐字段重复 target/view_projection/time/delta_time/frame。
3. **`model_buffer_init(buf, material, capacity, name := "")`**：设备取 `material.owner.device`（不再单独传 device），槽数取材质效果的 `[Instance]` 字段数，存进 `buf.slots`；材质为 nil、效果未声明 instanced 或字段数超过 `MAX_INSTANCE_FIELDS` 返回 false。槽数计算放在 material 包新的公开函数 `mat.instance_slot_count(material) -> int`（各参数组的 `[Instance]` 字段数不一致时返回 -1，与 `instance_slot` 的规则一致）。
4. **2D 同步对称**：`sprite_buffer_init` 改为同样从材质取槽数（`sprite_buffer_init(buf, material, capacity, name)`），否则这次改完 2D/3D 又不对称。这是本计划唯一的 2D 改动。
5. **`model_draw_buffer` 传 nil 或未初始化的缓冲返回 `.Instance_Buffer_Required`**（不再是 `.Instance_Mismatch`）。`sprite_draw_buffer` 同步。
6. **蒙皮网格明确报错**：`mat.Draw_Error` 新增 `Unsupported_Mesh`（“模型材质路径只支持静态顶点格式”），`model_draw` / `model_draw_buffer` 按网格顶点格式步长不等于 `dasset.DASSET_VERTEX_STRIDE_STATIC` 返回它。不新增蒙皮的材质路径支持。
7. **`std140_write_vec4` / `std140_write_matrix` 移到 `kit/rendering/material/std140.odin`**，3D 包内部改用 `mat.` 版本。`shader3d_driver_supported` / `shader3d_pick_code` 直接删除，调用方改用 `mat.shader_driver_supported` / `mat.shader_pick`。
8. **去掉名字和文件名里的“3d”**：`mesh3d_upload/dispose/static_format/skin_format` → `mesh_*`；文件 `mesh3d.odin` → `mesh.odin`、`queue3d.odin` → `queue.odin`、`lod3d.odin` → `lod.odin`、`uniforms3d.odin` → `uniforms.odin`、`debug_draw3d.odin` → `debug_draw.odin`。`shader3d.odin` 并入 `debug_draw.odin`（只剩调试线着色器），`Shader3D_Debug_Line_Pair` / `shader3d_debug_line_init` 改为 `@(private)`。`Debug_Draw_3D` 与 `debug_draw_*` 不改名（gizmo 里也有 2D 调试绘制，保留区分）。
9. **删除无调用方的 `Vertex_Matrix_Block` 结构体**，保留 `VERTEX_MATRIX_BLOCK_SIZE` 与 `pack_vertex_matrix_block`。
10. **修 LOD 包围盒**：`model_lod_select` 按注释所说变换 8 个角点再取 AABB，补一个旋转 90° 的测试。
11. **`Model_Item` / `Model_Buffer` / `Render_Queue` / `Lod_Selector` / `Model_Lod` 不改名**（与 `Sprite_Item` / `Sprite_Buffer` 对称；其余名字本身没问题）。
12. **不保留过渡别名**，旧名字直接消失。
13. **README 重写为业务向，目标 120 行左右**，结构对齐 2D README：模型绘制 → 实例化 → 排序 / LOD / 调试线 → 自写 Shader 的接口约定（b0/b1/space2，链接 shader/lang 与 forward3d）。现在的“写一个着色器：从 HLSL 到画面”教程、“约定与常见错误”和“模型材质执行”压缩后移到同目录新文件 `REFERENCE.md`（做法同 hotreload 的 `2b5da61`）。

## 执行步骤

前置：工作区里有上一轮未提交的改动（olib：2D/3D 实例缓冲拆成两个 GPU 缓冲，涉及 `sprite_buffer.odin`、`model_buffer.odin`、`model_material_draw.odin`、`material/draw.odin` 及两份测试；olib_sample：`src/material2d/main.odin`）。先运行 `odin run tools/check`，通过后单独提交为 `rendering: 实例缓冲拆为实例记录与字段值两个缓冲，按内存布局直接上传`（olib_sample 的改动一并按其内容提交）；不通过就停下汇报，不在本计划里修。之后在 master 上新建分支 `rendering3d-api`。olib_sample 的改动在它自己的仓库单独提交。

### 1. 通用工具归位，删除转发

按决策 7：新建 `material/std140.odin`，删除 r3d 的 std140 与 shader3d 转发；更新 `kit/gizmo/render3d.odin`、`kit/tools/shader_lab/effects.odin`、olib_sample `forward3d` 与 `book_ui`。3D 包测试里字节码分发的用例改测 `mat.shader_pick`（或并入 material 测试），std140 用例移到 `tests/kit/rendering/material/`。

提交：olib `rendering: std140 写入移到 material，删除 3D 包的字节码转发`；olib_sample `forward3d/book_ui: 改用 mat 的 std140 与 shader_pick`

### 2. 业务入口：model_draw / View / Model_Buffer

按决策 1–6：改 `model_draw.odin`、`model_buffer.odin`、`model_material_draw.odin`，新增 `mat.instance_slot_count` 与 `Draw_Error.Unsupported_Mesh`（含 `draw_error_text`）；`sprite_buffer_init` / `sprite_draw_buffer` 同步。更新 `shader_lab/material_preview.odin`、olib_sample `material3d`（main.odin、swarm.odin 去掉 `SWARM_SLOTS` 常数）与 `material2d`（`swarm.odin` 同样去掉 `SWARM_SLOTS`）；`tests/kit/rendering/2d/sprite_draw_test.odin` 的 `sprite_buffer_init` 用例改为新签名。测试补：nil 网格、nil 缓冲、蒙皮网格三种错误码；`model_buffer_init` 从材质取槽数（含非 instanced 效果返回 false）；`instance_slot_count` 的一致 / 不一致两种情况。

提交：olib `rendering3d: model_draw 直接接材质与网格，实例缓冲槽数取自材质`；olib_sample `material2d/material3d: 跟随新的绘制与缓冲接口`

### 3. 内部整理与 LOD 修复

按决策 8–10：文件改名（`git mv`）、`mesh3d_*` → `mesh_*`、调试线着色器私有化、删 `Vertex_Matrix_Block`、修 `model_lod_select` 并补测试。更新 shader_lab `session.odin` / `shapes.odin` 与 olib_sample `forward3d`。

完成后复查：`grep -rn "mesh3d_\|shader3d_\|Model_View\|Vertex_Matrix_Block\|r3d\.Model\b\|r3d\.std140" --include=*.odin kit tools tests ../olib_sample/src` 没有结果。

提交：olib `rendering3d: 去掉名字里的 3d，调试线着色器私有化，修 LOD 包围盒`；olib_sample `forward3d: 跟随 mesh_* 改名`

### 4. 文档

- 按决策 13 重写 `kit/rendering/3d/README.md`，新建 `REFERENCE.md`。README 里每个代码块的名字都要在源码里存在（执行者逐个 grep 核对）。
- 更新 `kit/rendering/README.md` 的最小示例与 API 速查、`kit/rendering/material/README.md`、`kit/rendering/2d/README.md`（`sprite_buffer_init` 新签名、错误码）、`kit/tools/shader_lab/README.md`、olib_sample `src/material3d/README.md`。
- 复查：`grep -rn "mesh3d_\|shader3d_\|Model_View\|model_material_draw\|std140_write" --include=*.md` 只允许出现在 `REFERENCE.md`（`model_material_draw`、`mat.std140_*`）和 `docs/plans/archive/`。

提交：olib `docs(rendering3d): README 改为业务向，底层细节拆到 REFERENCE.md`；olib_sample `docs(material3d): 跟随新接口`

### 5. 按 docs/plans/README.md 归档本计划

## 验收

- `odin run tools/check` 全部通过（含 olib_sample 示例编译与测试）。
- `run.bat material3d` 与 `run.bat forward3d` 画面与改动前一致（本计划不改渲染结果）：改动前后各截一张到 `library/screenshots/`，同名覆盖，对比后在汇报里说明。
- 第 3、4 步的 grep 复查符合要求。
- 3D README 行数在 150 行以内，开头 30 行内能看到完整的“加载材质 → model_draw”示例。

## 禁止事项

- 不新增渲染功能（蒙皮材质路径、剔除、排序策略、实例子区间等）。
- 不改 `foster/`、`core/dasset`、顶点格式与 HLSL 约定（b0/b1/space2、`OlibInstanceInput`），不重编着色器。
- 2D 只改决策 4、5 涉及的两个函数，不顺手重排 2D API 或 README 结构。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 两个仓库各自的 commit 列表。
- `odin run tools/check` 结果，失败就贴输出。
- material3d / forward3d 改动前后截图对比结论。
- 新旧 README 行数，以及 grep 复查结果。
- 与计划不一致的地方及原因。
