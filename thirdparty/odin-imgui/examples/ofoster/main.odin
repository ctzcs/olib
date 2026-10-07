package imgui_example_ofoster

// Dear ImGui + ofoster bridge example.
//
// Build & run (Windows, from this example directory):
//   odin build . -collection:olib=..\..\..\.. -out:build\example.exe
//
// or just use run.bat next to this file.

import "core:fmt"

import foster "olib:foster"
import imgui "../.."
import imgui_ofoster "../../imgui_impl_ofoster"

bg_color := [3]f32{0.08, 0.09, 0.12}
show_demo := true
spin := 0.0

startup :: proc(app: ^foster.App) {
	ok := imgui_ofoster.Init(app, {.NavEnableKeyboard, .DockingEnable}, .Dark)
	if !ok {
		foster.Exit(app)
		return
	}
	fmt.println("imgui_ofoster: initialized")
}

shutdown :: proc(app: ^foster.App) {
	imgui_ofoster.Shutdown()
	fmt.println("imgui_ofoster: shut down")
}

update :: proc(app: ^foster.App) {
	dt := app.Time.Delta

	// game-side input, gated behind the UI:
	if !imgui_ofoster.WantCaptureKeyboard() {
		if foster.Pressed(&app.Input.State.Keyboard, .Escape) {
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
