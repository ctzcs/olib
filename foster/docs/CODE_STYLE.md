# OFoster 源码布局与排版规范

本规范适用于 olib 内 Foster 移植（原 OFoster）的新增、移植和维护代码。保留一个模块一个主题文件，
通过文件内的导航和分区注释表达 Foster 的目录、类型与子功能层级。

## 文件组织

- 公共 API 保持在 `foster/` 的 `foster` 包中，按主题放入
  `graphics.odin`、`input.odin`、`spatial.odin` 等现有文件。
- 同一类型的声明、构造、查询、修改和释放函数尽量集中在对应分区。
  新增函数放入已有分区；出现新的功能组时，补充分区标题和顶部导航。
- 平台适配继续使用带 `#+build` 的文件；内部绑定和 Web 桥继续放在
  `foster/internal/`。文件对应关系见 [移植映射](PORTING_MAP.md)。

## 文件内层级

文件顶部保留构建条件、包声明、文件说明和 imports。导航放在 imports 后、
实现前，按文件中大分区的出现顺序列出；无 imports 的文件放在包声明和文件
说明之后。导航用于定位大块，具体类型由块内的第二级标题标识。

分区使用以下约定：

| 层级 | 分隔线 | 标题内容 | 示例 |
| --- | --- | --- | --- |
| 大分区 | `// ==============================================================================` | 模块或主要功能组的路径 | `Input / Bindings — 输入绑定` |
| 子分区 | `// ------------------------------------------------------------------------------` | 类型或子功能的完整路径 | `Input / Bindings / KeyboardKeyBinding` |

路径各级使用 ` / ` 分隔；需要说明用途时，在路径后用 ` — ` 添加简短说明。
同一类型在导航、标题和移植映射中使用一致名称。沿用源码中的路径标签，例如
`Graphics / Batcher`、`Spatial / Rect` 和 `Utility / Rng`；平台及内部实现
分别使用 `Platform / ...`、`Internal / ...`。

标题前后留一个空行；相邻的大分区和子分区标题之间也留一个空行。
说明类型用途、资源所有权或平台差异的注释放在对应标题之后、声明之前。
无需给每个函数都添加分隔线：一个类型内按生命周期或子功能分组即可。

下面是输入模块的局部示例；其他模块遵循同样的结构：

```odin
// 文件内导航（按 Foster 目录 / 类型分级）
//   Input / Bindings — 输入绑定
//   Input / Sets — 绑定组合

// ==============================================================================
// Input / Bindings — 输入绑定
// ==============================================================================

// ------------------------------------------------------------------------------
// Input / Bindings / KeyboardKeyBinding
// ------------------------------------------------------------------------------

KeyboardKeyBinding :: struct {
	Key: Keys,
}

KeyboardKeyBindingMake :: proc(key: Keys) -> KeyboardKeyBinding {
	return KeyboardKeyBinding{key}
}
```

## 多行排版

- 函数体始终使用多行花括号，包括只有一条 `return` 的函数。
- `if`、`else`、`for`、`switch` 的执行语句拆行，保持块级缩进。
  控制流统一使用花括号，避免将 `do` 和执行语句压在一行。
- 每条独立语句单独一行，不用分号串联语句。`for` 的初始化、条件和步进
  仍可在循环头中使用分号。
- 结构体、枚举的每组字段或成员单独一行；同类型且紧密关联的字段可以
  保留为 `Width, Height: int` 这样的声明。
- 较长的参数列表、调用和复合字面量按参数或逻辑组拆行，续行增加一级缩进。
  简短的坐标、颜色和空值可以保留为 `Vec2{1, 2}`、`Color{...}`、`{}`。
- 独立函数和类型声明之间留一个空行。函数内部可用空行分隔初始化、验证、
  操作和清理等步骤，避免给每条语句都加空行。

例如，短函数和条件判断也按下面的形式书写：

```odin
ClampIndex :: proc(index, count: int) -> int {
	if count <= 0 {
		return 0
	}

	return min(max(index, 0), count - 1)
}
```

## 本地修改

偏离上游 Foster 的主动修改（新增、行为变更、修复、删除）必须登记到
[LOCAL_CHANGES.md](LOCAL_CHANGES.md)，并在修改点写 `// [olib L-xxx] 简述` 标记；
纯新增优先放在 `olib_ext.odin` / `olib_*.odin`，少改移植文件。提交前运行
`powershell -File foster/tests/check_local_changes.ps1`。

## 格式配置与维护

本目录上一级的 [odinfmt.json](../odinfmt.json) 是格式参数的依据：

| 项目 | 当前约定 |
| --- | --- |
| 缩进 | Tab，显示宽度为 4 |
| 行宽 | 以 100 字符为换行目标，优先保留清晰的参数分组 |
| 空行 | 普通声明和语句间最多保留一个空行 |
| 换行符 | CRLF |
| imports | 保持既有顺序，不自动排序 |
| 控制流 | 将 `do` 转换为花括号；case 的执行语句拆行 |
| 复合字面量 | 较长内容使用多行，保留结构体中的分组空行 |

在 olib 根目录运行：

```powershell
# 格式化整个库
odinfmt -path:foster -config:foster/odinfmt.json -w

# 仅格式化当前修改的模块
odinfmt -path:foster/input.odin -config:foster/odinfmt.json -w
```

格式化器负责统一缩进、空格和换行参数；文件层级、函数归属和顶部导航需要
维护者更新。已有单行函数体或结构体字段也需要主动展开，不能只依赖自动格式化。

`web.odin` 中较长的 `foreign proc` 声明使用局部
`// odinfmt: disable` / `// odinfmt: enable` 保留手工参数分组。
维护该区域时仍遵循多行排版约定，禁用范围仅覆盖需要保留布局的接口块。

提交前确认新增内容位于正确分区、导航与标题一致、代码已拆行，再检查格式差异：

```powershell
git diff --check
```

纯文档修改无需重跑运行时测试。涉及源码的排版调整至少运行
`odin check foster -collection:olib=. -no-entry-point`；存在逻辑或块结构改动时，再按
[README 的验证说明](../README.md#port-coverage-and-verification)运行相关回归。
