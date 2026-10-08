# Plan：foster 每帧清理临时分配器 + 全库通过 -vet

## 背景

编写 `prompts/` 时发现两个库层面的问题：

1. **foster 的主循环从不清理 `context.temp_allocator`**。OFoster_Sample 的示例也没有清理，每帧用到的临时内存会一直累积。目前 `prompts/new-project.md` 和 `prompts/dod-guidelines.md` 只能要求游戏自己在每帧末尾 `free_all`，容易遗漏。
2. **olib 自己没有通过 `-vet`**，游戏无法对整个工程开 `-vet`，提示词里只能退而求其次，用 `-vet-packages` 只检查游戏自己的包。用下面的命令在 olib 根目录逐包检查，目前共 25 处错误：

   ```bash
   odin check <包路径> -collection:olib=. -no-entry-point -vet -vet-packages:<包名>
   ```

   | 位置 | 问题 |
   |---|---|
   | `foster/storage.odin:586` | 循环变量 `entry` 未使用 |
   | `foster/images.odin:789` | `data` 遮蔽第 777 行的参数（有意：遮蔽成拷贝后的数据） |
   | `core/dasset/dasset_io.odin:146, 163, 168, 188, 261, 271` | 循环变量 `i` / `j` / `c` 未使用 |
   | `core/dasset/dasset_io.odin:361, 442` | 同宽整数之间用了 `transmute`，应该用 `cast` |
   | `core/debug/debug.odin:8, 9` | import `fmt`、`mem` 未使用 |
   | `core/entities/entities.odin:14` | import `runtime` 未使用 |
   | `core/handle/virtual/virtual.odin:71` | import `runtime` 未使用 |
   | `core/tween/interpolated.odin:5`、`core/tween/tween.odin:6` | import `math` 未使用 |
   | `kit/asset/asset.odin:286` | `ok` 遮蔽第 271 行的 `ok` |
   | `kit/asset/blob.odin:12` | import `mem` 未使用 |
   | `kit/rendering3d/renderer3d.odin:9`、`kit/rendering3d/uniforms3d.odin:9` | import `mem` 未使用 |
   | `kit/rendering/rendering.odin:15` | import `foster` 未使用 |
   | `kit/ui/ui_widgets.odin:383` | `value` 遮蔽参数 |
   | `kit/ui/ui_widgets.odin:414` | `width` 遮蔽参数 |
   | `kit/world/camera2d.odin:4`、`kit/world/scene_router.odin:8` | import `math` 未使用 |

   **注意：** `odin check` 不检查 `#+test` 测试文件，测试文件里可能还有错误，见第 2 步。

## 已定决策（执行时不要改）

1. 临时分配器在 foster 的 `tick_app`（`foster/framework.odin`，约第 1977 行）末尾统一清理，也就是 `RenderProc` 和 `end_frame` 之后。桌面主循环（`run_impl`）和 Web 的 `foster_step`（`foster/web.odin`）都调用 `tick_app`，只改这一处就能同时覆盖两个平台。**不加开关**，始终清理。
2. 清理的语义是**一帧结束清空**：在 `UpdateProc` / `RenderProc` 里分配的临时内存，下一帧就失效。`StartupProc` 里的临时分配，会在第一帧结束时释放。这些都要写进注释和文档。
3. 这是对 foster 的主动修改，按 `foster/docs/LOCAL_CHANGES.md` 登记为 **L-001**：类型“行为变更”，上游对应写 `App.cs / 主循环（C# 有 GC，无对应）`，同步策略写“保留”。
4. vet 修复**只改写法，不改行为**：未使用的循环变量改为 `for _ in`；未使用的 import 直接删；同宽整数的 `transmute` 改为 `cast`；有意的遮蔽改名（例如 `ok` 改成 `tex_ok`，参数遮蔽改成 `clamped_value`、`min_width` 这类表达意图的名字）。如果某处修复会改变行为，**停下来问用户**。
5. foster 里的 2 处 vet 修复同样要登记，作为 **L-002**：类型“修复”，上游对应写“无（Odin 写法）”，同步策略写“保留”。两处都要打 `// [olib L-002]` 标记。
6. `thirdparty/` 不改。如果游戏可达的代码里 thirdparty 也有 vet 错误，提示词里保留 `-vet-packages` 作为备选写法。

## 执行步骤

在 master 上新建分支 `temp-and-vet`，每一步一个 commit。开始前先运行 `powershell -File check.ps1`，确认现状全部通过。

### 1. foster：tick_app 末尾清理临时分配器（L-001）

1. **先审计跨帧持有的情况**。在 `foster/`（不含 `foster/tests`、`foster/build`）和 `kit/` 里，搜索所有 `context.temp_allocator` 和 `temp_allocator` 的用法（目前约 50 处）。逐一确认：没有任何结构体字段、全局变量或缓存，会在跨过一次 `tick_app` 之后还持有临时分配的内存。如果有，改成长期分配器并写明所有权，或者在汇报里列出来**停下来问用户**。
2. 在 `tick_app` 末尾加上：

   ```odin
   // [olib L-001] 每帧末尾清空临时分配器：Update/Render 中的临时分配到下一帧失效。
   free_all(context.temp_allocator)
   ```

   位置要放在 `if begin_frame ... else if ...` 整个分支**之后**，保证无论哪条渲染路径都会执行到。
3. 在 `foster/docs/LOCAL_CHANGES.md` 的清单里加一行 L-001。
4. 写一个小程序验证（放在 scratch 目录，不提交）：用 `foster.App` 每帧分配约 1MB 临时内存，跑 300 帧后退出；每 100 帧在 `RenderProc` 开头打印一次 `(^runtime.Default_Temp_Allocator)(context.temp_allocator.data).arena.total_used`。**改动前占用随帧数增长，改动后保持在一帧的量级。** 汇报里贴出改动前后的数值。
5. 运行 `powershell -File check.ps1`，并实际运行 OFoster_Sample 的 `run.bat game_ui shot`、`run.bat ui_gallery shot msdf`，与之前的截图对比，必须完全一致。截图基线可以先在改动前生成一份。

Commit：`foster: tick_app 每帧末尾清理临时分配器（L-001）`

### 2. 全库修 vet 错误

1. 按上表逐处修复，遵守“已定决策”第 4 条，只改写法。
2. foster 的 2 处打 `// [olib L-002]` 标记，并在 LOCAL_CHANGES 里登记 L-002。
3. **测试文件也要检查**：对 `core/`、`kit/` 下每个有测试的包运行下面的命令，把测试文件里的 vet 错误一并修掉：

   ```bash
   odin test <包路径> -collection:olib=. -vet -vet-packages:<包名>
   ```

4. 每个包修完都要确认这三条命令全部通过：
   - `odin check <包> ... -vet -vet-packages:<包名>`
   - `odin check foster -collection:olib=. -no-entry-point -vet -vet-packages:foster`
   - 所有带测试的包：`odin test <包> -collection:olib=. -vet -vet-packages:<包名>`

Commit：`全库: 修复 -vet 报错（foster 部分登记 L-002）`

### 3. 把 vet 接进 check.ps1，防止回退

- `check.ps1` 里的单元测试一步改成 `odin test <包> -collection:olib=. -vet -vet-packages:<包名> -out:...`。包名就是目录名的最后一段，与 `package` 声明一致（`core/handle/array` 的包名是 `array`）。
- 对没有测试的包（`core/debug`、`core/encoding`、`core/profiler` 等），加一步 `odin check <包> -collection:olib=. -no-entry-point -vet -vet-packages:<包名>`。做法是自动发现 `core/`、`kit/` 下所有含 `.odin` 文件的目录，对**全部**包都跑 check，不只是有测试的。
- `check foster` 那一步加上 `-vet -vet-packages:foster`。
- 用一个临时加入的未使用 import 验证 check.ps1 确实会报 FAIL，验证完删掉。

Commit：`check.ps1: 全部包启用 -vet`

### 4. 用游戏的视角验证

用 OFoster_Sample 的 `game_ui` 验证游戏能否直接对全工程开 `-vet`（在 OFoster_Sample 根目录执行）：

```bash
odin build src/game_ui -collection:olib=../olib -vet -out:build/game_ui_vet.exe
```

- 如果通过：说明游戏可达的 olib 代码已经干净。
- 如果失败：错误只应该来自 `thirdparty/`（clay-odin），把具体错误记录到汇报里。

### 5. 更新提示词与文档

根据第 1、4 步的结果修改：

- `prompts/new-project.md`：
  - “内存与资源所有权”一节：把“foster 的主循环不会清理临时分配器，游戏在每帧末尾 `free_all`”改为“foster 在每帧末尾（`tick_app` 结束时）清空 `context.temp_allocator`；临时分配只在本帧有效，不要跨帧持有”。
  - App 骨架示例里删掉 `defer free_all(context.temp_allocator)` 和它的注释。
  - “至少验证以下内容”一节的 vet 条目：第 4 步通过时改为“游戏用 `-vet` 编译通过”；失败时保留 `-vet-packages` 的写法，并说明原因是 thirdparty。
- `prompts/dod-guidelines.md`：
  - 第 6 节（并行）里关于“每个线程各自 `free_all`”的说明保留，因为工作线程不经过 `tick_app`。
  - 第 7 节和反面例子表里“foster 主循环不会替你做”的说法，改为 foster 每帧清空、不要跨帧持有。
- `kit/ui/README.md`、`foster/README.md`：如果提到了临时分配的生命周期，同步修改；没有提到就不用动。
- `docs/CODE_STYLE.md` 第 8 节（测试约定）加一句：提交前 `check.ps1` 会对所有包运行 `-vet`。

Commit：`prompts/docs: 临时分配器由 foster 每帧清理；全库 -vet`

## 验收

在 olib 根目录执行：

```bash
powershell -File check.ps1                                           # 全部通过，且已包含 vet
powershell -File foster/tests/check_local_changes.ps1                # 2 条记录（L-001、L-002）一致
grep -rn "不会清理临时分配器\|不会替你做" prompts docs kit foster/README.md   # 无结果
```

另外：

- 第 1 步的临时内存占用，改动前后的对比数值；
- OFoster_Sample 截图在改动前后逐像素一致；
- 第 4 步游戏视角的 `-vet` 结果。

## 禁止事项

- 不要改 `thirdparty/`。
- vet 修复不要顺手重构或重排代码，只改报错的那一行（以及改名后的引用处）。
- 不要 push，不要合并回 master。
- 不要动 `docs/plans/` 里已有的文件（工作区里的 archive 目录调整是用户自己在做的事）。

## 汇报内容

- commit 列表；
- 第 1 步审计跨帧持有的结论（有没有发现问题、怎么处理的）；
- 临时内存占用前后对比、截图对比、check.ps1 输出；
- 测试文件里额外发现并修复了哪些 vet 错误；
- 第 4 步游戏视角 `-vet` 的结果；
- 任何偏离本计划的地方及原因。
