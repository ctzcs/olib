# Plan：Render3D 视图块、深度比较补全与深度贴图

> **状态：已完成（2026-10-20）** · olib 提交 `3044865`..`4cd9315`；olib_sample `6f61274`
> 偏离：① `VIEW_GLOBALS_SIZE`、槽位常量与补零函数放在 material 包（draw.odin），没放 3d/uniforms.odin：Render3D 与 Shader Lab 用的 `material_draw` 共用同一份规则。② 第 4 步拆成两个提交：foster 本地修改须以 `foster(local): L-018` 单独提交，`TextureIsSampleable` 按 LOCAL_CHANGES 规则放进 olib_ext.odin，并在 port_regression 加了真 GPU 回归；material 的拒绝逻辑另起一个提交。③ Shader Lab 的 `bank_sprite_group` 改为按 Pass 种类判断的 `bank_group_draws`。④ stylized3d 的 Shader 标签用英文：Shader Lab 的 MSDF 图集缺这些中文字形，不为示例重新生成共享图集。⑤ 示例 Shader 在视图块全零（Shader Lab 预览）时换成默认值。
> 验收：完整 `odin run tools/check` 89 项通过（新增 sample stylized3d）。port_regression 在 D3D12 / Vulkan 实测单采样深度附件当贴图采样通过、多采样深度判为不可采样。stylized3d 的 D3D12 与 Vulkan 截图一致（olib_sample/library/screenshots 的 stylized3d.png、stylized3d_flat.png），开关描边相差约 5200 像素；material3d、forward3d 两个后端的画面与改动前逐像素一致。Shader Lab 在两个后端加载六个程序均无绑定错误，改动源码后的热重载也无错误。Metal 只确认 `.msl` 生成，未实测。
> 性能：stylized3d 每帧 23 个模型 Draw（主视图 sky/scene/silhouette/body/transparent + 小地图 scene/body/transparent），1280×720、预热 10 帧后 119 帧平均 submit CPU 约 0.11 ms（D3D12 / Vulkan）；GPU 时间未测。
> 两个仓库都在 `render3d-view-depth-texture` 分支，未合并、未推送。olib_sample 工作区里他人未提交的 material2d/material3d 改动未动。蒙皮仍是待定项。

## 背景

以 [Celeste64](https://github.com/ExOK/Celeste64)（提交 `6edfe1e`，同样基于 Foster）作验收用例，检查“一个真实的 3D 小游戏”
用现有 Render3D 能否写出来。它的一帧：

1. 640×360 场景 Target（Color + Depth16），清屏；
2. 天空盒（不测深度、不写深度）；
3. Terrain；
4. Silhouette：角色被墙挡住的部分画成纯色剪影，`DepthCompare.Greater`、不写深度，与本体共用 Shader，靠一个 uniform 开关；
5. Default：角色本体；
6. 描边后处理：读场景**深度附件**，邻域深度差处混入描边色，结果写回场景；
7. 精灵、朝向相机的 billboard、贴地圆影（预乘混合、测深度不写）；Transparent（不写深度）；
8. 草莓特效：清深度后重画特效模型；
9. UI；最后整体放大到窗口。

太阳方向、竖直雾色、near/far 放在 `RenderState` 里，每次 Draw 前写进所有材质；billboard 用相机的 left/up 轴展开。

对照 olib 现状（基线见下文“前置”）：

| Celeste64 做法 | olib 对应 | 结论 |
| --- | --- | --- |
| ModelFlags 分桶、多次 RenderModels | 材质 Pass id + 多次 submit，记录保留 | 已有 |
| 剪影 uniform 开关 | Pass 的 `Value` 固定覆盖 | 已有 |
| 透明不写深度、草莓特效中途清深度 | Pass 状态；游戏在两次 submit 之间清深度 | 已有 |
| 天空盒先画 | 单独 Pass id 先 submit，`ZTest Off` | 已有 |
| 按 Actor 距离整体后到前 | 不透明分组前到后、透明后到前，逐 submit 剔除 | 已有且更好 |
| 每个 Model 自己 Draw，无实例化 | 自动实例化、常驻缓冲 | 已有且更好 |
| 相机位置 | b0 带 CameraPosition（`e885d1c`） | 已有 |
| 太阳方向、雾色写进所有材质；billboard 用相机轴 | 只能逐材质 `material_set_number`；记录快照材质值、多视图共用 | **缺：视图级数据** |
| 剪影 `DepthCompare.Greater` | `Pass_Depth` 只有 Less / Less_Equal / Equal / Always | **缺：Greater 等其余四种** |
| 描边读场景深度附件 | `material_set_texture` 可绑运行时贴图，但 foster 深度附件不带 SAMPLER 用途（`foster/graphics.odin` TargetInit） | **缺：深度附件不可采样** |
| 主角蒙皮（32 关节，同一 Shader 用 JointsMult 开关） | 材质路径对蒙皮网格返回 `.Unsupported_Mesh` | **缺，本计划只列待定问题** |

不借鉴的部分：

- UI 画进 640×360 再整体放大，违反 [UI 像素与采样约定](../../kit/ui/README.md#最终像素采样与清晰度验收)；只借鉴“3D 场景低分辨率渲染再放大”。
- 每个 Model 虚函数式立即绘制、Draw 前改共享材质 uniform、`Clone` 材质做每对象颜色。olib 已用快照与 `Instance_Values` 解决。
- 光照、雾、描边写死在 DefaultMaterial/RenderState。按 `rendering3d-mechanism-only` 的决定，外观归游戏或示例，库只给机制。

## 前置：基线提交

本计划以 olib `cd52e6d`..`e885d1c` 为基础：

- `cd52e6d` foster `L-017`：DrawCommand.InstanceOffset，Render3D 每次 submit 一次上传全部实例；
- `e885d1c` 材质相机/采样/运行时贴图：
  - `material_set_texture`（借用；nil 恢复白图；reload 恢复文件贴图）、贴图字段 `[Filter]/[Wrap]`、`Material.revision`；
  - 顶点 b0 在 Clock 后接 CameraPosition（`MATERIAL_VERTEX_BLOCK_SIZE = 128 + 32`），片元 b0 为 Clock/Pointer/Tint/CameraPosition（`MATERIAL_FRAME_BLOCK_SIZE = 64`）；
  - `MANIFEST_VERSION = 2`；指定 pass_id 的 submit 默认不画调试线；
  - 3d README 的“相机、灯光与运行时贴图”一节：灯光、雾作为材质参数用 `material_set_number` 设置，阴影图等用 `material_set_texture(..., foster.TargetAttachment(&shadow))` 绑定。

本计划的 foster 改动使用下一个 LOCAL_CHANGES 编号 **L-018**。
执行前确认 HEAD 包含这两个提交且 `odin run tools/check` 通过。若之后有人改了本计划要动的文件
（`render3d.odin`、`material_library.odin`、`draw.odin`、`shader/dev/dev.odin`、`shader_lab/bank.odin`、3d README）或占用了 L-018，
按当时的代码调整本计划里的数字，决策不变。

## 已定决策

### 1. 视图块 `View.globals`（优先级 1）

为什么材质参数不够：

- **真正逐视图的数据**（billboard 的相机轴、视矩阵/投影参数、某个视图关雾）不能放材质参数：同一份记录会提交给多个视图，记录时已快照材质值。
- **场景共用数据**（太阳方向、雾色）用材质参数要对每个材质、每个参数组调用 `material_set_number`，每个效果都得在 Properties 里声明同名字段，
  漏一个就静默不生效。视图块写一次，所有 Model Pass 都能读到。材质参数仍适合逐材质的值，两者并存。

决策：

- `View` 新增 `globals: []u8`：游戏按 std140 自行打包的视图级数据，只在 submit 调用期间借用。
  库不定义其中任何字段，不新增包装结构体；打包继续用 `mat.std140_write_*`，或直接取游戏结构体的字节。
- 库固定的每视图数据仍只放 b0（Clock、CameraPosition），本计划不再往 b0 加字段；视矩阵等由游戏按需写进 globals。
- 槽位：**Model Pass 的顶点 b1/space1 与片元 b2/space3**，两阶段是同一份字节。Sprite Pass 不变（顶点 b1 已被生成器占用），
  Render2D 的 View 本次不加 globals。Web 后端只支持 Foster 布局，材质的 Web 检查已拒绝 Olib 布局，无需另外处理。
- 大小固定 `VIEW_GLOBALS_SIZE :: 1024`（64 个 float4）：每次 Draw 先拷贝 globals，剩余部分补零，整块提交。
  `len(globals) > 1024` 时 submit 返回新增的 `.View_Globals_Too_Large`，不消耗记录。
  固定大小的理由：宿主不知道 Shader 声明的块有多大，各后端读取超出已提交长度的 UBO 行为未定义；Shader Lab 预览提交全零，同一 Shader 可直接预览。
  逐 Draw 提交是为了简单可靠；第 5 步记录 submit 的 CPU 时间，开销明显时再改为每次 submit 只在首个 Draw 提交
  （SDL_gpu.h 写明槽值在同一命令缓冲内保持到下次 Push）。
- 槽数：含 Model Pass 的效果把顶点 `UniformBufferCount` 1→2、片元（Olib 布局）2→3。不声明这些槽的旧 Shader 不受影响
  （和现在不声明片元 b0 的 Shader 同理），所以**不升 `MANIFEST_VERSION`**：生成代码不变，旧产物不需重编。
- Shader Lab 的预期绑定同步：`shader/dev` 会按预期槽数检查反射结果，超出就报 “Shader resource bindings changed”。
  `configure_parameters` 与 `shader_lab/bank.odin` 的 `dev.init` 对 Model 参数组改为顶点 2、片元 3（仿照现有 `bank_sprite_group` 判断 Model 组），
  Sprite 组不变。
- 预留：Model 顶点 b2/b3 留给将来的蒙皮 palette（两块各 4KB）。SDL GPU 每个着色器阶段只有 4 个 uniform 槽（SDL_gpu.h），顶点阶段至此用满。
- `mat.Material_Draw` 新增 `view_globals: []u8`；`model_material_draw` 从 `draw.view.globals` 透传，Shader Lab 传 nil（全零）。
- 多视图天然支持：每个视图提交自己的 globals，记录不变。forward3d 手写渲染器不受影响。

### 2. 深度比较补全（优先级 2）

- 现有 `Pass_Depth` 为 `Default, Off, Less, Less_Equal, Equal, Always`。补全 foster `DepthCompare` 的其余四种，
  在 `Always` **之后**追加 `Greater, Greater_Equal, Not_Equal, Never`，补全后与 foster 的 8 种一一对应。
  `Off` 仍表示关闭深度测试，与 `Always`（测试开启、总是通过）不同；`Default` 仍保留调用方状态。
- 编译清单用 `json.marshal` 默认选项（不写枚举名），枚举存成整数；追加不改变旧值，旧清单仍可读。
- 同步：`effect.odin` 里 `p.state.depth > .Always` 的范围校验改到新的末项；`draw.odin` 的 `pass_state_apply` 由 `#partial switch` 改为覆盖全部取值，
  映射到 foster 的 `.Greater` / `.NotEqual` / `.GreatorOrEqual` / `.Never`（foster 的拼写不改）；
  `.oshader` 的 `ZTest Greater` 等由 `enum_value` 按名字解析，不改解析器；更新 shader/lang README 的表格。Zed 高亮只列指令名，不需要改。
- Render3D 排序不改：不透明混合的 Greater Pass 照常进不透明桶。剪影与遮挡物的先后由游戏分阶段 submit：
  **场景 → 剪影 → 角色本体**。剪影必须在遮挡物写完深度之后、本体写深度之前画，否则会叠到角色自己被挡住的部位上。
  pass_id 只按名字筛选，所以场景材质与角色本体要用不同的 Pass id（如 `scene` / `silhouette` / `body`），或者把角色放进第二个 Render3D。写进 3d README。

### 3. 深度附件可采样（优先级 3）

- 绑定接口用 `e885d1c` 的 `material_set_texture`，不改它的语义。
- foster：TargetInit 给**单采样**深度附件加 `.SAMPLER` 用途，前提是 `GraphicsDeviceIsTextureFormatSupported` 对该格式成立
  （它已经按 SAMPLER + DEPTH_STENCIL_TARGET 检查）。多采样深度不加（SDL 没有深度解析），保持现状。
- 判定规则放进 foster 的一个新函数 `TextureIsSampleable(texture) -> bool`，由 TargetInit 与材质共用：
  依据现有的 `Format`、`SampleCount`、`ResolveResource` 与格式支持判断，不新增 Texture 字段。
  多采样颜色附件可采样：绑定时 `TextureSampleResource` 取其 L-005 解析纹理；多采样深度没有解析纹理，不可采样。
  这两处 foster 改动登记为 LOCAL_CHANGES 的 **L-018**，改动处写 `// [olib L-018]`。
- `material_set_texture` 对 `TextureIsSampleable` 为假的贴图返回 false，避免 SDL 校验错误或崩溃。
  3d README 里的阴影图示例要注明：`foster.TargetAttachment(&shadow)` 默认取颜色附件；取深度附件（index 1）要求单采样。
- 深度附件不能在仍作为当前深度目标时采样：后处理画到另一张 Target（同 Celeste64 的 postTarget），再合回。
  深度是非线性的硬件深度，线性化需要的 near/far 由游戏传入（后处理材质参数，或 3D 中的 globals）。写进 3d README 和材质 README。
- 不做：内建 SceneDepth 输入、自动深度预通道、Render2D 的视图块。

## 执行步骤

### 1. 前置与基线

- 按“前置”确认基线提交与 L-018 未被占用；在 olib、olib_sample 各建分支 `render3d-view-depth-texture`，不合并 master、不推送。
- 阅读 [编辑工具开发约定](../../prompts/editor-guidelines.md) 与 UI 像素约定；运行一次完整 `odin run tools/check` 作为基线。

不单独提交。

### 2. 视图块

- `kit/rendering/3d/render3d.odin`：`View.globals`；submit 预检大小；`render3d_draw` 提交顶点 b1 与片元 b2。
- `kit/rendering/3d/uniforms.odin`：`VIEW_GLOBALS_SIZE` 与补零打包。
- `kit/rendering/material/draw.odin`：`Material_Draw.view_globals`、`Draw_Error.View_Globals_Too_Large` 及 `draw_error_text`。
- `kit/rendering/material/material_library.odin`：Model 效果的 `UniformBufferCount`。
- `kit/rendering/shader/dev/dev.odin`、`kit/tools/shader_lab/bank.odin`：Model 参数组的预期槽数。
- `kit/rendering/3d/model_material_draw.odin` 透传；Shader Lab 预览传 nil。
- 测试（`tests/kit/rendering/3d/`、`tests/kit/rendering/material/`）只补：超长返回错误且记录保留；补零打包的字节；Model 与 Sprite 效果的槽数差异。

提交：`rendering3d: View.globals 视图级 uniform 块`

### 3. 深度比较补全

- 改 `kit/rendering/material/effect.odin`、`kit/rendering/material/draw.odin`、`kit/rendering/shader/lang/README.md`。
- 测试：`lang_test` 解析新增的四个 ZTest 值；`draw_test` 覆盖 `Pass_Depth` 全部取值到 foster DepthCompare 的映射（含 Off 关闭测试、Default 不改状态）。

提交：`material: ZTest 补全 Greater / Greater_Equal / Not_Equal / Never`

### 4. 深度附件可采样

- `foster/graphics.odin`（`TextureIsSampleable`、TargetInit）+ `foster/docs/LOCAL_CHANGES.md`；`kit/rendering/material/material.odin` 拒绝不可采样贴图。
- 测试只覆盖 CPU 可判定的拒绝路径；GPU 行为在第 5 步示例中验收。

提交：`rendering: 单采样深度附件可作为材质贴图采样`

### 5. olib_sample 验收示例

- 新建 `src/stylized3d`（按 olib_sample 现有示例的入口与 run 约定），用自建的简单几何，**不复制 Celeste64 的资产**，代码只作参考。按背景里的流程画一帧：
  低分辨率场景 Target → 背景（单独 Pass 先 submit）→ 地形（`scene`）→ 剪影（`silhouette`，ZTest Greater）→ 角色本体（`body`）
  → 深度描边后处理（Render2D + 读深度附件的材质，画到另一张 Target 再合回）→ 透明与 billboard → UI。
- 太阳方向、雾色和相机轴走 `View.globals`；再提交一个小视图（例如俯视小地图），globals 不同，billboard 在两个视图里都朝向各自的相机。
- UI 在最终窗口像素尺寸绘制，不随低分辨率场景放大。
- 截图输出到 olib_sample/library/screenshots，同场景复用文件名：剪影透过墙可见且不叠在本体上；描边沿深度边缘；两视图光照与 billboard 朝向各自正确。
- material3d、forward3d 不改代码，重跑确认画面不变（旧 Shader 不声明新槽也能画）。
- 记录 Draw 数与 submit 的 CPU 时间；GPU 时间未测时明确标注。D3D12、Vulkan 实测；Metal 只确认 `.msl` 生成与编译通过。

提交：olib_sample `samples: stylized3d 验收视图块、剪影与深度描边`

### 6. 文档

- `kit/rendering/3d/README.md`：在“相机、灯光与运行时贴图”一节加入 globals，说明材质参数（逐材质）与 globals（逐视图、场景共用）的分工；
  剪影的分阶段顺序与 Pass 命名；深度后处理的目标切换与线性化；阴影图示例注明深度附件需单采样。
- `kit/rendering/3d/REFERENCE.md`：槽位表加顶点 b1 / 片元 b2 视图块，注明顶点 b2/b3 预留给蒙皮。
- `kit/rendering/material/README.md`：深度附件的采样条件；`kit/rendering/README.md` 的 API 速查按需更新。

提交：`docs(rendering3d): 视图块、深度比较与深度贴图`

### 7. 按 docs/plans/README.md 归档本计划

## 待定：蒙皮（不在本计划执行范围）

Celeste64 的主角是蒙皮模型，任何角色 3D 游戏都会马上用到。需要用户先定下面几点，再单独写计划：

1. **Shader 变体**：(a) `.oshader` 的 `Draw Model` 像 instanced 一样自动生成蒙皮顶点变体；(b) 作者另写 `Draw Skinned_Model` Pass；
   (c) Celeste64 式单 Shader + 开关。olib 静态 48B、蒙皮 68B 步长不同，(c) 仍需两种顶点格式，等同于 (a)。建议 (a)。
2. **骨骼数据**：每条记录复制 palette（≤128 关节，两块 4KB，走顶点 b2/b3，约 8KB/记录），还是借用调用方数组到 clear。建议复制，与现有“记录复制 CPU 数据”一致。
3. **合批**：首版蒙皮记录逐条 Draw、不实例化；palette 放 storage buffer/纹理以支持实例化，留到有需求时。
4. **包围盒**：动画姿态的保守盒由调用方传入（与现在 bounds 语义一致），库不从动画推算。
5. **职责**：动画采样与混合留在游戏或 dasset，Render3D 只接收 palette。
6. 蒙皮与 `Model_Buffer` / instanced 材质组合时返回错误，不静默画错。

## 验收

- `odin run tools/check` 全部通过（含 -vet、单元测试、foster 回归、LOCAL_CHANGES 校验与示例编译）。
- 第 2–4 步新增的回归通过；旧清单（含 `Always` 等原有取值）仍能登记；Shader Lab 能热重载声明了视图块的 Model Shader。
- stylized3d 截图满足第 5 步各项；material3d、forward3d 画面不变。
- 同一份记录提交给两个视图，globals 互不影响；globals 超长时报错且记录保留。

## 禁止事项

- 不在库内加入光照、雾、阴影、描边等外观实现；示例里的这些只属于示例。
- 不复制 Celeste64 的资产；不升 `MANIFEST_VERSION`；不重命名 foster 的 `GreatorOrEqual`。
- 不给 Render2D 的 View 加 globals；不新增包装结构体或 Texture 字段；不改 Render2D/Render3D 的 submit 生命周期。
- 不修改 Proj_Sand；不改 `docs/plans/archive/` 里的历史计划正文。
- 不实现蒙皮（见“待定”）。

## 汇报内容

各仓库的提交范围、`tools/check` 输出摘要、截图路径与变化、Draw 数与 CPU 计时、D3D12/Vulkan/Metal 的实测边界、与计划的偏离；
蒙皮各待定项仍待用户决定；验收后按 README 立即单独归档。
