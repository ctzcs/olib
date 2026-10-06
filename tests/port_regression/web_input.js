"use strict";

// This fixture replaces device polling only on the explicit input-test page.
(() => {
	const enabled = new URLSearchParams(location.search).has("input-tests");
	const original = Object.getOwnPropertyDescriptor(navigator, "getGamepads");
	let devices = [];
	let rumble = null;
	const originalClipboard = Object.getOwnPropertyDescriptor(navigator, "clipboard");
	const clipboardCase = phase => {
		if (phase === 2) {
			if (originalClipboard) Object.defineProperty(navigator, "clipboard", originalClipboard);
			else delete navigator.clipboard;
			return;
		}
		Object.defineProperty(navigator, "clipboard", {
			configurable: true,
			value: {
				writeText: () => Promise.resolve(),
				readText: () => phase === 0 ? Promise.resolve("剪贴板😀") : Promise.reject(new Error("denied")),
			},
		});
	};
	const device = {
		index: 0, id: "Regression 标准手柄", mapping: "standard", connected: true,
		buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })),
		axes: [0, 0, 0, 0],
		vibrationActuator: { playEffect(effect, options) { rumble = options; return Promise.resolve(); } },
	};
	if (enabled) Object.defineProperty(navigator, "getGamepads", { configurable: true, value: () => devices });
	const step = phase => {
		const target = document.querySelector('textarea[aria-label="Game text input"]');
		if (phase === 0) {
			devices = [device];
			device.buttons[0] = { pressed: true, value: 1 };
			device.buttons[6] = { pressed: true, value: .75 };
			device.axes[0] = -.5;
		} else if (phase === 1) {
			device.buttons[0] = { pressed: false, value: 0 };
			device.axes[0] = .25;
		} else if (phase === 2) {
			devices = [];
		} else if (phase === 3) {
			target.value = "hello😀";
			target.dispatchEvent(new InputEvent("input", { data: "hello😀", inputType: "insertText" }));
			target.dispatchEvent(new CompositionEvent("compositionstart"));
			target.value = "中文";
			target.dispatchEvent(new InputEvent("input", { data: "中文", isComposing: true }));
			target.dispatchEvent(new CompositionEvent("compositionend", { data: "中文" }));
			// Some browsers send a final non-composing input after compositionend.
			target.value = "中文";
			target.dispatchEvent(new InputEvent("input", { data: "中文", inputType: "insertFromComposition" }));
		} else if (phase === 4) {
			target.value = "ignored";
			target.dispatchEvent(new InputEvent("input", { data: "ignored", inputType: "insertText" }));
		}
		window.__fosterDebug.pollGamepads();
	};
	const pickerNames = ["showOpenFilePicker", "showDirectoryPicker", "showSaveFilePicker"];
	const originalPickers = pickerNames.map(name => Object.getOwnPropertyDescriptor(window, name));
	let savedBytes = null;
	let denyWrite = false;
	const fileHandle = (name, contents) => ({
		kind: "file", name,
		async getFile() { return new File([contents], name); },
		async createWritable() {
			if (denyWrite) throw new Error("write denied");
			let data;
			return {
				async write(bytes) { data = bytes.slice(); },
				async close() { savedBytes = data; },
				async abort() {},
			};
		},
	});
	const directoryHandle = (name, children) => ({
		kind: "directory", name,
		async *values() { yield* children; },
	});
	const dialogCase = phase => {
		if (phase === 4) {
			pickerNames.forEach((name, i) => {
				if (originalPickers[i]) Object.defineProperty(window, name, originalPickers[i]);
				else delete window[name];
			});
			return;
		}
		denyWrite = phase === 2;
		Object.defineProperty(window, "showOpenFilePicker", { configurable: true, value: phase === 3 ? undefined : async options => {
			if (phase === 1) throw new DOMException("cancelled", "AbortError");
			if (!options.multiple || options.types[0].accept["application/octet-stream"][0] !== ".bin") throw new Error("filter mismatch");
			return [fileHandle("读入.bin", new Uint8Array([0, 255, 128])), fileHandle("second.bin", "second")];
		} });
		Object.defineProperty(window, "showDirectoryPicker", { configurable: true, value: async () => directoryHandle("目录", [
			directoryHandle("empty", []), directoryHandle("nested", [fileHandle("value.txt", "folder😀")]),
		]) });
		Object.defineProperty(window, "showSaveFilePicker", { configurable: true, value: async () => fileHandle("保存.txt", "") });
	};

	window.FOSTER_EXTRA_IMPORTS = {
		input_regression: {
			enabled: () => enabled,
			step,
			cursor_is: kind => kind === 3 ? document.getElementById("foster").style.cursor.startsWith("url(") : document.getElementById("foster").style.cursor === ["default", "pointer", "none"][kind],
			clipboard_case: clipboardCase,
			dialog_case: dialogCase,
			saved_ok: () => savedBytes && new TextDecoder().decode(savedBytes) === "final😀",
			rumble_ok: () => rumble?.strongMagnitude === .5 && rumble?.weakMagnitude === .25 && rumble?.duration === 200,
			done() {
				if (original) Object.defineProperty(navigator, "getGamepads", original);
				else delete navigator.getGamepads;
			},
		},
	};
})();
