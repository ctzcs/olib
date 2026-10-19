# 2D 精灵与图集

本包提供图集、帧动画、精灵绘制与合批。材质加载、缓存和 Pass 执行由
[rendering/material](../material/README.md) 提供；3D 模型绘制见 [rendering/3d](../3d/README.md)。

使用现成效果时，业务流程是：加载材质 → 绘制（材质 + 子图 + 变换）。
初始化时登记 Effect/Shader，并创建可复用的 `Sprite_Renderer`。不需要为每个精灵创建对象。

## 精灵绘制

```odin
import r2d "olib:kit/rendering/2d"

renderer: r2d.Sprite_Renderer
r2d.sprite_renderer_init(&renderer, device)
err := r2d.sprite_draw(&renderer, material, current_animation_frame.subtexture, transform, {
    target = scene_target, time = elapsed,
}, origin = animation.origin)
// err 为 mat.Draw_Error：.None 成功；mat.draw_error_text(err) 给出失败原因。
// 停止绘制后：
r2d.sprite_renderer_dispose(&renderer)
```

### 常用写法

```odin
r2d.sprite_draw(&renderer, material, subtexture, transform, view, tint = {1, 1, 1, 0.8})
r2d.sprite_draw_texture(&renderer, material, &texture, transform, view, origin = {128, 128})
// 同一材质画不同变体：Instance_Values 只设置这个精灵的 [Instance] 字段，不修改共享材质，仍可合批。
hue := mat.instance_slot(material, "hue")                       // 解析一次
cool: mat.Instance_Values
mat.instance_values_set(&cool, hue, {0.7, 0, 0, 0})
r2d.sprite_draw(&renderer, material, subtexture, transform, view, values = &cool)
// 只画一个 Pass（例如先画全部阴影、再画全部本体）：
r2d.sprite_draw(&renderer, material, subtexture, transform, view, pass_id = "shadow")
```

`sprite_draw` 的 `frame` 可以直接传 `sprite_get_frame_at` 取得的 `frame.subtexture`；
`sprite_draw_texture` 把整张贴图当一帧。`tint`、`origin`、`values`、`pass_id` 都是可选参数。

### 跨实例合批（`[Instance]` 与 `Instanced`）

默认情况下 tint 和材质参数都在 uniform 里，值不同的精灵会拆成多次 Draw。把效果声明为
instanced（`.oshader` 里给属性加 `[Instance]`，或顶层写 `Instanced`）后，tint 与 `[Instance]` 字段
随每个精灵的顶点传入，Fragment uniform 对所有精灵一致，因此**只要贴图（同一图集页）、Shader、
绘制状态相同就合成一次 Draw**，与 hue、opacity、tint 等 `[Instance]` 字段的取值无关。
着色器约定见 [lang README](../shader/lang/README.md#instanced-效果的-hlsl-约定)。
每个精灵写成一条 80 + 16×字段数 字节的实例记录，由硬件实例化一次画出；不同贴图仍会拆批——请使用图集。

### 百万精灵：Sprite_Buffer

同一张图集页上的精灵数量很大（几十万到上百万）时，把精灵数据放进调用方持有的 `Sprite_Buffer`，**一次 Draw 画完**。
库不缓存、不排序、不剔除：

```odin
buffer: r2d.Sprite_Buffer
r2d.sprite_buffer_init(&buffer, material, capacity = 1_000_000) // 设备与字段数（buffer.slots）取自材质

items := make([]r2d.Sprite_Item, count)
values := make([][4]f32, count*buffer.slots)                    // 每个精灵连续 slots 个 float4
frame := foster.SubtextureFromTexture(&atlas_texture)          // 或 atlas_subtexture 取得的子图
items[i] = r2d.sprite_item_make(frame, origin, transform, tint)
hue := mat.instance_slot(material, "hue")                       // 名字只解析一次；百万次赋值里没有字符串比较
mat.instance_array_set(values, buffer.slots, i, hue, {0.7, 0, 0, 0})
r2d.sprite_buffer_upload(&buffer, items, values = values)       // 加载时一次上传；运行中只更新变化区间（first 参数）

// 每帧：
err := r2d.sprite_draw_buffer(&renderer, material, &buffer, count, &atlas_texture, view)
err = r2d.sprite_draw_buffer(&renderer, material, &buffer, count, &atlas_texture, view, pass_id = "body")
```

- 字段个数由效果决定：声明几个 `[Instance]`，`buffer.slots` 就是几个（硬上限 `MAX_INSTANCE_FIELDS` = 16）；
  材质不是 instanced 效果时 `sprite_buffer_init` 返回 false。`values` 长度必须是 `len(items) × slots`，传 `nil` 表示全部为 0。
- 一次 Draw 里的精灵共用同一张贴图（`texture`，即帧贴图字段）；不同图集页各自一个缓冲。
- 每个精灵 80 + 16×slots 字节：100 万个、2 个字段约 112 MB 显存。`Sprite_Item` 的内存布局就是 GPU 记录，没有字段时整块拷贝，
  有字段时只做两次块拷贝拼接，不逐字段打包；实测 100 万个精灵（2 个字段）上传约 37 ms（RTX 3070，D3D12）。
  请在加载时一次完成，运行中只更新变化的区间（帧内上传占用设备暂存区）。
- 剔除：把精灵按空间分块放进多个缓冲，每块每帧只提交可见的；`count` 可以只画缓冲前 N 个。
- 绘制顺序：`sprite_draw_buffer` 先提交 begin/end 里已排队的精灵再绘制，保持调用顺序；缓冲内部按下标顺序混合。
- `[Instance]` 字段以缓冲为准，其余统一参数来自材质、整批共用。非 instanced 效果返回 `.Not_Instanced_Effect`，缓冲为 nil 或未创建返回 `.Instance_Buffer_Required`，字段数不一致返回 `.Instance_Mismatch`。
- 示例 `olib_sample/src/material2d` 的 `swarm`：100 万个精灵、1 次 Draw，每帧 CPU 约 0.02 ms。

### 帧动画

`Sprite` 是共享的帧动画资源（帧 = 图集子图 + 时长，动画 = 帧区间），不保存播放状态；
当前时间由调用者自己累计，每帧取出应显示的帧交给 `sprite_draw`：

```odin
// 初始化（一次）：从图集取子图，按时长加入帧，再命名动画区间。
hero: r2d.Sprite
r2d.sprite_init(&hero, "hero", origin = {16, 32})
for name in frame_names {
    subtexture, _ := r2d.atlas_subtexture(&atlas, name)
    r2d.sprite_add_frame(&hero, subtexture, 0.1)
}
r2d.sprite_add_animation(&hero, "walk", 0, len(frame_names))

// 每帧：elapsed 是这个对象自己的动画时间（秒）。
walk := r2d.sprite_get_animation(&hero, "walk") // 追加新动画后指针失效，不要跨帧缓存
frame, _ := r2d.sprite_get_frame_at(&hero, walk, elapsed, true) // true 循环；false 停在最后一帧
err := r2d.sprite_draw(&renderer, material, frame.subtexture, transform, view, origin = hero.origin)
```

`.aseprite` 目录可用 `aseprite_build` 一次打成图集并生成命名动画（`Built_Clip`：区域名 + 时长，
PingPong / Reverse 已展开）。目前需要自己把 `Built_Clip` 的区域名经 `atlas_subtexture` 转成 `Sprite` 的帧，
还没有一步到位的转换函数；也没有内置的播放器（暂停、变速、结束回调需自己处理）。

`Sprite` 是共享帧动画资源，播放状态由调用者保存。`transform` 使用 Foster
Matrix3x2，单位矩阵须显式传入 `foster.Matrix3x2Identity`，不是零矩阵。
输入/输出坐标为最终目标像素，左上原点；相机变换可预乘入 transform。
图集 TexCoords、裁剪 DrawCoords、原图 origin 均保留。多个精灵可共用一个 renderer。

### 自选 Pass 与自动合批

`sprite_draw` 默认按声明顺序画全部启用 Pass；传 `pass_id` 只画指定 ID。
库不定义或调度“阴影阶段”，顺序完全由调用者决定，例如先画所有阴影再画本体：

```odin
if r2d.sprite_begin(&renderer) {
    for i in 0..<count {
        err := r2d.sprite_draw(&renderer, material, frame, transforms[i], view, pass_id = "shadow")
        // err != .None：未知 Pass、缺失材质/纹理、设备不一致或无效目标等，见 mat.draw_error_text。
    }
    for i in 0..<count {
        err := r2d.sprite_draw(&renderer, material, frame, transforms[i], view, pass_id = "body")
    }
    r2d.sprite_end(&renderer)
}
```

- begin/end 之间自动合并相邻且 Shader、纹理/采样、全部 uniform、目标与绘制状态一致的请求。
  不要求 Material 是同一个实例；位置和图集 UV 可以不同。非 instanced 效果的 tint 位于 uniform，颜色不同会分批；instanced 效果不受此限。
- 只保持调用顺序，不自动按材质排序；多 Pass 的全部绘制仍是 A 阴影 → A 本体 → B 阴影 → B 本体。
  自选顺序会改变透明遮挡：全部阴影先画时，后一个对象的阴影不会覆盖前一个对象的本体。
- 每批最多 4096 个四边形，达到容量或遇到不兼容状态时自动提交；end 提交最后一批。
  renderer 的 `sprite_passes` / `draw_calls` 记录最近一次 begin/end 内合批路径的 Pass 数 / Draw 数。
- 未调用 begin 时保持立即绘制。begin 不可嵌套，成功后须在本帧内 end。
  `sprite_flush` 提交当前批次但不结束范围；穿插模型、另一个 renderer、Batcher、清屏或读回前须 flush。
- 数值参数在提交请求时保存，之后 `material_set_number` 不影响已排队的图像。
  Shader 和纹理仍借用；重载、销毁或修改 GPU 资源前必须 flush/end，不能跨帧积压。
- `pass_id` 为空画全部启用的 Pass；未知 ID 返回 `.Unknown_Pass`，不退回全部绘制。被禁用的已知 Pass 返回 `.None` 但不绘制，
  并遵守工具的 enabled/pass_limit 覆盖。全部入口在首个 Pass 前检查所有选中的绑定。

普通 Sprite 可继续使用 Foster Batcher；本渲染器不改变它的状态或隐式提交它的批次。
先提交底层 Batcher，再 begin/draw/end 材质 Sprite，最后提交上层/UI Batcher。

ShaderLab 的 `.Sprite` 预览调用同一个 `sprite_material_draw`（见 sprite_material_draw.odin），支持多 Pass、参数修改、
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
- fragment b1/space3 与 space2 纹理仍由 `.oshader` 的 Properties 布局定义；参数不提供给顶点阶段。
- 输出预乘颜色；传入的帧贴图应预乘。`sprite_draw` 的可选 tint 默认白色。
- 合批时一个 Draw 内含多个四边形；Shader 应按传入位置/UV 工作，不依赖每个对象重新从零开始的顶点 ID。

## 实现与工具接入

[rendering/material](../material/README.md) 保存精灵和模型共用的绑定、状态设置与 Pass 循环。
本包的 `sprite_material_draw` 准备精灵几何，再调用 `mat.material_draw`。

ShaderLab 通过 `sprite_material_draw` / `model_material_draw` 使用自己管理的 GPU 资源，
预览接线集中在 `kit/tools/shader_lab/material_preview.odin`。
这些接口与业务入口调用同一实现，避免预览和游戏分别维护一套绘制逻辑。
低层输入的 `pass_id` 留空表示全部；设置后只选择该 ID。
`sprite_material_draw` 带 prepare/submit 回调时会先 flush，再立即执行回调，不参与自动合批，
以保留工具对任意 DrawCommand 状态和提交行为的控制。
