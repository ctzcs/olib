# Shader 开发与热重载（2D / 3D）

`shaderdev` 是仅用于开发构建的桌面扩展。它不持有 App、相机或场景，
也不规定 2D/3D 材质模型。外部编辑器保存 HLSL 后，后台编译候选版本；
渲染线程用实际 DrawCommand 检查管线，成功后原位替换两个 Shader。
材质引用、uniform、纹理、相机和预览时间保持不变。失败保留上一版 GPU 资源。

## 直接使用 Shader Lab

工具主体位于 [kit/tools/shader_lab](../tools/shader_lab/README.md)，提供可嵌入宿主区域的
Session API；示例只负责窗口启动、输入映射、路径和 MSDF 字体资产。工具不依赖示例代码。

在同级 `olib_sample` 目录运行：

```bat
run.bat shader_lab
run.bat shader_lab vulkan
run.bat shader_lab d3d12
```

需要 `odin` 和 `shadercross` 在 PATH 中。无需另开监听进程，也无需重启预览窗口。
工具第一次启动也会编译源码；编译器缺失时显示错误，安装完成后点击 Recompile。

- **2D Fullscreen / Sprite**：全屏片元效果、带透明度的贴图精灵。
- **3D Sphere / Cube**：球体和立方体，透视相机、深度和 4× MSAA。
- **参数面板**：从 Odin 字段标签生成滑条、向量、可视化调色板与纹理选择；每组参数独立。
- **多 Pass**：同包 `X_Passes / X_Output` 声明生成 `Parameter_Build.effects`；
  Shader Lab 只列出显式 `X_Passes / X_Output` 效果，单 Pass 也需声明；参数组不自动生成效果。
  单 Pass 与多 Pass 共用选择器、参数面板及执行路径，同一 Shader 可供多个 Pass 复用。
  效果可用 `X_Preview :: mat.Preview_Mode.Two_D / Three_D` 指定工作区，3D 效果内的全屏后处理仍归该效果。
  省略时按是否包含 3D 模型 Pass 推断，兼容已有声明。两个工作区独立记忆选择和预览设置。
  声明类型与依赖排序在 `kit/material`，RenderTexture/历史帧执行在 Shader Lab。
  详见 [多 Pass 声明与限制](../tools/shader_lab/README.md#odin-多-pass-与历史帧)。
- **紧凑主题**：MSDF 字体、内置图标与蓝色选中态；选择区固定，Pass 列表和参数区分别滚动。
  效果菜单使用浮层，切换不推挤左栏；纹理卡片显示实际图片缩略图，点击选择。
  Odin 的 `mat.Texture_Path` 字段保存图片路径，缩略图使用宿主加载并绑定的纹理。
- **Pause / Resume**：暂停/继续时间；右键从预览区域开始拖动可环绕 3D 模型，滚轮缩放。
- 修改 `src/shader_lab/shaders/Preview2D.hlsl` 或 `Preview3D.hlsl`；
  修改共享 `Palette.hlsli` 会触发两者重载。
- `source <目录> params <目录>` 分别指定 HLSL 根目录和单个 Odin 参数包。
  默认缓存位于示例项目 `library/shader_dev/`；`cache <目录>` 可指定另一生成目录。
  自定义位置时把 HLSL 的 include 相对路径指向对应组的头文件。
- 在 `src/shader_lab/shader_params/` 添加/修改 `.odin` 文件会自动生成描述和参数布局。
  Shader Lab 最多显示 16 组；生成器本身不限制组数。

保存前的编辑由文本编辑器管理。面板参数不写回 HLSL/Odin，支持显式保存/加载预览预设，
没有宿主材质文档的撤销/重做或内置源码编辑器。Texture 支持图片选择、拖入和文件热更新；
效果中还可连接 RenderTexture，加载失败保留旧纹理。

## 一个 Odin 包，多组参数，一个生成程序

```text
src/shader_lab/
├── shader_params/              # 同一个 package shader_params
│   ├── preview2d.odin
│   └── preview3d.odin
├── shaders/
│   ├── Preview2D.hlsl
│   ├── Preview3D.hlsl
│   ├── Palette.hlsli
│   └── textures/
└── main.odin                   # import olib:kit/tools/shader_lab
```

自定义一组参数，例如 `water.odin`：

```odin
package shader_params

import mat "olib:kit/material"

Water_Shader :: mat.Shader_Path("water.hlsl") // 相对于 source 目录
Water_Preview :: mat.Preview_Mode.Two_D      // 可选，Shader 省略时默认 Two_D
Water_Label :: "水面"       // 可选显示名；不改变 Water 这个稳定 ID。
Water_Folder :: "材质"      // 可选 Shader folder 标题前缀；仅影响面板展示。

Water_Params :: struct {
    speed: mat.Scalar `label:"流动速度" min:"0" max:"5" step:"0.1"`,
    tint: mat.Color `label:"染色"`,
    noise: mat.Texture_Path `label:"噪声贴图"`,
}

water_defaults :: proc() -> Water_Params {
    return {speed = 1, tint = {1, 1, 1, 1}, noise = "textures/noise.png"}
}
```

发现约定为顶层 `X_Params`、必需的 `X_Shader`、可选 `X_Preview`，以及把前缀转小写
后的 `x_defaults()`。省略默认值函数则取 Odin 零值；默认值必须在标签范围内。
文件名仅用于组织，一份文件可以放多组声明；组名在 UI 中取 `X`。
同一 Shader 路径只接受一份参数定义。标签 `id:"稳定标识"` 可在字段改名后保留旧值。
`Scalar / Color / Vector2 / Vector3 / Texture_Path` 自动选择控件，不必写 ui 标签；
`label / id / min / max / step` 仍可选。旧基础类型 + ui 标签、字符串 Shader 路径常量、
`"2d" / "3d"` 预览声明仍兼容。`Preview_Mode.Auto` 只用于 Effect 工作区推断，
Shader 的顶点接口须指定 Two_D/Three_D 或省略取默认值。
Pass 引用使用 `Params_Ref / Target_Ref / Field_Ref / Pass_Id`，详见 [声明类型](../material/README.md#数据与所有权)。
`ui:"vector"` 对应 [2]f32 / [3]f32，`ui:"color"` 对应 [4]f32，数值默认范围 0..1。
颜色字段显示可点击色块，打开 HSV 调色板、透明度条与常用色；实时预览，
Apply 保留，Cancel / Escape / 窗口离焦恢复原色。`step` 控制普通数值滑条的键盘步长。

HLSL 入口文件中加入（下面的相对路径对应示例的 `src/shader_lab/shaders/`）：

```hlsl
#include "../../../library/shader_dev/Water/params.generated.hlsli"
// 在 fragment_main 中直接使用 _speed、_tint。
// _noise.Sample(_noiseSampler, uv) 读取贴图。
```

用现有 Preview2D/Preview3D 的顶点接口和公共输入作为模板。片元 b0 是引擎输入，
b1 和 space2 中的纹理由生成器管理，详见 [参数布局](../material/README.md)。
不要在 HLSL 里再次手写这些材质参数，也不要将生成字段用于顶点阶段。

整个参数包只编译一个临时 `shader_params` 程序，运行后输出机器读取的描述。
JSON 只是内部交换数据，不需要用户编写。每次任务结束清理临时生成程序；
头文件保留在项目 `library/shader_dev/<组名>/params.generated.hlsli`，供查看和 IDE 解析。
文件随有效 Odin 声明更新，内容未变时不写盘，写入失败保留旧文件。library 已被示例仓库
忽略，不提交 Git。即使 HLSL 有错误，这里也会展示最近一次有效 Odin 声明的布局；
它不表示该候选已成功用于 GPU 预览。它使用真实 Odin 编译器，默认值可以由函数
计算；不把 Odin 当成解释执行的配置文件，也不热加载 DLL。

声明改变后：后台生成完整描述 → 比较各组 → 只为变化的组生成布局并编译 Shader →
准备对应值和纹理 → 验证 GPU 管线 → 一起替换该组的 Shader/参数面板/值。
失败保留该组上一份可用画面与参数。新增字段取默认值，已有 ID 和类型相同的值保留，
字段重排不改变值。直接改滑条或选择纹理不编译。HLSL 内容改动沿用目录级监听。

参数包采用扁平目录；仅发现顶层声明，不扫描 `when`/foreign 块中的类型，
不支持依赖另一个项目相对路径包或 build-tag 选择的多套声明。
可以导入 core/olib 包，但外部导入包变化不会触发监听，需点 Recompile。
默认值函数运行在生成程序中，应只计算默认值，不执行游戏初始化或依赖当前工作目录。
标签错误、Odin 编译错误会显示在面板；默认纹理路径错误在准备候选资源时显示。

字体由宿主提供离线 MSDF 图集；缺字需更新宿主图集，工具不烘焙 Bitmap 或运行时 SDF。

## 参数生成 API

`Parameter_Watch` 与 `Session` 都必须保持地址稳定：

- `parameters_init / parameters_update / parameters_take / parameters_dispose` 管理一个参数包。
- `parameters_take` 返回拥有的 `Parameter_Build`，使用 `parameter_build_dispose` 释放。
- `parameters_compile` 是同步生成入口，适合构建工具和测试。
- `parameters_write_headers(schemas, root)` 将各组头文件保留到指定缓存目录，返回拥有的
  错误字符串（成功为空）。IDE 副本不作为运行时参数来源，不应手工编辑。
- 对变化的组，保留候选 Schema；用 `material.hlsl` 生成 include，调用
  `configure_parameters(session, header, texture_count, source, header_include)`。
  `header_include` 为入口 HLSL 中指向 library 头文件的相对路径（正斜杠、双引号 include）。
  该函数复制字符串；编译副本把此路径映射到独立候选头文件，避免并发保存影响编译。
  省略 `header_include` 时仍支持临时 `#include "params.generated.hlsli"`。
- `apply` 成功后提交候选描述、迁移后的值和纹理；失败保留旧参数。
  `configure_parameters` 不自行更新宿主的参数数组或纹理。

## 游戏开发入口接入

`Session` 必须保持地址稳定。它拥有两个 Shader 和对应字节码，材质借用其地址。
`init` 的资源数量应与宿主提供的 uniform 和纹理一致：

```odin
import dev "olib:kit/shaderdev"
import foster "olib:foster"

// state.live 与 state.material 是宿主持有的稳定字段。
ok := dev.init(&state.live, "content/shaders/MyEffect.hlsl", device.Driver,
    {uniform_buffers = 1},
    {uniform_buffers = 1, samplers = 1})
foster.MaterialInitWithShaders(&state.material, &state.live.vertex, &state.live.fragment)

// UpdateProc：检测保存，后台编译，不在渲染线程运行编译器。
dev.update(&state.live, f64(app.Time.Delta))

// RenderProc：在提交任何相关绘制、或向 Batcher 排队之前。
// probes 是宿主用实际 mesh/target/blend/depth/MSAA 构造的 DrawCommand 切片。
// 覆盖该 Shader 的全部绘制配置；通常在窗口离屏目标创建/更新后构造。
_ = dev.apply(&state.live, device, probes)
if state.live.revision > 0 {
    // 照常设置 state.material 的 uniform/纹理并绘制。
}

// ShutdownProc：先释放借用者，再释放 Session，最后释放 GraphicsDevice。
foster.MaterialDispose(&state.material)
dev.dispose(&state.live)
```

`init` 返回 false 时仍应调用 `dispose`。`diagnostic` 借用到下一次状态变化/销毁；
`retry` 重新尝试当前文件。内部跨线程数据使用系统 heap allocator，
不借用调用方的帧临时分配器。退出时等待正在运行的编译器结束。

## 重载契约与边界

- 每 250ms 检查源码内容散列，稳定至少 250ms 后开始编译；耗时不承诺固定帧数。
  一个会话同时只有一项编译任务。编译期间的新保存会使过期结果被丢弃。
- 递归监测源文件所在目录的 `.hlsl` / `.hlsli`；为两个阶段创建同一份临时源码快照。
  普通 include 必须位于该目录树内，使用相对路径；不支持普通外部 include 和符号链接依赖。
  参数生成头文件是例外：入口中的 library 相对路径会在编译副本中映射到独立候选文件。
- vertex/fragment 入口固定为 `vertex_main` / `fragment_main`。
  只生成当前驱动需要的 SPIR-V、DXIL 或 MSL；不覆盖 `Compiled/` 发布产物。
- 通过 SPIR-V 反射校验 sampler、uniform buffer、storage buffer 数量。
  **这不是完整的 ABI 反射**：不自动检测 cbuffer 内部字段偏移/大小、语义或槽位重排。
  手写的引擎接口必须保持与宿主一致；修改时同步修改宿主并重启。
  生成的材质参数由同一描述派生 HLSL 和字节布局，允许通过 Odin 声明热改。
  生成模式允许编译器消除未使用的 sampler/uniform，不接受超出声明上限的资源。
  graphics storage texture 当前不支持。
- GPU 检查仅覆盖传入的 probes。调用方应涵盖实际用到的顶点格式、目标格式、
  混合、深度和多采样组合。Foster 新增 `ShaderTryInit` 和 `ShaderPairTryReplace`；
  原有 `ShaderInit` / `ShaderRecreate` 保留其 API 和失败行为。
- 本机已验收 Windows D3D12 / Vulkan。Metal 编译路径已实现但未在 macOS 实机验收；
  WebGL/JS、compute shader 不在本工具范围内。
- 发布入口通过编译期依赖排除本包和工具 UI，继续用 `tools/shaders` 预编译并 `#load`。

## 验收

```bat
odin test kit/shaderdev -collection:olib=. -vet
odin run tools/check
```

在 `olib_sample`：

```bat
run.bat shader_lab smoke d3d12 scaled
run.bat shader_lab smoke vulkan
run.bat shader_lab shot narrow vulkan
```

smoke 使用独立临时源码，验证两个阶段的管线失败回退、语法错误保留旧画面、
include 修复后的像素变化、绑定数量变更拒绝、状态保留、真实 UI 点击/滑条与 resize。
也验证 Odin 标签错误、字段新增/重排、参数迁移、中文标签、纹理替换/失败保留，
以及运行中发现、编译、预览和移除第三个 Shader。
日志中故意触发的 Shader 和 GPU 错误属于验收用例，最终以退出码和 PASS 为准。
失败的临时源码保留供诊断；成功后清理。

shot 保存四种预览的最终合成 PNG；UI 在最终像素绘制，场景按预览实际像素渲染。
截图在下一次 update 读取已提交的上一帧，不读取尚未提交的渲染命令。
已检查 960×720、1280×800、1600×1000 与运行中 1100×825 resize；
示例菜单使用英文，Windows 对参数标签按需添加中文字符覆盖；未提供自定义 UI 缩放设置。
