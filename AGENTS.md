# olib 开发约定（给 AI 代理）

本文件由 Codex / GPT 等代理自动读取；`CLAUDE.md` 引用本文件，Claude Code 读到的是同一份。只写必须遵守的规则，细节见链接。

## 仓库

- 结构与依赖方向：`core/`（纯 Odin）→ `foster/`（Foster 移植，唯一运行时）→ `kit/`（扩展），见 [README](README.md) 与 [CODE_STYLE](docs/CODE_STYLE.md)。
- kit 不封装、不别名 foster；`foster/` 以外不得 import `olib:foster/internal/...`。
- 修改 `foster/` 必须登记到 [foster/docs/LOCAL_CHANGES.md](foster/docs/LOCAL_CHANGES.md)，并在修改处写 `// [olib L-xxx]` 标记。
- 示例在同级仓库 OFoster_Sample，库仓库只放库代码与测试。

## 提交前

- 在仓库根目录运行 `powershell -File check.ps1`，全部通过才提交（包含全部包的 `-vet`、单元测试、foster 回归程序与示例编译）。
- 结果如实汇报：失败就贴输出，跳过的步骤要写明。

## 计划（docs/plans）

- 按计划执行任务时，**计划完成并验收通过后，立即把计划归档**：`git mv` 到 `docs/plans/archive/`，在标题下写状态块（完成日期、commit 范围、偏离），单独提交 `docs: 归档计划 <name>`。完整规则见 [docs/plans/README.md](docs/plans/README.md)。
- 写新计划时，最后一步固定为“按 docs/plans/README.md 归档本计划”。
- 不改 `docs/plans/archive/` 里历史计划的正文。
