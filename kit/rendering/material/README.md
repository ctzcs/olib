# 材质系统

本包统一提供材质参数、效果描述、实例值、GPU 布局、资源加载和 Pass 执行。
使用同一个 `mat` import；各部分按职责分文件，不另设运行时子包。
GPU 资源使用 Foster，解析、编解码与布局函数不需要创建窗口或 GPU 设备。
本包不依赖 UI、编辑器或 Shader 开发工具。

## 文件与概念地图

| 文件 | 内容 |
| --- | --- |
| `declarations.odin` | `Scalar / Color / Texture_Path / Pass_Id` 等声明用的 distinct 类型 |
| `parameters.odin` | `Schema / Field / Value`：参数声明、实例数值、迁移与 GPU 布局（`hlsl` / `pack`） |
| `schema.odin` | `describe`：由 Odin 结构体反射出 `Schema` |
| `effect.odin` | `Effect_Desc / Pass_Desc`：多 Pass 声明，`effect_validate` 校验、`effect_sort` 拓扑排序，clone / dispose |
| `instance.odin`、`resource.odin` | 实例 / 单参数组的 JSON 编解码（纯字节，不碰文件与 GPU） |
| `material_library.odin` | `Material_Library`：登记 Effect、惰性创建 Shader、贴图缓存 |
| `shader_code.odin` | `Shader_Binaries / Pass_Binaries`、`shader_pick`、`material_register_directory / material_register_manifest`：按驱动选字节码并登记效果 |
| `material.odin` | `Material`：`material_load / reload / set_number / set_texture` |
| `draw.odin` | `Material_Binding / Draw_Options / Draw_Error / material_draw`：选取 Pass、上传参数、提交 DrawCommand |

包含关系（名字里的 Material 容易混，按这张图读）：

```
Material_Library ─┬─ Material_Effect ─ Effect_Desc（Pass 列表）+ []Schema + 预编译 Shader + []foster.Material（GPU）
                  ├─ Material_Texture（按路径缓存）
                  └─ Material（一个对象的实例）
                       ├─ Instance：每个参数组一份 Schema + []Value（数值与贴图路径）
                       └─ Material_Binding：Schema + Value + 指向 Effect 的 foster.Material + 采样器
```

2D 的 `r2d.image/texture` 记录几何与材质快照，`r2d.submit` 按连续兼容记录逐 Pass 绘制。
3D 的 `Render3D` 记录快照，submit 按视图剔除、排序与实例化；工具的 `r2d.material_draw` 和
`r3d.model_material_draw` 仍使用立即 Pass 执行器。Render2D 提交后清空，Render3D 保留到显式 clear。
`Draw_Options { enabled, pass_id, instance_values, user_data, prepare, submit }` 保留工具所需的
选择、参数覆盖与回调；业务只需 `pass_id` 和 `values`。

## 每个实例的值：槽位与句柄

同一个共享 `Material` 画不同变体（不同 hue、opacity……）时，不必为每种取值再建材质实例，也不必拆批。
做法分两步：

1. **效果里把参数声明成 `[Instance]`**（`Field.instance`）：它不再占 uniform，而是写进每个对象的**实例记录**，
   于是取值不同的对象仍能合成一次 Draw。Sprite 与 Model 效果都支持，最多 `MAX_INSTANCE_FIELDS`（16）个，实际个数由项目决定（见[字段个数](#字段个数由你的项目决定)），
   2D 的实例字段走顶点 storage buffer；只有常驻缓冲需要 `Effect_Desc.instanced`。3D 仍要求 instanced。着色器写法见
   [lang 的 HLSL 约定](../shader/lang/README.md#2d-效果的-hlsl-约定)。
2. **按槽位给每个实例设值**：槽位是字段在效果里声明的先后，**名字只解析一次**得到句柄，之后全按槽位赋值，没有字符串比较。

```odin
hue := mat.instance_slot(material, "hue")            // 解析一次；名字写错或不是 [Instance] 时 hue.valid == false

// 逐个绘制：Instance_Values 设置这一次绘制的实例字段，只覆盖显式设置的槽位，其余沿用材质里的值
cool: mat.Instance_Values
mat.instance_values_set(&cool, hue, 0.7)                 // 只写用到的分量：Scalar 一个、Vector3 三个，其余补 0
r2d.image(&renderer, frame, transform, material = material, values = &cool)

// 缓冲：同样的槽位，写进平铺数组（每个实例连续 buffer.slots 个 float4），上传时一并传入
mat.instance_array_set(values, sprite_buffer.slots, i, hue, 0.7)
r2d.sprite_buffer_upload(&sprite_buffer, items, values = values)
r3d.model_buffer_upload(&model_buffer, instances, values = values)
```

`Instance_Values` 是逐个绘制的"每实例值"：按槽位存的小数组，加"哪些槽位被设置过"的掩码
（以及材质回调里该 Pass 的字段数 `count`）；大批量缓冲则用平铺的 `[][4]f32`，两者按同一个槽位句柄赋值。回调 `prepare / submit` 的 `^Instance_Values` 是该 Pass 已套用全部覆盖后的实例数值。
`uniform_size / pack / hlsl` 都已跳过 `[Instance]` 字段，`hlsl(schema, mode)` 生成 `OlibInstanceInput / OlibInstance`。

**覆盖优先级**：材质实例值 < `Instance_Values`（实例字段） < Pass 的固定 `values`。
数值按字段范围钳制，非有限数值被忽略；不修改共享材质，已排队的批次也不受之后修改的影响。

### 整体参数：不是 `[Instance]` 的字段

不是 `[Instance]` 的字段是**整批共用**的统一参数，值放在 uniform 里，来自材质。想整体改它：

```odin
mat.material_set_number(material, "Sprite_body", "strength", {0.8, 0, 0, 0})   // 之后所有绘制都用 0.8
```

- 精灵合批在**记录时**就把 uniform 复制进批次，所以在两次绘制之间改它，已排队的绘制不受影响，可以临时改一下再改回去。
- 但统一参数取值不同的绘制无法合批，每个不同取值至少多一次 Draw；如果它其实是每个实例不同的值，就把它声明成 `[Instance]`。
- 只有少数几种固定变体时，再 `material_load` 一个材质文件即可，共享同一份 Shader 和贴图。

### 字段个数：由你的项目决定

库里**没有**全局的字段数配置。每个效果声明了几个 `[Instance]` 字段，就有几个槽位（`mat.instance_slot_count(material)`；
各参数组字段数不一致时为 -1）。缓冲创建时从材质读取槽数，存进 `buffer.slots`，调用方不需要自己定义常数：

```odin
r2d.sprite_buffer_init(&buffer, material, capacity)   // buffer.slots = 效果的 [Instance] 字段数
values := make([][4]f32, count*buffer.slots)         // 平铺数组：每个实例连续 slots 个 float4
mat.instance_array_set(values, buffer.slots, i, hue, 0.7)
r2d.sprite_buffer_upload(&buffer, items, values = values)
```

平铺数组里某个实例要单独绘制时，`mat.instance_values_from(values[i*slots:][:slots])` 把它转成整套覆盖值
（每个槽位都算显式设置），可直接传给 `r3d.model` / `r2d.image` 的 values。已有的 `[4]f32` 变量写成 `..color[:]`。

- 硬上限 `MAX_INSTANCE_FIELDS` = 16，只用来保护顶点属性预算：每个实例占 `5 + 槽数` 个属性，网格还要自己的属性
  （3D 常见 4 个），桌面 GPU 一般支持 16～32 个。需要更多值时，先考虑把几个标量打包进同一个 `float4` 的 xyzw。
- 内存与槽数成正比：值数组每个实例 `16 × slots` 字节，GPU 记录同理；`Sprite_Item` / `Model_Item` 本身不含字段数值，
  不会因为上限变大而变大。
- `Instance_Values`（逐个绘制用）是固定大小的小结构，最多容纳 16 个槽位。

## 约定

- **错误返回**：绘制路径返回 `Draw_Error` 枚举（记录失败不加入队列，submit 返回错误并清空本次记录）；声明、解析、加载和登记返回
  `reason: string`，空串表示成功，因为这些错误需要带上 Pass / 字段名等具体信息。文本借用至本帧
  `temp_allocator` 重置，需要保留时自行克隆。`describe`、`effect_validate`、`material_load` 等均遵循这一规则。
- **上限常量**：`MAX_PASSES`（32）、`MAX_TEXTURES`（16）、`MAX_UNIFORM_BYTES`（16384）、
  `MAX_TARGET_SIZE`（8192）、`MAX_RESOURCE_BYTES`（1 MiB）、`MAX_RESOURCE_FIELDS`（256）；
  数值只在对应常量处修改。
- **字符串所有权**：`Schema` 用 `schema_clone / schema_dispose`，`Effect_Desc` 用
  `effect_clone / effect_dispose`（内部通过 `clone_text / delete_text` 统一处理 `distinct string`）。
  新增拥有字符串或切片的字段时，须同步对应的 clone、dispose（Schema 另有 `schema_equal`）。

## 公共材质资源

```odin
import mat "olib:kit/rendering/material"

materials := mat.Material_Library{device = device, storage = &resources}
// 嵌入 tools/shaders 的整个产物目录；库按驱动选择后端，登记其中所有材质效果。
reason := mat.material_register_directory(&materials, #load_directory("shaders/Compiled"))
material, load_error := mat.material_load(&materials, "materials/hero.json")
// 检查 reason / load_error 后将 material 传给 r2d.image 或 r3d.model。
```

`material_register_directory` 遍历目录里的每个 `*.shader.json`，按清单里的参数组名找当前后端的
`<组名>.vertex / .fragment.<spv|dxil|msl>`，instanced 精灵另找 `<组名>.instanced.vertex.*`，其他文件忽略。
首个 Pass 不是 Model / Sprite 的效果只供 Shader Lab 预览，跳过；缺文件、清单过期等错误以文件名开头，
遇到第一个就返回。在 `.oshader` 里增删 Pass 或效果后只需重新运行 tools/shaders，不改 Odin 代码。

`#load_directory` 必须直接作参数或变量初始化，写成 `X :: #load_directory(...)` 编译不过。它嵌入整个目录，
产物目录最好只放本游戏用到的效果。热重载 Watch 默认只监听 `.odin`：要让重新生成的产物触发重编，
把 Compiled 目录或 `spv / dxil / msl / json` 扩展名列入 `roots` / `extensions`（与 `#load` 相同）。

字节码来自别处（自定义打包等）时，用 `material_register_manifest(&materials, manifest, passes)` 逐个登记，
`passes` 是与清单参数组一一对应的 `[]mat.Pass_Binaries`。已经自己持有 Effect、Schema 和字节码时，
用底层的 `material_register(&materials, effect, schemas, code)`，其中 `code` 用 `shader_pick(driver, binaries)` 按驱动取字节码。

每次 load 创建独立参数实例，共享同一效果的 Shader 和同路径贴图。
Effect/Schema 由库深复制，当前后端预编译字节码借用至 `material_library_dispose`。
材质和贴图使用同一个 Foster StorageContainer；材质路径相对容器根，贴图路径相对材质文件。
游戏统一使用此入口，不直接读取桌面文件。参数编解码函数处理 Storage 读取的字节；
ShaderLab 的本机路径适配属于工具内部实现，底层同样使用 Storage，不是另一套游戏加载接口。
库、device、storage 的地址及存储根在使用期间须保持稳定。

`material_set_number(material, group, field, value)` 检查类型和范围后修改单个实例。
`material_set_texture(material, group, field, texture)` 把运行时贴图（阴影图、反射等 Target 附件）绑到 Texture 字段，
采样方式取字段声明，nil 恢复白色默认贴图；贴图须属于同一设备，借用期间保持有效，不改材质文件里的路径。
不能采样的贴图返回 false（`foster.TextureIsSampleable`）：多采样深度附件（SDL 没有深度解析）和设备不支持采样的深度格式；
单采样深度附件可以绑定，例如后处理读场景深度。
`material_reload(&materials, material)` 完整候选成功后替换，失败保留旧值，材质指针不变。
它只重载材质文件，同路径贴图仍使用缓存，不自动热重载 Shader/贴图；运行时绑定的贴图恢复为文件里的贴图。
以上修改成功时 `material.revision` 递增，Render2D 据此判断已记录的参数快照是否还能合批；
不要绕过这些接口直接改 bindings 或数值。

Texture 字段的采样器由 `field_sampler(field)` 按字段的 filter（Linear / Nearest）与 wrap（Clamp / Repeat / Mirror）创建，
零值即线性、钳制。.oshader 写 `[Filter(Nearest)] [Wrap(Repeat)] _Albedo ("Albedo", 2D) = ""`，
Odin 参数结构体写 `filter:"nearest" wrap:"repeat"` 标签。Shader Lab 预览与游戏使用同一规则。
停止绘制后用 `material_library_dispose` 统一释放全部材质、Shader 和贴图；不浅复制资源对象。
加载和重载在主线程、合法 GPU 生命周期内、提交绘制之外进行。缓存按库统一释放，
目前不逐项卸载，建议按场景或资源会话划分库。
路径中的 `.`、`..`、反斜杠会规范化；导出文件含绝对贴图路径时，应先将贴图纳入资产根并改为相对路径。

## 内置效果与 Web

```odin
sprite, reason := mat.material_create(&materials, "Sprite_Default")
text, reason := mat.material_create(&materials, "Text_Msdf")
mat.material_set_number(text, "Text_Msdf", "distance_range", {4, 0, 0, 0})
```

内置效果首次使用时自动登记，直接借用设备的默认 Shader（foster 已按驱动选好，含 Web 的手写 GLSL），库只释放材质实例。
每种字体可以有独立的 Text_Msdf 实例。material_create 也支持已登记的自定义效果，
每次创建独立参数、沿用声明默认值；material_library_dispose 统一释放。

`Shader_Binaries { spv, dxil, msl }` 按驱动选择 tools/shaders 的产物，缺少对应格式返回空切片，登记失败。
Web 构建（`ODIN_OS == .JS`）没有预编译字节码：`shader_driver_supported` 返回 false，
`.oshader` 材质登记时返回 "Unsupported shader backend"；直接调用 material_register 时，
Web 只接受 Foster uniform 布局（矩阵与一个片元 float），Olib Clock/参数块、[Instance] 与实例缓冲都返回明确错误。
原生的 Private 驱动需要平台私有格式，同样不支持。

`Pass_Binaries.instanced_vertex` 是 Sprite 常驻缓冲的顶点变体（产物 `<组名>.instanced.vertex.*`，
按目录登记时自动找到）；普通批量用 vertex，两种变体共用 fragment。自定义效果代码借用到材质库释放，内置 Shader 归设备所有。

## 渲染器与工具接入

`material_library.odin` 提供 `Material_Library`，`material.odin` 提供 `Material` 和游戏材质加载入口。
`draw.odin` 提供 `Material_Binding`、`Material_Draw`、`Draw_Options`、`material_draw` 和 `pass_state_apply`，
负责选取 Pass、验证绑定、上传参数、绑定纹理、应用状态并提交 DrawCommand。
2D/3D 绘制入口与 Shader Lab 复用相同的 Pass 选择、数值覆盖与状态规则；业务通常从 `r2d.image` 或 `r3d.model` 接入。
所有绘制入口返回 `Draw_Error`，`.None` 表示成功，`draw_error_text(error)` 得到可读文本。
Render2D 记录成功不代表已提交；被禁用的 Pass 不记录。

Shader Lab 的参数作者使用 [.oshader 的 Properties](../shader/lang/README.md)。
运行时代码也可通过 `describe` 反射创建 Schema；手工构造 Schema 的调用方
须保证字段 ID 唯一、字段名可用于 HLSL、范围有效以及类型/默认值匹配。

## 数据与所有权

声明专用类型定义在 [declarations.odin](declarations.odin)：

| 类型 | 用途 |
| --- | --- |
| `Scalar` | 单个 f32 数值，默认用滑条编辑；无需 `ui:"slider"` |
| `Vector2 / Vector3` | 两/三分量数值控件；无需 `ui:"vector"` |
| `Color` | 四分量 RGBA 调色板；无需 `ui:"color"` |
| `Texture_Path` | 参数里的图片路径；自动生成 Texture 控件，无需 `ui:"texture"` |
| `Shader_Path` | 程序资源路径 |
| `Params_Ref` | `Pass_Desc.params`，引用 Schema 名称 |
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

`hlsl(schema)` 返回拥有的字符串，调用方负责 delete。shader/lang 将它直接放入每个
Pass 的候选 HLSL，无需生成或 include 参数头文件。数值参数从 fragment `b1, space3` 开始，
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
`instance_encode/decode` 提供 2D/3D 完整材质 JSON（version=2，包含 Effect 名和全部参数组）。
这些编解码函数只处理字节与数据校验；文件读取由本包的材质加载器负责。
游戏统一通过 [Material_Library](README.md#公共材质资源) 的 `material_load/reload`
从 Foster StorageContainer 读取材质与贴图，再由本包解码；自定义资源层也应通过 Storage 获取字节。
ShaderLab 内部的 [material_files.odin](../../tools/shader_lab/material_files.odin)
负责桌面文件路径和相对贴图路径换算，通过 Storage 读取与原子保存，对外使用
`save_preset/load_preset` 或 `save_material/load_material`。游戏不依赖这套工具文件接口。
ShaderLab 显式导出当前参数，不自动修改 Odin 默认值或宿主材质文档，JSON 格式保持兼容。

## 多 Pass 声明

`effect.odin` 的 `Pass_Desc / Target_Desc / Effect_Desc` 是纯数据类型；
`effect_order` = `effect_validate`（逐 Pass 检查参数组、目标、纹理输入、覆盖值与输出唯一性）
+ `effect_sort`（当前帧依赖拓扑排序，检出循环），返回拥有的拓扑顺序。
`Previous` 边跨帧，不参与排序；错误文本借用至临时分配器重置。
`effect_clone / effect_dispose` 复制和释放全部嵌套数据。
声明和 GPU 执行示例见 [Shader Lab](../../tools/shader_lab/README.md#odin-多-pass-与历史帧)。

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
`instance_decode(effect, schemas, bytes)` 返回独立候选，失败不改原实例。文件保存 Effect 的稳定名和
参数值，**不打包 Shader 或 Pass 定义**；运行时资源表必须能把这个名字解析为随游戏发布的同一份定义。
多个 Pass 引用相同参数组时共用该组数值，可用 Pass.values 固定区分。

GPU 执行见 [rendering3d 的 model_material_draw](../3d/REFERENCE.md#model_material_drawshader-lab-的底层入口)。完整实例见
`olib_sample/src/material3d`，Shader/参数的唯一来源是 `olib_sample/src/shader_lab`。
游戏业务默认使用 [Material_Library](README.md#公共材质资源)：
`material_load` 自动解析效果并加载 Shader/纹理，之后直接传给 `r3d.model`。
这里的 Instance 编解码接口留给资源层和工具使用，不要求每个游戏手动组装 GPU 绑定。

2D 使用 `.Sprite` Pass，与 `.Model` 共用 Instance、资源格式和公共加载器。
一个 Effect 内不能混合 Sprite、Model 或图像效果；Sprite 使用 2d 参数组，Model 使用 3d。
Sprite 的 `sprite_texture` 指定当前帧覆盖的 Texture 字段，无隐式贴图槽。
Sprite 默认预乘 Alpha、无剔除和深度读写；`.Premultiplied` 可显式声明预乘混合。
2D 接口及示例见 [精灵绘制](../2d/README.md#最小用法)。
