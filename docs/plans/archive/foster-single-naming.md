# Plan：foster 对外只保留 PascalCase 一套名字

> **状态：已完成（2026-10-14）** · 提交 `8613c55`..`e5fcde9`
> 偏离：步骤 1 删除 227 行别名（230 行中 `BeginFrame`、`EndFrame`、`ComputeStorageBufferUploadTyped` 按决策 2 保留并改指新定义）；重复实现中 `vec2_length_squared`、`vec2_normalized` 删除并改调 PascalCase 版，`BatcherPushMatrixRaw` 由包装改为直接实现，`clamp01` 与 `Clamp01` 对 NaN / -0.0 结果可能不同，保留并标 `@(private)`；文档步骤顺带改了 kit/rendering3d 与 imgui_impl_ofoster 注释里的旧名；Proj_Sand 无需改动；Web 端只做了 js_wasm32 类型检查，wasm 链接因本机缺 `vendor/sdl3/env.o` 失败（master 上同样失败）。

## 背景

foster 沿用上游 C# Foster 的 PascalCase 命名（与 `vendor:sdl3` 保留 SDL 原名同理：方便对照上游源码与文档、同步上游）。但目前同一个函数常有两个名字，规则没有落实：

| 现象 | 数量（2026-10-14 统计） |
| --- | --- |
| foster 顶层 snake_case proc | 531（已标 `@(private)` 的只有 2 个） |
| `PascalName :: snake_name` 别名 | 230 个，指向 227 个 snake proc（`begin_frame`、`end_frame`、`storage_buffer_upload_typed` 各有两个别名） |
| 被 foster 包外直接调用的 snake proc | 27 个、共 79 处；其中 17 个有别名，10 个没有 PascalCase 名字 |
| 无别名、只在 foster 内部用的 snake proc | 约 290 个 |

包外调用方：`kit/`、`thirdparty/odin-imgui/examples/`、`foster/tests/`（独立包）、同级 `olib_sample/src/`。另一个依赖 olib 的游戏项目 `Proj_Sand` 没有直接调用 snake 名字，所有调用方都用 `import foster "olib:foster"`。

调用方的写法也混用：`foster.Xxx(` 约 490 处，`foster.xxx_yyy(` 约 65 处；CODE_STYLE 里也写成 "`init_app` / `Run` / `Exit` / `dispose_app`"。

## 已定决策（执行时不要改）

1. **对外 API 只用 PascalCase。** 名字以现有 PascalCase 别名为准（例如 `Size :: window_size` 的对外名就是 `Size`），不重新起名。
2. **有别名的 snake proc：把定义直接改成 PascalCase 名字，删除别名行。** foster 内部对旧 snake 名的调用全部改成新名字。snake 名字不再存在。
   - `begin_frame` / `end_frame`：定义改名为 `GraphicsDeviceBeginFrame` / `GraphicsDeviceEndFrame`，保留 `BeginFrame :: GraphicsDeviceBeginFrame`、`EndFrame :: GraphicsDeviceEndFrame`（PascalCase 同义名不在本计划范围，见决策 6）。
   - `storage_buffer_upload_typed`：定义改名为 `StorageBufferUploadTyped`，`ComputeStorageBufferUploadTyped :: StorageBufferUploadTyped`（与同组 `ComputeStorageBuffer*` 别名写法一致）。
3. **没有别名、但被包外调用的 10 个 snake proc：改成下表的 PascalCase 名字**，同样直接改定义，不加别名：

   | 现名 | 新名 | 包外调用方 |
   | --- | --- | --- |
   | `material_init_with_shaders` | `MaterialInitWithShaders` | kit/rendering3d、olib_sample book_ui |
   | `vertex_format_make` | `VertexFormatMake` | kit/rendering3d、olib_sample book_ui |
   | `mesh_init_with_format` | `MeshInitWithFormat` | kit/rendering3d、olib_sample book_ui |
   | `end_render_pass` | `GraphicsDeviceEndRenderPass` | foster/tests |
   | `graphics_device_dispose_caches` | `GraphicsDeviceDisposeCaches` | foster/tests |
   | `version_string` | `VersionString` | olib_sample basic |
   | `sdl_version_string` | `SDLVersionString` | olib_sample basic |
   | `storage_join_path` | `StorageJoinPath` | kit/asset |
   | `storage_dialog_dispose` | `StorageDialogDispose` | foster/tests |
   | `storage_dialog_filters` | `StorageDialogFilters` | foster/tests |

4. **其余 snake proc 一律标 `@(private)`**（包内可见，包外不可见）。规则：
   - 已有属性的合并写成一个，例如 `@(private, require_results)`。
   - 作为公开 proc group 成员的（如 `TargetInit :: proc { target_init, ... }`）照样标 `@(private)`，已验证外部包可以经公开 group 调用私有成员。
   - `@(export)` 的 proc（`web.odin` 里给 JS 调用的）和 foreign 块里的声明不动。
   - 与已有 PascalCase 实现重复的 snake proc（如 `spatial.odin` 的 `clamp01` 与 `foundation.odin` 的 `Clamp01`、`vec2_length_squared` 与 `Vec2LengthSquared`）：包内有调用就改成调用 PascalCase 版并删掉 snake 版；行为不一致时不删，标 `@(private)` 并在汇报中列出。
5. **这是命名整理，不是行为修改**：不登记 L-xxx，不打 `[olib L-xxx]` 标记（LOCAL_CHANGES.md 写明命名差异归 PORTING_MAP 管）。命名规则写进 `foster/docs/PORTING_MAP.md` 和 `docs/CODE_STYLE.md`。
6. **不在本计划范围**：PascalCase 之间的同义名（约 29 个，如 `CardinalEast :: CardinalRight`、`BatcherText :: SpriteFontDraw`、`ComputeStorageBuffer*`、`BeginFrame`）不动；类型名、结构体字段、enum 成员不动；`core/`、`kit/` 的命名不动；不改 proc 的签名和行为。
7. **直接断开**：不保留旧 snake 名字的过渡别名。

## 执行步骤

在 master 上新建分支 `foster-single-naming`，每一步一个 commit（olib_sample 的改动在它自己的仓库单独提交）。开始前运行 `powershell -File check.ps1` 确认全部通过。

改名用脚本做（脚本放 scratchpad，不提交），要求：

- 只替换标识符 token：跳过字符串字面量；跳过前面是 `.` 的成员访问（`foster.` 前缀除外）；注释里的旧名一并替换。
- 每步替换后 `git diff` 人工过一遍，重点看 `run`、`exit`、`present`、`size` 这类短名字有没有误伤局部变量或结构体字段。
- 每步结束跑 `check.ps1`，并在 Proj_Sand 根目录运行 `powershell -File check.ps1`（它用同级 olib 编译与测试）。

### 1. 有别名的 snake proc 改为 PascalCase 定义

按决策 2 处理 227 个 snake proc、删除 230 行别名；同步改 foster 内部调用，以及包外对其中 17 个 snake 名字的调用（kit、thirdparty 示例、foster/tests、olib_sample）。

提交：`foster: 有别名的 snake_case proc 直接以 PascalCase 名字定义`

### 2. 包外调用的 10 个 snake proc 改为 PascalCase

按决策 3 的表改名，同步改全部调用方。

提交：`foster: 包外调用的 snake_case proc 改为 PascalCase`

### 3. 其余 snake proc 标 `@(private)`

按决策 4 处理。处理完后用脚本复查：foster 顶层不存在未标 `@(private)` 的 snake proc（`@(export)` 和 foreign 声明除外）。

提交：`foster: 内部 snake_case proc 标为 @(private)`

### 4. 文档

- `docs/CODE_STYLE.md`：写明 foster 对外沿用上游 Foster 的 PascalCase，snake_case 只用于 `@(private)` 内部实现；`core/`、`kit/` 用 Odin 惯例（类型 Ada_Case，proc/字段 snake_case）。修正 "`init_app` / `Run` / `Exit` / `dispose_app`" 等写法。
- `foster/docs/PORTING_MAP.md`：新增“命名规则”一节（同上），并附旧 snake 名 → 新名对照表（步骤 1、2 中所有包外可见名字的变化，供 Proj_Sand 等外部项目迁移）。
- `foster/docs/LOCAL_CHANGES.md`：“位置”列里的 proc 名改成新名字（如 `tick_app` → `Tick`），编号和其他列不动。
- `README.md`、`foster/README.md`、`foster/docs/*.md` 中提到对外 API 的旧 snake 名字改成新名字；描述内部实现的（如 `web_relocate_app`）保持不变。不改 `docs/plans/archive/`。

提交：`docs: foster 对外只用 PascalCase，补命名规则与对照表`

### 5. 按 docs/plans/README.md 归档本计划

## 验收

1. `powershell -File check.ps1` 全部通过，包括 olib_sample 全部示例。
2. Proj_Sand 的 `check.ps1` 通过（不提交 Proj_Sand）。
3. 脚本复查：foster 顶层没有 `PascalName :: snake_name` 形式的别名；没有未标 `@(private)` 的 snake proc（`@(export)`、foreign 除外）。
4. `grep -rE "foster\.[a-z_][a-z0-9_]*\(" kit thirdparty foster/tests ../olib_sample/src` 无结果。
5. foster 回归程序运行结果与改动前一致（`foster/tests/port_regression` 运行通过；graphics_regression 按其 README 运行）。

## 禁止事项

- 不改 proc 签名和行为，不顺手重构。
- 不给旧 snake 名字留别名。
- 不改类型名、结构体字段、enum 成员、PascalCase 同义名。
- 不改 `docs/plans/archive/` 的历史正文。
- olib_sample 的 `src/book_ui/` 和 `README.md` 是用户未提交的工作：`book_ui` 里的调用必须改（否则 check.ps1 编译失败），但**不提交**这些文件，在汇报里说明改了哪些行。
- 不提交 Proj_Sand。

## 汇报内容

- 每步的 commit 与 check.ps1 结果（失败贴输出）。
- 实际处理的数量：改名定义数、删除别名数、标 `@(private)` 数、删除的重复实现。
- 决策 4 中行为不一致、未删除的重复实现清单。
- olib_sample 未提交文件里改动的位置。
- Proj_Sand 编译结果。
- 计划已归档。
