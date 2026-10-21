# 2D 绘制、帧动画与图集

`Render2D` 先记录图元，最后 `submit` 合批绘制并清空。不需要 begin/end，
相机继续用原来的矩阵；材质使用 [mat.Material](../material/README.md)，不传就用默认材质。

## 最小用法

```odin
import foster "olib:foster"
import mat "olib:kit/rendering/material"
import r2d "olib:kit/rendering/2d"

// 初始化一次；materials 和 renderer 的地址保持稳定。
materials := mat.Material_Library{device = &app.GraphicsDevice}
renderer: r2d.Render2D
reason := r2d.init(&renderer, &materials) // "" 成功，否则处理原因后停止绘制

// 每帧：相机先压栈，物体的 transform 随后作用。
r2d.push_matrix(&renderer, camera_matrix)
err := r2d.image(&renderer, frame, transform, foster.White)
r2d.pop_matrix(&renderer)
err = r2d.rect(&renderer, {16, 16, 120, 24}, foster.White)
err = r2d.submit(&renderer, {target = target, time = elapsed, delta_time = dt})
// 每个 err 都应检查：.None 成功，mat.draw_error_text(err) 给出原因。

// 退出：先释放 UI，再释放 renderer、材质库和它们借用的资源。
r2d.dispose(&renderer)
mat.material_library_dispose(&materials)
```

`image` 接受 `foster.Subtexture`，`texture` 接受整张贴图；保留图集 UV、裁剪位置与原图锚点。
`transform` 是 Foster Matrix3x2，单位矩阵用 `foster.Matrix3x2Identity`，不能传零矩阵。
坐标以最终目标像素为单位、左上角为原点。UI 按 [最终像素采样约定](../../ui/README.md#最终像素采样与清晰度验收) 绘制。

图元有 `quad / quad_texture / rect / line / circle / triangle`，支持矩阵、裁剪、混合、
采样器和 mode 的 push/pop。完整参数、渐变和工具接口见 [REFERENCE](REFERENCE.md)。

## 材质与合批

先登记预编译效果，再 `material_load` 读取材质，或 `material_create` 按效果名创建默认实例。
普通图形不用登记效果：init 自动提供 `Sprite_Default`；UI 自动创建所需的 `Text_Msdf`。

```odin
err := r2d.image(&renderer, frame, transform, material = material)
err = r2d.texture(&renderer, &texture, transform, origin = {16, 32}, material = material)
hue := mat.instance_slot(material, "hue") // 只解析一次
cool: mat.Instance_Values
mat.instance_values_set(&cool, hue, 0.7)
err = r2d.image(&renderer, frame, transform, material = material, values = &cool)
```

- tint 在顶点颜色中，不同颜色仍可合批；color 是 `foster.Color`（RGBA 字节），默认白色。
- `[Instance]` 数值随精灵记录，未覆盖的值来自各 Pass 的材质参数，不会因取值不同拆批。
- 相邻记录只有材质指针、材质 revision、帧贴图、Pass 选择、采样、混合和裁剪一致时才合批；
  两次记录之间 `material_set_number / material_set_texture / material_reload` 会递增 revision 并断批，不逐个精灵比较参数。
  不跨材质排序，单批最多 4096 个四边形。
- 连续兼容记录按 Pass 分组：先全部 pass1，再全部 pass2。`pass_id = "body"` 只画指定 Pass。
  状态变化会结束这一段；透明遮挡顺序由调用方安排。
- 参数与贴图绑定在记录时保存；Shader、纹理、常驻缓冲借用至 submit。
  重载、销毁资源、清屏或穿插其他渲染之前先提交。
- submit 后记录与栈全部清空，失败也清空；reset 可主动丢弃。另一个目标需要重新记录。
  `renderer.draw_calls` 是最近一次提交的 Draw 数；Clock 来自提交时的 View。

内置精灵和 MSDF 文字支持 Web。`.oshader` 自定义效果、`[Instance]` 和常驻实例缓冲不支持 Web；
不支持的效果登记时返回原因，见 [材质后端](../material/README.md#内置效果与-web)。

## 大量精灵：常驻缓冲

长期保留大量精灵时用 `Sprite_Buffer`，效果须声明 Instanced 并提供缓冲变体。
每帧只记录缓冲引用，不重新上传未变化的数据。

```odin
sprites: r2d.Sprite_Buffer
reason := r2d.sprite_buffer_init(&sprites, material, capacity = count) // "" 成功
items := make([]r2d.Sprite_Item, count)
values := make([][4]f32, count * sprites.slots)
items[i] = r2d.sprite_item_make(frame, origin, transform, tint)
mat.instance_array_set(values, sprites.slots, i, hue, 0.7)
ok := r2d.sprite_buffer_upload(&sprites, items, values = values)

// 每帧，与其他图元保持记录顺序；每个选中 Pass 一次 Draw。
err := r2d.buffer(&renderer, material, &sprites, count, &atlas_texture, pass_id = "body")
err = r2d.submit(&renderer, {target = target, time = elapsed})
// 不再使用且已提交后：r2d.sprite_buffer_dispose(&sprites)
```

values 仍是平铺的 `[][4]f32`，每个精灵连续 slots 个值，nil 表示全零。
`Sprite_Item` 是 80 字节，GPU 每实例再加 `16 × slots` 字节。first 可更新局部，
count 可只画前 N 个；同一缓冲共用一张图集页，库不排序或剔除。
示例：`olib_sample/src/material2d` 的普通多 Pass 与 swarm 模式。

## 帧动画与图集

`Animation_Set` 只保存共享帧与命名区间，播放时间由调用方维护。

```odin
hero: r2d.Animation_Set
r2d.animation_set_init(&hero, "hero", origin = {16, 32})
for name in frame_names {
    subtexture, _ := r2d.atlas_subtexture(&atlas, name)
    r2d.animation_set_add_frame(&hero, subtexture, 0.1)
}
r2d.animation_set_add_animation(&hero, "walk", 0, len(frame_names))
walk := r2d.animation_set_get_animation(&hero, "walk")
frame, _ := r2d.animation_set_get_frame_at(&hero, walk, elapsed, true)
err := r2d.image(&renderer, frame.subtexture, transform, origin = hero.origin)
// 退出：r2d.animation_set_dispose(&hero)
```

追加动画后不要保留旧 Animation 指针；循环参数 false 表示停在最后一帧。
图集用 `Sprite_Atlas` 和 `atlas_subtexture`；grid、Kenney、Aseprite 各用自己的导入入口。
`aseprite_build` 的 Built_Clip 提供区域名与时长，经 atlas_subtexture 转成动画帧。
暂停、变速和结束回调由游戏实现。
