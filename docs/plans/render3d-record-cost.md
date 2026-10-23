# Plan：降低 Render3D 每次记录与每个 Draw 的固定开销

## 背景

Proj_first 实测（debug，D3D12，1280×720，MSAA4）：draw_scene 每帧 2.8 ms，142 次 `r3d.model` 共用一个材质，
折合约 10 µs/次；改成按“关节 × Surface”调用 `r3d.models` 后次数降到约 15 次，只省 0.75 ms。
对照 Proj_OTD 直接用 foster Material、一个 Pass 每帧只设一次 uniform，没有这层开销。

### 本机复测（2026-10-23）

用 olib_sample material3d 的临时副本测：142 个球共用 Outlined 材质（非实例化，body + outline 两个 Pass，
每个记录两个 Draw，共 284 个），记录循环与 submit 分开计时，另外单独计 foster `GraphicsDeviceDraw`。
预热 10 帧后取 120 帧平均。

| 构建 | 记录 | submit 中 Render3D 自身 | foster GraphicsDeviceDraw | Render3D 占比 |
| --- | --- | --- | --- | --- |
| `-o:none -debug` | 0.444 ms（3.1 µs/次） | 0.513 ms（1.8 µs/Draw） | 0.364 ms（1.28 µs/Draw） | 约 72% |
| `-o:speed` | 0.063 ms（0.44 µs/次） | 0.062 ms | 0.184 ms（0.65 µs/Draw） | 约 40% |

实例化材质（Swarm，每个实例单独调一次 `model`，自动合成 1 个 Draw）：

| 构建 | 142 个：记录 / submit | 4096 个：记录 / submit |
| --- | --- | --- |
| `-o:none -debug` | 0.239 ms / 0.124 ms | 6.09 ms（1.49 µs/次）/ 1.31 ms |
| `-o:speed` | 0.033 ms / 0.082 ms | 0.80 ms（0.20 µs/次）/ 0.30 ms |

结论：

- debug 下约 9 µs/对象与 Proj_first 一致，其中约三分之二在 submit 一侧（非实例化材质每个记录、每个 Pass 一个 Draw），
  并非全在记录；Render3D 自身的记录与提交簿记占 debug 总量的约 72%，值得去掉。
- release 下 foster 的每 Draw 开销占大头，Render3D 侧能省的有限；真正的杠杆是减少 Draw 数：
  材质声明 Instanced 后自动实例化把同网格、同快照的记录合成一个 Draw。这是项目侧选择，不在本计划内。

### 热点（读码确认）

1. `render3d_record` 每次调用都做 `mat.material_select`（按字符串匹配参数组名、逐个检查采样器），
   再对每个 Pass 调 `material_pass_values`：temp 上复制全部字段值、套覆盖、`sh.field_index` 按字符串找 Pass 固定值、
   `sh.pack` 打包整块 uniform。材质没变也照样重算。
2. `render3d_source` 对整块 uniform 逐字节 FNV 哈希，再 `mem.compare` 查重。
3. `models` 每个实例一条记录（这是逐实例剔除与排序的语义，保留），但每个实例、每个 Pass 都调
   `material_pass_instance`，其中对每个字段做 `string(fixed.field) == field.id`；`render3d_world_bounds`
   对 8 个角点各做一次带齐次除法的矩阵变换。
4. submit 预检对队列里每一项都重新 `render3d_validate` 并遍历快照的 16 个采样器槽；
   `queue_sort(grouped = true)` 每次比较都查一次 `group_depths` map；`render3d_draw` 每个 Draw 由
   `DrawCommandFromMesh` 在堆上分配 VertexBuffers 动态数组再释放（实例化时还要克隆 VertexFormat）。

## 已定决策

1. **按材质 revision 缓存记录准备结果**（采纳 Proj_first 建议 1）。Render3D 内部按材质指针缓存
   `{revision, shader 指针, selection, source 下标, 各 Pass 的默认实例值}`，clear 时清空。
   revision 与 shader 指针都没变就跳过 `material_select`、`material_pass_values` 和 `render3d_source` 的哈希查重。
   缓存只依赖 `Material.revision`，与 Render2D 的合批规则一致；文档已规定不要绕过
   `material_set_number / material_set_texture / material_reload` 直接改 bindings。
2. **逐实例路径不再比较字符串**（采纳建议 2 中逐实例的部分）。material 包新增按 Pass 预解析的实例值表：
   各槽默认值、钳制范围与分量数、Pass 固定值覆盖的槽位掩码；`model(values=)`、`models(values=)` 与
   Render2D 的逐精灵实例值都用它。缓存未命中时的 `material_select`、`field_index` 仍按字符串查找，
   每个材质每次 revision 变化才走一次，不在注册时另建全局下标表。
3. **不把 `models` 改成一条记录对应 N 个实例**（不采纳建议 3）。逐实例剔除、按深度排序和批次切分是现有语义，
   整块剔除已有 `r3d.buffer` + `Model_Buffer`。改为把逐实例的固定成本降下来：实例值表 + 仿射矩阵的包围盒快速路径
   （中心与半长按 |M| 变换，与 8 角点结果一致；非仿射矩阵仍走原路径）。
4. **提交路径去掉重复工作**：预检按来源（source）与网格各校验一次，不再每个队列项重复；排序前把组的最近深度写进
   队列项，比较时不查 map；`render3d_draw` 不再为每个 Draw 堆分配（绘制命令的动态数组改用 temp 分配或复用）。
   `pack_material_blocks` 的逐 Draw 矩阵乘法是必要工作，保留。
5. **文档写明性能取舍**（采纳建议 4）：每帧变化的灯光、雾等视图级数据放 `View.globals`；
   在同一材质的两次记录之间调用 `material_set_number` 会让缓存失效并新建快照；
   大量重复网格优先用 Instanced 材质（自动实例化）或 `r3d.buffer`。
6. **foster 的 `GraphicsDeviceDraw` 不在本计划内**。debug 1.28 µs/Draw、release 0.65 µs/Draw 是绘制命令本身的成本，
   要优化须单独写 foster(local) 计划。

## 执行步骤

### 1. 基线与基准模式

- 在 olib、olib_sample 各建分支 `render3d-record-cost`；先运行一次完整 `odin run tools/check` 作为基线。
- olib_sample material3d 增加基准参数（例如 `objects=N` 用一个非实例化材质记录 N 个对象；`models each`
  让实例化路径每个实例单独调用 `model`），shot 模式分别打印记录与 submit 的平均耗时及 Draw 数，取代本计划背景里的临时副本。
- 在 `-o:none -debug` 与 `-o:speed` 下记录基线数字（与背景表同口径），写进汇报草稿。

提交（olib_sample）：`samples: material3d 基准模式分别统计记录与提交`

### 2. 按 revision 缓存记录准备结果

- `kit/rendering/3d/render3d.odin`：Render3D 增加按材质指针的缓存（clear 清空、dispose 释放）；`render3d_record`
  与 `buffer` 命中时跳过选择、打包与哈希；未命中时行为与现在相同并写入缓存。
- 测试（`tests/kit/rendering/3d/`）：同一材质连续记录只建一个 source 且只调一次打包（可用计数或快照数断言）；
  revision 递增、shader 指针变化、clear 之后都重新准备；reload 之后的旧记录仍按原快照绘制（现有测试保持通过）。

提交：`rendering3d: 按材质 revision 缓存记录的选择与快照`

### 3. 实例值表

- `kit/rendering/material/draw.odin`（或 instance_values.odin）：按 Pass 构建实例值表与按表求值的函数，
  覆盖顺序与 `material_pass_instance` 相同（材质值 < 本次覆盖 < Pass 固定值，覆盖值按字段范围钳制、非有限值忽略）。
- Render3D 的 `model/models` 与 Render2D 的 `render2d_record_instances` 改用它；表随第 2 步的缓存保存，Render2D 按段保存。
- 测试：对含 Scalar/Vector/Color 字段、范围、Pass 固定值、部分与全部覆盖、NaN 的组合，新函数与
  `material_pass_instance` 结果逐值相同。

提交：`material: 预解析 Pass 实例值覆盖，逐实例不再比较字符串`

### 4. 包围盒仿射快速路径

- `kit/rendering/3d/render3d.odin`：`render3d_world_bounds` 对仿射矩阵（第 4 列为 0,0,0,1）用中心/半长变换；
  非仿射、NaN/Inf 仍走原来的保守路径。
- 测试：随机平移、旋转、非均匀缩放矩阵下与 8 角点结果在 1e-4 内一致；非仿射矩阵结果与原实现相同。

提交：`rendering3d: 仿射矩阵的包围盒按中心与半长变换`

### 5. 提交路径

- 预检按 source 与网格去重校验；排序项携带组深度，`render_item_less` 不查 map（`Render_Queue` 的公开行为不变）；
  `render3d_draw` 的绘制命令不再逐 Draw 堆分配。
- 测试：现有 queue 排序测试保持通过并补一个分组深度相同、按 group 键排序的用例；错误码与“错误保留记录”的行为不变。

提交：`rendering3d: 提交预检按来源校验，排序与绘制命令不再分配`

### 6. 文档

- `kit/rendering/3d/README.md` 增加“性能”小节：记录与 Draw 的成本来源、Instanced 材质与 `buffer` 的选择、
  `View.globals` 放每帧变化的数据、记录之间改材质参数的代价；附第 7 步的实测表。
- `kit/rendering/3d/REFERENCE.md` 说明缓存与 revision 的关系。

提交：`docs(rendering3d): 记录缓存与性能取舍`

### 7. 复测

- 用第 1 步的基准模式在两种构建下复测，与基线对比；material3d、stylized3d 截图与改动前逐像素一致。
- 不单独提交，结果写进归档状态块和汇报。

### 8. 按 docs/plans/README.md 归档本计划

## 验收

- 完整 `odin run tools/check` 通过。
- `-o:none -debug` 下 142 个非实例化对象：记录降到 1.0 µs/次以内（基线 3.1），submit 中 Render3D 自身部分降到
  1.0 µs/Draw 以内（基线 1.8）；实例化 4096 个逐个 `model` 的记录时间至少减半（基线 6.09 ms）。
  达不到时如实写出实测数字和原因，不为凑数改变语义。
- `-o:speed` 下各项不比基线慢。
- 画面不变：material3d（默认、views、swarm、models）与 stylized3d 截图与改动前逐像素一致。

## 禁止事项

- 不改 `model / models / buffer / submit` 的公开签名和语义：逐实例剔除、排序、批次切分、错误码与“错误保留记录”保持不变。
- 不做依赖直接修改 bindings 或数值（绕过 revision）的缓存失效检测，也不为此恢复逐字节比较。
- 不改 foster（含 GraphicsDeviceDraw）；不改 Proj_first、Proj_OTD 等项目代码。
- 不提交临时基准副本；诊断文件只放 library/tmp，用完删除。

## 汇报内容

- 每一步的提交号；两种构建下基线与复测的对比表（记录、Render3D 自身 submit、foster Draw）。
- 截图对比结果；与本计划不一致的地方及原因。
- 给 Proj_first 的复测方式：在其 `Signal.exe profile` 的 PROFILE 行对比 scene（基线 2.06 ms；改成合批前 2.8 ms）。
