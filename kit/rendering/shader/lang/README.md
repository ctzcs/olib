# 单文件 Shader

`.oshader` 将参数、默认值、渲染状态、Pass、目标连线和 HLSL 放在同一文件。
语法借鉴 Unity ShaderLab，但不是 Unity Shader 的兼容层。普通 HLSL 的入口仍为
`vertex_main` / `fragment_main`，顶点接口和引擎输入仍遵循宿主约定。

完整可运行示例在同级仓库 `olib_sample/src/shader_lab/shaders/Unified.oshader`：
第一遍生成半分辨率环纹，第二遍读取它并染色。运行 `run.bat shader_lab d3d12`，
在 2D 工作区选择 **Single-file / rings + tint**。

```hlsl
Shader "Water"
{
    Label "水面"
    Preview 2D

    Properties
    {
        [Id("speed")] [Step(0.1)] _Speed ("速度", Range(0, 5)) = 1
        _Tint ("颜色", Color) = (0.2, 0.5, 0.8, 1)
        _Source ("输入", 2D) = ""
    }

    HLSLINCLUDE
    // 可在这里放所有 Pass 共用的结构体、顶点入口、函数和 include。
    ENDHLSL

    Pass "main"
    {
        Draw Fullscreen
        Blend Opaque
        HLSLPROGRAM
        // 此例省略宿主要求的 vertex_main；完整版本见 Unified.oshader。
        float4 fragment_main() : SV_Target0 { return _Tint; }
        ENDHLSL
    }
}
```

## 声明

- `Shader` 名和 `Pass` 名是稳定标识，只接受 ASCII 字母、数字和下划线，首字符不能为数字。
  显示名称使用可选的 `Label "..."`，不改变预设或运行时身份。
- `Properties` 是全文件共用的声明模板。**各 Pass 继承相同字段，但保有独立的实例值**，
  对应既有的 Effect → Pass → 参数面板；当前不提供 Unity 式的跨 Pass 共享可变参数值。
  每个程序的参数组名为 `<Shader>_<Pass>`；重命名其中任一项会改变参数组身份。
- 属性名必须为 `_Name`；生成器自动声明 HLSL 数值、纹理与 `_NameSampler`。
  不再手写这些资源声明，也无需 include 参数头文件。`_olib_` 前缀保留给生成器。
- `Range(min,max)`、`Float`、`Vector2`、`Vector3`、`Color`、`2D` 对应现有控件。
  除 Float 默认范围 -10000..10000 外，数值控件默认范围 0..1；向量和颜色可写
  `Vector2(-5,5)`、`Color(0,4)` 指定范围。默认值必须落在范围内。
- `[Step(0.01)]` 设置步长；`[Id("稳定标识")]` 让字段改名后保留值。未指定 Id 时取去掉第一个下划线后的属性名，大小写敏感。
- `[Instance]` 标记每对象数值字段（最多 16 个）；2D 走顶点 storage buffer，不占参数 uniform，
  不同取值仍可合批。tint 总在顶点颜色里，不需要额外标记。
- 顶层 `Instanced` 声明生成常驻缓冲变体；当前解析器遇到 `[Instance]` 也会自动启用它。
  底层 Effect 允许 2D 只用实例字段而不启用 instanced；3D 仍要求实例缓冲。

### 2D 效果的 HLSL 约定

所有 `Draw Sprite` 都用同一份输入接口，批量与常驻缓冲的差异由生成器处理：

```hlsl
cbuffer ViewBlock : register(b0, space1) { float4x4 Projection; };
struct Input { OlibSpriteInput Sprite; };
struct Output { float4 Position : SV_Position; float2 Uv : TEXCOORD0; OlibInstance Instance; };
Output vertex_main(Input v)
{
    OlibSprite s = olib_sprite(v.Sprite);
    Output o;
    o.Position = mul(Projection, float4(s.position, 0, 1));
    o.Uv = s.uv;
    o.Instance = s.instance;
    return o;
}
float4 fragment_main(Output v) : SV_Target0
{
    olib_instance = v.Instance;
    return _image.Sample(_imageSampler, v.Uv) * InstanceTint;
}
```

`InstanceTint` 是绘制调用的顶点色；片元 b0 中的 Tint 固定白色。
批量变体使用 BatcherVertex；有实例字段时，mode 字节存 storage buffer 下标，
生成器声明顶点 t0/space0 和 b1/space1 的 Pass 偏移，运行时一次上传各 Pass 的独立数值。
缓冲变体使用单位四边形与实例顶点，由 `r2d.buffer` 绘制，不使用 storage buffer。
顶点 b0 为投影；片元 b0 为 Clock/Pointer/Tint，b1 为统一参数；这些帧块仍由宿主提供。
不要手写或复用旧的精灵顶点布局。Odin 的字段标签 `instance:"true"` 对应 `[Instance]`。

### instanced 效果的 HLSL 约定

**模型 instanced** 的 HLSL（`Draw Model`）：

```hlsl
// 顶点 b0 为 { ViewProjection, 单位矩阵 }；世界矩阵来自实例，用 olib_world 取得。
cbuffer ViewBlock : register(b0, space1) { float4x4 ViewProjection; float4x4 Unused; };
struct Input {
    OlibInstanceInput Instance;   // 必须是第一个成员，网格属性随后依次声明
    float3 Position : TEXCOORD0;
    float3 Normal : TEXCOORD1;
};
struct Output { float4 Position : SV_Position; float3 Normal : TEXCOORD0; OlibInstance Instance; };
// vertex_main:   o.Position = mul(mul(float4(v.Position, 1), olib_world(v.Instance)), ViewProjection);
//                o.Instance = olib_instance_from(v.Instance);
// fragment_main: olib_instance = v.Instance;
```

两条来自 shadercross 的限制（D3D12 会按"实际用到的"属性重新编号语义，Vulkan 不会，二者不一致就会创建管线失败或画错）：
1. `OlibInstanceInput` 必须是 `Input` 的第一个成员，这样实例属性的位置总是 0.. 且全部被使用；
   网格属性自动后移，网格里末尾未使用的属性（如 Tangent）无妨，中间未使用的属性会错位。
2. 传给片元的变量（`Output` 里除 `SV_Position` 外的成员）必须全部在片元里被使用，否则顶点输出与片元输入对不上。

- `2D` 默认值是相对 Shader Lab `source_root` 的贴图路径，空字符串使用内置棋盘格。
- 数值只支持 fragment 参数；保持现有 fragment b1/space3、每字段 16 字节及
  texture/sampler space2 布局。引擎 b0 由宿主提供，不自动生成 `Time` 等全局变量。
- 每个 Pass 必须有一个非空的 `HLSLPROGRAM`。可选的 `HLSLINCLUDE` 插入所有 Pass。
  `ENDHLSL` 独占一行；注释或字符串中的同名文字不会截断代码。
  普通 `#include` 仍遵循 shader/dev 的源码目录范围约定。

## Pass 与目标

| 指令 | 值 / 行为 |
| --- | --- |
| `Draw` | `Fullscreen`（默认）、`Preview_Model`、`Model`、`Sprite` |
| `Preview` | `2D` / `3D`；Shader 层指定工作区，Pass 层指定顶点接口；Model 默认 3D |
| `Cull` | `Default` / `None` / `Front` / `Back` |
| `Blend` | `Default` / `Opaque` / `Alpha` / `Additive` / `Premultiplied` |
| `ZTest` | `Default` / `Off` / `Less` / `Less_Equal` / `Equal` / `Always` |
| `ZWrite` | `Default` / `On` / `Off` |
| `Disabled` | `On` 默认禁用此 Pass；省略或 `Off` 启用 |
| `Output "name"` | Pass 的输出目标，默认 `color`；Shader 层省略时取最后一个 Pass 的输出 |
| `Input _Source "scene" Current` | 纹理输入引用本帧目标；`Previous` 读取上一帧 |
| `Value "speed" 2` | 按字段稳定 Id 覆盖数值；向量写 `(1,0)`，不改实例值 |
| `SpriteTexture _Image` | Sprite 当前帧贴图对应的纹理字段 |

连线的 `_Name` 使用默认字段 Id `Name`；字段声明显式 Id 时，使用字符串引用稳定 Id，
如 `Input "source" "scene" Current`。重复输入、未知字段、无效覆盖和本帧循环依赖都报错。

`Target { Size 640 360 Scale 0.5 Format Float16 Samples 1 Depth Off Clear (0,0,0,0) }`
对应既有 Target_Desc。Size 与 Scale 通常择一使用；Format 支持 Color/Float16/Float32，
Samples 为 0/1/4。模型和精灵各 Pass 必须共享同一个目标描述；图像效果保持每目标单个生产者。
这些约束由 `material.effect_order` 统一验证。

## 接入与发布

Shader Lab 自动递归发现 `Config.source_root` 下的 `.oshader`，重名拒绝。
参数声明统一由 Properties 提供，不再读取 Odin 参数包。
源码和 include 的变化触发整包候选验证；错误保留上一版 Shader、参数与预览。
成功后按参数组名与字段 Id/类型迁移值。删除最后一个单文件效果后工作区变空。

`lang.parse(text, source_path)` 返回独立拥有的 `Document`，使用 `dispose` 释放。
解析器不读文件、不执行 HLSL；返回 Schema、Effect、按 Schema 排列的完整 HLSL。
`#line` 将编译错误指回原文件；语法错误也包含原文件行列。

发布使用现有工具，无需额外生成步骤：

```sh
odin run ../olib/tools/shaders -- -dir:src/shader_lab/shaders
```

工具编译指定目录顶层的 `.hlsl` 和 `.oshader`，子目录需分别运行。
每个 Pass 输出 `Compiled/<Shader>_<Pass>.<vertex|fragment>.<spv|dxil|msl>`，
Sprite 批量变体总是生成；声明 Instanced 时还输出 `<Shader>_<Pass>.instanced.vertex.<spv|dxil|msl>`，
片元代码共用。同时输出 `Compiled/<Shader>.shader.json`，包含 `version:1`、`schemas`、`effect`。
描述中的 `schema.shader` 是不带后缀的程序资源键，不含开发机路径。
游戏可将其解码为现有 `material.Schema` / `Effect_Desc`，配合预编译代码登记到
Material_Library；它与保存参数值的材质实例 JSON 是两种不同数据，不可互换。
所有 Pass 编译成功才开始写发布文件；多文件写入不是目录级原子事务。

不包含 Unity 的 SubShader 回退、Tags、Surface Shader、变体系统、CustomEditor、
UsePass 或自动 Web GLSL。
Zed / ZedG 的 `.oshader` 高亮见 [本地扩展](../../../../tools/zed-shader/README.md)，
支持外层声明和嵌入 HLSL；语义补全与跨块跳转尚未提供。
共享代码可用 HLSLINCLUDE / HLSLI；每个效果在自己的文件中声明 Pass，分别编译。

检查：`odin run tools/check -- -only:kit/rendering/shader`，全仓检查为 `odin run tools/check`。
