# 材质系统

游戏用的材质入口：材质库、材质加载与修改、每实例的值、按驱动选字节码与登记效果。
效果、参数组和 Pass 的描述，参数打包、HLSL 生成与文件编解码在下层的
[shader](../shader/README.md)（`sh`），给渲染器、Shader 工具链和 Shader Lab 用，游戏一般不 import。
本包不依赖 UI、编辑器或 Shader 开发工具。

游戏常用的就是下面这些：

| 用途 | API |
| --- | --- |
| 材质库与登记 | `Material_Library`、`material_register_directory`、`material_register_manifest`、`material_library_dispose` |
| 材质 | `Material`、`material_load`、`material_reload`、`material_create`、`material_set_number`、`material_set_texture` |
| 每实例的值 | `Instance_Values`、`instance_slot`、`instance_slot_count`、`instance_values_set`、`instance_values_from`、`instance_array_set` |
| 绘制结果与 Pass | `Pass_Id`（`r2d.image` / `r3d.submit` 的 pass_id）、`Draw_Error`、`draw_error_text` |
| 手写 Shader | `Shader_Binaries`、`shader_pick`、`shader_driver_supported`、`std140_write_vec4`、`std140_write_matrix` |

## 文件与概念地图

| 文件 | 内容 |
| --- | --- |
| `material_library.odin` | `Material_Library`：登记 Effect、惰性创建 Shader、贴图缓存 |
| `shader_code.odin` | `Shader_Binaries / Pass_Binaries`、`shader_pick`、`material_register_directory / material_register_manifest`：按驱动选字节码并登记效果 |
| `material.odin` | `Material`：`material_load / reload / set_number / set_texture` |
| `draw.odin` | `Material_Binding / Draw_Error / material_select / pass_state_apply`：Render2D / Render3D 共用的 Pass 选择、绑定检查、参数打包与 Pass 状态 |

包含关系（名字里的 Material 容易混，按这张图读；`sh.` 开头的类型在 shader）：

```
Material_Library ─┬─ Material_Effect ─ sh.Shader_Desc（Pass 列表）+ []sh.Schema + 预编译 Shader + []foster.Material（GPU）
                  ├─ Material_Texture（按路径缓存）
                  └─ Material（一个对象的实例）
                       ├─ sh.Instance：每个参数组一份 Schema + []Value（数值与贴图路径）
                       └─ Material_Binding：Schema + Value + 指向 Effect 的 foster.Material + 采样器
```

2D 的 `r2d.image/texture` 记录几何与材质快照，`r2d.submit` 按连续兼容记录逐 Pass 绘制。
3D 的 `Render3D` 记录快照，submit 按视图剔除、排序与实例化。Render2D 提交后清空，Render3D 保留到显式 clear。
Shader Lab 的材质预览也走这两个渲染器：`material_from_bindings` 用工具自己持有的效果与 GPU 绑定组成 `Material`
（不登记、不拥有资源），之后与游戏的材质一样记录、提交。

## 每个实例的值：槽位与句柄

同一个共享 `Material` 画不同变体（不同 hue、opacity……）时，不必为每种取值再建材质实例，也不必拆批。
做法分两步：

1. **效果里把参数声明成 `[Instance]`**（`Field.instance`）：它不再占 uniform，而是写进每个对象的**实例记录**，
   于是取值不同的对象仍能合成一次 Draw。Sprite 与 Model 效果都支持，最多 `MAX_INSTANCE_FIELDS`（16）个，实际个数由项目决定（见[字段个数](#字段个数由你的项目决定)），
   2D 的实例字段走顶点 storage buffer；只有常驻缓冲需要 `Shader_Desc.instanced`。3D 仍要求 instanced。着色器写法见
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
（以及该 Pass 的字段数 `count`）；大批量缓冲则用平铺的 `[][4]f32`，两者按同一个槽位句柄赋值。

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
  `temp_allocator` 重置，需要保留时自行克隆。`material_load`、`material_register_directory` 等均遵循这一规则。
- 上限常量（Pass、贴图、参数字节、实例字段数等）与字符串所有权规则见 [shader](../shader/README.md#约定)。

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
`passes` 是与清单参数组一一对应的 `[]mat.Pass_Binaries`。

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

Texture 字段的采样方式由 .oshader 声明：`[Filter(Nearest)] [Wrap(Repeat)] _Albedo ("Albedo", 2D) = ""`，没写时线性、钳制。
精灵纹理字段例外：只用显式写了的部分，没写的部分跟随 Render2D 的 `push_sampler`（规则见 `sh.field_sprite_sampler`）。
Shader Lab 预览与游戏使用同一规则。
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
`.oshader` 材质登记时返回 "Unsupported shader backend"；Web 只接受 Foster uniform 布局（矩阵与一个片元 float），
Olib Clock/参数块、[Instance] 与实例缓冲都返回明确错误。
原生的 Private 驱动需要平台私有格式，同样不支持。

`Pass_Binaries.instanced_vertex` 是 Sprite 常驻缓冲的顶点变体（产物 `<组名>.instanced.vertex.*`，
按目录登记时自动找到）；普通批量用 vertex，两种变体共用 fragment。自定义效果代码借用到材质库释放，内置 Shader 归设备所有。

## 渲染器与工具接入

`draw.odin` 提供 `Material_Binding`、`material_select`、`material_pass_values` 和 `pass_state_apply`：
Render2D / Render3D 记录时用它们选取 Pass、检查绑定、打包参数并应用 Pass 状态；Shader Lab 通过这两个渲染器预览，
规则与游戏完全相同。业务从 `r2d.image` 或 `r3d.model` 接入。
所有绘制入口返回 `Draw_Error`，`.None` 表示成功，`draw_error_text(error)` 得到可读文本。
Render2D 记录成功不代表已提交；被禁用的 Pass 不记录。

Shader Lab 的材质预览用 `material_from_bindings` 把工具自己持有的效果与 GPU 绑定组成 `Material`（不登记、不拥有资源），
之后与游戏的材质一样记录、提交。

材质文件只保存效果的稳定名和各参数组的值，不打包 Shader 或 Pass 定义；运行时资源表（材质库）必须能把这个名字
解析为随游戏发布的同一份定义。Pass、参数组、目标的声明规则、HLSL 布局与编解码格式见
[shader](../shader/README.md)。完整实例见 `olib_sample/src/material2d`、`src/material3d`，
Shader/参数的唯一来源是 `olib_sample/src/shader_lab`。2D 接口见 [精灵绘制](../2d/README.md#最小用法)，
3D 见 [Render3D](../3d/README.md)。
