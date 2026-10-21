# 游戏 UI

[纯 Odin Clay](../../thirdparty/clay-odin/README.md) 负责布局，`kit/ui` 提供控件、交互与 Render2D 后端（原生使用 olib 材质）。
kit/ui 只承担玩家 UI；编辑器、开发面板和调试工具使用 odin-imgui，见[新项目约定](../../prompts/new-project.md#ui-用什么以及如何接入)。
可运行游戏界面位于示例仓库 [olib_sample](https://github.com/ctzcs/olib_sample) 的 `src/game_ui`：遗迹场景上的生命/能量 HUD、
带冷却遮罩的技能栏、格子背包和暂停菜单。它使用同一套布局与交互，游戏皮肤在示例中定义。
原来的设置页和控件验收示例在同仓库的 `src/ui_gallery`。
示例仓库需与 olib 同级检出，以下 `run.bat` 命令均在示例仓库根目录执行。

需要保存 UI 的 Odin 代码后在运行中的游戏看到修改时，使用
[游戏代码与 UI 热重载](../../core/hotreload/README.md)。UI 声明在游戏 DLL 内执行，
每次成功切换都重建该 DLL 私有的 `UI_Context` 并重新注册字体；不要跨 DLL 保留 Clay 内存、
测量回调或文字地址。背包开关等需保留的状态由游戏快照恢复，按住/拖动/焦点等瞬时交互重置。

## 最小帧流程

初始化一次 `ui_init(&ctx, width, height)`，注册字体；退出时先释放 UI，再释放字体、
贴图和 GraphicsDevice。`UI_Context` 必须保持地址稳定，不要按值复制。
文字材质借用 Render2D 的材质库，库须活到 UI 释放之后；ui_draw/ui_render 只记录，调用方最后 submit。

```odin
// renderer: r2d.Render2D 已用材质库初始化，见 rendering/2d README。
// 初始化：font 与 texture 由资产层提供，存活到 ui_dispose 之后。
ui.ui_init(&ctx, 1280, 720)
theme := ui.UI_THEME_DARK
theme.body_font_id = u16(ui.ui_register_font(&ctx, &font, texture, .MSDF))

// 每帧：viewport 和鼠标位置均为渲染目标像素，布局尺寸则是逻辑像素。
ui.ui_set_viewport(&ctx, {0, 0, pixel_width, pixel_height}, scale = 1.25)
ui.ui_set_pointer(&ctx, mouse_x_pixels, mouse_y_pixels, mouse_down)
ui.ui_add_scroll(&ctx, wheel_x, wheel_y)
ui.ui_set_navigation(&ctx, {next = tab_direction, activate = confirm_pressed})
ui.ui_begin(&ctx, dt)

if clay.UI()(ui.ui_panel_decl(&theme, width = 300)) {
    ui.ui_heading(&ctx, &theme, "Settings")
    ui.ui_toggle(&ctx, &theme, "music", &music_enabled)
    if ui.ui_slider(&ctx, &theme, "volume", &volume) {
        // 将 volume 应用到音频系统。
    }
    if ui.ui_button(&ctx, &theme, "resume", "Resume") {
        // 关闭暂停菜单。
    }
}

ui.ui_draw(&ctx, &renderer) // end + translate + render；复用操作缓冲
capture := ui.ui_input_capture(&ctx)
// 根据 capture.pointer / capture.keyboard，决定是否将本帧输入交给游戏。
err := r2d.submit(&renderer, {target = target})
```

需要自定义渲染时，可继续使用 `ui_end → ui_translate → ui_render`；`ui_translate`
的结果由调用者 `delete`。`ui_translate_into` 可以复用自有缓冲。
不要在 `ui_end` 之后再调用 `ui_draw`，它会重复结束布局。

## 子树视觉变换与 Tween

`ui_set_visual` 对稳定 ID 对应的整个子树应用位移、二维缩放、旋转与透明度。
文字、图片、九宫格、圆角和边框一起变换；布局占位不变。每帧在 `ui_begin` 和
`ui_end/ui_draw` 之间重新注册，不注册的帧恢复原样。注册复制值，不保存调用者指针。

```odin
// 跨帧状态，地址必须稳定；退出时先 manager_delete，再释放目标状态。
visual := ui.UI_VISUAL_DEFAULT
mgr := tween.manager_make() // import tween "olib:core/tween"

// 只在事件发生时创建；若旧动画尚在运行，先 manager_kill 再从当前 visual 接续。
target := ui.UI_VISUAL_DEFAULT
target.offset = {0, -12}
target.scale = {1.05, 1.05}
target.rotation = -0.04
handle := tween.manager_add_tween_to(&mgr,
    tween.make_ex(visual, target, 0, {duration = 0.15, transition = .EaseOut}, ui.ui_visual_lerp),
    &visual)

// 每帧推进一次，然后声明 UI。
tween.manager_update(&mgr, dt)
ui.ui_begin(&ctx, dt)
ui.ui_set_visual(&ctx, "play", visual)
if ui.ui_button(&ctx, &theme, "play", "PLAY") {
    // 触发游戏逻辑或下一段动画。
}
ui.ui_draw(&ctx, &renderer)
```

- 从 `UI_VISUAL_DEFAULT` 初始化；`UI_Visual{}` 的零缩放和零透明度不可见。
  `offset` 为逻辑像素，`rotation` 为弧度（正值顺时针），`pivot` 为布局矩形的
  归一化支点，默认中心 `{0.5, 0.5}`，底部中心为 `{0.5, 1}`。
- 嵌套变换按父子关系合成，透明度相乘；浮动元素按其 attachment parent 继承。
  `.Root` 浮层独立于声明位置的祖先变换。旋转插值直接插值弧度，不自动选最短路径。
- `ui_visual_lerp` 可用于现有 Tween / Sequence。位置和缩放允许过冲，绘制时钳制透明度。
  每个图元的预乘 RGB 与 alpha 同步衰减；这不是离屏合成的组透明度。
- 点击沿用上一帧布局，并使用上一帧显示变换的逆矩阵；保留 Clay 浮层遮挡和模态规则。
  内置滑条也使用逆变换指针，自定义拖动控件可调用 `ui_pointer_local`。
  零缩放和零透明度不接受指针命中；键盘焦点与业务可交互性仍由 `disabled` / 模态控制。
- 裁剪仍是屏幕轴对齐矩形。平移/轴对齐缩放后的裁剪准确；旋转裁剪容器使用变换后的
  **轴对齐包围盒**，不支持精确旋转遮罩。固定滚动窗口中的内容可以自由旋转。
- 动画期间不修改字体图集，不把 UI 先画成低分辨率纹理；字形几何在最终像素目标上变换。
  退场时保留声明和输入隔离，动画完成后再移除元素。UI 时间应独立于暂停的世界时间。

同级示例仓库运行 `run.bat ui_motion`：点击 ATTACK 看按压回弹、RELIC 看蓄力跳跃和
落地挤压、REWARD 看弹窗进出；Tab/Enter 支持键盘确认。`shot` 自动点击、resize 并
保存最终输出截图，可加 `scaled narrow` 验收 125% 和窄窗口。这是既有示例的可选检查，
不要求新游戏接入，也不要求每次修改都运行。留存截图归入示例项目的 `library/screenshots/`。

## 离线 MSDF 字体（默认）

新项目统一使用真正的多通道 MSDF：离线用 `msdf-atlas-gen -type msdf` 生成 PNG＋JSON，
运行时直接加载并以 `.MSDF` 注册。RGB 保存不同边缘的距离信息，不能把单个距离值复制到 RGB。
生成命令、字符集格式与测试资产的复现步骤见 [字体资产生成](../../tools/fonts/README.md)。

```odin
font := foster.MsdfFontLoadFiles("assets/ui.png", "assets/ui.json")
// 本加载接口对图像与元数据的校验有限，资产构建阶段必须检查生成结果。
assert(font.Image.Width > 0 && font.Size > 0 && font.DistanceRange > 0)
texture := foster.TextureFromImage(&game.GraphicsDevice, &font.Image, "UI MSDF")
assert(texture.Resource != nil)
ui.ui_register_font(&ctx, &font, texture, .MSDF)
```

- 生成时必须指定 `-type msdf -yorigin top`；现有 Foster 加载器按向下的 Y 轴读取字形边界，
  不能直接使用生成器默认的 bottom 原点。PNG 与 JSON 必须来自同一次生成。
- `-size 48 -pxrange 8` 是起点，分别写入 `Size` 与 `DistanceRange`；显示字号独立于图集尺寸。
- 字符集文件应包含全部本地化文字、标点与动态文本可能用到的字符；仅 ASCII 不包含中文。
  新增字符需重新生成资产并重新打包，不在运行时读取 TTF 补字。
- 距离值按线性数据采样，不使用 sRGB 解码、不做 `ImagePremultiply`；保持线性过滤。
- `font` 地址必须稳定并存活到 `ui_dispose` 之后。随后调用 `MsdfFontDispose`、
  `TextureDispose` 分别释放字体和纹理。`MsdfFontLoadFiles` 成功加载时拥有图像；
  用 `ImageFromEncoded`＋`MsdfFontMake` 内嵌资产时，须显式设置 `font.OwnsImage = true`
  或由调用方单独释放图像，不能重复释放。

迁移：`ui_font_bake_sdf` 已删除，没有兼容别名。旧调用应改为加载离线 MSDF 资产，
保留 `.MSDF` 注册。SDF 的旧图集也必须重新生成，不能只改名字。
MSDF 能更好地保留尖角，但不保证任意小字号都清晰，仍须完成下面的最终像素验收。

示例：`run.bat ui_gallery shot msdf`、`run.bat ui_gallery shot msdf scaled`；
普通 UI 加载真正的 MSDF，`msdf` 模式单独展示中英文在 14/18/36/72px 下的效果（Shader Lab 已改用 ImGui）。

## 旧项目的位图字体兼容

保留 `ui_font_bake` 与 `.Bitmap` 供旧项目兼容，新项目默认采用上面的离线 MSDF。
位图烘焙尺寸应等于“显示字号 × 最终像素比例”的实际像素尺寸，比例变化时重新烘焙对应缓存。
UI 使用线性采样且图集没有 mipmap，将较大的位图缩小显示会让笔画边缘发灰发虚。

`ui_font_bake` 使用 Foster 的公开 Font API，把字体烘焙为 UI 可注册的位图图集。
默认字符集是 ASCII 32..126；可传 `[]int` 指定字符集。48px ASCII 图集为 1024x512，
更大的字号或字符集按 shelf 布局扩容，字形间留 2px，像素采用预乘 alpha。

```odin
source := foster.FontLoadFile("path/to/font.ttf")
font, texture, ok := ui.ui_font_bake(&game.GraphicsDevice, &source, 48)
foster.FontDispose(&source)
if ok {
    ui.ui_register_font(&ctx, &font, texture, .Bitmap)
}
```

`font` 必须保持地址稳定、存活到 `ui_dispose` 之后。调用方用 `MsdfFontDispose`
释放图集像素、字形和字距表，再用 `TextureDispose` 释放纹理；失败时不遗留资源。
烘焙把 `FontMake` 移入 `LineGap` 的下降量还原，以保留旧示例的基线和行高。
`Descent == 0 && LineGap > 0` 按这一归一化约定处理。所有字符集都用 `FontGetKerning`
按 Unicode 码点查询字距；省略字符集与显式传入相同 ASCII 列表的结果一致。

## 最终像素采样与清晰度验收

**字体清晰度必须检查完整输出链路，不能仅凭 `.MSDF` 注册成功或构建通过判断。**

### 先确定 UI 最终画到哪里

推荐顺序为：世界渲染 → 缩放/后处理到窗口实际像素 → 叠加 UI → 输出窗口。
如果使用最终离屏 Target，它应与窗口 drawable 像素尺寸一致，再 1:1 复制到窗口。
不要把文字先画进固定 1280×720 的场景 Target，再整体缩放到 1600×900 等窗口尺寸：
MSDF 已经解码成像素，后续仍会插值或产生台阶，增大图集和加粗字体都不能消除这次采样。
需要模糊、FXAA 等全屏后处理时，应先处理世界再叠加 UI。

`ui_set_viewport` 的 rect 与指针都以最终渲染目标像素为单位，scale 负责逻辑布局到像素的映射。
高 DPI 下先区分窗口逻辑尺寸和实际 drawable 像素，按比例转换鼠标；resize 时更新输出 Target、
viewport、留边及命中坐标。只改变布局尺寸而不改变最终 UI 渲染目标，不能解决二次缩放。

### 再检查小字号和图集

- 字号、字重和采样是不同变量。常规中文正文优先保证约 14～16 个实际像素的可读性，
  更小字号需在最终尺寸实测。窄窗口不能无条件按比例缩小所有文字。
- MSDF 图集的 size 48 是起点；根据最终字号检查图集精度、`DistanceRange` 与实际屏幕距离范围。
  中文细笔画的小字号可能仍发灰，单纯提高图集 size 不保证改善。距离场保留线性采样，
  不要用最近邻或硬阈值作为通用修复，否则会产生锯齿和缩放闪烁。
- 小字号可用 `ui_font_bake` 按每个实际像素字号生成 `.Bitmap` 覆盖率图集，大标题继续用 MSDF。
  位图字形最终应按 1:1 像素绘制；必要时只平移整个字形到像素格点，保持四边形大小和
  advance/kerning 的累计精度，不分别取整两侧边缘或累计字距。kit/ui 当前不自动做像素对齐，
  自定义操作流可使用 `ui_end → ui_translate_into → 调整字形位置 → ui_render`，不能再调用 `ui_draw`。
- 位图缓存的来源包括字体、字符集、字号和最终像素比例；仅在来源改变时重建，不能每帧烘焙。
  注册项引用的字体地址必须稳定。替换 GPU 纹理时同步 UI 中的纹理副本，并清除 Clay 的文字测量缓存，
  由调用方释放旧字体与纹理，避免使用已释放的资源；不要通过不断追加注册项造成缓存增长。
- 使用可变字体时核对真实 `wght` 轴值；若发布固定字重，先实例化目标字重再裁剪字符集。
  不能假定源字体默认是 400，也不能以提高字重代替修复采样链路。

### 必须查看最终输出

截图应在世界、后处理和 UI 合成完成之后读取最终输出，PNG 尺寸等于实际渲染像素。
只保存固定分辨率的场景 Target 会漏掉窗口缩放造成的问题，不能作为最终画面的验收依据。
首次接入或修改全局布局、字体采样、DPI 换算时，检查默认窗口、窄窗口、非整数缩放（如 125%）、
运行中 resize 和相关中英文菜单/HUD；局部变更只验证受影响场景。记录窗口逻辑尺寸、实际渲染像素
和 UI scale。先按 1:1 查看可读性，再放大看笔画边缘，同时验证点击与留边对齐。
修改后重建实际运行的开发版/发布版，避免观察旧可执行文件。

截图只保存必要结果到所属项目的 `library/screenshots/`，同场景复用文件名；不要求每次生成
所有尺寸、语言与状态的整套图片。目录、文档和配置调整不额外截图，完整规则见
[生成文件与目录纪律](../../prompts/new-project.md#生成文件与目录纪律)。

文字发虚时按以下顺序定位：最终缩放链路 → 字形实际像素大小与像素对齐 → 图集及 MSDF 参数 → 字体字重。
3D 场景的斜边台阶与运动闪烁还需要单独检查场景分辨率、抗锯齿和细线尺度；
UI 的线性采样不是场景抗锯齿，文字清晰也不意味着 3D 画面已经通过验收。

## 控件和容器

| 接口 | 用途 |
|---|---|
| `ui_button / ui_button_ex` | 普通、主操作、Ghost 按钮；返回确认事件 |
| `ui_toggle` | 修改 bool，返回当前值 |
| `ui_slider` | 修改 f32，返回是否改变；支持拖动和导航步进 |
| `ui_progress_bar` | 0..1 进度，越界钳制 |
| `ui_image` | Foster Subtexture，支持图集及裁切帧 |
| `ui_image_decl` | 图片背景容器，可叠加文字、图标等子元素 |
| `ui_nine_slice_decl` | 整张纹理的对称九宫格背景，固定圆角和边框尺寸 |
| `ui_image_button` | 带焦点、禁用态的图像按钮 |
| `ui_heading / ui_label / ui_label_dim / ui_label_ex` | 文本、字号与颜色 |
| `ui_row_decl / ui_column_decl` | 行、列；默认 gap=8 |
| `ui_panel_decl` | 竖排面板；gap、固定宽度可配置 |
| `ui_scroll_decl` | 固定高度、滚轮滚动、双轴裁剪的列容器 |
| `ui_modal_decl` | 全屏浮动遮罩，配合模态输入作用域使用 |

声明函数返回普通 `clay.ElementDeclaration`，可在传给 `clay.UI()` 前继续修改尺寸、
padding、对齐等属性。不要把 `clay.UI()` 包进普通函数后返回给外层使用，
它依赖 Odin deferred 调用的作用域关闭元素。

```odin
if clay.UI()(ui.ui_scroll_decl(&ctx, "inventory", height = 300)) {
    for item in items {
        // item.id 必须全局唯一且跨帧稳定，不要用会随排序改变的位置作为身份。
        if ui.ui_image_button(&ctx, &theme, item.id, item.subtexture) {
            selected = item.id
        }
    }
}
// 整张贴图可先转为 foster.SubtextureFromTexture(&texture)。
```

## 交互和游戏输入

- 按钮、开关、图像按钮默认在“内部按下，再在内部松开”时确认；移出松开取消。
  `{trigger = .Press}` 可选择旧版按下即触发。
- `{disabled = true}` 禁止确认并跳过焦点导航，但仍阻挡世界点击。
- 滑条在按下后捕获指针，拖出仍能调值；释放、取消、禁用或控件消失会清除捕获。
- `UI_Navigation` 接受游戏映射后的动作：`next=±1` 按声明顺序导航、`activate`
  确认、`adjust` 调滑条、`cancel` 清除捕获和焦点。均为单帧事件，由 `ui_end` 消费。
  可映射 Tab/方向键/手柄按钮；当前没有空间方向寻路或自动滚动到焦点。
- 使用 `ui_interact` 给自定义控件复用 hovered/active/focused/disabled 等状态。
  一个控件 ID 每帧只调用一次。控件的命中依据上一帧布局，新元素需完成一帧布局。
- 普通容器不会自动消费鼠标：给面板设稳定 ID，调用 `ui_block_pointer(&ctx, id)`
  可让整个面板挡住世界输入。滚动区会自动调用它。
- 在声明完成之后读取 `ui_input_capture`，再处理游戏世界输入，避免点击穿透。
  该查询只报告消费意图，不会修改 Foster 原始输入状态。

模态应在帧开始前设置，并且每帧保持一致：

```odin
ui.ui_set_modal(&ctx, show_dialog ? "confirm-dialog" : "")
ui.ui_begin(&ctx, dt)
// 声明普通界面……
if show_dialog {
    ui.ui_set_scope(&ctx, "confirm-dialog")
    if clay.UI()(ui.ui_modal_decl(&ctx, "confirm-dialog")) {
        if clay.UI()(ui.ui_panel_decl(&theme, width = 360)) {
            if ui.ui_button(&ctx, &theme, "confirm", "Confirm") {
                show_dialog = false // 下帧更新模态状态
            }
        }
    }
    ui.ui_set_scope(&ctx, "")
}
```

模态期间背景控件不可交互，鼠标与键盘消费均为 true。改变模态会清除旧捕获/焦点。
打开弹窗的同帧，建议以 `ctx.modal_id != 0` 决定是否声明弹窗，避免显示与输入隔离错帧。

## 字体、缩放和资源

- `ui_register_font(..., .Bitmap)`：普通预乘 alpha 位图；默认类型，兼容旧 demo。
- `ui_register_font(..., .MSDF)`：真正的多通道距离场图集；使用字体的 `DistanceRange`
  和设备默认 MSDF 材质。不同字体会分别保留材质参数。GraphicsDevice 必须先初始化。
- 字体元数据与 GPU 纹理由调用方持有，UI 只释放自己的池、圆角纹理和材质副本。
  只在帧外注册字体；注册会清除 Clay 的文本测量缓存。
- 中文字距按 Unicode 码点计算；需要图集本身包含相应字形。当前没有 fallback 字体、
  动态汉字图集、字形塑形或 IME。文本换行由 Clay 处理，并非完整的多语言排版系统。
- `ui_set_viewport` 统一处理绘制、命中与裁剪的缩放/偏移。高 DPI 窗口要先把窗口鼠标坐标
  转成渲染目标像素，示例已演示。`ui_set_dimensions` 直接设置逻辑尺寸。
- 渲染恢复 Render2D 的矩阵、采样、混合、模式及裁剪状态。继承外部裁剪区域，
  使用屏幕 UI 变换，不叠加世界相机矩阵；UI 图元用默认材质，MSDF 文字用每种字体独立的 Text_Msdf 材质。
- 同一线程可逐帧切换多个 context，但不可交错 begin/end 或并发操作 Clay。
- `error_count / last_error` 记录 Clay 错误；`pool_overflow` 报告本帧文本/图像池超限。
  默认每帧各 1024 个，溢出元素不显示。运行时字符串要存活到渲染结束，
  帧临时分配器可用于 `fmt.aprintf`；foster 在 `RenderProc` 和 `GraphicsDeviceEndFrame` 之后
  自动清空 `context.temp_allocator`，这些字符串只在本帧有效，不要跨帧持有。

## 兼容性与边界

按钮/开关默认触发时机由按下改为松开；需要原语义时传 `.Press`。
`ui_panel_decl` 默认改为竖排并占满可用宽度，可用 `width` 参数固定宽度。
原始 Clay `.Image.imageData` 仍接受 `^foster.Texture`，UV 已修复为完整图像。
`ui_image` 使用自己的 Custom 命令；其他 Custom 数据不会被当作图像解码。

目前支持矩形嵌套裁剪、统一圆角填充；裁剪不是圆角遮罩，独立四角半径和圆角描边
仍未完整实现。输入框/IME、Dropdown、富文本、拖放数据协议、列表虚拟化、精确旋转遮罩
和自动布局过渡仍属于后续功能。视觉变换与显式 Tween 动画见上文。

## 验证

```powershell
# olib 根目录
odin run tools/check -- -only:kit/ui

# 示例仓库根目录（示例名之后的参数透传给程序）
.\run.bat game_ui
```

运行时需 Foster 的平台动态库（Windows 为 SDL3.dll）。`game_ui` / `ui_gallery` 内嵌共享的
离线中英文 MSDF，不依赖系统字体；`font <图集前缀>` 可指定成对的 PNG＋JSON。

`game_ui` 的交互：点击地面移动角色；点击技能或按 1–6 施放；B 切换背包；
点击格子选择道具；Esc 暂停/继续，暂停菜单中可调音量、切换音乐状态或退出。
这是游戏 UI 演示，角色移动、生命/能量和技能效果用于交互反馈；没有战斗系统或真实音频播放。

`run.bat game_ui shot` 自动渲染并保存 PNG 到示例仓库根目录后退出，可加 `scaled`、`modal`、`scroll` 或 `hud`
（收起背包）。`run.bat game_ui smoke` 会通过真实布局自动依次点击技能、选择道具、暂停、
调滑条、切换开关并返回游戏，使用断言验证状态变化。可与 `scaled` 一起运行。
场景、角色和图标用代码生成；按钮、技能格和背包格使用
示例中的 `src/game_ui/assets/button-skin.png` 图片皮肤，编译时嵌入，无运行目录依赖。

图片按钮可在 `ui_interact` 后按状态选择贴图或 tint，再把文字作为背景容器的子元素：

```odin
decl := ui.ui_nine_slice_decl(&ctx, &button_texture, 128, 12)
decl.id = clay.ID("start")
decl.layout.sizing = {width = clay.SizingFixed(240), height = clay.SizingFixed(52)}
decl.layout.childAlignment = {x = .Center, y = .Center}
if clay.UI()(decl) {
    ui.ui_label(&ctx, &theme, "START")
}
```

第三个参数为原图四边切分宽度（源像素），第四个参数为显示边宽（逻辑像素）。
纹理应先通过 `ImagePremultiply` 转换为预乘 alpha，再上传；透明圆角由 PNG 自身提供。
九宫格目前使用整张纹理和对称边距，普通图集/裁切帧背景使用 `ui_image_decl`。

真实 MSDF 字体的多字号展示在控件展台中：

```powershell
.\run.bat ui_gallery shot msdf
```

它使用离线多通道图集绘制 `AV中文`，覆盖 14/18/36/72px，旧的同值 RGB 环形探针已移除。
库内 CPU 测试使用 Abel 的真实 MSDF 资产，检查通道差异、基线、字距、图集边界与文字布局。
