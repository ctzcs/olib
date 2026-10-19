package rendering3d

// 记录拥有 CPU 数据与材质绑定快照；GPU 资源借用至 clear/dispose。
// submit 只重建当前视图的队列，不消耗记录，也不清理目标附件。
import "core:math"
import "base:builtin"
import "core:mem"
import dasset "olib:core/dasset"
import foster "olib:foster"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

View :: struct {
	target: foster.DrawableTarget,
	view_projection: world.Matrix4,
	view_matrix: world.Matrix4, // 零值按单位矩阵处理；排序与调试线朝向使用它
	draw_debug: Maybe(bool), // 未指定为 true；显式 false 可用于阴影阶段
	time, delta_time: f32,
	frame: u64,
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
}

@(private)
Render3D_Record :: struct {
	mesh: ^foster.Mesh,
	source: int,
	item: Model_Item,
	bounds: dasset.Dasset_Bounds, // 已转换到世界空间
	has_bounds: bool,
}

@(private)
Render3D_Source :: struct {
	material: ^mat.Material,
	selection: mat.Pass_Selection,
	snapshot, next: int,
	// 本次 submit 的选择，不改记录的完整 selection。
	selected: [mat.MAX_PASSES]int,
	count: int,
	transparent: bool,
}

init :: proc(r: ^Render3D, library: ^mat.Material_Library) -> string {
	if library == nil || library.device == nil do return "Missing graphics device"
	r^ = {library = library}
	return ""
}

dispose :: proc(r: ^Render3D) {
	for &snapshot in r.snapshots do foster.MaterialDispose(&snapshot)
	delete(r.snapshots)
	delete(r.records)
	delete(r.sources)
	delete(r.source_heads)
	queue_dispose(&r.queue)
	r^ = {}
}

clear :: proc(r: ^Render3D) {
	builtin.clear(&r.records)
	builtin.clear(&r.sources)
	builtin.clear(&r.source_heads)
	r.snapshot_count = 0
	queue_clear(&r.queue)
}

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
	if m == nil || m.owner == nil || m.effect == nil do return .Missing_Material
	if m.owner.device != r.library.device do return .Device_Mismatch
	if mesh == nil do return .Missing_Mesh
	if mesh.GraphicsDevice != r.library.device do return .Device_Mismatch
	if mesh.VertexData.Format.Stride != dasset.DASSET_VERTEX_STRIDE_STATIC do return .Unsupported_Mesh
	if !mat.effect_is_material(m.effect.desc) do return .Not_Material_Effect
	return .None
}

@(private)
render3d_record :: proc(r: ^Render3D, mesh: ^foster.Mesh, m: ^mat.Material,
	items: []Model_Item, bounds: ^dasset.Dasset_Bounds, flat: [][4]f32,
	overrides: ^mat.Instance_Values) -> mat.Draw_Error {
	if error := render3d_validate(r, mesh, m); error != .None do return error
	if m.effect.desc.instanced do return .Instance_Buffer_Required // 下一阶段接入自动实例化
	if flat != nil && len(flat) != 0 do return .Instance_Mismatch
	selection: mat.Pass_Selection
	if error := mat.material_select(m.effect.desc, m.bindings, {kind = .Model}, &selection);
		error != .None do return error
	if len(items) == 0 do return .None
	uniforms: [mat.MAX_PASSES][]u8
	for i in 0..<selection.count {
		p := m.effect.desc.passes[selection.passes[i]]
		uniforms[i], _ = mat.material_pass_values(p, m.bindings[selection.bindings[i]], overrides)
	}
	source := render3d_source(r, m, selection, uniforms[:selection.count])
	for item in items {
		record := Render3D_Record{mesh = mesh, source = source, item = item}
		if bounds != nil {
			record.bounds, record.has_bounds = render3d_world_bounds(bounds^, item.world)
		}
		append(&r.records, record)
	}
	return .None
}

// 同一材质、相同 uniform 与采样绑定共用快照；实例数值不作为快照键。
// 哈希冲突再逐字段比较，不依赖指针所指的可变材质值。
@(private)
render3d_source :: proc(r: ^Render3D, m: ^mat.Material, selection: mat.Pass_Selection,
	uniforms: [][]u8) -> int {
	hash := u64(uintptr(m))
	for uniform in uniforms do for byte in uniform do hash = (hash ~ u64(byte)) * 1099511628211
	slot := m.effect.desc.uniforms == .Foster ? 0 : 1
	head := r.source_heads[hash] - 1
	for index := head; index >= 0; index = r.sources[index].next {
		source := &r.sources[index]
		if source.material != m || source.selection != selection do continue
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
	append(&r.sources, Render3D_Source{material = m, selection = selection,
		snapshot = r.snapshot_count, next = head})
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

@(private)
render3d_view_matrix :: proc(view: View) -> world.Matrix4 {
	return view.view_matrix == (world.Matrix4{}) ? world.MATRIX4_IDENTITY : view.view_matrix
}

// 每次从完整记录生成可见队列；Pass 是否存在在剔除之前判断。
@(private)
render3d_prepare :: proc(r: ^Render3D, view: View, pass_id: mat.Pass_Id) -> mat.Draw_Error {
	queue_clear(&r.queue)
	found := pass_id == "" || len(r.records) == 0
	for &source in r.sources {
		source.count = 0
		source.transparent = false
		effect := source.material.effect.desc
		for p in effect.passes do if p.id == pass_id do found = true
		for i in 0..<source.selection.count {
			p := effect.passes[source.selection.passes[i]]
			if pass_id != "" && p.id != pass_id do continue
			source.selected[source.count] = i
			source.count += 1
			source.transparent = source.transparent ||
				(p.state.blend != .Default && p.state.blend != .Opaque)
		}
	}
	if !found do return .Unknown_Pass
	frustum := world.frustum_from_view_projection(view.view_projection)
	view_matrix := render3d_view_matrix(view)
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

submit :: proc(r: ^Render3D, view: View, pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	r.draw_calls = 0
	r.instances = 0
	if len(r.records) == 0 do return .None
	if r.library == nil || r.library.device == nil do return .Missing_Device
	if view.target.WidthInPixels <= 0 || view.target.HeightInPixels <= 0 do return .Invalid_Target
	if error := render3d_prepare(r, view, pass_id); error != .None do return error
	// 完整预检后再发 Draw；错误保留所有记录。
	for item in r.queue.items {
		record := &r.records[item.payload]
		source := &r.sources[record.source]
		if error := render3d_validate(r, record.mesh, source.material); error != .None do return error
		for i in source.selected[:source.count] {
			snapshot := &r.snapshots[source.snapshot + i]
			if snapshot.Vertex.Shader.Resource == nil || snapshot.Fragment.Shader.Resource == nil do return .Invalid_Binding
			for sampler in snapshot.Fragment.Samplers {
				if sampler.Texture != nil && sampler.Texture.Resource == nil do return .Invalid_Binding
			}
		}
	}
	for item in r.queue.items {
		record := &r.records[item.payload]
		source := &r.sources[record.source]
		for i in source.selected[:source.count] do render3d_draw(r, record, source, i, view)
	}
	return .None
}

@(private)
render3d_draw :: proc(r: ^Render3D, record: ^Render3D_Record, source: ^Render3D_Source,
	i: int, view: View) {
	snapshot := &r.snapshots[source.snapshot + i]
	matrices: [VERTEX_MATRIX_BLOCK_SIZE]u8
	pack_vertex_matrix_block(matrices[:], world.matrix4_multiply(record.item.world,
		view.view_projection), record.item.world)
	foster.MaterialStageSetUniformBuffer(&snapshot.Vertex, matrices[:])
	if source.material.effect.desc.uniforms == .Olib {
		frame: [48]u8
		mat.std140_write_vec4(frame[:], 0, {view.time, view.delta_time, f32(view.frame), 0})
		mat.std140_write_vec4(frame[:], 16, {0, 0, f32(view.target.WidthInPixels), f32(view.target.HeightInPixels)})
		mat.std140_write_vec4(frame[:], 32, record.item.tint)
		foster.MaterialStageSetUniformBuffer(&snapshot.Fragment, frame[:])
	}
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, view.target, record.mesh, snapshot)
	defer foster.DrawCommandDispose(&command)
	command.CullMode = .Back
	command.BlendMode = foster.BlendModeDisabled
	command.DepthTestEnabled = true
	command.DepthWriteEnabled = true
	command.DepthCompare = .Less
	p := source.material.effect.desc.passes[source.selection.passes[i]]
	mat.pass_state_apply(&command, p.state)
	foster.GraphicsDeviceDraw(r.library.device, &command)
	r.draw_calls += 1
	r.instances += 1
}
