# Shader Lab 改用 ImGui，ImGui 使用 olib 字体与图标

> **状态：已完成（2026-10-22）** · 提交 `196665c`..`fd5fe19`；olib_sample `efcf66c`
> 偏离：ImGui 1.92 的 sdlgpu3 直接以 SDL_GPUTexture 作 ImTextureID，Texture 不自建采样器与绑定；NewFrame 增加 force_focus，供检查在后台窗口注入输入；features 的分隔条/收起/紧凑侧栏步骤改为预览区尺寸检查，targets 用注入滚轮把纹理卡片滚进可见范围；检查只跑了 d3d12 与默认驱动，未跑 vulkan；模板 Live Editor 随后端默认换成 olib 字体与样式；olib_sample 的 tools/msdf_charset 保留，只用于复现现有字符集。

## 背景

编辑器 UI 已默认用 odin-imgui（见 archive/editor-imgui.md），但 Shader Lab 仍用 kit/ui 手写侧栏、
滚动记忆、分隔条、紧凑布局和调色板。ImGui 自带的 ProggyClean 字体与 kit/ui 的 Noto Sans CJK SC 不一致，
也没有中文；ImGui 侧还没有接 olib 内置图标。

## 已定决策

1. Shader Lab 画进宿主的 ImGui 帧：宿主持有上下文、字体、输入和 Dock；工具只提交窗口
   （“Shader Lab”控制窗口与“预览”窗口，可停靠），预览用 imgui.Image 显示。去掉 region + Input 接口、
   UI 比例、侧栏宽度/分隔条/紧凑覆盖、滚动记忆与自绘调色板；Config 不再要求 MSDF 字体。
2. 新接口：`init / update / draw / cancel / dispose`。`draw` 在宿主 BeginRender 与 EndRender 之间调用，
   内部完成候选包切换、按预览窗口尺寸渲染 Pass 和提交控件；上一帧引用的旧纹理与目标在下一次 `draw`
   开始时释放。文件拖放由 `draw(s, dropped_files, drop_position)` 传入，命中纹理卡片才生效。
3. 调色板改为 ImGui ColorPicker4 弹窗，保留“打开记原值、实时预览、应用/取消、Escape/失焦取消、预设色”的语义。
4. 字体：olib 新增 `assets/fonts/` 的 Noto Sans CJK SC 子集（ASCII、Latin-1、GB2312 汉字与符号，约 3 MB，OFL），
   后端 Init 默认加载为 ImGui 主字体，所有 ImGui 使用者统一；来源哈希、子集脚本与命令写进 README。
5. 图标：r2d 增加内置图标的 CPU 解码（straight alpha，不上传）；后端增加按名字挑选图标、面积平均缩放到
   固定格子并上传的小图标表，以及 Icon / IconButton。图标保持 straight alpha，与 sdlgpu3 管线混合方式一致。
6. 后端增加 foster 纹理到 ImTextureRef 的转换（自建线性采样器，每帧复用绑定对象）、EndRender 可渲染到
   宿主 foster Target（Init 可指定颜色格式），以及与 kit/ui 主题一致的默认样式。
7. 自动检查保留注入输入：Shader Lab 记录关键控件矩形（ImGui 坐标即窗口逻辑坐标），检查按 ID 取矩形点击；
   删除 Clay 布局专有断言（固定锚点坐标、滚动位置记忆、分隔条、收起/紧凑侧栏、UI 比例）。
   示例宿主渲染到离屏目标再贴到窗口，截图读取该目标，包含 UI。
8. `embedded` 参数不再有意义，示例与检查不再使用。

## 执行步骤

1. olib：字体资产与子集脚本、r2d 内置图标解码、ImGui 后端（默认字体与样式、纹理转换、图标表、离屏渲染）。
   提交 `imgui_ofoster: olib 字体、图标与离屏渲染`。
2. olib：Shader Lab 改写为 ImGui，README 宿主接入与行为说明同步。olib_sample 同步改宿主、文件桥、检查与文档。
   两个仓库同时改完、`odin run tools/check` 通过后分别提交
   （olib `shader_lab: 改用 ImGui 窗口`，olib_sample `samples: Shader Lab 改用 ImGui`）。
3. olib 文档：new-project、tools/fonts、kit/ui、ROADMAP 等提到 Shader Lab 或 ImGui 字体的位置。
   提交 `docs: Shader Lab 与 ImGui 字体图标`。
4. 按 docs/plans/README.md 归档本计划。

## 验收

- olib `odin run tools/check` 全部通过。
- olib_sample 运行 `run.bat shader_lab smoke d3d12`、`features d3d12`、`multipass d3d12`、`hierarchy d3d12`、
  `targets d3d12`、`colors d3d12`、`shot` 全部 PASS（检查期间屏蔽真实输入，不对桌面发送输入）。
- 截图检查中文字体、图标与预览显示；模板 Live Editor 使用新字体。截图在各自项目的 library/screenshots。

## 禁止事项

- 不改 `foster/`；不改 archive 历史正文。
- 不提交两个仓库里与本计划无关的已有改动（olib 的 core/hotreload、shader_lab/bank.odin 的
  heap allocator 改动；olib_sample 的 stylized3d）。bank.odin 若必须修改，只改界面相关部分并先告知。
- 不用系统字体或运行时下载；不对用户桌面发送合成输入。

## 汇报内容

- 每步 commit、check 与各检查模式结果、截图路径、删掉的断言清单、未实现的限制。
