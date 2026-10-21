package rendering2d

// Render2D：2D 唯一的绘制入口，用法与 foster Batcher 一致——记录图元（矩阵 / 裁剪 / 混合 / 采样器 / mode 栈），
// submit 时按记录顺序合批提交并清空，submit 是唯一的提交点。材质是 olib 的 mat.Material；不传时用材质库的
// 内置 Sprite_Default（贴图 × 顶点色，Web 可用）。顶点格式就是 foster.BatcherVertex，tint 放在顶点色里。
// 分区：类型 / 生命周期 / 状态栈 / 图元 / 提交 / 记录与合批。
import "core:math"
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"

@(private)
RENDER2D_BATCH_QUADS :: 4096

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 一次提交的视图：目标与时间（写入 olib 效果的 Clock）。pointer 是归一化指针位置（Pointer.xy），业务通常不用。
View :: struct {
	target: foster.DrawableTarget,
	time, delta_time: f32,
	frame: u64,
	pointer: [2]f32,
}

// 材质路径的引擎块字节数：顶点 b0 为 Projection + Clock，片元 b0 为 Clock、Pointer、Tint。
// 与 kit/rendering/shader/lang/include/olib/sprite.hlsli 一致（tests/kit/rendering/2d 检查）。
SPRITE_VERTEX_BLOCK_SIZE :: 80
SPRITE_FRAME_BLOCK_SIZE :: 48

Render2D :: struct {
	library: ^mat.Material_Library,
	default_material: ^mat.Material, // 内置 Sprite_Default 的实例，归材质库所有
	draw_calls: int, // 最近一次 submit 的 Draw 数
	// 以下由渲染器维护。
	transform: [16]f32, // 4×4 矩阵，行向量约定（v * M，下标 行*4+列），存储与 foster Batcher 相同
	sampler: foster.TextureSampler,
	blend: foster.BlendMode,
	mode: foster.BatcherMode,
	mode_color: foster.Color,
	scissor: foster.RectInt,
	has_scissor: bool,
	transform_stack: [dynamic][16]f32,
	sampler_stack: [dynamic]foster.TextureSampler,
	blend_stack: [dynamic]foster.BlendMode,
	mode_stack: [dynamic]foster.BatcherModeState,
	scissor_stack: [dynamic]Render2D_Scissor,
	vertices: [dynamic]foster.BatcherVertex,
	runs: [dynamic]Render2D_Run,
	// 每个 run 的每个 Pass 一份 GPU 材质快照（Shader、参数 uniform、贴图）；跨帧复用，submit 时补上投影与 Clock。
	snapshots: [dynamic]foster.Material,
	snapshot_count: int,
	mesh: foster.Mesh,
	index_quads: int, // 索引缓冲已覆盖的四边形数（索引是固定的四边形图案，只在增长时重建）
	// 带 [Instance] 字段的效果：每个精灵一组 float4，顶点 mode 字节存它的起始偏移；[0] 保留不用。submit 时上传一次。
	instance_values: [dynamic][4]f32,
	instance_buffer: foster.StorageBuffer,
	instance_ready: bool,
	// r2d.buffer 用的单位四边形角点网格，首次使用时创建。
	corner_mesh: foster.Mesh,
	corner_ready: bool,
}

Render2D_Scissor :: struct {
	rect: foster.RectInt,
	enabled: bool,
}

// 连续可合并的一段记录：同一材质与 Pass 选择、同一帧贴图 / 采样器 / 混合 / 裁剪、参数相同。
@(private)
Render2D_Run :: struct {
	material: ^mat.Material,
	revision: u64, // 快照时的材质 revision；之后数值或贴图有变就开新段

	pass_id: mat.Pass_Id,
	selection: mat.Pass_Selection,
	snapshot: int, // 第一个 Pass 的快照下标，后面连续 selection.count 个
	texture: ^foster.Texture,
	sampler: foster.TextureSampler,
	blend: foster.BlendMode,
	scissor: Render2D_Scissor,
	quad_start, quad_count: int,
	storage: bool, // 顶点从 instance_values 读两条轴和 [Instance] 字段（.oshader 效果总是）
	pass_offsets: [mat.MAX_PASSES]u32, // 每个精灵的数值记录内，各 Pass 的 float4 偏移
	// r2d.buffer 记录的常驻缓冲：不与其他记录合并，用缓冲变体顶点着色器实例化绘制。
	buffer: ^Sprite_Buffer,
	instance_count: int,
	transform: [16]f32, // 记录时的变换栈，提交时其 2D 仿射部分写入顶点 b1
}

// ------------------------------------------------------------------------------
// 生命周期
// ------------------------------------------------------------------------------

// 设备取自材质库；返回 "" 表示成功。r 初始化后不得搬动（快照材质被绘制命令借用）。
init :: proc(r: ^Render2D, library: ^mat.Material_Library) -> string {
	if library == nil || library.device == nil do return "Missing graphics device"
	material, reason := mat.material_create(library, mat.BUILTIN_SPRITE)
	if reason != "" do return reason
	r^ = {library = library, default_material = material}
	render2d_reset_state(r)
	format := foster.BatcherVertexFormat()
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(&r.mesh, library.device, format, .ThirtyTwo, "render2d")
	return ""
}

// 丢弃未提交的记录并释放 GPU 资源；默认材质归材质库，不在这里释放。
dispose :: proc(r: ^Render2D) {
	for &snapshot in r.snapshots do foster.MaterialDispose(&snapshot)
	delete(r.snapshots)
	delete(r.vertices)
	delete(r.runs)
	delete(r.transform_stack)
	delete(r.sampler_stack)
	delete(r.blend_stack)
	delete(r.mode_stack)
	delete(r.scissor_stack)
	delete(r.instance_values)
	if r.instance_ready do foster.StorageBufferDispose(&r.instance_buffer)
	if r.corner_ready do foster.MeshDispose(&r.corner_mesh)
	if r.library != nil do foster.MeshDispose(&r.mesh)
	r^ = {}
}

// 丢弃已记录、未提交的内容并恢复默认状态（与 foster BatcherClear 相同），例如目标失效时放弃本帧。
reset :: proc(r: ^Render2D) {
	render2d_reset(r)
}

// ------------------------------------------------------------------------------
// 状态栈 —— 语义与 foster Batcher 的同名 Push/Pop 相同；submit 后全部恢复默认。
// ------------------------------------------------------------------------------

// relative 为 true 时 m 先作用，再接当前矩阵（相机先 push，物体再相对 push）。
push_matrix :: proc(r: ^Render2D, m: foster.Matrix3x2, relative := true) {
	push_matrix_raw(r, {m.M11, m.M12, 0, 0, m.M21, m.M22, 0, 0, 0, 0, 1, 0, m.M31, m.M32, 0, 1}, relative)
}

push_matrix_trs :: proc(r: ^Render2D, position, scale: foster.Vec2, rotation: f32, relative := true) {
	push_matrix(r, foster.TransformCreateMatrix(position, {}, scale, rotation), relative)
}

push_matrix_raw :: proc(r: ^Render2D, m: [16]f32, relative := true) {
	append(&r.transform_stack, r.transform)
	if !relative {
		r.transform = m
		return
	}
	// 行向量约定（v' = v * M，下标 行*4+列）：out = m * 当前，与上游 Foster 的 `matrix * Matrix` 一致。
	// 注意 foster 移植版 BatcherPushMatrixRaw 的相对组合顺序与此相反（现有调用都用 relative=false，未受影响）。
	a := r.transform
	out: [16]f32
	for row in 0..<4 {
		for col in 0..<4 {
			out[row*4 + col] = m[row*4]*a[col] + m[row*4 + 1]*a[4 + col] + m[row*4 + 2]*a[8 + col] + m[row*4 + 3]*a[12 + col]
		}
	}
	r.transform = out
}

pop_matrix :: proc(r: ^Render2D) {
	if len(r.transform_stack) > 0 do r.transform = pop(&r.transform_stack)
}

// 只影响默认材质：Normal 为贴图 × 颜色，Wash 只取贴图 alpha，Fill 只用颜色。
push_mode :: proc(r: ^Render2D, mode: foster.BatcherMode) {
	append(&r.mode_stack, foster.BatcherModeState{r.mode, r.mode_color})
	r.mode = mode
	r.mode_color = render2d_mode_color(mode)
}

pop_mode :: proc(r: ^Render2D) {
	if len(r.mode_stack) == 0 do return
	state := pop(&r.mode_stack)
	r.mode, r.mode_color = state.Mode, state.Color
}

// 帧贴图的采样方式；材质自带的其他贴图不受影响。
push_sampler :: proc(r: ^Render2D, sampler: foster.TextureSampler) {
	append(&r.sampler_stack, r.sampler)
	r.sampler = sampler
}

pop_sampler :: proc(r: ^Render2D) {
	if len(r.sampler_stack) > 0 do r.sampler = pop(&r.sampler_stack)
}

// 未声明混合方式的 Pass 使用它；Pass 显式声明的 blend 优先。
push_blend :: proc(r: ^Render2D, blend: foster.BlendMode) {
	append(&r.blend_stack, r.blend)
	r.blend = blend
}

pop_blend :: proc(r: ^Render2D) {
	if len(r.blend_stack) > 0 do r.blend = pop(&r.blend_stack)
}

// 目标像素坐标的裁剪矩形。
push_scissor :: proc(r: ^Render2D, scissor: foster.RectInt) {
	append(&r.scissor_stack, Render2D_Scissor{r.scissor, r.has_scissor})
	r.scissor, r.has_scissor = scissor, true
}

pop_scissor :: proc(r: ^Render2D) {
	if len(r.scissor_stack) == 0 do return
	state := pop(&r.scissor_stack)
	r.scissor, r.has_scissor = state.rect, state.enabled
}

// ------------------------------------------------------------------------------
// 图元 —— 只记录；返回值为记录时就能确定的错误（材质未加载、Pass 不存在等），.None 表示已记录。
// material 为 nil 时用内置 Sprite_Default。纯色图元在默认材质下用 Fill 模式，不因贴图不同而断批。
// ------------------------------------------------------------------------------

// 画图集子图：保留裁剪后的 DrawCoords / TexCoords，origin 是相对未裁剪原图的锚点像素。
// values 只设置这一次绘制的 [Instance] 字段，不修改共享材质。
image :: proc(r: ^Render2D, frame: foster.Subtexture, transform: foster.Matrix3x2, color := foster.White,
	origin: foster.Vec2 = {}, material: ^mat.Material = nil, values: ^mat.Instance_Values = nil,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if frame.Texture == nil || frame.Texture.Resource == nil do return .Missing_Sprite_Texture
	corners := render2d_frame_corners(frame, origin, transform)
	axes := [4]f32{transform.M11, transform.M12, transform.M21, transform.M22}
	return render2d_record(r, material, frame.Texture, corners, frame.TexCoords, {color, color, color, color}, values, pass_id, axes)
}

// 整张贴图当一帧。
texture :: proc(r: ^Render2D, texture: ^foster.Texture, transform: foster.Matrix3x2, color := foster.White,
	origin: foster.Vec2 = {}, material: ^mat.Material = nil, values: ^mat.Instance_Values = nil,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if texture == nil || texture.Resource == nil do return .Missing_Sprite_Texture
	return image(r, foster.SubtextureFromTexture(texture), transform, color, origin, material, values, pass_id)
}

// 任意四边形贴图，顶点顺序 a→b→c→d（两个三角形 abc、acd）。
quad_texture :: proc(r: ^Render2D, texture: ^foster.Texture, a, b, c, d: foster.Vec2,
	uv0, uv1, uv2, uv3: foster.Vec2, color := foster.White, material: ^mat.Material = nil,
	values: ^mat.Instance_Values = nil, pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if texture == nil || texture.Resource == nil do return .Missing_Sprite_Texture
	return render2d_record(r, material, texture, {a, b, c, d}, {uv0, uv1, uv2, uv3}, {color, color, color, color}, values, pass_id, RENDER2D_AXES_IDENTITY)
}

quad :: proc(r: ^Render2D, a, b, c, d: foster.Vec2, color: foster.Color, material: ^mat.Material = nil) -> mat.Draw_Error {
	return render2d_record(r, material, nil, {a, b, c, d}, {}, {color, color, color, color}, nil, "", RENDER2D_AXES_IDENTITY)
}

// 四个顶点各自的颜色，GPU 插值成渐变；顶点顺序同 quad。
quad_gradient :: proc(r: ^Render2D, a, b, c, d: foster.Vec2, c0, c1, c2, c3: foster.Color,
	material: ^mat.Material = nil) -> mat.Draw_Error {
	return render2d_record(r, material, nil, {a, b, c, d}, {}, {c0, c1, c2, c3}, nil, "", RENDER2D_AXES_IDENTITY)
}

// 矩形渐变：c0..c3 依次为左上、右上、右下、左下。
rect_gradient :: proc(r: ^Render2D, rect: foster.Rect, c0, c1, c2, c3: foster.Color, material: ^mat.Material = nil) -> mat.Draw_Error {
	x0, y0, x1, y1 := rect.X, rect.Y, rect.X + rect.Width, rect.Y + rect.Height
	return quad_gradient(r, {x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}, c0, c1, c2, c3, material)
}

rect :: proc(r: ^Render2D, rect: foster.Rect, color: foster.Color, material: ^mat.Material = nil) -> mat.Draw_Error {
	x0, y0, x1, y1 := rect.X, rect.Y, rect.X + rect.Width, rect.Y + rect.Height
	return quad(r, {x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}, color, material)
}

// 粗细为 thickness 的线段（四边形）；长度为 0 时不记录。
line :: proc(r: ^Render2D, from, to: foster.Vec2, thickness: f32, color: foster.Color, material: ^mat.Material = nil) -> mat.Draw_Error {
	d := to - from
	length := math.sqrt(d.x*d.x + d.y*d.y)
	if length <= 0 do return .None
	n := foster.Vec2{-d.y, d.x} / length * thickness * 0.5
	return quad(r, from + n, to + n, to - n, from - n, color, material)
}

// 三角形按退化四边形（第四个顶点重复 c）记录，与其他图元共用同一套索引。
triangle :: proc(r: ^Render2D, a, b, c: foster.Vec2, color: foster.Color, material: ^mat.Material = nil) -> mat.Draw_Error {
	return quad(r, a, b, c, c, color, material)
}

// 实心圆，steps < 3 时不记录。
circle :: proc(r: ^Render2D, center: foster.Vec2, radius: f32, steps: int, color: foster.Color, material: ^mat.Material = nil) -> mat.Draw_Error {
	if steps < 3 do return .None
	for i in 0..<steps {
		a0 := f32(i) / f32(steps) * math.TAU
		a1 := f32(i + 1) / f32(steps) * math.TAU
		p0 := center + foster.Vec2{math.cos(a0), math.sin(a0)} * radius
		p1 := center + foster.Vec2{math.cos(a1), math.sin(a1)} * radius
		if error := triangle(r, center, p0, p1, color, material); error != .None do return error
	}
	return .None
}

// 中心到边缘渐变的实心圆，steps < 3 时不记录。
circle_gradient :: proc(r: ^Render2D, center: foster.Vec2, radius: f32, steps: int, center_color, edge_color: foster.Color,
	material: ^mat.Material = nil) -> mat.Draw_Error {
	if steps < 3 do return .None
	for i in 0..<steps {
		a0 := f32(i) / f32(steps) * math.TAU
		a1 := f32(i + 1) / f32(steps) * math.TAU
		p0 := center + foster.Vec2{math.cos(a0), math.sin(a0)} * radius
		p1 := center + foster.Vec2{math.cos(a1), math.sin(a1)} * radius
		error := quad_gradient(r, center, p0, p1, p1, center_color, edge_color, edge_color, edge_color, material)
		if error != .None do return error
	}
	return .None
}

// 用 foster 的位图字体（SpriteFont）画一段文字，语义同 foster SpriteFontDraw：position 是左上角，
// size 为 0 时用字体原始字号，justify 为对齐比例（0 左/上，0.5 居中，1 右/下），支持换行与字距。
// 字形用字体的采样器；字体自带的 foster.Material 不使用（material 为 nil 时用默认材质）。
text :: proc(r: ^Render2D, font: ^foster.SpriteFont, value: string, position: foster.Vec2, color := foster.White,
	size: f32 = 0, justify: foster.Vec2 = {}, material: ^mat.Material = nil) -> mat.Draw_Error {
	if font == nil do return .None
	size := size > 0 ? size : font.Size
	scale := font.Size > 0 ? size / font.Size : 1
	push_matrix(r, {scale, 0, 0, scale, position.x, position.y})
	defer pop_matrix(r)
	push_sampler(r, font.Sampler)
	defer pop_sampler(r)
	line_start := 0
	at := foster.Vec2{0, font.Ascent}
	if justify.y != 0 do at.y -= justify.y * foster.SpriteFontHeightOf(font, value)
	last := 0
	for c, index in value {
		if index == line_start && justify.x != 0 {
			at.x = -justify.x * foster.SpriteFontWidthOfLine(font, value[index:])
		}
		if c == '\n' {
			at = {0, at.y + font.LineHeight}
			line_start, last = index + 1, 0
			continue
		}
		glyph, ok := foster.SpriteFontFindCharacter(font, int(c))
		if !ok do continue
		if last != 0 do at.x += foster.SpriteFontGetKerning(font, last, int(c))
		if glyph.Subtexture.Texture != nil {
			p := at + glyph.Offset
			if error := image(r, glyph.Subtexture, {1, 0, 0, 1, p.x, p.y}, color, material = material); error != .None {
				return error
			}
		}
		at.x += glyph.Advance
		last = int(c)
	}
	return .None
}

// 空心圆：外径 radius、环宽 thickness；环宽不小于半径时画实心圆，steps < 3 时不记录。
circle_line :: proc(r: ^Render2D, center: foster.Vec2, radius, thickness: f32, steps: int, color: foster.Color,
	material: ^mat.Material = nil) -> mat.Draw_Error {
	if steps < 3 do return .None
	inner := radius - thickness
	if inner <= 0 do return circle(r, center, radius, steps, color, material)
	for i in 0..<steps {
		a0 := f32(i) / f32(steps) * math.TAU
		a1 := f32(i + 1) / f32(steps) * math.TAU
		d0 := foster.Vec2{math.cos(a0), math.sin(a0)}
		d1 := foster.Vec2{math.cos(a1), math.sin(a1)}
		error := quad(r, center + d0*inner, center + d0*radius, center + d1*radius, center + d1*inner, color, material)
		if error != .None do return error
	}
	return .None
}

// ------------------------------------------------------------------------------
// 提交 —— 上传本帧顶点，按记录顺序逐段、逐 Pass 绘制，然后清空记录并恢复默认状态。
// ------------------------------------------------------------------------------

submit :: proc(r: ^Render2D, view: View) -> mat.Draw_Error {
	defer render2d_reset(r)
	r.draw_calls = 0
	if len(r.runs) == 0 do return .None
	w, h := view.target.WidthInPixels, view.target.HeightInPixels
	if w <= 0 || h <= 0 do return .Invalid_Target
	render2d_upload(r)
	// 顶点 b0：目标像素到裁剪空间的投影，后接 Clock（与片元 Clock 同值）。
	vertex_uniform := [SPRITE_VERTEX_BLOCK_SIZE/4]f32{2/f32(w), 0, 0, 0, 0, -2/f32(h), 0, 0, 0, 0, 1, 0, -1, 1, 0, 1,
		view.time, view.delta_time, f32(view.frame), 0}
	frame := [SPRITE_FRAME_BLOCK_SIZE/4]f32{view.time, view.delta_time, f32(view.frame), 0, view.pointer[0], view.pointer[1],
		f32(w), f32(h), 1, 1, 1, 1}
	for &run in r.runs {
		effect := run.material.effect.desc
		for i in 0..<run.selection.count {
			snapshot := &r.snapshots[run.snapshot + i]
			storage := run.storage
			if storage {
				pass_offset := [4]u32{run.pass_offsets[i], 0, 0, 0}
				foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, mem.slice_to_bytes(pass_offset[:]), 1)
			}
			if run.buffer != nil {
				// 常驻缓冲的实例在变换栈之前的坐标里：olib_sprite 用 b1 的 2D 仿射部分换算到目标像素，
				// 与批量变体在 CPU 上套用的部分相同，position 与轴在两种变体里同一空间。
				t := run.transform
				stack := [8]f32{t[0], t[1], t[4], t[5], t[12], t[13], 0, 0}
				foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, mem.slice_to_bytes(stack[:]), 1)
			}
			foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, mem.slice_to_bytes(vertex_uniform[:]), 0)
			if effect.uniforms == .Olib {
				foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, mem.slice_to_bytes(frame[:]), 0)
			}
			command: foster.DrawCommand
			shifted: foster.VertexBuffer
			if run.buffer != nil {
				// 角点网格的属性后移，让实例属性占据 0..4+slots；浅拷贝只换格式，共享 GPU 资源。
				foster.DrawCommandFromMesh(&command, view.target, &r.corner_mesh, snapshot)
				shifted = r.corner_mesh.VertexData
				shifted.Format = foster.VertexFormatClone(r.corner_mesh.VertexData.Format)
				for &element in shifted.Format.Elements do element.Index += mat.INSTANCE_FIXED_ATTRIBUTES + run.buffer.slots
				command.VertexBuffers[0].Buffer = &shifted
				append(&command.VertexBuffers, foster.VertexBufferBinding{Buffer = &run.buffer.buffer, InstanceInputRate = true})
				command.InstanceCount = run.instance_count
			} else {
				foster.DrawCommandFromMesh(&command, view.target, &r.mesh, snapshot)
				command.IndexOffset = run.quad_start*6
				command.IndexCount = run.quad_count*6
				command.VertexCount = 0
				if storage do append(&command.VertexStorageBuffers, &r.instance_buffer)
			}
			command.BlendMode = run.blend
			command.CullMode = .None
			command.DepthTestEnabled = false
			command.DepthWriteEnabled = false
			command.HasScissor = run.scissor.enabled
			command.Scissor = run.scissor.rect
			mat.pass_state_apply(&command, effect.passes[run.selection.passes[i]].state)
			foster.GraphicsDeviceDraw(r.library.device, &command)
			foster.DrawCommandDispose(&command)
			if run.buffer != nil do foster.VertexFormatDispose(&shifted.Format)
			r.draw_calls += 1
		}
	}
	return .None
}

// 记录常驻缓冲 buf 的前 count 个精灵：每个 Pass 一次实例化 Draw，帧贴图都是 texture（图集页）。
// 材质须是 instanced 精灵效果（有缓冲变体）；[Instance] 字段以缓冲为准，统一参数来自材质。
// 当前变换栈（如相机）同样作用于这些精灵；按记录顺序与其他图元叠放，不与它们合批。
buffer :: proc(r: ^Render2D, material: ^mat.Material, buf: ^Sprite_Buffer, count: int,
	texture: ^foster.Texture, pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if r.library == nil || r.library.device == nil do return .Missing_Device
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if material.owner.device != r.library.device do return .Device_Mismatch
	effect := material.effect
	if !mat.effect_is_sprite(effect.desc) || !effect.desc.instanced || effect.instanced_vertex == nil {
		return .Not_Instanced_Effect
	}
	if buf == nil || buf.capacity <= 0 do return .Instance_Buffer_Required
	if buf.slots != mat.instance_slot_count(material) do return .Instance_Mismatch
	if texture == nil || texture.Resource == nil do return .Missing_Sprite_Texture
	selection: mat.Pass_Selection
	if error := mat.material_select(effect.desc, material.bindings, .Sprite, pass_id, texture, &selection); error != .None do return error
	if selection.count == 0 do return .None
	if !render2d_corner_mesh(r) do return .Missing_Device
	render2d_run_begin(r, material, pass_id, texture, selection, nil)
	run := &r.runs[len(r.runs) - 1]
	run.buffer, run.instance_count, run.transform = buf, clamp(count, 0, buf.capacity), r.transform
	run.storage = false // 缓冲变体的数值在实例顶点里，不使用 storage 或 Pass 偏移。
	// 顶点阶段换成缓冲变体；片元、参数与贴图与批量变体相同。
	for i in 0..<selection.count {
		group := material.bindings[selection.bindings[i]].schema.name
		for schema, j in effect.schemas {
			if schema.name == group {
				foster.MaterialStageSetShader(&r.snapshots[run.snapshot + i].Vertex, &effect.instanced_vertex[j])
			}
		}
	}
	return .None
}

// ------------------------------------------------------------------------------
// 记录与合批
// ------------------------------------------------------------------------------

@(private)
render2d_mode_color :: proc(mode: foster.BatcherMode) -> foster.Color {
	switch mode {
	case .Normal: return {255, 0, 0, 0}
	case .Wash: return {0, 255, 0, 0}
	case .Fill: return {0, 0, 255, 0}
	}
	return {255, 0, 0, 0}
}

@(private)
render2d_reset_state :: proc(r: ^Render2D) {
	r.transform = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
	r.sampler = foster.TextureSamplerMake(.Nearest, .Clamp)
	r.blend = foster.BlendModePremultiply
	r.mode = .Normal
	r.mode_color = render2d_mode_color(.Normal)
	r.scissor, r.has_scissor = {}, false
	clear(&r.transform_stack)
	clear(&r.sampler_stack)
	clear(&r.blend_stack)
	clear(&r.mode_stack)
	clear(&r.scissor_stack)
}

@(private)
render2d_reset :: proc(r: ^Render2D) {
	clear(&r.vertices)
	clear(&r.runs)
	clear(&r.instance_values)
	r.snapshot_count = 0
	render2d_reset_state(r)
}

// 精灵局部 1 像素在变换栈之前的两条轴 (x.x, x.y, y.x, y.y)；没有局部空间的图元用单位轴。
@(private)
RENDER2D_AXES_IDENTITY :: [4]f32{1, 0, 0, 1}

// 记录一个四边形。texture 为 nil 表示纯色图元。corners 与 axes 是变换栈之前的坐标与局部轴。
@(private)
render2d_record :: proc(r: ^Render2D, material: ^mat.Material, texture: ^foster.Texture,
	corners: [4]foster.Vec2, uvs: [4]foster.Vec2, colors: [4]foster.Color,
	values: ^mat.Instance_Values, pass_id: mat.Pass_Id, axes: [4]f32) -> mat.Draw_Error {
	if r.library == nil || r.library.device == nil do return .Missing_Device
	m := material != nil ? material : r.default_material
	if m == nil || m.owner == nil || m.effect == nil do return .Missing_Material
	if m.owner.device != r.library.device do return .Device_Mismatch
	last: ^Render2D_Run = len(r.runs) > 0 ? &r.runs[len(r.runs) - 1] : nil
	frame_texture := texture
	mode := m.effect.desc.uniforms == .Foster ? r.mode_color : foster.Color{}
	if texture == nil {
		if m == r.default_material {
			// Fill 只用顶点色：沿用当前段的帧贴图即可继续合批。
			mode = render2d_mode_color(.Fill)
			frame_texture = last != nil && last.material == m && last.texture != nil ? last.texture : &r.library.white
		} else {
			frame_texture = &r.library.white
		}
	}
	selection: mat.Pass_Selection
	if error := mat.material_select(m.effect.desc, m.bindings, .Sprite, pass_id, frame_texture, &selection); error != .None do return error
	if selection.count == 0 do return .None
	if !render2d_run_matches(r, last, m, pass_id, frame_texture, selection) {
		render2d_run_begin(r, m, pass_id, frame_texture, selection, values)
		last = &r.runs[len(r.runs) - 1]
	}
	if last.storage {
		// 轴也经过变换栈，与顶点位置在同一空间。
		t := r.transform
		stacked := [4]f32{axes[0]*t[0] + axes[1]*t[4], axes[0]*t[1] + axes[1]*t[5],
			axes[2]*t[0] + axes[3]*t[4], axes[2]*t[1] + axes[3]*t[5]}
		offset := render2d_record_instances(r, m, selection, values, stacked)
		mode = {u8(offset), u8(offset >> 8), u8(offset >> 16), u8(offset >> 24)}
	}
	for i in 0..<4 {
		append(&r.vertices, foster.BatcherVertex{Pos = render2d_transform(r, corners[i]), Tex = uvs[i], Col = colors[i], Mode = mode})
	}
	last.quad_count += 1
	return .None
}

// 一个精灵的记录：首项是两条轴，随后连续存放各 Pass 的独立数值；顶点保存起点，
// 提交时由顶点 b1 选择该 Pass 的偏移。
@(private)
render2d_record_instances :: proc(r: ^Render2D, m: ^mat.Material, selection: mat.Pass_Selection,
	values: ^mat.Instance_Values, axes: [4]f32) -> int {
	if len(r.instance_values) == 0 do append(&r.instance_values, [4]f32{})
	offset := len(r.instance_values)
	append(&r.instance_values, axes)
	for i in 0..<selection.count {
		p := m.effect.desc.passes[selection.passes[i]]
		instance := mat.material_pass_instance(p, m.bindings[selection.bindings[i]], values)
		append(&r.instance_values, ..instance.numbers[:instance.count])
	}
	return offset
}

// 子图四角（裁剪后的 DrawCoords 减去锚点）经 transform 变换，顺序与 TexCoords 一致。
@(private)
render2d_frame_corners :: proc(frame: foster.Subtexture, origin: foster.Vec2, transform: foster.Matrix3x2) -> (corners: [4]foster.Vec2) {
	for &corner, i in corners {
		corner = foster.Matrix3x2TransformPoint(transform, frame.DrawCoords[i] - origin)
	}
	return
}

@(private)
render2d_transform :: proc(r: ^Render2D, p: foster.Vec2) -> foster.Vec2 {
	m := r.transform
	return {p.x*m[0] + p.y*m[4] + m[12], p.x*m[1] + p.y*m[5] + m[13]}
}

// 参数 uniform 所在的片元槽：内置效果（Foster 布局）在槽 0，.oshader 效果在槽 1（槽 0 是 Clock 帧块）。
@(private)
render2d_param_slot :: proc(effect: mat.Effect_Desc) -> int {
	return effect.uniforms == .Foster ? 0 : 1
}

@(private)
render2d_run_matches :: proc(r: ^Render2D, run: ^Render2D_Run, m: ^mat.Material, pass_id: mat.Pass_Id,
	texture: ^foster.Texture, selection: mat.Pass_Selection) -> bool {
	// 两次绘制之间 material_set_number / material_set_texture / reload 会递增 revision：参数或贴图快照过期就断批。
	// [Instance] 数值不进参数 uniform，不影响合批。
	return run != nil && run.buffer == nil && run.quad_count < RENDER2D_BATCH_QUADS &&
		run.material == m && run.revision == m.revision && run.pass_id == pass_id && run.texture == texture &&
		run.sampler == r.sampler && run.blend == r.blend &&
		run.scissor == (Render2D_Scissor{r.scissor, r.has_scissor}) && run.selection == selection
}

@(private)
render2d_run_begin :: proc(r: ^Render2D, m: ^mat.Material, pass_id: mat.Pass_Id, texture: ^foster.Texture,
	selection: mat.Pass_Selection, values: ^mat.Instance_Values) {
	run := Render2D_Run{material = m, revision = m.revision, pass_id = pass_id, selection = selection, snapshot = r.snapshot_count,
		texture = texture, sampler = r.sampler, blend = r.blend, scissor = {r.scissor, r.has_scissor},
		quad_start = len(r.vertices) / 4}
	slot := render2d_param_slot(m.effect.desc)
	offset: u32
	for i in 0..<selection.count {
		p := m.effect.desc.passes[selection.passes[i]]
		binding := m.bindings[selection.bindings[i]]
		run.pass_offsets[i] = offset
		if m.effect.desc.uniforms == .Olib do offset += u32(mat.instance_count(binding.schema))
		if r.snapshot_count == len(r.snapshots) {
			append(&r.snapshots, foster.Material{})
			foster.MaterialInitWithShaders(&r.snapshots[r.snapshot_count], nil, nil)
		}
		snapshot := &r.snapshots[r.snapshot_count]
		r.snapshot_count += 1
		foster.MaterialStageSetShader(&snapshot.Vertex, binding.material.Vertex.Shader)
		foster.MaterialStageSetShader(&snapshot.Fragment, binding.material.Fragment.Shader)
		for k in 0..<len(snapshot.Vertex.UniformBuffers) do foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, nil, k)
		for k in 0..<len(snapshot.Fragment.UniformBuffers) do foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, nil, k)
		uniform, _ := mat.material_pass_values(p, binding, values)
		foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, uniform, slot)
		snapshot.Fragment.Samplers = {}
		copy(snapshot.Fragment.Samplers[:], binding.samplers)
		if p.sprite_texture != "" {
			index := 0
			for field in binding.schema.fields {
				if field.kind != .Texture do continue
				if field.id == string(p.sprite_texture) {
					snapshot.Fragment.Samplers[index] = {texture, mat.field_sprite_sampler(field, r.sampler)}
				}
				index += 1
			}
		}
	}
	run.storage = m.effect.desc.uniforms == .Olib
	append(&r.runs, run)
}

// 上传本帧顶点；索引是固定的四边形图案（0,1,2, 0,2,3），只在四边形数超过已有容量时重建。
@(private)
render2d_upload :: proc(r: ^Render2D) {
	quads := len(r.vertices) / 4
	if quads > r.index_quads {
		capacity := max(quads, r.index_quads*2, 1024)
		indices := make([]u32, capacity*6, context.temp_allocator)
		for q in 0..<capacity {
			base := u32(q*4)
			copy(indices[q*6:], []u32{base, base + 1, base + 2, base, base + 2, base + 3})
		}
		foster.MeshSetIndicesTyped(u32, &r.mesh, indices)
		r.index_quads = capacity
	}
	foster.MeshSetVerticesTyped(foster.BatcherVertex, &r.mesh, r.vertices[:])
	if len(r.instance_values) > 1 {
		if !r.instance_ready {
			foster.StorageBufferInitTyped([4]f32, &r.instance_buffer, r.library.device, "render2d instance values")
			r.instance_ready = true
		}
		foster.StorageBufferUploadTyped([4]f32, &r.instance_buffer, r.instance_values[:])
	}
}

// 单位四边形的四个角点，缓冲变体用 olib_sprite_vertex 把它展开成屏幕上的矩形。
@(private)
render2d_corner_mesh :: proc(r: ^Render2D) -> bool {
	if r.corner_ready do return true
	if r.library == nil || r.library.device == nil do return false
	format := foster.VertexFormatMake([]foster.VertexElement{{0, .Float2, false}}, size_of([2]f32))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(&r.corner_mesh, r.library.device, format, .ThirtyTwo, "render2d corners")
	corners := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	foster.MeshSetVerticesTyped([2]f32, &r.corner_mesh, corners[:])
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	foster.MeshSetIndicesTyped(u32, &r.corner_mesh, indices[:])
	r.corner_ready = true
	return true
}
