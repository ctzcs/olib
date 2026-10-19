# Shader 归属与编译

同一入口也支持 [单文件 `.oshader`](../../kit/rendering/shader/lang/README.md)，无需手动拆出 HLSL。
每个 Pass 生成 `<Shader>_<Pass>.<阶段>.<格式>`，并输出包含 Schema/Effect 的
`<Shader>.shader.json`。它描述材质定义，与保存实例参数值的 JSON 区分；
预览与发布共用解析器。指定目录内的旧 `.hlsl` 可以并存，输出重名会在编译前报错。

Shader 与使用它的功能放在一起。框架内置绘制属于 `foster`，库功能属于对应 `kit` 包，
游戏材质和演示效果属于游戏/示例仓库。跨模块共享的代码按依赖方向提取到共同拥有者；
库不得引用示例资产，不为目录统一而复制 shader。

## 统一目录

```text
<功能>/shaders/
├── Effect.hlsl                 # 原生后端源码
├── Common.hlsli                # 手工维护的共享 include（按需）
├── Effect.vertex.glsl          # 手工适配的 Web 源码（按需）
├── Effect.fragment.glsl
└── Compiled/                   # 自动生成，禁止手工编辑
    ├── Effect.vertex.spv
    ├── Effect.vertex.dxil
    ├── Effect.vertex.msl
    ├── Effect.fragment.spv
    ├── Effect.fragment.dxil
    └── Effect.fragment.msl
```

Foster 的拥有者目录为 `foster/assets/shaders/`，遵循相同的源码/产物分层。
虽然 MSL 是文本，它仍是本工具生成的产物；现有 GLSL 是按 Web uniform/attribute 接口
手工适配的源码，放在源码层，不放入 `Compiled/`。

| 所有者 | Shader |
| --- | --- |
| `foster/assets/shaders` | Batcher / Textured / Msdf |
| `kit/rendering/3d/shaders` | DebugLine3D |
| `kit/gizmo/shaders` | Gizmo3D |
| `olib_sample/src/<示例>/shaders` | 示例专用效果与材质 |

测试夹具留在对应测试目录。热重载编译器的源码快照、临时 HLSL 与字节码
使用独占的系统临时目录，编译结束后清理，遵循
[shader/dev](../../kit/rendering/shader/dev/README.md)。不覆盖 `Compiled/` 中用于发布的资产，
也不为每次构建在项目根另建输出目录；截图及诊断副本遵循
[生成文件规则](../../prompts/new-project.md#生成文件与目录纪律)。

## 编译入口

原生 vertex/fragment shader 统一使用 `tools/shaders`，需要 `odin` 与 `shadercross` 在 PATH。
入口名为 `vertex_main` / `fragment_main`，每个目录内的 `.hlsl` 都编译，`.hlsli` 仅作 include。
流程为 HLSL → SPIR-V → DXIL/MSL，不自动生成 Web GLSL。

在 olib 根目录运行：

```sh
odin run tools/shaders -- -dir:foster/assets/shaders
odin run tools/shaders -- -dir:kit/rendering/3d/shaders
odin run tools/shaders -- -dir:kit/gizmo/shaders
```

在游戏/示例仓库运行同一个工具：

```sh
odin run ../olib/tools/shaders -- -dir:src/forward3d/shaders
```

省略 `-dir` 时仍只编译 `kit/rendering/3d/shaders`；路径相对于当前工作目录，工具路径可用绝对路径。
独立的 compute/故障注入测试保留专用测试构建脚本，不交给固定双阶段入口。

源码、共享 include 和发布产物一起纳入版本管理，使使用库的人无需安装 shader 编译器。
修改源码后重新生成对应产物；同步维护有对应功能的 Web 源码。若升级编译器，应单独检查
产物差异与实际渲染，不把目录迁移和 shader 行为变更混在一起。

新增 shader 时同步更新相应模块的 `#load`，运行 `odin run tools/check`，再执行涉及后端的
GPU 回归或最终画面检查。`tools/check` 会通过编译检查嵌入引用的文件是否存在，
但不运行 shadercross，不判断产物是否过期，也不代替 GPU 测试。
