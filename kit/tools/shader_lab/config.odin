package shader_lab

// 宿主负责窗口、ImGui 上下文与字体、输入路由和 Dock 布局；工具只持有独立的预览会话，
// 每帧在宿主的 ImGui 帧里提交自己的窗口。
import r2d "olib:kit/rendering/2d"
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"

// 工具提交的两个窗口名，宿主可据此停靠；同一 ImGui 上下文只放一个 Session。
CONTROL_WINDOW :: "Shader Lab"
PREVIEW_WINDOW :: "Shader 预览"

Config :: struct {
	// source_root 递归发现 .oshader。
	source_root: string,
	paused: bool,
	// 宿主通过 file_request / file_reply 接入自己的文件对话框。
	file_dialogs: bool,
	// 可选：用系统默认程序打开源码文件（参数组里的“编辑 <文件>”按钮）；nil 时只显示文件名。path 是绝对路径。
	open_file: proc(path: string) -> bool,
	preview: Preview_Hooks,
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
