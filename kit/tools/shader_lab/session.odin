package shader_lab

// 会话拥有预览参数、相机、GPU 资源与各组独立的热重载会话。
// HLSL 由外部编辑器修改/保存；这里的参数仅供预览，不写回源码，无文档撤销历史。
// UI 先消费输入；右键轨道旋转只在预览内开始，捕获持续到释放或离焦。
// 分区：状态 / 生命周期 / 更新与取消。面板和绘制分别见 panel / preview。

import "core:fmt"
import "core:math"
import "core:strings"

import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import mat "olib:kit/rendering/material"
import r3d "olib:kit/rendering/3d"
import dev "olib:kit/rendering/shader/dev"
import ui "olib:kit/ui"
import world "olib:kit/world"
import clay "olib:thirdparty/clay-odin"

Session :: struct {
	device: ^foster.GraphicsDevice,
	// 2D 材质预览：Render2D 借用这个库的设备与默认材质；sprite_mesh 是 BatcherVertex 布局的空网格，供管线探测。
	library: mat.Material_Library,
	render: r2d.Render2D,
	// 材质效果的预览与游戏一样用 Render2D / Render3D 记录后提交，材质借用 bank 的 GPU 绑定（见 material_preview.odin）。
	preview_sprites: r2d.Render2D,
	preview_models: r3d.Render3D,
	sprite_mesh: foster.Mesh,
	font: ^foster.MsdfFont, // 借用宿主字体，宿主须在 dispose 后释放。
	icons: ^r2d.Sprite_Atlas,
	owned_icons: r2d.Sprite_Atlas,
	delta_time: f32,
	region: foster.Rect,
	input: Input,
	capture: ui.UI_Input_Capture,
	source_root: string,
	using bank: ^Parameter_Bank,
	pending_bank: ^Parameter_Bank,
	bank_error: string,
	selected: int,
	// selected_effect=-1 表示工作区无效果；inspect_pass 只决定编辑哪个 Pass。
	selected_effect, inspect_pass: int,
	preview_pass: int, // -1 始终看最终效果；与编辑中的 inspect_pass 分开。
	effect_menu, preview_settings: bool,
	ui_scale: f32,
	workspace: int, // 0: 2D，1: 3D。
	workspace_empty: bool,
	workspaces: [2]Workspace_State,
	scroll_offsets: map[u32]clay.Vector2,
	scroll_restores: [dynamic]ui.UI_Scroll_Entry,
	tick_serial: u64,
	step_requested: bool,
	parameter_watch: dev.Parameter_Watch,
	fonts_dirty: bool,
	color_picker: Color_Picker,
	meshes: [3]foster.Mesh,
	texture: foster.Texture,
	sprite_texture: foster.Texture, // Sprite 预览帧采用预乘 Alpha，旧图像预览保持原输入。
	output: foster.Target,
	panel_active: bool,
	retired_textures: [dynamic]^foster.Texture,
	batch: r2d.Render2D, // UI：panel 记录，preview 叠加到输出时提交；预览合成用 render
	ctx: ui.UI_Context,
	theme, heading_theme, small_theme: ui.UI_Theme,
	camera: world.Camera3D,
	mode: int,

	yaw, pitch, distance, clock: f32,
	paused, orbiting: bool,
	viewport: foster.Rect,
	pointer: foster.Vec2,
	initialized: bool,
	render_serial: int,
	file_dialogs: bool,
	request: File_Request,
	request_serial, schema_generation: u64,
	preview_hooks: Preview_Hooks,
	custom_preview: bool,
	sidebar_width, sidebar_effective, splitter_original: f32,
	sidebar_collapsed, compact, splitting: bool,
	parameter_inset: f32, // 当前 Shader folder 的布局缩进，仅在构建 UI 时使用。
	texture_poll: f32,
}

Vertex2D :: struct {
	position: [2]f32,
	uv: [2]f32,
}

// ==============================================================================
// 生命周期
// ==============================================================================

// Config 的路径被复制；device / font / font_texture 借用至 dispose。Session 不得搬动。
init :: proc(s: ^Session, device: ^foster.GraphicsDevice, config: Config) -> bool {
	if s.initialized || device == nil || config.font == nil || config.font_texture.Resource == nil do return false
	if config.font.Size <= 0 || config.font.DistanceRange <= 0 do return false
	if config.source_root == "" do return false
	if config.icons != nil {
		if !config.icons.has_upload || config.icons.texture.Resource == nil do return false
		s.icons = config.icons
	} else {
		if !r2d.builtin_icons_load(&s.owned_icons, device) do return false
		s.icons = &s.owned_icons
	}
	s.device = device
	s.bank = new(Parameter_Bank)
	s.selected_effect = -1
	s.inspect_pass = -1
	s.preview_pass = -1
	s.ui_scale = 1
	s.scroll_offsets = make(map[u32]clay.Vector2)
	s.font = config.font
	s.source_root = strings.clone(config.source_root)
	s.distance = 4
	s.yaw = 0.4
	s.pitch = 0.25
	s.paused = config.paused
	s.file_dialogs = config.file_dialogs
	s.preview_hooks = config.preview
	s.custom_preview = config.preview.record != nil
	for &w, i in s.workspaces {
		w.mode = i == 1 ? 2 : 0
		w.paused = s.paused
		w.custom_preview = s.custom_preview
		w.yaw, w.pitch, w.distance = s.yaw, s.pitch, s.distance
	}
	s.sidebar_width = 312
	s.clock = 1
	dev.parameters_init(&s.parameter_watch, s.source_root)
	s.library = {device = device}
	if reason := r2d.init(&s.render, &s.library); reason != "" {
		fmt.eprintln("Shader Lab:", reason)
		return false
	}
	if reason := r2d.init(&s.batch, &s.library); reason != "" {
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
	assert(ui.ui_init(&s.ctx, 1280, 800))
	s.theme = config.theme != nil ? config.theme^ : lab_theme()
	s.theme.body_font_id = u16(ui.ui_register_font(&s.ctx, s.font, config.font_texture, .MSDF))
	s.heading_theme = s.theme
	s.small_theme = s.theme
	if config.theme == nil do s.small_theme.small_font_size = 14
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
	mat.material_library_dispose(&s.library)
	r2d.dispose(&s.batch)
	ui.ui_dispose(&s.ctx)
	r2d.atlas_dispose(&s.owned_icons)
	foster.TextureDispose(&s.texture)
	foster.TextureDispose(&s.sprite_texture)
	texture_retire_flush(s)
	delete(s.retired_textures)
	foster.TargetDispose(&s.output)
	delete(s.source_root)
	for &workspace in s.workspaces do workspace_dispose(&workspace)
	delete(s.scroll_offsets)
	delete(s.scroll_restores)
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
		for &shader in s.pending_bank.shaders[:s.pending_bank.shader_count] {
			dev.update(&shader, f64(s.delta_time))
		}
	}
	textures_update(s)

	for &shader, i in s.shaders[:s.shader_count] {
		if !s.parameters[i].available do continue
		if shader.status != s.last_status[i] {
			fmt.printf("%s: %v (revision %d)\n", s.parameters[i].name, shader.status, shader.revision)
			if shader.status == .Error && shader.diagnostic != "" do fmt.eprintln(shader.diagnostic)
			s.last_status[i] = shader.status
		}
	}
}

// 停用/隐藏面板时也应调用；调色板恢复原值，其他输入捕获清空。
cancel :: proc(s: ^Session) {
	if !s.initialized do return
	color_picker_close(s, false)
	s.orbiting = false
	if s.splitting do s.sidebar_width = s.splitter_original
	s.splitting = false
	s.ctx.active_id = 0
	s.ctx.focused_id = 0
	// 取消捕获不伪造鼠标松开，否则按住时下一帧会被当成新的点击。
	ui.ui_set_modal(&s.ctx, "")
	s.capture = {}
}
