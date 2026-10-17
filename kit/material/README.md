# 材质参数描述与值

`material` 保存 Shader 参数的描述、实例值，并生成与之匹配的 HLSL 和 uniform 字节。
它不依赖 UI、编辑器或 `shaderdev`，不持有 Foster Shader/Texture。多个材质可以用
同一 `Schema` 各自创建一份 `values_make` 结果。

参数作者使用同一 Odin 包中的具名结构体，详见 [Shader 开发](../shaderdev/README.md)。
`shaderdev/paramgen` 通过 Odin 反射创建经过校验的描述；手工构造 Schema 的调用方
须保证字段 ID 唯一、字段名可用于 HLSL、范围有效以及类型/默认值匹配。

## 数据与所有权

声明专用类型定义在 [declarations.odin](declarations.odin)：

| 类型 | 用途 |
| --- | --- |
| `Scalar` | 单个 f32 数值，默认用滑条编辑；无需 `ui:"slider"` |
| `Vector2 / Vector3` | 两/三分量数值控件；无需 `ui:"vector"` |
| `Color` | 四分量 RGBA 调色板；无需 `ui:"color"` |
| `Texture_Path` | 参数里的图片路径；自动生成 Texture 控件，无需 `ui:"texture"` |
| `Shader_Path` | `X_Shader` 的 HLSL 路径 |
| `Params_Ref` | `Pass_Desc.params`，引用 `X_Params` 的前缀 X |
| `Target_Ref` | Pass 输出、输入目标和 Effect 最终输出 |
| `Field_Ref` | Texture 输入和数值覆盖的字段稳定 ID |
| `Pass_Id` | Pass 自身的稳定 ID |
| `Preview_Mode` | `.Two_D / .Three_D`；效果可用 `.Auto` 推断工作区 |

路径和引用类型是 `distinct string`；数值控件类型是独立的 f32 或 f32 数组类型。
字面量可直接赋值，但不同用途的已命名值不能混用。
推荐把重复引用声明为具名常量，例如 `Scene_Color :: mat.Target_Ref("scene_color")`，
输入和输出都使用 `Scene_Color`，由 IDE 补全。专用类型不自动发现文件或字段；
参数组/字段/目标是否存在仍由生成器校验。标签、显示名、folder 保持普通 string。
`Texture_Path` 仍只是路径，不加载 GPU 资源，不改变 HLSL 布局或增加渲染开销。
数值类型同样不改变现有字段 Kind、HLSL 布局或热重载迁移规则。`label / id / min / max / step`
标签仍可选；默认范围 0..1、步长 0.01，默认值取 Odin 零值（Color 也不会自动设为白色）。
专用类型允许省略 ui；如果显式写 ui，必须与类型匹配。旧基础类型 + ui 标签继续兼容。

- `Schema`：组名、Shader 路径、预览维度、字段列表。
- `Field`：稳定 ID、HLSL 字段名、界面标签、类型、范围、默认数值/贴图路径。
- `Value`：一份材质实例的数值和图片路径；字符串路径不是 GPU 纹理。
- `schema_clone` 深复制，`schema_dispose` 释放；`values_make` 分配实例，
  `values_dispose` 释放。调用方使用同一 allocator 创建和销毁，不浅复制拥有的数据。
- `values_make(new_schema, old_schema, old_values)` 按 ID + 类型迁移；新增字段和类型
  变化使用默认值，范围收窄时钳制。没有 `id` 标签时 ID 默认为字段名；改名要保留旧 ID。

## GPU 布局

`hlsl(schema)` 返回拥有的字符串，调用方负责 delete。编译时以
`params.generated.hlsli` 提供给 HLSL。Shader Lab 同时将可读副本保留在项目的
`library/shader_dev/<组名>/`，源码通过相对 include 供 IDE 直接解析。数值参数从 fragment `b1, space3` 开始，
**每字段独占 16 字节**，标量/向量分别取 x/xy/xyz/xyzw；不复制 Odin 结构体本身。
HLSL 参数名统一添加 `_` 前缀：Odin 的 `strength` 对应 `_strength`，纹理 `image` 对应 `_image`。
纹理字段按声明顺序分配 `t0/s0, t1/s1, …`，使用 `space2`，采样器名字为
`_字段名Sampler`。引擎公共输入使用 fragment b0，顶点输入由宿主决定。

用 `uniform_size` 分配缓冲，然后 `pack` 写入，将字节交给
`foster.MaterialStageSetUniformBuffer(&material.Fragment, bytes, 1)`。
宿主负责把图片路径加载为纹理并设置 Foster material 的 sampler。
支持 `Scalar / Vector2 / Vector3 / Color / Texture_Path`，兼容旧基础类型 + ui 标签；暂不支持矩阵、通用数组、整数、
嵌套结构体或 vertex 材质参数。

这个包没有实现材质存档格式/资源管线导入器。Shader Lab 支持显式导出预览参数快照，
不把预览会话当成宿主材质文档，也不改写 Odin 默认值。

## 多 Pass 声明

`passes.odin` 的 `Pass_Desc / Target_Desc / Effect_Desc` 是纯数据类型；
`effect_order` 检查纹理字段、输出唯一性和当前帧依赖循环，返回拥有的拓扑顺序。
`Previous` 边跨帧，不参与排序；错误文本借用至临时分配器重置。
`effect_clone / effect_dispose` 复制和释放全部嵌套数据。
声明和 GPU 执行示例见 [Shader Lab](../tools/shader_lab/README.md#odin-多-pass-与历史帧)。
