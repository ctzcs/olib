#+build js
package main

import "core:fmt"
import "core:strings"
import foster "ofoster:."

foreign import dialog_fixture "input_regression"
@(default_calling_convention = "contextless")
foreign dialog_fixture {
	dialog_case :: proc(phase: i32) ---
	saved_ok :: proc() -> bool ---
}

dialog_phase: int
saved_path: string

dialog_files :: proc(result: foster.DialogResult) {
	assert(!result.Cancelled && len(result.Files) == 2)
	storage := foster.StorageContainer {
		Writable = true,
	}
	data := foster.ReadAllBytes(&storage, result.Files[0])
	assert(len(data) == 3 && data[0] == 0 && data[1] == 255 && data[2] == 128)
	delete(data)
	for path in result.Files {
		assert(foster.Remove(&storage, path))
	}
	dialog_phase = 1
}

dialog_folder :: proc(path: string) {
	assert(path != "")
	storage := foster.StorageContainer {
		Root     = path,
		Writable = true,
	}
	assert(foster.DirectoryExists(&storage, "empty"))
	text := foster.ReadAllText(&storage, "nested/value.txt")
	assert(text == "folder😀")
	delete(text)
	assert(foster.Remove(&storage, ""))
	dialog_phase = 3
}

dialog_saved :: proc(path: string) {
	assert(path != "")
	saved_path, _ = strings.clone(path)
	storage := foster.StorageContainer {
		Writable = true,
	}
	assert(foster.WriteAllText(&storage, path, "first"))
	assert(foster.WriteAllText(&storage, path, "final😀"))
	foster.FlushStorageFileAsync(&storage, path, dialog_flushed)
	dialog_phase = 5
}

dialog_flushed :: proc(succeeded: bool) {
	assert(succeeded && saved_ok())
	dialog_phase = 7
}

dialog_write_denied :: proc(succeeded: bool) {
	assert(!succeeded)
	storage := foster.StorageContainer {
		Writable = true,
	}
	assert(foster.Remove(&storage, saved_path))
	delete(saved_path)
	saved_path = ""
	dialog_phase = 11
}

dialog_cancelled :: proc(result: foster.DialogResult) {
	assert(result.Cancelled && len(result.Files) == 0)
	dialog_phase += 1
}

begin_dialog_regression :: proc(app: ^foster.App) {
	if !enabled() {
		return
	}
	dialog_case(0)
	foster.OpenFileDialog(&app.FileSystem, "Read files", {{"Binary", "*.bin;*.dat"}}, dialog_files)
}

update_dialog_regression :: proc(app: ^foster.App) {
	switch dialog_phase {
	case 1:
		dialog_phase = 2
		foster.OpenFolderDialog(&app.FileSystem, "Read folder", dialog_folder)
	case 3:
		dialog_phase = 4
		foster.SaveFileDialog(&app.FileSystem, "Save file", nil, dialog_saved)
	case 7:
		dialog_case(2)
		dialog_phase = 9
		storage := foster.StorageContainer {
			Writable = true,
		}
		assert(foster.WriteAllText(&storage, saved_path, "denied"))
		foster.FlushStorageFileAsync(&storage, saved_path, dialog_write_denied)
	case 11:
		dialog_case(1)
		dialog_phase = 12
		foster.OpenFileDialog(&app.FileSystem, "Cancel", nil, dialog_cancelled)
	case 13:
		dialog_case(3)
		dialog_phase = 14
		foster.OpenFileDialog(&app.FileSystem, "Unavailable", nil, dialog_cancelled)
	case 15:
		dialog_case(4)
		dialog_phase = 16
		fmt.println(
			"PASS: browser file/folder import, UTF-8 paths, binary snapshots, ordered save flush, write failure, picker cancellation and unavailable API",
		)
	}
}
