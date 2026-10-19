# 3D 模型绘制

本包用材质画静态网格，并提供每个 3D 游戏都要的机制：网格上传、实例化缓冲、排序队列、LOD 与调试线。
材质加载、缓存和 Pass 执行由 [rendering/material](../material/README.md) 提供，2D 精灵见 [rendering/2d](../2d/README.md)。
光照、阴影和后处理由游戏自己写，参考实现是 olib_sample 的 `src/forward3d`；手写 HLSL 与底层接口见 [REFERENCE.md](REFERENCE.md)。

## 模型绘制

```odin
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"

// 初始化：材质库登记效果后加载材质，网格从 dasset primitive 上传。
material, reason := mat.material_load(&materials, "materials/hero.json")
mesh: foster.Mesh
r3d.mesh_upload(&mesh, device, &primitive, "hero")

// 每帧：target 需要深度附件；view_projection 来自相机。
view := r3d.View{target = scene, view_projection = world.camera3d_view_projection(&camera), time = elapsed}
err := r3d.model_draw(material, &mesh, transform, view)
// err 为 mat.Draw_Error：.None 成功；mat.draw_error_text(err) 给出失败原因。

// 退出：先停止绘制，再释放。
r3d.mesh_dispose(&mesh)
mat.material_library_dispose(&materials)
```

- 参数顺序与 `sprite_draw` 一致：材质、几何、变换、视图，最后是可选的 `pass_id`。
- `pass_id` 为空画全部启用的 Pass；`r3d.model_draw(material, &mesh, transform, view, "outline")` 只画该 Pass，
  用循环组织“全部本体 → 全部描边”这类顺序。未知 ID 返回 `.Unknown_Pass`，已禁用的 Pass 返回 `.None` 但不绘制。
- 一个网格（primitive）一次调用；多 primitive 的模型由场景持有多组“网格 + 材质”。库不做场景、不排序、不合并网格。
- 只支持静态顶点格式；蒙皮网格返回 `.Unsupported_Mesh`。
- 整体参数用 `mat.material_set_number` 改材质；每个实例不同的值用 `[Instance]` 字段和下面的实例化。
- 与精灵混画时，先 `sprite_flush`，再提交模型。

材质登记、参数修改、重载与生命周期见 [公共材质资源](../material/README.md#公共材质资源)，示例见 olib_sample 的 `src/material3d`。

## 实例化：一个网格画上百万次

树、草、子弹这类同一网格的大量实例，用 instanced 效果 + 调用方持有的 `Model_Buffer`：**每个 Pass 只有一次 Draw**。

```odin
// 效果在 .oshader 里写 Instanced（可用 [Instance] 声明每个实例的字段），示例见 olib_sample 的 Swarm.oshader。
buffer: r3d.Model_Buffer
r3d.model_buffer_init(&buffer, material, capacity = 1_000_000) // 设备与字段数（buffer.slots）取自材质

items := make([]r3d.Model_Item, count)               // 每个实例的 world 矩阵与 tint
values := make([][4]f32, count*buffer.slots)         // [Instance] 字段：每个实例连续 slots 个 float4
hue := mat.instance_slot(material, "hue")            // 名字只解析一次
mat.instance_array_set(values, buffer.slots, i, hue, {0.7, 0, 0, 0})
r3d.model_buffer_upload(&buffer, items, values = values) // 静态场景加载时上传一次；动画交给着色器（Clock）

// 每帧：
err := r3d.model_draw_buffer(material, &mesh, &buffer, count, view)
// 退出：
r3d.model_buffer_dispose(&buffer)
```

- **成本在三角形数**：CPU 只有一次 Draw，百万实例的耗时几乎都在 GPU。远处的实例用低模（每个 LOD 一个缓冲），
  并把近处的实例排在前面以便提前深度测试。
- **规模**：每实例 `80 + 16×slots` 字节（100 万实例、1 个字段约 96 MB）。运行中只更新变化的区间：`model_buffer_upload(..., first = 偏移)`。
- **剔除与透明**：库不做。把实例按空间分块放进多个缓冲，每帧只画可见的块；`count` 可以只画缓冲的前 N 个。
  需要透明混合的实例由调用方分块从后向前提交。
- **错误码**：非 instanced 效果用缓冲画返回 `.Not_Instanced_Effect`；instanced 效果用 `model_draw` 返回 `.Instance_Buffer_Required`
  （传 nil 或未创建的缓冲同样如此）；缓冲与效果字段数不一致返回 `.Instance_Mismatch`。
- 着色器写法见 [instanced 效果的 HLSL 约定](../shader/lang/README.md#instanced-效果的-hlsl-约定)。

## 排序、LOD 与调试线

```odin
// 渲染队列：payload 由游戏定义；不透明从前到后、透明从后到前。
queue: r3d.Render_Queue(My_Draw)
r3d.queue_clear(&queue)
r3d.queue_submit(&queue, draw, r3d.queue_view_depth(&camera, draw.transform), transparent = false)
r3d.queue_sort(&queue)
for item in queue.items { /* 按顺序 model_draw 或手写提交 */ }

// LOD：屏幕高度占比阈值从高到低、末项为 0，带滞回。
lod: r3d.Model_Lod(^foster.Mesh)
r3d.model_lod_init(&lod, meshes[:], {0.3, 0.1, 0}, bounds)
mesh, ok := r3d.model_lod_select(&lod, &camera, transform)

// 调试线：每帧排队，render 后清空；深度测试可选，不写深度。
debug: r3d.Debug_Draw_3D
r3d.debug_draw_init(&debug, device)
r3d.debug_draw_grid(&debug, 6, 1, {1, 1, 1, 0.12})
r3d.debug_draw_aabb(&debug, bounds, {1, 0.6, 0.2, 1})
r3d.debug_draw_render(&debug, scene, &camera)
```

调试线还有 `debug_draw_line / sphere / frustum / axis / skeleton`；LOD 也可以单独用 `Lod_Selector` 与 `lod_screen_height`。

## 自己写 Shader 时的接口

材质路径（`model_draw`）的 Shader 由 `.oshader` 生成，约定如下；手写 HLSL 渲染器的完整流程见 [REFERENCE.md](REFERENCE.md)。

| 绑定 | 内容 |
| --- | --- |
| 顶点输入 | 静态格式：`TEXCOORD0..3` = 位置、法线、UV、切线（48B，`mesh_static_format`） |
| vertex b0 | WVP + World（各 64B，`pack_vertex_matrix_block`）；instanced 时为 `{ViewProjection, 单位矩阵}` |
| fragment b0 | Clock =（time, delta_time, frame, 0）、Pointer =（x, y, 目标宽, 目标高）、Tint = 白色 |
| fragment b1 | 材质参数（`mat.pack` 的布局） |
| space2 | 材质贴图 |

矩阵沿用 `kit/world` 的行向量约定（`v' = v * M`），HLSL 里一律写 `mul(v, M)`。

## 文件

| 文件 | 提供 |
| --- | --- |
| `model_draw.odin` | `View`、`model_draw`、`model_draw_buffer` |
| `model_buffer.odin` | `Model_Buffer`、`Model_Item`、`model_buffer_init / upload / dispose` |
| `model_material_draw.odin` | Shader Lab 用的底层入口 `model_material_draw`（见 REFERENCE.md） |
| `mesh.odin` | `mesh_upload / dispose`、`mesh_static_format / skin_format` |
| `queue.odin` | `Render_Queue($T)`、`queue_*` |
| `lod.odin` | `Lod_Selector`、`lod_*`、`Model_Lod($T)`、`model_lod_*` |
| `debug_draw.odin` | `Debug_Draw_3D`、`debug_draw_*`，内嵌 DebugLine3D 着色器 |
| `uniforms.odin` | `pack_vertex_matrix_block`、`pack_joint_palette`（手写 HLSL 用） |
| `shaders/` | DebugLine3D 的 HLSL 与编译产物；编译工具是 olib 根目录的 `tools/shaders` |
