#+build js
package main

import "core:fmt"
import foster "olib:foster"

app: foster.App
tested: bool

startup :: proc(app: ^foster.App) {
	verify_common()
	verify_web_input(app)
	begin_clipboard_regression(app)
	begin_dialog_regression(app)
	storage := foster.StorageContainer {
		Root     = "/ofoster-port-regression",
		Writable = true,
	}
	verify_zip(&storage)
	assert(foster.CreateDirectory(&storage, "empty"))
	assert(foster.DirectoryExists(&storage, "empty"))
	assert(foster.WriteAllText(&storage, "nested/value.txt", "abc"))
	assert(foster.DirectoryExists(&storage, "nested"))
	names := foster.EnumerateDirectory(&storage, "")
	assert(len(names) == 2)
	for name in names {
		delete(name)
	}
	delete(names)
	assert(foster.ReadAllText(&storage, "nested/value.txt", context.temp_allocator) == "abc")
	assert(foster.Remove(&storage, "nested") && !foster.Exists(&storage, "nested/value.txt"))
	assert(foster.Remove(&storage, "empty"))
	fmt.println(
		"PASS: Web storage directory creation, enumeration, persistence and recursive removal",
	)
}

flush_web :: proc(device: ^foster.GraphicsDevice) {
	foster.end_render_pass(device)
}

render :: proc(app: ^foster.App) {
	if tested {
		return
	}
	verify_graphics(&app.GraphicsDevice, flush_web)
	tested = true
}

main :: proc() {
	foster.InitApp(&app, foster.DefaultAppConfig("OFoster Port Regression", 128, 128))
	app.StartupProc = startup
	app.UpdateProc = update_clipboard_regression
	app.RenderProc = render
	foster.Run(&app)
}
