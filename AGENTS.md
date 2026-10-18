# olib 开发约定（给 AI 代理）

本文件由 Codex / GPT 等代理自动读取；`CLAUDE.md` 引用本文件，Claude Code 读到的是同一份。只写必须遵守的规则，细节见链接。

## 仓库

- 结构与依赖方向：`core/`（纯 Odin）→ `foster/`（Foster 移植，唯一运行时）→ `kit/`（扩展），见 [README](README.md) 与 [CODE_STYLE](docs/CODE_STYLE.md)。
- kit 不封装、不别名 foster；`foster/` 以外不得 import `olib:foster/internal/...`。
- 修改 `foster/` 必须登记到 [foster/docs/LOCAL_CHANGES.md](foster/docs/LOCAL_CHANGES.md)，并在修改处写 `// [olib L-xxx]` 标记。
- 示例在同级仓库 olib_sample，库仓库只放库代码与测试。
- 新游戏默认 core（游戏）/core_editor（可热替换编辑器）/editor（常驻开发入口）/game（发布入口）四目录；core_editor 与 core 编成一个 DLL，共享服务放 core/services.odin，不另建 host 或 editor/play，细节与模板见 [新项目约定](prompts/new-project.md)。
- 新增或修改编辑器、开发面板和交互工具前，阅读并遵循 [编辑工具开发约定](prompts/editor-guidelines.md)；它是项目接入规则，不要求预建编辑器框架。
- UI/字体或游戏渲染改动须阅读 [UI 像素与采样约定](kit/ui/README.md#最终像素采样与清晰度验收)。UI 在最终像素尺寸绘制，不能随低分辨率场景一起放大；截图取最终输出。3D 分辨率与抗锯齿、字体小字号质量分别验收，不能以加粗字体代替采样排查。

## 生成文件

- 遵循 [生成文件与目录纪律](prompts/new-project.md#生成文件与目录纪律)，同样适用于本库：截图放 library/screenshots，图像候选/参考/提示词放 library/imagegen，临时报告/脚本/诊断副本放 library/tmp，按需创建；不在根目录新增 output、artifacts 或日期/任务目录。
- 仅在用户要求或画面/输入变化确需验收时截图；目录、文档和配置修改不额外截图。同场景复用文件名，发布目录验收也输出到所属项目根 library。
- build 保留构建、测试、发布产物及已有工具构建日志；正式资产、字体、shaders/Compiled 不按临时文件清理。library 不整体删除或发布，派生资源仅处理各工具拥有的子目录。
- 测试私有临时目录、编译器隔离目录和同目录原子保存文件遵循各自生命周期，详见上述规则；不为归档破坏隔离或原子替换。

## 测试组织

- 第一方单元测试集中放 `tests/<被测包路径>/`，例如 `tests/kit/material/`；core/kit 不放测试文件或测试专用资产。
- 通过 `odin run tools/check` 执行；单包使用 `-- -only:kit/material`。检查工具在独占临时目录组装被测包，保留私有函数测试能力；详见 [tests/README](tests/README.md)。
- Foster 移植回归和第三方配套测试保留各自已有的独立 tests 目录，不混入业务源码。

## 提交前

- 运行 `odin run tools/check`（任意目录均可，跨平台），全部通过才提交（包含全部包的 `-vet`、单元测试、foster 回归程序、LOCAL_CHANGES 校验与示例编译）。
- 结果如实汇报：失败就贴输出，跳过的步骤要写明。

## 计划（docs/plans）

- 按计划执行任务时，**计划完成并验收通过后，立即把计划归档**：`git mv` 到 `docs/plans/archive/`，在标题下写状态块（完成日期、commit 范围、偏离），单独提交 `docs: 归档计划 <name>`。完整规则见 [docs/plans/README.md](docs/plans/README.md)。
- 写新计划时，最后一步固定为“按 docs/plans/README.md 归档本计划”。
- 不改 `docs/plans/archive/` 里历史计划的正文。
