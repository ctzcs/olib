# Plan：仓库工具脚本改用 Odin 编写

> **状态：已完成（2026-10-14）** · 提交 `d0a2626`..`ff11dc7`（olib_sample：`146369b`）
> 偏离：① `-only` / `-dir` 额外接受被拆开的写法（`-only: x`、`-only x`）：PowerShell 会把 `-only:x` 拆成两个参数传给原生程序。② LOCAL_CHANGES 的成功汇总行（“本地修改标记一致：N 条记录”）与其他检查项一样只在失败时打印，条数未单独核对；三种故障注入的输出与 ps1 逐字一致。③ 重新编译的 18 个着色器产物按 git 规范化后的 blob 比对（MSL 是文本，工作区换行符随 autocrlf 不同），全部一致。④ 执行第 4 步时，我的 Python 脚本先截断了 olib_sample 的 README.md 才断言失败，导致用户未提交的 book_ui 段落丢失；已从本机会话记录恢复，恢复结果的 git 哈希与原工作区版本（`a04ad7f`）一致。

## 背景

olib 的开发工具目前都是 PowerShell 脚本，并且都用 `powershell -File ...` 调用：

| 脚本 | 作用 | 引用处 |
| --- | --- | --- |
| `check.ps1` | 提交前一键检查：core/kit 全部包 `-vet`、单元测试、foster `-vet` 与回归程序编译、LOCAL_CHANGES 校验、imgui 示例编译、同级 olib_sample 示例编译与示例测试 | AGENTS.md、README、docs/CODE_STYLE、docs/ROADMAP、prompts/* |
| `foster/tests/check_local_changes.ps1` | `[olib L-xxx]` 标记与 `foster/docs/LOCAL_CHANGES.md` 一一对应 | check.ps1、foster/docs/CODE_STYLE、LOCAL_CHANGES、PORTING_MAP |
| `kit/rendering3d/shaders/build_shaders.ps1` | SDL_shadercross 编译 HLSL → spv/dxil/msl，`-Dir` 指定目录 | kit/rendering3d README 与 shader3d.odin、docs/ROADMAP、olib_sample README 与 forward3d/renderer.odin |

`powershell` 是 Windows 自带的 Windows PowerShell 5.1，只能在 Windows 上运行；macOS / Linux 只能另装 PowerShell 7（命令名是 `pwsh`）。check.ps1 内部还会再调用 `powershell`，产物也写死了 `.exe`，所以离开 Windows 就无法使用。

当前 Odin nightly（dev-2026-10）的 `core:os` 已经提供写这类工具需要的接口：`process_exec`（运行命令，收集 stdout/stderr 与退出状态）、`read_all_directory_by_path` / `walker_create`（遍历目录），加上 `core:path/filepath`、`core:strings`。`odin run <dir> -- <args>` 运行结束后会自动删除生成的可执行文件。2026-10-14 已用约 30 行原型验证：遍历 `kit/` 逐包运行 `odin check -vet`，结果与 check.ps1 一致。

## 已定决策（执行时不要改）

1. **工具放在 `tools/` 下，每个工具一个 `package main`**：`tools/check`、`tools/shaders`。只依赖 `core:*`，不 import olib 自己的包，这样工具不会被自己检查的代码弄坏。
2. **调用方式**：
   - `odin run tools/check`（olib 根目录）；`odin run tools/check -- -no-samples`；`odin run tools/check -- -only:<子串>`。
   - `odin run <olib>/tools/shaders -- -dir:<着色器目录>`；不传 `-dir` 时编译 `kit/rendering3d/shaders`。
3. **`tools/check` 与 check.ps1 行为完全一致**：
   - 检查项、顺序、命名一致（`check  kit/ui`、`test   kit/ui`、`build  foster/tests/port_regression`、`local  foster LOCAL_CHANGES`、`sample game_ui`、`test   sample forward3d` 等）。
   - 输出格式一致：通过打印 `ok    <名称>`，失败打印 `FAIL  <名称>`，紧接着输出该步的完整 stdout 与 stderr；结尾打印 `全部 N 项通过`，或 `M 项失败，N 项通过：` 加失败列表。有失败时退出码为 1。
   - 包的自动发现规则一致：`core/`、`kit/` 下所有含 `.odin` 的目录做 `odin check -vet`，含 `@(test)` 的目录做 `odin test -vet`；同级 `olib_sample/src/*` 逐个编译，含 `*_test.odin` 的额外 `odin test`。
   - 新增一组检查：`tools/` 下的每个工具包也跑 `odin check -vet`。
   - 产物仍写到 `build/check/`；可执行文件的后缀按平台决定（Windows 是 `.exe`，其他平台无后缀）。
   - 定位 olib 根目录用 `#directory`（编译期的源码目录）向上两级，不依赖当前工作目录。
   - 按顺序执行，不做并行。
4. **LOCAL_CHANGES 校验在 `tools/check` 进程内完成**，不再启动子进程。规则与 check_local_changes.ps1 一致：清单中有重复编号、代码有标记但清单没有、清单有记录但代码没有，都算失败，并打印具体文件与行号。单独运行时用 `odin run tools/check -- -only:local`。
5. **`-only:<子串>`** 只运行名称包含该子串的检查项，用于单独跑某一步（例如 `-only:local`、`-only:kit/ui`）。`-only` 与 `-no-samples` 可以同时使用。除这两个参数外不加其他开关。
6. **`tools/shaders` 与 build_shaders.ps1 流程一致**：目录下每个 `*.hlsl`（跳过 `*.hlsli`）的 vertex 和 fragment 两个阶段，都依次执行 `shadercross` 把 HLSL 编成 spv，再从 spv 转出 dxil 和 msl。HLSL 那一步传 `-I <dir>`。产物写到 `<dir>/Compiled`。shadercross 只从 PATH 查找，找不到就报错退出，不再写死 `D:\Tools`。
7. **直接删除三个 ps1，不保留转调用的过渡脚本**：`check.ps1`、`foster/tests/check_local_changes.ps1`、`kit/rendering3d/shaders/build_shaders.ps1`。所有文档同步改为新的调用方式。
8. **新游戏模板也改为推荐 Odin 工具**：`prompts/new-project.md` 里让游戏写 `check.ps1` 和 `tools/check_layers.ps1` 的部分，改为写 `tools/check`（Odin，可参考 olib 的 `tools/check`），层间依赖检查作为其中一步。已有游戏（Proj_Sand）的 check.ps1 不在本计划范围。
9. **不在本计划范围**：`foster/tests/graphics_regression/run.ps1`、`foster/tests/webtest/build_web.{bat,sh}`、`thirdparty/` 下的脚本、olib_sample 的 `run.bat`（这些本来就是针对特定平台或第三方的）；以及新增检查项、并行执行、增量编译。

## 执行步骤

前置：`rendering3d-mechanism-only` 分支已合并到 master（本计划依赖它对 check.ps1 加的示例测试步骤，以及 build_shaders.ps1 的 shadercross 版本）。从 master 新建分支 `odin-tools`。开始前运行 `powershell -File check.ps1`，确认全部通过，并记下检查项总数（2026-10-14 为 55 项）。

### 1. tools/check：与 check.ps1 等价

按决策 1～3、5 实现 `tools/check`（LOCAL_CHANGES 这一步暂时仍调用 ps1，第 2 步再换成进程内实现）。

验收：

- `odin run tools/check` 与 `powershell -File check.ps1` 的检查项名称列表一致（逐行 diff），新工具只多出 `check  tools/check`。
- 两者都全部通过；`-no-samples` 下两者的项数也一致。
- 失败路径：临时在某个 kit 包里制造一个 vet 错误（不提交），新工具打印 `FAIL` 加编译器输出，退出码为 1；改回后通过。
- 在 olib 以外的目录运行 `odin run <olib>/tools/check`，结果相同。
- Windows Terminal 下中文输出不乱码。乱码就在 Windows 上调用 `SetConsoleOutputCP(65001)`（`core:sys/windows`）。

提交：`tools: 用 Odin 实现 tools/check（与 check.ps1 等价）`

### 2. LOCAL_CHANGES 校验内置

按决策 4 把校验移进 `tools/check/local_changes.odin`。

验收：

- 当前仓库通过，打印条数与 ps1 一致。
- 以下三种情况都能报出（只做临时改动，不提交）：
  - 清单里删掉一行；
  - 代码里多出一个 `[olib L-999]`；
  - 清单里出现重复编号。

提交：`tools/check: 内置 foster LOCAL_CHANGES 校验`

### 3. tools/shaders

按决策 6 实现，并在 `tools/check` 的工具包检查中加上 `check  tools/shaders`。

验收：

- 用 `odin run tools/shaders` 重新编译 kit 的 DebugLine3D，用 `odin run tools/shaders -- -dir:../olib_sample/src/forward3d/shaders` 重新编译 forward3d。两边产物与入库版本逐字节一致：shadercross 版本没变，所以必须一致，不一致就查清原因再继续。
- PATH 里没有 shadercross 时，报错信息清楚。

提交：`tools: 用 Odin 实现 tools/shaders（替代 build_shaders.ps1）`

### 4. 切换并删除 ps1

按决策 7、8 删除三个 ps1，并更新全部引用：

- `AGENTS.md`、`README.md`、`docs/CODE_STYLE.md`、`docs/ROADMAP.md`
- `foster/docs/CODE_STYLE.md`、`foster/docs/LOCAL_CHANGES.md`、`foster/docs/PORTING_MAP.md`
- `kit/rendering3d/README.md`、`kit/rendering3d/shader3d.odin` 的注释
- `prompts/new-project.md`、`prompts/dod-guidelines.md`
- olib_sample：`README.md` 和 `src/forward3d/renderer.odin` 的注释。在它自己的仓库单独提交，只暂存这几处改动，不带上用户未提交的修改。

完成后复查：`git grep -n "check\.ps1\|check_local_changes\|build_shaders"` 只剩 `docs/plans/archive/` 里的历史计划。

提交：olib `tools: 删除 check.ps1 等 PowerShell 脚本，文档改用 odin run tools/*`；olib_sample `docs: 着色器编译改用 olib tools/shaders`

### 5. 按 docs/plans/README.md 归档本计划

## 验收

- olib 根目录 `odin run tools/check` 全部通过：检查项为原 55 项，加上 `check  tools/check` 和 `check  tools/shaders`。
- Proj_Sand 根目录 `powershell -File check.ps1` 全部通过（它只依赖 olib 的包，不依赖 olib 的脚本）。
- 第 1～3 步各自的验收都已完成，结果写进汇报。
- 仓库里除决策 9 列出的文件以外，不再有 `.ps1`。

## 禁止事项

- 不改检查内容：不增加检查项（`tools/` 的 vet 除外），不放宽或收紧现有检查。
- 工具不 import olib 自己的包（`olib:*`）。
- 不改 `docs/plans/archive/` 里历史计划的正文。
- 不动 Proj_Sand。
- 不动 olib_sample 里用户未提交的改动（`README.md` 的 book_ui 段落、`src/book_ui/`、`.zed/`）。

## 汇报内容

- 两个仓库各自的 commit 列表。
- 第 1 步新旧检查项列表的 diff 结果，以及失败路径的输出片段。
- 第 2 步三种故障注入的输出。
- 第 3 步字节比对结果。
- `odin run tools/check` 的最终结果与项数，Proj_Sand 的检查结果。
- 与计划不一致的地方及原因。
