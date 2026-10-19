# 测试入口

第一方单元测试集中在这里，按被测包路径对应：

```text
core/…                  库的生产代码（不含测试）
kit/rendering/2d/        库的生产代码（不含测试）
tests/core/…             core 的单元测试
tests/kit/rendering/2d/  rendering2d 的单元测试
tests/tools/check/       检查工具自身的测试
tests/new_game/          新项目生成与构建回归
```

```sh
odin run tools/check                         # 完整检查
odin run tools/check -- -only:test           # 测试及名称匹配的回归项
odin run tools/check -- -only:kit/rendering/material   # 只检查/测试指定包
```

`tests/core`、`tests/kit`、`tests/tools` 中的文件保留 `#+test` 和被测包的
`package` 名称。检查工具会自动发现它们，在独占系统临时目录中组合生产源码与测试，
执行 `odin test -vet`，然后清理目录。包内私有函数仍可测试，不为测试扩大公开 API。
生产源码不写入测试文件；检查入口会拒绝 core/kit 中遗漏的 `@(test)`。

测试引用的专用资产放测试目录，例如 `tests/kit/ui/testdata`。`#load` 的相对路径
按测试文件自身位置填写。隔离编译保持原文件的 `#directory`、字面量 `#load` 和相对
import 路径含义，只调整路径 token，不修改代码逻辑、注释或其他字符串内容。
失败诊断中的源码位置指向临时副本；同名文件对应原生产包或这里的测试文件。

测试可执行文件保留在 `build/check/`。并行运行各自拥有独立源码临时目录；
同一输出目录的构建仍应串行运行。不要直接对 `tests/kit/<包>` 执行 `odin test`，
因为该目录仅存测试，生产源码由检查工具组合。

Foster 的移植回归已集中在 `foster/tests/`，第三方一致性测试保留在其各自
`thirdparty/.../tests/` 下；统一由同一检查入口发现或调用，不移动上游配套目录。
GPU 回归当前由完整检查编译，实际画面与交互按受影响功能人工验收，不新增冒烟入口。
