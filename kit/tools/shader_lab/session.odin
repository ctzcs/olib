package shader_lab

// 会话拥有预览参数、相机、GPU 资源与各组独立的热重载会话。
// HLSL 由外部编辑器修改/保存；这里的参数仅供预览，不写回源码，无文档撤销历史。
// 输入由宿主的 ImGui 分配；右键轨道旋转只在预览图上开始，捕获持续到松开或 cancel。
// 分区：状态 / 生命周期 / 更新与取消。窗口和绘制分别见 windows / preview。

import "core:fmt"
import "core:math"
import "core:strings"

import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import mat "olib:kit/rendering/material"
import r3d "olib:kit/rendering/3d"
import sh "olib:kit/rendering/shader"
import dev "olib:kit/rendering/shader/dev"
import world "olib:kit/world"
import imgui_foster "olib:thirdparty/odin-imgui/imgui_impl_ofoster"

Session :: struct {
	device: ^foster.GraphicsDevice,
	// 2D 材质预览：Render2D 借用这个库的设备与默认材质；sprite_mesh 是 BatcherVertex 布局的空网格，供管线探测。
	library: mat.Material_Library,
	render: r2d.Render2D,
	// 材质 Shader 的预览与游戏一样用 Render2D / Render3D 记录后提交，材质借用 bank 的 GPU 绑定（见 material_preview.odin）。
	preview_sprites: r2d.Render2D,
	preview_models: r3d.Render3D,
	sprite_mesh: foster.Mesh,
	// instanced 模型的管线探测按 [Instance] 字段数各用一个实例缓冲（只用格式），首次需要时创建。
	probe_instances: [sh.MAX_INSTANCE_FIELDS + 1]r3d.Model_Buffer,
	icons: imgui_foster.Icons, // 从内置图集挑出 ICON_NAMES 缩成的小图标表
	delta_time: f32,
	source_root: string,
	using bank: ^Parameter_Bank,
	pending_bank: ^Parameter_Bank,
	bank_error: string,
	selected: int,
	// selected_shader=-1 表示工作区无 Shader；inspect_pass 只决定编辑哪个 Pass。
	selected_shader, inspect_pass: int,
	preview_pass: int, // -1 始终看最终效果；与编辑中的 inspect_pass 分开。
	shader_menu, preview_settings: bool,
	shader_menu_shown: bool, // 上一次 draw 结束时 Shader 菜单浮层是否打开
	workspace: int, // 0: 2D，1: 3D。
	workspace_empty: bool,
	workspaces: [2]Workspace_State,
	tick_serial: u64,
	step_requested: bool,
	parameter_watch: dev.Parameter_Watch,
	fonts_dirty: bool,
	missing_glyphs: int, // 最近一次标签校验中 ImGui 字体缺的字数
	color_picker: Color_Picker,
	meshes: [3]foster.Mesh,
	texture: foster.Texture,
	sprite_texture: foster.Texture, // Sprite 预览帧采用预乘 Alpha，旧图像预览保持原输入。
	drawing: bool, // draw 进行中：本帧 ImGui 绘制列表可能已引用旧纹理
	retired_textures: [dynamic]^foster.Texture,
	widgets: map[u64]Widget_Rect, // 最近一次 draw 登记的控件矩形，见 widget_rect
	dropped_files: []string, // 本次 draw 借用的拖入文件
	drop_position: [2]f32,
	camera: world.Camera3D,
	mode: int,

	yaw, pitch, distance, clock: f32,
	paused, orbiting: bool,
	viewport: foster.Rect, // 预览图在最终输出中的像素区域，决定 Pass 目标尺寸与鼠标 UV
	pointer: foster.Vec2, // 鼠标的最终输出像素坐标
	initialized: bool,
	render_serial: int,
	file_dialogs: bool,
	open_file: proc(path: string) -> bool,
	request: File_Request,
	request_serial, schema_generation: u64,
	preview_hooks: Preview_Hooks,
	custom_preview: bool,
	pending_shader: string, // new_shader 写出的 Shader 名，编译进 bank 后自动选中
	texture_poll: f32,
}

Vertex2D :: struct {
	position: [2]f32,
	uv: [2]f32,
}

// ==============================================================================
// 生命周期
// ==============================================================================

// Config 的路径被复制；device 借用至 dispose。Session 不得搬动。宿主的 ImGui 后端
// 可在 init 之前或之后初始化，draw 时必须已就绪。
init :: proc(s: ^Session, device: ^foster.GraphicsDevice, config: Config) -> bool {
	if s.initialized || device == nil || config.source_root == "" do return false
	icon_image, icon_rects, decoded := r2d.builtin_icons_decode()
	if !decoded do return false
	icons_ok := imgui_foster.IconsInit(&s.icons, device, icon_image, icon_rects^, ICON_NAMES[:], ICON_CELL)
	delete(icon_image.Pixels)
	r2d.kenney_rects_dispose(icon_rects)
	if !icons_ok do return false
	s.device = device
	s.bank = new(Parameter_Bank)
	s.selected_shader = -1
	s.inspect_pass = -1
	s.preview_pass = -1
	s.viewport = {0, 0, 960, 640} // 预览窗口第一次测量前的目标尺寸
	s.source_root = strings.clone(config.source_root)
	s.distance = 4
	s.yaw = 0.4
	s.pitch = 0.25
	s.paused = config.paused
	s.file_dialogs = config.file_dialogs
	s.open_file = config.open_file
	s.preview_hooks = config.preview
	s.custom_preview = config.preview.record != nil
	for &w, i in s.workspaces {
		w.mode = i == 1 ? 2 : 0
		w.paused = s.paused
		w.custom_preview = s.custom_preview
		w.yaw, w.pitch, w.distance = s.yaw, s.pitch, s.distance
	}
	s.clock = 1
	dev.parameters_init(&s.parameter_watch, s.source_root)
	s.library = {device = device}
	if reason := r2d.init(&s.render, &s.library); reason != "" {
		fmt.eprintln("Shader Lab:", reason)
		return false
	}
	if reason := r2d.init(&s.preview_sprites, &s.library); reason != "" {
		fmt.eprintln("Shader Lab:", reason)
		return false
	}
	if reason := r3d.init(&s.preview_models, &s.library); reason != "" {
		fmt.eprintln("Shader Lab:", reason)
		return false
	}
	sprite_format := foster.BatcherVertexFormat()
	defer foster.VertexFormatDispose(&sprite_format)
	foster.MeshInitWithFormat(&s.sprite_mesh, device, sprite_format, .ThirtyTwo, "sprite probe")
	format := foster.VertexFormatMake([]foster.VertexElement{{0, .Float2, false},
		{1, .Float2, false}}, size_of(Vertex2D))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(&s.meshes[0], device, format, .ThirtyTwo, "preview quad")
	vertices := [4]Vertex2D{{{-1, 1}, {0, 0}}, {{1, 1}, {1, 0}},
		{{1, -1}, {1, 1}}, {{-1, -1}, {0, 1}}}
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	foster.MeshSetVerticesTyped(Vertex2D, &s.meshes[0], vertices[:])
	foster.MeshSetIndicesTyped(u32, &s.meshes[0], indices[:])
	sphere := make_sphere(1.15, 48, 64, {})
	defer primitive_dispose(&sphere)
	assert(r3d.mesh_upload(&s.meshes[1], device, &sphere, "preview sphere"))
	cube := make_cube(1.8, {})
	defer primitive_dispose(&cube)
	assert(r3d.mesh_upload(&s.meshes[2], device, &cube, "preview cube"))
	image := foster.ImageMake(512, 512)
	defer foster.ImageDispose(&image)
	for y in 0..<512 {
		for x in 0..<512 {
			color := (x/64+y/64)%2 == 0 ? foster.Color{240, 245, 255, 255} :
				foster.Color{100, 120, 155, 255}
			dx := f32(x)-255.5
			dy := f32(y)-255.5
			color.A = u8(math.clamp(240-math.sqrt(dx*dx+dy*dy), 0, 1)*255)
			foster.ImageSetPixel(&image, x, y, color)
		}
	}
	s.texture = foster.TextureFromImage(device, &image, "checker sprite")
	foster.ImagePremultiply(&image)
	s.sprite_texture = foster.TextureFromImage(device, &image, "premultiplied sprite frame")
	world.camera3d_init(&s.camera, 960, 640)
	s.initialized = true
	fmt.println("Shader Lab: save .oshader/HLSLI to reload. Sources:", s.source_root)
	return true
}

dispose :: proc(s: ^Session) {
	if s.device == nil do return
	color_picker_dispose(s)
	file_request_clear(s)
	bank_dispose(s.pending_bank)
	bank_dispose(s.bank)
	delete(s.bank_error)
	dev.parameters_dispose(&s.parameter_watch)
	for &mesh in s.meshes do foster.MeshDispose(&mesh)
	r2d.dispose(&s.render)
	r2d.dispose(&s.preview_sprites)
	r3d.dispose(&s.preview_models)
	foster.MeshDispose(&s.sprite_mesh)
	for &buf in s.probe_instances do r3d.model_buffer_dispose(&buf)
	mat.material_library_dispose(&s.library)
	imgui_foster.IconsDispose(&s.icons)
	foster.TextureDispose(&s.texture)
	foster.TextureDispose(&s.sprite_texture)
	texture_retire_flush(s)
	delete(s.retired_textures)
	delete(s.widgets)
	delete(s.source_root)
	delete(s.pending_shader)
	for &workspace in s.workspaces do workspace_dispose(&workspace)
	s^ = {}
}

// ==============================================================================
// 输入与面板
// ==============================================================================

// 每帧调用；只推进时间与后台编译，不读取窗口输入，也不退出宿主。
update :: proc(s: ^Session, delta_time: f32) {
	if !s.initialized do return
	s.delta_time = max(0, delta_time)
	s.tick_serial += 1
	if !s.paused do s.clock += s.delta_time
	parameters_update(s)
	if s.pending_bank != nil {
		for &program in s.pending_bank.programs[:s.pending_bank.program_count] {
			dev.update(&program, f64(s.delta_time))
		}
	}
	textures_update(s)
	templates_update(s)

	for &program, i in s.programs[:s.program_count] {
		if !s.parameters[i].available do continue
		if program.status != s.last_status[i] {
			fmt.printf("%s: %v (revision %d)\n", s.parameters[i].name, program.status, program.revision)
			if program.status == .Error && program.diagnostic != "" do fmt.eprintln(program.diagnostic)
			s.last_status[i] = program.status
		}
	}
}

// 停用/隐藏面板、窗口离焦时调用；工具内按 Escape 也会调用。调色板恢复原值，轨道旋转结束。
cancel :: proc(s: ^Session) {
	if !s.initialized do return
	color_picker_close(s, false)
	s.orbiting = false
}
