package ui

import "core:math"

import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   视觉属性 —— 子树注册与 Tween 插值
//   布局快照 —— 父子矩阵合成与裁剪
//   输入 —— 上一帧显示位置的逆变换
//   发射 —— 预乘颜色与最终像素矩阵

// ------------------------------------------------------------------------------
// 视觉属性 —— 不改变布局占位；零值不可见，请从 UI_VISUAL_DEFAULT 开始。
// ------------------------------------------------------------------------------

UI_Visual :: struct {
	offset: foster.Vec2,
	scale: foster.Vec2,
	rotation: f32, // 弧度；屏幕坐标中正值顺时针。
	pivot: foster.Vec2, // 相对布局矩形的归一化支点，允许在 0..1 之外。
	opacity: f32,
}

UI_VISUAL_DEFAULT :: UI_Visual{scale = {1, 1}, pivot = {0.5, 0.5}, opacity = 1}

// 每帧 begin/end 之间按稳定 ID 注册；同 ID 最后一次注册生效。
// 子树继承矩阵和透明度，浮动元素按 Clay 的 attachment parent 继承。
// 不持有 visual 指针；Tween 绑定的状态由调用方保持地址稳定并负责释放。
ui_set_visual :: proc(ctx: ^UI_Context, id: string, visual: UI_Visual) {
	ctx.visuals[clay.ID(id).id] = visual
}

// 可直接传给 core/tween.make_ex；不限制过冲，透明度在绘制时钳制。
ui_visual_lerp :: proc "contextless" (a, b: UI_Visual, t: f32) -> UI_Visual {
	return {
		offset = a.offset + (b.offset - a.offset) * t,
		scale = a.scale + (b.scale - a.scale) * t,
		rotation = a.rotation + (b.rotation - a.rotation) * t,
		pivot = a.pivot + (b.pivot - a.pivot) * t,
		opacity = a.opacity + (b.opacity - a.opacity) * t,
	}
}

@(private)
UI_Visual_Element :: struct {
	info: clay.LayoutElementInfo,
	transform: foster.Matrix3x2,
	opacity: f32,
	resolved, resolving: bool,
}

@(private)
UI_VISUAL_IDENTITY :: foster.Matrix3x2{1, 0, 0, 1, 0, 0}

// ------------------------------------------------------------------------------
// 布局快照 —— 保存数值，不保留 Clay 帧内指针
// ------------------------------------------------------------------------------

@(private)
ui_visual_snapshot :: proc(ctx: ^UI_Context) {
	clear(&ctx.visual_elements)
	if len(ctx.visuals) == 0 {
		return
	}
	count := clay.GetLayoutElementInfo(nil)
	resize(&ctx.visual_layout, count)
	clay.GetLayoutElementInfo(ctx.visual_layout[:])
	for info in ctx.visual_layout {
		ctx.visual_elements[info.id] = UI_Visual_Element{info = info}
	}
	for info in ctx.visual_layout {
		ui_visual_resolve(ctx, info.id)
	}
}

@(private)
ui_visual_resolve :: proc(ctx: ^UI_Context, id: u32) -> UI_Visual_Element {
	e, found := ctx.visual_elements[id]
	if !found || e.resolving {
		return UI_Visual_Element{transform = UI_VISUAL_IDENTITY, opacity = 1}
	}
	if e.resolved {
		return e
	}
	e.resolving = true
	ctx.visual_elements[id] = e
	parent := ui_visual_resolve(ctx, e.info.parentId)
	e.transform = parent.transform
	e.opacity = parent.opacity
	if v, ok := ctx.visuals[id]; ok {
		bb := e.info.boundingBox
		pivot := foster.Vec2{bb.x + bb.width * v.pivot.x, bb.y + bb.height * v.pivot.y}
		c := math.cos(v.rotation)
		s := math.sin(v.rotation)
		local := foster.Matrix3x2{c * v.scale.x, s * v.scale.x,
			-s * v.scale.y, c * v.scale.y, 0, 0}
		local.M31 = pivot.x + v.offset.x - pivot.x * local.M11 - pivot.y * local.M21
		local.M32 = pivot.y + v.offset.y - pivot.x * local.M12 - pivot.y * local.M22
		e.transform = ui_visual_compose(parent.transform, local)
		e.opacity *= math.clamp(v.opacity, 0, 1)
	}
	e.resolved = true
	e.resolving = false
	ctx.visual_elements[id] = e
	return e
}

@(private)
ui_visual_compose :: proc(a, b: foster.Matrix3x2) -> foster.Matrix3x2 {
	return {
		a.M11 * b.M11 + a.M21 * b.M12, a.M12 * b.M11 + a.M22 * b.M12,
		a.M11 * b.M21 + a.M21 * b.M22, a.M12 * b.M21 + a.M22 * b.M22,
		a.M11 * b.M31 + a.M21 * b.M32 + a.M31,
		a.M12 * b.M31 + a.M22 * b.M32 + a.M32,
	}
}

@(private)
ui_visual_point :: proc "contextless" (m: foster.Matrix3x2, p: foster.Vec2) -> foster.Vec2 {
	return {p.x * m.M11 + p.y * m.M21 + m.M31, p.x * m.M12 + p.y * m.M22 + m.M32}
}

// 第一版裁剪仍为屏幕轴对齐矩形；旋转裁剪容器时使用变换后包围盒。
@(private)
ui_visual_clip :: proc "contextless" (m: foster.Matrix3x2, bb: clay.BoundingBox) -> clay.BoundingBox {
	points := [4]foster.Vec2{{bb.x, bb.y}, {bb.x + bb.width, bb.y},
		{bb.x + bb.width, bb.y + bb.height}, {bb.x, bb.y + bb.height}}
	lo := ui_visual_point(m, points[0])
	hi := lo
	for point in points[1:] {
		p := ui_visual_point(m, point)
		lo = {min(lo.x, p.x), min(lo.y, p.y)}
		hi = {max(hi.x, p.x), max(hi.y, p.y)}
	}
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}

// ------------------------------------------------------------------------------
// 输入 —— 与既有 Clay 一样使用上一帧布局和显示变换
// ------------------------------------------------------------------------------

// 返回去掉子树变换后的逻辑指针；供自定义滑条/拖动控件使用。
// 零缩放不可逆时 ok=false，不能开始或推进拖动。
ui_pointer_local :: proc(ctx: ^UI_Context, id: string) -> (point: foster.Vec2, ok: bool) {
	return ui_visual_pointer(ctx, clay.ID(id).id, {ctx.pointer_x, ctx.pointer_y})
}

@(private)
ui_visual_pointer :: proc "contextless" (ctx: ^UI_Context, id: u32, point: foster.Vec2) -> (foster.Vec2, bool) {
	e, found := ctx.visual_elements[id]
	if !found {
		return point, true
	}
	m := e.transform
	det := m.M11 * m.M22 - m.M12 * m.M21
	if abs(det) < 0.000001 || e.opacity <= 0 {
		return {}, false
	}
	p := point - foster.Vec2{m.M31, m.M32}
	return {(p.x * m.M22 - p.y * m.M21) / det,
		(p.y * m.M11 - p.x * m.M12) / det}, true
}

@(private)
ui_visual_hit :: proc "c" (
	id: u32, position: clay.Vector2, bounds_arg: clay.BoundingBox, clip: bool, userdata: rawptr,
) -> bool {
	bounds := bounds_arg
	ctx := cast(^UI_Context)userdata
	p := foster.Vec2{position[0], position[1]}
	if !ui_visual_inside(p, {0, 0, ctx.width, ctx.height}) {
		return false
	}
	if clip {
		if e, ok := ctx.visual_elements[id]; ok {
			bounds = ui_visual_clip(e.transform, bounds)
		}
	} else {
		local, ok := ui_visual_pointer(ctx, id, p)
		if !ok {
			return false
		}
		p = local
		// Clay 原生只检查最近裁剪；动画命中需要与完整嵌套 scissor 相交一致。
		if e, exists := ctx.visual_elements[id]; exists {
			clip_id := e.info.clipId
			for depth := 0; clip_id != 0 && depth < len(ctx.visual_elements); depth += 1 {
				ancestor, found := ctx.visual_elements[clip_id]
				if !found {
					break
				}
				bb := ui_visual_clip(ancestor.transform, ancestor.info.boundingBox)
				if !ui_visual_inside({position[0], position[1]}, bb) {
					return false
				}
				clip_id = ancestor.info.clipId
			}
		}
	}
	return ui_visual_inside(p, bounds)
}

@(private)
ui_visual_inside :: proc "contextless" (p: foster.Vec2, bb: clay.BoundingBox) -> bool {
	return p.x >= bb.x && p.y >= bb.y && p.x <= bb.x + bb.width && p.y <= bb.y + bb.height
}

// ------------------------------------------------------------------------------
// 发射 —— 预乘颜色与最终像素矩阵
// ------------------------------------------------------------------------------

@(private)
ui_visual_apply_ops :: proc(ctx: ^UI_Context, id: u32, ops: ^[dynamic]UI_Op, start: int) {
	e, found := ctx.visual_elements[id]
	if !found {
		return
	}
	for &op in ops^[start:] {
		if op.kind == .Quad {
			op.transformed = e.transform != UI_VISUAL_IDENTITY
			op.transform = e.transform
			// UI 颜色为预乘 alpha，RGB 和 A 必须同步衰减。
			op.color = {u8(f32(op.color.R) * e.opacity), u8(f32(op.color.G) * e.opacity),
				u8(f32(op.color.B) * e.opacity), u8(f32(op.color.A) * e.opacity)}
		} else if op.kind == .Scissor_Start {
			bb := ui_visual_clip(e.transform, {op.clip_x, op.clip_y, op.clip_w, op.clip_h})
			op.clip_x = bb.x
			op.clip_y = bb.y
			op.clip_w = bb.width
			op.clip_h = bb.height
		}
	}
}

@(private)
ui_visual_pixel_matrix :: proc(ctx: ^UI_Context, m: foster.Matrix3x2) -> [16]f32 {
	s := ctx.scale
	return {m.M11 * s, m.M12 * s, 0, 0, m.M21 * s, m.M22 * s, 0, 0,
		0, 0, 1, 0, m.M31 * s + ctx.viewport_origin.x, m.M32 * s + ctx.viewport_origin.y, 0, 1}
}
