# 3D 渲染参考：手写 HLSL 与底层接口

业务绘制见 [README](README.md)。本文给自己写渲染器（不经过材质系统）和集成 Shader Lab 的人看。
完整可运行的手写渲染器是 olib_sample 的 `src/forward3d`（Standard PBR 前向渲染：方向光、点光、聚光、半透明排序），
复制到游戏里按画风改写即可。

## 常驻实例缓冲

静态的百万级实例可在加载时上传一次，随后只记录缓冲引用。普通动态模型优先用 README 的 models。

```odin
instances: r3d.Model_Buffer
reason := r3d.model_buffer_init(&instances, material, capacity = 1_000_000) // 空串成功
// items: []Model_Item；values: [][4]f32，每个实例连续 instances.slots 个 float4。
ok := r3d.model_buffer_upload(&instances, items, values = values)

r3d.clear(&renderer)
err := r3d.buffer(&renderer, &mesh, material, &instances, count, bounds = &world_bounds)
err = r3d.submit(&renderer, view, "body")
// 释放前先 clear/dispose renderer。
r3d.clear(&renderer)
r3d.model_buffer_dispose(&instances)
```

- buffer 的 bounds 是整块实例的**世界 AABB**；只做整块剔除、排序，不读回或逐实例重排。
  透明块内部顺序由调用方负责。无盒时保留整块，并用世界原点作为排序位置。
- count 必须在 0..capacity 内；缓冲槽数必须匹配 instanced Shader，资源必须属于同一设备。
  每个所选 Pass 绘制一次；重复 submit 不重新上传常驻数据。
- 每实例 `80 + 16×slots` 字节。更新部分数据用 `model_buffer_upload(..., first = offset)`。
  upload 的 nil values 表示全零；model/models 的 nil values 表示材质默认值，两者不同。
- 常驻实例字段和 tint 完全来自缓冲，不套用材质默认实例值或 Pass 的实例字段覆盖；
  各 Pass 的非实例 uniform、纹理与状态仍独立生效。需要每 Pass 不同实例值时用 models 或自行提供不同缓冲。
- 自动实例化的临时缓冲按 [Instance] 字段数各一个、复用容量。每次 submit 在发 Draw 之前把全部批次、
  全部所选 Pass 的实例数据一次上传（同一批的各 Pass 连续存放），绘制时用 `DrawCommand.InstanceOffset`
  （Foster L-017，即 SDL first_instance）取各自那一段，上传只在提交开头打断一次渲染通道。
  生成的 Shader 不使用 SV_InstanceID，自己写的 instanced Shader 也不要依赖它。

## 记录缓存与 revision

Render3D 按材质指针缓存准备结果：Pass 选择、参数 uniform 快照（来源）和各 Pass 的实例值表（`mat.Instance_Table`）。
命中条件是 `material.revision` 与 Shader 指针都没变；clear 时清空。`material_set_number / material_set_texture /
material_reload` 成功时都会递增 revision，所以只经这些接口修改材质时缓存总是对的；
绕过它们直接改 bindings 或数值不会被发现，已记录与之后记录的对象都沿用旧快照（Render2D 的合批规则相同）。
缓存失效时按 uniform 内容查找已有快照，改回原值会复用原来的快照。

实例值表把材质值与 Pass 固定值预先合好，逐实例只按槽位覆盖与钳制；手写渲染器需要同样规则时用
`mat.instance_table_make(pass, binding)` 建表、`mat.instance_table_write(&table, numbers, set, out)` 逐实例写出，
结果与 `mat.material_pass_values` 的实例值相同。

## 手写队列、LOD 与独立调试线

```odin
queue: r3d.Render_Queue(My_Draw)
r3d.queue_clear(&queue)
r3d.queue_submit(&queue, draw, r3d.queue_view_depth(&camera, draw.transform), transparent = false)
r3d.queue_sort(&queue)
for item in queue.items { /* 自己的 DrawCommand */ }
// 退出时 queue_dispose。
```

默认排序与 forward3d 一致：不透明前到后、透明后到前，同深度稳定。
可选 queue_submit 的 group 键与 `queue_sort(..., grouped = true)` 开启不透明分组，
组按最近深度、同深度按 group 键排列，组内前到后；透明仍全局后到前。
使用可复用工作区的稳定 O(n log n) 归并排序，Render3D 内部也用这一实现。

LOD 独立使用 `Model_Lod`、`model_lod_init / select`，或 `Lod_Selector`、`lod_screen_height`；
Render3D 不自动选 LOD。调试线只有 Render3D 的 `line / aabb / sphere / frustum / axis / grid / skeleton` 一套；
手写渲染器另建一个只记录调试线的 Render3D，画完 submit 再 clear。

## 模型材质 Shader 布局

| 绑定 | 内容 |
| --- | --- |
| 静态顶点 | TEXCOORD0..3：位置、法线、UV、切线，48B |
| vertex b0 | WVP + World + Clock + CameraPosition（`MATERIAL_VERTEX_BLOCK_SIZE`，160B）；instanced 时 WVP 位置为 VP、World 为单位矩阵 |
| fragment b0 | Clock、Pointer（xy 为 0，zw 为目标像素尺寸）、Tint、CameraPosition（`MATERIAL_FRAME_BLOCK_SIZE`，64B） |
| fragment b1 | 材质非实例参数 |
| vertex b1 / fragment b2 | 视图块：`View.globals` 补零到 `mat.VIEW_GLOBALS_SIZE`（1024B），两阶段同一份字节；Shader Lab 预览为全零 |
| vertex b2 / b3 | 预留给将来的蒙皮 palette（SDL GPU 每阶段 4 个 uniform 槽，顶点阶段至此用满） |
| space2 | 材质纹理和采样器；采样方式取字段的 `[Filter]` / `[Wrap]` 声明 |

CameraPosition 是 `r3d.camera_position(view.view_matrix)`：世界坐标 xyz、w = 1，视矩阵不可逆时为原点。
vertex b0 与 fragment b0 的声明在 `#include "olib/model.hlsli"`（见 [标准 include](../shader/lang/README.md#引擎块与标准-include)）。
手写时也可只声明用到的前缀，例如片元只读 Clock 时 `cbuffer FrameBlock { float4 Clock; }` 照常工作。
Model Shader 的 Shader 按顶点 2 个、片元 3 个 uniform 槽创建；不声明视图块的旧 Shader 不受影响。Foster 布局的内置 Shader 没有视图块。

model 的 Tint 为白色；非 instanced models 使用 Model_Item.tint；instanced 模型的 tint 来自实例缓冲。
实例输入属性在前，网格属性位置后移 `5 + slots`，详见 [instanced HLSL 约定](../shader/lang/README.md#instanced-shader-的-hlsl-约定)。
普通材质不生成隐式 instanced Shader 变体。静态格式以外的网格返回 `.Unsupported_Mesh`。

## 手写一个着色器

### 1. HLSL

一个 `.hlsl` 同时包含 `vertex_main` 和 `fragment_main`；共用代码放进 `.hlsli`（编译脚本跳过 `.hlsli`）。

```hlsl
// 顶点 uniform：b*, space1   片元 uniform：b*, space3   片元贴图/采样器：t*/s*, space2（SDL GPU 固定约定）
cbuffer VertexBlock : register(b0, space1) { float4x4 WorldViewProjection; float4x4 World; };
cbuffer ToonBlock : register(b0, space3) { float4 BaseColor; float4 LightDir; };
Texture2D Albedo : register(t0, space2);
SamplerState AlbedoSampler : register(s0, space2);

// TEXCOORDn = VertexFormat 的第 n 个元素；这四项与 mesh_static_format 一致
struct VsInput { float3 Position : TEXCOORD0; float3 Normal : TEXCOORD1; float2 Uv : TEXCOORD2; float4 Tangent : TEXCOORD3; };
struct VsOutput { float4 Position : SV_Position; float3 Normal : TEXCOORD0; float2 Uv : TEXCOORD1; };

VsOutput vertex_main(VsInput i)
{
    VsOutput o;
    o.Position = mul(float4(i.Position, 1), WorldViewProjection); // mul(v, M)
    o.Normal = mul(i.Normal, (float3x3)World);
    o.Uv = i.Uv;
    return o;
}

float4 fragment_main(VsOutput i) : SV_Target0
{
    float n = saturate(dot(normalize(i.Normal), -LightDir.xyz));
    return Albedo.Sample(AlbedoSampler, i.Uv) * BaseColor * (n > 0.5 ? 1.0 : 0.4);
}
```

### 2. 编译

需要 PATH 上的 [SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross)。在游戏根目录：

```bash
odin run ../olib/tools/shaders -- -dir:src/shaders
```

产物写到 `src/shaders/Compiled/`（`Toon.vertex.{spv,dxil,msl}`、`Toon.fragment.{spv,dxil,msl}`），**提交进仓库**；
平时构建只 `#load` 它们，只有改了 HLSL 才需要 shadercross。

### 3. 装载与绘制

```odin
Toon :: struct {
	vertex, fragment: foster.Shader,
	material:         foster.Material,
}

toon_init :: proc(t: ^Toon, device: ^foster.GraphicsDevice) -> bool {
	if !mat.shader_driver_supported(device.Driver) do return false
	d := device.Driver
	// SamplerCount / UniformBufferCount 必须与 HLSL 声明的数量一致
	foster.ShaderInit(&t.vertex, device, {Stage = .Vertex, UniformBufferCount = 1, EntryPoint = "vertex_main",
		Code = mat.shader_pick(d, {
		spv = #load("shaders/Compiled/Toon.vertex.spv"),
		dxil = #load("shaders/Compiled/Toon.vertex.dxil"),
		msl = #load("shaders/Compiled/Toon.vertex.msl")})}, "toon vertex")
	foster.ShaderInit(&t.fragment, device, {Stage = .Fragment, SamplerCount = 1, UniformBufferCount = 1, EntryPoint = "fragment_main",
		Code = mat.shader_pick(d, {
		spv = #load("shaders/Compiled/Toon.fragment.spv"),
		dxil = #load("shaders/Compiled/Toon.fragment.dxil"),
		msl = #load("shaders/Compiled/Toon.fragment.msl")})}, "toon fragment")
	if t.vertex.Resource == nil || t.fragment.Resource == nil do return false
	foster.MaterialInitWithShaders(&t.material, &t.vertex, &t.fragment)
	return true
}

toon_draw :: proc(t: ^Toon, device: ^foster.GraphicsDevice, target: foster.DrawableTarget,
	camera: ^world.Camera3D, mesh: ^foster.Mesh, model: world.Matrix4, color, light_dir: [4]f32, albedo: ^foster.Texture) {
	// 顶点槽 0：WVP + World
	matrices: [r3d.VERTEX_MATRIX_BLOCK_SIZE]u8
	r3d.pack_vertex_matrix_block(matrices[:], world.matrix4_multiply(model, world.camera3d_view_projection(camera)), model)
	foster.MaterialStageSetUniformBuffer(&t.material.Vertex, matrices[:], 0)
	// 片元槽 0：按 HLSL 里的 vec4 偏移逐个写
	block: [32]u8
	mat.std140_write_vec4(block[:], 0, color)
	mat.std140_write_vec4(block[:], 16, light_dir)
	foster.MaterialStageSetUniformBuffer(&t.material.Fragment, block[:], 0)
	// 贴图：Samplers[n] 对应 tn/sn
	t.material.Fragment.Samplers[0] = {Texture = albedo, Sampler = foster.TextureSamplerMake(.Linear, .Clamp)}

	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, target, mesh, &t.material)
	command.DepthTestEnabled = true
	command.DepthWriteEnabled = true
	command.CullMode = .Back
	foster.GraphicsDeviceDraw(device, &command)
	foster.DrawCommandDispose(&command)
}
```

`target` 需要深度附件：先画到带深度的离屏 Target，再合成到窗口。

```odin
attachments := [2]foster.TargetAttachmentSpec{{Format = .Color}, {Format = .Depth32}}
foster.TargetInit(&scene, device, w, h, attachments[:], "scene color + depth")
```

多个物体用 `Render_Queue` 排序后按序调用 `toon_draw`；半透明 draw 关掉深度写入并设置混合，
例如 `command.BlendMode = foster.BlendModeNonPremultiplied`。蒙皮网格用 `pack_joint_palette` 打包两块各 64 关节的骨骼矩阵
（SDL Vulkan 每槽 UBO 上限 4KB），槽位由着色器决定，参考 forward3d 的 Skinned 着色器。

## 约定与常见错误

- **矩阵一律 `mul(v, M)`。** `kit/world` 是行向量约定，`mat.std140_write_matrix` 按存储原样上传，HLSL 默认 column_major
  读到的就是同一个矩阵。写成 `mul(M, v)` 等于乘了转置矩阵。法线同理：`mul(n, (float3x3)World)`。
- **寄存器空间固定**：顶点 uniform `b*, space1`；片元贴图与采样器 `t*/s*, space2`；片元 uniform `b*, space3`。
- **数量要对上**：`ShaderCreateInfo` 的 `SamplerCount` / `UniformBufferCount` 与 HLSL 声明一致。没绑定贴图的采样器槽，foster 会填一张调试纹理。
- **每张贴图配独立的 SamplerState**，多张贴图共用一个时 shadercross 可能把它误判成 storage texture。
- **cbuffer 按 vec4（16 字节）对齐**：尽量全用 `float4` / `float4x4`，给块大小和关键偏移写测试（参考 forward3d 的 `forward3d_test.odin`）。
- **自己构造 `BlendMode` 时写上 `Mask = .RGBA`**：零值是 `.None`，颜色写入会被关掉。用 `foster.BlendModeNonPremultiplied` 等预设则不用管。
- **`mat.shader_pick` 没有 msl 时 Metal 拿到空字节码**，`foster.ShaderInit` 会越界崩溃；要支持 Mac 就三种都传。
- **Web 不适用**：Web 后端是 WebGL + 手写 GLSL ES（命名 uniform，不用 UBO），shadercross 不输出 GLSL。

## 范围

Shader Lab 的材质预览也走 Render3D（借用自己的 GPU 绑定，见 `mat.material_from_bindings`），与游戏同一套剔除、排序与状态规则。
库不提供蒙皮材质、自动阴影调度或逐模型后处理。示例描边沿顶点法线外扩，
宽度是 HLSL 常量，颜色属于材质参数；硬边/非均匀缩放的法线和描边策略由 Shader 作者处理。
发布游戏使用预编译 Shader，不 import Shader Lab 或 shader/dev。
