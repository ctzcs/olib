# 渲染

## 最小示例：带材质的精灵

```odin
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import mat "olib:kit/rendering/material"

// 初始化（一次）：资源容器、材质库、精灵渲染器。
materials := mat.Material_Library{device = &app.GraphicsDevice, storage = &resources}
if reason := mat.material_register_manifest(&materials, manifest_json, pass_binaries); reason != "" {
    // 清单或字节码有问题：reason 说明原因。
}
renderer: r2d.Sprite_Renderer
r2d.sprite_renderer_init(&renderer, &app.GraphicsDevice)
material, reason := mat.material_load(&materials, "materials/hero.json")
frame := foster.SubtextureFromTexture(&texture)

// 每帧：begin/end 之间自动合并相邻兼容的绘制。
view := r2d.Sprite_View{target = foster.DrawableTargetFromWindow(&app.Window), time = elapsed}
if r2d.sprite_begin(&renderer) {
    if err := r2d.sprite_draw(&renderer, material, frame, foster.Matrix3x2Identity, view); err != .None {
        fmt.eprintln(mat.draw_error_text(err))
    }
    r2d.sprite_end(&renderer)
}

// 退出：先停止绘制，再释放。
r2d.sprite_renderer_dispose(&renderer)
mat.material_library_dispose(&materials)
```

整张贴图当一帧时用 `r2d.sprite_draw_texture(&renderer, material, &texture, transform, view)`。
同一材质要画不同取值（如不同 hue）时：效果里把参数声明成 `[Instance]`，用 `mat.instance_slot` 解析一次槽位，
再用 `mat.Instance_Values` 给每个精灵设值，这些不同取值仍会合成一次 Draw
（见 [2d README](2d/README.md#跨实例合批instance-与-instanced)）。整体参数用 `mat.material_set_number` 改材质。

3D 把 `sprite_draw` 换成 `r3d.model_draw(material, &mesh, transform, view)`，同样返回 `mat.Draw_Error`。
`manifest_json` 与 `pass_binaries` 由 `tools/shaders` 的产物 `#load` 得到，完整写法见
`olib_sample/src/material2d` 和 `src/material3d`；各部分细节见下面各包的 README。

## API 速查：从哪个文件找

业务代码只会用到下面这些；没列出的（`*_selected`、`material_pass_*`、`pass_state_apply`、`aseprite_*` 内部函数等）是实现细节或工具集成接口。

| 要做什么 | 函数 / 类型 | 文件 |
| --- | --- | --- |
| 创建材质库、登记效果 | `Material_Library`、`material_register_manifest`、`material_register`、`material_library_dispose` | [material/material_library.odin](material/material_library.odin)、[material/shader_code.odin](material/shader_code.odin) |
| 加载材质、改参数 | `material_load`、`material_reload`、`material_set_number` | [material/material.odin](material/material.odin) |
| 每个实例的值（可合批） | `Instance_Slot`、`instance_slot`、`instance_slot_count`、`Instance_Values`、`instance_values_set`、`instance_array_set`（缓冲用） | [material/instance_values.odin](material/instance_values.odin) |
| 绘制失败原因 | `Draw_Error`、`draw_error_text` | [material/draw.odin](material/draw.odin) |
| 2D 画精灵 | `Sprite_Renderer`、`sprite_renderer_init/dispose`、`sprite_begin/end/flush`、`sprite_draw`、`sprite_draw_texture`、`Sprite_View` | [2d/sprite_draw.odin](2d/sprite_draw.odin) |
| 2D 百万精灵（一次 Draw） | `Sprite_Buffer`、`sprite_buffer_init/upload/dispose`、`Sprite_Item`、`sprite_item_make`、`sprite_draw_buffer` | [2d/sprite_buffer.odin](2d/sprite_buffer.odin) |
| 2D 帧动画 | `Sprite`、`sprite_init/dispose`、`sprite_add_frame`、`sprite_add_animation`、`sprite_get_animation`、`sprite_get_frame_at` | [2d/sprite.odin](2d/sprite.odin) |
| 2D 图集 | `Sprite_Atlas`、`atlas_from_rects`、`atlas_upload`、`atlas_subtexture`、`atlas_get/has/names/crop` | [2d/atlas.odin](2d/atlas.odin)（来源格式见 `atlas_grid / atlas_kenney / atlas_aseprite / atlas_builtin_icons`） |
| 3D 画模型 | `View`、`model_draw` | [3d/model_draw.odin](3d/model_draw.odin) |
| 3D 实例化（大批量） | `Model_Buffer`、`Model_Item`、`model_buffer_init/upload/dispose`、`model_draw_buffer` | [3d/model_buffer.odin](3d/model_buffer.odin)、[3d/model_draw.odin](3d/model_draw.odin) |
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
