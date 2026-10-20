# Plan：引擎 b0 块改用 olib 标准 include

> **状态：已完成（2026-10-20）** · 提交 `8a1250b`..`2e492ee`（olib_sample：`9f447da`）
> 偏离：① 第 5 步按决策 8 跳过：stylized3d 仍有 63 处未提交改动，等这些改动提交后再迁移。② 计划文件先单独提交（`8a1250b`），归档的 `git mv` 需要它已被跟踪。③ Shader Lab 验证模式有两处间歇失败：基线的 `targets` 两次中失败一次（“switch back recreates history while retaining parameters and folding”），迁移后 4 次全部通过；迁移后的 `smoke` 8 次中有 1 次退出 1，当次没有保留诊断，其余 7 次通过。基线没有跑 `smoke`，无法确认它改动前是否也会偶发失败。

## 背景

`.oshader` 的原则：外层（Properties、Pass、渲染状态、Draw、Preview、目标）是编辑器功能，`HLSLPROGRAM` 里尽量是原版 HLSL。
生成器只补布局由编辑器决定的部分（参数块、贴图、`[Instance]` 字段、精灵两种变体的输入）。

宿主每次绘制填的引擎块（顶点 b0 / space1、片元 b0 / space3）目前由作者在每个 Pass 里手抄：

- olib_sample 16 个 `.oshader` 里共 34 处，名字有 ViewBlock（14）、PreviewBlock（13）、MatrixBlock（5）、FrameBlock（2）四种。
- 宿主的块还在变：顶点 b0 已从“矩阵 + Clock”变成“矩阵 + Clock + CameraPosition”，片元 b0 也加了 CameraPosition。
  手抄的声明不会跟着改，少声明只是读不到新成员，声明错了就无声画错。
- stylized3d 已在项目里用 `Stylized.hlsli` 集中声明 Model 的引擎块，本计划把这个做法提到 olib。

各宿主实际填写的内容（2026-10-20 核对）：

| Draw | 宿主 | 顶点 b0 | 片元 b0 |
| --- | --- | --- | --- |
| Model | Render3D、`model_material_draw`、Shader Lab 3D 预览 | `MATERIAL_VERTEX_BLOCK_SIZE`（160）：WVP（instanced 为 VP）、World（instanced 为单位矩阵）、Clock、CameraPosition | `MATERIAL_FRAME_BLOCK_SIZE`（64）：Clock、Pointer、Tint、CameraPosition |
| Sprite | Render2D 的 submit 与工具路径 | `[20]f32`（80）：Projection、Clock | `[12]f32`（48）：Clock、Pointer、Tint |
| Fullscreen、2D 的 Preview_Model | Shader Lab `pass_uniforms` | 16：View（x 横向缩放，y 纵向缩放） | 64：Clock、Pointer、Tint，CameraPosition 只在 3D 预览写入 |

3D 的 Preview_Model 用的就是 Model 的布局。

已核对的工具事实：

- shadercross 只接受一个 `-I`，第二个会报 “'-I' can only be used once”。
- DXC 处理 `#include "..."` 时先找当前文件所在目录，再找 `-I`。
  实测：源文件旁边放 `olib/engine.hlsli`、`-I` 指向另一个目录时，两边的 include 都能找到。
- tools/shaders 把每个参数组的程序写进私有临时工作区 `<组名>.hlsl` 再编译，`-I` 是 shader 源目录；工作区清理只删一层文件。
- Shader Lab（`kit/rendering/shader/dev`）把源根目录递归快照到私有临时目录再编译，`-I` 是该临时目录；`remove_workspace` 递归删除。
- tools/shaders 与 dev 都 import `kit/rendering/shader/lang`。
- `tools/check` 单元测试的隔离编译会改写 `#directory` 和字面量 `#load` 的相对路径。

## 已定决策（执行时不要改）

1. **三个标准 include，按 Draw 类型**，放在 `kit/rendering/shader/lang/include/olib/`，作者写 `#include "olib/<名>.hlsli"`：

   | 文件 | 用于 | 顶点 b0（`OlibVertex`） | 片元 b0（`OlibFrame`） |
   | --- | --- | --- | --- |
   | `model.hlsli` | Draw Model；3D 的 Preview_Model | `float4x4 Wvp; float4x4 World; float4 VertexClock; float4 VertexCameraPosition;` | `float4 Clock; float4 Pointer; float4 Tint; float4 CameraPosition;` |
   | `sprite.hlsli` | Draw Sprite | `float4x4 Projection; float4 VertexClock;` | `float4 Clock; float4 Pointer; float4 Tint;` |
   | `fullscreen.hlsli` | Draw Fullscreen；2D 的 Preview_Model（只在 Shader Lab） | `float4 View;` | `float4 Clock; float4 Pointer; float4 Tint;` |

   内容就是普通 HLSL：带 include guard 的 `cbuffer` 声明，每个成员注释写明含义和由哪个宿主填写，`Clock.w` 注明各宿主不同、不要依赖。
   名字沿用现有 shader 里的多数写法；顶点侧与片元同名的成员加 `Vertex` 前缀（同一份源码里两个阶段的 cbuffer 不能重名）。
   instanced Model 也用 `model.hlsli`：World 为单位矩阵，所以 `Wvp` 即 ViewProjection，世界矩阵仍用 `olib_world` 取。
2. **生成器不注入任何东西**，手写引擎块仍然合法；宿主布局不变，不升 `MANIFEST_VERSION`。
   唯一的宿主改动：Render2D 把 `[20]f32` / `[12]f32` 换成命名常量 `SPRITE_VERTEX_BLOCK_SIZE :: 80`、
   `SPRITE_FRAME_BLOCK_SIZE :: 48`（与 3D 的 `MATERIAL_*_BLOCK_SIZE` 对应），数值不变。
3. **不用第二个 `-I`**（shadercross 不支持）：tools/shaders 和 dev 编译前把 `olib/` 下的 include 复制到各自临时目录的
   `olib/` 子目录。生成的程序就在临时目录里，DXC 按“当前文件所在目录”找到它们；`-I` 仍指向项目的 shader 源目录。
   `olib/` 因此是保留的 include 目录名：项目自己的 shader 目录里不要再建 `olib/`（会被覆盖）。
4. **路径常量放在 lang**：`INCLUDE_DIRECTORY :: #directory + "/include"`，tools/shaders 与 dev 都从这里复制。
   tools/shaders 的工作区清理改为能删除 `olib/` 子目录。
5. **布局一致性测试**：`tests/kit/rendering/3d` 用 `#load` 读 `model.hlsli`，计算两个 cbuffer 的字节数（`float4x4` 64、`float4` 16），
   必须分别等于 `MATERIAL_VERTEX_BLOCK_SIZE`、`MATERIAL_FRAME_BLOCK_SIZE`；`tests/kit/rendering/2d` 对 `sprite.hlsli`
   与 `SPRITE_*_BLOCK_SIZE` 做同样检查。宿主改块时测试失败，提醒同步改 include。`fullscreen.hlsli` 只在 Shader Lab 里用，
   由 Shader Lab 的验证模式覆盖。
6. **Shader Lab 热重载**只给项目源根目录算指纹；改 olib 的 include 要重启 Shader Lab，写进文档。
7. **只服务 `.oshader`**：手写 `.hlsl` 的渲染器（foster、kit/gizmo、kit/rendering/3d 调试线、forward3d、book_ui）不迁移。
8. **stylized3d 只在它的进行中改动提交之后再迁移**：执行到该步时若 `src/stylized3d` 仍有未提交改动，就跳过并在汇报里说明。

## 执行步骤

前置：olib 与 olib_sample 都从 `master` 新建分支 `olib-hlsl-include`。两个仓库都有不属于本计划的未提交改动
（olib：`kit/tools/shader_lab/bank.odin`；olib_sample：stylized3d 下的修改与新文件、根 `README.md`），全程不提交它们，
每次提交只 `git add` 本计划的文件。开始前运行 `odin run tools/check` 记录基线，若基线就失败则停下来汇报。
基线截图：material2d（默认、`swarm`）、material3d（默认、`models`、`swarm`）的 `shot`；Shader Lab 的
`shot` 与 `multipass`、`hierarchy`、`targets` 写出的截图。每组跑两遍确认可重复，只把可重复的那些用于后面的逐像素对比；
基线复制到 olib_sample `library/tmp/olib-hlsl-include-baseline/`。

### 1. olib：标准 include、Render2D 尺寸常量与布局测试

按决策 1、2、5 新增三个 `.hlsli`、`lang.INCLUDE_DIRECTORY`（决策 4）、Render2D 的两个常量和两个布局测试。
运行 `odin run tools/check -- -only:kit/rendering/2d`、`-only:kit/rendering/3d`，再跑完整 `odin run tools/check`。

提交：olib `shader: 引擎 b0 块的标准 include（model / sprite / fullscreen）`

### 2. olib：编译时提供 olib/ include

按决策 3、4 修改 tools/shaders 与 `kit/rendering/shader/dev` 的编译流程，并让 tools/shaders 的清理能删子目录。
复制做成 dev 的私有过程并加单元测试（不需要 shadercross）：复制到临时目录后 `olib/` 下有三个文件，
`remove_workspace` 能把目录删干净。

手动验证：在 scratchpad 写一个 Sprite `.oshader`，只靠 `#include "olib/sprite.hlsli"` 声明引擎块，
用 tools/shaders 编译成功，产物齐全，工作区已被删除。

提交：olib `shader: tools/shaders 与 Shader Lab 编译时提供 olib/ 标准 include`

### 3. olib：文档

- `kit/rendering/shader/lang/README.md`：2D 与 instanced 模型的 HLSL 约定示例改用 `#include "olib/sprite.hlsli"`、
  `#include "olib/model.hlsli"`；列出三个 include 及适用的 Draw；说明手写仍合法、`olib/` 是保留目录名、改 include 要重启 Shader Lab。
- `tools/shaders/README.md`：说明编译前复制 `olib/` include，以及手写 `.hlsl` 不经过这一步。
- `kit/rendering/3d/README.md`、`REFERENCE.md`：顶点 b0 的说明指向 `model.hlsli`。

提交：olib `docs: 引擎 b0 块改用 olib 标准 include`

### 4. olib_sample：Shader Lab 示例着色器迁移

把 `src/shader_lab/shaders/` 8 个文件里手写的引擎块换成 include：

- `model.hlsli`：Outlined（两个 Pass）、Preview3D、Swarm、Trail3D 的 scene Pass。Swarm 的 `ViewProjection` 改为 `Wvp`。
- `sprite.hlsli`：SpriteShadow（两个 Pass）。
- `fullscreen.hlsli`：Preview2D、Trail2D（四个 Pass）、Trail3D 的 feedback / blur_x / blur_y、Unified（在 HLSLINCLUDE 里）。

重新生成 Compiled（`odin run tools/shader_lab_assets -collection:olib=../olib -out:build/shader_lab_assets.exe`）。
字节码会因 cbuffer 名字变化而不同，以画面为准：

- 前置里的 5 张材质 `shot` 与基线逐像素一致。
- Shader Lab 的 `shot`、`smoke`、`features`、`colors`、`multipass`、`hierarchy`、`targets` 都正常退出，
  可重复的截图与基线逐像素一致。
- 不带参数打开 Shader Lab 加载完整目录，所有参数组都没有 Error。
- 完整 `odin run tools/check` 通过。

提交：olib_sample `samples: Shader Lab 示例着色器改用 olib 标准 include`

### 5. olib_sample：stylized3d 迁移（有条件）

只在决策 8 的条件满足时执行：`Stylized.hlsli` 删除自己的 MatrixBlock / FrameBlock，改为 include `olib/model.hlsli`
（保留游戏自己的 SceneView 视图块）；SunShadow include `olib/model.hlsli`；AmbientOcclusion、DepthEdge include `olib/sprite.hlsli`；
`VertexCamera` 改为 `VertexCameraPosition`。重新生成 stylized3d 的 Compiled，改前改后各跑一次 `run.bat stylized3d shot`，画面一致。

提交：olib_sample `samples: stylized3d 改用 olib 标准 include`

### 6. 按 docs/plans/README.md 归档本计划

## 验收

- `odin run tools/check` 全部通过，包含两个布局测试和 dev 的新测试。
- 已迁移的示例着色器里不再有手写的引擎 b0 块：`grep -n "register(b0" src/shader_lab/shaders/*.oshader` 为空。
- 材质示例的 5 张 `shot` 与基线逐像素一致；Shader Lab 各验证模式通过，可重复截图一致。
- 新写的 `.oshader` 只需一行 `#include "olib/<Draw>.hlsli"` 就有全部引擎输入，不用自己写寄存器号。

## 禁止事项

- 生成器不注入引擎块；不改宿主写入的布局和大小（Render2D 只把数组长度换成常量）；不升 `MANIFEST_VERSION`。
- 不增加第二个 `-I`，不改 shadercross 的调用方式以外的编译参数。
- 不迁移手写 `.hlsl` 渲染器；不改 Proj_Sand；不提交、不修改不属于本计划的未提交改动（见前置）；不 push。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 两个仓库各自的 commit 列表。
- `tools/check` 结果，有失败就贴输出；新增测试的名字。
- 截图对比结果（哪些可重复、哪些一致），Shader Lab 各模式与完整目录的运行结果。
- stylized3d 是否迁移；跳过时说明原因。
- 与计划不一致的地方及原因。
