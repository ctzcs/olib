package shader_lab

// 宿主负责窗口、输入路由和 MSDF 资产；工具只持有独立的预览会话。
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import ui "olib:kit/ui"

Config :: struct {
	// source_root 递归发现 .oshader。
	source_root: string,
	// 借用至 dispose；必须是真正的距离场，工具始终以 .MSDF 注册。
	font: ^foster.MsdfFont,
	font_texture: foster.Texture,
	// 可选，借用宿主已上传的内置图标图集；nil 时工具自行加载和释放。
	icons: ^r2d.Sprite_Atlas,
	// 可选，init 时复制；nil 使用工具默认主题。
	theme: ^ui.UI_Theme,
	paused: bool,
	// 宿主通过 file_request / file_reply 接入自己的文件对话框。
	file_dialogs: bool,
	preview: Preview_Hooks,
}

// pointer / delta 使用目标最终像素；宿主自行转换 DPI，并决定输入归属。
// 已捕获的拖动即使移出 region 也继续传入；失焦传 focused=false，隐藏时调用 cancel。
Input :: struct {
	pointer, delta, scroll: foster.Vec2,
	left_down, right_down, right_pressed: bool,
	focused, escape: bool,
	navigation: ui.UI_Navigation,
	vertical_adjust: f32,
	// 本帧拖入的文件；只借用到 render 返回。坐标仍为 pointer。
	dropped_files: []string,
}

Preview_Frame :: struct {
	device: ^foster.GraphicsDevice,
	target: foster.DrawableTarget,
	material: ^foster.Material,
	group, dimension: string,
	time: f32,
	width, height: int,
	pass: string, // 显式声明的 Pass ID；未被 Pass 引用的组不执行 GPU 管线探测。
	delta_time: f32,
	frame_index: u64,
}

Preview_Hooks :: struct {
	user_data: rawptr,
	// 填写实际绘制命令，同时用于热重载管线探测；false 使用内置模型。
	prepare: proc(user_data: rawptr, frame: Preview_Frame, command: ^foster.DrawCommand) -> bool,
	// 可覆盖 b0 等宿主输入后绘制；须使用 prepare 声明的管线配置。
	draw: proc(user_data: rawptr, frame: Preview_Frame, command: ^foster.DrawCommand),
}
