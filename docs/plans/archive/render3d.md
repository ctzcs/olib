# Plan：Render3D（第二阶段）

> **状态：已完成（2026-10-20）** · olib 提交 `8b219cc`..`dcbdadc`
> 偏离：Odin 不支持结构体字段默认值，draw_debug 使用 Maybe(bool) 表达“未指定则开启”，零 view_matrix 按单位矩阵处理。Foster 没有实例缓冲起始偏移绑定，临时实例按批次/Pass 紧凑上传并复用容量。不透明也仅合并排序后相邻的兼容项，以保留组内前到后顺序。
> olib_sample：`949d3b9`（迁移与演示）、`3b2f1b8`（文档与实测）；两个仓库均在 render3d 分支，未合并、未推送。Proj_Sand 未修改。
> 验收：完整 `odin run tools/check` 全部 86 项通过；新增 2 个 CPU 回归，复用并扩充既有队列/缓冲错误检查。material3d 默认、第二视图、单个与 4096 个自动实例、百万常驻实例及 forward3d 已运行，最终输出截图位于 olib_sample/library/screenshots。默认双球布局/描边保持，shot 改为固定动画时间；多视图和自动实例是新增展示。Shader Lab 编译回归通过，工具入口保留。
> 性能：D3D12、1100×720、4x MSAA、tools/check 默认构建，预热 10 帧后统计 120 帧。默认 4 Draw / submit CPU 0.046 ms；多视图 6 Draw / 0.080 ms；4096 自动实例 1 Draw / 0.891 ms；百万常驻实例 1 Draw / 0.030 ms。GPU 时间未测，16.667 ms 的受限帧时间不作为 GPU 耗时。

## 背景与范围

第一阶段 Render2D 已完成。本阶段按用户给出的方向，提供记录式 Render3D：模型、实例组和调试线统一记录，
submit 按当前视图剔除、排序、合批；同一份记录可提交给多个相机和 Pass，游戏编排阶段。

现有实现可复用：

- `kit/rendering/3d/model_material_draw.odin`：模型材质 Pass 执行及 Shader Lab 工具入口。
- `model_buffer.odin`：已有 Model_Item、Model_Buffer、平铺实例数值数组，不新增 Instance_Array 包装。
- `queue.odin`：Render_Queue 当前只有不透明/透明与深度排序，尚无材质分组；保留手写渲染器用法。
- `kit/world/frustum3d.odin`：从 VP 提取视锥并测试 AABB。
- `debug_draw.odin`：调试线几何与 GPU 资源；现有 render 会清空，不能直接用于重复 submit。

当前 Foster Mesh 不保存局部包围盒；现有 View 只有 VP，没有排序所需的视矩阵。
本计划不新建 Mesh、Camera 或材质包装类型。

## 用户已确定的方向

1. Render3D 的常用入口为 `model`、`models`、`line / aabb` 等、`submit` 与单独的 `clear`。
2. submit 不清空记录。同一份记录支持先阴影视图与 shadow Pass，再主视图与场景 Pass。
3. submit 使用 kit/world 做视锥剔除；不透明按材质分组、前到后，透明后到前。
4. 同网格、同 instanced 材质的兼容记录自动实例化；调试线在同一次 submit 内绘制。
5. 保留多 Pass 及状态、进阶常驻实例缓冲、Render_Queue；Render3D 内部也使用该队列。
6. 少加接口和测试，不改用户要求保持的平铺实例数组，不修改 Proj_Sand。

## 实现细则建议

以下是为使上述方向可实现而补充的具体语义；本阶段计划评审以此为准。

### 业务 API 与生命周期

```odin
init(r: ^Render3D, library: ^mat.Material_Library) -> string
dispose(r: ^Render3D)
clear(r: ^Render3D)

model(r, mesh: ^foster.Mesh, material: ^mat.Material, transform: world.Matrix4,
    bounds: ^dasset.Dasset_Bounds = nil, values: ^mat.Instance_Values = nil) -> mat.Draw_Error
models(r, mesh: ^foster.Mesh, material: ^mat.Material, items: []Model_Item,
    bounds: ^dasset.Dasset_Bounds = nil, values: [][4]f32 = nil) -> mat.Draw_Error

// 进阶：借用已经上传的常驻缓冲；bounds 是整块实例的世界包围盒。
buffer(r, mesh: ^foster.Mesh, material: ^mat.Material, buf: ^Model_Buffer, count: int,
    bounds: ^dasset.Dasset_Bounds = nil) -> mat.Draw_Error

line(r, from, to, color, ...)
aabb(r, bounds, color, ...)
submit(r, view: View, pass_id: mat.Pass_Id = "") -> mat.Draw_Error
```

- 直接传 Mesh、Material 和已有 Model_Item；models 是批量记录入口，不要求业务先创建 GPU 缓冲。
  普通材质仍可使用 models，提交时逐个画；instanced 材质由 Render3D 管理临时实例缓冲。
- 单个 model 的实例字段：材质值 → values → Pass 固定覆盖。models 的平铺数组按 slots 读取，
  nil 沿用材质默认值；这与进阶 model_buffer_upload 的 nil 表示全零分开说明。
  各 Pass 的独立参数和覆盖必须分别生效，不能只取第一个 Pass 的实例值。
- model 默认白色 tint；models 沿用 Model_Item.tint。非 instanced 路径通过既有帧 Tint 约定传值。
- 记录时复制矩阵、包围盒、CPU 实例数据及材质数值/贴图绑定，不借用调用者的临时切片。
  Mesh、Shader、纹理、常驻 GPU 缓冲借用到 clear/dispose；清空记录后才能重载或销毁这些资源。
- submit 只生成本次视图的可见队列，不修改原记录，不隐式 clear，也不清颜色/深度附件。
  游戏清目标继续使用 Foster；clear 仅清 CPU 记录、保留复用容量。
- 记录错误不加入队列；submit 先验证本次候选，再发 Draw，失败保留原记录。
  空记录是成功的空操作。初始化返回空串为成功。
- View 保留 target、view_projection、时间字段，补充 view_matrix（默认单位矩阵）及
  draw_debug（默认 true）。直接从现有 Camera3D 取矩阵，也可传游戏自己的正交阴影视图矩阵。
  不新增相机类，不在 submit 中改相机 viewport。调试线根据本次视图重新展开，兼容视图方向。

```odin
r3d.clear(&r)
r3d.model(&r, &mesh, material, transform, bounds = &primitive.bounds)
r3d.models(&r, &tree_mesh, tree_material, trees, bounds = &tree_bounds, values = tree_values)
r3d.aabb(&r, debug_bounds, debug_color)

// targets 的创建、清理与阶段间资源绑定由游戏负责。
shadow_view.draw_debug = false
r3d.submit(&r, shadow_view, "shadow")
r3d.submit(&r, main_view, "body")
// 此处仍可再提交同一份记录；下一帧重新记录之前 clear。
```

### 剔除与排序

- model/models 的 bounds 是共享网格的局部 AABB，使用每个实例的矩阵变换八角得到保守世界 AABB。
  每次 submit 都重新按当前 VP 剔除；先画阴影不得丢掉主相机仍需要的记录。
- 未提供 bounds 时保守保留对象，不从 GPU 读回顶点、不把零大小盒当作“未知”、不新建网格注册表。
  由 Shader 扩张的几何需要调用方提供覆盖扩张范围的保守盒。
- 排序深度使用视矩阵和世界包围盒中心；无盒时用世界矩阵平移点。
  不用投影后的深度或到相机的欧氏距离替代视空间深度。
- 透明分类来自本次所选 Pass 的有效 Blend 状态，不能仅检查材质名字或颜色 Alpha。
  Model 默认/显式 Opaque 进入不透明桶，Alpha/Premultiplied/Additive 进入透明桶。
- 不透明：材质及绑定快照分组优先，组内前到后；材质组按最近深度排列，同深度稳定。
  这是组内前到后，不宣称与“全场景严格深度顺序”同时成立。
- 透明：全局后到前、同深度保持记录顺序；只对排序后相邻的兼容项实例化。
  不跨越其他透明对象搜集相同 Mesh/Material；对象交叉的逐像素透明排序不属于本阶段。
- 现有 Render_Queue 默认排序行为保持不变。通过最小可选排序扩展供 Render3D 材质分组使用，
  不复制第二套队列；大量实例不能沿用当前 O(n²) 插入排序，使用可复用工作区的稳定排序。

### Pass、自动实例化与常驻缓冲

- 非空 pass_id 选择同名 Pass；队列中不含该 ID 的材质不参加这一阶段。
  非空模型记录中完全不存在这个 ID 时返回 Unknown_Pass，避免静默吞掉拼写错误；
  已声明但禁用的 Pass 不绘制。此检查在剔除前做，不能因当前相机没看到对象就误报。
- pass_id 为空时保留各效果声明顺序；全不透明的兼容组逐 Pass 整批画。
  含透明 Pass 的多 Pass 对象作为一个排序单元，按对象保持 Pass 顺序，禁止跨对象自动合批改变混合次序。
  游戏需要全场景分阶段时显式多次 submit，不由 Render3D 猜测“阴影”“本体”“描边”。
- 自动实例化要求 Mesh 指针、Material 指针、所选 Pass、uniform、纹理/采样与有效状态兼容。
  instanced 材质即使只有一个 model 也能画；非 instanced 材质不生成隐式 Shader 变体。
  每次 submit 的临时实例数据按该视图的可见与排序结果紧凑上传；数值不同的实例字段不拆批。
- 同材质同 Mesh 不保证跨越排序屏障后仍只有一个 Draw；透明正确性与 Pass 状态优先。
- 常驻 Model_Buffer 保留，只借用引用，不读回、不逐实例重排，也不每帧重复上传。
  buffer 的 bounds 用于整块剔除，透明常驻缓冲内部顺序仍由调用方负责；重复提交不能假装自动处理了块内透明排序。
  高阶接口明确这个限制，普通 models 则提供逐实例剔除和排序。
- draw_debug=false 时不提交调试线。开启时在模型之后画，默认深度测试、不写深度；
  调试线不参与模型材质 Pass，也不会因先提交阴影而被清掉。复用现有线宽/颜色与几何函数。

## 执行步骤

### 1. 前置与队列准备

- 执行时检查 olib、olib_sample 工作区。当前基础分别为 render2d 的 `2713a64` 与 `667ce09`；
  从这两个已完成第一阶段的 HEAD 新建 render3d 分支，不擅自合并 master 或推送。
- 阅读渲染/编辑工具及最终像素采样约定，运行一次完整 `odin run tools/check` 作为基线。
- 给 Render_Queue 增加最小的可选分组排序支持，保留 forward3d 默认深度排序语义。
- 复用已有 queue 测试，覆盖默认行为与分组后透明顺序即可。

提交：`rendering3d: 支持 Render3D 所需的稳定分组排序`

### 2. Render3D 记录、重复提交与剔除

- 新建 render3d.odin，按上述语义实现 init/dispose/clear、model/models、View、submit。
- 复用材质选择和快照逻辑，实现每视图的保守 AABB 剔除、Pass 筛选与排序。
- 先打通普通材质，覆盖一份记录在两个相机提交后仍完整、clear 才移除；不写镜像实现的测试。

提交：`rendering3d: 新增可重复提交的 Render3D`

### 3. 自动实例化、常驻缓冲与调试线

- 接入 instanced 材质、每 Pass 独立实例值与可复用临时实例缓冲；保留平铺数组。
- 添加 buffer 记录入口；model_buffer_init 的 bool 改为 string，迁移已知调用方并保持失败原因清楚。
- 接入 line/aabb 及已有常用调试图元。分离调试线的保留式绘制实现和旧入口的清空策略，
  Render3D 不复制一份几何实现，forward3d 的独立 Debug_Draw_3D 路径仍可用。
- 针对合批边界、透明顺序及重复提交后的调试线保留补最少必要回归。

提交：`rendering3d: 自动实例化与调试线统一提交`

### 4. 调用方迁移与验收

- olib_sample/material3d 迁移普通 model、models 和常驻 swarm；使用现有截图入口验收。
  在该示例中复用同一记录提交不同视图/Pass，展示库机制，不新增完整阴影渲染管线。
- forward3d 保持手写渲染器、Render_Queue 和独立调试线；仅调整必要接口变动。
- Shader Lab 保留 model_material_draw 工具入口及 Pass/回调能力，不强行改为业务记录接口。
- 完成调用迁移后删除旧业务 model_draw/model_draw_buffer，不保留转发别名；工具入口保留。
- Proj_Sand 按用户指示不改；WebPreview 无 3D 使用方，不做无关改动。
- 运行完整 `odin run tools/check`；只运行实际受影响的示例画面与既有回归。
  记录 Draw/实例数及 CPU 提交时间；GPU 时间未测时明确标注，不用 vsync 帧时冒充渲染耗时。

提交：olib `rendering3d: 完成业务入口迁移`；olib_sample `samples: material3d 改用 Render3D`

### 5. 文档

- 3d/README 只讲 model/models、重复 submit/clear、相机与 bounds、普通合批行为。
- 3d/REFERENCE 放常驻缓冲限制、手写队列、Shader/工具接口；更新渲染总览、材质说明与示例 README。
- 说明 Render2D submit 会清空、Render3D submit 会保留，这是两者当前明确的生命周期差异。
- 复查旧业务入口无残留调用，历史归档正文不改。

提交：`docs(rendering3d): Render3D 用法与进阶接口`

### 6. 按 docs/plans/README.md 归档本计划

## 验收与禁止事项

- 两个不同相机的剔除结果独立，重复提交不丢模型或调试线；空提交和 clear 行为明确。
- 不透明材质分组、透明远到近、相同深度稳定；透明合批不跨越其他绘制。
- 单个及多实例 instanced 材质都能画；多 Pass 参数/状态保持独立；常驻 swarm 不重复上传。
- 所有现有检查通过；UI 在最终输出尺寸绘制，不随低分辨率 3D 场景放大。
- 不改 foster，不引入场景管理、FrameGraph、自动灯光/阴影/后处理、蒙皮或自动 LOD 策略。
- 不新增 Mesh/Camera/Instance_Array 包装，不改 Render2D 生命周期，不修改 Proj_Sand。
- 汇报各仓库提交、检查结果、截图变化、CPU/GPU 计时边界及计划偏离；验收后立即单独归档。
