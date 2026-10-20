# 渲染

2D 用 `Render2D`，3D 用 `Render3D`，均先记录再 `submit`。二者共用材质库，互不依赖。
Render2D 提交后清空；Render3D 保留记录，支持多个视图/Pass 重复提交，下一帧重新记录前显式 `clear`。

## 最小示例

```odin
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import mat "olib:kit/rendering/material"

materials := mat.Material_Library{device = &app.GraphicsDevice, storage = &resources}
renderer: r2d.Render2D
reason := r2d.init(&renderer, &materials) // 检查 reason；空串成功

// 每帧：默认材质无需登记或加载；自定义材质加 material = material。
err := r2d.texture(&renderer, &texture, foster.Matrix3x2Identity)
err = r2d.submit(&renderer, {target = foster.DrawableTargetFromWindow(&app.Window), time = elapsed})
// 检查每个 err：.None 成功，mat.draw_error_text(err) 给出原因。

// 退出：
r2d.dispose(&renderer)
mat.material_library_dispose(&materials)
```

自定义效果用 `material_register_manifest` 登记，再 `material_load` 或 `material_create` 创建材质。
不同 tint 自动合批；每个对象独立变化的材质字段用 `[Instance]` 和 `Instance_Values`。
常驻实例缓冲继续使用平铺数值数组，见 [2D](2d/README.md) 和 [3D](3d/README.md)。

## API 速查：从哪个文件找

业务代码只会用到下面这些；没列出的（`*_selected`、`material_pass_*`、`pass_state_apply`、`aseprite_*` 内部函数等）是实现细节或工具集成接口。

| 要做什么 | 函数 / 类型 | 文件 |
| --- | --- | --- |
| 创建材质库、登记效果 | `Material_Library`、`material_create`、`material_register_manifest`、`material_register`、`material_library_dispose` | [material/material_library.odin](material/material_library.odin)、[material/shader_code.odin](material/shader_code.odin) |
| 加载材质、改参数、绑运行时贴图 | `material_load`、`material_reload`、`material_set_number`、`material_set_texture` | [material/material.odin](material/material.odin) |
| 每个实例的值（可合批） | `Instance_Slot`、`instance_slot`、`instance_slot_count`、`Instance_Values`、`instance_values_set`、`instance_array_set`（缓冲用） | [material/instance_values.odin](material/instance_values.odin) |
| 绘制失败原因 | `Draw_Error`、`draw_error_text` | [material/draw.odin](material/draw.odin) |
| 2D 画精灵 | `Render2D`、`init/dispose`、`image/texture`、`push_matrix/pop_matrix`、`submit`、`View` | [2d/render2d.odin](2d/render2d.odin) |
| 2D 百万精灵（一次 Draw） | `Sprite_Buffer`、`sprite_buffer_init/upload/dispose`、`Sprite_Item`、`sprite_item_make`、`buffer` | [2d/sprite_buffer.odin](2d/sprite_buffer.odin) |
| 2D 帧动画 | `Animation_Set`、`animation_set_init/dispose`、`animation_set_add_frame/add_animation`、`animation_set_get_animation/get_frame_at` | [2d/animation_set.odin](2d/animation_set.odin) |
| 2D 图集 | `Sprite_Atlas`、`atlas_from_rects`、`atlas_upload`、`atlas_subtexture`、`atlas_get/has/names/crop` | [2d/atlas.odin](2d/atlas.odin)（来源格式见 `atlas_grid / atlas_kenney / atlas_aseprite / atlas_builtin_icons`） |
| 3D 画模型 / 自动实例化 | `Render3D`、`View`、`init/dispose/clear`、`model/models`、`submit`、`Model_Item` | [3d/render3d.odin](3d/render3d.odin) |
| 3D 常驻实例缓冲 | `Model_Buffer`、`model_buffer_init/upload/dispose`、`buffer` | [3d/model_buffer.odin](3d/model_buffer.odin)、[3d/REFERENCE.md](3d/REFERENCE.md) |
| 3D 随模型提交调试线 | `line/aabb/sphere/frustum/axis/grid/skeleton` | [3d/render3d_debug.odin](3d/render3d_debug.odin) |
| 3D 网格上传 | `mesh_upload`、`mesh_dispose`、`mesh_static_format`、`mesh_skin_format` | [3d/mesh.odin](3d/mesh.odin) |
| 3D 排序 / LOD / 调试线 | `Render_Queue`、`queue_*`；`Lod_Selector`、`lod_*`、`Model_Lod`；`Debug_Draw_3D`、`debug_draw_*` | [3d/queue.odin](3d/queue.odin)、[3d/lod.odin](3d/lod.odin)、[3d/debug_draw.odin](3d/debug_draw.odin) |
| 解析 `.oshader`、开发期热重载 | `lang.parse`；`dev.*` | [shader/lang/lang.odin](shader/lang/lang.odin)、[shader/dev/](shader/dev/) |

import 别名：`mat "olib:kit/rendering/material"`、`r2d "olib:kit/rendering/2d"`、`r3d "olib:kit/rendering/3d"`。

## 目录

| 目录 | 职责 | 推荐 import |
| --- | --- | --- |
| [material](material/README.md) | 材质参数、效果描述、序列化、GPU 资源与 Pass 提交 | `mat "olib:kit/rendering/material"` |
| [2d](2d/README.md) | 图集、帧动画、精灵绘制与合批 | `r2d "olib:kit/rendering/2d"` |
| [3d](3d/README.md) | 模型绘制与实例化、Mesh、队列、LOD 与调试线 | `r3d "olib:kit/rendering/3d"` |
| [shader/lang](shader/lang/README.md) | .oshader 语法解析与每个 Pass 的 HLSL，解析时不读取文件或执行 GPU 操作 | `lang "olib:kit/rendering/shader/lang"` |
| [shader/dev](shader/dev/README.md) | 开发期编译、文件监听与热重载 | `dev "olib:kit/rendering/shader/dev"` |

`rendering/` 与 `shader/` 仅组织目录，不提供转发包。2D 和 3D 都使用 material，互不依赖。
材质参数、效果描述与序列化位于 [kit/rendering/material](material/README.md)，
供公共渲染资源、Shader 解析和编辑工具共同使用。
Shader Lab 仍位于 [kit/tools/shader_lab](../tools/shader_lab/README.md)。
