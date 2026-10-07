# Plan：把 OFoster 并入 olib

## 背景与目标

olib（`D:\MySpace\Github\olib`）目前通过 `-collection:ofoster=<OFoster/src>` 依赖独立仓库
OFoster（`D:\MySpace\Github\OFoster`，remote `https://github.com/ctzcs/OFoster.git`，分支 `master`，
23 个 commit）。目标：把 OFoster 并入 olib 的 `foster/` 目录，**保留 git 历史**，之后只维护 olib 一个仓库。

完成后：

- 包导入路径 `"ofoster:."` → `"olib:foster"`，`"ofoster:internal/third_party"` → `"olib:foster/internal/third_party"`；
- 所有构建/测试命令只需 `-collection:olib=<olib 根>`，不再需要 `-collection:ofoster=...`；
- 包名保持 `package foster`，调用方的 `foster.xxx` 写法不变。

## 已定决策（执行时不要改）

1. **保持 Foster 移植身份**：`foster/` 的 API、命名（PascalCase，如 `StartupProc`、`DefaultAppConfig`）、
   文件组织一律不动。本次只做搬迁和路径替换，**不做任何风格化重构**。
2. `foster/` 和 `thirdparty/` 一样**豁免** olib 的 `docs/CODE_STYLE.md`，沿用它自带的
   `foster/docs/CODE_STYLE.md`。
3. 目标布局（`foster/` 本身就是 Odin 包目录）：

   ```
   olib/
   ├── core/
   ├── engine/
   ├── foster/            ← 原 OFoster/src/* （package foster）
   │   ├── *.odin
   │   ├── assets/shaders/
   │   ├── internal/third_party/ , internal/web/
   │   ├── tests/         ← 原 OFoster/tests/
   │   ├── docs/          ← 原 OFoster/docs/
   │   └── README.md      ← 原 OFoster/README.md
   ├── examples/
   └── thirdparty/
   ```

   依赖方向：`engine → foster`、`engine → core`；`core` 不得 import `foster`；`foster` 不依赖 olib 其他任何包。
4. 本次**不处理** `engine/app/game_app.odin` 的重构（单独的任务）。

## 执行步骤

在 olib 新建分支 `merge-ofoster` 上进行，每一步一个 commit。

### 1. 前置检查

- 两个仓库 `git status` 必须干净；OFoster 的 `master` 是最新状态。
- 确认 OFoster 的源码里没有 `"ofoster:` 自引用（已核实 `src/` 下没有；`tests/` 下有，第 4 步处理）。
- 注意：OFoster 的 `build/` 目录是 gitignore 的（里面是基线包、脚本、exe），**不搬**。subtree 只会带入已跟踪文件，这是预期行为。

### 2. 用 subtree 引入（保留历史）

```bash
git remote add ofoster ../OFoster
git fetch ofoster
git subtree add --prefix=foster ofoster master
git remote remove ofoster
```

不要加 `--squash`，要保留完整历史。此时目录是 `foster/src/`、`foster/tests/`、`foster/docs/`、`foster/README.md` 等。

### 3. 调整布局

用 `git mv` 把 `foster/src/` 下的所有内容（`*.odin`、`assets/`、`internal/`）上移到 `foster/`，然后删掉空的 `foster/src/`。
`tests/`、`docs/`、`README.md` 留在 `foster/` 下。

- `framework.odin` 里的 `#load("assets/shaders/...")` 是相对包目录的路径，上移后依然有效，**不要改**。
- `foster/odinfmt.json`、`foster/.gitattributes` 保留。`foster/.gitignore` 里的规则合并进 olib 根 `.gitignore`
  （改写成带 `foster/` 前缀的路径：`foster/tests/webtest/*.wasm`、`foster/tests/webtest/*.exe`、
  `foster/tests/webtest/odin.js`、`foster/*.wasm`、`foster/build/`），然后删除 `foster/.gitignore`。

Commit：`foster: 把 src 上移为包根目录`

### 4. 替换导入路径

全仓库（含 `foster/tests/`、`engine/`、`examples/`、`thirdparty/odin-imgui/`）执行：

- `"ofoster:."` → `"olib:foster"`（约 45 处，44 个文件）
- `"ofoster:internal/third_party"` → `"olib:foster/internal/third_party"`（`examples/game_ui/font.odin`、`examples/ui_gallery/font.odin`）

imports 写法保持原样（如 `import foster "olib:foster"`）。按 olib 规范，`olib:` 分组内按字母序排列，
原来排在最后的 `ofoster:` 分组要并进 `olib:` 分组。**只调整 import 行，不改其他代码。**

替换完成后，`grep -rn '"ofoster:' --include=*.odin .` 应该没有任何结果。

Commit：`全仓库: ofoster collection → olib:foster`

### 5. 更新构建脚本与命令

所有出现 `-collection:ofoster=...` 的地方，改为 `-collection:olib=<到 olib 根的相对路径>`：

- `foster/tests/port_regression/README.md`、`foster/tests/graphics_regression/run.ps1`
  （`$repoRoot/src` → olib 根）、`foster/tests/webtest/build_web.bat`、`build_web.sh`、`main.odin` 注释里的命令
- `foster/README.md` 里的 “Use the framework” 一节
- `thirdparty/odin-imgui/examples/ofoster/run.bat`：去掉 `OFOSTER_PATH` 相关逻辑（现在它指向的是一个过时的路径
  `tinyglade\ofoster\foster_framework.odin`），改成 `-collection:olib=..\..\..\..`
- `thirdparty/odin-imgui/README.md` 第 86 行附近的说明
- `engine/asset/README.md`、`engine/ui/README.md` 里的测试/构建命令

`thirdparty/odin-imgui/examples/ofoster/` 这个目录名先**不改**，避免牵连 vendored 的 imgui 结构。

Commit：`构建命令去掉 ofoster collection`

### 6. 更新文档

- `README.md`：第 3 行改为 “内置 `foster/`（Foster 框架的 Odin 移植，原 OFoster 仓库）”；布局图加上 `foster/`；
  “使用”和“测试”两节的命令去掉 `-collection:ofoster`；import 示例加一行 `import foster "olib:foster"`。
- `docs/CODE_STYLE.md`：
  - 仓库布局图加上 `foster/`，说明 “Foster 移植，豁免本规范，见 `foster/docs/CODE_STYLE.md`”；
  - 第 20 行依赖方向改为 `engine → foster`、`engine → core → (Odin core/base)`；core 不得 import foster；foster 不依赖 olib 其他包；
  - 第 73 行 imports 排序去掉 `ofoster:` 分组。
- `docs/ROADMAP.md`：第 11 行 “原则：不改 OFoster” 改成 “foster/ 保持 Foster API 对齐；引擎侧能力优先在 engine/ 拼装”；
  第 46、52 行的 “OFoster 仓库自行决定” 改成在 `foster/` 内演进；其余提到 ofoster 的地方统一改为 `foster/`。
- `foster/README.md`：“Runnable examples are maintained in the separate `OFoster_Sample` project” 保留，
  补一句 “本目录已并入 olib，原 OFoster 仓库停止维护”。
- **LICENSE**：OFoster 没有 LICENSE 文件。Foster 上游是 MIT 协议，新建 `foster/LICENSE`，写入 Foster 上游的 MIT 声明
  （版权方以上游仓库 `FosterFramework/Foster` 的 LICENSE 原文为准，从 `foster/README.md` 里给出的 baseline commit 获取；
  如果无法联网拿到原文，**停下来问用户**，不要编造版权方）。

Commit：`docs: foster 并入后的文档与 LICENSE`

## 验收

所有命令在 olib 根目录执行，**必须全部通过**：

```bash
# olib 现有单测（17 个包）
for p in core/entities core/handle/array core/handle/fixed core/handle/growing core/handle/virtual core/tween \
         engine/animation engine/app engine/asset engine/audio engine/dasset engine/messaging \
         engine/rendering engine/rendering3d engine/storage engine/ui engine/world; do
  odin test $p -collection:olib=. || echo "FAIL $p"
done

# 示例能编译
odin build examples/game_ui    -collection:olib=. -out:build/game_ui.exe
odin build examples/ui_gallery -collection:olib=. -out:build/ui_gallery.exe
odin build thirdparty/odin-imgui/examples/ofoster -collection:olib=. -out:build/imgui_example.exe

# foster 自带回归（按各自 README 的方式运行，桌面目标即可）
odin build foster/tests/port_regression     -collection:olib=. -out:build/port-regression.exe
odin build foster/tests/graphics_regression -collection:olib=. -out:build/graphics-regression.exe
odin build foster/tests/webtest             -collection:olib=. -out:build/webtest.exe
```

另外检查：

- `grep -rn "ofoster" --include=*.odin --include=*.bat --include=*.ps1 --include=*.sh --include=*.md .`
  剩下的结果只能是：历史说明（“原 OFoster 仓库”）、`thirdparty/odin-imgui/examples/ofoster` 这个目录名、以及 `.zcode/`。
- `git log --oneline -- foster/framework.odin | wc -l` 能看到 OFoster 时期的历史（大于 1）。
- 根目录 `build/` 下的产物没有被提交（`*.exe` 已经在 olib 的 gitignore 里；如有需要，给 `/build` 加一条忽略规则）。

如果某个测试在**合并前**就是失败的（可以用旧方式 `-collection:ofoster=../OFoster/src` 在 master 上复测），
在汇报里如实注明，不要为了让它通过去改代码。

## 禁止事项

- 不要 push，不要建 PR，不要动 GitHub 上的 OFoster 仓库（是否 archive 由用户决定）。
- 不要修改 `D:\MySpace\Github\OFoster` 和 `D:\MySpace\Github\OFoster_Sample` 的任何文件。
- 不要改 `foster/` 内部的任何逻辑、命名或格式（第 4、5 步明确列出的 import 和命令行除外）；不要对 `foster/` 跑 odinfmt。
- 不要使用 `git subtree add --squash`、不要 rebase 改写 subtree 引入的历史。

## 汇报内容

完成后汇报：各个 commit 的列表、验收命令的结果（哪些通过、哪些失败及原因）、
仍残留的 `ofoster` 引用、以及需要用户自己处理的事项：

- OFoster_Sample 的 `run.bat` 需要改成 `-collection:olib=..\olib`，并把 import 换成 `olib:foster`（或者并入 olib 的 `examples/`）；
- GitHub OFoster 仓库是否 archive，README 里要不要放一个指向 olib 的说明。
