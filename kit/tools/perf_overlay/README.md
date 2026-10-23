# 悬浮性能面板

`olib:kit/tools/perf_overlay` 在画面角落叠加一个半透明面板：

- FPS 与平均帧时间（按 60 FPS 预算着色：绿 ≤ 1 帧，黄 ≤ 2 帧，红更慢）
- 最近 240 帧的 min / max 与 1% low FPS
- 最近 120 帧的帧时间柱状曲线，细线为 16.7 ms；纵轴至少 33 ms，有更长的帧时自动压缩
- [core/profiler](../../../core/profiler/profiler.odin) 作用域按每帧耗时降序的前 8 项（ms/frame 与每帧调用次数）

数字每 0.5 秒刷新一次，避免逐帧跳动。面板是被动浮层：不读取窗口输入、不捕获指针，不影响宿主的输入分配。

面板有两种画法，采样（`Overlay` 与 `frame`）共用，宿主按自己有没有 ImGui 选一种接入：

- **kit/ui 版**（本包 `init` / `draw`）：自带 Render2D 与 UI 上下文，借用宿主的 MSDF 字体，不依赖 ImGui。
  新游戏模板的开发入口 `src/editor/main.odin` 默认接的是这一版，按 F3 切换。
- **ImGui 版**（子包 [`perf_overlay/imgui`](imgui/perf_imgui.odin)）：在宿主已有的 ImGui 帧里提交一个窗口，
  字体、样式与缩放跟随宿主 ImGui。适合已经有 ImGui 的编辑器或开发工具；ImGui 只用于桌面开发入口，
  不进入发布与 Web 构建（见 [新项目约定](../../../prompts/new-project.md)）。

## 接入

### kit/ui 版

```odin
import perf "olib:kit/tools/perf_overlay"

// 地址稳定的宿主字段；font / texture 为宿主已加载的 MSDF 字体，借用至 dispose。
ok := perf.init(&app_state.perf, device, &font, font_texture)
app_state.perf.corner = .Top_Right // 可选：Top_Left / Bottom_Right / Bottom_Left

// Update：每帧都要记录，隐藏时也一样，打开时才有完整历史。按键由宿主自己读。
if foster.KeyboardPressed(k, .F3) do app_state.perf.visible = !app_state.perf.visible
perf.frame(&app_state.perf, app.Time.Delta)

// Render：放在所有场景与 UI 之后，scale 与宿主 UI 比例一致。
perf.draw(&app_state.perf, target, ui_scale)

// 关闭时先释放面板，再释放字体纹理与 GraphicsDevice。
perf.dispose(&app_state.perf)
```

### ImGui 版

```odin
import perf "olib:kit/tools/perf_overlay"
import perf_imgui "olib:kit/tools/perf_overlay/imgui"

// 不调用 perf.init；Overlay 零值即可采样。宿主已按 imgui_impl_ofoster 初始化 ImGui。
app_state.perf.corner = .Top_Right

// Update：同上，每帧 perf.frame，按键由宿主自己读（先看 WantCaptureKeyboard / WantTextInput）。
perf.frame(&app_state.perf, app.Time.Delta)

// Render：在 BeginRender 与 EndRender 之间，放在其他窗口之后。
if imgui_foster.BeginRender(app) {
	// ...宿主自己的窗口
	perf_imgui.draw(&app_state.perf)
	imgui_foster.EndRender(app)
}

// 关闭时仍要 perf.dispose（释放作用域名副本），与 ImGui Shutdown 先后无关。
perf.dispose(&app_state.perf)
```

ImGui 窗口名为 `perf_imgui.WINDOW`，贴在主视口工作区的 `corner` 角，不接收鼠标、不抢焦点、不停靠、
不写入 ini；曲线尺寸随 ImGui 字号缩放。

### 作用域

想看 CPU 各阶段耗时，在代码里标作用域，面板自动列出：

```odin
import profiler "olib:core/profiler"

profiler.profile_init() // 启动时一次
update :: proc(...) {
	defer profiler.profile_scope("update")
	// ...
}
```

## 说明与限制

- `frame` 传入的是整帧间隔，包含垂直同步等待；开着 VSync 时 FPS 会贴在刷新率上，此时看各作用域耗时判断余量。
- 不统计 GPU 时间与 Draw 数量；Foster 目前没有 GPU 计时查询。
- 作用域表读取的是**同一模块**里的 `profiler.profile_stats`。热重载 DLL 与常驻 exe 各有一份全局表：
  模板中面板在常驻的 `src/editor` 里，所以只显示 exe 内标记的作用域；要看游戏 DLL 内的作用域，
  把面板放进 core_editor（那里已有 ImGui 上下文，可直接用 ImGui 版），或在 DLL 内调用 `profile_dump`。
  放进 DLL 时 `Overlay` 随模块重建，热重载后帧历史从头记录。作用域名在面板内复制保存，DLL 卸载后不会悬空。
- 面板在最终像素尺寸绘制，不随低分辨率场景放大，见 [UI 像素与采样约定](../../ui/README.md#最终像素采样与清晰度验收)。
- 面板文字为英文与数字，字体图集需含 ASCII。
