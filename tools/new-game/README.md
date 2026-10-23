# 新游戏模板

在 olib 根目录运行：

```powershell
odin run tools/new-game -- ../MyGame MyGame
cd ../MyGame
.\play.bat
```

两个参数分别是**尚不存在的目标目录**与**英文项目名**。支持带空格的目标目录（加引号），项目名只接受字母开头的字母/数字/下划线。拒绝覆盖现有目录、Windows 保留名称和在 olib 内创建游戏；不自动初始化 Git、不安装依赖。

生成器把 template 中 `.in` 文件展开为普通文件，其他资产原样复制。游戏源码留在独立项目；olib 内的模板文件只是创建工具的输入，不会作为库包或游戏示例编译。生成后无须安装或运行生成器，olib_sample 也不参与构建。

## 精简布局

src 下只有四个子目录，平时主要改 core 和 core_editor：

```text
src/
├─ core/              游戏：状态、规则、UI、实例和快照
│  └─ services.odin   共享服务协议、资源函数与跨平台 storage
├─ core_editor/       编辑器：会话、工具 UI 与组合快照
│  ├─ editor.odin     面板实现、编辑命令与输入归属
│  └─ module.odin     DLL 接入，组合 core 与编辑器实现
├─ editor/            薄常驻开发入口（package main）
│  └─ main.odin       窗口、资源、监听、DLL 切换与失败提示
└─ game/              Windows/Web 薄发布入口（package main）
```

- 窗口与 UI 跟随系统显示缩放：入口打开 foster 的 `LogicalWindowSize`，游戏 UI 按 `core.ui_scale`（`foster.ContentScale` × 测试参数），编辑器 ImGui 每帧跟随。
- `play.bat` 启动开发版；编辑面板用 Dear ImGui，默认停靠在右侧，游戏画在中央 Dock 区域，Editor 一栏可调界面字号（按显示器给建议值，存为用户目录的 editor-settings.json）；F1 收起/打开面板，可边玩边改位置、分数及暂停；F3 打开悬浮性能面板；面板按钮使用 olib 内置图标。玩家 UI 仍用 kit/ui。
- 开发版窗口旁的终端是开发控制台（`kit/app` 的 `Cli_Console`），输入 `help` 查看命令，自带 status/retry/perf/quit；只在 editor 入口接入，发布版不引用、也不弹终端。
- 修改 core 的游戏代码或 core_editor 的工具 UI 后保存，自动编译一个 DLL，保留游戏进度、面板开关、Dock 布局及未处理命令。UI、ImGui 上下文和 GPU 对象重建，按住输入先等待松开，避免误触。
- `publish.bat` 发布 Windows，`publish_web.bat` 发布 Web；两者编译 src/game、复用 core，均排除 editor、core_editor 和加载器。Web 无热重载，刷新新开一局。
- 开发入口自带非阻塞失败摘要：说明旧版仍运行或首次未加载，完整错误写入 build/hotreload-last-error.txt；只有实际加载成功才清除提示。编译中保留旧提示，F5 可重试。
- 默认通过 kit/storage 初始化跨平台存储，共享资源函数放 core/services.odin，资源与容器由入口持有，业务直接用 Foster API 读写；存档格式和保存时机由游戏定义。
- editor 入口、core/services.odin 的服务协议/资源函数、core/args_native.odin、字体、olib 和工具链修改需重启；服务 ABI 变化升级 core.SERVICES_VERSION。

启动时编译 src/editor 为常驻 EXE，运行时编译 src/core_editor 及它导入的 core 为一个 DLL；两个入口都不承载玩法。没有独立 host 包，也不生成 editor/play、src/tools/editor 或根目录宿主。游戏和编辑会话归 DLL 所有；常驻入口只借用 core 的资源服务代码，不创建静态游戏实例，不保存 DLL 内业务指针或回调。

类型、状态、规则、UI 先在 core 内按文件组织，不预建 def/data/logic/view/session/platform。需要独立复用或依赖边界时，在 src/core 内拆子包；tools/check 自动识别子包与 vet 包名，改变依赖边界时同步规则；不恢复顶层 def/data/logic/view。模板自带离线中英文字体和许可、OLS、AGENTS、状态单元测试与构建检查。编辑器只修改当前运行实例，不包含关卡文档、磁盘保存或撤销系统。

默认 Windows 开发，支持 Windows 和 Web 静态发布，其他桌面平台未验证。创建器与无窗口检查使用 Odin；Web 无需 Emscripten，资源嵌入 WASM，脚本复制本地 Odin/Foster JS 运行时。`publish_web.bat serve` 使用 Python 在 http://127.0.0.1:8138/ 预览，Ctrl+C 停止。库路径在生成时写入，可用 `OLIB` 覆盖（同步更新 OLS）。

生成文件约定随模板的 AGENTS.md、README 和 .gitignore 一起交付：临时截图、图像生成素材和
诊断产物分别归入 `library/screenshots`、`library/imagegen`、`library/tmp`，仅在需要时创建。
不按任务在根目录创建输出文件夹，也不为文档或配置修改生成截图；正式资产和预编译 Shader 保留。
规则来源见 [新项目生成文件约定](../../prompts/new-project.md#生成文件与目录纪律)。

## 修改和验证

普通玩法开发改 `core/world.odin`、`core/rules.odin`、`core/ui.odin`；保存后热重载。编辑器面板在 `core_editor/editor.odin`，改动后同样热重载。新增状态或改变格式时维护 core/core.odin 和 core_editor/module.odin 的快照默认值/版本，具体规则见 [热重载文档](../../core/hotreload/README.md)。

在生成项目运行：

```powershell
odin run tools/check
.\publish.bat
.\publish_web.bat
```

check 包括单元测试发现、依赖检查和桌面入口和 Web WASM 编译，并读取编译器源码依赖清单确认桌面/Web 排除 editor 和 core_editor、常驻入口不静态带入 core_editor，并检查 WASM 无 SDL 函数导入。运行 play.bat 可直接体验修改游戏规则、游戏 UI 和编辑器 UI 后的热重载；模板不生成自动点击、改源码或截图的测试模式。

模板随库维护，项目生成后归项目维护，不提供覆盖式更新。改模板后运行 olib 的 `odin run tools/check`，其中 new-game 回归会在带空格的临时目录生成全新项目，验证覆盖拒绝及完整无窗口检查。涉及 UI 或宿主时可直接运行新项目检查交互。
