# olib 编码规范

适用范围：`core/` 与 `kit/` 的第一方源码（含测试）。
`thirdparty/` 是外部绑定的 vendored 代码，保持与上游一致，**不适用**本规范。
`foster/` 是 Foster 移植，**豁免**本规范，沿用 [foster/docs/CODE_STYLE.md](../foster/docs/CODE_STYLE.md)；
对它的主动修改须登记到 [foster/docs/LOCAL_CHANGES.md](../foster/docs/LOCAL_CHANGES.md)。

## 1. 仓库布局

```
olib/
├── core/        纯 Odin：通用数据结构、数据格式，无运行时依赖
├── foster/      唯一运行时：App / 窗口 / 输入 / 图形 / 基础类型，豁免本规范
├── kit/         扩展层（kit）：UI / 资源管线 / 相机场景 / 3D / 动画 / 音频 / CLI
├── thirdparty/  外部绑定：clay-odin / odin-imgui
├── prompts/     给 AI 的提示词与开发约定（new-project / dod-guidelines）
└── docs/        本文档
```

- 一个目录一个 Odin 包；包名与目录名一致（`core/handle/array` → `package array`）。
- 同一主题的声明、构造、查询、修改和释放函数放在一起，不为层级拆小文件；
  单主题的小包（如 `meta.odin`）一个文件即可，多主题包按主题分文件
  （参考 `core/tween/`：manager / tween / interpolated / managed_*）。
- 依赖方向单向：`kit → foster`、`kit → core → (Odin core/base)`；
  core 不得依赖 foster 或 kit；foster 不依赖 olib 其他任何包。

## foster 与 kit 的边界

1. **foster**：App 生命周期、窗口、输入、图形、基础类型（`Color`、`Vec2`、`Rect`……）一律直接用 foster。
2. **kit**：只提供 foster 没有的能力，例如 UI、资源管线、相机/场景、3D 队列、动画、音频、CLI 控制台。
3. **硬规则**：
   - kit 的 API 直接接收、返回 foster 类型；**不给** foster 的类型或 proc 起别名，**不做**一对一封装；
   - kit **不封装** foster 的 App 生命周期（`init_app` / `Run` / `Exit` / `dispose_app`）；
   - `foster/` 以外的代码**不得** import `olib:foster/internal/...`。
4. 依赖方向：`kit → foster`、`kit → core`；`core` 不得依赖 `foster` 或 `kit`；`foster` 不依赖 olib 其他任何包。

主动修改 Foster 时须先登记 [LOCAL_CHANGES.md](../foster/docs/LOCAL_CHANGES.md)，
保留 Foster API 与命名体系。

## 2. 分节注释（表达层级）

大模块/大分区用 80 字符宽的双线框：

```odin
// ==============================================================================
// 模块 / 主要功能 — 简短说明
// ==============================================================================
```

类型或子分区用 80 字符宽的单线框：

```odin
// ------------------------------------------------------------------------------
// 模块 / 主要功能 / 类型或子功能 — 简短说明
// ------------------------------------------------------------------------------
```

- 函数内部的局部阶段用单行短注释（`// ---- 第一遍：身份 ----`），不加线框。
- 分区前后保留一个空行；不给每个小函数加线框。
- 标题使用真实语义（"生命周期"“查询”“迭代”），禁止"其他"“杂项"。
- 有参考实现时标题对齐其目录/类型层级（olib 的 kit/* 对位 DragonLib
  Libs/Engine 的 Assets/World/Messaging）。

## 3. 顶部导航

文件顶部（`package` 之后、imports 附近）列出主要分区，顺序与正文一致：

```odin
package tween

// 分区：
//   类型 —— 句柄/状态机/节点/回调/配置
//   节点池管理 —— make / add / remove / reset / delete
//   帧推进 —— manager_update / 自动清理
```

单主题小文件（如 `scene_router.odin`、`meta.odin`）可以只有文件头说明，
不需要导航。包文档（`package` 上方注释）只写在包的一个主文件里，
其余文件用 `package` 之后的普通注释描述本文件职责。

## 4. 排版

- **缩进**：Tab（宽 4）。禁止空格缩进与 Tab 混用。
- **行宽**：约 100 字符；超出时拆参数列表/调用/条件/复合字面量并保持缩进。
- **多行展开**：函数体、if/for/switch 分支、struct 字段一律多行。
  `if cond { stmt }`、`if destroy != nil { destroy(item) }` 这类挤压写法要展开。
- **允许的单行**：
  - `if cond do return` / `if cond do continue`（Odin 惯用单语句）；
  - 短向量/颜色/坐标字面量（`{0, 0}`、`Color{255, 0, 0, 255}`）；
  - switch 的 `case 值:` 标签行本身（语句体换行）。
- **imports 排序**：按库分组字母序——`base:` < `core:` < `olib:`，
  别名紧跟（`import ha "olib:core/handle/array"`）。
- 保留语言自然写法：proc 分组重载（`remove :: proc {…}`）、`or_return`、
  `do` 单语句、`#optional_ok/error` 等按 Odin 惯例使用，不模仿 C#。

## 5. 注释质量

- 说明**用途、资源所有权、生命周期、平台差异、关键约束**（如
  "指针在 add/remove 后可能失效"“destroy 回调不得结构性变更本池”）。
- 不逐句复述代码；不写"这里调用了 x"式的空泛注释。
- 有价值的原注释（上游作者的英文文档、署名、许可证、`#+build`、`#+vet`
  等编译指令）原样保留；整理时只增不改。
- 注释语言：结构性注释（分节/导航/文件头）用中文；保留的英文原注释不强翻。

## 6. 格式化工具

当前工具链（Odin dev-2026-07-nightly, ab0131c）**没有 `odin fmt` 子命令**，
也没有独立的 odinfmt 二进制，因此排版靠本规范 + 人工保持。
将来工具链提供 `odin fmt` 后，提交前对第一方目录运行：

```powershell
odin fmt core
odin fmt kit
```

`odin fmt` 无法展开的密集代码（单行 if、挤压的 case 体）仍按第 4 节手动整理。

## 7. Odin 语言注意事项（踩过的坑）

- proc 字面量**没有闭包**：需要状态的回调走 `proc(item, userdata: rawptr)` +
  userdata 惯例（见 `core/messaging` 的 `queue_drain`）。
- 泛型参数上的隐式枚举选择子无法解析：调用处写显式成员名
  （`Screen.Title` 而非 `.Title`，见 `kit/world/scene_router.odin`）。
- 切片 `transmute` 保留 len 数值而非按字节换算：跨类型字节拷贝一律
  `mem.copy(rawptr, rawptr, 字节数)`（设计语义，不会随版本改变）。
- 结构体字段无默认值：提供 `xxx_init` proc 并在文档注明零值可用性。

## 8. 测试约定

- 每包一个 `*_test.odin`，文件头 `#+test` + `package <包名>`，
  用例 `@(test)` + `testing.expect/expectf`。
- 涉及文件系统的测试在 `%TEMP%/olib_<包名>_test` 下自建自清；
  Windows 上不用 `os.remove_all`（core bug，见
  [odin#7547](https://github.com/odin-lang/Odin/issues/7547)），用自实现递归删除。
