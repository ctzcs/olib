package foster_framework

import "core:math"
import "core:strconv"
import "core:strings"
import "base:intrinsics"
import "core:fmt"
import coretime "core:time"
import json "core:encoding/json"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Utility / Calc — 常量与计算助手
//   Utility / Converters — JSON 数值转换
//   Utility / Ease — 缓动
//   Utility / Log — 日志
//   Utility / Pool — 对象池
//   Utility / Rng — 随机数
//   Utility / StackList — 固定容量集合
//   Utility / TriangulationEnumerator — 三角化枚举
//   Extensions — 扩展函数
//   Extensions / Numbers — 数值解析
//   Extensions / Numerics — 向量与四元数
//   Extensions / TimeSpan — 时间转换
//   Utility / Calc / Intervals & Collections — 区间与集合助手
//   Utility / Log / Callbacks — 回调与历史
//   Utility / Rng / Collections — 集合选择与时间种子
//   Extensions / TimeSpan / Expiration — 时间比较
//   Utility / Time — 帧计时助手

// ==============================================================================
// Utility / Calc — 常量与计算助手
// ==============================================================================

Right :: f32(0)
Left :: PI
Up :: PI + HalfPI
Down :: HalfPI
UpRight :: TAU - PI * 0.25
DownRight :: PI * 0.25
UpLeft :: TAU - PI * 0.75
DownLeft :: PI * 0.75

IsBitSet :: proc(value: $T, position: int) -> bool {
	return (value & (T(1) << T(position))) != 0
}

GiveMe :: proc(index: int, choices: []$T) -> T {
	if index < 0 || index >= len(choices) {
		return {}
	}
	return choices[index]
}

SignsMatch :: proc(a, b: f32) -> bool {
	return math.sign(a) == math.sign(b)
}

Squared :: proc(v: f32) -> f32 {
	return v * v
}

AvgFloat :: proc(values: []f32) -> f32 {
	if len(values) == 0 {
		return 0
	}
	sum: f32 = 0
	for v in values {
		sum += v
	}
	return sum / f32(len(values))
}

AvgVec2 :: proc(values: []Vec2) -> Vec2 {
	if len(values) == 0 {
		return {}
	}
	sum: Vec2 = {}
	for v in values {
		sum[0] += v[0]
		sum[1] += v[1]
	}
	return Vec2{sum[0] / f32(len(values)), sum[1] / f32(len(values))}
}
Avg :: proc {
	AvgFloat,
	AvgVec2,
}

OffsetPoint2Slice :: proc(points: []Point2, offset: Point2) -> []Point2 {
	for i := 0; i < len(points); i += 1 {
		points[i] = Point2{points[i].X + offset.X, points[i].Y + offset.Y}
	}
	return points
}

TriangleAreaVec2 :: proc(a, b, c: Vec2) -> f32 {
	return math.abs((a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1])) * .5)
}

Cross :: proc(a, b: Vec2) -> f32 {
	return a[0] * b[1] - a[1] * b[0]
}

SignCross :: proc(a, b: Vec2) -> int {
	return int(math.sign(Cross(a, b)))
}

Orient :: proc(a, b, c: Vec2) -> int {
	return SignCross(Vec2{b[0] - a[0], b[1] - a[1]}, Vec2{c[0] - a[0], c[1] - a[1]})
}

TriangleContainsPoint :: proc(a, b, c, p: Vec2) -> bool {
	return math.abs(Orient(a, b, p) + Orient(b, c, p) + Orient(c, a, p)) == 3
}

AbsDot :: proc(a, b: Vec2) -> f32 {
	return math.abs(spatial_vec2_dot(a, b))
}

DotSq :: proc(a, b: Vec2) -> f32 {
	d := spatial_vec2_dot(a, b)
	return math.sign(d) * d * d
}

AbsDotSq :: proc(a, b: Vec2) -> f32 {
	d := spatial_vec2_dot(a, b)
	return d * d
}

spatial_vec2_dot :: proc(a, b: Vec2) -> f32 {
	return a[0] * b[0] + a[1] * b[1]
}

ApproachVec2 :: proc(from, target: Vec2, amount: f32) -> Vec2 {
	if from == target {
		return target
	}
	d := Vec2{target[0] - from[0], target[1] - from[1]}
	if d[0] * d[0] + d[1] * d[1] <= amount * amount {
		return target
	}
	l := math.sqrt(d[0] * d[0] + d[1] * d[1])
	return Vec2{from[0] + d[0] / l * amount, from[1] + d[1] / l * amount}
}

Approach3 :: proc(from, target: Vec3, amount: f32) -> Vec3 {
	if from == target {
		return target
	}
	d := Vec3{target[0] - from[0], target[1] - from[1], target[2] - from[2]}
	l2 := d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
	if l2 <= amount * amount {
		return target
	}
	l := math.sqrt(l2)
	return Vec3 {
		from[0] + d[0] / l * amount,
		from[1] + d[1] / l * amount,
		from[2] + d[2] / l * amount,
	}
}

ApproachRefScalar :: proc(from: ^f32, target, amount: f32) -> f32 {
	from^ = ApproachScalar(from^, target, amount)
	return from^
}

ApproachRefVec2 :: proc(from: ^Vec2, target: Vec2, amount: f32) -> Vec2 {
	from^ = ApproachVec2(from^, target, amount)
	return from^
}
Approach :: proc {
	ApproachScalar,
	ApproachVec2,
	Approach3,
}

ApproachIfLower :: proc(from, target, amount: f32) -> f32 {
	if SignsMatch(from, target) && math.abs(from) >= math.abs(target) {
		return from
	}
	return ApproachScalar(from, target, amount)
}

RotateToward :: proc(dir, target: Vec2, max_angle_delta, max_magnitude_delta: f32) -> Vec2 {
	angle := Angle(dir)
	length := spatial_vec2_length(dir)
	if max_angle_delta > 0 {
		angle = AngleApproach(angle, Angle(target), max_angle_delta)
	}
	if max_magnitude_delta > 0 {
		length = Approach(length, spatial_vec2_length(target), max_magnitude_delta)
	}
	return AngleToVector(angle, length)
}

SineMap :: proc(radians, new_min, new_max: f32) -> f32 {
	return MapTo(math.sin(radians), -1, 1, new_min, new_max)
}

AngleVector :: proc(v: Vec2) -> f32 {
	return math.atan2(v[1], v[0])
}

AngleBetween :: proc(from, to: Vec2) -> f32 {
	return math.atan2(to[1] - from[1], to[0] - from[0])
}
Angle :: proc {
	AngleVector,
	AngleBetween,
}

AngleToVector :: proc(angle: f32, length: f32 = 1) -> Vec2 {
	return Vec2{math.cos(angle) * length, math.sin(angle) * length}
}

AngleWrap :: proc(angle: f32) -> f32 {
	result := math.mod(angle, TAU)
	if result < 0 {
		result += TAU
	}
	return result
}

AngleDiff :: proc(a, b: f32) -> f32 {
	result := math.mod(b - a - PI, TAU)
	if result < 0 {
		result += TAU
	}
	return result - PI
}

AbsAngleDiff :: proc(a, b: f32) -> f32 {
	return math.abs(AngleDiff(a, b))
}

AngleApproach :: proc(value, target, max_move: f32) -> f32 {
	d := AngleDiff(value, target)
	if math.abs(d) < max_move {
		return target
	}
	return value + Clamp(d, -max_move, max_move)
}

AngleLerp :: proc(a, b, percent: f32) -> f32 {
	return a + AngleDiff(a, b) * percent
}

AngleReflectOnX :: proc(angle: f32) -> f32 {
	return AngleWrap(-angle)
}

AngleReflectOnY :: proc(angle: f32) -> f32 {
	return AngleWrap(HalfPI - (angle - HalfPI))
}

spatial_vec2_length :: proc(v: Vec2) -> f32 {
	return math.sqrt(v[0] * v[0] + v[1] * v[1])
}

NextPowerOfTwo :: proc(x: int) -> int {
	if x <= 0 {
		return 0
	}
	if x == 1 {
		return 1
	}
	v := x - 1
	v |= v >> 1
	v |= v >> 2
	v |= v >> 4
	v |= v >> 8
	v |= v >> 16
	return v + 1
}

Approx :: proc(a, b: f32) -> bool {
	return math.abs(a - b) <= 0.001
}

GetBresenhamsLine :: proc(a, b: Point2) -> [dynamic]Point2 {
	result: [dynamic]Point2 = {}
	aa := a
	bb := b
	steep := math.abs(bb.Y - aa.Y) > math.abs(bb.X - aa.X)
	if steep {
		aa.X, aa.Y = aa.Y, aa.X
		bb.X, bb.Y = bb.Y, bb.X
	}
	if aa.X > bb.X {
		aa.X, bb.X = bb.X, aa.X
		aa.Y, bb.Y = bb.Y, aa.Y
	}
	dx := bb.X - aa.X
	dy := math.abs(bb.Y - aa.Y)
	err := dx / 2
	ystep := 1
	if aa.Y >= bb.Y {
		ystep = -1
	}
	y := aa.Y
	for x := aa.X; x <= bb.X; x += 1 {
		if steep {
			append(&result, Point2{y, x})
		} else {
			append(&result, Point2{x, y})
		}
		err -= dy
		if err < 0 {
			y += ystep
			err += dx
		}
	}
	return result
}

SolveQuadratic :: proc(a, b, c: f32) -> (bool, f32, f32) {
	d := b * b - 4 * a * c
	if d < 0 {
		return false, 0, 0
	}
	if d == 0 {
		r := -b / (2 * a)
		return true, r, r
	}
	s := math.sqrt(d)
	return true, (-b + s) / (2 * a), (-b - s) / (2 * a)
}

GetClosestPointIndexVec2 :: proc(points: []Vec2, to: Vec2) -> int {
	best := -1
	dist: f32 = 0
	for i := 0; i < len(points); i += 1 {
		p := points[i]
		dx := p[0] - to[0]
		dy := p[1] - to[1]
		d := dx * dx + dy * dy
		if best < 0 || d < dist {
			best = i
			dist = d
		}
	}
	return best
}

GetFurthestPointIndexVec2 :: proc(points: []Vec2, to: Vec2) -> int {
	best := -1
	dist: f32 = 0
	for i := 0; i < len(points); i += 1 {
		p := points[i]
		dx := p[0] - to[0]
		dy := p[1] - to[1]
		d := dx * dx + dy * dy
		if best < 0 || d > dist {
			best = i
			dist = d
		}
	}
	return best
}

GetClosestPointIndexPoint2 :: proc(points: []Point2, to: Vec2) -> int {
	best := -1
	dist: f32 = 0
	for i := 0; i < len(points); i += 1 {
		p := points[i]
		dx := f32(p.X) - to[0]
		dy := f32(p.Y) - to[1]
		d := dx * dx + dy * dy
		if best < 0 || d < dist {
			best = i
			dist = d
		}
	}
	return best
}

GetFurthestPointIndexPoint2 :: proc(points: []Point2, to: Vec2) -> int {
	best := -1
	dist: f32 = 0
	for i := 0; i < len(points); i += 1 {
		p := points[i]
		dx := f32(p.X) - to[0]
		dy := f32(p.Y) - to[1]
		d := dx * dx + dy * dy
		if best < 0 || d > dist {
			best = i
			dist = d
		}
	}
	return best
}
GetClosestPointIndex :: proc {
	GetClosestPointIndexVec2,
	GetClosestPointIndexPoint2,
}
GetFurthestPointIndex :: proc {
	GetFurthestPointIndexVec2,
	GetFurthestPointIndexPoint2,
}

Smallest :: proc(values: []$T) -> int {
	if len(values) == 0 {
		return -1
	}
	best := 0
	for i := 1; i < len(values); i += 1 {
		if values[i] < values[best] {
			best = i
		}
	}
	return best
}

Largest :: proc(values: []$T) -> int {
	if len(values) == 0 {
		return -1
	}
	best := 0
	for i := 1; i < len(values); i += 1 {
		if values[i] > values[best] {
			best = i
		}
	}
	return best
}

GetClosestValueIndex :: proc(values: []$T, to: T) -> int where intrinsics.type_is_numeric(T) {
	best: int = -1
	dist: T = {}
	for v, i in values {
		d: T = v - to
		if d < T(0) {
			d = -d
		}
		if best < 0 || d < dist {
			best = i
			dist = d
		}
	}
	return best
}

GetFurthestValueIndex :: proc(values: []$T, to: T) -> int where intrinsics.type_is_numeric(T) {
	best: int = -1
	dist: T = {}
	for v, i in values {
		d: T = v - to
		if d < T(0) {
			d = -d
		}
		if best < 0 || d > dist {
			best = i
			dist = d
		}
	}
	return best
}

GetClosestValue :: proc(values: []$T, to: T) -> T where intrinsics.type_is_numeric(T) {
	i := GetClosestValueIndex(values, to)
	if i < 0 {
		return {}
	}
	return values[i]
}

GetFurthestValue :: proc(values: []$T, to: T) -> T where intrinsics.type_is_numeric(T) {
	i := GetFurthestValueIndex(values, to)
	if i < 0 {
		return {}
	}
	return values[i]
}

GetClosestPointVec2 :: proc(points: []Vec2, to: Vec2) -> Vec2 {
	i := GetClosestPointIndexVec2(points, to)
	if i < 0 {
		return {}
	}
	return points[i]
}

GetFurthestPointVec2 :: proc(points: []Vec2, to: Vec2) -> Vec2 {
	i := GetFurthestPointIndexVec2(points, to)
	if i < 0 {
		return {}
	}
	return points[i]
}

GetClosestPointPoint2 :: proc(points: []Point2, to: Vec2) -> Point2 {
	i := GetClosestPointIndexPoint2(points, to)
	if i < 0 {
		return {}
	}
	return points[i]
}

GetFurthestPointPoint2 :: proc(points: []Point2, to: Vec2) -> Point2 {
	i := GetFurthestPointIndexPoint2(points, to)
	if i < 0 {
		return {}
	}
	return points[i]
}
GetClosestPoint :: proc {
	GetClosestPointVec2,
	GetClosestPointPoint2,
}
GetFurthestPoint :: proc {
	GetFurthestPointVec2,
	GetFurthestPointPoint2,
}

Lerp :: proc(a, b, percent: f32) -> f32 {
	return a + (b - a) * percent
}

ClampedLerp :: proc(a, b, percent: f32) -> f32 {
	return Lerp(a, b, Clamp01(percent))
}

Bezier3 :: proc(a, b, c, t: f32) -> f32 {
	return Lerp(Lerp(a, b, t), Lerp(b, c, t), t)
}

Bezier4 :: proc(a, b, c, d, t: f32) -> f32 {
	return Bezier3(Lerp(a, b, t), Lerp(b, c, t), Lerp(c, d, t), t)
}

BezierVec3 :: proc(a, b, c: Vec2, t: f32) -> Vec2 {
	return Vec2{Bezier3(a[0], b[0], c[0], t), Bezier3(a[1], b[1], c[1], t)}
}

BezierVec4 :: proc(a, b, c, d: Vec2, t: f32) -> Vec2 {
	return BezierVec3(
		Vec2{Lerp(a[0], b[0], t), Lerp(a[1], b[1], t)},
		Vec2{Lerp(b[0], c[0], t), Lerp(b[1], c[1], t)},
		Vec2{Lerp(c[0], d[0], t), Lerp(c[1], d[1], t)},
		t,
	)
}
Bezier :: proc {
	Bezier3,
	Bezier4,
	BezierVec3,
	BezierVec4,
}

SnapScalar :: proc(value, interval: f32) -> f32 {
	if interval == 0 {
		return value
	}
	return math.round(value / interval) * interval
}

SnapFloorScalar :: proc(value, interval: f32) -> f32 {
	if interval == 0 {
		return value
	}
	return math.floor(value / interval) * interval
}

SnapCeilScalar :: proc(value, interval: f32) -> f32 {
	if interval == 0 {
		return value
	}
	return math.ceil(value / interval) * interval
}

SnapVec2 :: proc(value, interval: Vec2) -> Vec2 {
	return Vec2{SnapScalar(value[0], interval[0]), SnapScalar(value[1], interval[1])}
}

SnapFloorVec2 :: proc(value, interval: Vec2) -> Vec2 {
	return Vec2{SnapFloorScalar(value[0], interval[0]), SnapFloorScalar(value[1], interval[1])}
}

SnapCeilVec2 :: proc(value, interval: Vec2) -> Vec2 {
	return Vec2{SnapCeilScalar(value[0], interval[0]), SnapCeilScalar(value[1], interval[1])}
}

SnapFloatPoint2 :: proc(value: Vec2, interval: Point2) -> Point2 {
	return Point2 {
		int(math.round(value[0] / f32(interval.X))) * interval.X,
		int(math.round(value[1] / f32(interval.Y))) * interval.Y,
	}
}

SnapScalarVec2 :: proc(value: Vec2, interval: f32) -> Vec2 {
	return Vec2{Snap(value[0], interval), Snap(value[1], interval)}
}

SnapIntPoint2 :: proc(value: Vec2, interval: int) -> Point2 {
	return Point2 {
		int(math.round(value[0] / f32(interval))) * interval,
		int(math.round(value[1] / f32(interval))) * interval,
	}
}
Snap :: proc {
	SnapScalar,
	SnapVec2,
	SnapFloatPoint2,
	SnapScalarVec2,
	SnapIntPoint2,
}

SnapFloorFloatPoint2 :: proc(value: Vec2, interval: Point2) -> Point2 {
	return Point2 {
		int(math.floor(value[0] / f32(interval.X))) * interval.X,
		int(math.floor(value[1] / f32(interval.Y))) * interval.Y,
	}
}

SnapFloorScalarVec2 :: proc(value: Vec2, interval: f32) -> Vec2 {
	return Vec2{SnapFloor(value[0], interval), SnapFloor(value[1], interval)}
}

SnapFloorIntPoint2 :: proc(value: Vec2, interval: int) -> Point2 {
	return Point2 {
		int(math.floor(value[0] / f32(interval))) * interval,
		int(math.floor(value[1] / f32(interval))) * interval,
	}
}
SnapFloor :: proc {
	SnapFloorScalar,
	SnapFloorVec2,
	SnapFloorFloatPoint2,
	SnapFloorScalarVec2,
	SnapFloorIntPoint2,
}

SnapCeilFloatPoint2 :: proc(value: Vec2, interval: Point2) -> Point2 {
	return Point2 {
		int(math.ceil(value[0] / f32(interval.X))) * interval.X,
		int(math.ceil(value[1] / f32(interval.Y))) * interval.Y,
	}
}

SnapCeilScalarVec2 :: proc(value: Vec2, interval: f32) -> Vec2 {
	return Vec2{SnapCeil(value[0], interval), SnapCeil(value[1], interval)}
}

SnapCeilIntPoint2 :: proc(value: Vec2, interval: int) -> Point2 {
	return Point2 {
		int(math.ceil(value[0] / f32(interval))) * interval,
		int(math.ceil(value[1] / f32(interval))) * interval,
	}
}
SnapCeil :: proc {
	SnapCeilScalar,
	SnapCeilVec2,
	SnapCeilFloatPoint2,
	SnapCeilScalarVec2,
	SnapCeilIntPoint2,
}

MoveVec2 :: proc(points: []Vec2, delta: Vec2) -> []Vec2 {
	for i := 0; i < len(points); i += 1 {
		points[i] += delta
	}
	return points
}

InsideTriangle :: proc(a, b, c, p: Vec2) -> bool {
	return TriangleContainsPoint(a, b, c, p)
}

ParseVector2 :: proc(value: string, delimiter: u8) -> (Vec2, bool) {
	result: Vec2 = {}
	start := 0
	parts: [dynamic]f32 = {}
	defer delete(parts)
	for i := 0; i <= len(value); i += 1 {
		if i == len(value) || value[i] == delimiter {
			if i == start {
				return result, false
			}
			v, ok := strconv.parse_f32(value[start:i])
			if !ok {
				return result, false
			}
			append(&parts, v)
			start = i + 1
		}
	}
	if len(parts) != 2 {
		return result, false
	}
	return Vec2{parts[0], parts[1]}, true
}

ParseVector3 :: proc(value: string, delimiter: u8) -> (Vec3, bool) {
	result: Vec3 = {}
	start := 0
	parts: [dynamic]f32 = {}
	defer delete(parts)
	for i := 0; i <= len(value); i += 1 {
		if i == len(value) || value[i] == delimiter {
			if i == start {
				return result, false
			}
			v, ok := strconv.parse_f32(value[start:i])
			if !ok {
				return result, false
			}
			append(&parts, v)
			start = i + 1
		}
	}
	if len(parts) != 3 {
		return result, false
	}
	return Vec3{parts[0], parts[1], parts[2]}, true
}

StaticStringHashString :: proc(value: string) -> int {
	hash: u32 = 5381
	for b in value {
		hash = (hash << 5) + hash + u32(b)
	}
	return int(i32(hash))
}

StaticStringHashBytes :: proc(value: []u8) -> int {
	hash: u32 = 5381
	for b in value {
		hash = (hash << 5) + hash + u32(b)
	}
	return int(i32(hash))
}
StaticStringHash :: proc {
	StaticStringHashString,
	StaticStringHashBytes,
}

EqualsOrdinalIgnoreCaseUtf8String :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i += 1 {
		ca := a[i]
		cb := b[i]
		if ca >= 'A' && ca <= 'Z' {
			ca += 32
		}
		if cb >= 'A' && cb <= 'Z' {
			cb += 32
		}
		if ca != cb {
			return false
		}
	}
	return true
}

EqualsOrdinalIgnoreCaseUtf8Bytes :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i += 1 {
		ca := a[i]
		cb := b[i]
		if ca >= 'A' && ca <= 'Z' {
			ca += 32
		}
		if cb >= 'A' && cb <= 'Z' {
			cb += 32
		}
		if ca != cb {
			return false
		}
	}
	return true
}
EqualsOrdinalIgnoreCaseUtf8 :: proc {
	EqualsOrdinalIgnoreCaseUtf8String,
	EqualsOrdinalIgnoreCaseUtf8Bytes,
}

AmountInCommon :: proc(a, b: string) -> int {
	n := 0
	for i := 0; i < min(len(a), len(b)); i += 1 {
		if a[i] == b[i] {
			n += 1
		} else {
			break
		}
	}
	return n
}

NormalizePathSingle :: proc(path: string) -> string {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	previous_slash := false
	for c in path {
		if c == '\\' || c == '/' {
			if !previous_slash {
				strings.write_byte(&b, '/')
				previous_slash = true
			}
		} else {
			strings.write_rune(&b, c)
			previous_slash = false
		}
	}
	return strings.to_string(b)
}

NormalizePathPair :: proc(a, b: string) -> string {
	bld := strings.builder_make()
	defer strings.builder_destroy(&bld)
	strings.write_string(&bld, a)
	strings.write_byte(&bld, '/')
	strings.write_string(&bld, b)
	return NormalizePathSingle(strings.to_string(bld))
}

NormalizePathTriple :: proc(a, b, c: string) -> string {
	bld := strings.builder_make()
	defer strings.builder_destroy(&bld)
	strings.write_string(&bld, a)
	strings.write_byte(&bld, '/')
	strings.write_string(&bld, b)
	strings.write_byte(&bld, '/')
	strings.write_string(&bld, c)
	return NormalizePathSingle(strings.to_string(bld))
}
NormalizePath :: proc {
	NormalizePathSingle,
	NormalizePathPair,
	NormalizePathTriple,
}

Swap :: proc(a, b: ^$T) {
	t := a^
	a^ = b^
	b^ = t
}

SmoothDamp :: proc(
	current, target: f32,
	velocity: ^f32,
	smooth_time, max_speed, delta_time: f32,
) -> f32 {
	st := math.max(0.0001, smooth_time)
	omega := 2 / st
	x := omega * delta_time
	exp := 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	change := current - target
	original := target
	max_change := max_speed * st
	change = Clamp(change, -max_change, max_change)
	adjusted_target := current - change
	temp := (velocity^ + omega * change) * delta_time
	velocity^ = (velocity^ - omega * temp) * exp
	output := adjusted_target + (change + temp) * exp
	if (original - current) * (output - original) > 0 {
		output = original
		velocity^ = (output - original) / delta_time
	}
	return output
}

tri_area :: proc(vertices: []Vec2) -> f32 {
	area: f32 = 0
	if len(vertices) < 3 {
		return 0
	}
	p := len(vertices) - 1
	for q := 0; q < len(vertices); q += 1 {
		area += vertices[p][0] * vertices[q][1] - vertices[q][0] * vertices[p][1]
		p = q
	}
	return area * 0.5
}

tri_inside :: proc(a, b, c, p: Vec2) -> bool {
	p0 := c - b
	p1 := a - c
	p2 := b - a
	ap := p - a
	bp := p - b
	cp := p - c
	return Cross(p0, bp) >= 0 && Cross(p2, ap) >= 0 && Cross(p1, cp) >= 0
}
// ------------------------------------------------------------------------------
// Utility / Calc / Triangulation — 多边形三角化
// ------------------------------------------------------------------------------

Triangulate :: proc(vertices: []Vec2, indices: ^[dynamic]int) {
	clear(indices)
	n := len(vertices)
	if n < 3 {
		return
	}
	v: [dynamic]int = {}
	defer delete(v)
	if tri_area(vertices) > 0 {
		for i := 0; i < n; i += 1 {
			append(&v, i)
		}
	} else {
		for i := 0; i < n; i += 1 {
			append(&v, n - 1 - i)
		}
	}
	nv := n
	count := 2 * nv
	m := nv - 1
	for nv > 2 {
		if count <= 0 {
			return
		}
		count -= 1
		u := m
		if u >= nv {
			u = 0
		}
		vv := u + 1
		if vv >= nv {
			vv = 0
		}
		w := vv + 1
		if w >= nv {
			w = 0
		}
		a := vertices[v[u]]
		b := vertices[v[vv]]
		c := vertices[v[w]]
		if Cross(b - a, c - a) > 0 {
			snip := true
			for p := 0; p < nv; p += 1 {
				if p == u || p == vv || p == w {
					continue
				}
				if tri_inside(a, b, c, vertices[v[p]]) {
					snip = false
					break
				}
			}
			if snip {
				append(&indices^, v[u], v[vv], v[w])
				for s, t := vv, vv + 1; t < nv; s, t = s + 1, t + 1 {
					v[s] = v[t]
				}
				nv -= 1
				count = 2 * nv
				m = vv
			} else {
				m = vv
			}
		} else {
			m = vv
		}
	}
}

// ==============================================================================
// Utility / Converters — JSON 数值转换
// ==============================================================================

Vector2Converter :: struct {}

Vector3Converter :: struct {}

Vector4Converter :: struct {}

Matrix3x2Converter :: struct {}

FloatVectorJsonConverter :: struct {
	Components: [][]string,
}

IntVectorJsonConverter :: struct {
	Components: [][]string,
}

FloatVectorToString :: proc(values: []f32) -> string {
	data, err := json.marshal(values)
	if err != nil {
		return ""
	}
	return string(data)
}

IntVectorToString :: proc(values: []int) -> string {
	data, err := json.marshal(values)
	if err != nil {
		return ""
	}
	return string(data)
}

// ------------------------------------------------------------------------------
// Utility / Converters / Read & Write — JSON 分量读写
// ------------------------------------------------------------------------------

vector_json_number :: proc(value: json.Value, $T: typeid) -> (T, bool) {
	number: f64
	#partial switch v in value {
	case json.Integer:
		number = f64(v)
	case json.Float:
		number = v
	case:
		return {}, false
	}
	when T == int {
		if math.floor(number) != number || number < -2147483648 || number > 2147483647 {
			return {}, false
		}
	}
	return T(number), true
}

vector_json_read :: proc(text: string, components: [][]string, values: []$T) -> bool {
	for i in 0 ..< len(values) {
		values[i] = {}
	}
	value, err := json.parse(text, spec = .JSON)
	if err != .None {
		return false
	}
	defer json.destroy_value(value)
	#partial switch v in value {
	case json.Array:
		index := 0
		for entry in v {
			if index >= len(values) {
				break
			}
			if number, ok := vector_json_number(entry, T); ok {
				values[index] = number
				index += 1
			}
		}
	case json.Object:
		for key, entry in v {
			for aliases, i in components {
				if i >= len(values) {
					break
				}
				for alias in aliases {
					if strings.equal_fold(key, alias) {
						if number, ok := vector_json_number(entry, T); ok {
							values[i] = number
						}
						break
					}
				}
			}
		}
	case:
		return false
	}
	return true
}

vector_json_write :: proc(components: [][]string, values: []$T) -> string {
	object := make(map[string]T)
	defer delete(object)
	for aliases, i in components {
		if i < len(values) && len(aliases) > 0 {
			object[aliases[0]] = values[i]
		}
	}
	data, err := json.marshal(object)
	if err != nil {
		return ""
	}
	return string(data)
}

FloatVectorJsonRead :: proc(
	converter: FloatVectorJsonConverter,
	text: string,
	values: []f32,
) -> bool {
	return vector_json_read(text, converter.Components, values)
}

FloatVectorJsonWrite :: proc(converter: FloatVectorJsonConverter, values: []f32) -> string {
	return vector_json_write(converter.Components, values)
}

IntVectorJsonRead :: proc(converter: IntVectorJsonConverter, text: string, values: []int) -> bool {
	return vector_json_read(text, converter.Components, values)
}

IntVectorJsonWrite :: proc(converter: IntVectorJsonConverter, values: []int) -> string {
	return vector_json_write(converter.Components, values)
}

Vector2FromJson :: proc(text: string) -> (Vec2, bool) {
	v: Vec2
	ok := vector_json_read(text, {{"X"}, {"Y"}}, v[:])
	return v, ok
}

Vector3FromJson :: proc(text: string) -> ([3]f32, bool) {
	v: [3]f32
	ok := vector_json_read(text, {{"X"}, {"Y"}, {"Z"}}, v[:])
	return v, ok
}

Vector4FromJson :: proc(text: string) -> ([4]f32, bool) {
	v: [4]f32
	ok := vector_json_read(text, {{"X"}, {"Y"}, {"Z"}, {"W"}}, v[:])
	return v, ok
}

Vector2ToJson :: proc(v: Vec2) -> string {
	values := v
	return vector_json_write({{"X"}, {"Y"}}, values[:])
}

Vector3ToJson :: proc(v: [3]f32) -> string {
	values := v
	return vector_json_write({{"X"}, {"Y"}, {"Z"}}, values[:])
}

Vector4ToJson :: proc(v: [4]f32) -> string {
	values := v
	return vector_json_write({{"X"}, {"Y"}, {"Z"}, {"W"}}, values[:])
}

Matrix3x2FromJson :: proc(text: string) -> (Matrix3x2, bool) {
	values: [6]f32
	value, err := json.parse(text, spec = .JSON)
	if err != .None {
		return {}, false
	}
	defer json.destroy_value(value)
	array, ok := value.(json.Array)
	if !ok {
		return {}, false
	}
	index := 0
	for entry in array {
		if index >= len(values) {
			break
		}
		if number, valid := vector_json_number(entry, f32); valid {
			values[index] = number
			index += 1
		}
	}
	return {values[0], values[1], values[2], values[3], values[4], values[5]}, true
}

Matrix3x2ToJson :: proc(v: Matrix3x2) -> string {
	values := [6]f32{v.M11, v.M12, v.M21, v.M22, v.M31, v.M32}
	return FloatVectorToString(values[:])
}

// ==============================================================================
// Utility / Ease — 缓动
// ==============================================================================
Easer :: #type proc(t: f32) -> f32

Ease :: struct {
	In, Out, InOut: Easer,
}

EaseApply :: proc(ease: Ease, t: f32) -> f32 {
	if t <= 0 {
		return 0
	}
	if t >= 1 {
		return 1
	}
	if ease.InOut != nil {
		return ease.InOut(t)
	}
	if ease.In == nil {
		return t
	}
	out := ease.Out
	if t <= .5 {
		return ease.In(t * 2) * .5
	}
	if out != nil {
		return out(t * 2 - 1) * .5 + .5
	}
	return 1 - ease.In(2 - t * 2) * .5
}

EaseInvert :: proc(easer: Easer, t: f32) -> f32 {
	return 1 - easer(1 - t)
}

EaseFollow :: proc(first, second: Easer, t: f32) -> f32 {
	if t <= .5 {
		return first(t * 2) * .5
	}
	return second(t * 2 - 1) * .5 + .5
}
EaseUpDown :: YoYo

InCube :: proc(t: f32) -> f32 {
	return t * t * t
}

InQuart :: proc(t: f32) -> f32 {
	return t * t * t * t
}

InQuint :: proc(t: f32) -> f32 {
	return t * t * t * t * t
}

InExpo :: proc(t: f32) -> f32 {
	return math.pow(f32(2), 10 * (t - 1))
}

InBack :: proc(t: f32) -> f32 {
	return t * t * (2.70158 * t - 1.70158)
}

InBigBack :: proc(t: f32) -> f32 {
	return t * t * (4 * t - 3)
}

InElastic :: proc(t: f32) -> f32 {
	s := t * t
	c := s * t
	return 33 * c * s - 59 * s * s + 32 * c - 5 * s
}

OutElastic :: proc(t: f32) -> f32 {
	s := t * t
	c := s * t
	return 33 * c * s - 106 * s * s + 126 * c - 67 * s + 15 * t
}

OutBounce :: proc(t: f32) -> f32 {
	if t < 1 / 2.75 {
		return 7.5625 * t * t
	}
	if t < 2 / 2.75 {
		x := t - 1.5 / 2.75
		return 7.5625 * x * x + .75
	}
	if t < 2.5 / 2.75 {
		x := t - 2.25 / 2.75
		return 7.5625 * x * x + .9375
	}
	x := t - 2.625 / 2.75
	return 7.5625 * x * x + .984375
}

InBounce :: proc(t: f32) -> f32 {
	return 1 - OutBounce(1 - t)
}
EaseQuad :: Ease {
	In    = InQuad,
	Out   = OutQuad,
	InOut = InOutQuad,
}

OutCube :: proc(t: f32) -> f32 {
	return EaseInvert(InCube, t)
}

InOutCube :: proc(t: f32) -> f32 {
	return EaseFollow(InCube, OutCube, t)
}
EaseCube :: Ease {
	In    = InCube,
	Out   = OutCube,
	InOut = InOutCube,
}

OutQuart :: proc(t: f32) -> f32 {
	return EaseInvert(InQuart, t)
}

InOutQuart :: proc(t: f32) -> f32 {
	return EaseFollow(InQuart, OutQuart, t)
}
EaseQuart :: Ease {
	In    = InQuart,
	Out   = OutQuart,
	InOut = InOutQuart,
}

OutQuint :: proc(t: f32) -> f32 {
	return EaseInvert(InQuint, t)
}

InOutQuint :: proc(t: f32) -> f32 {
	return EaseFollow(InQuint, OutQuint, t)
}
EaseQuint :: Ease {
	In    = InQuint,
	Out   = OutQuint,
	InOut = InOutQuint,
}
EaseSine :: Ease {
	In    = SineIn,
	Out   = SineOut,
	InOut = SineInOut,
}

OutExpo :: proc(t: f32) -> f32 {
	return EaseInvert(InExpo, t)
}

InOutExpo :: proc(t: f32) -> f32 {
	return EaseFollow(InExpo, OutExpo, t)
}
EaseExpo :: Ease {
	In    = InExpo,
	Out   = OutExpo,
	InOut = InOutExpo,
}

OutBack :: proc(t: f32) -> f32 {
	return EaseInvert(InBack, t)
}

InOutBack :: proc(t: f32) -> f32 {
	return EaseFollow(InBack, OutBack, t)
}
EaseBack :: Ease {
	In    = InBack,
	Out   = OutBack,
	InOut = InOutBack,
}

OutBigBack :: proc(t: f32) -> f32 {
	return EaseInvert(InBigBack, t)
}

InOutBigBack :: proc(t: f32) -> f32 {
	return EaseFollow(InBigBack, OutBigBack, t)
}
EaseBigBack :: Ease {
	In    = InBigBack,
	Out   = OutBigBack,
	InOut = InOutBigBack,
}

InOutElastic :: proc(t: f32) -> f32 {
	return EaseFollow(InElastic, OutElastic, t)
}
EaseElastic :: Ease {
	In    = InElastic,
	Out   = OutElastic,
	InOut = InOutElastic,
}

InOutBounce :: proc(t: f32) -> f32 {
	return EaseFollow(InBounce, OutBounce, t)
}
EaseBounce :: Ease {
	In    = InBounce,
	Out   = OutBounce,
	InOut = InOutBounce,
}

Linear :: proc(t: f32) -> f32 {
	return t
}

InQuad :: proc(t: f32) -> f32 {
	return t * t
}

OutQuad :: proc(t: f32) -> f32 {
	return t * (2 - t)
}

InOutQuad :: proc(t: f32) -> f32 {
	if t < 0.5 {
		return 2 * t * t
	}
	return -1 + (4 - 2 * t) * t
}

SineIn :: proc(t: f32) -> f32 {
	return 1 - math.cos(t * f32(math.PI) * 0.5)
}

SineOut :: proc(t: f32) -> f32 {
	return math.sin(t * f32(math.PI) * 0.5)
}

SineInOut :: proc(t: f32) -> f32 {
	return -(math.cos(f32(math.PI) * t) - 1) * 0.5
}

// ==============================================================================
// Utility / Log — 日志
// ==============================================================================

LogState :: struct {
	History:   [dynamic]string,
	OnInfo:    proc(msg: string),
	OnWarning: proc(msg: string),
	OnError:   proc(msg: string),
}

log_append :: proc(state: ^LogState, message: string) {
	append(&state.History, message)
}

LogInfo :: proc(state: ^LogState, message: string) {
	log_append(state, message)
	if state.OnInfo != nil {
		state.OnInfo(message)
	} else {
		fmt.println(message)
	}
}

LogWarning :: proc(state: ^LogState, message: string) {
	log_append(state, message)
	if state.OnWarning != nil {
		state.OnWarning(message)
	} else {
		fmt.println(message)
	}
}

LogError :: proc(state: ^LogState, message: string) {
	log_append(state, message)
	if state.OnError != nil {
		state.OnError(message)
	} else {
		fmt.println(message)
	}
}

LogClearHistory :: proc(state: ^LogState) {
	clear(&state.History)
}

LogHistory :: proc(state: ^LogState) -> []string {
	return state.History[:]
}

// ==============================================================================
// Utility / Pool — 对象池
// ==============================================================================

Pool :: struct($T: typeid) {
	Available: [dynamic]T,
}

PoolGet :: proc(pool: ^Pool($T)) -> T {
	if len(pool.Available) > 0 {
		n := len(pool.Available) - 1
		v := pool.Available[n]
		resize(&pool.Available, n)
		return v
	}
	return T{}
}

PoolReturn :: proc(pool: ^Pool($T), value: T) {
	append(&pool.Available, value)
}
PoolRecycle :: PoolReturn

PoolClear :: proc(pool: ^Pool($T)) {
	clear(&pool.Available)
}
IPoolable :: #type proc(value: rawptr)

// ==============================================================================
// Utility / Rng — 随机数
// ==============================================================================

Rng :: struct {
	Seed: u64,
}

RngMake :: proc(seed: u64) -> Rng {
	return Rng{Seed = seed}
}

RngU64 :: proc(r: ^Rng) -> u64 {
	r.Seed += 0x9e3779b97f4a7c15
	n := r.Seed
	n = (n ~ (n >> 30)) * 0xbf58476d1ce4e5b9
	n = (n ~ (n >> 27)) * 0x94d049bb133111eb
	return n ~ (n >> 31)
}

RngU64Max :: proc(r: ^Rng, max: u64) -> u64 {
	if max == 0 {
		return 0
	}
	return RngU64(r) % max
}

RngU64Range :: proc(r: ^Rng, min, max: u64) -> u64 {
	return min + RngU64Max(r, max - min)
}

RngU32 :: proc(r: ^Rng) -> u32 {
	return u32(RngU64(r))
}

RngU32Max :: proc(r: ^Rng, max: u32) -> u32 {
	if max == 0 {
		return 0
	}
	return RngU32(r) % max
}

RngU32Range :: proc(r: ^Rng, min, max: u32) -> u32 {
	return min + RngU32Max(r, max - min)
}

RngInt :: proc(r: ^Rng) -> int {
	return int(i32(RngU32(r)))
}

RngIntMax :: proc(r: ^Rng, max: int) -> int {
	if max <= 0 {
		return 0
	}
	return int(RngU32(r) % u32(max))
}

RngIntRange :: proc(r: ^Rng, min, max: int) -> int {
	return min + RngIntMax(r, max - min)
}

RngFloat :: proc(r: ^Rng) -> f32 {
	bits := u32(0x3f800000 | (RngU64(r) >> 40))
	return transmute(f32)bits - 1
}

RngFloatMax :: proc(r: ^Rng, max: f32) -> f32 {
	return RngFloat(r) * max
}

RngFloatRange :: proc(r: ^Rng, min, max: f32) -> f32 {
	return min + RngFloatMax(r, max - min)
}

RngDouble :: proc(r: ^Rng) -> f64 {
	bits := u64(0x3ff0000000000000 | (RngU64(r) >> 11))
	return transmute(f64)bits - 1
}

RngDoubleMax :: proc(r: ^Rng, max: f64) -> f64 {
	return RngDouble(r) * max
}

RngDoubleRange :: proc(r: ^Rng, min, max: f64) -> f64 {
	return min + RngDoubleMax(r, max - min)
}

RngU16 :: proc(r: ^Rng) -> u16 {
	return u16(RngU64(r))
}

RngU16Max :: proc(r: ^Rng, max: u16) -> u16 {
	if max == 0 {
		return 0
	}
	return RngU16(r) % max
}

RngU16Range :: proc(r: ^Rng, min, max: u16) -> u16 {
	return min + RngU16Max(r, max - min)
}

RngU8 :: proc(r: ^Rng) -> u8 {
	return u8(RngU64(r))
}

RngU8Max :: proc(r: ^Rng, max: u8) -> u8 {
	if max == 0 {
		return 0
	}
	return RngU8(r) % max
}

RngU8Range :: proc(r: ^Rng, min, max: u8) -> u8 {
	return min + RngU8Max(r, max - min)
}

RngLong :: proc(r: ^Rng) -> i64 {
	return i64(RngU64(r))
}

RngLongMax :: proc(r: ^Rng, max: i64) -> i64 {
	if max <= 0 {
		return 0
	}
	return i64(RngU64(r) % u64(max))
}

RngLongRange :: proc(r: ^Rng, min, max: i64) -> i64 {
	return min + RngLongMax(r, max - min)
}

RngShort :: proc(r: ^Rng) -> i16 {
	return i16(RngU64(r))
}

RngShortMax :: proc(r: ^Rng, max: i16) -> i16 {
	if max <= 0 {
		return 0
	}
	return i16(math.abs(i32(RngShort(r))) % i32(max))
}

RngShortRange :: proc(r: ^Rng, min, max: i16) -> i16 {
	if max <= min {
		return min
	}
	return i16(i32(min) + math.abs(i32(RngShort(r))) % (i32(max) - i32(min)))
}

RngSByte :: proc(r: ^Rng) -> i8 {
	return i8(RngU64(r))
}

RngSByteMax :: proc(r: ^Rng, max: i8) -> i8 {
	if max <= 0 {
		return 0
	}
	return i8(math.abs(i16(RngSByte(r))) % i16(max))
}

RngSByteRange :: proc(r: ^Rng, min, max: i8) -> i8 {
	if max <= min {
		return min
	}
	return i8(i16(min) + math.abs(i16(RngSByte(r))) % (i16(max) - i16(min)))
}

RngShake :: proc(r: ^Rng) -> Point2 {
	return {RngIntRange(r, -1, 2), RngIntRange(r, -1, 2)}
}

RngSign :: proc(r: ^Rng) -> Signs {
	if RngBoolean(r) {
		return .Positive
	}
	return .Negative
}

RngBoolean :: proc(r: ^Rng) -> bool {
	return (RngU64(r) & 1) != 0
}

RngChance :: proc(r: ^Rng, p: f32) -> bool {
	return RngFloat(r) < p
}

RngChanceDouble :: proc(r: ^Rng, p: f64) -> bool {
	return RngDouble(r) < p
}

RngAngle :: proc(r: ^Rng) -> f32 {
	return RngFloatMax(r, f32(math.TAU))
}

rng_spread_around :: proc(r: ^Rng, angle, spread: f32) -> f32 {
	return angle + RngFloatRange(r, -spread, spread)
}

rng_spread_width :: proc(r: ^Rng, spread: f32) -> f32 {
	return RngFloat(r) * spread - spread / 2
}
RngSpread :: proc {
	rng_spread_around,
	rng_spread_width,
}

RngChoose :: proc(r: ^Rng, choices: []$T) -> T {
	if len(choices) == 0 {
		return {}
	}
	return choices[RngIntMax(r, len(choices))]
}

RngShuffle :: proc(r: ^Rng, values: []$T) {
	for i := len(values) - 1; i > 0; i -= 1 {
		j := RngIntMax(r, i + 1)
		values[i], values[j] = values[j], values[i]
	}
}

RngPointInside :: proc(r: ^Rng, rect: Rect) -> Vec2 {
	return RectOn(rect, RngFloat(r), RngFloat(r))
}

// ==============================================================================
// Utility / StackList — 固定容量集合
// ==============================================================================

StackList4 :: struct($T: typeid) {
	Data:  [4]T,
	Count: int,
}

StackList8 :: struct($T: typeid) {
	Data:  [8]T,
	Count: int,
}

StackList16 :: struct($T: typeid) {
	Data:  [16]T,
	Count: int,
}

StackList32 :: struct($T: typeid) {
	Data:  [32]T,
	Count: int,
}

StackList64 :: struct($T: typeid) {
	Data:  [64]T,
	Count: int,
}

stack_add :: proc(list: ^$L, value: $T) where intrinsics.type_is_struct(L) {
	if list.Count >= len(list.Data) {
		panic("Exceeding Capacity of StackList")
	}
	list.Data[list.Count] = value
	list.Count += 1
}

StackList4Add :: proc(list: ^StackList4($T), value: T) {
	stack_add(list, value)
}

StackList8Add :: proc(list: ^StackList8($T), value: T) {
	stack_add(list, value)
}

StackList16Add :: proc(list: ^StackList16($T), value: T) {
	stack_add(list, value)
}

StackList32Add :: proc(list: ^StackList32($T), value: T) {
	stack_add(list, value)
}

StackList64Add :: proc(list: ^StackList64($T), value: T) {
	stack_add(list, value)
}

StackList4Clear :: proc(list: ^StackList4($T)) {
	StackListClear(list)
}

StackList8Clear :: proc(list: ^StackList8($T)) {
	StackListClear(list)
}

StackList16Clear :: proc(list: ^StackList16($T)) {
	StackListClear(list)
}

StackList32Clear :: proc(list: ^StackList32($T)) {
	StackListClear(list)
}

StackList64Clear :: proc(list: ^StackList64($T)) {
	StackListClear(list)
}

// ------------------------------------------------------------------------------
// Utility / StackList / Operations — 各容量共用的集合操作
// ------------------------------------------------------------------------------

StackListAdd :: stack_add

StackListClear :: proc(list: ^$L) where intrinsics.type_is_struct(L) {
	for i in 0 ..< list.Count {
		list.Data[i] = {}
	}
	list.Count = 0
}

StackListIndexOf :: proc(list: ^$L, value: $T) -> int where intrinsics.type_is_struct(L) {
	for i in 0 ..< list.Count {
		if list.Data[i] == value {
			return i
		}
	}
	return -1
}

StackListContains :: proc(list: ^$L, value: $T) -> bool where intrinsics.type_is_struct(L) {
	return StackListIndexOf(list, value) >= 0
}

StackListInsert :: proc(list: ^$L, index: int, value: $T) where intrinsics.type_is_struct(L) {
	assert(index >= 0 && index <= list.Count)
	assert(list.Count < len(list.Data), "Exceeding Capacity of StackList")
	for i := list.Count; i > index; i -= 1 {
		list.Data[i] = list.Data[i - 1]
	}
	list.Data[index] = value
	list.Count += 1
}

StackListRemoveAt :: proc(list: ^$L, index: int) where intrinsics.type_is_struct(L) {
	assert(index >= 0 && index < list.Count)
	for i := index; i < list.Count - 1; i += 1 {
		list.Data[i] = list.Data[i + 1]
	}
	list.Count -= 1
	list.Data[list.Count] = {}
}

StackListRemove :: proc(list: ^$L, value: $T) -> bool where intrinsics.type_is_struct(L) {
	index := StackListIndexOf(list, value)
	if index < 0 {
		return false
	}
	StackListRemoveAt(list, index)
	return true
}

StackListCopyTo :: proc(
	list: ^$L,
	destination: []$T,
	offset: int = 0,
) where intrinsics.type_is_struct(L) {
	assert(offset >= 0 && offset <= len(destination) && list.Count <= len(destination) - offset)
	copy(destination[offset:], list.Data[:list.Count])
}

// ==============================================================================
// Utility / TriangulationEnumerator — 三角化枚举
// ==============================================================================

TriangulationEnumerable :: struct {
	Vertices:  []Vec2,
	Triangles: []int,
}

TriangulationEnumerableMake :: proc(
	vertices: []Vec2,
	triangles: []int,
) -> TriangulationEnumerable {
	return TriangulationEnumerable{vertices, triangles}
}

// Owned 返回动态数组，由调用方 delete；Pooled 使用 temp_allocator，失效时间由其清理决定。

TriangulateOwned :: proc(vertices: []Vec2, allocator := context.allocator) -> [dynamic]int {
	indices := make([dynamic]int, allocator)
	Triangulate(vertices, &indices)
	return indices
}

TriangulatePooled :: proc(vertices: []Vec2) -> []int {
	return TriangulateOwned(vertices, context.temp_allocator)[:]
}

TriangulateAndEnumerate :: proc(
	vertices: []Vec2,
	indices: ^[dynamic]int,
) -> TriangulationEnumerable {
	Triangulate(vertices, indices)
	return {vertices, indices[:]}
}

TriangulateAndEnumeratePooled :: proc(vertices: []Vec2) -> TriangulationEnumerable {
	return {vertices, TriangulatePooled(vertices)}
}

TriangulationEnumerator :: struct {
	Vertices:  []Vec2,
	Triangles: []int,
	Index:     int,
	Current:   Triangle,
}

TriangulationEnumeratorGet :: proc(value: TriangulationEnumerable) -> TriangulationEnumerator {
	return TriangulationEnumerator {
		Vertices  = value.Vertices,
		Triangles = value.Triangles,
		Index     = -3,
	}
}

TriangulationMoveNext :: proc(e: ^TriangulationEnumerator) -> bool {
	e.Index += 3
	if e.Index + 2 >= len(e.Triangles) {
		return false
	}
	e.Current = Triangle {
		e.Vertices[e.Triangles[e.Index]],
		e.Vertices[e.Triangles[e.Index + 1]],
		e.Vertices[e.Triangles[e.Index + 2]],
	}
	return true
}

// ==============================================================================
// Extensions — 扩展函数
// ==============================================================================

EnumHas :: proc(flags, check: $T) -> bool {
	return (flags & check) != 0
}

EnumHasAll :: proc(flags, check: $T) -> bool {
	return (flags & check) == check
}

EnumWith :: proc(flags, value: $T) -> T {
	return flags | value
}

EnumWithout :: proc(flags, value: $T) -> T {
	return flags & ~value
}

EnumMask :: proc(flags, value: $T, condition: bool) -> T {
	if condition {
		return EnumWith(flags, value)
	}
	return EnumWithout(flags, value)
}

// ==============================================================================
// Extensions / Numbers — 数值解析
// ==============================================================================

NumberHas :: proc(flags, check: $T) -> bool {
	return (flags & check) != 0
}

NumberHasAll :: proc(flags, check: $T) -> bool {
	return (flags & check) == check
}

NumberWith :: proc(flags, value: $T) -> T {
	return flags | value
}

NumberWithout :: proc(flags, value: $T) -> T {
	return flags & ~value
}

NumberMask :: proc(flags, value: $T, condition: bool) -> T {
	if condition {
		return flags | value
	}
	return flags & ~value
}

// ==============================================================================
// Extensions / Numerics — 向量与四元数
// ==============================================================================
// Quaternion mirrors System.Numerics.Quaternion for callers that need the
// small set of orientation helpers exposed by Foster's numerics extensions.

// System.Numerics.Vector128<int> 的点转换以固定四分量 i32 数组表达。

AsPoint2 :: proc(vector: [4]i32) -> Point2 {
	return {int(vector[0]), int(vector[1])}
}

AsPoint3 :: proc(vector: [4]i32) -> Point3 {
	return {int(vector[0]), int(vector[1]), int(vector[2])}
}

Quaternion :: struct {
	X, Y, Z, W: f32,
}

QuaternionConjugated :: proc(q: Quaternion) -> Quaternion {
	return Quaternion{-q.X, -q.Y, -q.Z, q.W}
}

quaternion_from_basis :: proc(right, up, forward: Vec3) -> Quaternion {
	// Convert an orthonormal 3x3 basis to a quaternion (trace-stable form).
	trace := right[0] + up[1] + forward[2]
	if trace > 0 {
		s := math.sqrt(trace + 1) * 2
		return Quaternion {
			(up[2] - forward[1]) / s,
			(forward[0] - right[2]) / s,
			(right[1] - up[0]) / s,
			0.25 * s,
		}
	}
	if right[0] > up[1] && right[0] > forward[2] {
		s := math.sqrt(1 + right[0] - up[1] - forward[2]) * 2
		return Quaternion {
			0.25 * s,
			(right[1] + up[0]) / s,
			(forward[0] + right[2]) / s,
			(up[2] - forward[1]) / s,
		}
	}
	if up[1] > forward[2] {
		s := math.sqrt(1 + up[1] - right[0] - forward[2]) * 2
		return Quaternion {
			(right[1] + up[0]) / s,
			0.25 * s,
			(up[2] + forward[1]) / s,
			(forward[0] - right[2]) / s,
		}
	}
	s := math.sqrt(1 + forward[2] - right[0] - up[1]) * 2
	return Quaternion {
		(forward[0] + right[2]) / s,
		(up[2] + forward[1]) / s,
		0.25 * s,
		(right[1] - up[0]) / s,
	}
}

QuaternionLookAtDirection :: proc(direction, up: Vec3) -> Quaternion {
	forward := Vec3Normalized(direction, Vec3{0, 0, -1})
	right := Vec3Normalized(Vec3Cross(up, forward), Vec3{1, 0, 0})
	true_up := Vec3Cross(forward, right)
	return quaternion_from_basis(right, true_up, forward)
}

QuaternionLookAt :: proc(from, to, up: Vec3) -> Quaternion {
	return QuaternionLookAtDirection(Vec3{to[0] - from[0], to[1] - from[1], to[2] - from[2]}, up)
}

Vec3Cross :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}
}

// ------------------------------------------------------------------------------
// Extensions / Numerics / Vector2 — 二维向量助手
// ------------------------------------------------------------------------------

Vec2Clamp :: proc(v, min, max: Vec2) -> Vec2 {
	return Vec2{math.clamp(v[0], min[0], max[0]), math.clamp(v[1], min[1], max[1])}
}

Vec2Normalized :: proc(v: Vec2, fallback: Vec2 = {}) -> Vec2 {
	l2 := v[0] * v[0] + v[1] * v[1]
	if l2 == 0 {
		return fallback
	}
	inv := 1 / math.sqrt(l2)
	return Vec2{v[0] * inv, v[1] * inv}
}

Vec2ClampRect :: proc(v: Vec2, bounds: Rect) -> Vec2 {
	return Vec2Clamp(v, RectMin(bounds), RectMax(bounds))
}

Vec2Floor :: proc(v: Vec2) -> Vec2 {
	return Vec2{math.floor(v[0]), math.floor(v[1])}
}

Vec2Round :: proc(v: Vec2) -> Vec2 {
	return Vec2{math.round(v[0]), math.round(v[1])}
}

Vec2Ceiling :: proc(v: Vec2) -> Vec2 {
	return Vec2{math.ceil(v[0]), math.ceil(v[1])}
}

Vec2RoundToPoint2 :: proc(v: Vec2) -> Point2 {
	return Point2{int(math.round(v[0])), int(math.round(v[1]))}
}

Vec2FloorToPoint2 :: proc(v: Vec2) -> Point2 {
	return Point2{int(math.floor(v[0])), int(math.floor(v[1]))}
}

Vec2CeilingToPoint2 :: proc(v: Vec2) -> Point2 {
	return Point2{int(math.ceil(v[0])), int(math.ceil(v[1]))}
}

Vec2TurnRight :: proc(v: Vec2) -> Vec2 {
	return Vec2{-v[1], v[0]}
}

Vec2TurnLeft :: proc(v: Vec2) -> Vec2 {
	return Vec2{v[1], -v[0]}
}

Vec2Angle :: proc(v: Vec2) -> f32 {
	return math.atan2(v[1], v[0])
}

Vec2LengthSquared :: proc(v: Vec2) -> f32 {
	return v[0] * v[0] + v[1] * v[1]
}

Vec2LengthLessThan :: proc(v: Vec2, length: f32) -> bool {
	return Vec2LengthSquared(v) < length * length
}

Vec2GetLengthAndNormalize :: proc(v: Vec2, fallback: Vec2 = {}) -> (Vec2, f32) {
	l2 := Vec2LengthSquared(v)
	if l2 == 0 {
		return fallback, 0
	}
	l := math.sqrt(l2)
	return Vec2{v[0] / l, v[1] / l}, l
}

Vec2FourWayNormal :: proc(v: Vec2, fallback: Vec2 = {}) -> Vec2 {
	if v == {} {
		return fallback
	}
	a := math.round(Vec2Angle(v) / (math.PI * 0.5)) * (math.PI * 0.5)
	r := Vec2{math.cos(a), math.sin(a)}
	if math.abs(r[0]) < .1 {
		r[0] = 0
		r[1] = math.sign(r[1])
	}
	if math.abs(r[1]) < .1 {
		r[1] = 0
		r[0] = math.sign(r[0])
	}
	return r
}

Vec2EightWayNormal :: proc(v: Vec2, fallback: Vec2 = {}) -> Vec2 {
	if v == {} {
		return fallback
	}
	a := math.round(Vec2Angle(v) / (math.PI * 0.25)) * (math.PI * 0.25)
	r := Vec2{math.cos(a), math.sin(a)}
	if math.abs(r[0]) < .1 {
		r[0] = 0
		r[1] = math.sign(r[1])
	}
	if math.abs(r[1]) < .1 {
		r[1] = 0
		r[0] = math.sign(r[0])
	}
	return r
}

Vec2Abs :: proc(v: Vec2) -> Vec2 {
	return Vec2{math.abs(v[0]), math.abs(v[1])}
}

Vec2ZeroX :: proc(v: Vec2) -> Vec2 {
	return Vec2{0, v[1]}
}

Vec2ZeroY :: proc(v: Vec2) -> Vec2 {
	return Vec2{v[0], 0}
}

Vec2IsSmallerThan :: proc(a, b: Vec2) -> bool {
	return Vec2LengthSquared(a) < Vec2LengthSquared(b)
}

Vec2Map :: proc(v: Vec2, from_bounds, to_bounds: Rect) -> Vec2 {
	return Vec2 {
		((v[0] - from_bounds.X) / from_bounds.Width) * to_bounds.Width + to_bounds.X,
		((v[1] - from_bounds.Y) / from_bounds.Height) * to_bounds.Height + to_bounds.Y,
	}
}

Vec3Normalized :: proc(v: Vec3, fallback: Vec3 = {}) -> Vec3 {
	l2 := v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
	if l2 == 0 {
		return fallback
	}
	l := math.sqrt(l2)
	return Vec3{v[0] / l, v[1] / l, v[2] / l}
}

Vec3XY :: proc(v: Vec3) -> Vec2 {
	return Vec2{v[0], v[1]}
}

Vec3WithXY :: proc(v: Vec3, xy: Vec2) -> Vec3 {
	return Vec3{xy[0], xy[1], v[2]}
}

Vec3Round :: proc(v: Vec3) -> Vec3 {
	return Vec3{math.round(v[0]), math.round(v[1]), math.round(v[2])}
}

Vec3Floor :: proc(v: Vec3) -> Vec3 {
	return Vec3{math.floor(v[0]), math.floor(v[1]), math.floor(v[2])}
}

Vec3Ceiling :: proc(v: Vec3) -> Vec3 {
	return Vec3{math.ceil(v[0]), math.ceil(v[1]), math.ceil(v[2])}
}

Vec3RoundToPoint3 :: proc(v: Vec3) -> Point3 {
	return Point3{int(math.round(v[0])), int(math.round(v[1])), int(math.round(v[2]))}
}

Vec3FloorToPoint3 :: proc(v: Vec3) -> Point3 {
	return Point3{int(math.floor(v[0])), int(math.floor(v[1])), int(math.floor(v[2]))}
}

Vec3CeilingToPoint3 :: proc(v: Vec3) -> Point3 {
	return Point3{int(math.ceil(v[0])), int(math.ceil(v[1])), int(math.ceil(v[2]))}
}

Vec4 :: [4]f32

Vec4Round :: proc(v: Vec4) -> Vec4 {
	return Vec4{math.round(v[0]), math.round(v[1]), math.round(v[2]), math.round(v[3])}
}

Vec4Floor :: proc(v: Vec4) -> Vec4 {
	return Vec4{math.floor(v[0]), math.floor(v[1]), math.floor(v[2]), math.floor(v[3])}
}

Vec4Ceiling :: proc(v: Vec4) -> Vec4 {
	return Vec4{math.ceil(v[0]), math.ceil(v[1]), math.ceil(v[2]), math.ceil(v[3])}
}

Matrix3x2XScaleFast :: proc(m: Matrix3x2) -> f32 {
	return m.M11
}

Matrix3x2YScaleFast :: proc(m: Matrix3x2) -> f32 {
	return m.M22
}

Matrix3x2ScaleFast :: proc(m: Matrix3x2) -> Vec2 {
	return Vec2{m.M11, m.M22}
}

Matrix3x2XScale :: proc(m: Matrix3x2) -> f32 {
	return math.sqrt(m.M11 * m.M11 + m.M21 * m.M21)
}

Matrix3x2YScale :: proc(m: Matrix3x2) -> f32 {
	return math.sqrt(m.M12 * m.M12 + m.M22 * m.M22)
}

Matrix3x2Scale :: proc(m: Matrix3x2) -> Vec2 {
	return Vec2{Matrix3x2XScale(m), Matrix3x2YScale(m)}
}

// ==============================================================================
// Extensions / TimeSpan — 时间转换
// ==============================================================================

DurationModulo :: proc(value: coretime.Duration, seconds: f64) -> coretime.Duration {
	if seconds <= 0 {
		return 0
	}
	period := coretime.Duration(seconds * 1e9)
	return value % period
}

DurationLerp :: proc(value: coretime.Duration, seconds: f64) -> f32 {
	if seconds <= 0 {
		return 0
	}
	return f32(coretime.duration_seconds(DurationModulo(value, seconds)) / seconds)
}

DurationYoyo :: proc(value: coretime.Duration, seconds: f64) -> f32 {
	t := DurationLerp(value, seconds) * 2
	if t > 1 {
		return f32(2 - t)
	}
	return f32(t)
}

DurationSin :: proc(value: coretime.Duration, rate := f64(1), offset := f64(0)) -> f32 {
	return f32(math.sin(coretime.duration_seconds(value) * rate + offset))
}

DurationCos :: proc(value: coretime.Duration, rate := f64(1), offset := f64(0)) -> f32 {
	return f32(math.cos(coretime.duration_seconds(value) * rate + offset))
}

// ==============================================================================
// Utility / Calc / Intervals & Collections — 区间与集合助手
// ==============================================================================

DifferenceFromInterval :: proc(value, interval: f32) -> f32 {
	assert(interval > 0)
	v := math.mod(value, interval)
	if v < 0 {
		v += interval
	}
	if v < interval * .5 {
		return -v
	}
	return interval - v
}

IndexOfSmallest :: proc(values: []$T) -> int {
	if len(values) == 0 {
		return -1
	}
	best := 0
	for i in 1 ..< len(values) {
		if values[i] < values[best] {
			best = i
		}
	}
	return best
}

IndexOfLargest :: proc(values: []$T) -> int {
	if len(values) == 0 {
		return -1
	}
	best := 0
	for i in 1 ..< len(values) {
		if values[i] > values[best] {
			best = i
		}
	}
	return best
}

ApproachAlongAxis :: proc(from, target, axis_normal: Vec2, max_delta: f32) -> Vec2 {
	return ApproachVec2(from, from + axis_normal * vec2_dot(target - from, axis_normal), max_delta)
}

IntervalCount :: proc(elapsed, delta, interval: f64, offset: f64 = 0) -> int {
	assert(interval > 0)
	return int(
		math.floor((elapsed - offset) / interval) -
		math.floor((elapsed - offset - delta) / interval),
	)
}

CycleInterval :: proc(elapsed, interval: f64, options: []$T, offset: f64 = 0) -> T {
	assert(interval > 0 && len(options) > 0)
	index := int((elapsed - offset) / interval) % len(options)
	if index < 0 {
		index += len(options)
	}
	return options[index]
}

StaticStringHashUInt64 :: proc(value: string) -> u64 {
	hash := u64(104729)
	// Match the upstream UTF-8 byte overload.
	for byte in transmute([]u8)value {
		hash = (hash << 7) + hash + u64(byte)
	}
	return hash
}

TryFirst :: proc(values: []$T) -> (T, bool) {
	if len(values) == 0 {
		return {}, false
	}
	return values[0], true
}
// ==============================================================================
// Utility / Log / Callbacks — 回调与历史
// ==============================================================================

LogSetCallbacks :: proc(state: ^LogState, info, warning, error: proc(message: string)) {
	state.OnInfo = info
	state.OnWarning = warning
	state.OnError = error
}
LogGetHistory :: LogHistory
// ==============================================================================
// Utility / Rng / Collections — 集合选择与时间种子
// ==============================================================================

RngChooseAndRemove :: proc(rng: ^Rng, values: ^[dynamic]$T) -> T {
	assert(len(values) > 0)
	index := RngIntMax(rng, len(values))
	result := values^[index]
	for i in index ..< len(values) - 1 {
		values^[i] = values^[i + 1]
	}
	resize(values, len(values) - 1)
	return result
}

rng_randomized_copy :: proc(rng: ^Rng, values: []$T) -> [dynamic]T {
	result := make([dynamic]T, 0, len(values))
	append(&result, ..values)
	RngShuffle(rng, result[:])
	return result
}

rng_randomized_make :: proc() -> Rng {
	return RngMake(u64(coretime.to_unix_nanoseconds(coretime.now())))
}
RngRandomized :: proc {
	rng_randomized_make,
	rng_randomized_copy,
}
// ==============================================================================
// Extensions / TimeSpan / Expiration — 时间比较
// ==============================================================================

DurationHasExpired :: proc(value, now: coretime.Duration, offset: f64 = 0) -> bool {
	return now >= value + coretime.Duration(offset * 1e9)
}

DurationHasPassed :: proc(value, timestamp: coretime.Duration, offset: f64 = 0) -> bool {
	return value >= timestamp + coretime.Duration(offset * 1e9)
}
// ==============================================================================
// Utility / Time — 帧计时助手
// ==============================================================================

TimeIntervalCount :: proc(t: Time, interval: f64, offset: f64 = 0) -> int {
	return IntervalCount(coretime.duration_seconds(t.Elapsed), f64(t.Delta), interval, offset)
}

TimeCycleInterval :: proc(t: Time, interval: f64, options: []$T, offset: f64 = 0) -> T {
	return CycleInterval(coretime.duration_seconds(t.Elapsed), interval, options, offset)
}

TimeSineWave :: proc(t: Time, from, to: f32, duration: f64, offset_percent: f32 = 0) -> f32 {
	assert(duration > 0)
	return SineMap(
		f32((coretime.duration_seconds(t.Elapsed) / duration + f64(offset_percent)) * math.TAU),
		from,
		to,
	)
}

TimeMultiplyDelta :: proc(t: Time, multiplier: f64) -> Time {
	result := t
	result.Delta = t.Delta * f32(multiplier)
	result.Elapsed = t.Previous + coretime.Duration(f64(t.Elapsed - t.Previous) * multiplier)
	return result
}
