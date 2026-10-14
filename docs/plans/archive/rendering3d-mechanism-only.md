# Plan：kit/rendering3d 只保留机制，Standard 管线移到示例

> **状态：已完成（2026-10-14）** · 提交 `96e58b7`..`ed8b155`（olib_sample：`9092518`）
> 偏离：① 步骤顺序改为“队列泛型化 → check.ps1 → 删 kit 管线 → shadercross → 示例提交”：kit 队列原先绑着 kit 的材质类型，示例无法先复制；示例着色器又必须先修正、重编才能跑通。② 计划外修复了原管线从未跑过而暴露的问题：`queue_view_depth` 忽略 world 矩阵且符号相反；着色器 `mul(M, v)` 与 world 行向量约定相反（kit DebugLine3D 与示例 Standard 一并改为 `mul(v, M)`）；`BlendMode.Mask` 零值关闭颜色写入（调试线与半透明都画不出）；光照块 80→112B、阴影块 160→320B、采样器 6→9 与 HLSL 不一致；蒙皮两块 palette 共用同一 scratch 内存。③ 换 shadercross 后不做字节比对，以 D3D12 / Vulkan 截图一致为准；Metal 只确认 `.msl` 生成与 `#load` 编译通过，未实测。④ `shader3d_debug_line_dispose` 未新增（`debug_draw_dispose` 已直接释放）。

## 背景

`kit/rendering3d` 现在包含两类性质不同的东西：

| 类别 | 内容 | 性质 |
| --- | --- | --- |
| 机制 | `mesh3d`（dasset → Foster Mesh）、`lod3d`、`debug_draw3d` + `DebugLine3D` 着色器、按驱动选字节码（`shader3d_driver_supported` / `shader3d_pick_code`）、std140 打包、骨骼 palette 打包、透明/不透明排序 | 与画风无关，每个 3D 游戏都要 |
| 外观策略 | `Standard3D*.hlsl` 的 PBR 光照、`Light_Block` / `Material_Block` / 阴影块 / 点光块布局、`Standard_Material_3D`、`Renderer3D` 固定槽位的前向 pass、`DepthOnly*`（阴影预留）、`Tonemap` / `Post*` / `Sky3D`（未编译、未接入） | 每个游戏不同；ROADMAP 里的 IBL / CSM / 后处理都属于这一类 |

两类东西缠在一起的地方：

- `queue3d.odin` 的 `Render_Item` 内嵌 `Standard_Material_3D`，通用的排序被绑在了 PBR 材质上。
- `renderer3d_render` 是封闭的：着色器、槽位都写死，没有阴影也要每帧打包一个“关闭”的阴影块。想换光照模型的游戏只能 fork。

使用情况（2026-10-14 核对）：

- olib 内只有 `kit/rendering3d` 自己和它的测试用到 Standard 管线。
- olib_sample 没有示例跑过 Standard 管线；未跟踪的进行中示例 `src/book_ui/renderer3d.odin` 只用了 `VERTEX_MATRIX_BLOCK_SIZE`、`pack_vertex_matrix_block`、`shader3d_driver_supported`、`shader3d_pick_code`。
- Proj_Sand 没有 import `kit/rendering3d`。

着色器工具链与上游不一致：

- 上游 Foster（`Foster/Framework/Content/Shaders/compile.sh`）和 DragonLib 都用 SDL_shadercross：HLSL → SPIR-V，再由 SPIR-V 转出 MSL 和 DXIL。`foster/assets/shaders` 里四种格式齐全（spv / dxil / msl，外加 Web 用的手写 glsl）。
- `kit/rendering3d/shaders/build_shaders.ps1` 却直接调用 Vulkan SDK 的 dxc，只产出 spv / dxil，所以 3D 在 Metal 上跑不了（`shader3d_driver_supported(.Metal)` 返回 false）。本机已装 `D:\Tools\ShaderCross\bin\shadercross.exe`。
- `shader3d.odin` 注释说“ShaderCreateInfo 无格式字段，SDL 按字节码魔数识别”，这不对：`foster.ShaderInit` 按驱动选格式（Vulkan→SPIRV、D3D12→DXIL、Metal→MSL）。
- Web 后端是 WebGL + 手写 GLSL ES、命名 uniform、不用 UBO；shadercross 不能输出 GLSL，3D 上 Web 要另写一套着色器，不在本计划范围。

## 已定决策（执行时不要改）

1. **`kit/rendering3d` 定位为 3D 机制层**：不含光照模型、材质模型、固定渲染管线。外观由游戏自己写；olib_sample 提供一份可复制改造的参考前向渲染器。
2. **留在 kit 的内容**：
   - `mesh3d.odin`、`lod3d.odin`：不改。
   - `debug_draw3d.odin` 和 `DebugLine3D` 着色器：调试工具，不受画风影响，保留。
   - `shader3d.odin`：只保留 `shader3d_driver_supported`、`shader3d_pick_code`、`DebugLine3D` 的字节码与 `shader3d_debug_line_init`。`shader3d_pick_code` 加一个默认参数 `msl: []u8 = nil`，Metal 驱动时返回它（book_ui 的三参数调用不受影响）；`shader3d_driver_supported` 加上 `.Metal`。修正上面那条错误注释。
   - `uniforms3d.odin`：保留 `Vertex_Matrix_Block` / `VERTEX_MATRIX_BLOCK_SIZE` / `pack_vertex_matrix_block`（WVP + World 是通用的顶点槽 0 约定，book_ui 也在用）和 `pack_joint_palette`（4KB UBO 上限下的拆块是机制，槽位由调用方定）。`write_matrix` / `write_vec4` 改为公开的 `std140_write_matrix` / `std140_write_vec4`，供游戏打包自己的 cbuffer。
   - `queue3d.odin`：改成泛型，不再知道材质（见决策 3）。
3. **队列泛型化**，写法与 `lod3d.odin` 的 `Model_Lod($T)` 一致：

   ```odin
   Render_Item :: struct($T: typeid) {
   	payload:     T,
   	view_depth:  f32,
   	transparent: bool,
   }
   Render_Queue :: struct($T: typeid) {
   	items: [dynamic]Render_Item(T),
   }
   queue_submit :: proc(q: ^Render_Queue($T), payload: T, view_depth: f32, transparent: bool)
   queue_sort / queue_clear / queue_dispose / queue_view_depth  // 语义不变
   ```

   排序规则不变：不透明前到后、透明后到前、插入排序稳定。不加材质批次键之类的新排序维度。
4. **移到 olib_sample 新示例 `src/forward3d/` 的内容**：`renderer3d.odin`、`material3d.odin`、`Light_Block` / `Material_Block` / 阴影块 / `Point_Light` / `Spot_Light` 及其打包、`shader3d_standard_init`、`Standard3D.hlsl` / `Standard3DSkinned.hlsl` / `Standard3DCommon.hlsli` / `EnvironmentUv.hlsli` 及其 dxil/spv 产物，以及对应的单元测试。示例的文件头注释写明“这是参考实现，复制到游戏里按需修改”。
5. **直接删除**（不移到示例）：`DepthOnly*.hlsl` 及产物、`shader3d_depth_init`、`Tonemap` / `PostBloom` / `PostComposite` / `PostDepth` / `PostFxaa` / `Sky3D` / `PostFullscreen.hlsli`。目前没有阴影 pass 和后处理在用；需要时从 git 历史或 DragonLib 取。
6. **着色器编译改用 shadercross，并参数化**：`kit/rendering3d/shaders/build_shaders.ps1` 改为与上游 Foster `compile.sh` 相同的流程，即 `shadercross` 把 HLSL 编成 `.spv`，再由 `.spv` 转出 `.msl` 和 `.dxil`。增加 `-Dir <目录>`，编译该目录下所有 `*.hlsl`（跳过 `*.hlsli`），产物写到 `<目录>/Compiled`；不传时默认用脚本所在目录。shadercross 先找 PATH，找不到再用 `D:\Tools\ShaderCross\bin\shadercross.exe`，都没有就报错退出。示例和游戏都调用这一个脚本。不再依赖 dxc。Web 用的 GLSL 不在本计划范围。
7. **示例 `forward3d`**：没有模型资源，用代码生成立方体和球体的 `Dasset_Primitive`，经 `mesh3d_upload` 上传；场景包含方向光、一盏点光、一个半透明物体，再用 `debug_draw3d` 画网格。支持 `shot` 参数：渲染一帧、写 PNG 后退出，与 `game_ui` / `ui_gallery` 的做法一致。
8. **示例的单元测试要跑起来**：`check.ps1` 的示例段对含 `*_test.odin` 的示例目录额外执行 `odin test`。
9. **不保留过渡别名**：被移走的名字直接从 kit 消失。

## 执行步骤

前置：`foster-single-naming` 计划完成并合并到 master 后，从 master 新建分支 `rendering3d-mechanism-only`。开始前运行 `powershell -File check.ps1`，确认全部通过。olib_sample 的改动在它自己的仓库单独提交。

### 1. 示例 forward3d：复制一份 Standard 管线

在 olib_sample 新建 `src/forward3d/`，按决策 4 **复制**（kit 里暂不删）Standard 管线代码、着色器源与产物、测试，改为示例包内的名字；仍 import `olib:kit/rendering3d` 使用机制部分。按决策 7 搭场景，`run.bat` 和 README 加入口。同时在 olib 按决策 8 修改 `check.ps1`。

运行 `run.bat forward3d` 目视确认（D3D12 和 Vulkan 各跑一次），再 `run.bat forward3d shot` 生成截图。

提交：olib_sample `forward3d: 参考前向渲染器（自 kit/rendering3d 复制 Standard 管线）`；olib `chore: check.ps1 运行示例目录里的单元测试`

### 2. kit 队列泛型化、公开 std140 写入函数

按决策 3 改 `queue3d.odin`，按决策 2 把 `write_matrix` / `write_vec4` 改名为公开的 `std140_write_*`。kit 内 `renderer3d` 暂时跟着改成 `Render_Queue(Standard_Material_3D)`，保证这一步能编译；forward3d 同步改用泛型队列。更新 `rendering3d_test.odin` 中的队列测试。

提交：olib `rendering3d: 渲染队列泛型化，公开 std140 写入函数`；olib_sample `forward3d: 跟随泛型渲染队列`

### 3. 从 kit 删除 Standard 管线

按决策 4、5 删除 kit 里的外观策略代码、着色器与产物；把对应测试从 `rendering3d_test.odin` 中删掉（第 1 步已复制到示例）。更新 `rendering3d.odin` 的包注释和分区说明。

完成后复查：`grep -rn "Light_Block\|Standard_Material_3D\|Renderer3D\|DepthOnly\|Tonemap" kit/` 没有结果。

提交：`rendering3d: 只保留机制，Standard 管线移到 olib_sample forward3d`

### 4. 着色器改用 shadercross，补上 Metal

按决策 6 改写 `build_shaders.ps1`，按决策 2 改 `shader3d_pick_code` / `shader3d_driver_supported`。用新脚本重新编译 kit 的 `DebugLine3D` 和 forward3d 的 Standard 着色器（产物多出 `.msl`），forward3d 的着色器装载同步支持 msl。编译器换了，dxil/spv 字节不会和旧版一致，以运行结果为准：`run.bat forward3d` 在 D3D12、Vulkan 下画面与第 1 步截图一致。本机是 Windows，Metal 无法实测，只确认 `.msl` 产物生成、`#load` 编译通过，并在汇报中写明。更新 `rendering3d_test.odin` 中字节码分发的测试，覆盖 Metal 分支。

提交：olib `rendering3d: 着色器改用 shadercross 编译，补 MSL`；olib_sample `forward3d: 着色器改用 shadercross 产物，支持 Metal`

### 5. 文档

- `docs/ROADMAP.md`：“已完成”表的 3D 渲染栈一行改为机制层的描述；“3D 渲染增量”一节删掉 msl 补编、阴影、后处理、IBL，只留“Web 目标的 3D 着色器（手写 GLSL ES、命名 uniform，shadercross 不覆盖）”；“工具链”一节的 ShaderCompiler 标为已由 shadercross 脚本覆盖；“明确不做”加一行：库内 PBR / IBL / 阴影 / CSM / 后处理 / 天空，理由是外观由游戏决定，参考实现见 olib_sample `forward3d`，DragonLib HLSL 源在 git 历史。
- `README.md` 目录树里 `rendering3d/` 的说明、`prompts/new-project.md` 对 `kit/rendering3d` 的描述：改成“3D 机制：Mesh 上传 / 渲染排序 / 着色器字节码选择 / std140 打包 / DebugDraw3D / LOD；光照与材质由游戏实现，参考 olib_sample forward3d”。
- `docs/CODE_STYLE.md` 里的“3D 队列”保持不变。

提交：`docs: rendering3d 定位为机制层`

### 6. 按 docs/plans/README.md 归档本计划

## 验收

- olib 根目录 `powershell -File check.ps1` 全部通过，其中包含 `sample forward3d` 的编译和测试。
- Proj_Sand 根目录 `powershell -File check.ps1` 全部通过。
- `run.bat forward3d` 在 D3D12、Vulkan 下画面正常：光照、点光衰减、半透明叠加、调试网格都在；`shot` 截图附在汇报里。
- `kit/rendering3d` 不再包含光照、材质、阴影、后处理相关的类型、着色器和产物（第 3 步的 grep 为空）。

## 禁止事项

- 不新增任何渲染功能（阴影、IBL、后处理、批次合并等），本计划只做搬迁和解耦。
- 不改 `mesh3d` 的顶点格式，不改 `core/dasset`，不改 `foster/`。
- 不动 olib_sample 里未跟踪的 `src/book_ui/`。它依赖的四个名字按决策 2 都保留，如果仍然编译失败，停下来汇报，不要改它。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 两个仓库各自的 commit 列表。
- check.ps1 结果（olib 与 Proj_Sand），有失败就贴输出。
- forward3d 截图，以及 D3D12 / Vulkan 是否都跑过。
- 第 4 步换 shadercross 后 D3D12 / Vulkan 的画面对比，以及 Metal 未实测的说明。
- 与计划不一致的地方及原因。
