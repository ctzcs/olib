# Plan：kit/ui 运行时 SDF 字体烘焙，让文字在任意缩放下锐利

## 背景

新游戏 Proj_Sand（`D:\MySpace\Github\Proj_Sand`）的文字发虚，原因如下：

- `src/view/view.odin:65` 用 `ui.ui_font_bake` 烘焙了 **40px 位图图集**，注册时用默认的 `.Bitmap`。
- 主题的实际字号是 32 / 20 / 17（`view.odin:81-83`），还要乘窗口适配缩放（`src/game/main.odin:81`，最小 0.5），正文相当于把 40px 字形**缩小到一半左右**绘制。
- kit/ui 绘制文字使用线性采样（`kit/ui/ui_backend.odin:240`），图集没有 mipmap，位图缩小后笔画边缘发灰发虚。

kit/ui 已经支持 MSDF 渲染（`ui_register_font(..., .MSDF)`，着色器 `foster/assets/shaders/Msdf.hlsl`），但 olib 没有在运行时生成距离场的能力，只能离线用 msdf-atlas-gen 生成，`prompts/new-project.md` 也只教了位图烘焙，所以新游戏都走了位图。

**方案**：在 kit/ui 新增运行时 **SDF** 烘焙。用 `vendor:stb/truetype` 的 `GetGlyphSDF` 生成单通道距离场，把同一个值写进 RGB 三个通道。MSDF 着色器取三通道中值，结果就是这个 SDF，可以直接复用，不改着色器。OFoster_Sample `ui_gallery shot msdf` 的距离场探针已经验证过“三通道同值”能在这个着色器上正确渲染。代价是字号极大时笔画尖角略圆（SDF 相比 MSDF 的已知限制），游戏 UI 字号下可以忽略。

## 已定决策（执行时不要改）

1. **新增 API，不改 `ui_font_bake`**。位图烘焙的行为、输出必须完全不变（像素艺术、固定字号场景仍需要它）。
2. 新 API 放在 `kit/ui/ui_font_bake.odin`，签名：

   ```odin
   // 用距离场烘焙字体图集：任意缩放下保持锐利，注册时必须传 .MSDF。
   // 返回的 msdf 拥有 Image.Pixels、Characters 和 Kerning，须用 MsdfFontDispose 释放；
   // texture 须由调用方 TextureDispose。源 Font 由调用方管理，可在烘焙后释放。
   ui_font_bake_sdf :: proc(
   	device: ^foster.GraphicsDevice,
   	font: ^foster.Font,
   	size: f32 = 48,
   	codepoints: []int = nil,      // nil 为 ASCII 32..126，与 ui_font_bake 一致
   	distance_range: f32 = 8,      // 距离场覆盖的像素范围（烘焙尺寸下），写入 MsdfFont.DistanceRange
   	label := "ui sdf font",
   ) -> (msdf: foster.MsdfFont, texture: foster.Texture, ok: bool)
   ```

   与 `ui_font_bake` 一样拆出一个不需要 GPU 的内部函数 `ui_font_bake_sdf_image`，便于单测。
3. **不得 import `olib:foster/internal/...`**。直接 `import stbtt "vendor:stb/truetype"`，用 `foster.Font` 的公开字段 `Data` 自己 `stbtt.InitFont`。foster 内部用的也是同一个 `vendor:stb/truetype`，不会产生重复链接；`stb_truetype_wasm.o` 存在，Web 目标可用。
4. **距离编码必须与着色器约定一致**。`Msdf.hlsl` 中 `dist - 0.5` 等于“到边缘的纹素距离 / DistanceRange”（内部为正），所以：
   - `GetGlyphSDF(info, scale, glyph, padding, onedge_value = 128, pixel_dist_scale = 255 / distance_range, ...)`；
   - `padding = int(math.ceil(distance_range / 2)) + 1`，保证距离场在字形包围盒外降到 0 之前不被截断；
   - 每个像素写 `Color{v, v, v, 255}`（RGB 同值，**不做预乘**；着色器只读 RGB，输出 `input.Color * alpha`）；
   - `msdf.DistanceRange = distance_range`。
   动手前先读 `Msdf.hlsl` 和 stb 的 `GetGlyphSDF` 文档确认符号方向（stb：`pixel_dist_scale` 为正时内部值大于 `onedge_value`）。
5. 度量（`Size`、`Ascent`、`Descent`、`LineHeight`）、字距（`FontGetKerning`，按码点）、字符集默认值、shelf 打包与扩容规则，与 `ui_font_bake` 保持一致。字形的 `SourceRect` 与 `Offset` 使用 SDF 位图的实际尺寸和 `xoff/yoff`（已包含 padding），保证 kit/ui 按 `字号 / Size` 缩放后基线不变。可以把打包和度量部分抽成两者共用的内部函数，但 **`ui_font_bake` 的输出必须逐字节不变**（第 2 步验证）。
6. 不改 `foster/`、不改着色器、不改 `thirdparty/`。

## 执行步骤

在 master 上新建分支 `ui-sdf-font`，每一步一个 commit。开始前运行 `powershell -File check.ps1` 确认全部通过，并用 OFoster_Sample 生成一组截图基线（`run.bat game_ui shot`、`run.bat ui_gallery shot`、`run.bat ui_gallery shot msdf`，存到 `build/baseline-sdf/`）。

### 1. 实现 `ui_font_bake_sdf`

按“已定决策”实现，并在 `kit/ui/ui_test.odin` 加 CPU 单测（不需要 GPU，参考现有的 `font_bake_*` 测试，字体用 `foster/tests/port_regression/fonts/Abel-Regular.ttf`）：

- ASCII 默认字符集：95 个字符，`DistanceRange == 8`，`'A'` 的 `SourceRect` 非空，空格 `SourceRect` 为 0 且 `Advance > 0`；
- 所有像素 `R == G == B` 且 `A == 255`；
- `'A'` 字形中心附近有大于 128 的值（内部），图集左上角 padding 区为 0 或接近 0（外部）；
- 显式传入 ASCII 列表与 `nil` 的字距结果一致；
- 自定义大字号字符集会扩容且 `SourceRect` 不越界；
- 无效输入（nil 字体、size ≤ 0、distance_range ≤ 0）返回 false 且不泄漏。

Commit：`kit/ui: ui_font_bake_sdf 运行时 SDF 字体烘焙`

### 2. 回归：位图路径不变

- `odin test kit/ui` 全部通过（原有位图测试不改）。
- 用开始前的截图基线逐像素比较 `game_ui shot`、`ui_gallery shot`、`ui_gallery shot msdf`，必须完全一致（这些示例仍用位图烘焙）。

这一步只有验证，没有改动就不提交。

### 3. 视觉验收：SDF 在不同缩放下锐利

在 OFoster_Sample 的 `src/ui_gallery` 增加一个 `sdf` 参数：开启时正文字体改用 `ui_font_bake_sdf` 烘焙并以 `.MSDF` 注册，其余不变。

- 分别运行 `run.bat ui_gallery shot sdf` 与 `run.bat ui_gallery shot sdf scaled`，和对应的位图版本截图对比。
- **实际打开截图查看**，放大文字区域，确认 SDF 版边缘清晰、没有发灰；同时检查字形没有被截断（padding 足够）、基线和行高与位图版一致（位置偏差不超过 1px）。
- 在汇报里附上对比结论和截图路径。截图放在 `build/`，不提交 png。

OFoster_Sample 单独提交：`ui_gallery: sdf 参数演示运行时 SDF 字体`。README 的 ui_gallery 参数说明里加上 `sdf`。

### 4. Proj_Sand 改用 SDF

在 `D:\MySpace\Github\Proj_Sand` 中：

- `src/view/view.odin` 的 `ui.ui_font_bake(device, &source, 40, points[:])` 改为 `ui.ui_font_bake_sdf(device, &source, 48, points[:])`，`ui_register_font` 传 `.MSDF`。
- 运行游戏的截图或冒烟参数（查看 Proj_Sand 的 README 与 `src/game/main.odin` 里支持的参数），在默认窗口和 `scaled` 下各截一张，实际查看确认中文和英文都锐利、没有缺字。
- 运行 Proj_Sand 的 `check.ps1`。
- **Proj_Sand 目前还没有任何提交，不要替用户提交**，只改文件并在汇报里说明。

### 5. 文档与提示词：默认用 SDF

- `kit/ui/README.md`：在“位图字体烘焙”一节旁新增“距离场字体（推荐）”一节，说明 `ui_font_bake_sdf` 的用法（必须以 `.MSDF` 注册）、参数含义（`size` 是烘焙尺寸、与显示字号无关；`distance_range`）、所有权，以及何时仍用位图（像素风、且烘焙尺寸恰好等于“显示字号 × 缩放”）。说明位图缩小显示会发虚的原因：线性采样且无 mipmap。
- `prompts/new-project.md`：
  - “UI 用什么以及如何接入”的字体条目改为：**默认用 `ui.ui_font_bake_sdf` 烘焙（建议 size 48）并以 `.MSDF` 注册，文字在任意字号和窗口缩放下都锐利**；`ui_font_bake` 位图只用于像素风或固定缩放，且烘焙尺寸要等于实际显示像素，否则缩小显示会发虚。中文仍需把本地化文本用到的全部字符作为 `codepoints` 传入。
  - “UI 视觉和文字约定”加一条：文字必须锐利，在默认窗口、窄窗口和缩放下截图放大检查笔画边缘，发虚即不合格。
  - “至少验证以下内容”的 UI 条目补上“文字在各缩放下锐利”。
- `prompts/dod-guidelines.md` 第 8 节（文本与显示）里提到 `ui_font_bake` 的地方，改为 `ui_font_bake_sdf`（`codepoints` 的说明保留）。
- `docs/ROADMAP.md`：“已完成”表的游戏 UI 行加上“运行时 SDF 字体（`ui_font_bake_sdf`）”；工具链里的 msdf-atlas-gen 保留，注明“需要尖角质量时再做”。

Commit：`docs/prompts: 字体默认用 SDF 烘焙，保证锐利`

### 6. 归档本计划

按 [docs/plans/README.md](README.md) 归档本计划。

## 验收

- `powershell -File check.ps1` 全部通过（含 vet 与新增单测）；
- 位图路径截图与基线逐像素一致；
- SDF 截图经实际查看确认锐利、无截断、基线一致（汇报写结论与截图路径）；
- Proj_Sand 改用 SDF 后截图锐利、`check.ps1` 通过；
- `grep -n "ui_font_bake_sdf" prompts/new-project.md kit/ui/README.md` 有结果。

## 禁止事项

- 不改 `foster/`、`thirdparty/`、着色器；不改 `ui_font_bake` 的输出。
- 不 import `olib:foster/internal/...`。
- 不替用户提交 Proj_Sand；不 push；不合并回 master。

## 汇报内容

- commit 列表（olib 与 OFoster_Sample 分开列）；
- 距离编码参数的最终取值及依据（与着色器的对应关系）；
- 位图回归比对结果、SDF 视觉检查结论与截图路径；
- Proj_Sand 的修改与截图结论；
- 任何偏离本计划的地方及原因。
