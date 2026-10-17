# Clay：纯 Odin 移植

此包是 Clay **v0.14** 的 Odin 实现，保留 olib 原有 `clay-odin` 导入路径、
公开类型、字段名、函数签名和 `if clay.UI()(declaration) { ... }` 写法。
运行与常规测试只需要 Odin，不链接 Clay 的 `.obj`、`.a`、`.o`，不需要 C 编译器。
`proc "c"` 仅保留已有函数及回调的调用约定；函数体均由 Odin 编译。

上游：[nicbarker/clay](https://github.com/nicbarker/clay)，固定源码提交
[`b25a31c1a152915cd7dd6796e6592273e5a10aac`](https://github.com/nicbarker/clay/tree/b25a31c1a152915cd7dd6796e6592273e5a10aac)。
这是明确修改过的移植版本，不是上游原始 C 文件；许可证见 [LICENSE.md](LICENSE.md)。
不要直接按上游 main 更新接口：main 已有 `EndLayout(deltaTime)` 等不兼容变化。

## 实现与边界

- `clay.odin`：原有公共类型和 Odin 声明辅助函数。
- `clay_types.odin`：Context、布局树、缓存及内部数组类型。
- `clay_memory.odin`：arena、数组、ID、文字测量缓存及相关辅助函数。
- `clay_layout.odin`：元素声明、尺寸约束、换行、浮动、裁剪及渲染命令生成。
- `clay_debug.odin`：完整的 v0.14 内置布局调试面板。
- `clay_api.odin`：生命周期、输入、滚动和查询接口。
- `clay_helpers.odin`：Odin 字符串、指针偏移和 C 表达式语义辅助函数。

函数保留上游对应名称及 `clay.h` 行号，便于对照修复。第一版以行为兼容为目标，
不同时重设计分配方式、接口或布局算法。原始 arena 由调用方持有；返回的命令、
文本切片和滚动指针仍遵循原有生命周期。切换 Context 的能力保留，全局当前
Context 和测量回调也保留，因此仍不能并发调用或交错执行 begin/end。

明确的实现差异：

- C 宏使用 Odin 泛型、普通过程及 `defer` 表达。
- 数据哈希与内存比较使用上游的标量实现，不依赖 SSE/NEON；没有声称性能优于 C。
- 字符串 ID 按原有 Windows x64 C 二进制的有符号字节规则散列；中文和其他 UTF-8
  ID 也保持一致，并在 Odin 支持的平台上统一该规则。
- `RenderCommandData.clip` 补全上游已有的裁剪数据；原有字段继续兼容。
- Context 内部布局不是稳定 ABI，`MinMemorySize()` 的数值不要求与 C 相同。
  应继续通过该函数申请内存，不硬编码 C 的结构大小。

## 验证

日常检查已接入 `odin run tools/check`，也可以单独运行：

```text
odin test thirdparty/clay-odin/tests -vet
odin test kit/ui -collection:olib=.
```

对照基准是 olib 历史提交 `a57cea853a46bf1b0a5662b80c0bb976154c635e`
中的原始 Windows x64 C 对象，SHA-256：
`7dc7101dfbea6f30742b77b6fdaa77a8391dbd9665a117f10d7133e0c390f557`。

同一组 Odin 场景分别调用该 C 绑定和本包，逐行比较 **20,096 行**可观察输出：
320 帧组合布局、18 帧双轴滚轮/拖拽/惯性滚动，以及 Context 切换和错误路径。
覆盖 Fit/Grow/Percent/Fixed、最小/最大尺寸、padding/gap/对齐、文本换行与行高、
图片宽高比、浮动锚点/zIndex、裁剪/culling、边框、自定义命令、悬停回调、
UTF-8 ID、调试面板、重复 ID、无效百分比/浮动父级、缺少文字测量回调、
元素容量/文本缓存容量溢出、越界命令查询及 arena 重新初始化。

几何输出格式为小数点后四位；命令顺序、ID、文本、颜色和其他打印值逐字一致。
日常测试使用 C 输出的逐帧 FNV-1a 摘要，失败时打印原始命令，避免提交大体积
参考输出。快照不是用 Odin 实现生成的。

需要重新执行完整的 C/Odin 对照时，在 Windows x64 上运行：

```text
python thirdparty/clay-odin/tests/compare_reference.py
```

该可选维护脚本需要 Python、Git、Odin 及上述历史提交。它在临时目录从 Git
取回并校验 C 对象，分别构建两个程序；不把 C 文件放回库中，不需要 C 编译器。
只有显式传 `--update-snapshot` 且完整输出一致时，才从 **C 版**重新生成快照。

本次验收：Windows x64 全量 71 项检查通过；Linux amd64、macOS arm64、
JS/Wasm32 通过 Odin 编译检查，未在这些目标平台执行运行测试。
UI Gallery 的默认尺寸、窄窗口 125% 缩放与运行中 resize（1100×760 → 760×760 →
960×800）截图，以及 Game UI 的技能、背包、
暂停、滑条、开关、返回/继续冒烟通过，UI 错误和池溢出均为零。
