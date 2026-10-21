package shader_lab

// 宿主负责窗口、输入路由和 MSDF 资产；工具只持有独立的预览会话。
import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"
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

// 自定义预览的这一次绘制：要画的 Pass、它的参数组与预览维度、时间和目标尺寸。
Preview_Frame :: struct {
	pass: string, // 本次要画的 Pass ID；2D 记录时作为 pass_id 传入
	group, dimension: string,
	time, delta_time: f32,
	frame_index: u64,
	width, height: int,
}

Preview_Hooks :: struct {
	user_data: rawptr,
	// 材质 Shader 的自定义预览：用游戏同一套 API 记录要画的东西，Shader Lab 负责提交。对每个要画的 Pass 调用一次；
	// 2D 记录时把 frame.pass 作为 pass_id 传入，3D 只管记录（Shader Lab 按该 Pass 提交）。sprites / models
	// 按 Shader 维度只给一个，另一个为 nil。返回 false 使用内置几何。非材质 Shader（Fullscreen、Preview_Model）总用内置几何。
	record: proc(user_data: rawptr, frame: Preview_Frame, material: ^mat.Material,
		sprites: ^r2d.Render2D, models: ^r3d.Render3D) -> bool,
}
