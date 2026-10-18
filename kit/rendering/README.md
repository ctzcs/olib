# 渲染资源与 2D 绘制

本包提供图集、帧动画、材质资源与精灵绘制。
`kit/material` 负责纯数据；本包负责 GPU 资源与有序对象 Pass；
`kit/rendering3d` 在同一套材质资源上提供模型绘制。

使用现成效果时，业务流程是：加载材质 → 赋给对象 → 绘制。

| 要做什么 | 入口 | 实现位置 |
| --- | --- | --- |
| 加载、修改和重载材质 | `material_load` / `material_set_number` / `material_reload` | `material_library.odin` |
| 绘制精灵全部 / 指定 Pass | `sprite_draw` / `sprite_draw_pass` | `sprite_draw.odin` |
| 精灵合批范围 / 中途提交 | `sprite_begin` / `sprite_end` / `sprite_flush` | `sprite_draw.odin` |
| 绘制模型全部 / 指定 Pass | `r3d.model_draw` / `r3d.model_draw_pass` | `../rendering3d/model_draw.odin` |

初始化时登记 Effect/Shader，并为精灵创建一个可复用的 `Sprite_Renderer`；退出时释放资源。

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
加载和重载在主线程、合法 GPU 生命周期内、提交绘制之外进行。缓存按库统一释放，
目前不逐项卸载，建议按场景或资源会话划分库。
路径中的 `.`、`..`、反斜杠会规范化；导出文件含绝对贴图路径时，应先将贴图纳入资产根并改为相对路径。

## 精灵绘制

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

### 自选 Pass 与自动合批

`sprite_draw` 按声明顺序画一个对象的全部启用 Pass；`sprite_draw_pass` 只画指定 ID。
库不定义或调度“阴影阶段”，顺序完全由调用者决定，例如先画所有阴影再画本体：

```odin
if rendering.sprite_begin(&renderer) {
    for sprite, i in sprites {
        ok := rendering.sprite_draw_pass(&renderer, sprite, "shadow", transforms[i], view)
        // 处理 ok=false：未知 Pass、缺失材质/纹理或无效目标。
    }
    for sprite, i in sprites {
        ok := rendering.sprite_draw_pass(&renderer, sprite, "body", transforms[i], view)
    }
    rendering.sprite_end(&renderer)
}
```

- begin/end 之间自动合并相邻且 Shader、纹理/采样、全部 uniform、目标与绘制状态一致的请求。
  不要求 Material 是同一个实例；位置和图集 UV 可以不同。当前 tint 位于 uniform，颜色不同会分批。
- 只保持调用顺序，不自动按材质排序；多 Pass 的全部绘制仍是 A 阴影 → A 本体 → B 阴影 → B 本体。
  自选顺序会改变透明遮挡：全部阴影先画时，后一个对象的阴影不会覆盖前一个对象的本体。
- 每批最多 4096 个四边形，达到容量或遇到不兼容状态时自动提交；end 提交最后一批。
  renderer 的 `sprite_passes` / `draw_calls` 记录最近一次 begin/end 内合批路径的 Pass 数 / Draw 数。
- 未调用 begin 时保持立即绘制。begin 不可嵌套，成功后须在本帧内 end。
  `sprite_flush` 提交当前批次但不结束范围；穿插模型、另一个 renderer、Batcher、清屏或读回前须 flush。
- 数值参数在提交请求时保存，之后 `material_set_number` 不影响已排队的图像。
  Shader 和纹理仍借用；重载、销毁或修改 GPU 资源前必须 flush/end，不能跨帧积压。
- 指定入口不接受空 ID；未知 ID 返回 false，不退回全部绘制。被禁用的已知 Pass 返回 true 但不绘制，
  并遵守工具的 enabled/pass_limit 覆盖。全部入口在首个 Pass 前检查所有选中的绑定。

普通 Sprite 可继续使用 Foster Batcher；本渲染器不改变它的状态或隐式提交它的批次。
先提交底层 Batcher，再 begin/draw/end 材质 Sprite，最后提交上层/UI Batcher。

ShaderLab 的 `.Sprite` 预览调用同一个 `sprite_material_draw`，支持多 Pass、参数修改、
Shader 热重载和整材质保存/载入。普通游戏只登记预编译字节码，不依赖 ShaderLab。
示例：`olib_sample/src/material2d`（阴影 + 本体）、`src/material3d`（本体 + 描边）。
当前预编译示例支持原生 SPIR-V/DXIL/MSL；Web 仍需适配 GLSL 与 Web uniform 接口。

## 效果与 Shader 接入

精灵 Shader 使用下列接口；现有 Batcher、ShaderLab Fullscreen/Preview_Model Shader 需要适配后才能使用。

效果的所有 Pass 声明为 `.Sprite`；全部入口按对象逐个、按 Pass 声明顺序绘制，指定入口只选一个；
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

### Shader 接口

- TEXCOORD0 为 Float2 像素位置；TEXCOORD1 为 Float2 帧 UV。
- vertex b0/space1 为 64B 列主序投影，HLSL 使用 `mul(Projection, float4(Position, 0, 1))`。
- fragment b0/space3 为 48B：Clock(time, dt, frame, 1)、Pointer(mouse UV, 目标宽高)、Tint。
- fragment b1/space3 与 space2 纹理仍由 material 的参数生成器定义；参数不提供给顶点阶段。
- 输出预乘颜色；传入的帧贴图应预乘。`sprite_draw` 的可选 tint 默认白色。
- 合批时一个 Draw 内含多个四边形；Shader 应按传入位置/UV 工作，不依赖每个对象重新从零开始的顶点 ID。

## 实现与工具接入

`material_passes.odin` 保存精灵和模型实际共用的绑定、状态设置与 Pass 循环。
`Material_Binding`、`Material_Draw`、`material_draw` 是这一层的集成接口，
跨包的模型绘制需要调用它们，所以保持可见；普通业务从上面的三个入口接入。

ShaderLab 通过 `sprite_material_draw` / `model_material_draw` 使用自己管理的 GPU 资源，
预览接线集中在 `kit/tools/shader_lab/material_preview.odin`。
这些接口与业务入口调用同一实现，避免预览和游戏分别维护一套绘制逻辑。
低层输入的 `pass_id` 留空表示全部；设置后只选择该 ID。
`sprite_material_draw` 带 prepare/submit 回调时会先 flush，再立即执行回调，不参与自动合批，
以保留工具对任意 DrawCommand 状态和提交行为的控制。
