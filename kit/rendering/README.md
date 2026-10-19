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
sprite := r2d.Sprite_Instance{frame = foster.SubtextureFromTexture(&texture), material = material}

// 每帧：begin/end 之间自动合并相邻兼容的绘制。
view := r2d.Sprite_View{target = foster.DrawableTargetFromWindow(&app.Window), time = elapsed}
if r2d.sprite_begin(&renderer) {
    if err := r2d.sprite_draw(&renderer, sprite, foster.Matrix3x2Identity, view); err != .None {
        fmt.eprintln(mat.draw_error_text(err))
    }
    r2d.sprite_end(&renderer)
}

// 退出：先停止绘制，再释放。
r2d.sprite_renderer_dispose(&renderer)
mat.material_library_dispose(&materials)
```

只有一个材质和一张图时可以省掉 `Sprite_Instance`：`r2d.sprite_draw_texture(&renderer, material, &texture, transform, view)`。
同一材质要画不同取值（如不同 hue）时，用 `mat.Property_Block` 按次覆盖，效果声明为 instanced 后这些
不同取值仍会合成一次 Draw（见 [2d README](2d/README.md#跨实例合批instance-与-instanced)）。

3D 把 `sprite_draw` 换成 `r3d.model_draw(model, transform, view)`，同样返回 `mat.Draw_Error`。
`manifest_json` 与 `pass_binaries` 由 `tools/shaders` 的产物 `#load` 得到，完整写法见
`olib_sample/src/material2d` 和 `src/material3d`；各部分细节见下面各包的 README。

## 目录

| 目录 | 职责 | 推荐 import |
| --- | --- | --- |
| [material](material/README.md) | 材质参数、效果描述、序列化、GPU 资源与 Pass 提交 | `mat "olib:kit/rendering/material"` |
| [2d](2d/README.md) | 图集、帧动画、精灵绘制与合批 | `r2d "olib:kit/rendering/2d"` |
| [3d](3d/README.md) | 模型绘制、Mesh、队列、矩阵打包与调试线 | `r3d "olib:kit/rendering/3d"` |
| [shader/lang](shader/lang/README.md) | .oshader 语法解析与每个 Pass 的 HLSL，解析时不读取文件或执行 GPU 操作 | `lang "olib:kit/rendering/shader/lang"` |
| [shader/dev](shader/dev/README.md) | 开发期编译、文件监听与热重载 | `dev "olib:kit/rendering/shader/dev"` |

`rendering/` 与 `shader/` 仅组织目录，不提供转发包。2D 和 3D 都使用 material，互不依赖。
材质参数、效果描述与序列化位于 [kit/rendering/material](material/README.md)，
供公共渲染资源、Shader 解析和编辑工具共同使用。
Shader Lab 仍位于 [kit/tools/shader_lab](../tools/shader_lab/README.md)。
