package material

// 多 Pass 的纯数据声明；不依赖编辑器或 GPU。分区：声明 / 拓扑校验 / 所有权。
import "core:fmt"
import "core:math"
import "core:strings"

Pass_Draw :: enum { Fullscreen, Preview_Model }
Pass_Frame :: enum { Current, Previous }
Target_Format :: enum { Color, Float16, Float32 }

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
	// 同一参数组可重复使用；如横/纵模糊分别覆盖 direction。
	values: []Pass_Value,
	target: Target_Desc,
}

Effect_Desc :: struct {
	name: string,
	output: Target_Ref,
	label: string,
	passes: []Pass_Desc,
	preview: string, // 效果工作区：2d / 3d；空值兼容旧声明的模型 Pass 推断。
}

// 拓扑顺序归调用方；错误文本借用至 temp_allocator 重置。Previous 不参与当前帧排序。
effect_order :: proc(e: Effect_Desc, schemas: []Schema) -> (order: []int, error: string) {
	if e.preview != "" && e.preview != "2d" && e.preview != "3d" do return nil, "Effect Preview must be 2d or 3d"
	if e.name == "" || len(e.passes) == 0 || len(e.passes) > 32 {
		return nil, "Effect requires a name and 1..32 passes"
	}
	output_found := false
	for p, i in e.passes {
		if p.id == "" || p.output == "" do return nil, "Pass id/output cannot be empty"
		for prior in e.passes[:i] {
			if p.id == prior.id || p.output == prior.output {
				return nil, "Pass IDs and output targets must be unique"
			}
		}
		output_found = output_found || p.output == e.output
		schema: ^Schema
		for &candidate in schemas {
			if candidate.name == string(p.params) do schema = &candidate
		}
		if schema == nil do return nil, fmt.tprintf("%s: unknown parameter group %s", p.id, p.params)
		if e.preview == "2d" && p.draw == .Preview_Model && schema.preview == "3d" {
			return nil, "2d effect cannot contain a 3d model pass"
		}
		if p.draw == .Fullscreen && schema.preview != "2d" {
			return nil, fmt.tprintf("%s: Fullscreen requires a 2d vertex interface", p.id)
		}
		t := p.target
		if t.width < 0 || t.height < 0 || (t.width == 0) != (t.height == 0) ||
			t.width > 8192 || t.height > 8192 || math.is_nan(t.scale) || math.is_inf(t.scale) ||
			t.scale < 0 || t.scale > 4 || (t.samples != 0 && t.samples != 1 && t.samples != 4) {
			return nil, fmt.tprintf("%s: invalid target size/scale/samples", p.id)
		}
		for v in t.clear {
			if math.is_nan(v) || math.is_inf(v) || v < 0 || v > 1 {
				return nil, "Target clear color must be finite and within 0..1"
			}
		}
		for input, j in p.inputs {
			for prior in p.inputs[:j] {
				if prior.field == input.field do return nil, "Duplicate pass texture binding"
			}
			found := false
			for f in schema.fields do found = found || (f.id == string(input.field) && f.kind == .Texture)
			if !found do return nil, fmt.tprintf("%s: no Texture field %s", p.id, input.field)
			found = false
			for producer in e.passes do found = found || producer.output == input.target
			if !found do return nil, fmt.tprintf("%s: unknown target %s", p.id, input.target)
		}
		for value, j in p.values {
			for prior in p.values[:j] {
				if prior.field == value.field do return nil, "Duplicate pass value override"
			}
			found := false
			for f in schema.fields {
				if f.id != string(value.field) || f.kind == .Texture do continue
				found = true
				for c in 0..<components(f.kind) {
					x := value.number[c]
					if math.is_nan(x) || math.is_inf(x) || x < f.minimum || x > f.maximum {
						return nil, fmt.tprintf("%s: override outside field range", p.id)
					}
				}
			}
			if !found do return nil, fmt.tprintf("%s: no numeric field %s", p.id, value.field)
		}
	}
	if !output_found do return nil, "Effect output must name a pass target"
	result := make([]int, len(e.passes))
	done: [32]bool
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

effect_clone :: proc(e: Effect_Desc) -> Effect_Desc {
	r := Effect_Desc{name = strings.clone(e.name), output = Target_Ref(strings.clone(string(e.output))), label = strings.clone(e.label),
		preview = strings.clone(e.preview),
		passes = make([]Pass_Desc, len(e.passes))}
	for p, i in e.passes {
		r.passes[i] = p
		q := &r.passes[i]
		q.id = Pass_Id(strings.clone(string(p.id)))
		q.label = strings.clone(p.label)
		q.params = Params_Ref(strings.clone(string(p.params)))
		q.output = Target_Ref(strings.clone(string(p.output)))
		q.inputs = make([]Pass_Input, len(p.inputs))
		for input, j in p.inputs {
			q.inputs[j] = {Field_Ref(strings.clone(string(input.field))), Target_Ref(strings.clone(string(input.target))), input.frame}
		}
		q.values = make([]Pass_Value, len(p.values))
		for value, j in p.values do q.values[j] = {Field_Ref(strings.clone(string(value.field))), value.number}
	}
	return r
}

effect_dispose :: proc(e: ^Effect_Desc) {
	delete(e.name)
	delete(e.label)
	delete(e.preview)
	delete(string(e.output))
	for p in e.passes {
		delete(string(p.id))
		delete(p.label)
		delete(string(p.params))
		delete(string(p.output))
		for input in p.inputs {
			delete(string(input.field))
			delete(string(input.target))
		}
		for value in p.values do delete(string(value.field))
		delete(p.inputs)
		delete(p.values)
	}
	delete(e.passes)
	e^ = {}
}
