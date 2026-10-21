# 编辑器 UI 改用 Dear ImGui

## 背景

新游戏模板的 core_editor 面板用 kit/ui（Clay）实现。kit/ui 面向玩家 UI，没有折叠/树、文本输入、
下拉框、拖放和 Docking；shader_lab 为此手写了取色器、侧栏折叠和滚动记忆。编辑器和开发工具需要的
控件 Dear ImGui 都已自带，仓库里也已有 `thirdparty/odin-imgui`（1.92.8 docking 分支）和
`imgui_impl_ofoster` 后端，示例可以正常编译运行。

## 已定决策

1. 分工：玩家 UI 继续用 kit/ui（Clay）；编辑器、开发面板和调试工具默认用 odin-imgui。
   kit/ui 以后只补玩家 UI 需要的能力，不为编辑器补树、Dock 之类控件。
2. ImGui 上下文属于 core_editor DLL：每次 load 创建上下文与后端，unload 前 Shutdown；
   不让常驻 EXE 持有上下文跨 DLL 共享。宿主的失败提示与 F3 性能面板继续用 kit/ui。
3. 布局（ImGui ini 文本）随编辑器快照跨热重载保留；`io.IniFilename = nil`，不在工作目录写
   imgui.ini。进程重启后回到默认布局，本次不做磁盘持久化。
4. 模板面板放进 Dock：主视口铺透明 DockSpace（PassthruCentralNode + NoDockingOverCentralNode），
   首次默认把面板停靠在右侧；游戏绘制到中央节点的最终像素区域，鼠标按该区域偏移换算。
5. 输入：鼠标归属沿用“按下时决定、保持到松开”，判断依据从面板矩形改为 `WantCaptureMouse`；
   重载、F1 切换或离焦后的按住输入用 `ConfigFlags.NoMouse` 屏蔽到松开。不开 ImGui 键盘导航，
   避免与游戏键位重复消费；悬停面板或正在文本输入时屏蔽游戏键盘。
6. 后端只补本次用到的分段渲染接口（BeginRender/EndRender），调用方可直接用自己的状态提交控件。
   foster 贴图显示、中文 IME 候选框位置、CJK 字体等暂不实现，写进文档限制。
7. 仓库只带 Windows x64 预编译库；其他桌面平台需用 build.py 自行编译。文档改正“纯 Odin odin-imgui”。
8. shader_lab 本次不迁移。

## 执行步骤

1. `thirdparty/odin-imgui/imgui_impl_ofoster`：增加 BeginRender/EndRender，Render 改为基于它们；
   README 表格补充限制说明。提交 `imgui_ofoster: 分段渲染接口`。
2. 模板 core_editor 改用 ImGui：editor.odin、module.odin、两个测试；同步模板 README、AGENTS 与
   tools/new-game/README。提交 `new-game: 编辑面板改用 ImGui Dock`。
3. 文档约定：prompts/new-project.md、prompts/editor-guidelines.md、prompts/dod-guidelines.md（如需）、
   kit/ui/README.md、docs/ROADMAP.md、README.md、docs/CODE_STYLE.md。core/hotreload/README.md
   有他人未提交的改动，本次不动。
   提交 `docs: 编辑器 UI 默认使用 ImGui`。
4. 按 docs/plans/README.md 归档本计划。

## 验收

- `odin run tools/check` 全部通过（含 new_game 模板端到端检查与 imgui 示例编译）。
- 在临时目录生成项目并运行 play.bat 一次：面板默认停靠右侧，按钮生效；拖动分隔条后游戏区域跟随；
  修改 core_editor 保存触发热重载后布局保留、按住鼠标不误触；F1 隐藏/显示正常。截图存
  library/screenshots。
- 记录热重载 DLL 编译耗时的变化。

## 禁止事项

- 不改 `foster/`；不改 `docs/plans/archive/` 历史正文。
- 不迁移 shader_lab，不新增 kit/editor 等预建框架。
- 不提交工作区里与本计划无关的已有改动（core/hotreload、shader_lab/bank.odin）。

## 汇报内容

- 每步 commit、check 结果、手动验收结论与截图路径、热重载耗时变化、未实现的后端限制。
