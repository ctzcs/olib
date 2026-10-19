# 3D 渲染参考：手写 HLSL 与底层接口

业务绘制见 [README](README.md)。本文给自己写渲染器（不经过材质系统）和集成 Shader Lab 的人看。
完整可运行的手写渲染器是 olib_sample 的 `src/forward3d`（Standard PBR 前向渲染：方向光、点光、聚光、半透明排序），
复制到游戏里按画风改写即可。

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
		Code = mat.shader_pick(d, {#load("shaders/Compiled/Toon.vertex.spv"),
			#load("shaders/Compiled/Toon.vertex.dxil"), #load("shaders/Compiled/Toon.vertex.msl")})}, "toon vertex")
	foster.ShaderInit(&t.fragment, device, {Stage = .Fragment, SamplerCount = 1, UniformBufferCount = 1, EntryPoint = "fragment_main",
		Code = mat.shader_pick(d, {#load("shaders/Compiled/Toon.fragment.spv"),
			#load("shaders/Compiled/Toon.fragment.dxil"), #load("shaders/Compiled/Toon.fragment.msl")})}, "toon fragment")
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

## model_material_draw：Shader Lab 的底层入口

`model_draw` 是它的薄包装。Shader Lab 用自己管理的 GPU 资源（`mat.Material_Binding`）预览效果，直接调用：

```odin
// 每组一个绑定；samplers 按 Schema 中 Texture 字段顺序，空路径也要绑定默认纹理。
bindings := []mat.Material_Binding{
	{instance.groups[0].schema, instance.groups[0].values, &surface_gpu, surface_samplers},
	{instance.groups[1].schema, instance.groups[1].values, &outline_gpu, outline_samplers},
}
err := r3d.model_material_draw(device, effect, bindings, {
	mesh = &preview_mesh, world_matrix = transform,
	view = {target = scene_target, view_projection = camera_view_projection, time = elapsed},
	pointer = pointer, pass_limit = preview_pass + 1, // 预览专用：Pointer.xy 与只画前 N 个 Pass
})
```

- 把一个静态网格的所有 `.Model` Pass 依次画到同一个外部颜色/深度目标；`options.pass_id` 非空时只画该 Pass。
  先用 `mat.effect_order` 或 `mat.instance_make` 校验定义；执行器借用资源，不加载文件、不清屏、不决定场景排序。
- 每次提交重新绑定数值、纹理和 Pass 覆盖，不同实例可顺序复用同一批 `foster.Material`。调用期间所有指针保持有效，
  Shader/Material 地址不能在初始化后因容器扩容而移动。
- `options`（`mat.Draw_Options`）里空 `enabled` 使用声明值；预览用 prepare/submit 回调扩展网格和绘制，显式 `Pass.state`
  在 prepare 后应用，Shader Lab 的候选管线探测也使用相同状态。
- 须提供有效世界矩阵和 VP，不能把零矩阵当单位阵。instanced 效果传 `instances` / `instance_count`，此时 `world_matrix` 被忽略。

首版不提供蒙皮材质、阴影 Pass 调度、透明物排序、顶点材质参数或逐模型后处理。示例描边沿顶点法线外扩，
宽度是 HLSL 常量，颜色属于材质参数；硬边/非均匀缩放的法线和描边策略由 Shader 作者处理。
发布游戏使用预编译 Shader，不 import Shader Lab 或 shader/dev。
