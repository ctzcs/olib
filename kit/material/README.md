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

`resource_encode/decode` 提供单参数组 JSON（version=1，兼容 Shader Lab 预设）；
`instance_encode/decode` 提供模型材质 JSON（version=2，包含 Effect 名和全部参数组）。
字节接口没有文件系统依赖，可以接 `kit/storage`；桌面另有原子文件保存与相对贴图路径处理的
`resource_save/load`、`instance_save/load`。这不是资产导入器；GPU 纹理仍由游戏资产系统加载。
Shader Lab 显式导出当前参数，不自动修改 Odin 默认值或宿主材质文档。

## 多 Pass 声明

`passes.odin` 的 `Pass_Desc / Target_Desc / Effect_Desc` 是纯数据类型；
`effect_order` 检查纹理字段、输出唯一性和当前帧依赖循环，返回拥有的拓扑顺序。
`Previous` 边跨帧，不参与排序；错误文本借用至临时分配器重置。
`effect_clone / effect_dispose` 复制和释放全部嵌套数据。
声明和 GPU 执行示例见 [Shader Lab](../tools/shader_lab/README.md#odin-多-pass-与历史帧)。

## 挂在对象上的多 Pass 材质

层级为 **材质实例 → Effect 定义 → Pass → Shader**。`foster.Material` 仍是单次绘制的底层
绑定；模型使用的 `material.Instance` 拥有各参数组的值和贴图路径，多份实例可以共享 Effect 和 GPU Shader。

把每个 Pass 声明为 `draw = .Model`，全部 `output` 指向 Effect.output，`target` 描述相同：

```odin
passes := []mat.Pass_Desc{
    {id = "body", params = "Surface", draw = .Model, output = "color",
        state = {cull = .Back, blend = .Opaque, depth = .Less, depth_write = .On}},
    {id = "outline", params = "Outline", draw = .Model, output = "color",
        state = {cull = .Front, blend = .Opaque, depth = .Less_Equal, depth_write = .Off}},
}
```

- 模型 Pass 按声明顺序绘制**同一网格**，共享外部目标的颜色和深度，每 Pass 之间不清屏。
  `target` 用于 Shader Lab 建预览目标；游戏渲染器提供自己的场景目标。
- `state` 支持剔除、混合、深度比较和深度写入。Model 默认不透明、背面剔除、Less 深度读写；
  显式 `Default` 保留执行器/宿主状态。Alpha 是非预乘，Additive 是 One+One。
- `values` 是 Pass 固定覆盖，临时应用，不修改材质实例；面板的 Pass 启停只是预览状态。
- Model 不能混用 Fullscreen/Preview_Model，也不能使用图目标输入或历史帧；这些仍由图像效果执行。
  图像效果继续要求输出唯一，不能靠重名输出叠加模型。

`instance_make(effect, schemas)` 校验定义并独立拥有 Schema/Value；`instance_dispose` 释放。
`instance_load(effect, schemas, path)` 返回独立候选，失败不改原实例。文件保存 Effect 的稳定名和
参数值，**不打包 Shader 或 Pass 定义**；运行时资源表必须能把这个名字解析为随游戏发布的同一份定义。
多个 Pass 引用相同参数组时共用该组数值，可用 Pass.values 固定区分。

GPU 执行见 [rendering3d](../rendering3d/README.md#模型材质执行)。完整实例见
`olib_sample/src/material3d`，Shader/参数的唯一来源是 `olib_sample/src/shader_lab`。
游戏业务默认使用 [Material_Library](../rendering/README.md#公共材质资源)：
`material_load` 自动解析效果并加载 Shader/纹理，赋给 `Model.material` 后调用 `model_draw`。
这里的 Instance 编解码接口留给资源层和工具使用，不要求每个游戏手动组装 GPU 绑定。

2D 使用 `.Sprite` Pass，与 `.Model` 共用 Instance、资源格式和公共加载器。
一个 Effect 内不能混合 Sprite、Model 或图像效果；Sprite 使用 2d 参数组，Model 使用 3d。
Sprite 的 `sprite_texture` 指定当前帧覆盖的 Texture 字段，无隐式贴图槽。
Sprite 默认预乘 Alpha、无剔除和深度读写；`.Premultiplied` 可显式声明预乘混合。
2D 接口及示例见 [材质 Sprite](../rendering/README.md#材质-sprite)。
