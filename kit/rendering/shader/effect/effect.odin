package effect

// 效果与多 Pass 的纯数据声明；不依赖编辑器或 GPU。分区：声明 / 校验与拓扑排序 / 所有权。
import "core:fmt"
import "core:math"

// 单个 Effect 的 Pass 数与目标尺寸上限；声明校验和绘制选择共用。
MAX_PASSES :: 32
MAX_TARGET_SIZE :: 8192

Pass_Draw :: enum { Fullscreen, Preview_Model, Model, Sprite }
Pass_Frame :: enum { Current, Previous }
Target_Format :: enum { Color, Float16, Float32 }

// Default 保留调用方状态；Model 默认不透明、背面剔除、Less 深度读写。
Pass_Cull :: enum { Default, None, Front, Back }
Pass_Blend :: enum { Default, Opaque, Alpha, Additive, Premultiplied }
// Off 关闭深度测试；Always 开启测试但总是通过。新值只追加在末尾：编译清单按整数保存枚举。
Pass_Depth :: enum { Default, Off, Less, Less_Equal, Equal, Always, Greater, Greater_Equal, Not_Equal, Never }
Pass_Write :: enum { Default, On, Off }
Pass_State :: struct {
	cull: Pass_Cull,
	blend: Pass_Blend,
	depth: Pass_Depth,
	depth_write: Pass_Write,
}

Target_Desc :: struct {
	// width/height 同时为 0 时跟随预览尺寸；scale=0 表示 1。
	width, height: int,
	scale: f32,
	format: Target_Format,
	depth: bool,
	// 0 为自动：模型 4x，全屏 1x；也可显式指定 1 或 4。
	samples: int,
	clear: [4]f32,
}

Pass_Input :: struct {
	field: Field_Ref, // 使用参数的稳定 ID。
	target: Target_Ref,
	frame: Pass_Frame,
}

Pass_Value :: struct {
	field: Field_Ref,
	number: [4]f32,
}

Pass_Desc :: struct {
	id: Pass_Id,
	params: Params_Ref,
	output: Target_Ref,
	label: string,
	disabled: bool, // 缺省启用；运行时 checkbox 不改写源声明。
	draw: Pass_Draw,
	inputs: []Pass_Input,
	// Sprite 当前帧绑定到此 Texture 字段；空值表示不使用帧贴图，不占用隐式槽位。
	sprite_texture: Field_Ref,
	// 同一参数组可重复使用；如横/纵模糊分别覆盖 direction。
	values: []Pass_Value,
	target: Target_Desc,
	state: Pass_State,
}

// Model 是可挂在网格上的有序材质 Pass，共享外部颜色/深度目标。
// 图像效果仍使用 Preview_Model / Fullscreen 和各自独立的图目标。
effect_is_model :: proc(e: Effect_Desc) -> bool {
	return len(e.passes) > 0 && e.passes[0].draw == .Model
}

effect_is_sprite :: proc(e: Effect_Desc) -> bool {
	return len(e.passes) > 0 && e.passes[0].draw == .Sprite
}

effect_is_material :: proc(e: Effect_Desc) -> bool {
	return effect_is_model(e) || effect_is_sprite(e)
}

Effect_Desc :: struct {
	name: string,
	output: Target_Ref,
	label: string,
	passes: []Pass_Desc,
	preview: string, // 效果工作区：2d / 3d；空值兼容旧声明的模型 Pass 推断。
	// 每个绘制对象的 tint 与 [Instance] 字段随顶点传入（见 hlsl 的 OlibInstance），不同取值可合批。
	// Sprite 与 Model 效果支持；模型需要用调用方持有的实例缓冲绘制（见 3d 包的 Model_Buffer）。
	instanced: bool,
	// uniform 布局：Olib 为 .oshader 约定（顶点 b0 投影/矩阵块，片元 b0 Clock/Pointer/Tint、b1 参数）；
	// Foster 为借用 foster 默认 Shader 的内置效果（顶点 b0 矩阵，片元 b0 直接放参数，没有帧块）。
	uniforms: Uniform_Layout,
}

Uniform_Layout :: enum { Olib, Foster }

// 效果使用的 per-instance 接口种类，供 hlsl 与绘制路径选择。
effect_instancing :: proc(e: Effect_Desc) -> Instancing {
	switch {
	case !e.instanced: return .None
	case effect_is_model(e): return .Model
	}
	return .Sprite
}

// ------------------------------------------------------------------------------
// 校验与拓扑排序 —— effect_order = effect_validate + effect_sort
// ------------------------------------------------------------------------------

// 拓扑顺序归调用方；错误文本借用至 temp_allocator 重置。Previous 不参与当前帧排序。
effect_order :: proc(e: Effect_Desc, schemas: []Schema) -> (order: []int, error: string) {
	if reason := effect_validate(e, schemas); reason != "" do return nil, reason
	return effect_sort(e)
}

// 只检查声明本身是否自洽，不分配结果。错误文本借用至 temp_allocator 重置。
effect_validate :: proc(e: Effect_Desc, schemas: []Schema) -> string {
	if e.preview != "" && e.preview != "2d" && e.preview != "3d" do return "Effect Preview must be 2d or 3d"
	if e.name == "" || len(e.passes) == 0 || len(e.passes) > MAX_PASSES {
		return "Effect requires a name and 1..32 passes"
	}
	output_found := false
	for p, i in e.passes {
		if reason := pass_validate(e, i, schemas); reason != "" do return reason
		output_found = output_found || p.output == e.output
	}
	if !output_found do return "Effect output must name a pass target"
	return ""
}

// 单个 Pass：种类/状态、与效果其余部分的关系、参数组、目标，再检查输入和覆盖值。
@(private)
pass_validate :: proc(e: Effect_Desc, index: int, schemas: []Schema) -> string {
	p := e.passes[index]
	model := effect_is_model(e)
	sprite := effect_is_sprite(e)
	object := model || sprite
	if p.draw < .Fullscreen || p.draw > .Sprite do return "Invalid pass draw kind"
	if (p.draw == .Model) != model || (p.draw == .Sprite) != sprite {
		return "Model, Sprite and image graph passes cannot mix"
	}
	if p.state.cull < .Default || p.state.cull > .Back ||
		p.state.blend < .Default || p.state.blend > .Premultiplied ||
		p.state.depth < .Default || p.state.depth > .Never ||
		p.state.depth_write < .Default || p.state.depth_write > .Off {
		return "Invalid pass render state"
	}
	if object && (p.output != e.output || len(p.inputs) != 0 || p.target != e.passes[0].target) {
		return "Material passes must share one target description and cannot sample graph targets"
	}
	if p.id == "" || p.output == "" do return "Pass id/output cannot be empty"
	for prior in e.passes[:index] {
		if p.id == prior.id || (!object && p.output == prior.output) {
			return "Pass IDs and output targets must be unique"
		}
	}
	schema: ^Schema
	for &candidate in schemas {
		if candidate.name == string(p.params) do schema = &candidate
	}
	if schema == nil do return fmt.tprintf("%s: unknown parameter group %s", p.id, p.params)
	if model && (schema.preview != "3d" || e.preview == "2d") do return "Model material requires 3d schemas and preview"
	if sprite && (schema.preview != "2d" || e.preview == "3d") {
		return "Sprite material requires 2d schemas and preview"
	}
	if e.instanced && !object do return "Instanced effects require Sprite or Model passes"
	if instance_count(schema^) > 0 && !e.instanced do return "Instance fields require an Instanced effect"
	if instance_count(schema^) > MAX_INSTANCE_FIELDS {
		return fmt.tprintf("%s: more than %d Instance fields", p.id, MAX_INSTANCE_FIELDS)
	}
	for f in schema.fields {
		if f.instance && f.kind == .Texture do return fmt.tprintf("%s: Texture cannot be Instance", f.id)
	}
	if p.sprite_texture != "" {
		field := field_index(schema^, string(p.sprite_texture))
		if !sprite || field < 0 || schema.fields[field].kind != .Texture {
			return "sprite_texture requires a Sprite pass Texture field"
		}
	}
	if e.preview == "2d" && p.draw == .Preview_Model && schema.preview == "3d" {
		return "2d effect cannot contain a 3d model pass"
	}
	if p.draw == .Fullscreen && schema.preview != "2d" {
		return fmt.tprintf("%s: Fullscreen requires a 2d vertex interface", p.id)
	}
	if reason := target_validate(p); reason != "" do return reason
	if reason := pass_inputs_validate(e, p, schema^); reason != "" do return reason
	return pass_values_validate(p, schema^)
}

@(private)
target_validate :: proc(p: Pass_Desc) -> string {
	t := p.target
	if t.width < 0 || t.height < 0 || (t.width == 0) != (t.height == 0) ||
		t.width > MAX_TARGET_SIZE || t.height > MAX_TARGET_SIZE || math.is_nan(t.scale) || math.is_inf(t.scale) ||
		t.scale < 0 || t.scale > 4 || (t.samples != 0 && t.samples != 1 && t.samples != 4) {
		return fmt.tprintf("%s: invalid target size/scale/samples", p.id)
	}
	for v in t.clear {
		if math.is_nan(v) || math.is_inf(v) || v < 0 || v > 1 {
			return "Target clear color must be finite and within 0..1"
		}
	}
	return ""
}

// 输入必须是本 Pass 参数组里的 Texture 字段，且目标由某个 Pass 产出。
@(private)
pass_inputs_validate :: proc(e: Effect_Desc, p: Pass_Desc, schema: Schema) -> string {
	for input, j in p.inputs {
		for prior in p.inputs[:j] {
			if prior.field == input.field do return "Duplicate pass texture binding"
		}
		found := false
		for f in schema.fields do found = found || (f.id == string(input.field) && f.kind == .Texture)
		if !found do return fmt.tprintf("%s: no Texture field %s", p.id, input.field)
		found = false
		for producer in e.passes do found = found || producer.output == input.target
		if !found do return fmt.tprintf("%s: unknown target %s", p.id, input.target)
	}
	return ""
}

// 固定覆盖值必须指向本参数组的数值字段，且落在字段范围内。
@(private)
pass_values_validate :: proc(p: Pass_Desc, schema: Schema) -> string {
	for value, j in p.values {
		for prior in p.values[:j] {
			if prior.field == value.field do return "Duplicate pass value override"
		}
		found := false
		for f in schema.fields {
			if f.id != string(value.field) || f.kind == .Texture do continue
			found = true
			for c in 0..<components(f.kind) {
				x := value.number[c]
				if math.is_nan(x) || math.is_inf(x) || x < f.minimum || x > f.maximum {
					return fmt.tprintf("%s: override outside field range", p.id)
				}
			}
		}
		if !found do return fmt.tprintf("%s: no numeric field %s", p.id, value.field)
	}
	return ""
}

// 每轮选第一个所有当前帧输入都已产出的 Pass；Previous 输入不参与依赖。
// 结果由调用方持有；已校验的声明里出现无法排序的 Pass 即为当前帧环。
effect_sort :: proc(e: Effect_Desc) -> (order: []int, error: string) {
	result := make([]int, len(e.passes))
	done: [MAX_PASSES]bool
	for n in 0..<len(e.passes) {
		chosen := -1
		for p, i in e.passes {
			if done[i] do continue
			ready := true
			for input in p.inputs {
				if input.frame == .Previous do continue
				for producer, j in e.passes {
					if producer.output == input.target && !done[j] do ready = false
				}
			}
			if ready {
				chosen = i
				break
			}
		}
		if chosen < 0 {
			delete(result)
			return nil, "Current-frame pass cycle; use Previous for feedback"
		}
		result[n] = chosen
		done[chosen] = true
	}
	return result, ""
}

// ------------------------------------------------------------------------------
// 所有权 —— clone / dispose 深复制与释放全部嵌套字符串和切片
// ------------------------------------------------------------------------------

effect_clone :: proc(e: Effect_Desc) -> Effect_Desc {
	r := Effect_Desc{
		name = clone_text(e.name), output = clone_text(e.output), label = clone_text(e.label),
		preview = clone_text(e.preview), passes = make([]Pass_Desc, len(e.passes)),
		instanced = e.instanced, uniforms = e.uniforms,
	}
	for p, i in e.passes {
		q := &r.passes[i]
		q^ = p
		q.id = clone_text(p.id)
		q.label = clone_text(p.label)
		q.sprite_texture = clone_text(p.sprite_texture)
		q.params = clone_text(p.params)
		q.output = clone_text(p.output)
		q.inputs = make([]Pass_Input, len(p.inputs))
		for input, j in p.inputs {
			q.inputs[j] = {clone_text(input.field), clone_text(input.target), input.frame}
		}
		q.values = make([]Pass_Value, len(p.values))
		for value, j in p.values do q.values[j] = {clone_text(value.field), value.number}
	}
	return r
}

effect_dispose :: proc(e: ^Effect_Desc) {
	delete_text(e.name)
	delete_text(e.label)
	delete_text(e.preview)
	delete_text(e.output)
	for p in e.passes {
		delete_text(p.id)
		delete_text(p.label)
		delete_text(p.sprite_texture)
		delete_text(p.params)
		delete_text(p.output)
		for input in p.inputs {
			delete_text(input.field)
			delete_text(input.target)
		}
		for value in p.values do delete_text(value.field)
		delete(p.inputs)
		delete(p.values)
	}
	delete(e.passes)
	e^ = {}
}
