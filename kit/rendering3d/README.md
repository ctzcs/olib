# olib:kit/rendering3d —— 3D 渲染机制层

这个包只提供与画风无关、每个 3D 游戏都要用的机制：

| 文件 | 提供 |
| --- | --- |
| `mesh3d.odin` | dasset primitive 上传为 `foster.Mesh`（静态 / 蒙皮顶点格式） |
| `queue3d.odin` | `Render_Queue($T)`：payload 由游戏定义，不透明从前到后、透明从后到前排序 |
| `shader3d.odin` | `shader3d_pick_code`：按图形驱动选 spv / dxil / msl 字节码 |
| `uniforms3d.odin` | `std140_write_matrix` / `std140_write_vec4`、WVP + World 顶点矩阵块、骨骼 palette 打包 |
| `material3d.odin` | 模型材质的参数绑定、Pass 状态与有序绘制；与 Shader Lab 共用 |
| `../rendering/material_library.odin` | 2D/3D 共用的材质加载与缓存；模型槽见 material3d |
| `debug_draw3d.odin` | 立即模式调试线（线、盒、球、视锥、网格、骨架） |
| `lod3d.odin` | 按屏幕高度选 LOD |
| `shaders/` | DebugLine3D 的 HLSL 与编译产物；编译工具是 olib 根目录的 `tools/shaders` |

光照/材质的具体外观、阴影和后处理由游戏自己写；本包只提供材质执行机制。参考实现是同级仓库
olib_sample 里的 `src/forward3d`（Standard PBR 前向渲染器：方向光、点光、聚光、半透明排序），
复制到游戏里按画风改写即可。

## 写一个着色器：从 HLSL 到画面

以一个带贴图的卡通着色器为例。完整可运行的版本见 olib_sample 的 `src/forward3d`。

### 1. 写 HLSL

一个 `.hlsl` 文件同时包含顶点和片元两个入口，函数名固定为 `vertex_main` 和 `fragment_main`。
共用代码放进 `.hlsl` 引用的 `.hlsli`（编译脚本会跳过 `.hlsli`）。

```hlsl
// 顶点 uniform：b*, space1        片元 uniform：b*, space3
// 片元贴图/采样器：t*/s*, space2  （SDL GPU 的固定约定）
cbuffer VertexBlock : register(b0, space1) { float4x4 WorldViewProjection; float4x4 World; };
cbuffer ToonBlock : register(b0, space3) { float4 BaseColor; float4 LightDir; };
Texture2D Albedo : register(t0, space2);
SamplerState AlbedoSampler : register(s0, space2);

// TEXCOORDn = VertexFormat 的第 n 个元素；这四项与 mesh3d_static_format 一致
struct VsInput { float3 Position : TEXCOORD0; float3 Normal : TEXCOORD1; float2 Uv : TEXCOORD2; float4 Tangent : TEXCOORD3; };
struct VsOutput { float4 Position : SV_Position; float3 Normal : TEXCOORD0; float2 Uv : TEXCOORD1; };

VsOutput vertex_main(VsInput i)
{
    VsOutput o;
    o.Position = mul(float4(i.Position, 1), WorldViewProjection); // mul(v, M)，见下文“约定”
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

需要 [SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross)（PATH 上的 `shadercross`）。在游戏根目录：

```bash
odin run ../olib/tools/shaders -- -dir:src/shaders
```

产物写到 `src/shaders/Compiled/`：`Toon.vertex.{spv,dxil,msl}`、`Toon.fragment.{spv,dxil,msl}`。
**产物提交进仓库**：平时构建只 `#load` 它们，不需要 shadercross；只有改了 HLSL 才重新编译。

### 3. Odin 侧：装载

```odin
import r3d "olib:kit/rendering3d"
import world "olib:kit/world"
import foster "olib:foster"

toon_vs_spv :: #load("shaders/Compiled/Toon.vertex.spv")
toon_vs_dxil :: #load("shaders/Compiled/Toon.vertex.dxil")
toon_vs_msl :: #load("shaders/Compiled/Toon.vertex.msl")
toon_fs_spv :: #load("shaders/Compiled/Toon.fragment.spv")
toon_fs_dxil :: #load("shaders/Compiled/Toon.fragment.dxil")
toon_fs_msl :: #load("shaders/Compiled/Toon.fragment.msl")

Toon :: struct {
	vertex, fragment: foster.Shader,
	material:         foster.Material,
}

toon_init :: proc(t: ^Toon, device: ^foster.GraphicsDevice) -> bool {
	if !r3d.shader3d_driver_supported(device.Driver) { return false }
	d := device.Driver
	// SamplerCount / UniformBufferCount 必须与 HLSL 声明的数量一致
	foster.ShaderInit(&t.vertex, device, {
		Stage              = .Vertex,
		Code               = r3d.shader3d_pick_code(d, toon_vs_spv, toon_vs_dxil, toon_vs_msl),
		UniformBufferCount = 1,
		EntryPoint         = "vertex_main",
	}, "toon vertex")
	foster.ShaderInit(&t.fragment, device, {
		Stage              = .Fragment,
		Code               = r3d.shader3d_pick_code(d, toon_fs_spv, toon_fs_dxil, toon_fs_msl),
		SamplerCount       = 1,
		UniformBufferCount = 1,
		EntryPoint         = "fragment_main",
	}, "toon fragment")
	if t.vertex.Resource == nil || t.fragment.Resource == nil { return false }
	foster.MaterialInitWithShaders(&t.material, &t.vertex, &t.fragment)
	return true
}

toon_dispose :: proc(t: ^Toon) {
	foster.MaterialDispose(&t.material)
	foster.ShaderDispose(&t.vertex)
	foster.ShaderDispose(&t.fragment)
}
```

### 4. Odin 侧：每次绘制

```odin
My_Draw :: struct {
	mesh:  ^foster.Mesh, // r3d.mesh3d_upload 上传
	model: world.Matrix4,
	color: [4]f32,
}

toon_draw :: proc(
	t: ^Toon, device: ^foster.GraphicsDevice, target: foster.DrawableTarget,
	camera: ^world.Camera3D, draw: My_Draw, light_dir: [4]f32, albedo: ^foster.Texture,
) {
	// 顶点槽 0：WVP + World（kit 现成的打包）
	matrices: [r3d.VERTEX_MATRIX_BLOCK_SIZE]u8
	wvp := world.matrix4_multiply(draw.model, world.camera3d_view_projection(camera))
	r3d.pack_vertex_matrix_block(matrices[:], wvp, draw.model)
	foster.MaterialStageSetUniformBuffer(&t.material.Vertex, matrices[:], 0)

	// 片元槽 0：自己的块，按 HLSL 里的 vec4 偏移逐个写
	block: [32]u8
	r3d.std140_write_vec4(block[:], 0, draw.color)
	r3d.std140_write_vec4(block[:], 16, light_dir)
	foster.MaterialStageSetUniformBuffer(&t.material.Fragment, block[:], 0)

	// 贴图：Samplers[n] 对应 tn/sn
	t.material.Fragment.Samplers[0] = {Texture = albedo, Sampler = foster.TextureSamplerMake(.Linear, .Clamp)}

	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, target, draw.mesh, &t.material)
	command.DepthTestEnabled = true
	command.DepthWriteEnabled = true
	command.CullMode = .Back
	foster.GraphicsDeviceDraw(device, &command)
	foster.DrawCommandDispose(&command)
}
```

`target` 需要深度附件才能做深度测试：先画到带深度的离屏 Target，再合成到窗口。

```odin
attachments := [2]foster.TargetAttachmentSpec{{Format = .Color}, {Format = .Depth32}}
foster.TargetInit(&scene, device, w, h, attachments[:], "scene color + depth")
```

### 5. 多个物体：用渲染队列排序

payload 是游戏自己的结构体，队列只关心视深度和是否透明：

```odin
queue: r3d.Render_Queue(My_Draw)

r3d.queue_clear(&queue)
for draw in draws {
	r3d.queue_submit(&queue, draw, r3d.queue_view_depth(&camera, draw.model), draw.color.a < 1)
}
r3d.queue_sort(&queue) // 不透明前到后，透明后到前
for item in queue.items {
	toon_draw(&toon, device, target, &camera, item.payload, light_dir, &albedo)
}
```

半透明 draw 关掉深度写入并设置混合，例如 `command.BlendMode = foster.BlendModeNonPremultiplied`。

## 约定与常见错误

- **矩阵一律 `mul(v, M)`。** `kit/world` 是行向量约定（`v' = v * M`），`std140_write_matrix`
  按存储原样上传，HLSL 默认 column_major 读到的就是同一个矩阵。写成 `mul(M, v)` 等于乘了
  转置矩阵，几何会整体错乱。法线同理：`mul(n, (float3x3)World)`。
- **寄存器空间固定**：顶点 uniform `b*, space1`；片元贴图与采样器 `t*/s*, space2`；片元 uniform `b*, space3`。
- **数量要对上**：`ShaderCreateInfo` 的 `SamplerCount` / `UniformBufferCount` 与 HLSL 声明一致。
  没绑定贴图的采样器槽，foster 会填一张调试纹理。
- **每张贴图配独立的 SamplerState**，不要多张贴图共用一个，否则 shadercross 可能把它误判成 storage texture。
- **cbuffer 按 vec4（16 字节）对齐。** 尽量全用 `float4` / `float4x4` 排布，给块大小和关键偏移写测试
  （参考 olib_sample `forward3d_test.odin`）。
- **自己构造 `BlendMode` 时写上 `Mask = .RGBA`**：零值是 `.None`，颜色写入会被关掉、什么都画不出。
  用 `foster.BlendModeNonPremultiplied` 等预设则不用管。
- **`shader3d_pick_code` 不传 msl 时，Metal 驱动拿到空字节码**，`foster.ShaderInit` 取 `Code[0]` 时会越界崩溃；要支持 Mac 就三种都传。
- **Web 不适用**：Web 后端是 WebGL + 手写 GLSL ES（命名 uniform，不用 UBO），shadercross 不输出 GLSL。

## 模型材质加载与使用

材质加载与缓存位于公共包 [kit/rendering](../rendering/README.md)，2D/3D 共用。
一般游戏从 `rendering.Material_Library` 接入。它把材质文件里的 Effect 名解析为已登记的效果，
自动加载参数/贴图、创建 Shader 和绑定；业务不需要组装 `rendering.Material_Binding`。

```odin
// 场景/资源初始化：resources 为已有的 Foster StorageContainer。
materials := rendering.Material_Library{device = device, storage = &resources}
// 每种效果登记一次；schemas 和预编译代码按组对应。
reason := rendering.materials_register(&materials, effect, schemas, shader_code)
// 检查 reason，再继续。
model := r3d.Model{mesh = &mesh}
model.material, reason = rendering.material_load(&materials, "materials/hero.json")

// 每帧；view 包含场景目标、相机 VP、时间。
ok := r3d.model_draw(model, transform, view)
// 场景退出：先停止绘制所有借用该库的模型，再释放。
rendering.materials_dispose(&materials)
```

一次登记放在资源初始化代码，参考 `olib_sample/src/material3d/shaders.odin`。
库复制 Effect/Schema，借用当前后端的 Shader 字节码（通常 #load）；按需创建 GPU 资源。
`material_load` 每次创建**独立参数实例**，同一效果的 Shader/底层 Material、同路径的贴图共享。
默认贴图为白色。所有 IO 直接通过同一个 `StorageContainer`，兼容其目录、ZIP/虚拟文件后端；
根目录由项目按 `kit/storage` 的策略选择，或显式指定资产根，不绕开存储层读取系统文件。

材质文件路径相对于存储根，贴图路径相对于材质文件；两者使用相对逻辑路径。
Shader Lab 导出跨盘绝对贴图路径时，应先把贴图纳入游戏资产根并改为相对路径。
`. / .. / 反斜杠` 会规范化，使相同逻辑贴图复用缓存。

- `material_set_number(material, group, field, value)` 按稳定 ID 修改实例参数，检查类型、范围和有限值；
  不影响其他实例。贴图/布局等资源改变通过重新加载材质文件处理。
- `material_reload(&materials, model.material)` 重新读原文件，也可指定新文件；先准备完整候选，失败保留
  原实例，成功保持对象地址，所有引用该实例的模型槽同时看到结果。
- reload 只刷新材质内容；同路径贴图复用缓存，不自动监听或刷新 Shader/贴图文件。
- 库拥有所有返回的材质和缓存，统一由 `materials_dispose` 释放，目前不逐项卸载或自动淘汰。
  建议按场景/资源会话划分库；释放后不可再用模型中的旧指针。不要浅复制拥有数据的库或材质。
- 库、设备和存储的地址、存储根及 Shader 字节码在使用期间保持稳定；所有 GPU 操作在主线程、
  合法设备生命周期内进行，加载/重载放在提交绘制之外。

`Model` 表示一个静态网格/primitive 的材质槽，不是新的场景或模型导入器；多 primitive 模型可持有多项。
场景仍负责网格、变换、相机、颜色/深度目标以及绘制排序。

## 模型材质执行

以下是渲染器/Shader Lab 需要的底层接口，普通业务使用上面的 `material_load` 和 `model_draw`。

`model_material_draw(device, effect, bindings, draw)` 把一个静态网格的所有 `.Model` Pass
依次画到同一个外部颜色/深度目标。先用 `material.effect_order` 或 `instance_make` 校验定义；
执行器借用资源，不加载文件、不清屏，也不决定场景排序。

```odin
// 每组一个绑定；samplers 按 Schema 中 Texture 字段顺序，空路径也要绑定默认纹理。
bindings := []rendering.Material_Binding{
    {instance.groups[0].schema, instance.groups[0].values, &surface_gpu, surface_samplers},
    {instance.groups[1].schema, instance.groups[1].values, &outline_gpu, outline_samplers},
}
ok := r3d.model_material_draw(device, effect, bindings, {
    mesh = &model_mesh, target = scene_target,
    world_matrix = model_transform, view_projection = camera_view_projection,
    time = elapsed,
})
```

每次提交重新绑定数值、纹理和 Pass 覆盖，因此不同实例可顺序复用同一批 `foster.Material`。
调用期间所有指针保持有效；Shader/Material 地址不能在初始化后因容器扩容而移动。
空 `enabled` 使用声明值，`pass_limit=0` 绘制全部。预览用 prepare/submit 回调扩展网格和绘制，
显式 Pass.state 在 prepare 后应用；Shader Lab 的候选管线探测也使用相同状态。

这一条路径的 Shader 接口为静态顶点格式、vertex b0 的 WVP+World（128B）、fragment b0 的
Clock/Pointer/Tint（48B）、fragment b1 的 material.pack 参数，以及 space2 的纹理。
Clock=(time, delta_time, frame, 0)，Pointer=(normalized x/y, target width/height)，Tint=白色。
须提供有效世界矩阵和 VP，不能把零矩阵当单位阵。

首版不提供蒙皮、阴影 Pass 调度、透明物排序、顶点材质参数或逐模型后处理。
示例描边沿顶点法线外扩，宽度是 HLSL 常量，颜色属于材质参数；硬边/非均匀缩放的法线和描边策略由 Shader 作者处理。
发布游戏使用预编译 Shader，不 import Shader Lab 或 shaderdev。Web Shader 仍需单独适配 GLSL。
