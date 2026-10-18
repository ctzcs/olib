# 渲染资源与 2D 绘制

本包提供图集、帧动画、公共材质资源与材质 Sprite 绘制。
`kit/material` 负责纯数据；本包负责 GPU 资源与有序对象 Pass；
`kit/rendering3d` 在同一套材质资源上提供模型绘制。

## 公共材质资源

```odin
materials := rendering.Material_Library{device = device, storage = &resources}
reason := rendering.materials_register(&materials, effect, schemas, shader_code)
material, reason := rendering.material_load(&materials, "materials/hero.json")
// 检查 reason 后将 material 赋给 Sprite_Instance.material 或 r3d.Model.material。
```

每次 load 创建独立参数实例，共享同一效果的 Shader 和同路径贴图。
Effect/Schema 由库深复制，当前后端预编译字节码借用至 `materials_dispose`。
材质和贴图使用同一个 Foster StorageContainer；材质路径相对容器根，贴图路径相对材质文件。
库、device、storage 的地址及存储根在使用期间须保持稳定。

`material_set_number(material, group, field, value)` 检查类型和范围后修改单个实例。
`material_reload(&materials, material)` 完整候选成功后替换，失败保留旧值，材质指针不变。
它只重载材质文件，同路径贴图仍使用缓存，不自动热重载 Shader/贴图。
停止绘制后用 `materials_dispose` 统一释放全部材质、Shader 和贴图；不浅复制资源对象。

## 材质 Sprite

```odin
renderer: rendering.Sprite_Renderer
rendering.sprite_renderer_init(&renderer, device)
sprite := rendering.Sprite_Instance{
    frame = current_animation_frame.Subtexture,
    origin = animation.Origin,
    material = material,
}
ok := rendering.sprite_draw(&renderer, sprite, transform, {
    target = scene_target, time = elapsed,
})
// 停止绘制后：
rendering.sprite_renderer_dispose(&renderer)
```

`Sprite` 仍是共享帧动画资源；对象状态放 `Sprite_Instance`。`transform` 使用 Foster
Matrix3x2，单位矩阵须显式传入 `foster.Matrix3x2Identity`，不是零矩阵。
输入/输出坐标为最终目标像素，左上原点；相机变换可预乘入 transform。
图集 TexCoords、裁剪 DrawCoords、原图 origin 均保留。多个精灵可共用一个 renderer。

效果的所有 Pass 声明为 `.Sprite`，按对象逐个、按 Pass 声明顺序立即绘制；
全部使用外部同一目标，中途不清屏。默认无剔除、无深度读写、预乘 Alpha 混合。
`state.blend = .Premultiplied` 可显式指定此混合；`.Alpha` 表示非预乘。
需要透明排序时由调用方按正确顺序提交对象。

```odin
{id = "body", params = "Sprite", draw = .Sprite, output = "color",
    sprite_texture = "image"}
```

`sprite_texture` 是当前帧要覆盖的 Texture 字段 ID；绑定按 Schema 定位，
不假设第一个贴图槽，其他贴图仍来自材质。空值表示该 Pass 不采样帧贴图。
当前帧由 Sprite 对象提供，因此不会使用该字段在材质文件中保存的贴图作为帧。

Shader 接口：

- TEXCOORD0 为 Float2 像素位置；TEXCOORD1 为 Float2 帧 UV。
- vertex b0/space1 为 64B 列主序投影，HLSL 使用 `mul(Projection, float4(Position, 0, 1))`。
- fragment b0/space3 为 48B：Clock(time, dt, frame, 1)、Pointer(mouse UV, 目标宽高)、Tint。
- fragment b1/space3 与 space2 纹理仍由 material 的参数生成器定义；参数不提供给顶点阶段。
- 输出预乘颜色；传入的帧贴图应预乘。`sprite_draw` 的可选 tint 默认白色。

这套接口与 Batcher、旧 ShaderLab Fullscreen/Preview_Model 接口不同，Shader 不能直接混用。
普通 Sprite 继续使用 Foster Batcher；材质 Sprite 是独立的立即提交入口，不隐式 flush
或改变 Batcher 状态。先提交底层批次，再绘制材质 Sprite，最后提交上层/UI 批次。

ShaderLab 的 `.Sprite` 预览调用同一个 `sprite_material_draw`，支持多 Pass、参数修改、
Shader 热重载和整材质保存/载入。普通游戏只登记预编译字节码，不依赖 ShaderLab。
示例：`olib_sample/src/material2d`（阴影 + 本体）、`src/material3d`（本体 + 描边）。
当前预编译示例支持原生 SPIR-V/DXIL/MSL；Web 仍需适配 GLSL 与 Web uniform 接口。
