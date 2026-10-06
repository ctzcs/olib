#+build js

package main

import "core:fmt"
import foster "ofoster:."

foreign import input_regression "input_regression"

@(default_calling_convention = "contextless")
foreign input_regression {
	enabled :: proc() -> bool ---
	step :: proc(phase: i32) ---
	cursor_is :: proc(kind: i32) -> bool ---
	rumble_ok :: proc() -> bool ---
	clipboard_case :: proc(phase: i32) ---
	done :: proc() ---
}

clipboard_phase: int

clipboard_written :: proc(text: string, succeeded: bool) {
	assert(text == "write😀" && succeeded)
	clipboard_phase = 1
}

clipboard_read :: proc(text: string, succeeded: bool) {
	assert(text == "剪贴板😀" && succeeded)
	clipboard_phase = 3
}

clipboard_denied :: proc(text: string, succeeded: bool) {
	assert(text == "" && !succeeded)
	clipboard_phase = 5
}

begin_clipboard_regression :: proc(app: ^foster.App) {
	if !enabled() {
		return
	}
	clipboard_case(0)
	foster.SetClipboardStringAsync(&app.Input, "write😀", clipboard_written)
}

update_clipboard_regression :: proc(app: ^foster.App) {
	update_dialog_regression(app)
	if clipboard_phase == 1 {
		text := foster.GetClipboardString(&app.Input)
		assert(text == "write😀")
		delete(text)
		clipboard_phase = 2
		foster.RequestClipboardString(&app.Input, clipboard_read)
	} else if clipboard_phase == 3 {
		clipboard_case(1)
		clipboard_phase = 4
		foster.RequestClipboardString(&app.Input, clipboard_denied)
	} else if clipboard_phase == 5 {
		clipboard_case(2)
		clipboard_phase = 6
		fmt.println(
			"PASS: asynchronous clipboard UTF-8, cached reads and denied permission callback",
		)
	}
}

verify_web_input :: proc(app: ^foster.App) {
	if !enabled() {
		return
	}
	defer done()
	input := &app.Input
	step(0)
	foster.poll_events(app)
	foster.InputStep(input, foster.Time{Elapsed = 1})
	controller := &input.State.Controllers[0]
	assert(
		controller.Connected &&
		controller.IsGamepad &&
		controller.Name == "Regression 标准手柄",
	)
	assert(controller.Buttons == 15 && controller.Axes == 6)
	assert(
		foster.ControllerPressed(controller, .South) && foster.ControllerDown(controller, .South),
	)
	assert(controller.axis[0] == -.5 && controller.axis[4] == .75)
	foster.Rumble(input, controller.ID, .5, .25, .2)
	assert(rumble_ok())
	step(1)
	foster.poll_events(app)
	foster.InputStep(input, foster.Time{Elapsed = 2})
	assert(
		foster.ControllerReleased(controller, .South) &&
		!foster.ControllerDown(controller, .South),
	)
	assert(controller.axis[0] == .25)
	step(2)
	foster.poll_events(app)
	foster.InputStep(input, foster.Time{Elapsed = 3})
	assert(!controller.Connected)

	foster.StartTextInput(&app.Window)
	step(3)
	foster.poll_events(app)
	foster.InputStep(input, foster.Time{Elapsed = 4})
	assert(input.State.Keyboard.Text == "hello😀中文", input.State.Keyboard.Text)
	foster.StopTextInput(&app.Window)
	step(4)
	foster.poll_events(app)
	foster.InputStep(input, foster.Time{Elapsed = 5})
	assert(input.State.Keyboard.Text == "")

	cursor := foster.CursorMakeSystem(.Pointer)
	image := foster.ImageMake(2, 2, foster.Color{255, 0, 0, 255})
	image_cursor := foster.CursorMakeImage(&image, {0, 0})
	foster.ImageDispose(&image)
	assert(foster.CursorSet(&image_cursor) && cursor_is(3))
	foster.CursorDispose(&image_cursor)
	assert(foster.CursorSet(&cursor) && cursor_is(1))
	foster.SetMouseVisible(&app.Window, false)
	assert(cursor_is(2))
	foster.SetMouseVisible(&app.Window, true)
	assert(cursor_is(1))
	foster.CursorDispose(&cursor)
	assert(cursor_is(0))
	fmt.println(
		"PASS: browser gamepad mapping/transitions/rumble, UTF-8 and IME deduplication, text toggle and cursor lifecycle",
	)
}
