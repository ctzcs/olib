# 悬浮性能面板

`olib:kit/tools/perf_overlay` 在画面角落叠加一个半透明面板：

- FPS 与平均帧时间（按 60 FPS 预算着色：绿 ≤ 1 帧，黄 ≤ 2 帧，红更慢）
- 最近 240 帧的 min / max 与 1% low FPS
- 最近 120 帧的帧时间柱状曲线，细线为 16.7 ms；纵轴至少 33 ms，有更长的帧时自动压缩
- [core/profiler](../../../core/profiler/profiler.odin) 作用域按每帧耗时降序的前 8 项（ms/frame 与每帧调用次数）

数字每 0.5 秒刷新一次，避免逐帧跳动。面板是被动浮层：不读取窗口输入、不捕获指针，不影响宿主的输入分配。
新游戏模板的开发入口 `src/editor/main.odin` 已接入，按 F3 切换。

## 接入

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
  把面板放进 core_editor，或在 DLL 内调用 `profile_dump`。作用域名在面板内复制保存，DLL 卸载后不会悬空。
- 面板在最终像素尺寸绘制，不随低分辨率场景放大，见 [UI 像素与采样约定](../../ui/README.md#最终像素采样与清晰度验收)。
- 面板文字为英文与数字，字体图集需含 ASCII。
