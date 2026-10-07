package foster_framework

import "core:math"
import coretime "core:time"
import SDL "vendor:sdl3"
import "core:time"
import "core:c"
import "core:strings"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Input / Enums — 输入标识与枚举
//   Input / Input — 内部坐标与启用选项
//   Input / Input — 事件、双缓冲与虚拟输入注册
//   Input / Bindings — 输入绑定
//   Input / Sets — 绑定组合
//   Input / Virtual — 虚拟输入
//   Input / InputProvider — 独立输入供给
//   Input / Cursor — 光标

// ==============================================================================
// Input / Enums — 输入标识与枚举
// ==============================================================================

ControllerID :: distinct u32

// ------------------------------------------------------------------------------
// Input / Enums / Keys
// ------------------------------------------------------------------------------

Keys :: enum int {
	Unknown = 0,
	A = 4,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	D1 = 30,
	D2,
	D3,
	D4,
	D5,
	D6,
	D7,
	D8,
	D9,
	D0,
	Enter = 40,
	Escape,
	Backspace,
	Tab,
	Space,
	Minus,
	Equals,
	LeftBracket,
	RightBracket,
	Backslash,
	Semicolon = 51,
	Apostrophe,
	Tilde,
	Comma,
	Period,
	Slash,
	Capslock,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	PrintScreen = 70,
	ScrollLock,
	Pause,
	Insert,
	Home,
	PageUp,
	Delete,
	End,
	PageDown,
	Right,
	Left,
	Down,
	Up,
	Numlock,
	Application = 101,
	KeypadEquals = 103,
	F13 = 104,
	F14,
	F15,
	F16,
	F17,
	F18,
	F19,
	F20,
	F21,
	F22,
	F23,
	F24,
	Execute = 116,
	Help,
	Menu,
	Select,
	Stop,
	Redo,
	Undo,
	Cut,
	Copy,
	Paste,
	Find,
	Mute,
	VolumeUp,
	VolumeDown,
	KeypadComma = 133,
	AltErase = 153,
	SysReq,
	Cancel,
	Clear,
	Prior,
	Enter2,
	Separator,
	Out,
	Oper,
	ClearAgain,
	Keypad00 = 176,
	Keypad000,
	KeypadLeftParen = 182,
	KeypadRightParen,
	KeypadLeftBrace,
	KeypadRightBrace,
	KeypadTab,
	KeypadBackspace,
	KeypadA,
	KeypadB,
	KeypadC,
	KeypadD,
	KeypadE,
	KeypadF,
	KeypadXor,
	KeypadPower,
	KeypadPercent,
	KeypadLess,
	KeypadGreater,
	KeypadAmpersand = 199,
	KeypadColon = 203,
	KeypadHash,
	KeypadSpace,
	KeypadClear = 216,
	LeftControl = 224,
	LeftShift,
	LeftAlt,
	LeftOS,
	RightControl,
	RightShift,
	RightAlt,
	RightOS,
	KeypadDivide = 84,
	KeypadMultiply = 85,
	KeypadMinus = 86,
	KeypadPlus = 87,
	KeypadEnter = 88,
	Keypad1 = 89,
	Keypad2 = 90,
	Keypad3 = 91,
	Keypad4 = 92,
	Keypad5 = 93,
	Keypad6 = 94,
	Keypad7 = 95,
	Keypad8 = 96,
	Keypad9 = 97,
	Keypad0 = 98,
	KeypadPeroid = 99,
}

// ------------------------------------------------------------------------------
// Input / Enums / Buttons & Axes
// ------------------------------------------------------------------------------

Buttons :: enum int {
	None = -1,
	South = 0,
	East,
	West,
	North,
	Back,
	Guide,
	Start,
	LeftStick,
	RightStick,
	LeftShoulder,
	RightShoulder,
	Up,
	Down,
	Left,
	Right,
}

Axes :: enum int {
	None = -1,
	LeftX = 0,
	LeftY,
	RightX,
	RightY,
	LeftTrigger,
	RightTrigger,
}

// ------------------------------------------------------------------------------
// Input / Enums / GamepadProviders & GamepadTypes
// ------------------------------------------------------------------------------

GamepadProviders :: enum {
	Unknown,
	Xbox,
	PlayStation,
	Nintendo,
}

GamepadTypes :: enum int {
	Unknown = 0,
	Standard,
	Xbox360,
	XboxOne,
	PS3,
	PS4,
	PS5,
	NintendoSwitchPro,
	NintendoSwitchJoyconLeft,
	NintendoSwitchJoyconRight,
	NintendoSwitchJoyconPair,
}

provider :: proc(t: GamepadTypes) -> GamepadProviders {
	#partial switch t {
	case .Standard, .Xbox360, .XboxOne:
		return .Xbox
	case .PS3, .PS4, .PS5:
		return .PlayStation
	case .NintendoSwitchPro,
	     .NintendoSwitchJoyconLeft,
	     .NintendoSwitchJoyconRight,
	     .NintendoSwitchJoyconPair:
		return .Nintendo
	}
	return .Unknown
}

// ------------------------------------------------------------------------------
// Input / Enums / MouseButtons
// ------------------------------------------------------------------------------

MouseButtons :: enum int {
	None   = 0,
	Left   = 1,
	Middle = 2,
	Right  = 3,
}

// ==============================================================================
// Input / Input — 内部坐标与启用选项
// ==============================================================================

Vec2f :: struct {
	X: f32,
	Y: f32,
}

InputEnabledFlag :: enum u8 {
	KeyboardKeys,
	Text,
	ControllerButtons,
	ControllerAxis,
	MouseButtons,
	MouseMotion,
	MouseWheel,
}

InputEnabledFlags :: distinct bit_set[InputEnabledFlag;u8]

InputEnabledAll: InputEnabledFlags : {
	.KeyboardKeys,
	.Text,
	.ControllerButtons,
	.ControllerAxis,
	.MouseButtons,
	.MouseMotion,
	.MouseWheel,
}
InputEnabledNone: InputEnabledFlags : {}

RepeatDelay: f32 = 0.4
RepeatInterval: f32 = 0.03

TextInputHandlerFn :: #type proc(text: string, window: ^Window)
ControllerConnectedFn :: #type proc(id: ControllerID)
ControllerDisconnectedFn :: #type proc(id: ControllerID)

KeyboardMaxKeys :: 512
MouseMaxButtons :: 5
ControllerMaxButtons :: 64
ControllerMaxAxes :: 64
InputMaxControllers :: 32

// ------------------------------------------------------------------------------
// Input / KeyboardState — 键盘状态定义
// ------------------------------------------------------------------------------

KeyboardState :: struct {
	text_storage:   [dynamic]u8,
	Text:           string,
	InputTimestamp: coretime.Duration,
	pressed:        [KeyboardMaxKeys]bool,
	down:           [KeyboardMaxKeys]bool,
	released:       [KeyboardMaxKeys]bool,
	timestamp:      [KeyboardMaxKeys]coretime.Duration,
	time:           Time,
}

// ------------------------------------------------------------------------------
// Input / MouseState — 鼠标状态定义
// ------------------------------------------------------------------------------

MouseState :: struct {
	InputTimestamp:   coretime.Duration,
	Position:         Vec2f,
	Delta:            Vec2f,
	Wheel:            Vec2f,
	pressed:          [MouseMaxButtons]bool,
	down:             [MouseMaxButtons]bool,
	released:         [MouseMaxButtons]bool,
	timestamp:        [MouseMaxButtons]coretime.Duration,
	motion_timestamp: coretime.Duration,
	time:             Time,
}

// ------------------------------------------------------------------------------
// Input / ControllerState — 控制器状态定义
// ------------------------------------------------------------------------------

ControllerState :: struct {
	Index:          int,
	ID:             ControllerID,
	Name:           string,
	Connected:      bool,
	IsGamepad:      bool,
	InputTimestamp: coretime.Duration,
	GamepadType:    GamepadTypes,
	Buttons:        int,
	Axes:           int,
	Vendor:         u16,
	Product:        u16,
	Version:        u16,
	pressed:        [ControllerMaxButtons]bool,
	down:           [ControllerMaxButtons]bool,
	released:       [ControllerMaxButtons]bool,
	timestamp:      [ControllerMaxButtons]coretime.Duration,
	axis:           [ControllerMaxAxes]f32,
	axis_timestamp: [ControllerMaxAxes]coretime.Duration,
	time:           Time,
}

// ------------------------------------------------------------------------------
// Input / InputState — 状态快照与设备句柄
// ------------------------------------------------------------------------------

InputState :: struct {
	Keyboard:    KeyboardState,
	Mouse:       MouseState,
	Controllers: [InputMaxControllers]ControllerState,
}

JoystickHandle :: struct {
	ID:  SDL.JoystickID,
	Ptr: ^SDL.Joystick,
}

GamepadHandle :: struct {
	ID:  SDL.JoystickID,
	Ptr: ^SDL.Gamepad,
}

// ==============================================================================
// Input / Input — 事件、双缓冲与虚拟输入注册
// ==============================================================================

Input :: struct {
	BindingFilters:           []string,
	App:                      ^App,
	State:                    InputState,
	LastState:                InputState,
	NextState:                InputState,
	Enabled:                  InputEnabledFlags,
	OnTextEvent:              TextInputHandlerFn,
	OnControllerConnected:    ControllerConnectedFn,
	OnControllerDisconnected: ControllerDisconnectedFn,
	last_mouse:               Vec2f,
	open_joysticks:           [dynamic]JoystickHandle,
	open_gamepads:            [dynamic]GamepadHandle,
	owned_controller_names:   [dynamic]string,
}

time_seconds :: proc(d: coretime.Duration) -> f64 {
	return coretime.duration_seconds(d)
}

trigger_repeat :: proc(time: Time, stamp: coretime.Duration, delay, interval: f32) -> bool {
	elapsed := time_seconds(time.Elapsed)
	previous := time_seconds(time.Previous)
	start := time_seconds(stamp) + f64(delay)
	if elapsed < start {
		return false
	}
	a := int(math.floor((previous - start) / f64(interval)))
	b := int(math.floor((elapsed - start) / f64(interval)))
	return b > a
}

// ------------------------------------------------------------------------------
// Input / KeyboardState — 状态操作
// ------------------------------------------------------------------------------

keyboard_clear :: proc(k: ^KeyboardState) {
	clear(&k.text_storage)
	k.Text = ""
	k.InputTimestamp = 0
	for i in 0 ..< KeyboardMaxKeys {
		k.pressed[i] = false
		k.down[i] = false
		k.released[i] = false
		k.timestamp[i] = 0
	}
}

keyboard_copy :: proc(dst: ^KeyboardState, src: KeyboardState) {
	clear(&dst.text_storage)
	append(&dst.text_storage, ..transmute([]u8)src.Text)
	dst.Text = string(dst.text_storage[:])
	dst.InputTimestamp = src.InputTimestamp
	dst.time = src.time
	dst.pressed = src.pressed
	dst.down = src.down
	dst.released = src.released
	dst.timestamp = src.timestamp
}

keyboard_step :: proc(k: ^KeyboardState, time: Time) {
	k.time = time
	clear(&k.text_storage)
	k.Text = ""
	for i in 0 ..< KeyboardMaxKeys {
		k.pressed[i] = false
		k.released[i] = false
	}
}

keyboard_on_key :: proc(
	k: ^KeyboardState,
	key_index: int,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if key_index < 0 || key_index >= KeyboardMaxKeys {
		return
	}
	if pressed {
		k.down[key_index] = true
		k.pressed[key_index] = true
		k.timestamp[key_index] = stamp
		k.InputTimestamp = stamp
	} else {
		k.down[key_index] = false
		k.released[key_index] = true
	}
}

// ------------------------------------------------------------------------------
// Input / MouseState — 状态操作
// ------------------------------------------------------------------------------

mouse_clear :: proc(m: ^MouseState) {
	m.InputTimestamp = 0
	m.Position = {}
	m.Delta = {}
	m.Wheel = {}
	m.motion_timestamp = 0
	for i in 0 ..< MouseMaxButtons {
		m.pressed[i] = false
		m.down[i] = false
		m.released[i] = false
		m.timestamp[i] = 0
	}
}

mouse_copy :: proc(dst: ^MouseState, src: MouseState) {
	dst.InputTimestamp = src.InputTimestamp
	dst.Position = src.Position
	dst.Delta = src.Delta
	dst.Wheel = src.Wheel
	dst.motion_timestamp = src.motion_timestamp
	dst.time = src.time
	dst.pressed = src.pressed
	dst.down = src.down
	dst.released = src.released
	dst.timestamp = src.timestamp
}

mouse_step :: proc(m: ^MouseState, time: Time) {
	m.time = time
	m.Delta = {}
	m.Wheel = {}
	for i in 0 ..< MouseMaxButtons {
		m.pressed[i] = false
		m.released[i] = false
	}
}

mouse_on_button :: proc(
	m: ^MouseState,
	button_index: int,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if button_index < 0 || button_index >= MouseMaxButtons {
		return
	}
	if pressed {
		m.down[button_index] = true
		m.pressed[button_index] = true
		m.timestamp[button_index] = stamp
		m.InputTimestamp = stamp
	} else {
		m.down[button_index] = false
		m.released[button_index] = true
	}
}

mouse_on_motion :: proc(m: ^MouseState, position, delta: Vec2f, stamp: coretime.Duration) {
	m.Position = position
	m.Delta = delta
	m.motion_timestamp = stamp
	m.InputTimestamp = stamp
}

mouse_on_wheel :: proc(m: ^MouseState, wheel: Vec2f) {
	m.Wheel = wheel
}

// ------------------------------------------------------------------------------
// Input / States / ControllerState — 状态操作
// ------------------------------------------------------------------------------

controller_clear_state :: proc(c: ^ControllerState) {
	c.InputTimestamp = 0
	for i in 0 ..< ControllerMaxButtons {
		c.pressed[i] = false
		c.down[i] = false
		c.released[i] = false
		c.timestamp[i] = 0
	}
	for i in 0 ..< ControllerMaxAxes {
		c.axis[i] = 0
		c.axis_timestamp[i] = 0
	}
}

controller_disconnect :: proc(c: ^ControllerState) {
	c.ID = ControllerID(0)
	c.Name = "Unknown"
	c.Connected = false
	c.IsGamepad = false
	c.GamepadType = .Unknown
	c.Buttons = 0
	c.Axes = 0
	c.Vendor = 0
	c.Product = 0
	c.Version = 0
	controller_clear_state(c)
}

controller_copy :: proc(dst: ^ControllerState, src: ControllerState) {
	dst.Index = src.Index
	dst.ID = src.ID
	dst.Name = src.Name
	dst.Connected = src.Connected
	dst.IsGamepad = src.IsGamepad
	dst.InputTimestamp = src.InputTimestamp
	dst.GamepadType = src.GamepadType
	dst.Buttons = src.Buttons
	dst.Axes = src.Axes
	dst.Vendor = src.Vendor
	dst.Product = src.Product
	dst.Version = src.Version
	dst.time = src.time
	dst.pressed = src.pressed
	dst.down = src.down
	dst.released = src.released
	dst.timestamp = src.timestamp
	dst.axis = src.axis
	dst.axis_timestamp = src.axis_timestamp
}

controller_step :: proc(c: ^ControllerState, time: Time) {
	c.time = time
	for i in 0 ..< ControllerMaxButtons {
		c.pressed[i] = false
		c.released[i] = false
	}
}

controller_connect :: proc(
	c: ^ControllerState,
	id: ControllerID,
	name: string,
	button_count, axis_count: int,
	is_gamepad: bool,
	gamepad_type: GamepadTypes,
	vendor, product, version: u16,
) {
	c.ID = id
	c.Name = name
	c.Connected = true
	c.IsGamepad = is_gamepad
	c.GamepadType = gamepad_type
	c.Buttons = min(button_count, ControllerMaxButtons)
	c.Axes = min(axis_count, ControllerMaxAxes)
	c.Vendor = vendor
	c.Product = product
	c.Version = version
}

controller_on_button :: proc(
	c: ^ControllerState,
	button_index: int,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if button_index < 0 || button_index >= ControllerMaxButtons {
		return
	}
	if pressed {
		c.down[button_index] = true
		c.pressed[button_index] = true
		c.timestamp[button_index] = stamp
		c.InputTimestamp = stamp
	} else {
		c.down[button_index] = false
		c.released[button_index] = true
	}
}

controller_on_axis :: proc(
	c: ^ControllerState,
	axis_index: int,
	value: f32,
	stamp: coretime.Duration,
) {
	if axis_index < 0 || axis_index >= ControllerMaxAxes {
		return
	}
	c.axis[axis_index] = value
	c.axis_timestamp[axis_index] = stamp
	if math.abs(value) > 0.5 {
		c.InputTimestamp = stamp
	}
}

input_state_init :: proc(state: ^InputState) {
	keyboard_clear(&state.Keyboard)
	mouse_clear(&state.Mouse)
	for i in 0 ..< InputMaxControllers {
		state.Controllers[i].Index = i
		controller_disconnect(&state.Controllers[i])
	}
}

input_state_copy :: proc(dst: ^InputState, src: InputState) {
	keyboard_copy(&dst.Keyboard, src.Keyboard)
	mouse_copy(&dst.Mouse, src.Mouse)
	for i in 0 ..< InputMaxControllers {
		controller_copy(&dst.Controllers[i], src.Controllers[i])
	}
}

input_state_step :: proc(state: ^InputState, time: Time) {
	keyboard_step(&state.Keyboard, time)
	mouse_step(&state.Mouse, time)
	for i in 0 ..< InputMaxControllers {
		if state.Controllers[i].Connected {
			controller_step(&state.Controllers[i], time)
		}
	}
}

// ------------------------------------------------------------------------------
// Input / Input / Lifecycle — 初始化、事件供给与帧更新
// ------------------------------------------------------------------------------

input_init :: proc(input: ^Input, app: ^App) {
	input.App = app
	input.Enabled = InputEnabledAll
	input_state_init(&input.State)
	input_state_init(&input.LastState)
	input_state_init(&input.NextState)
}

input_step :: proc(input: ^Input, time: Time) {
	input_state_copy(&input.LastState, input.State)
	input_state_copy(&input.State, input.NextState)
	input_state_step(&input.NextState, time)
}

get_controller :: proc(input: ^Input, id: ControllerID) -> ^ControllerState {
	for i in 0 ..< InputMaxControllers {
		if input.State.Controllers[i].ID == id {
			return &input.State.Controllers[i]
		}
	}
	return nil
}

get_next_controller :: proc(input: ^Input, id: ControllerID) -> ^ControllerState {
	for i in 0 ..< InputMaxControllers {
		if input.NextState.Controllers[i].ID == id {
			return &input.NextState.Controllers[i]
		}
	}
	return nil
}

input_connect_controller :: proc(
	input: ^Input,
	id: ControllerID,
	name: string,
	button_count, axis_count: int,
	is_gamepad: bool,
	gamepad_type: GamepadTypes,
	vendor, product, version: u16,
) {
	for i in 0 ..< InputMaxControllers {
		if input.NextState.Controllers[i].Connected {
			continue
		}
		controller_connect(
			&input.NextState.Controllers[i],
			id,
			name,
			button_count,
			axis_count,
			is_gamepad,
			gamepad_type,
			vendor,
			product,
			version,
		)
		if input.OnControllerConnected != nil {
			input.OnControllerConnected(id)
		}
		return
	}
}

input_disconnect_controller :: proc(input: ^Input, id: ControllerID) {
	for i in 0 ..< InputMaxControllers {
		if input.NextState.Controllers[i].ID != id {
			continue
		}
		controller_disconnect(&input.NextState.Controllers[i])
		if input.OnControllerDisconnected != nil {
			input.OnControllerDisconnected(id)
		}
		return
	}
}

input_key :: proc(input: ^Input, key: Keys, pressed: bool, stamp: coretime.Duration) {
	if !(.KeyboardKeys in input.Enabled) {
		return
	}
	keyboard_on_key(&input.NextState.Keyboard, int(key), pressed, stamp)
}

input_mouse_button :: proc(
	input: ^Input,
	button: MouseButtons,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if !(.MouseButtons in input.Enabled) {
		return
	}
	mouse_on_button(&input.NextState.Mouse, int(button), pressed, stamp)
}

input_mouse_move :: proc(input: ^Input, position, delta: Vec2f, stamp: coretime.Duration) {
	if !(.MouseMotion in input.Enabled) {
		return
	}
	mouse_on_motion(&input.NextState.Mouse, position, delta, stamp)
}

input_mouse_wheel :: proc(input: ^Input, wheel: Vec2f) {
	if !(.MouseWheel in input.Enabled) {
		return
	}
	mouse_on_wheel(&input.NextState.Mouse, wheel)
}

input_text :: proc(input: ^Input, text: string, window: ^Window) {
	if !(.Text in input.Enabled) || text == "" {
		return
	}
	append(&input.NextState.Keyboard.text_storage, ..transmute([]u8)text)
	input.NextState.Keyboard.Text = string(input.NextState.Keyboard.text_storage[:])
	if input.OnTextEvent != nil {
		input.OnTextEvent(text, window)
	}
}

input_controller_button :: proc(
	input: ^Input,
	id: ControllerID,
	button: int,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if !(.ControllerButtons in input.Enabled) {
		return
	}
	controller := get_next_controller(input, id)
	if controller != nil {
		controller_on_button(controller, button, pressed, stamp)
	}
}

input_controller_axis :: proc(
	input: ^Input,
	id: ControllerID,
	axis: int,
	value: f32,
	stamp: coretime.Duration,
) {
	if !(.ControllerAxis in input.Enabled) {
		return
	}
	controller := get_next_controller(input, id)
	if controller != nil {
		controller_on_axis(controller, axis, value, stamp)
	}
}

input_update :: proc(input: ^Input, window: ^Window, stamp: coretime.Duration) {
	when ODIN_OS == .JS {
		// Web: 鼠标状态由 DOM 事件驱动(foster.js 队列), 无逐帧轮询; M3 接入
		_ = input
		_ = stamp
		return
	}
	if window == nil || window.Handle == nil {
		return
	}

	// Wayland 不提供屏幕全局坐标(GetGlobalMouseState 与窗口位置恒为 0),
	// 导致鼠标位置永远停在 (0,0)、所有点击判定失效。
	// 改用窗口相对坐标的 GetMouseState: 各平台一致且 Wayland 安全。
	wx, wy: f32
	_ = SDL.GetMouseState(&wx, &wy)
	size := window_size(window)
	size_px := window_size_in_pixels(window)

	mouse_x := wx
	mouse_y := wy
	if size.X != 0 && size.Y != 0 {
		mouse_x = mouse_x / f32(size.X) * f32(size_px.X)
		mouse_y = mouse_y / f32(size.Y) * f32(size_px.Y)
	}

	delta := Vec2f{mouse_x - input.last_mouse.X, mouse_y - input.last_mouse.Y}
	if SDL.GetWindowRelativeMouseMode(window.Handle) {
		dx, dy: f32
		_ = SDL.GetRelativeMouseState(&dx, &dy)
		if size.X != 0 && size.Y != 0 {
			delta = Vec2f{dx / f32(size.X) * f32(size_px.X), dy / f32(size.Y) * f32(size_px.Y)}
		} else {
			delta = Vec2f{dx, dy}
		}
	}

	position := Vec2f{mouse_x, mouse_y}
	if position.X != input.last_mouse.X ||
	   position.Y != input.last_mouse.Y ||
	   delta.X != 0 ||
	   delta.Y != 0 {
		input.last_mouse = position
		input_mouse_move(input, position, delta, stamp)
	}
}

input_set_clipboard :: proc(input: ^Input, value: string) -> bool {
	_ = input
	when ODIN_OS == .JS {
		ptr, length := web_string_bytes(value)
		return fw_clipboard_write(0, ptr, length)
	}
	return SDL.SetClipboardText(to_cstring(value))
}

input_get_clipboard :: proc(input: ^Input) -> string {
	_ = input
	when ODIN_OS == .JS {
		length := fw_clipboard_cached(nil, 0)
		data := make([]u8, int(length))
		_ = fw_clipboard_cached(raw_data(data), length)
		return string(data)
	}
	text := SDL.GetClipboardText()
	if text == nil {
		return ""
	}
	defer SDL.free(text)
	owned, _ := strings.clone(string(cstring(text)))
	return owned
}

// ------------------------------------------------------------------------------
// Input / Input / Clipboard — 同步缓存与异步系统剪贴板
// ------------------------------------------------------------------------------

// 回调中的字符串仅在回调期间有效；需要保留时由调用方复制。
ClipboardCallback :: #type proc(text: string, succeeded: bool)

RequestClipboardString :: proc(input: ^Input, callback: ClipboardCallback) {
	if callback == nil {
		return
	}
	when ODIN_OS == .JS {
		fw_clipboard_read(web_clipboard_register(callback))
	} else {
		text := SDL.GetClipboardText()
		if text == nil {
			callback("", false)
			return
		}
		defer SDL.free(text)
		callback(string(cstring(text)), true)
	}
}

SetClipboardStringAsync :: proc(input: ^Input, value: string, callback: ClipboardCallback) {
	when ODIN_OS == .JS {
		ptr, length := web_string_bytes(value)
		_ = fw_clipboard_write(web_clipboard_register(callback), ptr, length)
	} else {
		succeeded := input_set_clipboard(input, value)
		if callback != nil {
			callback(value, succeeded)
		}
	}
}

input_rumble :: proc(
	input: ^Input,
	id: ControllerID,
	low_intensity, high_intensity, duration: f32,
) {
	when ODIN_OS == .JS {
		fw_rumble(u32(id), low_intensity, high_intensity, duration)
		return
	}
	_ = input
	low := u16(math.clamp(low_intensity, 0, 1) * 65535)
	high := u16(math.clamp(high_intensity, 0, 1) * 65535)
	ms := u32(duration * 1000)
	gamepad := SDL.GetGamepadFromID(cast(SDL.JoystickID)u32(id))
	if gamepad != nil {
		_ = SDL.RumbleGamepad(gamepad, low, high, ms)
		return
	}
	joystick := SDL.GetJoystickFromID(cast(SDL.JoystickID)u32(id))
	if joystick != nil {
		_ = SDL.RumbleJoystick(joystick, low, high, ms)
	}
}

input_close_devices :: proc(input: ^Input) {
	if input == nil {
		return
	}
	keyboards := [3]^KeyboardState {
		&input.State.Keyboard,
		&input.LastState.Keyboard,
		&input.NextState.Keyboard,
	}
	for keyboard in keyboards {
		delete(keyboard.text_storage)
		keyboard.text_storage = nil
		keyboard.Text = ""
	}
	for name in input.owned_controller_names {
		delete(name)
	}
	delete(input.owned_controller_names)
	input.owned_controller_names = nil
	when ODIN_OS == .JS {
		delete(input.open_joysticks)
		delete(input.open_gamepads)
		input.open_joysticks = nil
		input.open_gamepads = nil
		return
	}
	for joystick in input.open_joysticks {
		if joystick.Ptr != nil {
			SDL.CloseJoystick(joystick.Ptr)
		}
	}
	for gamepad in input.open_gamepads {
		if gamepad.Ptr != nil {
			SDL.CloseGamepad(gamepad.Ptr)
		}
	}
	delete(input.open_joysticks)
	delete(input.open_gamepads)
	input.open_joysticks = nil
	input.open_gamepads = nil
}

// 释放自己拥有的设备句柄和文本缓冲；BindingFilters 与 App 为借用。

InputDispose :: proc(input: ^Input) {
	input_close_devices(input)
	if input != nil {
		input^ = {}
	}
}

gamepad_name :: proc(ptr: ^SDL.Gamepad, fallback_id: SDL.JoystickID) -> string {
	if ptr != nil {
		return string(SDL.GetGamepadName(ptr))
	}
	return string(SDL.GetGamepadNameForID(fallback_id))
}

joystick_name :: proc(ptr: ^SDL.Joystick, fallback_id: SDL.JoystickID) -> string {
	if ptr != nil {
		return string(SDL.GetJoystickName(ptr))
	}
	return string(SDL.GetJoystickNameForID(fallback_id))
}

normalize_axis :: proc(value: i16) -> f32 {
	if value >= 0 {
		return f32(value) / 32767.0
	}
	return f32(value) / 32768.0
}

input_on_event :: proc(
	input: ^Input,
	window: ^Window,
	event: ^SDL.Event,
	stamp: coretime.Duration,
) {
	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		input_mouse_button(input, cast(MouseButtons)int(event.button.button), true, stamp)
	case .MOUSE_BUTTON_UP:
		input_mouse_button(input, cast(MouseButtons)int(event.button.button), false, stamp)
	case .MOUSE_WHEEL:
		input_mouse_wheel(input, Vec2f{event.wheel.x, event.wheel.y})
	case .KEY_DOWN:
		if !event.key.repeat {
			input_key(input, cast(Keys)int(event.key.scancode), true, stamp)
		}
	case .KEY_UP:
		if !event.key.repeat {
			input_key(input, cast(Keys)int(event.key.scancode), false, stamp)
		}
	case .TEXT_INPUT:
		input_text(input, string(event.text.text), window)
	case .JOYSTICK_ADDED:
		id := event.jdevice.which
		if SDL.IsGamepad(id) {
			break
		}
		ptr := SDL.OpenJoystick(id)
		append(&input.open_joysticks, JoystickHandle{id, ptr})
		input_connect_controller(
			input,
			ControllerID(u32(id)),
			joystick_name(ptr, id),
			int(SDL.GetNumJoystickButtons(ptr)),
			int(SDL.GetNumJoystickAxes(ptr)),
			false,
			.Unknown,
			u16(SDL.GetJoystickVendor(ptr)),
			u16(SDL.GetJoystickProduct(ptr)),
			u16(SDL.GetJoystickProductVersion(ptr)),
		)
	case .JOYSTICK_REMOVED:
		id := event.jdevice.which
		if SDL.IsGamepad(id) {
			break
		}
		for i := len(input.open_joysticks) - 1; i >= 0; i -= 1 {
			if input.open_joysticks[i].ID == id {
				if input.open_joysticks[i].Ptr != nil {
					SDL.CloseJoystick(input.open_joysticks[i].Ptr)
				}
				ordered_remove(&input.open_joysticks, i)
			}
		}
		input_disconnect_controller(input, ControllerID(u32(id)))
	case .JOYSTICK_BUTTON_DOWN:
		if !SDL.IsGamepad(event.jbutton.which) {
			input_controller_button(
				input,
				ControllerID(u32(event.jbutton.which)),
				int(event.jbutton.button),
				true,
				stamp,
			)
		}
	case .JOYSTICK_BUTTON_UP:
		if !SDL.IsGamepad(event.jbutton.which) {
			input_controller_button(
				input,
				ControllerID(u32(event.jbutton.which)),
				int(event.jbutton.button),
				false,
				stamp,
			)
		}
	case .JOYSTICK_AXIS_MOTION:
		if !SDL.IsGamepad(event.jaxis.which) {
			input_controller_axis(
				input,
				ControllerID(u32(event.jaxis.which)),
				int(event.jaxis.axis),
				normalize_axis(event.jaxis.value),
				stamp,
			)
		}
	case .GAMEPAD_ADDED:
		id := event.gdevice.which
		ptr := SDL.OpenGamepad(id)
		append(&input.open_gamepads, GamepadHandle{id, ptr})
		input_connect_controller(
			input,
			ControllerID(u32(id)),
			gamepad_name(ptr, id),
			15,
			6,
			true,
			cast(GamepadTypes)int(SDL.GetGamepadType(ptr)),
			u16(SDL.GetGamepadVendor(ptr)),
			u16(SDL.GetGamepadProduct(ptr)),
			u16(SDL.GetGamepadProductVersion(ptr)),
		)
	case .GAMEPAD_REMOVED:
		id := event.gdevice.which
		for i := len(input.open_gamepads) - 1; i >= 0; i -= 1 {
			if input.open_gamepads[i].ID == id {
				if input.open_gamepads[i].Ptr != nil {
					SDL.CloseGamepad(input.open_gamepads[i].Ptr)
				}
				ordered_remove(&input.open_gamepads, i)
			}
		}
		input_disconnect_controller(input, ControllerID(u32(id)))
	case .GAMEPAD_BUTTON_DOWN:
		input_controller_button(
			input,
			ControllerID(u32(event.gbutton.which)),
			int(cast(SDL.GamepadButton)event.gbutton.button),
			true,
			stamp,
		)
	case .GAMEPAD_BUTTON_UP:
		input_controller_button(
			input,
			ControllerID(u32(event.gbutton.which)),
			int(cast(SDL.GamepadButton)event.gbutton.button),
			false,
			stamp,
		)
	case .GAMEPAD_AXIS_MOTION:
		input_controller_axis(
			input,
			ControllerID(u32(event.gaxis.which)),
			int(cast(SDL.GamepadAxis)event.gaxis.axis),
			normalize_axis(event.gaxis.value),
			stamp,
		)
	}
}

KeyboardPressed :: proc(state: ^KeyboardState, key: Keys) -> bool {
	i := int(key)
	return state != nil && i >= 0 && i < KeyboardMaxKeys && state.pressed[i]
}

KeyboardDown :: proc(state: ^KeyboardState, key: Keys) -> bool {
	i := int(key)
	return state != nil && i >= 0 && i < KeyboardMaxKeys && state.down[i]
}

KeyboardReleased :: proc(state: ^KeyboardState, key: Keys) -> bool {
	i := int(key)
	return state != nil && i >= 0 && i < KeyboardMaxKeys && state.released[i]
}

Timestamp :: proc(state: ^KeyboardState, key: Keys) -> coretime.Duration {
	i := int(key)
	if state == nil || i < 0 || i >= KeyboardMaxKeys {
		return 0
	}
	return state.timestamp[i]
}

Repeated :: proc(
	state: ^KeyboardState,
	key: Keys,
	delay := RepeatDelay,
	interval := RepeatInterval,
) -> bool {
	if KeyboardPressed(state, key) {
		return true
	}
	return(
		KeyboardDown(state, key) &&
		trigger_repeat(state.time, Timestamp(state, key), delay, interval) \
	)
}

PressedOrRepeated :: proc(
	state: ^KeyboardState,
	key: Keys,
	delay := RepeatDelay,
	interval := RepeatInterval,
) -> bool {
	return KeyboardPressed(state, key) || Repeated(state, key, delay, interval)
}

KeyboardFirstDown :: proc(state: ^KeyboardState) -> (Keys, bool) {
	if state == nil {
		return .Unknown, false
	}
	for i in 0 ..< KeyboardMaxKeys {
		if state.down[i] {
			return Keys(i), true
		}
	}
	return .Unknown, false
}

KeyboardFirstPressed :: proc(state: ^KeyboardState) -> (Keys, bool) {
	if state == nil {
		return .Unknown, false
	}
	for i in 0 ..< KeyboardMaxKeys {
		if state.pressed[i] {
			return Keys(i), true
		}
	}
	return .Unknown, false
}

KeyboardFirstReleased :: proc(state: ^KeyboardState) -> (Keys, bool) {
	if state == nil {
		return .Unknown, false
	}
	for i in 0 ..< KeyboardMaxKeys {
		if state.released[i] {
			return Keys(i), true
		}
	}
	return .Unknown, false
}

KeyboardCtrl :: proc(state: ^KeyboardState) -> bool {
	return(
		state != nil &&
		(KeyboardDown(state, .LeftControl) || KeyboardDown(state, .RightControl)) \
	)
}

KeyboardShift :: proc(state: ^KeyboardState) -> bool {
	return state != nil && (KeyboardDown(state, .LeftShift) || KeyboardDown(state, .RightShift))
}

KeyboardAlt :: proc(state: ^KeyboardState) -> bool {
	return state != nil && (KeyboardDown(state, .LeftAlt) || KeyboardDown(state, .RightAlt))
}

KeyboardCtrlTimestamp :: proc(state: ^KeyboardState) -> coretime.Duration {
	if state == nil {
		return 0
	}
	a := Timestamp(state, .LeftControl)
	b := Timestamp(state, .RightControl)
	if a > b {
		return a
	}
	return b
}

KeyboardShiftTimestamp :: proc(state: ^KeyboardState) -> coretime.Duration {
	if state == nil {
		return 0
	}
	a := Timestamp(state, .LeftShift)
	b := Timestamp(state, .RightShift)
	if a > b {
		return a
	}
	return b
}

KeyboardAltTimestamp :: proc(state: ^KeyboardState) -> coretime.Duration {
	if state == nil {
		return 0
	}
	a := Timestamp(state, .LeftAlt)
	b := Timestamp(state, .RightAlt)
	if a > b {
		return a
	}
	return b
}
KeyboardCtrlOrCommand :: KeyboardCtrl
KeyboardCtrlOrCommandTimestamp :: KeyboardCtrlTimestamp

MousePressed :: proc(state: ^MouseState, button: MouseButtons) -> bool {
	i := int(button)
	return state != nil && i >= 0 && i < MouseMaxButtons && state.pressed[i]
}

MouseDown :: proc(state: ^MouseState, button: MouseButtons) -> bool {
	i := int(button)
	return state != nil && i >= 0 && i < MouseMaxButtons && state.down[i]
}

MouseReleased :: proc(state: ^MouseState, button: MouseButtons) -> bool {
	i := int(button)
	return state != nil && i >= 0 && i < MouseMaxButtons && state.released[i]
}

PressedTimestamp :: proc(state: ^MouseState, button: MouseButtons) -> coretime.Duration {
	i := int(button)
	if state == nil || i < 0 || i >= MouseMaxButtons {
		return 0
	}
	return state.timestamp[i]
}

MotionTimestamp :: proc(state: ^MouseState) -> coretime.Duration {
	if state == nil {
		return 0
	}
	return state.motion_timestamp
}

MouseX :: proc(state: ^MouseState) -> f32 {
	if state == nil {
		return 0
	}
	return state.Position.X
}

MouseY :: proc(state: ^MouseState) -> f32 {
	if state == nil {
		return 0
	}
	return state.Position.Y
}

MouseLeftPressed :: proc(state: ^MouseState) -> bool {
	return MousePressed(state, .Left)
}

MouseLeftDown :: proc(state: ^MouseState) -> bool {
	return MouseDown(state, .Left)
}

MouseLeftReleased :: proc(state: ^MouseState) -> bool {
	return MouseReleased(state, .Left)
}

MouseRightPressed :: proc(state: ^MouseState) -> bool {
	return MousePressed(state, .Right)
}

MouseRightDown :: proc(state: ^MouseState) -> bool {
	return MouseDown(state, .Right)
}

MouseRightReleased :: proc(state: ^MouseState) -> bool {
	return MouseReleased(state, .Right)
}

MouseMiddlePressed :: proc(state: ^MouseState) -> bool {
	return MousePressed(state, .Middle)
}

MouseMiddleDown :: proc(state: ^MouseState) -> bool {
	return MouseDown(state, .Middle)
}

MouseMiddleReleased :: proc(state: ^MouseState) -> bool {
	return MouseReleased(state, .Middle)
}

MouseRepeated :: proc(
	state: ^MouseState,
	button: MouseButtons,
	delay := RepeatDelay,
	interval := RepeatInterval,
) -> bool {
	if MousePressed(state, button) {
		return true
	}
	if state == nil {
		return false
	}
	i := int(button)
	if i < 0 || i >= MouseMaxButtons {
		return false
	}
	return(
		MouseDown(state, button) &&
		trigger_repeat(state.time, state.timestamp[i], delay, interval) \
	)
}

ControllerPressed :: proc(state: ^ControllerState, button: Buttons) -> bool {
	i := int(button)
	return state != nil && i >= 0 && i < ControllerMaxButtons && state.pressed[i]
}

ControllerDown :: proc(state: ^ControllerState, button: Buttons) -> bool {
	i := int(button)
	return state != nil && i >= 0 && i < ControllerMaxButtons && state.down[i]
}

ControllerReleased :: proc(state: ^ControllerState, button: Buttons) -> bool {
	i := int(button)
	return state != nil && i >= 0 && i < ControllerMaxButtons && state.released[i]
}

ControllerAxisValue :: proc(state: ^ControllerState, axis: Axes) -> f32 {
	i := int(axis)
	if state == nil || i < 0 || i >= ControllerMaxAxes {
		return 0
	}
	return state.axis[i]
}

ControllerTimestamp :: proc(state: ^ControllerState, button: Buttons) -> coretime.Duration {
	i := int(button)
	if state == nil || i < 0 || i >= ControllerMaxButtons {
		return 0
	}
	return state.timestamp[i]
}

ControllerAxisTimestamp :: proc(state: ^ControllerState, axis: Axes) -> coretime.Duration {
	i := int(axis)
	if state == nil || i < 0 || i >= ControllerMaxAxes {
		return 0
	}
	return state.axis_timestamp[i]
}

ControllerRepeated :: proc(
	state: ^ControllerState,
	button: Buttons,
	delay := RepeatDelay,
	interval := RepeatInterval,
) -> bool {
	if ControllerPressed(state, button) {
		return true
	}
	return(
		ControllerDown(state, button) &&
		trigger_repeat(state.time, ControllerTimestamp(state, button), delay, interval) \
	)
}

ControllerPressedOrRepeated :: proc(
	state: ^ControllerState,
	button: Buttons,
	delay := RepeatDelay,
	interval := RepeatInterval,
) -> bool {
	return ControllerPressed(state, button) || ControllerRepeated(state, button, delay, interval)
}

ControllerGamepadProvider :: proc(state: ^ControllerState) -> GamepadProviders {
	if state == nil {
		return .Unknown
	}
	return provider(state.GamepadType)
}

ControllerLeftStick :: proc(state: ^ControllerState) -> Vec2f {
	if state == nil {
		return {}
	}
	return Vec2f{state.axis[int(Axes.LeftX)], state.axis[int(Axes.LeftY)]}
}

ControllerRightStick :: proc(state: ^ControllerState) -> Vec2f {
	if state == nil {
		return {}
	}
	return Vec2f{state.axis[int(Axes.RightX)], state.axis[int(Axes.RightY)]}
}

GetController :: get_controller

InputStateClear :: proc(state: ^InputState) {
	if state == nil {
		return
	}
	input_state_init(state)
}

InputStateSnapshot :: proc(state: ^InputState) -> InputState {
	result: InputState
	input_state_copy(&result, state^)
	return result
}

InputStateGetController :: proc(state: ^InputState, id: ControllerID) -> ^ControllerState {
	if state == nil {
		return nil
	}
	for i := 0; i < InputMaxControllers; i += 1 {
		if state.Controllers[i].Connected && state.Controllers[i].ID == id {
			return &state.Controllers[i]
		}
	}
	return nil
}

InputCreateEcho :: proc(input: ^Input) -> Input {
	if input == nil {
		return {}
	}
	return Input{App = input.App, Enabled = input.Enabled}
}
SetClipboardString :: input_set_clipboard
GetClipboardString :: input_get_clipboard
Rumble :: input_rumble

AddSDLGamepadMapping :: proc(mapping: string) -> bool {
	when ODIN_OS == .JS {
		return false // 浏览器映射由 Gamepad API 提供。
	}
	return SDL.AddGamepadMapping(to_cstring(mapping)) >= 0
}

AddSDLGamepadMappings :: proc(mappings: []string) -> int {
	added := 0
	for mapping in mappings {
		if AddSDLGamepadMapping(mapping) {
			added += 1
		}
	}
	return added
}
InputKey :: input_key
InputMouseButton :: input_mouse_button
InputMouseMove :: input_mouse_move
InputMouseWheel :: input_mouse_wheel
InputText :: input_text
InputControllerButton :: input_controller_button
InputControllerAxis :: input_controller_axis
InputInit :: input_init
InputStep :: input_step

// ==============================================================================
// Input / Bindings — 输入绑定
// ==============================================================================

BindingKind :: enum {
	KeyboardKey,
	ControllerAxis,
	ControllerButton,
	MouseButton,
	MouseMotion,
}

// Binding is a compact tagged value.  Keeping the payload here makes bindings
// copyable and usable by the set types without requiring heap allocated
// interface values.

Binding :: struct {
	Kind:        BindingKind,
	Key:         Keys,
	Axis:        Axes,
	Button:      Buttons,
	MouseButton: MouseButtons,
	Sign:        int,
	Deadzone:    f32,
	MotionAxis:  [2]f32,
	Min:         f32,
	Max:         f32,
}

BindingFromKeyboard :: proc(v: KeyboardKeyBinding) -> Binding {
	return Binding{Kind = .KeyboardKey, Key = v.Key}
}

BindingFromControllerAxis :: proc(v: ControllerAxisBinding) -> Binding {
	return Binding{Kind = .ControllerAxis, Axis = v.Axis, Sign = v.Sign, Deadzone = v.Deadzone}
}

BindingFromControllerButton :: proc(v: ControllerButtonBinding) -> Binding {
	return Binding{Kind = .ControllerButton, Button = v.Button}
}

BindingFromMouseButton :: proc(v: MouseButtonBinding) -> Binding {
	return Binding{Kind = .MouseButton, MouseButton = v.Button}
}

BindingFromMouseMotion :: proc(v: MouseMotionBinding) -> Binding {
	return Binding {
		Kind       = .MouseMotion,
		MotionAxis = v.Axis,
		Sign       = v.Sign,
		Min        = v.Min,
		Max        = v.Max,
	}
}

BindingDescriptor :: proc(binding: Binding) -> string {
	switch binding.Kind {
	case .KeyboardKey:
		return "Keyboard Key"
	case .ControllerAxis:
		return "Controller Axis"
	case .ControllerButton:
		return "Controller Button"
	case .MouseButton:
		return "Mouse Button"
	case .MouseMotion:
		return "Mouse Motion"
	}
	return "Binding"
}

binding_motion_value :: proc(binding: Binding, mouse: ^MouseState) -> f32 {
	if binding.Max <= binding.Min {
		return 0
	}
	value :=
		(mouse.Delta.X * binding.MotionAxis[0] + mouse.Delta.Y * binding.MotionAxis[1]) *
		f32(binding.Sign)
	return Clamp((value - binding.Min) / (binding.Max - binding.Min), f32(0), f32(1))
}

binding_axis_value :: proc(binding: Binding, state: InputState, device: int) -> f32 {
	if device < 0 || device >= InputMaxControllers {
		return 0
	}
	v := state.Controllers[device].axis[int(binding.Axis)] * f32(binding.Sign)
	return Clamp((v - binding.Deadzone) / (1 - binding.Deadzone), 0, 1)
}

BindingGetState :: proc(binding: Binding, input: ^Input, device: int) -> BindingState {
	result := BindingState{}
	switch binding.Kind {
	case .KeyboardKey:
		k := &input.State.Keyboard
		result = BindingState {
			Pressed   = KeyboardPressed(k, binding.Key),
			Released  = KeyboardReleased(k, binding.Key),
			Down      = KeyboardDown(k, binding.Key),
			Value     = 0,
			Timestamp = Timestamp(k, binding.Key),
		}
		if result.Down {
			result.Value = 1
		}
	case .ControllerButton:
		if device < 0 || device >= InputMaxControllers {
			return result
		}
		c := &input.State.Controllers[device]
		result = BindingState {
			Pressed   = ControllerPressed(c, binding.Button),
			Released  = ControllerReleased(c, binding.Button),
			Down      = ControllerDown(c, binding.Button),
			Value     = 0,
			Timestamp = ControllerTimestamp(c, binding.Button),
		}
		if result.Down {
			result.Value = 1
		}
	case .ControllerAxis:
		if device < 0 || device >= InputMaxControllers {
			return result
		}
		c := &input.State.Controllers[device]
		v := binding_axis_value(binding, input.State, device)
		prev := binding_axis_value(binding, input.LastState, device)
		result.Value = v
		result.Down = v > 0
		result.Pressed = v > 0 && prev <= 0
		result.Released = v <= 0 && prev > 0
		result.Timestamp = ControllerAxisTimestamp(c, binding.Axis)
	case .MouseButton:
		m := &input.State.Mouse
		result = BindingState {
			Pressed   = MousePressed(m, binding.MouseButton),
			Released  = MouseReleased(m, binding.MouseButton),
			Down      = MouseDown(m, binding.MouseButton),
			Value     = 0,
			Timestamp = PressedTimestamp(m, binding.MouseButton),
		}
		if result.Down {
			result.Value = 1
		}
	case .MouseMotion:
		m := &input.State.Mouse
		v := binding_motion_value(binding, m)
		prev := binding_motion_value(binding, &input.LastState.Mouse)
		result.Value = v
		result.Down = result.Value > 0
		result.Pressed = v > 0 && prev <= 0
		result.Released = v <= 0 && prev > 0
		result.Timestamp = MotionTimestamp(m)
	}
	return result
}

// ------------------------------------------------------------------------------
// Input / Bindings / BindingAxisOverlap
// ------------------------------------------------------------------------------

BindingAxisOverlap :: enum {
	TakeNewer,
	TakeOlder,
	CancelOut,
}

BindingAxisOverlapResolve :: proc(
	overlap: BindingAxisOverlap,
	negative, positive: BindingState,
) -> f32 {
	if overlap == .CancelOut {
		return Clamp(positive.Value - negative.Value, -1, 1)
	}
	if positive.Down && negative.Down {
		if overlap == .TakeNewer {
			if negative.Timestamp > positive.Timestamp {
				return -negative.Value
			}
			return positive.Value
		}
		if negative.Timestamp < positive.Timestamp {
			return -negative.Value
		}
		return positive.Value
	}
	if positive.Down {
		return positive.Value
	}
	if negative.Down {
		return -negative.Value
	}
	return 0
}

// ------------------------------------------------------------------------------
// Input / Bindings / BindingState
// ------------------------------------------------------------------------------

BindingState :: struct {
	Pressed, Released, Down: bool,
	Value:                   f32,
	Timestamp:               time.Duration,
}

// ------------------------------------------------------------------------------
// Input / Bindings / ControllerAxisBinding
// ------------------------------------------------------------------------------

ControllerAxisBinding :: struct {
	Axis:     Axes,
	Sign:     int,
	Deadzone: f32,
}

ControllerAxisBindingMake :: proc(axis: Axes, sign: int, deadzone: f32) -> ControllerAxisBinding {
	return ControllerAxisBinding{axis, sign, deadzone}
}

// ------------------------------------------------------------------------------
// Input / Bindings / ControllerButtonBinding
// ------------------------------------------------------------------------------

ControllerButtonBinding :: struct {
	Button: Buttons,
}

ControllerButtonBindingMake :: proc(button: Buttons) -> ControllerButtonBinding {
	return ControllerButtonBinding{button}
}

// ------------------------------------------------------------------------------
// Input / Bindings / KeyboardKeyBinding
// ------------------------------------------------------------------------------

KeyboardKeyBinding :: struct {
	Key: Keys,
}

KeyboardKeyBindingMake :: proc(key: Keys) -> KeyboardKeyBinding {
	return KeyboardKeyBinding{key}
}

KeyboardKeyBindingDescriptor :: proc(binding: KeyboardKeyBinding) -> string {
	return "Keyboard Key"
}

// ------------------------------------------------------------------------------
// Input / Bindings / MouseButtonBinding
// ------------------------------------------------------------------------------

MouseButtonBinding :: struct {
	Button: MouseButtons,
}

MouseButtonBindingMake :: proc(button: MouseButtons) -> MouseButtonBinding {
	return MouseButtonBinding{button}
}

// ------------------------------------------------------------------------------
// Input / Bindings / MouseMotionBinding
// ------------------------------------------------------------------------------

MouseMotionBinding :: struct {
	Axis:     [2]f32,
	Sign:     int,
	Min, Max: f32,
}

MouseMotionBindingMake :: proc(
	axis: [2]f32,
	sign: int,
	min_value, max_value: f32,
) -> MouseMotionBinding {
	return MouseMotionBinding{axis, sign, min_value, max_value}
}

// ==============================================================================
// Input / Sets — 绑定组合
// ==============================================================================

// ------------------------------------------------------------------------------
// Input / Sets / ActionBindingSet
// ------------------------------------------------------------------------------

ActionEntry :: struct {
	Binding: Binding,
	Masks:   [dynamic]string,
}

ActionBindingSet :: struct {
	Entries: [dynamic]ActionEntry,
}

ActionBindingSetMake :: proc() -> ActionBindingSet {
	return ActionBindingSet{}
}

ActionBindingSetAdd :: proc(set: ^ActionBindingSet, binding: Binding, masks: ..string) {
	e := ActionEntry {
		Binding = binding,
	}
	for m in masks {
		append(&e.Masks, m)
	}
	append(&set.Entries, e)
}

ActionBindingSetAddKey :: proc(set: ^ActionBindingSet, key: Keys, masks: ..string) {
	ActionBindingSetAdd(set, Binding{Kind = .KeyboardKey, Key = key}, ..masks[:])
}

ActionBindingSetAddButton :: proc(set: ^ActionBindingSet, button: Buttons, masks: ..string) {
	ActionBindingSetAdd(set, Binding{Kind = .ControllerButton, Button = button}, ..masks[:])
}

ActionBindingSetAddMouseButton :: proc(
	set: ^ActionBindingSet,
	button: MouseButtons,
	masks: ..string,
) {
	ActionBindingSetAdd(set, Binding{Kind = .MouseButton, MouseButton = button}, ..masks[:])
}

ActionBindingSetAddAxis :: proc(
	set: ^ActionBindingSet,
	axis: Axes,
	sign: int,
	deadzone := f32(0),
	masks: ..string,
) {
	ActionBindingSetAdd(
		set,
		Binding{Kind = .ControllerAxis, Axis = axis, Sign = sign, Deadzone = deadzone},
		..masks[:],
	)
}

ActionBindingSetGetState :: proc(
	set: ^ActionBindingSet,
	input: ^Input,
	device: int,
) -> BindingState {
	r := BindingState{}
	for e in set.Entries {
		if !InputIsIncluded(input, e.Masks[:]) {
			continue
		}
		s := BindingGetState(e.Binding, input, device)
		r.Pressed |= s.Pressed
		r.Released |= s.Released
		r.Down |= s.Down
		if s.Value > r.Value {
			r.Value = s.Value
		}
		if s.Timestamp > r.Timestamp {
			r.Timestamp = s.Timestamp
		}
	}
	return r
}

ActionBindingSetClear :: proc(set: ^ActionBindingSet) {
	clear(&set.Entries)
}
ActionBindingSet_ActionEntry :: ActionEntry

// ------------------------------------------------------------------------------
// Input / Sets / AxisBindingSet
// ------------------------------------------------------------------------------

AxisEntry :: struct {
	Negative, Positive: Binding,
	Overlap:            BindingAxisOverlap,
	Masks:              [dynamic]string,
}

AxisBindingSet :: struct {
	Entries: [dynamic]AxisEntry,
}

AxisBindingSetAdd :: proc(
	set: ^AxisBindingSet,
	negative, positive: Binding,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	e := AxisEntry {
		Negative = negative,
		Positive = positive,
		Overlap  = overlap,
	}
	for m in masks {
		append(&e.Masks, m)
	}
	append(&set.Entries, e)
}

AxisBindingSetAddKeys :: proc(
	set: ^AxisBindingSet,
	negative, positive: Keys,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	AxisBindingSetAdd(
		set,
		Binding{Kind = .KeyboardKey, Key = negative},
		Binding{Kind = .KeyboardKey, Key = positive},
		overlap,
		..masks[:],
	)
}

AxisBindingSetAddButtons :: proc(
	set: ^AxisBindingSet,
	negative, positive: Buttons,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	AxisBindingSetAdd(
		set,
		Binding{Kind = .ControllerButton, Button = negative},
		Binding{Kind = .ControllerButton, Button = positive},
		overlap,
		..masks[:],
	)
}

AxisBindingSetAddAxis :: proc(
	set: ^AxisBindingSet,
	axis: Axes,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	AxisBindingSetAdd(
		set,
		Binding{Kind = .ControllerAxis, Axis = axis, Sign = -1},
		Binding{Kind = .ControllerAxis, Axis = axis, Sign = 1},
		overlap,
		..masks[:],
	)
}

AxisBindingSetValue :: proc(set: ^AxisBindingSet, input: ^Input, device: int) -> f32 {
	value: f32 = 0
	for e in set.Entries {
		if !InputIsIncluded(input, e.Masks[:]) {
			continue
		}
		n := BindingGetState(e.Negative, input, device)
		p := BindingGetState(e.Positive, input, device)
		v := BindingAxisOverlapResolve(e.Overlap, n, p)
		if math.abs(v) > math.abs(value) {
			value = v
		}
	}
	return value
}

AxisBindingSetPressedSign :: proc(set: ^AxisBindingSet, input: ^Input, device: int) -> int {
	value: f32
	for e in set.Entries {
		if !InputIsIncluded(input, e.Masks[:]) {
			continue
		}
		n := BindingGetState(e.Negative, input, device)
		p := BindingGetState(e.Positive, input, device)
		if !n.Pressed {
			n = {}
		}
		if !p.Pressed {
			p = {}
		}
		next := BindingAxisOverlapResolve(e.Overlap, n, p)
		if math.abs(next) > math.abs(value) {
			value = next
		}
	}
	return int(math.sign(value))
}

AxisBindingSetClear :: proc(set: ^AxisBindingSet) {
	clear(&set.Entries)
}
AxisBindingSet_AxisEntry :: AxisEntry

// ------------------------------------------------------------------------------
// Input / Sets / StickBindingSet
// ------------------------------------------------------------------------------

StickEntry :: struct {
	Left, Right, Up, Down: Binding,
	CircularDeadzone:      f32,
	Overlap:               BindingAxisOverlap,
	Masks:                 [dynamic]string,
}

StickBindingSet :: struct {
	Entries: [dynamic]StickEntry,
}

StickBindingSetAdd :: proc(
	set: ^StickBindingSet,
	left, right, up, down: Binding,
	deadzone := f32(0),
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	e := StickEntry {
		Left             = left,
		Right            = right,
		Up               = up,
		Down             = down,
		CircularDeadzone = deadzone,
		Overlap          = overlap,
	}
	for m in masks {
		append(&e.Masks, m)
	}
	append(&set.Entries, e)
}

StickBindingSetAddKeys :: proc(
	set: ^StickBindingSet,
	left, right, up, down: Keys,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	StickBindingSetAdd(
		set,
		Binding{Kind = .KeyboardKey, Key = left},
		Binding{Kind = .KeyboardKey, Key = right},
		Binding{Kind = .KeyboardKey, Key = up},
		Binding{Kind = .KeyboardKey, Key = down},
		0,
		overlap,
		..masks[:],
	)
}

StickBindingSetAddButtons :: proc(
	set: ^StickBindingSet,
	left, right, up, down: Buttons,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	StickBindingSetAdd(
		set,
		Binding{Kind = .ControllerButton, Button = left},
		Binding{Kind = .ControllerButton, Button = right},
		Binding{Kind = .ControllerButton, Button = up},
		Binding{Kind = .ControllerButton, Button = down},
		0,
		overlap,
		..masks[:],
	)
}

StickBindingSetAddAxes :: proc(
	set: ^StickBindingSet,
	x, y: Axes,
	deadzone: f32,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	StickBindingSetAdd(
		set,
		Binding{Kind = .ControllerAxis, Axis = x, Sign = -1},
		Binding{Kind = .ControllerAxis, Axis = x, Sign = 1},
		Binding{Kind = .ControllerAxis, Axis = y, Sign = -1},
		Binding{Kind = .ControllerAxis, Axis = y, Sign = 1},
		deadzone,
		overlap,
		..masks[:],
	)
}

StickBindingSetValue :: proc(set: ^StickBindingSet, input: ^Input, device: int) -> [2]f32 {
	value: [2]f32 = {}
	for e in set.Entries {
		if !InputIsIncluded(input, e.Masks[:]) {
			continue
		}
		l := BindingGetState(e.Left, input, device)
		r := BindingGetState(e.Right, input, device)
		u := BindingGetState(e.Up, input, device)
		d := BindingGetState(e.Down, input, device)
		next := [2]f32 {
			BindingAxisOverlapResolve(e.Overlap, l, r),
			BindingAxisOverlapResolve(e.Overlap, u, d),
		}
		if e.CircularDeadzone > 0 &&
		   next[0] * next[0] + next[1] * next[1] < e.CircularDeadzone * e.CircularDeadzone {
			continue
		}
		if next[0] * next[0] + next[1] * next[1] > value[0] * value[0] + value[1] * value[1] {
			value = next
		}
	}
	return value
}

StickBindingSetClear :: proc(set: ^StickBindingSet) {
	clear(&set.Entries)
}
StickBindingSet_StickEntry :: StickEntry

// ==============================================================================
// Input / Virtual — 虚拟输入
// ==============================================================================

VirtualInput :: struct {
	Input:           ^Input,
	Name:            string,
	ControllerIndex: int,
	Active:          bool,
	IsDisposed:      bool,
}

VirtualInputMake :: proc(input: ^Input, name: string, controller_index := 0) -> VirtualInput {
	return VirtualInput {
		Input           = input,
		Name            = name,
		ControllerIndex = controller_index,
		Active          = true,
	}
}

VirtualInputDispose :: proc(v: ^VirtualInput) {
	v.IsDisposed = true
}

VirtualInputSetControllerIndex :: proc(v: ^VirtualInput, index: int) {
	if index >= 0 {
		v.ControllerIndex = index
	}
}

VirtualInputSetActive :: proc(v: ^VirtualInput, active: bool) {
	if v != nil {
		v.Active = active
	}
}

VirtualInputIsActive :: proc(v: ^VirtualInput) -> bool {
	return v != nil && v.Active && !v.IsDisposed
}

// ------------------------------------------------------------------------------
// Input / Virtual / VirtualDevice
// ------------------------------------------------------------------------------

VirtualDeviceIndexMode :: enum {
	Manual,
	AutomaticLatest,
}

VirtualDevice :: struct {
	Base:      VirtualInput,
	IndexMode: VirtualDeviceIndexMode,
	Inputs:    [dynamic]^VirtualInput,
	actions:   [dynamic]^VirtualAction,
	axes:      [dynamic]^VirtualAxis,
	sticks:    [dynamic]^VirtualStick,
}

VirtualDeviceMake :: proc(input: ^Input, name: string, controller_index := 0) -> VirtualDevice {
	return VirtualDevice {
		Base      = VirtualInputMake(input, name, controller_index),
		IndexMode = .Manual,
	}
}

VirtualDeviceSetControllerIndex :: proc(v: ^VirtualDevice, index: int) {
	if v.IndexMode == .Manual {
		v.Base.ControllerIndex = index
		for p in v.Inputs {
			p.ControllerIndex = index
		}
	}
}

VirtualDeviceAddAction :: proc(
	v: ^VirtualDevice,
	name: string,
	set := ActionBindingSet{},
	buffer := f32(0),
) -> ^VirtualAction {
	a := new(VirtualAction)
	a^ = VirtualActionMake(v.Base.Input, name, set, v.Base.ControllerIndex, buffer)
	append(&v.actions, a)
	append(&v.Inputs, &a.Base)
	return a
}

VirtualDeviceAddAxis :: proc(
	v: ^VirtualDevice,
	name: string,
	set := AxisBindingSet{},
) -> ^VirtualAxis {
	a := new(VirtualAxis)
	a^ = VirtualAxisMake(v.Base.Input, name, set, v.Base.ControllerIndex)
	append(&v.axes, a)
	append(&v.Inputs, &a.Base)
	return a
}

VirtualDeviceAddStick :: proc(
	v: ^VirtualDevice,
	name: string,
	set := StickBindingSet{},
) -> ^VirtualStick {
	s := new(VirtualStick)
	s^ = VirtualStickMake(v.Base.Input, name, set, v.Base.ControllerIndex)
	append(&v.sticks, s)
	append(&v.Inputs, &s.Base)
	return s
}

VirtualDeviceUpdate :: proc(v: ^VirtualDevice, t: Time) {
	if v.IndexMode == .AutomaticLatest && v.Base.Input != nil {
		latest := 0
		for i in 1 ..< InputMaxControllers {
			if v.Base.Input.State.Controllers[i].IsGamepad &&
			   v.Base.Input.State.Controllers[i].InputTimestamp >
				   v.Base.Input.State.Controllers[latest].InputTimestamp {
				latest = i
			}
		}
		v.Base.ControllerIndex = latest
		for p in v.Inputs {
			p.ControllerIndex = latest
		}
	}
	for a in v.actions {
		VirtualActionUpdate(a, t)
	}
	for a in v.axes {
		VirtualAxisUpdate(a, t)
	}
	for s in v.sticks {
		VirtualStickUpdate(s, t)
	}
}

VirtualDeviceDispose :: proc(v: ^VirtualDevice) {
	if v.Base.IsDisposed {
		return
	}
	for p in v.Inputs {
		VirtualInputDispose(p)
	}
	clear(&v.Inputs)
	clear(&v.actions)
	clear(&v.axes)
	clear(&v.sticks)
	v.Base.IsDisposed = true
}

VirtualDeviceIsGamepadLatest :: proc(v: ^VirtualDevice) -> bool {
	if v.Base.Input == nil ||
	   v.Base.ControllerIndex < 0 ||
	   v.Base.ControllerIndex >= InputMaxControllers {
		return false
	}
	c := &v.Base.Input.State.Controllers[v.Base.ControllerIndex]
	return c.IsGamepad && c.InputTimestamp > v.Base.Input.State.Keyboard.InputTimestamp
}

// ------------------------------------------------------------------------------
// Input / Virtual / VirtualAction
// ------------------------------------------------------------------------------

VirtualAction :: struct {
	Base:                                             VirtualInput,
	Set:                                              ActionBindingSet,
	RepeatDelay:                                      f32,
	RepeatInterval:                                   f32,
	Buffer:                                           f32,
	Pressed, PressConsumed, Down, Released, Repeated: bool,
	Value, ValueNoDeadzone:                           f32,
	Timestamp:                                        time.Duration,
}

VirtualActionMake :: proc(
	input: ^Input,
	name: string,
	set := ActionBindingSet{},
	controller_index := 0,
	buffer := f32(0),
) -> VirtualAction {
	return VirtualAction {
		Base           = VirtualInputMake(input, name, controller_index),
		Set            = set,
		RepeatDelay    = RepeatDelay,
		RepeatInterval = RepeatInterval,
		Buffer         = buffer,
	}
}

VirtualActionUpdate :: proc(v: ^VirtualAction, t: Time) {
	if v.Base.IsDisposed || !v.Base.Active || v.Base.Input == nil {
		return
	}
	s := ActionBindingSetGetState(&v.Set, v.Base.Input, v.Base.ControllerIndex)
	v.Pressed, v.Released, v.Down, v.Value = s.Pressed, s.Released, s.Down, s.Value
	v.ValueNoDeadzone = s.Value
	v.Repeated = false
	if v.Pressed {
		v.PressConsumed = false
		v.Timestamp = t.Elapsed
	} else if !v.PressConsumed &&
	   v.Timestamp > 0 &&
	   time.duration_seconds(t.Elapsed - v.Timestamp) < f64(v.Buffer) {
		v.Pressed = true
	}
	if v.Down &&
	   time.duration_seconds(t.Elapsed - v.Timestamp) > f64(v.RepeatDelay) &&
	   v.RepeatInterval > 0 {
		elapsed := time.duration_seconds(t.Elapsed - v.Timestamp) - f64(v.RepeatDelay)
		previous := elapsed - f64(t.Delta)
		v.Repeated = int(previous / f64(v.RepeatInterval)) < int(elapsed / f64(v.RepeatInterval))
	}
}

VirtualActionManualUpdate :: proc(v: ^VirtualAction, t: Time) {
	VirtualActionUpdate(v, t)
}

VirtualActionConsumePress :: proc(v: ^VirtualAction) -> bool {
	if v.Pressed {
		v.Pressed = false
		v.PressConsumed = true
		return true
	}
	return false
}

VirtualActionClear :: proc(v: ^VirtualAction) {
	v.Pressed = false
	v.Released = false
	v.PressConsumed = true
	v.Down = false
	v.Repeated = false
	v.Value = 0
	v.ValueNoDeadzone = 0
}

VirtualActionSetControllerIndex :: proc(v: ^VirtualAction, index: int) {
	VirtualInputSetControllerIndex(&v.Base, index)
}

// ------------------------------------------------------------------------------
// Input / Virtual / VirtualAxis
// ------------------------------------------------------------------------------

VirtualAxis :: struct {
	Base:        VirtualInput,
	Set:         AxisBindingSet,
	Value:       f32,
	IntValue:    int,
	PressedSign: int,
}

VirtualAxisMake :: proc(
	input: ^Input,
	name: string,
	set := AxisBindingSet{},
	controller_index := 0,
) -> VirtualAxis {
	return VirtualAxis{Base = VirtualInputMake(input, name, controller_index), Set = set}
}

VirtualAxisUpdate :: proc(v: ^VirtualAxis, t: Time) {
	_ = t
	if v.Base.IsDisposed || !v.Base.Active || v.Base.Input == nil {
		return
	}
	v.Value = AxisBindingSetValue(&v.Set, v.Base.Input, v.Base.ControllerIndex)
	if v.Value > 0 {
		v.IntValue = 1
	} else if v.Value < 0 {
		v.IntValue = -1
	} else {
		v.IntValue = 0
	}
	v.PressedSign = AxisBindingSetPressedSign(&v.Set, v.Base.Input, v.Base.ControllerIndex)
}

VirtualAxisManualUpdate :: proc(v: ^VirtualAxis, t: Time) {
	VirtualAxisUpdate(v, t)
}

VirtualAxisPressed :: proc(v: ^VirtualAxis) -> bool {
	return v.PressedSign != 0
}

VirtualAxisPressedNegative :: proc(v: ^VirtualAxis) -> bool {
	return v.PressedSign < 0
}

VirtualAxisPressedPositive :: proc(v: ^VirtualAxis) -> bool {
	return v.PressedSign > 0
}

VirtualAxisClear :: proc(v: ^VirtualAxis) {
	v.Value = 0
	v.IntValue = 0
	v.PressedSign = 0
}

VirtualAxisSetControllerIndex :: proc(v: ^VirtualAxis, index: int) {
	VirtualInputSetControllerIndex(&v.Base, index)
}

// ------------------------------------------------------------------------------
// Input / Virtual / VirtualStick
// ------------------------------------------------------------------------------

VirtualStick :: struct {
	Base:                                              VirtualInput,
	Set:                                               StickBindingSet,
	Value:                                             [2]f32,
	IntValue:                                          Point2,
	PressedLeft, PressedRight, PressedUp, PressedDown: bool,
}

VirtualStickMake :: proc(
	input: ^Input,
	name: string,
	set := StickBindingSet{},
	controller_index := 0,
) -> VirtualStick {
	return VirtualStick{Base = VirtualInputMake(input, name, controller_index), Set = set}
}

VirtualStickUpdate :: proc(v: ^VirtualStick, t: Time) {
	_ = t
	if v.Base.IsDisposed || !v.Base.Active || v.Base.Input == nil {
		return
	}
	v.Value = StickBindingSetValue(&v.Set, v.Base.Input, v.Base.ControllerIndex)
	v.IntValue = Point2{}
	if v.Value[0] < 0 {
		v.IntValue.X = -1
	}
	if v.Value[0] > 0 {
		v.IntValue.X = 1
	}
	if v.Value[1] < 0 {
		v.IntValue.Y = -1
	}
	if v.Value[1] > 0 {
		v.IntValue.Y = 1
	}
	v.PressedLeft = false
	v.PressedRight = false
	v.PressedUp = false
	v.PressedDown = false
	for e in v.Set.Entries {
		if !InputIsIncluded(v.Base.Input, e.Masks[:]) {
			continue
		}
		l := BindingGetState(e.Left, v.Base.Input, v.Base.ControllerIndex)
		r := BindingGetState(e.Right, v.Base.Input, v.Base.ControllerIndex)
		u := BindingGetState(e.Up, v.Base.Input, v.Base.ControllerIndex)
		d := BindingGetState(e.Down, v.Base.Input, v.Base.ControllerIndex)
		v.PressedLeft |= l.Pressed
		v.PressedRight |= r.Pressed
		v.PressedUp |= u.Pressed
		v.PressedDown |= d.Pressed
	}
}

VirtualStickManualUpdate :: proc(v: ^VirtualStick, t: Time) {
	VirtualStickUpdate(v, t)
}

VirtualStickClear :: proc(v: ^VirtualStick) {
	v.Value = {}
	v.IntValue = {}
	v.PressedLeft = false
	v.PressedRight = false
	v.PressedUp = false
	v.PressedDown = false
}

VirtualStickSetControllerIndex :: proc(v: ^VirtualStick, index: int) {
	VirtualInputSetControllerIndex(&v.Base, index)
}

// ==============================================================================
// Input / InputProvider — 独立输入供给
// ==============================================================================

InputProvider :: struct {
	Input:     ^Input,
	OwnsInput: bool,
}

InputProviderMake :: proc() -> InputProvider {
	p := InputProvider {
		OwnsInput = true,
	}
	p.Input = new(Input)
	InputInit(p.Input, nil)
	return p
}

InputProviderDispose :: proc(p: ^InputProvider) {
	if p == nil {
		return
	}
	if p.OwnsInput && p.Input != nil {
		InputDispose(p.Input)
		free(p.Input)
	}
	p^ = {}
}

InputProviderUpdate :: proc(p: ^InputProvider, t: Time) {
	if p.Input != nil {
		InputStep(p.Input, t)
	}
}

InputProviderText :: proc(p: ^InputProvider, text: string) {
	if p.Input != nil {
		input_text(p.Input, text, nil)
	}
}

InputProviderKey :: proc(p: ^InputProvider, key: Keys, pressed: bool, stamp: coretime.Duration) {
	if p.Input != nil {
		InputKey(p.Input, key, pressed, stamp)
	}
}

InputProviderMouseButton :: proc(
	p: ^InputProvider,
	button: MouseButtons,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if p.Input != nil {
		InputMouseButton(p.Input, button, pressed, stamp)
	}
}

InputProviderMouseMove :: proc(
	p: ^InputProvider,
	position, delta: Vec2f,
	stamp: coretime.Duration,
) {
	if p.Input != nil {
		InputMouseMove(p.Input, position, delta, stamp)
	}
}

InputProviderMouseWheel :: proc(p: ^InputProvider, wheel: Vec2f) {
	if p.Input != nil {
		InputMouseWheel(p.Input, wheel)
	}
}

InputProviderControllerButton :: proc(
	p: ^InputProvider,
	id: ControllerID,
	button: int,
	pressed: bool,
	stamp: coretime.Duration,
) {
	if p.Input != nil {
		InputControllerButton(p.Input, id, button, pressed, stamp)
	}
}

InputProviderControllerAxis :: proc(
	p: ^InputProvider,
	id: ControllerID,
	axis: int,
	value: f32,
	stamp: coretime.Duration,
) {
	if p.Input != nil {
		InputControllerAxis(p.Input, id, axis, value, stamp)
	}
}

// ==============================================================================
// Input / Cursor — 光标
// ==============================================================================

CursorSystemType :: enum {
	Default,
	Text,
	Wait,
	Crosshair,
	Progress,
	ResizeNWSE,
	ResizeNESW,
	ResizeHorizontal,
	ResizeVertical,
	Move,
	NotAllowed,
	Pointer,
	ResizeNW,
	ResizeN,
	ResizeNE,
	ResizeE,
	ResizeSE,
	ResizeS,
	ResizeSW,
	ResizeW,
}

Cursor :: struct {
	FocusPoint: Point2,
	Size:       Point2,
	SystemType: CursorSystemType,
	Image:      ^Image,
	Handle:     ^SDL.Cursor,
	Disposed:   bool,
}

cursor_sdl_system :: proc(kind: CursorSystemType) -> SDL.SystemCursor {
	return SDL.SystemCursor(kind)
}

CursorMakeSystem :: proc(kind: CursorSystemType) -> Cursor {
	when ODIN_OS == .JS {
		return Cursor {
			SystemType = kind,
			Handle     = cast(^SDL.Cursor)web_handle_ptr(fw_cursor_system(u32(kind))),
		}
	}
	return Cursor{SystemType = kind, Handle = SDL.CreateSystemCursor(cursor_sdl_system(kind))}
}

CursorMakeImage :: proc(image: ^Image, focus: Point2) -> Cursor {
	result := Cursor {
		FocusPoint = focus,
	}
	if image == nil || image.Width <= 0 || image.Height <= 0 || len(image.Pixels) == 0 {
		return result
	}
	result.Size = Point2{image.Width, image.Height}
	result.Image = image
	when ODIN_OS == .JS {
		result.Handle = cast(^SDL.Cursor)web_handle_ptr(
			fw_cursor_image(
				raw_data(image.Pixels),
				i32(image.Width),
				i32(image.Height),
				i32(focus.X),
				i32(focus.Y),
			),
		)
		return result
	}
	surface := SDL.CreateSurfaceFrom(
		c.int(image.Width),
		c.int(image.Height),
		SDL.PixelFormat.RGBA32,
		raw_data(image.Pixels),
		c.int(image.Width * 4),
	)
	if surface == nil {
		return result
	}
	result.Handle = SDL.CreateColorCursor(surface, c.int(focus.X), c.int(focus.Y))
	SDL.DestroySurface(surface)
	return result
}

CursorSet :: proc(c: ^Cursor) -> bool {
	if c == nil || c.Disposed || c.Handle == nil {
		return false
	}
	when ODIN_OS == .JS {
		return fw_cursor_set(web_handle_u32(c.Handle))
	}
	return SDL.SetCursor(c.Handle)
}

CursorDispose :: proc(c: ^Cursor) {
	if c == nil || c.Disposed {
		return
	}
	if c.Handle != nil {
		when ODIN_OS == .JS {
			fw_cursor_release(web_handle_u32(c.Handle))
		} else {
			SDL.DestroyCursor(c.Handle)
		}
		c.Handle = nil
	}
	c.Disposed = true
	c.Image = nil
}

// ------------------------------------------------------------------------------
// Input / Input / BindingFilters — 绑定筛选
// ------------------------------------------------------------------------------

InputIsIncluded :: proc(input: ^Input, masks: []string) -> bool {
	if input == nil {
		return false
	}
	if input.BindingFilters == nil || len(masks) == 0 {
		return true
	}
	for mask in masks {
		for filter in input.BindingFilters {
			if mask == filter {
				return true
			}
		}
	}
	return false
}
// ------------------------------------------------------------------------------
// Input / InputProvider / Controllers — 控制器供给
// ------------------------------------------------------------------------------

InputProviderConnectController :: proc(
	provider: ^InputProvider,
	id: ControllerID,
	name: string,
	buttons, axes: int,
	is_gamepad: bool,
	kind: GamepadTypes,
	vendor, product, version: u16,
) {
	if provider.Input != nil {
		input_connect_controller(
			provider.Input,
			id,
			name,
			buttons,
			axes,
			is_gamepad,
			kind,
			vendor,
			product,
			version,
		)
	}
}

InputProviderDisconnectController :: proc(provider: ^InputProvider, id: ControllerID) {
	if provider.Input != nil {
		input_disconnect_controller(provider.Input, id)
	}
}

VirtualDeviceGetByInputName :: proc(device: ^VirtualDevice, name: string) -> ^VirtualInput {
	for input in device.Inputs {
		if input.Name == name {
			return input
		}
	}
	return nil
}
// ------------------------------------------------------------------------------
// Input / Sets / Helpers — 常用绑定组助手
// ------------------------------------------------------------------------------

StickBindingSetAddArrowKeys :: proc(
	set: ^StickBindingSet,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	StickBindingSetAddKeys(set, .Left, .Right, .Up, .Down, overlap, ..masks[:])
}

StickBindingSetAddWasd :: proc(
	set: ^StickBindingSet,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	StickBindingSetAddKeys(set, .A, .D, .W, .S, overlap, ..masks[:])
}

StickBindingSetAddLeftJoystick :: proc(set: ^StickBindingSet, deadzone: f32, masks: ..string) {
	StickBindingSetAddAxes(set, .LeftX, .LeftY, deadzone, .TakeNewer, ..masks[:])
}

StickBindingSetAddRightJoystick :: proc(set: ^StickBindingSet, deadzone: f32, masks: ..string) {
	StickBindingSetAddAxes(set, .RightX, .RightY, deadzone, .TakeNewer, ..masks[:])
}

StickBindingSetAddDPad :: proc(
	set: ^StickBindingSet,
	overlap := BindingAxisOverlap.TakeNewer,
	masks: ..string,
) {
	StickBindingSetAddButtons(set, .Left, .Right, .Up, .Down, overlap, ..masks[:])
}

StickBindingSetAddMouseMotion :: proc(
	set: ^StickBindingSet,
	max_motion: f32 = 25,
	masks: ..string,
) {
	StickBindingSetAdd(
		set,
		Binding{Kind = .MouseMotion, MotionAxis = {1, 0}, Sign = -1, Max = max_motion},
		Binding{Kind = .MouseMotion, MotionAxis = {1, 0}, Sign = 1, Max = max_motion},
		Binding{Kind = .MouseMotion, MotionAxis = {0, 1}, Sign = -1, Max = max_motion},
		Binding{Kind = .MouseMotion, MotionAxis = {0, 1}, Sign = 1, Max = max_motion},
		0,
		.TakeNewer,
		..masks[:],
	)
}

ActionBindingSetAddLeftJoystickLeft :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .LeftX, -1, deadzone, ..masks[:])
}

ActionBindingSetAddLeftJoystickRight :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .LeftX, 1, deadzone, ..masks[:])
}

ActionBindingSetAddLeftJoystickUp :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .LeftY, -1, deadzone, ..masks[:])
}

ActionBindingSetAddLeftJoystickDown :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .LeftY, 1, deadzone, ..masks[:])
}

ActionBindingSetAddRightJoystickLeft :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .RightX, -1, deadzone, ..masks[:])
}

ActionBindingSetAddRightJoystickRight :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .RightX, 1, deadzone, ..masks[:])
}

ActionBindingSetAddRightJoystickUp :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .RightY, -1, deadzone, ..masks[:])
}

ActionBindingSetAddRightJoystickDown :: proc(
	set: ^ActionBindingSet,
	deadzone: f32 = 0,
	masks: ..string,
) {
	ActionBindingSetAddAxis(set, .RightY, 1, deadzone, ..masks[:])
}
