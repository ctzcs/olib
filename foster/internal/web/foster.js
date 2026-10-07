"use strict";

// OFoster Web 桥 —— Odin 侧 foreign import "foster_web" 的 JS 实现(web.odin)。
// 用法(与 odin.js 同目录加载):
//   <script>window.FOSTER_WASM = "game.wasm";</script>
//   <script src="odin.js"></script>
//   <script src="foster.js"></script>
// 可选: window.FOSTER_CANVAS_ID (默认 "foster"), window.FOSTER_LOG_ID (默认 "foster-log")。
//
// 手动实例化 wasm(不用 odin.runWasm): 需要持有 memory 以便 rawptr 传参,
// 以及直接驱动导出的 foster_step。模式与 vehicles/web-spike 一致。
//
// M1: WebGL2 即时式状态机 —— 句柄表(shader/pipeline/buffer/texture/sampler)、
// 渲染通道、管线状态(blend/cull/fill)、逐 draw uniform、VAO 顶点装配、索引绘制。

(function () {
	const WASM_URL = window.FOSTER_WASM || "game.wasm";
	const canvas = document.getElementById(window.FOSTER_CANVAS_ID || "foster");
	const logEl = document.getElementById(window.FOSTER_LOG_ID || "foster-log");
	// 诊断日志默认隐藏: URL 加 ?debug=1 常显; 出现 ERROR 行时自动弹出
	const debugVisible = new URLSearchParams(location.search).has("debug");
	const showLog = () => { if (logEl) logEl.style.display = "block"; };
	if (debugVisible) showLog();
	const log = (msg) => {
		if (logEl) {
			logEl.textContent += msg + "\n";
			if (!debugVisible && /\bERROR\b/.test(msg)) showLog();
		}
		console.log(msg);
	};

	if (!canvas) { log("[foster.js] missing <canvas id=foster>"); return; }
	const gl = canvas.getContext("webgl2", { antialias: true, alpha: false, preserveDrawingBuffer: true });
	if (!gl) { log("[foster.js] WebGL2 not available"); return; }

	// --- 常量 ---
	const GL = {
		FLOAT: 0x1406, UNSIGNED_BYTE: 0x1401, SHORT: 0x1402, UNSIGNED_SHORT: 0x1403, UNSIGNED_INT: 0x1405,
		NEAREST: 0x2600, LINEAR: 0x2601,
		REPEAT: 0x2901, MIRRORED_REPEAT: 0x8370, CLAMP_TO_EDGE: 0x812F,
		FUNC_ADD: 0x8006, FUNC_SUBTRACT: 0x800A, FUNC_REVERSE_SUBTRACT: 0x800B, MIN: 0x8007, MAX: 0x8008,
		ZERO: 0, ONE: 1,
		SRC_COLOR: 0x0300, ONE_MINUS_SRC_COLOR: 0x0301, DST_COLOR: 0x0306, ONE_MINUS_DST_COLOR: 0x0307,
		SRC_ALPHA: 0x0302, ONE_MINUS_SRC_ALPHA: 0x0303, DST_ALPHA: 0x0304, ONE_MINUS_DST_ALPHA: 0x0305,
		CONSTANT_COLOR: 0x8001, ONE_MINUS_CONSTANT_COLOR: 0x8002, SRC_ALPHA_SATURATE: 0x0308,
	};
	// 序号映射(与 Odin 侧 enum 声明顺序一致)
	const BLEND_FACTOR = [
		GL.ZERO, GL.ONE, GL.SRC_COLOR, GL.ONE_MINUS_SRC_COLOR, GL.DST_COLOR, GL.ONE_MINUS_DST_COLOR,
		GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.DST_ALPHA, GL.ONE_MINUS_DST_ALPHA,
		GL.CONSTANT_COLOR, GL.ONE_MINUS_CONSTANT_COLOR, GL.SRC_ALPHA_SATURATE,
	];
	const BLEND_OP = [GL.FUNC_ADD, GL.FUNC_SUBTRACT, GL.FUNC_REVERSE_SUBTRACT, GL.MIN, GL.MAX];
	const CULL = [0, gl.FRONT, gl.BACK]; // 0 = 禁用
	const COMPARE = [gl.ALWAYS, gl.NEVER, gl.LESS, gl.EQUAL, gl.LEQUAL, gl.GREATER, gl.NOTEQUAL, gl.GEQUAL];
	const STENCIL_OP = [gl.KEEP, gl.KEEP, gl.ZERO, gl.REPLACE, gl.INCR, gl.DECR, gl.INVERT, gl.INCR_WRAP, gl.DECR_WRAP];
	let boundStencil = null;
	const setStencilReference = (reference) => {
		if (!boundStencil) return;
		for (const [face, state] of [[gl.FRONT, boundStencil.front], [gl.BACK, boundStencil.back]]) {
			gl.stencilFuncSeparate(face, COMPARE[state.compare], reference, boundStencil.compareMask);
		}
	};
	// FillMode.Line 需要 polygonMode, WebGL2 不支持 —— Web 后端恒按填充绘制(已知差异)。
	const VERTEX_TYPE = [ // VertexType 序号 → [size, glType]
		null,          // None
		[1, GL.FLOAT], // Float
		[2, GL.FLOAT], // Float2
		[3, GL.FLOAT], // Float3
		[4, GL.FLOAT], // Float4
		[4, gl.BYTE],        // Byte4
		[4, GL.UNSIGNED_BYTE], // UByte4
		[2, GL.SHORT],       // Short2
		[2, GL.UNSIGNED_SHORT], // UShort2
		[4, GL.SHORT],       // Short4
		[4, GL.UNSIGNED_SHORT], // UShort4
	];
	const FILTER = [GL.NEAREST, GL.LINEAR];
	const WRAP = [GL.REPEAT, GL.MIRRORED_REPEAT, GL.CLAMP_TO_EDGE];
	const INDEX_TYPE = [GL.UNSIGNED_SHORT, GL.UNSIGNED_INT];

	// --- 事件队列(Odin 侧 fw_poll_event 逐条取) ---
	// WebEvent 布局(web_runtime.odin): kind u32 @0, a i32 @4, b i32 @8, c i32 @12, f f32 @16, g f32 @20
	const EV = {
		Quit: 0, WindowResized: 1, WindowFocusGained: 2, WindowFocusLost: 3,
		KeyDown: 4, KeyUp: 5, MouseMove: 6, MouseButtonDown: 7, MouseButtonUp: 8,
		MouseWheel: 9, TextInput: 10, ControllerConnected: 11, ControllerDisconnected: 12,
		ControllerButtonDown: 13, ControllerButtonUp: 14, ControllerAxis: 15, ClipboardResult: 16, DialogResult: 17, StorageFlushResult: 18,
	};
	const eventQueue = [];
	const push = (kind, a = 0, b = 0, c = 0, f = 0, g = 0) => eventQueue.push({ kind, a, b, c, f, g });
	const pushText = (kind, text, a = 0, b = 0, c = 0, f = 0) => {
		eventQueue.push({ kind, a, b, c, f, g: 0, text });
	};
	let eventText = "";
	let clipboardText = "";
	const encoder = new TextEncoder();
	const writeText = (text, ptr, capacity) => {
		const bytes = encoder.encode(text);
		if (ptr && capacity >= bytes.length) {
			new Uint8Array(bridge.memory.buffer, ptr, bytes.length).set(bytes);
		}
		return bytes.length;
	};

	// --------------------------------------------------------------------------
	// Input / Text — 可聚焦的输入目标承接浏览器 IME 与粘贴
	// --------------------------------------------------------------------------
	const textTarget = document.createElement("textarea");
	textTarget.setAttribute("aria-label", "Game text input");
	textTarget.autocomplete = "off";
	textTarget.spellcheck = false;
	textTarget.style.cssText = "position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none";
	document.body.appendChild(textTarget);
	let textEnabled = false;
	let composing = false;
	let committedComposition = "";
	textTarget.addEventListener("compositionstart", () => { composing = true; });
	textTarget.addEventListener("compositionend", (event) => {
		composing = false;
		committedComposition = event.data || textTarget.value;
		if (textEnabled && committedComposition) pushText(EV.TextInput, committedComposition);
		textTarget.value = "";
	});
	textTarget.addEventListener("input", (event) => {
		if (!textEnabled || composing || event.isComposing) return;
		const text = textTarget.value;
		const duplicateCommit = committedComposition && (event.data || text) === committedComposition &&
			event.inputType !== "insertFromPaste";
		committedComposition = "";
		if (duplicateCommit) { textTarget.value = ""; return; }
		if (text) pushText(EV.TextInput, text);
		textTarget.value = "";
	});
	textTarget.addEventListener("paste", event => {
		clipboardText = event.clipboardData?.getData("text/plain") || "";
	});

	// --------------------------------------------------------------------------
	// Input / Controllers — 标准映射、状态差分与断开
	// --------------------------------------------------------------------------
	const gamepads = new Map();
	let nextControllerID = 1;
	let currentCursor = 0;
	let cursorStyle = "default";
	let cursorVisible = true;
	const standardButtons = [0, 1, 2, 3, 8, 16, 9, 10, 11, 4, 5, 12, 13, 14, 15];
	function pollGamepads() {
		let devices;
		try { devices = navigator.getGamepads ? navigator.getGamepads() : []; }
		catch (_) { return; }
		const present = new Set();
		for (const device of devices) {
			if (!device || !device.connected) continue;
			present.add(device.index);
			let state = gamepads.get(device.index);
			const standard = device.mapping === "standard";
			if (state && (state.name !== device.id || state.standard !== standard)) {
				push(EV.ControllerDisconnected, state.id);
				gamepads.delete(device.index);
				state = null;
			}
			const buttons = standard
				? standardButtons.map(index => !!device.buttons[index]?.pressed)
				: Array.from(device.buttons, button => !!button.pressed);
			const axes = standard
				? [device.axes[0] || 0, device.axes[1] || 0, device.axes[2] || 0, device.axes[3] || 0,
					device.buttons[6]?.value || 0, device.buttons[7]?.value || 0]
				: Array.from(device.axes);
			if (!state) {
				state = { id: nextControllerID++, name: device.id, standard, buttons: [], axes: [] };
				gamepads.set(device.index, state);
				pushText(EV.ControllerConnected, device.id, state.id, buttons.length, axes.length, standard ? 1 : 0);
			}
			buttons.forEach((down, index) => {
				if (down !== !!state.buttons[index]) {
					push(down ? EV.ControllerButtonDown : EV.ControllerButtonUp, state.id, index);
				}
			});
			axes.forEach((value, index) => {
				value = Math.fround(Number.isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0);
				if (value !== (state.axes[index] || 0)) push(EV.ControllerAxis, state.id, index, 0, value);
			});
			state.buttons = buttons;
			state.axes = axes.map(value => Math.fround(Number.isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0));
		}
		for (const [index, state] of gamepads) {
			if (!present.has(index)) {
				push(EV.ControllerDisconnected, state.id);
				gamepads.delete(index);
			}
		}
	}

	// e.code → SDL scancode(Foster Keys 值与 SDL scancode 一致)
	const KEYCODE = (() => {
		const t = {};
		const add = (code, sc) => { t[code] = sc; };
		for (let i = 0; i < 26; i++) add("Key" + String.fromCharCode(65 + i), 4 + i);   // A=4..Z=29
		for (let i = 1; i <= 9; i++) add("Digit" + i, 29 + i);                            // 1=30..9=38
		add("Digit0", 39);
		add("Enter", 40); add("Escape", 41); add("Backspace", 42); add("Tab", 43); add("Space", 44);
		add("Minus", 45); add("Equal", 46); add("BracketLeft", 47); add("BracketRight", 48); add("Backslash", 49);
		add("Semicolon", 51); add("Quote", 52); add("Backquote", 53); add("Comma", 54); add("Period", 55); add("Slash", 56);
		add("CapsLock", 57);
		for (let i = 1; i <= 12; i++) add("F" + i, 57 + i);                                // F1=58..F12=69
		add("PrintScreen", 70); add("ScrollLock", 71); add("Pause", 72); add("Insert", 73);
		add("Home", 74); add("PageUp", 75); add("Delete", 76); add("End", 77); add("PageDown", 78);
		add("ArrowRight", 79); add("ArrowLeft", 80); add("ArrowDown", 81); add("ArrowUp", 82);
		add("NumLock", 83);
		add("NumpadDivide", 84); add("NumpadMultiply", 85); add("NumpadSubtract", 86); add("NumpadAdd", 87);
		add("NumpadEnter", 88);
		for (let i = 1; i <= 9; i++) add("Numpad" + i, 88 + i);                           // 89..97
		add("Numpad0", 98); add("NumpadDecimal", 99);
		add("ControlLeft", 224); add("ShiftLeft", 225); add("AltLeft", 226); add("MetaLeft", 227);
		add("ControlRight", 228); add("ShiftRight", 229); add("AltRight", 230); add("MetaRight", 231);
		return t;
	})();

	// 会截获的按键(防页面滚动等默认行为)
	const isGameKey = (code) => code in KEYCODE;

	// --- canvas 尺寸同步(CSS 尺寸 × DPR = 绘制缓冲尺寸) ---
	function syncCanvasSize() {
		const dpr = window.devicePixelRatio || 1;
		const w = Math.max(1, Math.floor(canvas.clientWidth * dpr));
		const h = Math.max(1, Math.floor(canvas.clientHeight * dpr));
		if (canvas.width !== w || canvas.height !== h) {
			canvas.width = w;
			canvas.height = h;
			push(EV.WindowResized, canvas.clientWidth | 0, canvas.clientHeight | 0);
		}
	}
	if (typeof ResizeObserver !== "undefined") new ResizeObserver(syncCanvasSize).observe(canvas);
	window.addEventListener("resize", syncCanvasSize);
	window.addEventListener("focus", () => push(EV.WindowFocusGained));
	window.addEventListener("blur", () => push(EV.WindowFocusLost));
	window.addEventListener("pagehide", () => push(EV.Quit));

	// --- M3: 键盘 / 鼠标 / 滚轮 / Pointer Lock ---
	const mouseButtonSDL = (b) => b === 0 ? 1 : b === 1 ? 2 : b === 2 ? 3 : 0; // DOM → SDL(左1中2右3)

	function pixelPos(e) {
		// clientX/Y 相对 canvas 归一: getBoundingClientRect 受页面 zoom/transform 影响,
		// 按 rect 与 clientWidth 比例换算回 CSS 尺寸, 再乘 DPR 得绘制缓冲像素
		const dpr = window.devicePixelRatio || 1;
		const rect = canvas.getBoundingClientRect();
		const sx = rect.width > 0 ? canvas.clientWidth / rect.width : 1;
		const sy = rect.height > 0 ? canvas.clientHeight / rect.height : 1;
		return [(e.clientX - rect.left) * sx * dpr, (e.clientY - rect.top) * sy * dpr];
	}

	// Pointer Lock 虚拟坐标(锁定后 movementX/Y 累积)
	let pointerLocked = false;
	let virtualX = 0, virtualY = 0;

	window.addEventListener("keydown", (e) => {
		if (!e.isComposing) committedComposition = "";
		const sc = KEYCODE[e.code];
		if (sc === undefined) return;
		if (isGameKey(e.code) && !(textEnabled && e.target === textTarget)) e.preventDefault();
		push(EV.KeyDown, sc, e.repeat ? 1 : 0);
	});
	window.addEventListener("keyup", (e) => {
		const sc = KEYCODE[e.code];
		if (sc === undefined) return;
		push(EV.KeyUp, sc, 0);
	});
	canvas.addEventListener("pointerdown", (e) => {
		if (textEnabled) textTarget.focus({ preventScroll: true });
		const [x, y] = pixelPos(e);
		push(EV.MouseButtonDown, mouseButtonSDL(e.button), 0, 0, x, y);
		canvas.setPointerCapture(e.pointerId);
	});
	canvas.addEventListener("pointerup", (e) => {
		const [x, y] = pixelPos(e);
		push(EV.MouseButtonUp, mouseButtonSDL(e.button), 0, 0, x, y);
	});
	canvas.addEventListener("pointermove", (e) => {
		if (pointerLocked) {
			const dpr = window.devicePixelRatio || 1;
			virtualX += e.movementX * dpr;
			virtualY += e.movementY * dpr;
			push(EV.MouseMove, 0, 0, 0, virtualX, virtualY);
		} else {
			const [x, y] = pixelPos(e);
			push(EV.MouseMove, 0, 0, 0, x, y);
		}
	});
	canvas.addEventListener("wheel", (e) => {
		e.preventDefault();
		// 归一化: ±100 像素 ≈ 1 个滚轮刻度, SDL 语义向上为正
		push(EV.MouseWheel, 0, 0, 0, e.deltaX / 100, -e.deltaY / 100);
	}, { passive: false });
	canvas.addEventListener("contextmenu", (e) => e.preventDefault());
	document.addEventListener("pointerlockchange", () => {
		pointerLocked = document.pointerLockElement === canvas;
		if (pointerLocked) {
			virtualX = canvas.width / 2;
			virtualY = canvas.height / 2;
		}
	});

	// 调试句柄(仅供开发排查; 游戏代码不要依赖)
	const callCounts = Object.create(null);
	const countedBridge = new Proxy({}, {
		get(_, prop) {
			if (prop in bridge) {
				return function (...args) {
					callCounts[prop] = (callCounts[prop] || 0) + 1;
					return bridge[prop].apply(this, args);
				};
			}
			return undefined;
		},
	});
	window.__fosterDebug = {
		push: push,
		queueDepth: () => eventQueue.length,
		drain: () => eventQueue.splice(0, eventQueue.length),
		calls: callCounts,
		pollGamepads,
	};

	// --- GL 初始状态 ---
	gl.disable(gl.DEPTH_TEST);
	gl.disable(gl.STENCIL_TEST);
	gl.disable(gl.CULL_FACE);
	gl.disable(gl.SCISSOR_TEST);
	gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
	gl.enable(gl.BLEND); // 具体混合因子由管线状态设置

	// 默认 1x1 白纹理(无纹理批次的占位, 对应桌面的 DebugTexture)
	const whiteTex = gl.createTexture();
	gl.bindTexture(gl.TEXTURE_2D, whiteTex);
	gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, GL.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));

	// --- 句柄表 ---
	const objects = new Map();
	let nextHandle = 1;
	function retain(kind, obj) {
		const h = nextHandle++;
		objects.set(h, { kind, obj });
		return h;
	}
	function release(h) {
		const e = objects.get(h);
		if (!e) return;
		switch (e.kind) {
			case "shader": gl.deleteShader(e.obj); break;
			case "pipeline":
				gl.deleteProgram(e.obj.program);
				gl.deleteVertexArray(e.obj.vao);
				break;
			case "buffer": gl.deleteBuffer(e.obj.gl); break;
			case "texture": gl.deleteTexture(e.obj); break;
			case "sampler": gl.deleteSampler(e.obj); break;
		}
		objects.delete(h);
	}
	const get = (h) => (objects.get(h) || {}).obj;
	const floatTargets = !!gl.getExtension("EXT_color_buffer_float");
	const textureFormats = [
		[gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, 4],
		[gl.R8, gl.RED, gl.UNSIGNED_BYTE, 1],
		[gl.RG8, gl.RG, gl.UNSIGNED_BYTE, 2],
		[gl.DEPTH24_STENCIL8, gl.DEPTH_STENCIL, gl.UNSIGNED_INT_24_8, 4],
		null,
		[gl.DEPTH_COMPONENT16, gl.DEPTH_COMPONENT, gl.UNSIGNED_SHORT, 2],
		null,
		[gl.DEPTH_COMPONENT32F, gl.DEPTH_COMPONENT, gl.FLOAT, 4],
		floatTargets ? [gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, 8] : null,
		floatTargets ? [gl.RGBA32F, gl.RGBA, gl.FLOAT, 16] : null,
		floatTargets ? [gl.R11F_G11F_B10F, gl.RGB, gl.UNSIGNED_INT_10F_11F_11F_REV, 4] : null,
	];
	const textureInfo = new Map();
	const drawFramebuffer = gl.createFramebuffer();
	let previousAttachmentCount = 0;
	function textureFramebuffer(handle) {
		const info = textureInfo.get(handle);
		if (!info || info.format >= 3 && info.format <= 7) return null;
		if (!info.fbo) {
			const previous = gl.getParameter(gl.FRAMEBUFFER_BINDING);
			info.fbo = gl.createFramebuffer();
			gl.bindFramebuffer(gl.FRAMEBUFFER, info.fbo);
			gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, get(handle), 0);
			gl.bindFramebuffer(gl.FRAMEBUFFER, previous);
		}
		return info.fbo;
	}
	function textureUpload(handle, x, y, width, height, dataPtr, size) {
		const info = textureInfo.get(handle);
		if (!info) return;
		const [, format, type] = textureFormats[info.format];
		const View = type === gl.FLOAT ? Float32Array : type === gl.HALF_FLOAT || type === gl.UNSIGNED_SHORT ? Uint16Array : type === gl.UNSIGNED_BYTE ? Uint8Array : Uint32Array;
		gl.bindTexture(gl.TEXTURE_2D, get(handle));
		// Byte-oriented public uploads may start at an unaligned slice offset.
		const pixels = dataPtr % View.BYTES_PER_ELEMENT === 0
			? new View(bridge.memory.buffer, dataPtr, size / View.BYTES_PER_ELEMENT)
			: new View(bridge.memory.buffer.slice(dataPtr, dataPtr + size));
		gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, width, height, format, type, pixels);
	}

	// --- M4: localStorage 虚拟 FS 辅助 ---
	const FS_PREFIX = "fosterfs:";
	const DIR_PREFIX = "fosterdir:";
	const fsPath = path => path.replace(/\/+$/, "") || "/";
	const fsDescendant = (path, parent) => path.startsWith(parent === "/" ? "/" : parent + "/");
	function fsPaths() {
		const paths = [];
		for (let i = 0; i < localStorage.length; ++i) {
			const key = localStorage.key(i);
			if (key.startsWith(FS_PREFIX)) paths.push(key.slice(FS_PREFIX.length));
			else if (key.startsWith(DIR_PREFIX)) paths.push(key.slice(DIR_PREFIX.length));
		}
		return paths;
	}
	function fsDirectory(path) {
		path = fsPath(path);
		return path === "/" || localStorage.getItem(DIR_PREFIX + path) !== null || fsPaths().some(p => fsDescendant(p, path));
	}
	const fsKey = (path) => FS_PREFIX + path;
	const fsReadBytes = (path) => {
		const v = localStorage.getItem(fsKey(path));
		if (v === null) return null;
		return base64ToBytes(v);
	};
	function bytesToBase64(bytes) {
		let bin = "";
		const chunk = 0x8000;
		for (let i = 0; i < bytes.length; i += chunk) {
			bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
		}
		return btoa(bin);
	}
	function base64ToBytes(b64) {
		const bin = atob(b64);
		const out = new Uint8Array(bin.length);
		for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
		return out;
	}

	// 文件选择只返回虚拟路径，导入的快照沿用 Storage 的同步读取接口。
	// 保存句柄的写入按路径排队，FlushStorageFileAsync 显式确认磁盘写入结果。
	const pickedFiles = new Map();
	const dialogSession = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);
	function fsWriteBytes(path, bytes) {
		path = fsPath(path);
		localStorage.setItem(fsKey(path), bytesToBase64(bytes));
		const selected = pickedFiles.get(path);
		if (selected) {
			const snapshot = bytes.slice();
			selected.pending = selected.pending.then(async () => {
				let writable;
				try {
					writable = await selected.handle.createWritable();
					await writable.write(snapshot);
					await writable.close();
					return true;
				} catch (error) {
					try { await writable?.abort(); } catch (_) {}
					return false;
				}
			});
		}
	}
	function pickerTypes(filters) {
		return (filters || []).flatMap(filter => {
			const extensions = filter.Pattern.split(";").map(value => value.trim().replace(/^\*?\.?/, "."))
				.filter(value => /^\.[a-zA-Z0-9._-]+$/.test(value));
			return extensions.length ? [{ description: filter.Name, accept: { "application/octet-stream": extensions } }] : [];
		});
	}
	async function fileDialog(request, kind, filters) {
		const root = "/foster-dialog/" + dialogSession + "/" + request;
		const importFile = async (handle, path) => {
			const file = await handle.getFile();
			fsWriteBytes(path, new Uint8Array(await file.arrayBuffer()));
		};
		try {
			const types = pickerTypes(filters);
			let paths;
			if (kind === 0) {
				if (!window.showOpenFilePicker) throw new Error("File picker unavailable");
				const handles = await window.showOpenFilePicker({ multiple: true, types });
				paths = [];
				for (const handle of handles) {
					const path = root + "/" + handle.name;
					await importFile(handle, path);
					paths.push(path);
				}
			} else if (kind === 1) {
				if (!window.showDirectoryPicker) throw new Error("Directory picker unavailable");
				const directory = await window.showDirectoryPicker({ mode: "read" });
				const path = root + "/" + directory.name;
				const walk = async (handle, prefix) => {
					localStorage.setItem(DIR_PREFIX + prefix, "1");
					for await (const child of handle.values()) {
						const childPath = prefix + "/" + child.name;
						if (child.kind === "directory") await walk(child, childPath);
						else await importFile(child, childPath);
					}
				};
				await walk(directory, path);
				paths = [path];
			} else {
				if (!window.showSaveFilePicker) throw new Error("Save picker unavailable");
				const handle = await window.showSaveFilePicker({ types });
				const path = root + "/" + handle.name;
				await importFile(handle, path);
				pickedFiles.set(path, { handle, pending: Promise.resolve(true) });
				paths = [path];
			}
			pushText(EV.DialogResult, paths.join("\0"), request, paths.length ? 1 : 0);
		} catch (error) {
			for (const path of fsPaths()) if (fsDescendant(path, root)) {
				localStorage.removeItem(fsKey(path));
				localStorage.removeItem(DIR_PREFIX + path);
			}
			pushText(EV.DialogResult, "", request, 0);
		}
	}

	// --- 逐 draw uniform 暂存(管线绑定时清空, draw 时应用) ---
	let pendingMatrix = null;   // Float32Array(16) 或 null
	let pendingFragFloat = null;
	let texturePass = false;

	function compileShader(stage, code) {
		const type = stage === 0 ? gl.VERTEX_SHADER : gl.FRAGMENT_SHADER;
		const s = gl.createShader(type);
		gl.shaderSource(s, code);
		gl.compileShader(s);
		if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
			log("[foster.js] shader compile error:\n" + gl.getShaderInfoLog(s) + "\n--- source ---\n" + code);
			gl.deleteShader(s);
			return 0;
		}
		return retain("shader", s);
	}

	// --- 桥实现 ---
	const bridge = {
		memory: null,
		setMemory(m) { bridge.memory = m; },

		fw_init(titlePtr, titleLen) {
			syncCanvasSize();
			if (titleLen > 0) document.title = readString(titlePtr, titleLen);
			return true;
		},
		fw_canvas_size(wPtr, hPtr) {
			const dv = new DataView(bridge.memory.buffer);
			dv.setInt32(wPtr, canvas.clientWidth | 0, true);
			dv.setInt32(hPtr, canvas.clientHeight | 0, true);
		},
		fw_canvas_pixel_size(wPtr, hPtr) {
			const dv = new DataView(bridge.memory.buffer);
			dv.setInt32(wPtr, canvas.width, true);
			dv.setInt32(hPtr, canvas.height, true);
		},
		fw_set_title(ptr, len) { if (len > 0) document.title = readString(ptr, len); },
		fw_clear(r, g, b, a) {
			gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
			gl.clearColor(r, g, b, a);
			gl.clear(gl.COLOR_BUFFER_BIT);
		},
		fw_present() { /* WebGL2: rAF 合成即 present */ },
		fw_poll_event(evPtr) {
			if (eventQueue.length === 0) return false;
			const ev = eventQueue.shift();
			eventText = ev.text || "";
			const dv = new DataView(bridge.memory.buffer, evPtr, 24);
			dv.setUint32(0, ev.kind, true);
			dv.setInt32(4, ev.a, true);
			dv.setInt32(8, ev.b, true);
			dv.setInt32(12, ev.c, true);
			dv.setFloat32(16, ev.f, true);
			dv.setFloat32(20, ev.g, true);
			return true;
		},
		fw_log(ptr, len) { if (len > 0) log(readString(ptr, len)); },
		fw_event_text(ptr, capacity) { return writeText(eventText, ptr, capacity); },
		fw_clipboard_cached(ptr, capacity) { return writeText(clipboardText, ptr, capacity); },
		fw_clipboard_read(request) {
			const complete = (text, succeeded) => pushText(EV.ClipboardResult, text, request, succeeded ? 1 : 0);
			if (!navigator.clipboard?.readText) { complete("", false); return; }
			try {
				navigator.clipboard.readText().then(text => {
					clipboardText = text;
					complete(text, true);
				}, () => complete("", false));
			} catch (_) { complete("", false); }
		},
		fw_clipboard_write(request, ptr, length) {
			const text = readString(ptr, length);
			const complete = succeeded => {
				if (succeeded) clipboardText = text;
				if (request) pushText(EV.ClipboardResult, text, request, succeeded ? 1 : 0);
			};
			if (!navigator.clipboard?.writeText) { complete(false); return false; }
			try {
				navigator.clipboard.writeText(text).then(() => complete(true), () => complete(false));
				return true;
			} catch (_) { complete(false); return false; }
		},
		fw_text_input(enabled) {
			textEnabled = !!enabled;
			textTarget.value = "";
			composing = false;
			if (textEnabled) textTarget.focus({ preventScroll: true });
			else textTarget.blur();
		},
		fw_cursor_system(kind) {
			const styles = ["default", "text", "wait", "crosshair", "progress", "nwse-resize", "nesw-resize",
				"ew-resize", "ns-resize", "move", "not-allowed", "pointer", "nw-resize", "n-resize",
				"ne-resize", "e-resize", "se-resize", "s-resize", "sw-resize", "w-resize"];
			return retain("cursor", { style: styles[kind] || "default" });
		},
		fw_cursor_image(ptr, width, height, x, y) {
			if (width <= 0 || height <= 0 || x < 0 || y < 0 || x >= width || y >= height) return 0;
			const image = document.createElement("canvas");
			image.width = width;
			image.height = height;
			const pixels = new Uint8ClampedArray(bridge.memory.buffer, ptr, width * height * 4);
			image.getContext("2d").putImageData(new ImageData(pixels, width, height), 0, 0);
			return retain("cursor", { style: `url("${image.toDataURL()}") ${x} ${y}, default` });
		},
		fw_cursor_set(handle) {
			const cursor = handle ? get(handle) : { style: "default" };
			if (!cursor) return false;
			cursorStyle = cursor.style;
			canvas.style.cursor = cursorVisible ? cursorStyle : "none";
			currentCursor = handle;
			return true;
		},
		fw_cursor_release(handle) {
			if (currentCursor === handle) bridge.fw_cursor_set(0);
			release(handle);
		},
		fw_cursor_visible(visible) {
			cursorVisible = !!visible;
			canvas.style.cursor = cursorVisible ? cursorStyle : "none";
		},
		fw_rumble(id, low, high, duration) {
			const connected = Array.from(gamepads).find(([, state]) => state.id === id);
			if (!connected || !navigator.getGamepads) return;
			const device = navigator.getGamepads()[connected[0]];
			const actuator = device?.vibrationActuator || device?.hapticActuators?.[0];
			if (!actuator) return;
			const clamp = value => Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0));
			const milliseconds = Number.isFinite(duration) ? Math.max(0, Math.round(duration * 1000)) : 0;
			try {
				const promise = actuator.playEffect
					? actuator.playEffect("dual-rumble", { duration: milliseconds, strongMagnitude: clamp(low), weakMagnitude: clamp(high) })
					: actuator.pulse?.(Math.max(clamp(low), clamp(high)), milliseconds);
				promise?.catch(() => {});
			} catch (_) { /* Devices without the requested effect keep working normally. */ }
		},

		// ---- GL 资源 ----
		fw_gl_create_shader(stage, codePtr, codeLen) {
			return compileShader(stage, readString(codePtr, codeLen));
		},
		fw_gl_release_shader(h) { release(h); },
		fw_gl_create_pipeline(vs, fs, blendEnable, cSrc, cDst, cOp, aSrc, aDst, aOp, colorMask, cull, fill) {
			const vsObj = get(vs), fsObj = get(fs);
			if (!vsObj || !fsObj) return 0;
			const p = gl.createProgram();
			gl.attachShader(p, vsObj);
			gl.attachShader(p, fsObj);
			gl.linkProgram(p);
			if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
				log("[foster.js] program link error: " + gl.getProgramInfoLog(p));
				gl.deleteProgram(p);
				return 0;
			}
			const prog = {
				program: p,
				vao: gl.createVertexArray(),
				// 状态(绑定时应用)
				blendEnable: blendEnable !== 0,
				cSrc: BLEND_FACTOR[cSrc], cDst: BLEND_FACTOR[cDst], cOp: BLEND_OP[cOp],
				aSrc: BLEND_FACTOR[aSrc], aDst: BLEND_FACTOR[aDst], aOp: BLEND_OP[aOp],
				colorMask: colorMask & 15, cull: CULL[cull] || 0,
				// uniform 位置(懒查询缓存)
				locs: {},
			};
			// sampler 统一 0 号单元
			gl.useProgram(p);
			const texLoc = gl.getUniformLocation(p, "u_tex");
			if (texLoc) gl.uniform1i(texLoc, 0);
			return retain("pipeline", prog);
		},
		fw_gl_release_pipeline(h) { release(h); },
		fw_gl_pipeline_depth_stencil(h, depthTest, depthWrite, depthCompare, stencilTest, compareMask, writeMask,
			frontFail, frontPass, frontDepthFail, frontCompare, backFail, backPass, backDepthFail, backCompare) {
			const prog = get(h);
			if (!prog) return;
			prog.depth = { test: !!depthTest, write: !!depthWrite, compare: depthCompare };
			prog.stencil = { test: !!stencilTest, compareMask, writeMask,
				front: { fail: frontFail, pass: frontPass, depthFail: frontDepthFail, compare: frontCompare },
				back: { fail: backFail, pass: backPass, depthFail: backDepthFail, compare: backCompare } };
		},
		fw_set_stencil_reference(reference) { setStencilReference(reference); },
		fw_gl_create_buffer(bufferType, byteSize) {
			// bufferType: 0=vertex 1=index 2=storage; 大小仅作提示, 上传时按需生效
			const b = gl.createBuffer();
			gl.bindVertexArray(null);
			const target = bufferType === 1 ? gl.ELEMENT_ARRAY_BUFFER : gl.ARRAY_BUFFER;
			gl.bindBuffer(target, b);
			gl.bufferData(target, byteSize, gl.DYNAMIC_DRAW);
			return retain("buffer", { gl: b, target });
		},
		fw_gl_upload_buffer(h, dataPtr, size, offset) {
			const b = get(h);
			if (!b) return;
			gl.bindVertexArray(null); // 保护 VAO 的 ELEMENT 绑定
			gl.bindBuffer(b.target, b.gl);
			gl.bufferSubData(b.target, offset, new Uint8Array(bridge.memory.buffer, dataPtr, size));
		},
		fw_gl_release_buffer(h) { release(h); },
		fw_gl_texture_supported(format) { return !!textureFormats[format]; },
		fw_gl_create_texture(width, height, format = 0) {
			const spec = textureFormats[format];
			if (!spec) return 0;
			const t = gl.createTexture();
			gl.bindTexture(gl.TEXTURE_2D, t);
			gl.texStorage2D(gl.TEXTURE_2D, 1, spec[0], width, height);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, GL.NEAREST);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, GL.NEAREST);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
			const handle = retain("texture", t);
			textureInfo.set(handle, { width, height, format, fbo: null });
			return handle;
		},
		fw_gl_upload_texture(h, width, height, dataPtr, size) {
			textureUpload(h, 0, 0, width, height, dataPtr, size);
		},
		fw_gl_upload_texture_region(h, x, y, width, height, dataPtr, size) { textureUpload(h, x, y, width, height, dataPtr, size); },
		fw_gl_download_texture(h, dataPtr, size) {
			const info = textureInfo.get(h);
			const fbo = textureFramebuffer(h);
			if (!info || !fbo || ![0, 1, 2, 9].includes(info.format) || size !== info.width * info.height * textureFormats[info.format][3]) return false;
			const previous = gl.getParameter(gl.READ_FRAMEBUFFER_BINDING);
			gl.bindFramebuffer(gl.READ_FRAMEBUFFER, fbo);
			gl.readBuffer(gl.COLOR_ATTACHMENT0);
			gl.pixelStorei(gl.PACK_ALIGNMENT, 1);
			const channels = info.format === 1 ? 1 : info.format === 2 ? 2 : 4;
			const pixels = info.format === 9 ? new Float32Array(info.width * info.height * 4) : new Uint8Array(info.width * info.height * 4);
			gl.readPixels(0, 0, info.width, info.height, gl.RGBA, info.format === 9 ? gl.FLOAT : gl.UNSIGNED_BYTE, pixels);
			const ok = gl.getError() === gl.NO_ERROR;
			gl.bindFramebuffer(gl.READ_FRAMEBUFFER, previous);
			if (!ok) return false;
			const out = info.format === 9 ? new Float32Array(bridge.memory.buffer, dataPtr, size / 4) : new Uint8Array(bridge.memory.buffer, dataPtr, size);
			for (let i = 0; i < info.width * info.height; ++i) for (let c = 0; c < channels; ++c) out[i * channels + c] = pixels[i * 4 + c];
			return true;
		},
		fw_gl_blit_texture(source, dest, sx, sy, sw, sh, dx, dy, dw, dh, filter) {
			const srcFbo = textureFramebuffer(source), dstFbo = textureFramebuffer(dest);
			if (!srcFbo || !dstFbo) return;
			const read = gl.getParameter(gl.READ_FRAMEBUFFER_BINDING), draw = gl.getParameter(gl.DRAW_FRAMEBUFFER_BINDING);
			gl.bindFramebuffer(gl.READ_FRAMEBUFFER, srcFbo);
			gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, dstFbo);
			gl.disable(gl.SCISSOR_TEST);
			gl.blitFramebuffer(sx, sy, sx + sw, sy + sh, dx, dy, dx + dw, dy + dh, gl.COLOR_BUFFER_BIT, FILTER[filter]);
			gl.bindFramebuffer(gl.READ_FRAMEBUFFER, read);
			gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, draw);
		},
		fw_gl_release_texture(h) {
			const info = textureInfo.get(h);
			if (info && info.fbo) gl.deleteFramebuffer(info.fbo);
			textureInfo.delete(h);
			release(h);
		},
		fw_gl_create_sampler(filter, wrapX, wrapY) {
			const s = gl.createSampler();
			gl.samplerParameteri(s, gl.TEXTURE_MIN_FILTER, FILTER[filter]);
			gl.samplerParameteri(s, gl.TEXTURE_MAG_FILTER, FILTER[filter]);
			gl.samplerParameteri(s, gl.TEXTURE_WRAP_S, WRAP[wrapX]);
			gl.samplerParameteri(s, gl.TEXTURE_WRAP_T, WRAP[wrapY]);
			return retain("sampler", s);
		},
		fw_gl_release_sampler(h) { release(h); },

		// ---- 帧内命令 ----
		fw_begin_pass(fboTexture, r, g, b, a, doClear) {
			texturePass = false;
			// M1: fboTexture 0 = 窗口画布; M2 接纹理 FBO
			gl.bindFramebuffer(gl.FRAMEBUFFER, null);
			gl.disable(gl.SCISSOR_TEST);
			if (doClear) {
				gl.colorMask(true, true, true, true);
				gl.clearColor(r, g, b, a);
				gl.clear(gl.COLOR_BUFFER_BIT);
			}
		},
		fw_begin_target(texturesPtr, count, depthTexture, colorsPtr, colorCount, clearDepth, depth, clearStencil, stencil) {
			texturePass = true;
			gl.bindFramebuffer(gl.FRAMEBUFFER, drawFramebuffer);
			const handles = new Uint32Array(bridge.memory.buffer, texturesPtr, count);
			const buffers = [];
			for (let i = 0; i < Math.max(count, previousAttachmentCount); ++i) {
				gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + i, gl.TEXTURE_2D, i < count ? get(handles[i]) : null, 0);
				if (i < count) buffers.push(gl.COLOR_ATTACHMENT0 + i);
			}
			previousAttachmentCount = count;
			gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, null, 0);
			gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.TEXTURE_2D, null, 0);
			if (depthTexture) {
				const attachment = textureInfo.get(depthTexture).format === 3 ? gl.DEPTH_STENCIL_ATTACHMENT : gl.DEPTH_ATTACHMENT;
				gl.framebufferTexture2D(gl.FRAMEBUFFER, attachment, gl.TEXTURE_2D, get(depthTexture), 0);
			}
			gl.drawBuffers(buffers.length ? buffers : [gl.NONE]);
			if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) return false;
			gl.disable(gl.SCISSOR_TEST);
			gl.colorMask(true, true, true, true);
			const colors = new Uint8Array(bridge.memory.buffer, colorsPtr, colorCount * 4);
			for (let i = 0; i < Math.min(count, colorCount); ++i) gl.clearBufferfv(gl.COLOR, i, new Float32Array(Array.from(colors.subarray(i * 4, i * 4 + 4), c => c / 255)));
			if (clearDepth) { gl.depthMask(true); gl.clearBufferfv(gl.DEPTH, 0, new Float32Array([depth])); }
			if (clearStencil) { gl.stencilMask(255); gl.clearBufferiv(gl.STENCIL, 0, new Int32Array([stencil])); }
			return true;
		},
		fw_end_pass() {
			gl.disable(gl.SCISSOR_TEST);
			gl.bindVertexArray(null);
		},
		fw_bind_pipeline(h) {
			const prog = get(h);
			if (!prog) return;
			pendingMatrix = null;
			pendingFragFloat = null;
			gl.useProgram(prog.program);
			gl.bindVertexArray(prog.vao);
			if (prog.blendEnable) {
				gl.enable(gl.BLEND);
				gl.blendEquationSeparate(prog.cOp, prog.aOp);
				gl.blendFuncSeparate(prog.cSrc, prog.cDst, prog.aSrc, prog.aDst);
			} else {
				gl.disable(gl.BLEND);
			}
			const m = prog.colorMask;
			gl.colorMask(!!(m & 1), !!(m & 2), !!(m & 4), !!(m & 8));
			if (prog.cull) { gl.enable(gl.CULL_FACE); gl.cullFace(prog.cull); }
			else gl.disable(gl.CULL_FACE);
			// SDL's default front face is counterclockwise. Offscreen matrices
			// invert Y to preserve texture row order, so their winding is inverted.
			gl.frontFace(texturePass ? gl.CW : gl.CCW);
			const depth = prog.depth;
			if (depth && (depth.test || depth.write)) {
				gl.enable(gl.DEPTH_TEST);
				gl.depthFunc(depth.test ? COMPARE[depth.compare] : gl.ALWAYS);
			} else gl.disable(gl.DEPTH_TEST);
			gl.depthMask(!!(depth && depth.write));
			boundStencil = prog.stencil;
			if (boundStencil && boundStencil.test) {
				gl.enable(gl.STENCIL_TEST);
				gl.stencilMask(boundStencil.writeMask);
				for (const [face, state] of [[gl.FRONT, boundStencil.front], [gl.BACK, boundStencil.back]]) {
					gl.stencilOpSeparate(face, STENCIL_OP[state.fail], STENCIL_OP[state.depthFail], STENCIL_OP[state.pass]);
				}
				setStencilReference(0);
			} else gl.disable(gl.STENCIL_TEST);
		},
		fw_set_matrix4(stage, slot, dataPtr) {
			pendingMatrix = new Float32Array(bridge.memory.buffer, dataPtr, 16).slice();
			// Store offscreen rows in the same order as uploaded texture data.
			if (texturePass) for (const i of [1, 5, 9, 13]) pendingMatrix[i] = -pendingMatrix[i];
		},
		fw_set_float(stage, slot, value) {
			pendingFragFloat = value;
		},
		fw_bind_texture(unit, texture, sampler) {
			gl.activeTexture(gl.TEXTURE0 + unit);
			gl.bindTexture(gl.TEXTURE_2D, texture ? get(texture) : whiteTex);
			gl.bindSampler(unit, sampler ? get(sampler) : null);
		},
		fw_bind_vertex_buffer(slot, buffer, stride) {
			const b = get(buffer);
			if (!b) return;
			gl.bindBuffer(gl.ARRAY_BUFFER, b.gl);
		},
		fw_vertex_attribute(location, slot, typeOrdinal, normalized, stride, offset) {
			const vt = VERTEX_TYPE[typeOrdinal];
			if (!vt) return;
			gl.enableVertexAttribArray(location);
			gl.vertexAttribPointer(location, vt[0], vt[1], normalized !== 0, stride, offset);
		},
		fw_bind_index_buffer(buffer) {
			const b = get(buffer);
			if (!b) return;
			gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b.gl);
		},
		fw_draw_elements(count, indexType, byteOffset, instances) {
			applyPendingUniforms();
			if (instances > 1) gl.drawElementsInstanced(gl.TRIANGLES, count, INDEX_TYPE[indexType], byteOffset, instances);
			else gl.drawElements(gl.TRIANGLES, count, INDEX_TYPE[indexType], byteOffset);
		},
		fw_draw_arrays(count, offset, instances) {
			applyPendingUniforms();
			if (instances > 1) gl.drawArraysInstanced(gl.TRIANGLES, offset, count, instances);
			else gl.drawArrays(gl.TRIANGLES, offset, count);
		},
		fw_set_viewport(x, y, w, h, fbHeight) {
			gl.viewport(x, texturePass ? y : fbHeight - y - h, w, h);
		},
		fw_set_scissor(x, y, w, h, fbHeight) {
			gl.enable(gl.SCISSOR_TEST);
			gl.scissor(x, texturePass ? y : fbHeight - y - h, w, h);
		},

		// ---- M3: 相对鼠标 ----
		fw_set_mouse_relative(enabled) {
			if (enabled) {
				if (canvas.requestPointerLock) canvas.requestPointerLock();
			} else {
				if (document.exitPointerLock) document.exitPointerLock();
			}
		},

		// ---- 窗口全屏 ----
		fw_set_fullscreen(enabled) {
			try {
				if (enabled) {
					const el = document.documentElement;
					(el.requestFullscreen || el.webkitRequestFullscreen || function(){}).call(el);
				} else {
					(document.exitFullscreen || document.webkitExitFullscreen || function(){}).call(document);
				}
			} catch (e) { log("[foster.js] fullscreen: " + e); }
		},
		fw_is_fullscreen() {
			return (document.fullscreenElement || document.webkitFullscreenElement) ? 1 : 0;
		},

		// ---- M4: 虚拟文件系统(localStorage, 每文件一键, base64 二进制安全) ----
		fw_fs_exists(pathPtr, pathLen) {
			const path = fsPath(readString(pathPtr, pathLen));
			return localStorage.getItem(fsKey(path)) !== null || fsDirectory(path) ? 1 : 0;
		},
		fw_fs_is_directory(pathPtr, pathLen) { return fsDirectory(readString(pathPtr, pathLen)); },
		fw_fs_make_directory(pathPtr, pathLen) {
			try {
				const path = fsPath(readString(pathPtr, pathLen));
				if (localStorage.getItem(fsKey(path)) !== null) return false;
				localStorage.setItem(DIR_PREFIX + path, "1");
				return true;
			} catch (e) { return false; }
		},
		fw_fs_enumerate(pathPtr, pathLen, destination, capacity) {
			const path = fsPath(readString(pathPtr, pathLen));
			const names = new Set();
			for (const child of fsPaths()) if (fsDescendant(child, path)) names.add(child.slice(path === "/" ? 1 : path.length + 1).split("/")[0]);
			const data = new TextEncoder().encode(Array.from(names).sort().join("\0"));
			if (destination && capacity >= data.length) new Uint8Array(bridge.memory.buffer, destination, data.length).set(data);
			return data.length;
		},
		fw_fs_size(pathPtr, pathLen) {
			const b = fsReadBytes(readString(pathPtr, pathLen));
			return b === null ? -1 : b.length;
		},
		fw_fs_read(pathPtr, pathLen, bufPtr, bufLen) {
			const b = fsReadBytes(readString(pathPtr, pathLen));
			if (b === null) return -1;
			const n = Math.min(b.length, bufLen);
			new Uint8Array(bridge.memory.buffer, bufPtr, n).set(b.subarray(0, n));
			return n;
		},
		fw_image_write_png(pathPtr, pathLen, width, height, pixels) {
			try {
				const image = document.createElement("canvas");
				image.width = width;
				image.height = height;
				const context = image.getContext("2d");
				const data = new Uint8ClampedArray(bridge.memory.buffer, pixels, width * height * 4).slice();
				context.putImageData(new ImageData(data, width, height), 0, 0);
				const base64 = image.toDataURL("image/png").split(",")[1];
				fsWriteBytes(readString(pathPtr, pathLen), base64ToBytes(base64));
				return true;
			} catch (_) { return false; }
		},
		fw_dialog_start(request, kind, filtersPtr, filtersLen) {
			try { fileDialog(request, kind, JSON.parse(readString(filtersPtr, filtersLen))); }
			catch (_) { pushText(EV.DialogResult, "", request, 0); }
		},
		fw_fs_flush(request, pathPtr, pathLen) {
			const path = fsPath(readString(pathPtr, pathLen));
			const pending = pickedFiles.get(path)?.pending || Promise.resolve(localStorage.getItem(fsKey(path)) !== null);
			pending.then(success => push(EV.StorageFlushResult, request, success ? 1 : 0), () => push(EV.StorageFlushResult, request, 0));
		},
		fw_fs_write(pathPtr, pathLen, dataPtr, dataLen) {
			try {
				const bytes = new Uint8Array(bridge.memory.buffer, dataPtr, dataLen);
				fsWriteBytes(readString(pathPtr, pathLen), bytes);
				return 1;
			} catch (e) {
				log("[foster.js] fs write failed: " + e);
				return 0;
			}
		},
		fw_fs_remove(pathPtr, pathLen) {
			const path = fsPath(readString(pathPtr, pathLen));
			for (const child of fsPaths()) if (child === path || fsDescendant(child, path)) {
				localStorage.removeItem(fsKey(child));
				localStorage.removeItem(DIR_PREFIX + child);
				pickedFiles.delete(child);
			}
			return 1;
		},
	};

	function applyPendingUniforms() {
		if (pendingMatrix !== null) {
			const loc = uniformLoc("u_matrix");
			if (loc) gl.uniformMatrix4fv(loc, false, pendingMatrix);
		}
		if (pendingFragFloat !== null) {
			const loc = uniformLoc("u_distance_range");
			if (loc) gl.uniform1f(loc, pendingFragFloat);
		}
	}

	let currentProgram = null;
	function uniformLoc(name) {
		if (!currentProgram) return null;
		const prog = get(currentProgram);
		if (!prog) return null;
		if (!(name in prog.locs)) prog.locs[name] = gl.getUniformLocation(prog.program, name);
		return prog.locs[name];
	}

	// 追踪当前管线(applyPendingUniforms 用)
	const origBindPipeline = bridge.fw_bind_pipeline;
	bridge.fw_bind_pipeline = function (h) { currentProgram = h; origBindPipeline(h); };

	function readString(ptr, len) {
		return new TextDecoder("utf-8").decode(new Uint8Array(bridge.memory.buffer, ptr, len));
	}

	// --- 实例化 + 帧循环 ---
	(async () => {
		try {
			syncCanvasSize();
			const wmi = new odin.WasmMemoryInterface();
			const imports = odin.setupDefaultImports(wmi, logEl, null);
			imports.foster_web = countedBridge;
			// 游戏侧附加桥(如音频): 页面在加载 foster.js 前设置 window.FOSTER_EXTRA_IMPORTS
			const extras = window.FOSTER_EXTRA_IMPORTS || {};
			for (const k in extras) imports[k] = extras[k];
			const file = await (await fetch(WASM_URL, { cache: "no-cache" })).arrayBuffer();
			const wasm = await WebAssembly.instantiate(file, imports);
			const exp = wasm.instance.exports;
			wmi.setExports(exp);
			if (exp.memory) {
				wmi.setMemory(exp.memory);
				bridge.setMemory(exp.memory);
				for (const k in extras) {
					if (extras[k] && typeof extras[k].setMemory === "function") extras[k].setMemory(exp.memory);
				}
			}
			window.__fosterExports = exp;
			log("[foster.js] instantiated, exports: " + Object.keys(exp).filter(k => !k.startsWith("_")).join(","));

			if (exp._start) exp._start(); // main → InitApp → Run(注册 web_app 后返回)

			if (exp.foster_step) {
				const ctxPtr = exp.default_context_ptr();
				let prev = undefined;
				const frame = (ts) => {
					if (prev === undefined) prev = ts;
					const dt = (ts - prev) * 0.001;
					prev = ts;
					let keep = true;
					try {
						pollGamepads();
						keep = exp.foster_step(dt, ctxPtr);
					} catch (e) {
						log("[foster.js] foster_step ERROR: " + e);
						return; // 停止帧循环, 避免错误刷屏
					}
					if (keep) requestAnimationFrame(frame);
				};
				requestAnimationFrame(frame);
			} else {
				log("[foster.js] no foster_step export — did the app call foster.Run?");
			}
		} catch (e) {
			log("[foster.js] ERROR " + e);
		}
	})();
})();
