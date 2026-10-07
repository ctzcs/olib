package imgui_impl_ofoster

// Dear ImGui bridge for ofoster (Odin port of Foster, SDL3 GPU based).
//
// ofoster owns the window, the input state and the frame's command buffer, so
// this backend does not talk to SDL events itself. Instead it composes the
// generated imgui_impl_sdlgpu3 renderer backend (ofoster renders through
// SDL3 GPU) with polled input feeding from app.Input, following the same
// proven integration used by the tinyglade editor:
//
//   - Init      once after foster.InitApp / in StartupProc
//   - NewFrame  every update  (feeds io from app.Input.State)
//   - Render    every render  (ends ofoster's open pass, builds + draws UI
//               into the swapchain on top of the scene)
//   - Shutdown  before foster.Dispose
//
// Usage:
//
//   import imgui "../.."
//   import imgui_ofoster "../../imgui_impl_ofoster"
//   import foster "olib:foster"
//
//   startup :: proc(app: ^foster.App) {
//       imgui_ofoster.Init(app)
//   }
//   update :: proc(app: ^foster.App) {
//       // gate game input first:
//       if !imgui_ofoster.WantCaptureMouse() { handle_camera(app) }
//       imgui_ofoster.NewFrame(app, app.Time.Delta)
//   }
//   render :: proc(app: ^foster.App) {
//       draw_scene(app)
//       imgui_ofoster.Render(app, build_ui) // build_ui :: proc(app: ^foster.App)
//   }
//
// Requires the `olib` package collection at build time:
//   odin build . -collection:olib=<path to olib>
//
// Notes / limitations:
//   - single window, no multi-viewport support (ofoster owns the window)
//   - gamepad navigation is not fed (keyboard + mouse only)

import "core:c"
import "core:fmt"

import imgui "../"
import imgui_sdlgpu3 "../imgui_impl_sdlgpu3"
import foster "olib:foster"
import sdl "vendor:sdl3"

Style :: enum {
	Dark,
	Light,
	Classic,
}

// package state; ofoster apps are single-window so one instance is enough
app:            ^foster.App
ready:          bool
display_size:   [2]f32 // window size in points, as seen during the last render
framebuffer_scale: [2]f32

// ---- lifecycle ----------------------------------------------------------------

Init :: proc(owner: ^foster.App, config_flags: imgui.ConfigFlags = {.NavEnableKeyboard, .DockingEnable}, style_kind: Style = .Dark) -> bool {
	if ready {
		return true
	}
	app = owner

	imgui.CHECKVERSION()
	imgui.CreateContext()

	io := imgui.GetIO()
	io.ConfigFlags += config_flags
	io.BackendPlatformName = "imgui_impl_ofoster"
	io.BackendFlags |= {.HasMouseCursors}

	switch style_kind {
	case .Dark:    imgui.StyleColorsDark()
	case .Light:   imgui.StyleColorsLight()
	case .Classic: imgui.StyleColorsClassic()
	}

	// DPI: scale style + fonts from the monitor the window is on
	scale := window_content_scale(owner)
	style := imgui.GetStyle()
	imgui.Style_ScaleAllSizes(style, scale)
	style.FontScaleDpi = scale
	io.ConfigDpiScaleFonts = true

	pio := imgui.GetPlatformIO()
	pio.Platform_SetClipboardTextFn = set_clipboard_text
	pio.Platform_GetClipboardTextFn = get_clipboard_text

	device := &owner.GraphicsDevice
	init_info := imgui_sdlgpu3.InitInfo{
		Device            = device.Device,
		ColorTargetFormat = device.SwapchainFormat,
		MSAASamples       = ._1, // UI renders straight into the swapchain
		// Only used in multi-viewports mode, which this bridge does not enable:
		SwapchainComposition = .SDR,
		PresentMode          = .VSYNC,
	}
	if !imgui_sdlgpu3.Init(&init_info) {
		fmt.eprintln("imgui_impl_ofoster: sdlgpu3 backend init failed:", string(sdl.GetError()))
		imgui.DestroyContext(nil)
		app = nil
		return false
	}
	// build the pipeline eagerly so a format/shader mismatch surfaces at startup
	imgui_sdlgpu3.CreateDeviceObjects()

	ready = true
	return true
}

Shutdown :: proc() {
	if !ready {
		return
	}
	for &cursor in mouse_cursors {
		if cursor != nil {
			sdl.DestroyCursor(cursor)
			cursor = nil
		}
	}
	last_mouse_cursor = .COUNT
	last_draw_cursor = false
	imgui_sdlgpu3.Shutdown()
	imgui.DestroyContext(nil)
	ready = false
	app = nil
}

// ---- update phase: input feeding ----------------------------------------------

// NewFrame feeds ImGui's IO from ofoster's polled input state. Call it every
// update, BEFORE the game consumes the same input (so WantCaptureMouse and
// friends gate it), and before Render. dt <= 0 falls back to app.Time.Delta.
NewFrame :: proc(owner: ^foster.App, dt: f32 = -1) {
	if !ready {
		return
	}
	io := imgui.GetIO()
	mouse := &owner.Input.State.Mouse
	kb := &owner.Input.State.Keyboard

	frame_dt := dt
	if frame_dt <= 0 {
		frame_dt = owner.Time.Delta
	}
	io.DeltaTime = max(frame_dt, 1.0 / 1000.0)

	// ofoster zeroes SwapchainWidth/Height in end_frame, so the update phase
	// must use the sizes cached during the last render (queried live the very
	// first time, before any render has happened)
	if display_size[0] <= 0 || display_size[1] <= 0 {
		cw, ch: c.int
		if owner.Window.Handle != nil && sdl.GetWindowSize(owner.Window.Handle, &cw, &ch) {
			display_size = {f32(cw), f32(ch)}
		}
	}
	io.DisplaySize = {display_size[0], display_size[1]}
	io.DisplayFramebufferScale = {framebuffer_scale[0], framebuffer_scale[1]}

	// focus (polled; ImGui only needs the transitions)
	if owner.Window.Handle != nil {
		focused := .INPUT_FOCUS in sdl.GetWindowFlags(owner.Window.Handle)
		imgui.IO_AddFocusEvent(io, focused)
	}

	// mouse: ofoster reports points, matching io.DisplaySize above
	imgui.IO_AddMousePosEvent(io, mouse.Position.X, mouse.Position.Y)
	if mouse.Wheel.X != 0 || mouse.Wheel.Y != 0 {
		imgui.IO_AddMouseWheelEvent(io, mouse.Wheel.X, mouse.Wheel.Y)
	}
	// send the full level (down AND up): only feeding "true" while held leaves
	// ImGui thinking the button never releases, which breaks all clicking
	imgui.IO_AddMouseButtonEvent(io, 0, foster.MouseDown(mouse, .Left))
	imgui.IO_AddMouseButtonEvent(io, 1, foster.MouseDown(mouse, .Right))
	imgui.IO_AddMouseButtonEvent(io, 2, foster.MouseDown(mouse, .Middle))

	// modifiers: ImGui wants them both as individual keys and aggregated
	for entry in key_map {
		imgui.IO_AddKeyEvent(io, entry.ik, foster.Down(kb, entry.key))
	}
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Ctrl,   foster.Down(kb, .LeftControl) || foster.Down(kb, .RightControl))
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Shift,  foster.Down(kb, .LeftShift)   || foster.Down(kb, .RightShift))
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Alt,    foster.Down(kb, .LeftAlt)     || foster.Down(kb, .RightAlt))
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Super,  foster.Down(kb, .LeftOS)      || foster.Down(kb, .RightOS))

	// text typed during this update
	for r in kb.Text {
		imgui.IO_AddInputCharacter(io, u32(r))
	}
}

// Read these after NewFrame to decide whether the game should ignore input.
// They reflect the last rendered frame (one frame of latency).
WantCaptureMouse :: proc() -> bool {
	return ready && imgui.GetIO().WantCaptureMouse
}

WantCaptureKeyboard :: proc() -> bool {
	return ready && imgui.GetIO().WantCaptureKeyboard
}

// ---- render phase -------------------------------------------------------------

// Render runs one full ImGui frame on top of whatever is already in the
// swapchain. Call it from the app's RenderProc after drawing the scene.
// build_ui (optional) submits widgets, e.g. proc(app: ^foster.App) {...}.
Render :: proc(owner: ^foster.App, build_ui: foster.AppCallback = nil) {
	if !ready {
		return
	}
	device := &owner.GraphicsDevice
	if device.CommandBuffer == nil || device.SwapchainTexture == nil {
		return
	}

	io := imgui.GetIO()

	// cache the display geometry for the next update-phase NewFrame
	cw, ch: c.int
	if owner.Window.Handle != nil && sdl.GetWindowSize(owner.Window.Handle, &cw, &ch) && cw > 0 && ch > 0 {
		display_size = {f32(cw), f32(ch)}
		framebuffer_scale = {
			f32(device.SwapchainWidth)  / f32(cw),
			f32(device.SwapchainHeight) / f32(ch),
		}
		io.DisplaySize = {display_size[0], display_size[1]}
		io.DisplayFramebufferScale = {framebuffer_scale[0], framebuffer_scale[1]}
	}

	// ofoster keeps its render pass open while drawing; ImGui opens its own
	// pass below, so close the current one (at the ofoster level, which also
	// resets its cached pass/pipeline state)
	foster.end_render_pass(device)

	imgui_sdlgpu3.NewFrame()
	imgui.NewFrame()

	if build_ui != nil {
		build_ui(owner)
	}

	update_mouse_cursor()
	imgui.Render()
	draw_data := imgui.GetDrawData()
	if draw_data.DisplaySize.x <= 0 || draw_data.DisplaySize.y <= 0 {
		return
	}

	imgui_sdlgpu3.PrepareDrawData(draw_data, device.CommandBuffer)
	target := sdl.GPUColorTargetInfo{
		texture = device.SwapchainTexture,
		mip_level = 0,
		layer_or_depth_plane = 0,
		load_op = .LOAD, // scene is already in the swapchain
		store_op = .STORE,
		cycle = false,
	}
	pass := sdl.BeginGPURenderPass(device.CommandBuffer, &target, 1, nil)
	if pass != nil {
		imgui_sdlgpu3.RenderDrawData(draw_data, device.CommandBuffer, pass, nil)
		sdl.EndGPURenderPass(pass)
	}
}

// ---- key map -------------------------------------------------------------------

KeyMapEntry :: struct { key: foster.Keys, ik: imgui.Key }

key_map := []KeyMapEntry{
	// letters
	{.A, .A}, {.B, .B}, {.C, .C}, {.D, .D}, {.E, .E}, {.F, .F}, {.G, .G},
	{.H, .H}, {.I, .I}, {.J, .J}, {.K, .K}, {.L, .L}, {.M, .M}, {.N, .N},
	{.O, .O}, {.P, .P}, {.Q, .Q}, {.R, .R}, {.S, .S}, {.T, .T}, {.U, .U},
	{.V, .V}, {.W, .W}, {.X, .X}, {.Y, .Y}, {.Z, .Z},
	// digits
	{.D1, ._1}, {.D2, ._2}, {.D3, ._3}, {.D4, ._4}, {.D5, ._5},
	{.D6, ._6}, {.D7, ._7}, {.D8, ._8}, {.D9, ._9}, {.D0, ._0},
	// punctuation
	{.Minus, .Minus}, {.Equals, .Equal}, {.LeftBracket, .LeftBracket},
	{.RightBracket, .RightBracket}, {.Backslash, .Backslash},
	{.Semicolon, .Semicolon}, {.Apostrophe, .Apostrophe},
	{.Tilde, .GraveAccent}, {.Comma, .Comma}, {.Period, .Period}, {.Slash, .Slash},
	// control
	{.Tab, .Tab}, {.Enter, .Enter}, {.Escape, .Escape}, {.Backspace, .Backspace},
	{.Space, .Space}, {.Capslock, .CapsLock},
	{.Insert, .Insert}, {.Delete, .Delete}, {.Home, .Home}, {.End, .End},
	{.PageUp, .PageUp}, {.PageDown, .PageDown},
	{.Right, .RightArrow}, {.Left, .LeftArrow}, {.Down, .DownArrow}, {.Up, .UpArrow},
	{.PrintScreen, .PrintScreen}, {.ScrollLock, .ScrollLock},
	{.Pause, .Pause}, {.Numlock, .NumLock}, {.Application, .Menu},
	// modifiers
	{.LeftControl, .LeftCtrl}, {.LeftShift, .LeftShift}, {.LeftAlt, .LeftAlt}, {.LeftOS, .LeftSuper},
	{.RightControl, .RightCtrl}, {.RightShift, .RightShift}, {.RightAlt, .RightAlt}, {.RightOS, .RightSuper},
	// function keys
	{.F1, .F1}, {.F2, .F2}, {.F3, .F3}, {.F4, .F4}, {.F5, .F5}, {.F6, .F6},
	{.F7, .F7}, {.F8, .F8}, {.F9, .F9}, {.F10, .F10}, {.F11, .F11}, {.F12, .F12},
	{.F13, .F13}, {.F14, .F14}, {.F15, .F15}, {.F16, .F16}, {.F17, .F17}, {.F18, .F18},
	{.F19, .F19}, {.F20, .F20}, {.F21, .F21}, {.F22, .F22}, {.F23, .F23}, {.F24, .F24},
	// keypad
	{.KeypadDivide, .KeypadDivide}, {.KeypadMultiply, .KeypadMultiply},
	{.KeypadMinus, .KeypadSubtract}, {.KeypadPlus, .KeypadAdd},
	{.KeypadEnter, .KeypadEnter}, {.KeypadEquals, .KeypadEqual},
	{.KeypadPeroid, .KeypadDecimal},
	{.Keypad0, .Keypad0}, {.Keypad1, .Keypad1}, {.Keypad2, .Keypad2},
	{.Keypad3, .Keypad3}, {.Keypad4, .Keypad4}, {.Keypad5, .Keypad5},
	{.Keypad6, .Keypad6}, {.Keypad7, .Keypad7}, {.Keypad8, .Keypad8},
	{.Keypad9, .Keypad9},
}

// ---- mouse cursor --------------------------------------------------------------

mouse_cursors: [imgui.MouseCursor.COUNT]^sdl.Cursor
last_mouse_cursor: imgui.MouseCursor = .COUNT
last_draw_cursor: bool

// indexed by imgui.MouseCursor (Arrow..NotAllowed, None is handled by hiding)
mouse_cursor_map := [imgui.MouseCursor.COUNT]sdl.SystemCursor{
	.DEFAULT,      // Arrow
	.TEXT,         // TextInput
	.MOVE,         // ResizeAll
	.NS_RESIZE,    // ResizeNS
	.EW_RESIZE,    // ResizeEW
	.NESW_RESIZE,  // ResizeNESW
	.NWSE_RESIZE,  // ResizeNWSE
	.POINTER,      // Hand
	.WAIT,         // Wait
	.PROGRESS,     // Progress
	.NOT_ALLOWED,  // NotAllowed
}

// honors the cursor ImGui asks for (GetMouseCursor) using SDL system cursors,
// created lazily and cached until Shutdown
@(private)
update_mouse_cursor :: proc() {
	if !ready || app == nil || app.Window.Handle == nil {
		return
	}
	io := imgui.GetIO()
	cursor := imgui.GetMouseCursor()
	draw := io.MouseDrawCursor
	if cursor == last_mouse_cursor && draw == last_draw_cursor {
		return
	}
	last_mouse_cursor = cursor
	last_draw_cursor = draw

	if draw || cursor == .None {
		_ = sdl.HideCursor()
		return
	}
	_ = sdl.ShowCursor()
	if int(cursor) >= 0 && cursor < .COUNT {
		if mouse_cursors[cursor] == nil {
			mouse_cursors[cursor] = sdl.CreateSystemCursor(mouse_cursor_map[cursor])
		}
		if mouse_cursors[cursor] != nil {
			_ = sdl.SetCursor(mouse_cursors[cursor])
		}
	}
}

// ---- clipboard -------------------------------------------------------------------

clipboard_buffer: [4096]u8

@(private)
get_clipboard_text :: proc "c" (ctx: ^imgui.Context) -> cstring {
	// "c" procs have no Odin context, so talk to SDL directly instead of
	// going through foster.GetClipboardString
	text := sdl.GetClipboardText()
	if text == nil {
		return ""
	}
	n := 0
	for n < len(clipboard_buffer) - 1 && text[n] != 0 {
		clipboard_buffer[n] = text[n]
		n += 1
	}
	clipboard_buffer[n] = 0
	return cstring(&clipboard_buffer[0])
}

@(private)
set_clipboard_text :: proc "c" (ctx: ^imgui.Context, text: cstring) {
	_ = sdl.SetClipboardText(text)
}

// ---- helpers ---------------------------------------------------------------------

@(private)
window_content_scale :: proc(owner: ^foster.App) -> f32 {
	scale := f32(0)
	if owner.Window.Handle != nil {
		scale = sdl.GetDisplayContentScale(sdl.GetDisplayForWindow(owner.Window.Handle))
	}
	if scale <= 0 {
		scale = sdl.GetDisplayContentScale(sdl.GetPrimaryDisplay())
	}
	if scale <= 0 {
		scale = 1
	}
	return scale
}
