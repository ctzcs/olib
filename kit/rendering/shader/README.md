# Shader 描述层（kit/rendering/shader）

一个 `.oshader` 文件就是一个 Shader（文件里的 `Shader "Name"` 是它的名字），层级与 Unity 相同：Shader → Pass，
参数值放在 Material 里。不设 SubShader：olib 只有一条渲染路径，后端差异由 shadercross 处理。

| 词 | 指什么 |
| --- | --- |
| Shader | 一个 `.oshader`：`sh.Shader_Desc` + 参数组 + 每个参数组一份 HLSL |
| 材质 Shader | Pass 全是 `Sprite` 或全是 `Model`，用 `mat.Material` 挂在物体上画 |
| 全屏 Shader | Pass 是 `Fullscreen` / `Preview_Model` 的多 Pass 图，目前只在 Shader Lab 里运行 |
| 参数组（Schema） | 每个 Pass 一组，字段来自 Properties |
| program | 每个参数组编译出的 GPU 顶点 + 片元程序（`foster.Shader`） |
| 后处理 | 游戏里的全屏处理：一个 `Draw Sprite` 的材质 Shader 画在场景 Target 上，见 [material](../material/README.md#全屏后处理) |

本包是材质下面的一层：Shader、Pass、参数组的描述与校验，参数打包、HLSL 生成，以及材质 / 预设文件的编解码。
全部是纯数据和字节，不碰文件与 GPU 设备（唯一的 Foster 依赖是 Texture 字段的采样器类型）。

谁用它：[material](../material/README.md) 的材质库、Render2D / Render3D、[shader/lang](lang/README.md)
（`.oshader` 解析成这里的类型）、[shader/dev](dev/README.md)、tools/shaders 与 Shader Lab。
游戏一般不 import 本包：材质用 `mat`，记录时用的 Pass ID 是 `mat.Pass_Id`（与 `sh.Pass_Id` 同一类型）。

```odin
import sh "olib:kit/rendering/shader"
```

## 文件

| 文件 | 内容 |
| --- | --- |
| `declarations.odin` | `Params_Ref / Target_Ref / Field_Ref / Pass_Id` 稳定引用（distinct string），`clone_text / delete_text` |
| `parameters.odin` | `Schema / Field / Value`：参数声明、实例数值、迁移与 GPU 布局（`hlsl` / `pack`），Texture 字段采样器 |
| `shader.odin` | `Shader_Desc / Pass_Desc / Target_Desc`：多 Pass 声明，`shader_validate` 校验、`shader_sort` 拓扑排序，clone / dispose |
| `instance.odin` | `Instance`：完整材质文件（version=2）的创建与编解码 |
| `resource.odin` | `Resource`：单参数组预设（version=1）的编解码 |

## 约定

- 声明、解析和编解码返回 `reason: string`，空串表示成功；文本借用至本帧 `temp_allocator` 重置，需要保留时自行克隆。
- **上限常量**：`MAX_PASSES`（32）、`MAX_TEXTURES`（16）、`MAX_UNIFORM_BYTES`（16384）、`MAX_INSTANCE_FIELDS`（16）、
  `MAX_TARGET_SIZE`（8192）、`MAX_RESOURCE_BYTES`（1 MiB）、`MAX_RESOURCE_FIELDS`（256）；数值只在对应常量处修改。
- **字符串所有权**：`Schema` 用 `schema_clone / schema_dispose`，`Shader_Desc` 用 `shader_clone / shader_dispose`
  （内部通过 `clone_text / delete_text` 统一处理 `distinct string`）。新增拥有字符串或切片的字段时，
  须同步对应的 clone、dispose。

## 参数组：Schema / Field / Value

- `Schema`：组名、Shader 路径、预览维度、字段列表。
- `Field`：稳定 ID、HLSL 字段名、界面标签、类型（`Kind`）、范围、默认数值/贴图路径；`instance` 标记 `[Instance]` 字段；
  Texture 字段另有 `filter / wrap` 与 `filter_declared / wrap_declared`（.oshader 里是否显式写过）。
- `Value`：一份材质实例的数值和图片路径；字符串路径不是 GPU 纹理。
- `values_make` 分配实例，`values_dispose` 释放。调用方使用同一 allocator 创建和销毁，不浅复制拥有的数据。
- `values_make(new_schema, old_schema, old_values)` 按 ID + 类型迁移；新增字段和类型变化使用默认值，范围收窄时钳制。
  没有显式 Id 时 ID 默认为字段名；改名要保留旧 ID。

参数组由 [.oshader 的 Properties](lang/README.md) 声明；手工构造 Schema 的调用方
须保证字段 ID 唯一、字段名可用于 HLSL、范围有效以及类型/默认值匹配。

引用类型是 `distinct string`：字面量可直接赋值，但不同用途的已命名值不能混用。推荐把重复引用声明为具名常量，
例如 `Scene_Color :: sh.Target_Ref("scene_color")`，输入和输出都使用它。专用类型不自动发现文件或字段；
参数组/字段/目标是否存在仍由校验报告。

### 采样器

`field_sampler(field)` 按字段的 filter（Linear / Nearest）与 wrap（Clamp / Repeat / Mirror）创建采样器，零值即线性、钳制。
精灵纹理字段用 `field_sprite_sampler(field, inherited)`：显式写了的部分按字段，没写的部分沿用 `inherited`
（Render2D 的 `push_sampler`，默认 Nearest、Clamp）。

## GPU 布局

`hlsl(schema)` 返回拥有的字符串，调用方负责 delete。shader/lang 将它直接放入每个 Pass 的候选 HLSL，
无需生成或 include 参数头文件。数值参数从 fragment `b1, space3` 开始，**每字段独占 16 字节**，
标量/向量分别取 x/xy/xyz/xyzw。HLSL 参数名统一添加 `_` 前缀：字段 `strength` 对应 `_strength`，纹理 `image` 对应 `_image`。
纹理字段按声明顺序分配 `t0/s0, t1/s1, …`，使用 `space2`，采样器名字为 `_字段名Sampler`。
引擎公共输入使用 fragment b0（见 [olib 标准 include](lang/README.md)），顶点输入由宿主决定。

用 `uniform_size` 分配缓冲，然后 `pack` 写入，将字节交给 `foster.MaterialStageSetUniformBuffer(&material.Fragment, bytes, 1)`。
宿主负责把图片路径加载为纹理并设置 Foster material 的 sampler。
`uniform_size / pack / hlsl` 都跳过 `[Instance]` 字段，`hlsl(schema, mode)` 生成 `OlibInstanceInput / OlibInstance`。
支持 Scalar / Vector2 / Vector3 / Color / Texture 五种字段；暂不支持矩阵、通用数组、整数、嵌套结构体或 vertex 材质参数。

## 文件格式

`resource_encode/decode` 提供单参数组 JSON（version=1，Shader Lab 预设）；
`instance_encode/decode` 提供 2D/3D 完整材质 JSON（version=2，包含 Shader 名和全部参数组）。
这些函数只处理字节与数据校验；游戏统一通过 [材质库](../material/README.md#公共材质资源) 的 `material_load / reload`
从 Foster StorageContainer 读取材质与贴图。Shader Lab 内部的 [material_files.odin](../../tools/shader_lab/material_files.odin)
负责桌面文件路径和相对贴图路径换算，通过 Storage 读取与原子保存。

`instance_make(shader, schemas)` 校验定义并独立拥有 Schema/Value；`instance_dispose` 释放。
`instance_decode(shader, schemas, bytes)` 返回独立候选，失败不改原实例。文件保存 Shader 的稳定名和参数值，
**不打包 Shader 或 Pass 定义**。多个 Pass 引用相同参数组时共用该组数值，可用 Pass.values 固定区分。

## 多 Pass 声明

`Pass_Desc / Target_Desc / Shader_Desc` 是纯数据类型；
`shader_order` = `shader_validate`（逐 Pass 检查参数组、目标、纹理输入、覆盖值与输出唯一性）
+ `shader_sort`（当前帧依赖拓扑排序，检出循环），返回拥有的拓扑顺序。
`Previous` 边跨帧，不参与排序。声明和 GPU 执行示例见
[Shader Lab](../../tools/shader_lab/README.md#odin-多-pass-与历史帧)。

### 挂在对象上的多 Pass 材质

层级为 **材质实例 → Shader → Pass → 程序**。`foster.Material` 仍是单次绘制的底层绑定；
`Instance` 拥有各参数组的值和贴图路径，多份实例可以共享 Shader 与它的 GPU 程序。
把每个 Pass 声明为 `draw = .Model`，全部 `output` 指向 Shader_Desc.output，`target` 描述相同：

```odin
passes := []sh.Pass_Desc{
    {id = "body", params = "Surface", draw = .Model, output = "color",
        state = {cull = .Back, blend = .Opaque, depth = .Less, depth_write = .On}},
    {id = "outline", params = "Outline", draw = .Model, output = "color",
        state = {cull = .Front, blend = .Opaque, depth = .Less_Equal, depth_write = .Off}},
}
```

- 模型 Pass 按声明顺序绘制**同一网格**，共享外部目标的颜色和深度，每 Pass 之间不清屏。
  `target` 用于 Shader Lab 建预览目标；游戏渲染器提供自己的场景目标。
- `state` 支持剔除、混合、深度比较和深度写入。Model 默认不透明、背面剔除、Less 深度读写；
  显式 `Default` 保留宿主状态。Alpha 是非预乘，Additive 是 One+One。
- `values` 是 Pass 固定覆盖，临时应用，不修改材质实例；面板的 Pass 启停只是预览状态。
- Model 不能混用 Fullscreen/Preview_Model，也不能使用图目标输入或历史帧；这些仍由全屏 Shader 执行。
  全屏 Shader 继续要求输出唯一，不能靠重名输出叠加模型。

2D 使用 `.Sprite` Pass，与 `.Model` 共用 Instance、资源格式和公共加载器。
一个 Shader 内不能混合 Sprite、Model 或全屏 Shader；Sprite 使用 2d 参数组，Model 使用 3d。
Sprite 的 `sprite_texture` 指定当前帧覆盖的 Texture 字段，无隐式贴图槽。
Sprite 默认预乘 Alpha、无剔除和深度读写；`.Premultiplied` 可显式声明预乘混合。
