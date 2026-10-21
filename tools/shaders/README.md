# Shader 归属与编译

同一入口也支持 [单文件 `.oshader`](../../kit/rendering/shader/lang/README.md)，无需手动拆出 HLSL。
每个 Pass 生成 `<Shader>_<Pass>.<阶段>.<格式>`，并输出包含 Schema/Shader 的
`<Shader>.shader.json`。它描述材质定义，与保存实例参数值的 JSON 区分；
预览与发布共用解析器。Sprite 总是生成 BatcherVertex 批量变体；
声明 Instanced 时额外输出 `<Shader>_<Pass>.instanced.vertex.<格式>`，两者共用片元代码。
运行时由 `mat.material_register_directory` 按这些文件名找到产物（自己拼 `Pass_Binaries` 时分别填入 vertex 与 instanced_vertex）；
修改 2D 输入约定后须一起重新生成。
编译 `.oshader` 前，工具把 `kit/rendering/shader/lang/include/olib/` 复制到工作区的 `olib/`，供
`#include "olib/<Draw>.hlsli"` 使用（shadercross 只接受一个 `-I`，仍指向 shader 目录）；手写 `.hlsl` 不提供这些文件。
项目的 shader 目录里不要建 `olib/` 子目录。指定目录内的旧 `.hlsl` 可以并存，输出重名会在编译前报错。

Shader 与使用它的功能放在一起。框架内置绘制属于 `foster`，库功能属于对应 `kit` 包，
游戏材质和演示 Shader 属于游戏/示例仓库。跨模块共享的代码按依赖方向提取到共同拥有者；
库不得引用示例资产，不为目录统一而复制 shader。

## 统一目录

```text
<功能>/shaders/
├── Shader.hlsl                 # 原生后端源码
├── Common.hlsli                # 手工维护的共享 include（按需）
├── Shader.vertex.glsl          # 手工适配的 Web 源码（按需）
├── Shader.fragment.glsl
└── Compiled/                   # 自动生成，禁止手工编辑
    ├── Shader.vertex.spv
    ├── Shader.vertex.dxil
    ├── Shader.vertex.msl
    ├── Shader.fragment.spv
    ├── Shader.fragment.dxil
    └── Shader.fragment.msl
```

Foster 的拥有者目录为 `foster/assets/shaders/`，遵循相同的源码/产物分层。
虽然 MSL 是文本，它仍是本工具生成的产物；现有 GLSL 是按 Web uniform/attribute 接口
手工适配的源码，放在源码层，不放入 `Compiled/`。

| 所有者 | Shader |
| --- | --- |
| `foster/assets/shaders` | Batcher / Textured / Msdf |
| `kit/rendering/3d/shaders` | DebugLine3D |
| `kit/gizmo/shaders` | Gizmo3D |
| `olib_sample/src/<示例>/shaders` | 示例专用 Shader 与材质 |

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

手写 `.hlsl` 新增 shader 时同步更新相应模块的 `#load`；`.oshader` 材质由
`material_register_directory` 按目录登记，增删 Pass 或 Shader 不改 Odin 代码。之后运行 `odin run tools/check`，再执行涉及后端的
GPU 回归或最终画面检查。`tools/check` 会通过编译检查嵌入引用的文件是否存在，
但不运行 shadercross，也不代替 GPU 测试。

## 产物是否过期

全部编译成功后，工具写 `Compiled/sources.json`，记下每个源码文件的指纹：目录下（含子目录，跳过
`Compiled` 和隐藏目录）的 `.oshader` / `.hlsl` / `.hlsli`，目录里有 `.oshader` 时再加上 olib 标准 include。
指纹去掉 `\r` 再算，git 的换行转换不会造成误报。记录在编译前计算，编译途中改了文件只会被报成过期。

```sh
odin run ../olib/tools/shaders -- -check -dir:src/forward3d/shaders
```

`-check` 只比对记录与当前源码，不需要 shadercross：一致时退出码 0；改了、新增或删除了源码，或者没有记录时退出码 1，
并列出文件和重新生成的命令。`tools/check` 对 olib 的 foster/、kit/ 与同级 olib_sample/src 下每个有记录的
`Compiled` 运行它；没有记录的目录只提示跳过，重新生成一次后开始检查。游戏仓库可以在自己的检查脚本里调用 `-check`。

foster 默认 shader 和 olib_sample book_ui 的产物原先与当前工具链编译结果不一致（book_ui 还缺 `.msl`），2026-10-21
用当前工具链重建，比对反汇编并在 D3D12/Vulkan 截图逐像素一致后写入记录（foster 见 [LOCAL_CHANGES L-019](../../foster/docs/LOCAL_CHANGES.md)）。
stylized3d 有进行中的改动，暂未记录；其余目录重新编译与已提交产物逐字节一致后写入记录。
