# Plan：foster 作为唯一运行时，engine 改名 kit 作为扩展层

## 背景

olib 目前是三层：`core/`（纯 Odin）、`foster/`（Foster 的 Odin 移植，含 App 生命周期、窗口、输入、图形、基础类型）、
`engine/`（建在 foster 之上的模块）。问题在于 engine 有时**替代** foster、有时**扩展** foster，用户写游戏时
一会儿用 foster、一会儿用 engine，同一件事有两种写法：

- **退出程序两种写法**：`examples/game_ui/main.odin:62`、`:198` 用 `foster.Exit(g)`，`examples/game_ui/hud.odin:282`
  用 `app.game_app_exit(&game)`。根源是 `engine/app/game_app.odin` 的 `Game_App` 把 `foster.App` 的生命周期包了一半。
- **示例直接用 foster 的内部包**：`examples/game_ui/font.odin` 和 `examples/ui_gallery/font.odin` 都
  `import stbtt "olib:foster/internal/third_party"` 手工烘焙字体图集，两份代码几乎相同。
  而 foster 其实已有公开的 `Font` API（`foster/images.odin:1639` 起：`FontMake`、`FontLoadFile`、
  `FontGetScale`、`FontGetCharacter`、`FontRasterize`/`FontGetPixels`、`FontGetKerning`、`FontDispose`）。
- **`Game_App` 在 Web 平台上本身就是错的**：`foster.Run` 在 `ODIN_OS == .JS` 时调用
  `web_relocate_app`（`foster/web.odin:396`），只把 `App` 结构拷到堆上，之后回调收到的是堆副本的 `^App`。
  `Game_App` 靠 `cast(^Game_App)a` 取回外层结构，在 Web 上读到的是 `App` 之后的越界内存。

## 已定决策（执行时不要改）

采用"**foster 是唯一运行时，kit 只做扩展**"：

1. **foster**：App 生命周期、窗口、输入、图形、基础类型（`Color`、`Vec2`、`Rect`……）一律直接用 foster。
2. **kit**（由 `engine/` 改名）：只提供 foster 没有的能力，例如 UI、资源管线、相机/场景、3D 队列、动画、音频、CLI 控制台。
3. **硬规则**：
   - kit 的 API 直接接收、返回 foster 类型；**不给** foster 的类型或 proc 起别名，**不做**一对一封装；
   - kit **不封装** foster 的 App 生命周期（`init_app` / `Run` / `Exit` / `dispose_app`）；
   - `foster/` 以外的代码**不得** import `olib:foster/internal/...`。
4. 依赖方向：`kit → foster`、`kit → core`；`core` 不得依赖 `foster` 或 `kit`；`foster` 不依赖 olib 其他任何包。
5. **本次不修改 `foster/`**。如果确实需要改 foster，**停下来问用户**；获得同意后按 `foster/docs/LOCAL_CHANGES.md` 的规则登记。

## 执行步骤

基于 master（HEAD `8f1dc59`，工作区干净），新建分支 `kit-layering`。每一步一个 commit，每步结束都要能编译、测试通过。

### 0. 先留一份基线截图（第 3 步验收要用）

在改动之前，用当前代码生成两个示例的验收截图，保存到 `build/baseline/`（`build/` 已被 gitignore）：

```bash
odin build examples/game_ui    -collection:olib=. -out:build/game_ui.exe
odin build examples/ui_gallery -collection:olib=. -out:build/ui_gallery.exe
```

两个示例都支持 `shot` 参数自动输出 png（文件名逻辑见 `examples/game_ui/main.odin:271` 和
`examples/ui_gallery/main.odin:237`）。对下面每种参数组合各跑一次，把生成的 png 移到 `build/baseline/`：

- game_ui：`shot`、`shot modal`、`shot hud`、`shot scaled`、`shot scroll`
- ui_gallery：`shot`、`shot modal`、`shot scaled`、`shot msdf`、`shot scroll`

如果当前环境开不了窗口、无法截图，在汇报里说明，第 3 步改为人工目测验收，**不要跳过不提**。

### 1. `engine/` 改名为 `kit/`

- `git mv engine kit`。各包的 `package` 名不变（仍是 `package ui`、`package app` 等）。
- 把 `"olib:engine/` 全部替换为 `"olib:kit/`，范围是 `kit/`、`examples/`。
- 文档和注释里指向目录的 `engine/xxx` 也改成 `kit/xxx`，范围是 `README.md`、`docs/CODE_STYLE.md`、
  `docs/ROADMAP.md`、`kit/**/README.md`，以及 `kit/` 下的源码注释。
  例如 `odin test engine/asset` → `odin test kit/asset`，`odin fmt engine` → `odin fmt kit`。
- 描述这一层的措辞同步修改：`README.md` 和 `docs/CODE_STYLE.md` 里的“引擎层”改为“扩展层（kit）”。
- **不要碰**：`thirdparty/`（odin-imgui 里有无关的 “engine” 字样）、`foster/`、`docs/plans/`（历史计划）、`.zcode/`、`build/`。

验收：`grep -rn "olib:engine" --include=*.odin .` 无结果；`kit/`、`examples/`、`README.md`、`docs/CODE_STYLE.md`
里不再出现指向旧目录的 `engine/` 路径。

Commit：`kit: engine/ 改名为 kit/（扩展层）`

### 2. 去掉 `Game_App`，只保留 CLI 控制台

**kit/app 的改动**

- 删除 `kit/app/game_app.odin`。它文件头里的包说明（第 1 到 12 行）挪到 `kit/app/cli_console.odin` 顶部，删掉其中关于 `Game_App` 的内容。
- `kit/app/cli_console.odin` 里有引用 `Game_App` / `enable_cli` 的注释（如第 9 行），一并改掉。
- 在 `cli_console.odin` 新增两个函数，取代 `game_app_enable_cli` 的作用：

  ```odin
  // 一步开启控制台：init + 注册 quit（传了 app 时调用 foster.Exit）+ 启动读取线程。
  // 无 stdin 等原因启动失败时释放资源，返回 false；之后 cli_update / cli_dispose 依然可以安全调用。
  cli_open :: proc(console: ^Cli_Console, quit_app: ^foster.App = nil) -> bool

  // 注册 quit 命令：调用 foster.Exit(app)。cli_open 内部使用，也可以单独调用。
  cli_register_quit :: proc(console: ^Cli_Console, app: ^foster.App)
  ```

  `cli_open` 的实现逻辑照搬现在 `game_app_enable_cli`（`engine/app/game_app.odin:86` 起）。
- **确认未开启的控制台也能安全调用 `cli_update` 和 `cli_dispose`**：例如零值的 `Cli_Console`、
  或者 `cli_open` 失败之后。如果现在做不到，加上判断让它们不做任何事。这样用户在 update 和 shutdown
  里无条件调用即可，不需要自己维护 `has_console` 标志。

**测试**（`kit/app/app_test.odin`）

- 删除 `Game_App` 相关的测试（第 74 行 “Game_App —— 桥接与字段提升” 那一节）。
- 新增测试：
  - 零值 `foster.App`，手动设 `Running = true`；`cli_init` 之后 `cli_register_quit(&console, &a)`；
    用 `cli_dispatch_line(&console, "quit")` 加 `cli_update` 执行；断言 `a.Exiting == true`。
    （`foster.exit` 只设置 `Exiting`，不需要窗口，见 `foster/framework.odin:2098`。）
  - 零值 `Cli_Console` 直接调用 `cli_update` 和 `cli_dispose` 不崩溃。

**示例的改动**（`examples/game_ui`、`examples/ui_gallery`）

- `game: app.Game_App` → `game: foster.App`。
- `main` 里改为 foster 原生写法（参考 `foster/tests/webtest/main.odin:44`）：

  ```odin
  foster.InitApp(&game, foster.DefaultAppConfig("...", W, H))
  defer foster.Dispose(&game)
  game.StartupProc = startup
  game.UpdateProc = update
  game.RenderProc = render
  game.ShutdownProc = shutdown
  foster.Run(&game)
  ```

- `hud.odin:282` 的 `app.game_app_exit(&game)` 改为 `foster.Exit(&game)`。改完后示例里退出程序只有 `foster.Exit` 一种写法。
- `examples/game_ui` 增加 CLI 用法演示，用 `cli` 参数开启：

  ```odin
  console: app.Cli_Console
  // startup 里
  if app.has_arg(os.args, "cli") { app.cli_open(&console, g) }
  // update 开头
  app.cli_update(&console)
  // shutdown 里
  app.cli_dispose(&console)
  ```

- `app.has_arg` 的用法不变。

验收：`grep -rn "Game_App\|game_app_" --include=*.odin --include=*.md .` 只能在 `docs/plans/` 里出现。

Commit：`kit/app: 去掉 Game_App，直接使用 foster.App；CLI 改为 cli_open`

### 3. 字体烘焙移入 kit/ui，示例不再 import foster/internal

- 在 `kit/ui` 新增一个文件，例如 `ui_font_bake.odin`（文件内分区按 `docs/CODE_STYLE.md`），提供：

  ```odin
  // 把 foster.Font 按指定字号和字符集烘焙成位图图集，产出 ui 可注册的 MsdfFont 和对应纹理。
  // 只用 foster 的公开 Font API，不 import foster/internal。
  ui_font_bake :: proc(
  	device: ^foster.GraphicsDevice,
  	font: ^foster.Font,
  	size: f32,
  	codepoints: []int = nil, // nil 表示 ASCII 32..126
  	label := "ui font",
  ) -> (msdf: foster.MsdfFont, texture: foster.Texture, ok: bool)
  ```

  行为必须和现在示例里的 `bake_font` 完全一致：
  - shelf 打包，字形之间留 2px 间距，图集从 1024x512 开始（字符集更大时可以扩容，ASCII 48px 时必须仍是 1024x512）；
  - 像素是**预乘 alpha**：`Color{a, a, a, a}`；
  - 不可见字形（空格等）只记录 advance，`SourceRect` 为 0；
  - 字距表只记录非零项；
  - `Size`、`Ascent`、`Descent`、`LineHeight` 的计算方式与现在相同；
  - `msdf.Image.Pixels` 的所有权与现在一致（交给 `MsdfFont`，由 `foster.MsdfFontDispose` 释放），
    纹理由调用方 `foster.TextureDispose`。在函数注释里写清楚。
- 改用 foster 公开的 `Font` API（`FontGetScale`、`FontGetGlyphIndex`、`FontGetCharacter`、`FontRasterize`
  或 `FontGetPixels`、`FontGetKerning`）。先读 `foster/images.odin:1639-1790`，确认 `FontCharacter`
  的字段与现在用的 `StbFontCharacter` 返回值一一对应，包括 advance、offset、宽高、visible 的语义和取整方式。
  **如果有对不上的地方，在汇报里写明差异和你的处理方式。**
- 两个示例的 `font.odin` 简化为：按候选路径列表（用户传入的 `font` 参数，加上 Windows 系统字体）尝试
  `foster.FontLoadFile` 或 `FontMake`；然后调用 `ui.ui_font_bake`，再 `ui.ui_register_font`。
  候选字体路径属于示例逻辑，留在示例里。用完 `foster.Font` 后调用 `FontDispose`。
- `examples/ui_gallery/font.odin` 里的 `make_distance_probe` 是着色器探针，留在示例中不动。
- `kit/ui` 加单元测试：用仓库里已有的 TTF（`foster/tests/port_regression/fonts/Abel-Regular.ttf`）
  烘焙 ASCII，断言字形数是 95，`'A'` 的 `SourceRect` 非空，空格的 `SourceRect` 为 0 但 `Advance > 0`。
  如果测试需要 GraphicsDevice 而无头环境下拿不到，就把"生成 Image 和字形表"拆成一个不需要 GPU 的内部函数来测，
  上传纹理放在外层函数。
- `kit/ui/README.md` 补充 `ui_font_bake` 的用法。

验收：
- `grep -rn "foster/internal" --include=*.odin . | grep -v "^./foster/"` 无结果；
- 用第 0 步同样的参数重新截图，与 `build/baseline/` 逐像素比较（写个小脚本即可，放在 scratch 目录，不提交）。
  **必须完全一致**；如果不一致，报告差异的位置和原因，不要为了通过修改基线。

Commit：`kit/ui: ui_font_bake，示例改用 foster 公开 Font API`

### 4. 把分层规则写进文档

- `docs/CODE_STYLE.md`：
  - 仓库布局图改为 `core/`、`foster/`、`kit/`、`thirdparty/`，并标注各自职责；
  - 新增一节“foster 与 kit 的边界”，写入上面“已定决策”第 1 到 4 条（硬规则原文照搬）；
  - 依赖方向一节同步修改。
- `README.md`：
  - 布局图更新；
  - “使用”一节写明“基础能力（App、窗口、输入、图形、基础类型）直接用 `olib:foster`，扩展能力用 `olib:kit/*`”，
    并给一个最小的启动示例（直接用 `foster.App`，可选接入 `app.cli_open`）。
- `docs/ROADMAP.md`：
  - 第 36 行 “GameApp 启动模板” 这一行注明：不再提供启动模板，直接使用 `foster.App`；保留 `CliConsole`（`kit/app`）；
  - 其余提到 `engine/` 的地方在第 1 步已经改过，这里只检查措辞。

Commit：`docs: foster / kit 分层规则`

## 验收（全部完成后在 olib 根目录执行）

```bash
# 单测
for p in core/dasset core/entities core/handle/array core/handle/fixed core/handle/growing core/handle/virtual \
         core/messaging core/tween \
         kit/animation kit/app kit/asset kit/audio kit/rendering kit/rendering3d kit/storage kit/ui kit/world; do
  odin test $p -collection:olib=. || echo "FAIL $p"
done

# 编译
odin check foster -collection:olib=. -no-entry-point
odin build examples/game_ui    -collection:olib=. -out:build/game_ui.exe
odin build examples/ui_gallery -collection:olib=. -out:build/ui_gallery.exe
odin build thirdparty/odin-imgui/examples/ofoster -collection:olib=. -out:build/imgui_example.exe

# foster 没有被修改，本地修改清单检查仍应通过
powershell -File foster/tests/check_local_changes.ps1
git diff master --stat -- foster/   # 必须为空
```

另外：
- 第 3 步的截图比对必须完全一致；
- 手动运行 `build/game_ui.exe cli`，在终端输入 `help`、`quit`，确认命令列表能列出、程序能正常退出；
- 第 1、2、3 步各自的 grep 验收再跑一遍。

如果某项检查在 master 上就已经失败（切回 master 复测确认），在汇报里注明，不要为了让它通过去改无关代码。

## 禁止事项

- 不要修改 `foster/` 和 `thirdparty/`（第 1 步只替换 import 路径，`thirdparty/odin-imgui/examples/ofoster` 也不涉及 engine，不需要改）。
- kit 里不要给 foster 的类型或 proc 起别名，也不要新增对 foster 功能的一对一封装。
- 不要 push，不要建 PR，不要合并回 master。
- 不要用 odinfmt 格式化整个目录，只格式化你改动过的文件。

## 汇报内容

- commit 列表；
- 验收命令的结果，逐项列出通过或失败；
- 截图比对结果；
- 第 3 步 `FontCharacter` 和 stb 返回值之间有没有语义差异、你是怎么处理的；
- 任何偏离本计划的地方及原因。
