package rendering3d

// 记录拥有 CPU 数据与材质绑定快照；GPU 资源借用至 clear/dispose。
// submit 只重建当前视图的队列，不消耗记录，也不清理目标附件。
// 分区：类型 / 生命周期 / 记录入口与快照 / 视图队列 / 提交与实例上传。
import "core:math"
import "base:builtin"
import "core:mem"
import dasset "olib:core/dasset"
import foster "olib:foster"
import mat "olib:kit/rendering/material"
import sh "olib:kit/rendering/shader"
import world "olib:kit/world"

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

View :: struct {
	target: foster.DrawableTarget,
	view_projection: world.Matrix4,
	// 必填（如 camera3d_view）：排序深度、调试线朝向与材质的 CameraPosition 使用它；零矩阵 submit 返回错误
	view_matrix: world.Matrix4,
	// 未指定时只在画全部 Pass（pass_id 为空）的提交里画；分阶段多次提交时在需要的那一次设为 true
	draw_debug: Maybe(bool),
	time, delta_time: f32,
	frame: u64,
	// 游戏按 std140 打包的视图级数据（太阳方向、雾色等），只在 submit 期间借用；
	// Model Pass 从顶点 b1 / 片元 b2 读取，超过 mat.VIEW_GLOBALS_SIZE 时 submit 返回错误。
	globals: []u8,
}

Render3D :: struct {
	library: ^mat.Material_Library,
	draw_calls, instances: int, // 最近一次 submit 的模型 Draw / 实例数（按 Pass 累计）
	// 以下由渲染器维护，clear 保留容量。
	records: [dynamic]Render3D_Record,
	sources: [dynamic]Render3D_Source,
	source_heads: map[u64]int,
	snapshots: [dynamic]foster.Material,
	snapshot_count: int,
	queue: Render_Queue(int),
	values: [dynamic][4]f32,
	// 每个材质最近一次准备的结果（选择、快照来源与默认实例值），revision 与 Shader 不变时复用。
	prepared: map[^mat.Material]Render3D_Prepared,
	defaults: [dynamic][4]f32,
	batches: [dynamic]Render3D_Batch,
	upload: [dynamic]u8,
	buffers: [sh.MAX_INSTANCE_FIELDS + 1]Model_Buffer, // 自动实例化的临时缓冲，按 [Instance] 字段数各一个
	debug: Debug_Draw_3D, // 线宽与深度开关；GPU 资源延迟到首次提交线段时创建
}

// 排序后队列中的一段连续 Draw。自动实例化时，第 k 个所选 Pass 的实例从临时缓冲的
// first + k × (end - start) 开始；每次 submit 先一次上传全部批次，再按偏移逐批绘制。
@(private)
Render3D_Batch :: struct {
	start, end: int,
	first: int,
}

@(private)
Render3D_Record :: struct {
	mesh: ^foster.Mesh,
	source: int,
	item: Model_Item,
	bounds: dasset.Dasset_Bounds, // 已转换到世界空间
	has_bounds: bool,
	values: int,
	buffer: ^Model_Buffer,
	count: int,
}

// 一个材质在当前记录集里的准备结果。材质只经 material_set_number / set_texture / reload 修改，
// 这些都会递增 revision，所以 revision 与 Shader 指针不变时选择、参数快照和默认实例值都仍然有效。
@(private)
Render3D_Prepared :: struct {
	revision: u64,
	shader: ^mat.Material_Shader,
	source: int,
	defaults: int, // r.defaults 中的起点：各所选 Pass 依次 slots 个无覆盖的实例值
}

// 记录时的 Shader 与槽数一并保存：之后 material_reload 换了 Shader 或参数组，已记录的快照仍按原布局绘制。
@(private)
Render3D_Source :: struct {
	material: ^mat.Material,
	shader: ^mat.Material_Shader,
	slots: int,
	selection: mat.Pass_Selection,
	snapshot, next: int,
	// 本次 submit 的选择，不改记录的完整 selection。
	selected: [sh.MAX_PASSES]int,
	count: int,
	transparent: bool,
}

// ------------------------------------------------------------------------------
// 生命周期
// ------------------------------------------------------------------------------

init :: proc(r: ^Render3D, library: ^mat.Material_Library) -> string {
	if library == nil || library.device == nil do return "Missing graphics device"
	r^ = {library = library}
	r.debug.thickness = DEBUG_DRAW_DEFAULT_THICKNESS
	r.debug.depth_test_enabled = true
	return ""
}

dispose :: proc(r: ^Render3D) {
	for &snapshot in r.snapshots do foster.MaterialDispose(&snapshot)
	delete(r.snapshots)
	delete(r.records)
	delete(r.sources)
	delete(r.source_heads)
	queue_dispose(&r.queue)
	delete(r.values)
	delete(r.prepared)
	delete(r.defaults)
	delete(r.batches)
	delete(r.upload)
	for &buffer in r.buffers do model_buffer_dispose(&buffer)
	debug_draw_dispose(&r.debug)
	r^ = {}
}

clear :: proc(r: ^Render3D) {
	builtin.clear(&r.records)
	builtin.clear(&r.sources)
	builtin.clear(&r.source_heads)
	r.snapshot_count = 0
	queue_clear(&r.queue)
	builtin.clear(&r.values)
	builtin.clear(&r.prepared)
	builtin.clear(&r.defaults)
	builtin.clear(&r.batches)
	debug_draw_clear(&r.debug)
}

// ------------------------------------------------------------------------------
// 记录入口与材质快照
// ------------------------------------------------------------------------------

model :: proc(r: ^Render3D, mesh: ^foster.Mesh, material: ^mat.Material,
	transform: world.Matrix4, bounds: ^dasset.Dasset_Bounds = nil,
	values: ^mat.Instance_Values = nil) -> mat.Draw_Error {
	item := Model_Item{transform, {1, 1, 1, 1}}
	return render3d_record(r, mesh, material, []Model_Item{item}, bounds, nil, values)
}

// items 和 values 都在调用内复制；nil values 沿用材质默认值。
models :: proc(r: ^Render3D, mesh: ^foster.Mesh, material: ^mat.Material,
	items: []Model_Item, bounds: ^dasset.Dasset_Bounds = nil,
	values: [][4]f32 = nil) -> mat.Draw_Error {
	return render3d_record(r, mesh, material, items, bounds, values, nil)
}

@(private)
render3d_validate :: proc(r: ^Render3D, mesh: ^foster.Mesh,
	m: ^mat.Material) -> mat.Draw_Error {
	if r.library == nil || r.library.device == nil do return .Missing_Device
	if m == nil || m.owner == nil || m.shader == nil do return .Missing_Material
	if m.owner.device != r.library.device do return .Device_Mismatch
	if mesh == nil do return .Missing_Mesh
	if mesh.GraphicsDevice != r.library.device do return .Device_Mismatch
	if mesh.VertexData.Format.Stride != dasset.DASSET_VERTEX_STRIDE_STATIC do return .Unsupported_Mesh
	if !sh.shader_is_material(m.shader.desc) do return .Not_Material_Shader
	return .None
}

@(private)
render3d_record :: proc(r: ^Render3D, mesh: ^foster.Mesh, m: ^mat.Material,
	items: []Model_Item, bounds: ^dasset.Dasset_Bounds, flat: [][4]f32,
	overrides: ^mat.Instance_Values) -> mat.Draw_Error {
	if error := render3d_validate(r, mesh, m); error != .None do return error
	prepared, error := render3d_prepared(r, m)
	if error != .None do return error
	source := &r.sources[prepared.source]
	slots, selection := source.slots, source.selection
	if flat != nil && len(flat) != len(items) * slots do return .Instance_Mismatch
	for item, item_index in items {
		record := Render3D_Record{mesh = mesh, source = prepared.source, item = item,
			values = len(r.values), count = 1}
		if bounds != nil {
			record.bounds, record.has_bounds = render3d_world_bounds(bounds^, item.world)
		}
		append(&r.records, record)
		if slots == 0 do continue
		if flat == nil && overrides == nil {
			append(&r.values, ..r.defaults[prepared.defaults:][:selection.count * slots])
			continue
		}
		input: mat.Instance_Values
		if flat != nil do input = mat.instance_values_from(flat[item_index*slots:(item_index+1)*slots])
		for i in 0..<selection.count {
			p := source.shader.desc.passes[selection.passes[i]]
			instance := mat.material_pass_instance(p, m.bindings[selection.bindings[i]], flat != nil ? &input : overrides)
			append(&r.values, ..instance.numbers[:slots])
		}
	}
	return .None
}

// 取材质的准备结果；revision 或 Shader 变了（含 reload）就重新选择 Pass、打包参数并查找快照来源。
// 实例覆盖只影响 [Instance] 字段，不进参数 uniform，因此同一准备结果对所有覆盖都适用。
@(private)
render3d_prepared :: proc(r: ^Render3D, m: ^mat.Material) -> (Render3D_Prepared, mat.Draw_Error) {
	if prepared, ok := r.prepared[m]; ok && prepared.revision == m.revision && prepared.shader == m.shader {
		return prepared, .None
	}
	slots := mat.instance_slot_count(m)
	if slots < 0 || slots > sh.MAX_INSTANCE_FIELDS do return {}, .Instance_Mismatch
	selection: mat.Pass_Selection
	if error := mat.material_select(m.shader.desc, m.bindings, .Model, "", nil, &selection);
		error != .None do return {}, error
	prepared := Render3D_Prepared{revision = m.revision, shader = m.shader, defaults = len(r.defaults)}
	uniforms: [sh.MAX_PASSES][]u8
	for i in 0..<selection.count {
		p := m.shader.desc.passes[selection.passes[i]]
		instance: mat.Instance_Values
		uniforms[i], instance = mat.material_pass_values(p, m.bindings[selection.bindings[i]], nil)
		append(&r.defaults, ..instance.numbers[:slots])
	}
	prepared.source = render3d_source(r, m, selection, uniforms[:selection.count])
	r.prepared[m] = prepared
	return prepared, .None
}

// 进阶：bounds 是整块实例的世界包围盒；不读回、重排或上传常驻实例。
buffer :: proc(r: ^Render3D, mesh: ^foster.Mesh, material: ^mat.Material,
	buf: ^Model_Buffer, count: int, bounds: ^dasset.Dasset_Bounds = nil) -> mat.Draw_Error {
	if error := render3d_validate(r, mesh, material); error != .None do return error
	if !material.shader.desc.instanced do return .Not_Instanced_Shader
	if buf == nil || buf.capacity <= 0 do return .Instance_Buffer_Required
	if buf.buffer.Base.GraphicsDevice != r.library.device do return .Device_Mismatch
	if buf.slots != mat.instance_slot_count(material) || count < 0 || count > buf.capacity do return .Instance_Mismatch
	prepared, error := render3d_prepared(r, material)
	if error != .None do return error
	if count == 0 do return .None
	record := Render3D_Record{mesh = mesh, source = prepared.source, buffer = buf, count = count,
		item = {world.MATRIX4_IDENTITY, {1, 1, 1, 1}}}
	if bounds != nil {
		record.bounds = bounds^
		record.has_bounds = true
	}
	append(&r.records, record)
	return .None
}

// 同一材质、相同 uniform 与采样绑定共用快照；实例数值不作为快照键。
// 哈希冲突再逐字段比较，不依赖指针所指的可变材质值。
@(private)
render3d_source :: proc(r: ^Render3D, m: ^mat.Material, selection: mat.Pass_Selection,
	uniforms: [][]u8) -> int {
	hash := u64(uintptr(m))
	for uniform in uniforms do for byte in uniform do hash = (hash ~ u64(byte)) * 1099511628211
	slot := m.shader.desc.uniforms == .Foster ? 0 : 1
	head := r.source_heads[hash] - 1
	for index := head; index >= 0; index = r.sources[index].next {
		source := &r.sources[index]
		if source.material != m || source.shader != m.shader || source.selection != selection do continue
		matches := true
		for i in 0..<selection.count {
			binding := m.bindings[selection.bindings[i]]
			snapshot := &r.snapshots[source.snapshot + i]
			current := snapshot.Fragment.UniformBuffers[slot][:]
			if len(current) != len(uniforms[i]) || mem.compare(current, uniforms[i]) != 0 ||
				snapshot.Vertex.Shader != binding.material.Vertex.Shader ||
				snapshot.Fragment.Shader != binding.material.Fragment.Shader {
				matches = false
				break
			}
			for sampler, j in binding.samplers {
				if sampler != snapshot.Fragment.Samplers[j] do matches = false
			}
		}
		if matches do return index
	}
	index := len(r.sources)
	append(&r.sources, Render3D_Source{material = m, shader = m.shader, slots = mat.instance_slot_count(m),
		selection = selection, snapshot = r.snapshot_count, next = head})
	r.source_heads[hash] = index + 1
	for i in 0..<selection.count {
		if r.snapshot_count == len(r.snapshots) {
			append(&r.snapshots, foster.Material{})
			foster.MaterialInitWithShaders(&r.snapshots[r.snapshot_count], nil, nil)
		}
		snapshot := &r.snapshots[r.snapshot_count]
		r.snapshot_count += 1
		binding := m.bindings[selection.bindings[i]]
		foster.MaterialStageSetShader(&snapshot.Vertex, binding.material.Vertex.Shader)
		foster.MaterialStageSetShader(&snapshot.Fragment, binding.material.Fragment.Shader)
		foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, uniforms[i], slot)
		snapshot.Fragment.Samplers = {}
		copy(snapshot.Fragment.Samplers[:], binding.samplers)
	}
	return index
}

// ------------------------------------------------------------------------------
// 包围盒与当前视图队列
// ------------------------------------------------------------------------------

@(private)
render3d_world_bounds :: proc(bounds: dasset.Dasset_Bounds,
	transform: world.Matrix4) -> (result: dasset.Dasset_Bounds, valid: bool) {
	for corner, i in aabb_corners(bounds) {
		point, ok := world.matrix4_transform_point(transform, corner)
		if !ok do return {}, false // 非仿射或无效盒保守保留
		for value in point do if math.is_nan(value) || math.is_inf(value) do return {}, false
		if i == 0 {
			result.min = point
			result.max = point
		} else {
			for axis in 0..<3 {
				result.min[axis] = min(result.min[axis], point[axis])
				result.max[axis] = max(result.max[axis], point[axis])
			}
		}
	}
	return result, true
}

// 每次从完整记录生成可见队列；Pass 是否存在在剔除之前判断。
@(private)
render3d_prepare :: proc(r: ^Render3D, view: View, pass_id: mat.Pass_Id) -> mat.Draw_Error {
	queue_clear(&r.queue)
	found := pass_id == "" || len(r.records) == 0
	for &source in r.sources {
		source.count = 0
		source.transparent = false
		shader := source.shader.desc
		for p in shader.passes do if p.id == pass_id do found = true
		for i in 0..<source.selection.count {
			p := shader.passes[source.selection.passes[i]]
			if pass_id != "" && p.id != pass_id do continue
			source.selected[source.count] = i
			source.count += 1
			source.transparent = source.transparent ||
				(p.state.blend != .Default && p.state.blend != .Opaque)
		}
	}
	if !found do return .Unknown_Pass
	frustum := world.frustum_from_view_projection(view.view_projection)
	view_matrix := view.view_matrix
	for record, i in r.records {
		source := &r.sources[record.source]
		if source.count == 0 do continue
		if record.has_bounds && !world.frustum_intersects_aabb(frustum,
			record.bounds.min, record.bounds.max) {
			continue
		}
		position := [3]f32{record.item.world.c0[3], record.item.world.c1[3], record.item.world.c2[3]}
		if record.has_bounds do position = (record.bounds.min + record.bounds.max) * 0.5
		p := world.matrix4_transform_vec4(view_matrix, {position[0], position[1], position[2], 1})
		depth := math.abs(p[3]) > 1e-8 ? -p[2] / p[3] : 0
		if math.is_nan(depth) || math.is_inf(depth) do depth = 0
		queue_submit(&r.queue, i, depth, source.transparent, record.source)
	}
	queue_sort(&r.queue, grouped = true)
	return .None
}

// ------------------------------------------------------------------------------
// 提交与实例上传
// ------------------------------------------------------------------------------

submit :: proc(r: ^Render3D, view: View, pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	r.draw_calls = 0
	r.instances = 0
	// 分阶段提交（指定 pass_id）默认不画调试线，避免多次提交重复叠加或画进阴影图。
	draw_debug := pass_id == ""
	if value, ok := view.draw_debug.?; ok do draw_debug = value
	if len(r.records) == 0 && (!draw_debug || len(r.debug.vertices) == 0) do return .None
	if r.library == nil || r.library.device == nil do return .Missing_Device
	if view.target.WidthInPixels <= 0 || view.target.HeightInPixels <= 0 do return .Invalid_Target
	// 零矩阵不是有效视矩阵；不悄悄当成单位矩阵，否则透明排序、调试线朝向与 CameraPosition 会无声地出错。
	if view.view_matrix == (world.Matrix4{}) do return .Missing_View_Matrix
	globals: [mat.VIEW_GLOBALS_SIZE]u8
	if !mat.view_globals_pack(&globals, view.globals) do return .View_Globals_Too_Large
	if error := render3d_prepare(r, view, pass_id); error != .None do return error
	// 完整预检后再发 Draw；错误保留所有记录。
	for item in r.queue.items {
		record := &r.records[item.payload]
		source := &r.sources[record.source]
		if error := render3d_validate(r, record.mesh, source.material); error != .None do return error
		if record.mesh.VertexData.Base.Resource == nil do return .Missing_Mesh
		if record.buffer != nil {
			buf := record.buffer
			if buf.buffer.Base.Resource == nil || buf.capacity < record.count do return .Instance_Buffer_Required
			if buf.buffer.Base.GraphicsDevice != r.library.device do return .Device_Mismatch
			if buf.slots != source.slots do return .Instance_Mismatch
		} else if source.shader.desc.instanced && !render3d_instance_buffer(r, source.slots) {
			return .Instance_Buffer_Required // 临时实例缓冲创建失败
		}
		for i in source.selected[:source.count] {
			snapshot := &r.snapshots[source.snapshot + i]
			if snapshot.Vertex.Shader.Resource == nil || snapshot.Fragment.Shader.Resource == nil do return .Invalid_Binding
			for sampler in snapshot.Fragment.Samplers {
				if sampler.Texture != nil && sampler.Texture.Resource == nil do return .Invalid_Binding
			}
		}
	}
	if draw_debug && len(r.debug.vertices) > 0 && !debug_draw_prepare(&r.debug, r.library.device) {
		return .Invalid_Binding
	}
	// 发 Draw 之前一次上传全部自动实例化数据（每种槽数一个缓冲），绘制期间不再因上传打断渲染通道。
	counts := render3d_plan(r)
	bases := render3d_pack(r, counts)
	for count, slots in counts {
		if count == 0 do continue
		buf := &r.buffers[slots] // 预检阶段已创建
		if buf.capacity < count {
			buf.capacity = max(count, buf.capacity * 2)
			foster.VertexBufferReserve(&buf.buffer, buf.capacity)
		}
		foster.VertexBufferUpload(&buf.buffer, &r.upload[bases[slots]], count)
	}
	camera := camera_position(view.view_matrix)
	for batch in r.batches {
		record := &r.records[r.queue.items[batch.start].payload]
		source := &r.sources[record.source]
		n := batch.end - batch.start
		for pass, k in source.selected[:source.count] {
			buf, count, first := record.buffer, record.count, 0
			if buf == nil && source.shader.desc.instanced {
				buf, count, first = &r.buffers[source.slots], n, batch.first + k*n
			}
			render3d_draw(r, record, source, pass, view, camera, globals[:], buf, count, first)
		}
	}
	if draw_debug && len(r.debug.vertices) > 0 do debug_draw_submit(&r.debug, view)
	return .None
}

// 只合并排序后相邻项；透明多 Pass 保持每对象的完整 Pass 顺序。
@(private)
render3d_batch_end :: proc(r: ^Render3D, start: int) -> int {
	a := r.records[r.queue.items[start].payload]
	source := &r.sources[a.source]
	if a.buffer != nil || !source.shader.desc.instanced ||
		(source.transparent && source.count > 1) {
		return start + 1
	}
	end := start + 1
	for end < len(r.queue.items) {
		b := r.records[r.queue.items[end].payload]
		if b.mesh != a.mesh || b.source != a.source || b.buffer != nil do break
		end += 1
	}
	return end
}

// 把排序后的队列切成批次；自动实例化批次按槽数排位，返回各槽数需要的实例总数（每个所选 Pass 一份）。
// 只读记录与队列，不碰 GPU。
@(private)
render3d_plan :: proc(r: ^Render3D) -> (counts: [sh.MAX_INSTANCE_FIELDS + 1]int) {
	builtin.clear(&r.batches)
	for start := 0; start < len(r.queue.items); {
		end := render3d_batch_end(r, start)
		batch := Render3D_Batch{start = start, end = end}
		record := &r.records[r.queue.items[start].payload]
		source := &r.sources[record.source]
		if record.buffer == nil && source.shader.desc.instanced {
			batch.first = counts[source.slots]
			counts[source.slots] += (end - start) * source.count
		}
		append(&r.batches, batch)
		start = end
	}
	return
}

// 按槽数分段写入 r.upload：每段对应一个临时缓冲，段内按 plan 的 first 排列，返回各段字节起点。
@(private)
render3d_pack :: proc(r: ^Render3D, counts: [sh.MAX_INSTANCE_FIELDS + 1]int) -> (bases: [sh.MAX_INSTANCE_FIELDS + 1]int) {
	total := 0
	for count, slots in counts {
		bases[slots] = total
		total += count * model_stride(slots)
	}
	resize(&r.upload, total)
	for batch in r.batches {
		record := &r.records[r.queue.items[batch.start].payload]
		source := &r.sources[record.source]
		if record.buffer != nil || !source.shader.desc.instanced do continue
		slots := source.slots
		stride := model_stride(slots)
		n := batch.end - batch.start
		for pass, k in source.selected[:source.count] {
			for entry, j in r.queue.items[batch.start:batch.end] {
				item := &r.records[entry.payload]
				at := bases[slots] + (batch.first + k*n + j) * stride
				mem.copy(&r.upload[at], &item.item, size_of(Model_Item))
				if slots > 0 {
					mem.copy(&r.upload[at + MODEL_BASE_BYTES], &r.values[item.values + pass * slots], slots * 16)
				}
			}
		}
	}
	return
}

// 自动实例化用的临时缓冲，按 [Instance] 字段数各一个，首次需要时创建。
// submit 在预检阶段调用，保证发 Draw 之前缓冲已就绪。
@(private)
render3d_instance_buffer :: proc(r: ^Render3D, slots: int) -> bool {
	if slots < 0 || slots > sh.MAX_INSTANCE_FIELDS do return false
	buf := &r.buffers[slots]
	if buf.capacity == 0 do model_buffer_create(buf, r.library.device, slots, 64, "render3d instances")
	return buf.capacity > 0
}

// first 是实例缓冲中的起始实例（自动实例化的批次偏移；常驻缓冲为 0）。
// globals 是已补零到 VIEW_GLOBALS_SIZE 的视图块，每次 submit 打包一次。
@(private)
render3d_draw :: proc(r: ^Render3D, record: ^Render3D_Record, source: ^Render3D_Source,
	i: int, view: View, camera: [4]f32, globals: []u8, buf: ^Model_Buffer, count, first: int) {
	snapshot := &r.snapshots[source.snapshot + i]
	matrices: [MATERIAL_VERTEX_BLOCK_SIZE]u8
	frame: [MATERIAL_FRAME_BLOCK_SIZE]u8
	if buf != nil {
		pack_material_blocks(matrices[:], frame[:], view.view_projection, world.MATRIX4_IDENTITY,
			view, camera, {}, {1, 1, 1, 1})
	} else {
		pack_material_blocks(matrices[:], frame[:], world.matrix4_multiply(record.item.world, view.view_projection),
			record.item.world, view, camera, {}, record.item.tint)
	}
	foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, matrices[:])
	if source.shader.desc.uniforms == .Olib {
		foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, frame[:])
		foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, globals, mat.MODEL_VIEW_VERTEX_SLOT)
		foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, globals, mat.MODEL_VIEW_FRAGMENT_SLOT)
	}
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, view.target, record.mesh, snapshot)
	defer foster.DrawCommandDispose(&command)
	shifted: foster.VertexBuffer
	if buf != nil {
		model_instanced_command(&command, record.mesh, buf, &shifted)
		command.InstanceCount = count
		command.InstanceOffset = first
	}
	defer if buf != nil do foster.VertexFormatDispose(&shifted.Format)
	command.CullMode = .Back
	command.BlendMode = foster.BlendModeDisabled
	command.DepthTestEnabled = true
	command.DepthWriteEnabled = true
	command.DepthCompare = .Less
	p := source.shader.desc.passes[source.selection.passes[i]]
	mat.pass_state_apply(&command, p.state)
	foster.GraphicsDeviceDraw(r.library.device, &command)
	r.draw_calls += 1
	r.instances += count
}
