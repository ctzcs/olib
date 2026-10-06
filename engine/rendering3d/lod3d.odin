// rendering3d:lod3d —— LOD 选择（对位 DragonLib LodSelector3D / ModelLod3D）。
//
// 屏幕高度占比阈值从高到低，最后必须为 0（最低档无条件兜底）；
// 阈值上下带相对滞回，避免相机在边界附近抖动。
package rendering3d

import "core:math"

import dasset "olib:engine/dasset"
import world "olib:engine/world"

// 分区：
//   Lod_Selector —— 阈值状态机 + 屏幕高度估算
//   Model_Lod —— 多级模型引用（泛型：GPU 资源类型由调用侧决定）

// ------------------------------------------------------------------------------
// Lod_Selector
// ------------------------------------------------------------------------------

Lod_Selector :: struct {
	thresholds:    []f32, // 严格降序，末项为 0
	current_level: int, // -1 = 未初始化（下次 Select 全量扫）
	hysteresis:    f32, // 0..0.49；0 关闭
}

// thresholds 必须非空、有限、非负、严格降序且末项为 0；违反返回 false。
lod_selector_init :: proc(s: ^Lod_Selector, thresholds: []f32, allocator := context.allocator) -> bool {
	if len(thresholds) == 0 { return false }
	if thresholds[len(thresholds) - 1] != 0 { return false }
	for i: int = 0; i < len(thresholds); i += 1 {
		t := thresholds[i]
		if t != t || t < 0 { return false } // NaN 或负
		if i > 0 && t >= thresholds[i - 1] { return false }
	}

	s.thresholds = make([]f32, len(thresholds), allocator)
	copy(s.thresholds, thresholds)
	s.current_level = -1
	s.hysteresis = 0.1
	return true
}

lod_selector_dispose :: proc(s: ^Lod_Selector) {
	delete(s.thresholds, context.allocator)
	s^ = {}
}

lod_selector_level_count :: proc(s: ^Lod_Selector) -> int {
	return len(s.thresholds)
}

lod_selector_reset :: proc(s: ^Lod_Selector) {
	s.current_level = -1
}

// 按屏幕高度选级（滞回生效）。NaN/负高度返回当前级。
lod_selector_select :: proc(s: ^Lod_Selector, screen_height: f32) -> int {
	if screen_height != screen_height || screen_height < 0 {
		return s.current_level >= 0 ? s.current_level : len(s.thresholds) - 1
	}
	hysteresis := math.clamp(s.hysteresis, 0, 0.49)

	if s.current_level < 0 {
		s.current_level = len(s.thresholds) - 1
		for i: int = 0; i < len(s.thresholds); i += 1 {
			if screen_height >= s.thresholds[i] {
				s.current_level = i
				break
			}
		}
	} else {
		for s.current_level > 0 && screen_height >= s.thresholds[s.current_level - 1] * (1 + hysteresis) {
			s.current_level -= 1
		}
		for s.current_level < len(s.thresholds) - 1 && screen_height < s.thresholds[s.current_level] * (1 - hysteresis) {
			s.current_level += 1
		}
	}
	return s.current_level
}

// 保守球的投影直径 / 视口高度。相机在球内、近裁面相交或数据不可靠时
// 返回 +inf（选最高细节——宁多画不低估）。
lod_screen_height :: proc(camera: ^world.Camera3D, bounds: dasset.Dasset_Bounds) -> f32 {
	center := [3]f32{
		(bounds.min[0] + bounds.max[0]) * 0.5,
		(bounds.min[1] + bounds.max[1]) * 0.5,
		(bounds.min[2] + bounds.max[2]) * 0.5,
	}
	dx := bounds.max[0] - bounds.min[0]
	dy := bounds.max[1] - bounds.min[1]
	dz := bounds.max[2] - bounds.min[2]
	radius := math.sqrt(dx*dx + dy*dy + dz*dz) * 0.5

	forward := world.camera3d_forward(camera)
	offset := [3]f32{center[0] - camera.position[0], center[1] - camera.position[1], center[2] - camera.position[2]}
	depth := offset[0]*forward[0] + offset[1]*forward[1] + offset[2]*forward[2]

	if radius != radius || depth != depth || radius < 0 ||
	   depth - radius <= max(0.001, camera.near_clip) {
		return f32(math.INF_F32)
	}
	// 透视投影 M22 = zz（列 2 的第 2 分量）
	projection := world.camera3d_projection(camera)
	return radius * math.abs(projection.c2[2]) / (depth - radius)
}

// ------------------------------------------------------------------------------
// Model_Lod —— 多级模型引用（泛型）
// ------------------------------------------------------------------------------

// 一个实例的多级模型引用与 LOD 状态。不拥有 GPU 资源、不生成简化网格；
// levels 的元素类型由调用侧决定（如 ^foster.Mesh 或自定义 Model 包装）。
// bounds 是所有级别的共同局部包围盒（动画使用者应传保守盒）。
Model_Lod :: struct($T: typeid) {
	models:   []T,
	selector: Lod_Selector,
	bounds:   dasset.Dasset_Bounds,
}

model_lod_init :: proc(m: ^Model_Lod($T), models: []T, thresholds: []f32, bounds: dasset.Dasset_Bounds) -> bool {
	if len(models) != len(thresholds) { return false }
	if !lod_selector_init(&m.selector, thresholds) { return false }
	m.models = models
	m.bounds = bounds
	return true
}

model_lod_dispose :: proc(m: ^Model_Lod($T)) {
	lod_selector_dispose(&m.selector)
	m^ = {}
}

// 选当前级的模型（内部先走 selector）。world 变换下用局部包围盒投影。
model_lod_select :: proc(m: ^Model_Lod($T), camera: ^world.Camera3D, world_matrix: world.Matrix4) -> (T, bool) {
	world_bounds := m.bounds
	// 包围盒随 world 平移（忽略旋转/缩放的保守近似：取 8 角点变换后的盒）
	if w, ok := world.matrix4_transform_point(world_matrix, m.bounds.min); ok {
		world_bounds.min = w
	}
	if w, ok := world.matrix4_transform_point(world_matrix, m.bounds.max); ok {
		world_bounds.max = w
	}
	level := lod_selector_select(&m.selector, lod_screen_height(camera, world_bounds))
	if level < 0 || level >= len(m.models) { return _, false }
	return m.models[level], true
}
