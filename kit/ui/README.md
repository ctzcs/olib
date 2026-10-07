# 游戏 UI

Clay 负责布局，`kit/ui` 提供控件、交互与 Foster Batcher 后端。
可运行游戏界面位于 [`examples/game_ui`](../../examples/game_ui)：遗迹场景上的生命/能量 HUD、
带冷却遮罩的技能栏、格子背包和暂停菜单。它使用同一套布局与交互，游戏皮肤在示例中定义。
原来的设置页和控件验收示例保留在 [`examples/ui_gallery`](../../examples/ui_gallery)。

## 最小帧流程

初始化一次 `ui_init(&ctx, width, height)`，注册字体；退出时先释放 UI，再释放字体、
贴图和 GraphicsDevice。`UI_Context` 必须保持地址稳定，不要按值复制。

```odin
// 初始化：font 与 texture 由资产层提供，存活到 ui_dispose 之后。
ui.ui_init(&ctx, 1280, 720)
theme := ui.UI_THEME_DARK
theme.body_font_id = u16(ui.ui_register_font(&ctx, &font, texture, .Bitmap))

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

foster.BatcherClear(&batcher)
ui.ui_draw(&ctx, &batcher) // end + translate + render；复用操作缓冲
capture := ui.ui_input_capture(&ctx)
// 根据 capture.pointer / capture.keyboard，决定是否将本帧输入交给游戏。
foster.BatcherRender(&batcher, target)
```

需要自定义渲染时，可继续使用 `ui_end → ui_translate → ui_render`；`ui_translate`
的结果由调用者 `delete`。`ui_translate_into` 可以复用自有缓冲。
不要在 `ui_end` 之后再调用 `ui_draw`，它会重复结束布局。

## 位图字体烘焙

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
- `ui_register_font(..., .MSDF)`：真实距离场图集；使用字体的 `DistanceRange`
  和设备默认 MSDF 材质。不同字体会分别保留材质参数。GraphicsDevice 必须先初始化。
- 字体元数据与 GPU 纹理由调用方持有，UI 只释放自己的池、圆角纹理和材质副本。
  只在帧外注册字体；注册会清除 Clay 的文本测量缓存。
- 中文字距按 Unicode 码点计算；需要图集本身包含相应字形。当前没有 fallback 字体、
  动态汉字图集、字形塑形或 IME。文本换行由 Clay 处理，并非完整的多语言排版系统。
- `ui_set_viewport` 统一处理绘制、命中与裁剪的缩放/偏移。高 DPI 窗口要先把窗口鼠标坐标
  转成渲染目标像素，示例已演示。`ui_set_dimensions` 直接设置逻辑尺寸。
- 渲染恢复 Batcher 的矩阵、采样、混合、模式、材质及裁剪状态。继承外部裁剪区域，
  使用屏幕 UI 变换，不叠加世界相机矩阵；用于 UI 的 Batcher 应使用普通默认材质。
- 同一线程可逐帧切换多个 context，但不可交错 begin/end 或并发操作 Clay。
- `error_count / last_error` 记录 Clay 错误；`pool_overflow` 报告本帧文本/图像池超限。
  默认每帧各 1024 个，溢出元素不显示。运行时字符串要存活到渲染结束，
  帧临时分配器可用于 `fmt.aprintf`。

## 兼容性与边界

按钮/开关默认触发时机由按下改为松开；需要原语义时传 `.Press`。
`ui_panel_decl` 默认改为竖排并占满可用宽度，可用 `width` 参数固定宽度。
原始 Clay `.Image.imageData` 仍接受 `^foster.Texture`，UV 已修复为完整图像。
`ui_image` 使用自己的 Custom 命令；其他 Custom 数据不会被当作图像解码。

目前支持矩形嵌套裁剪、统一圆角填充；裁剪不是圆角遮罩，独立四角半径和圆角描边
仍未完整实现。输入框/IME、Dropdown、富文本、拖放数据协议、列表虚拟化和过渡动画
仍属于后续功能。

## 验证

```powershell
odin test kit/ui -collection:olib=.
odin build examples/game_ui -collection:olib=. -out:game_ui.exe
```

运行时需 Foster 的平台动态库（Windows 为 SDL3.dll）。Windows 自动尝试系统字体；
其他平台或自定义字体可传 `font <ttf路径>`。示例使用 ASCII 位图字体，测试中另有中文测量用例。

`game_ui.exe` 的交互：点击地面移动角色；点击技能或按 1–6 施放；B 切换背包；
点击格子选择道具；Esc 暂停/继续，暂停菜单中可调音量、切换音乐状态或退出。
这是游戏 UI 演示，角色移动、生命/能量和技能效果用于交互反馈；没有战斗系统或真实音频播放。

`game_ui.exe shot` 自动渲染并保存 PNG 后退出，可加 `scaled`、`modal`、`scroll` 或 `hud`
（收起背包）。`game_ui.exe smoke` 会通过真实布局自动依次点击技能、选择道具、暂停、
调滑条、切换开关并返回游戏，使用断言验证状态变化。可与 `scaled` 一起运行。
场景、角色和图标用代码生成；按钮、技能格和背包格使用
`examples/game_ui/assets/button-skin.png` 图片皮肤，编译时嵌入，无运行目录依赖。

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

原来的距离场渲染探针在控件展台中：

```powershell
odin build examples/ui_gallery -collection:olib=. -out:ui_gallery.exe
ui_gallery.exe shot msdf
```

它使用解析环形距离场编码到 RGB，验证 18/36/72px 下的解码与材质切换，
不是完整 MSDF 字体资产的视觉回归测试。
