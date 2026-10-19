// rendering3d:lod —— LOD 选择（对位 DragonLib LodSelector3D / ModelLod3D）。
//
// 屏幕高度占比阈值从高到低，最后必须为 0（最低档无条件兜底）；
// 阈值上下带相对滞回，避免相机在边界附近抖动。
package rendering3d

import "core:math"
import "core:math/linalg"

import dasset "olib:core/dasset"
import world "olib:kit/world"

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
	if len(thresholds) == 0 do return false
	if thresholds[len(thresholds) - 1] != 0 do return false
	for i: int = 0; i < len(thresholds); i += 1 {
		t := thresholds[i]
		if t != t || t < 0 do return false // NaN 或负
		if i > 0 && t >= thresholds[i - 1] do return false
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
	center := (bounds.min + bounds.max) * 0.5
	return lod_sphere_screen_height(camera, center, linalg.length(bounds.max - bounds.min) * 0.5)
}

// 球（世界空间）的投影直径 / 视口高度，规则同 lod_screen_height。
@(private)
lod_sphere_screen_height :: proc(camera: ^world.Camera3D, center: [3]f32, radius: f32) -> f32 {
	forward := world.camera3d_forward(camera)
	depth := linalg.dot(center - camera.position, forward)
	if radius != radius || depth != depth || radius < 0 ||
	   depth - radius <= max(0.001, camera.near_clip) {
		return f32(math.INF_F32)
	}
	// 透视投影 M22 = zz（列 2 的第 2 分量）
	projection := world.camera3d_projection(camera)
	return radius * math.abs(projection.c2[2]) / (depth - radius)
}

// 局部包围盒经 world_matrix 变换后的包围球：球心是盒中心的像，半径取 8 个角点到球心的最远距离。
// 平移、旋转、缩放（含非均匀缩放）下都不低估；变换退化时返回 ok=false。
@(private)
lod_world_sphere :: proc(bounds: dasset.Dasset_Bounds, world_matrix: world.Matrix4) -> (center: [3]f32, radius: f32, ok: bool) {
	center = world.matrix4_transform_point(world_matrix, (bounds.min + bounds.max) * 0.5) or_return
	for corner in aabb_corners(bounds) {
		p := world.matrix4_transform_point(world_matrix, corner) or_return
		radius = max(radius, linalg.length(p - center))
	}
	return center, radius, true
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
	if len(models) != len(thresholds) do return false
	if !lod_selector_init(&m.selector, thresholds) do return false
	m.models = models
	m.bounds = bounds
	return true
}

model_lod_dispose :: proc(m: ^Model_Lod($T)) {
	lod_selector_dispose(&m.selector)
	m^ = {}
}

// 选当前级的模型（内部先走 selector）。局部包围盒按 world_matrix 变换成保守包围球再投影。
model_lod_select :: proc(m: ^Model_Lod($T), camera: ^world.Camera3D, world_matrix: world.Matrix4) -> (T, bool) {
	height := f32(math.INF_F32) // 变换退化时选最高细节
	if center, radius, ok := lod_world_sphere(m.bounds, world_matrix); ok {
		height = lod_sphere_screen_height(camera, center, radius)
	}
	level := lod_selector_select(&m.selector, height)
	if level < 0 || level >= len(m.models) do return _, false
	return m.models[level], true
}
