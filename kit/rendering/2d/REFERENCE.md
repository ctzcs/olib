# Render2D 参考

业务用法见 [README](README.md)。图集、动画与常驻缓冲操作保留类型前缀。

## 入口

| 入口 | 用途 |
| --- | --- |
| `init(r, library) -> string` | 从材质库取设备，空串成功 |
| `dispose(r)` / `reset(r)` | 释放资源 / 丢弃记录并重置状态 |
| `image(r, frame, transform, color = White, origin = {}, material = nil, values = nil, pass_id = "")` | 子图 |
| `texture(r, texture, transform, color = White, origin = {}, material = nil, values = nil, pass_id = "")` | 整张贴图 |
| `quad_texture` / `quad` / `rect` / `line` / `triangle` / `circle` | 参数见 [render2d.odin](render2d.odin) |
| `quad_gradient` / `rect_gradient` / `circle_gradient` / `circle_line` | 渐变与圆环 |
| `text` | Foster SpriteFont；kit/ui 字体走 UI 后端 |
| `buffer(r, material, buf, count, texture, pass_id = "")` | 记录常驻 Sprite_Buffer |
| `submit(r, View) -> mat.Draw_Error` | 唯一批量提交点，随后清空记录与栈 |

图元也返回 Draw_Error。记录时检查材质、设备、Pass 选择；提交时检查目标。
空提交返回 .None；被禁用的已知 Pass 不记录，未知 ID 返回 .Unknown_Pass。
`View { target, time, delta_time, frame, pointer }` 的 pointer 为归一化坐标。

## 状态栈

`push_matrix(Matrix3x2, relative = true)`、`push_matrix_trs(position, scale, rotation, relative = true)`
和 `push_matrix_raw([16]f32, relative = true)` 共用矩阵栈，pop_matrix 恢复上一级。
原始 4×4 矩阵使用行向量约定；先作用新矩阵，再接已有矩阵。相机先 push，物体随后相对 push。

`push_scissor(RectInt)`、`push_blend(BlendMode)`、`push_sampler(TextureSampler)`、
`push_mode(BatcherMode)` 各自配对 pop。裁剪在最终目标像素坐标中，不随矩阵变换。
默认最近点/Clamp、预乘 Alpha、无裁剪、Normal mode；Normal/Wash/Fill 仅内置效果使用。
submit/reset 后恢复默认，不应靠状态跨帧保留。

## Shader 约定

所有 Pass 使用 .Sprite，sprite_texture 指定当前帧覆盖的纹理字段 ID。
输出预乘颜色，默认无剔除和深度读写；Pass 的显式状态覆盖记录状态。

- 普通顶点使用 `foster.BatcherVertex`：已套用变换栈的目标像素位置、UV、RGBA 字节色和 mode 字节。
  .oshader 效果的 mode 存 storage buffer 中该精灵记录的起始 float4 下标（0 保留）；记录首项是两条轴，再接各 Pass 的实例字段。
- 顶点 b0/space1 为投影（64 字节）后接 Clock，共 80 字节；b1/space1 为当前 Pass 的数值偏移，
  由生成器的 olib_sprite 使用。所有精灵、所有 Pass 的记录在 submit 时一次上传。
- Olib 片元 b0/space3 为 Clock、Pointer、白色 Tint，共 48 字节；参数在 b1/space3。
  顶点 tint 用生成的 InstanceTint；纹理和采样器在 space2。
- 内置效果使用 Foster uniform 布局：顶点槽 0 为矩阵，MSDF 片元槽 0 为 distance_range。
- 缓冲变体用单位四边形和实例顶点，数值来自调用方缓冲，不使用 storage 或 Pass 偏移。
  顶点 b0 与批量变体相同；b1/space1 是记录时变换栈的 2D 仿射部分（两个 float4），olib_sprite 在 GPU 上套用，
  因此两种变体的 position 与轴都在目标像素空间。变换栈的非仿射部分在两种变体里都不使用。

作者统一写 OlibSpriteInput / olib_sprite，见 [lang README](../shader/lang/README.md#2d-效果的-hlsl-约定)。
索引缓冲按容量增长后复用，顶点与实例数值每次 submit 上传，不在图元调用中发 Draw。
