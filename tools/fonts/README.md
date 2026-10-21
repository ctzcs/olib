# 离线 MSDF 字体资产

统一使用 [msdf-atlas-gen](https://github.com/Chlumsky/msdf-atlas-gen) 生成真正的多通道图集。
生成器只用于开发/资产构建，不随游戏发布；运行时直接使用 Foster 的 `MsdfFontLoadFiles`
或 `ImageFromEncoded`＋`MsdfFontMake`，不新增 kit 包装层。

本仓库测试资产使用 **msdf-atlas-gen 1.4**。从上游 release 下载对应平台工具，
或按上游说明从 v1.4 源码构建；把可执行文件加入 PATH。Windows release 为
[msdf-atlas-gen-1.4-win64.zip](https://github.com/Chlumsky/msdf-atlas-gen/releases/download/v1.4/msdf-atlas-gen-1.4-win64.zip)。

## 生成

字符集文件是生成器的 charset 语法，例如 ASCII 加中文：

```text
[32, 126]
"中文菜单设置返回确认取消"
```

包含本地化和动态文本可能用到的全部字符；引号内按 UTF-8 保存，也可一行一个 `0x4E2D`
这样的 Unicode 码点。不要直接把未经转义的本地化 JSON 当作 charset 输入。

在游戏仓库中运行（输出目录须先存在）：

```sh
msdf-atlas-gen -font assets/source/ui.otf -charset assets/source/ui-charset.txt -type msdf -format png -size 48 -pxrange 8 -yorigin top -seed 0 -imageout assets/ui.png -json assets/ui.json
```

必须确认生成器退出成功，且 `Loaded geometry of N out of N glyphs` 没有缺字。
输出 JSON 应为 `atlas.type = "msdf"`、`atlas.yOrigin = "top"`，宽高应匹配 PNG。
PNG 的 RGB 应包含不同的距离信息；不能换成 SDF 或把同一个距离复制三次。

`-yorigin top` 对当前 Foster 加载器是必需的，省略时生成器默认 bottom 原点，
会导致字形边界/基线解释错误。保留默认对称距离范围，不使用自定义非对称范围；
现有 shader 以 0.5 为边界。PNG 与 JSON 必须一起更新，不能混用不同批次。

图集是线性数据，禁止 sRGB 解码或预乘 alpha。运行时保持线性过滤；不要通过硬阈值
或增加字体字重掩盖采样问题。48px/em、范围 8 是起点，最终质量验收见
[UI 像素与采样约定](../../kit/ui/README.md#最终像素采样与清晰度验收)。

源字体、许可证、字符集、生成器版本、完整参数和生成结果一起纳入资产版本管理。
字体子集和图集是正式资源，不迁入 library；临时对比图与验收截图按
[生成文件规则](../../prompts/new-project.md#生成文件与目录纪律) 分别放 library/tmp 与 library/screenshots。
动态新增字符后重新生成并打包；离线资产不提供运行时 TTF 补字。

## 复现库内测试资产

在 olib 根目录运行：

```sh
msdf-atlas-gen -font foster/tests/port_regression/fonts/Abel-Regular.ttf -charset tests/kit/ui/testdata/abel-charset.txt -type msdf -format png -size 48 -pxrange 8 -yorigin top -seed 0 -imageout tests/kit/ui/testdata/abel-msdf.png -json tests/kit/ui/testdata/abel-msdf.json
odin run tools/check -- -only:kit/ui
```

预期 95/95 字形、336×336 图集。CPU 测试读取真实 PNG/JSON，检查通道独立信息、字形
边界、基线、空格、字距和 UI 四边形/测量一致性。该测试不能替代最终 GPU 输出验收。
Abel 源字体及 OFL 许可证位于 `foster/tests/port_regression/fonts/`，图集旁附许可证副本。

示例共用的中英文图集及复现说明位于同级 `olib_sample/shared/msdf_font/`；
`game_ui`、`ui_gallery` 内嵌该资产，无系统字体依赖；Shader Lab 改用 ImGui 后使用下文的 ImGui 字体。

## ImGui 字体

ImGui 不使用 MSDF 图集，而是在运行时按需光栅化 OTF。olib 的 ImGui 后端默认加载
[`assets/fonts`](../../assets/fonts/README.md) 里同一字体（Noto Sans CJK SC）的 GB2312 子集，
由本目录的 `imgui_font.py` 生成；用法与复现命令见该 README。
