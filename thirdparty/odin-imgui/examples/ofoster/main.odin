package imgui_example_ofoster

// Dear ImGui + ofoster bridge example.
//
// Build & run (Windows, from this example directory):
//   odin build . -collection:olib=..\..\..\.. -out:build\example.exe
//
// or just use run.bat next to this file.

import "core:fmt"

import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import imgui "../.."
import imgui_ofoster "../../imgui_impl_ofoster"

bg_color := [3]f32{0.08, 0.09, 0.12}
show_demo := true
spin := 0.0
icons: imgui_ofoster.Icons

startup :: proc(app: ^foster.App) {
	ok := imgui_ofoster.Init(app)
	if !ok {
		foster.Exit(app)
		return
	}
	// olib icons for IconButton: decode the built-in atlas, keep only what the UI uses
	image, rects, decoded := r2d.builtin_icons_decode()
	if decoded {
		defer delete(image.Pixels)
		defer r2d.kenney_rects_dispose(rects)
		imgui_ofoster.IconsInit(&icons, &app.GraphicsDevice, image, rects^, {"media/play", "media/pause", "ui/settings"}, 40)
	}
	fmt.println("imgui_ofoster: initialized")
}

shutdown :: proc(app: ^foster.App) {
	imgui_ofoster.IconsDispose(&icons)
	imgui_ofoster.Shutdown()
	fmt.println("imgui_ofoster: shut down")
}

update :: proc(app: ^foster.App) {
	dt := app.Time.Delta

	// game-side input, gated behind the UI:
	if !imgui_ofoster.WantCaptureKeyboard() {
		if foster.KeyboardPressed(&app.Input.State.Keyboard, .Escape) {
			foster.Exit(app)
		}
	}
	if !imgui_ofoster.WantCaptureMouse() {
		spin += f64(dt)
	}

	imgui_ofoster.NewFrame(app, dt)
}

render :: proc(app: ^foster.App) {
	// the "scene": just a clear that leaves an open ofoster render pass,
	// which the bridge must close before drawing the UI on top
	color := foster.Color{
		u8(bg_color[0] * 255),
		u8(bg_color[1] * 255),
		u8(bg_color[2] * 255),
		255,
	}
	foster.GraphicsDeviceClear(&app.GraphicsDevice, foster.DrawableTargetFromWindow(&app.Window), color)

	imgui_ofoster.Render(app, build_ui)
}

build_ui :: proc(app: ^foster.App) {
	imgui.Begin("ofoster bridge")
	imgui.Text("Dear ImGui over ofoster (SDL3 GPU)")
	imgui.Text("olib 字体：着色器 · 参数 · 预览")
	if imgui_ofoster.IconButton(&icons, "play", "media/play", "播放") {
		show_demo = true
	}
	imgui.SameLine()
	imgui_ofoster.IconButton(&icons, "settings", "ui/settings")
	imgui.Separator()
	imgui.ColorEdit3("background", &bg_color)
	imgui.Checkbox("Show demo window", &show_demo)
	imgui.Separator()
	imgui.Text("frame %d  dt %.2f ms", app.Time.Frame, app.Time.Delta * 1000)
	if imgui_ofoster.WantCaptureMouse() {
		imgui.Text("wants mouse: YES (game input gated)")
	} else {
		imgui.Text("wants mouse: no")
	}
	if imgui_ofoster.WantCaptureKeyboard() {
		imgui.Text("wants keyboard: YES")
	} else {
		imgui.Text("wants keyboard: no")
	}
	imgui.End()

	if show_demo {
		imgui.ShowDemoWindow(&show_demo)
	}
}

main :: proc() {
	config := foster.DefaultAppConfig("imgui_ofoster_example", 1280, 720)
	config.WindowTitle = "odin-imgui x ofoster"

	app: foster.App
	foster.InitApp(&app, config)
	defer foster.Dispose(&app)

	app.StartupProc = startup
	app.ShutdownProc = shutdown
	app.UpdateProc = update
	app.RenderProc = render

	foster.Run(&app)
}
