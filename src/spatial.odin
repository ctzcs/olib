package foster_framework

import "core:math"
import "core:strings"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Spatial / Cardinal
//   Spatial / Circle
//   Spatial / ConvexPolygon
//   Spatial / IConvexShape
//   Spatial / IProjectable
//   Spatial / Line
//   Spatial / LineInt
//   Spatial / Point3
//   Spatial / Polygon
//   Spatial / Quad
//   Spatial / Ray
//   Spatial / Rect
//   Spatial / RectInt
//   Spatial / Signs
//   Spatial / Transform
//   Spatial / Triangle

// ==============================================================================
// Spatial / Cardinal
// ==============================================================================

Cardinal :: struct {
	Value: int,
}
CardinalRightValue :: 0
CardinalDownValue :: 1
CardinalLeftValue :: 2
CardinalUpValue :: 3
CardinalRight :: Cardinal{CardinalRightValue}
CardinalDown :: Cardinal{CardinalDownValue}
CardinalLeft :: Cardinal{CardinalLeftValue}
CardinalUp :: Cardinal{CardinalUpValue}
CardinalEast :: CardinalRight
CardinalSouth :: CardinalDown
CardinalWest :: CardinalLeft
CardinalNorth :: CardinalUp

CardinalMake :: proc(value: int) -> Cardinal {
	return Cardinal{((value % 4) + 4) % 4}
}

CardinalReverse :: proc(c: Cardinal) -> Cardinal {
	return CardinalMake(c.Value + 2)
}

CardinalTurnRight :: proc(c: Cardinal) -> Cardinal {
	return CardinalMake(c.Value + 1)
}

CardinalTurnLeft :: proc(c: Cardinal) -> Cardinal {
	return CardinalMake(c.Value + 3)
}

CardinalHorizontal :: proc(c: Cardinal) -> bool {
	return c.Value % 2 == 0
}

CardinalVertical :: proc(c: Cardinal) -> bool {
	return c.Value % 2 == 1
}

CardinalX :: proc(c: Cardinal) -> int {
	if c == CardinalRight {
		return 1
	}
	if c == CardinalLeft {
		return -1
	}
	return 0
}

CardinalY :: proc(c: Cardinal) -> int {
	if c == CardinalDown {
		return 1
	}
	if c == CardinalUp {
		return -1
	}
	return 0
}

CardinalPoint :: proc(c: Cardinal) -> Point2 {
	return Point2{CardinalX(c), CardinalY(c)}
}

CardinalAngle :: proc(c: Cardinal) -> f32 {
	switch c.Value {
	case 0:
		return 0
	case 1:
		return f32(math.PI / 2)
	case 2:
		return f32(math.PI)
	case 3:
		return -f32(math.PI / 2)
	}
	return 0
}

CardinalAbs :: proc(c: Cardinal) -> Cardinal {
	if CardinalHorizontal(c) {
		return CardinalRight
	}
	return CardinalDown
}

CardinalFromPoint :: proc(p: Point2) -> Cardinal {
	if math.abs(p.X) > math.abs(p.Y) {
		if p.X < 0 {
			return CardinalLeft
		}
		return CardinalRight
	}
	if p.Y < 0 {
		return CardinalUp
	}
	return CardinalDown
}

CardinalFromVector :: proc(v: [2]f32) -> Cardinal {
	if math.abs(v[0]) > math.abs(v[1]) {
		if v[0] < 0 {
			return CardinalLeft
		}
		return CardinalRight
	}
	if v[1] < 0 {
		return CardinalUp
	}
	return CardinalDown
}
CardinalAll :: [4]Cardinal{CardinalRight, CardinalDown, CardinalLeft, CardinalUp}

CardinalIsPerpendicular :: proc(a, b: Cardinal) -> bool {
	return CardinalHorizontal(a) != CardinalHorizontal(b)
}
CardinalFromRawValue :: CardinalMake

CardinalFromString :: proc(value: string) -> Cardinal {
	if strings.equal_fold(value, "Left") {
		return CardinalLeft
	}
	if strings.equal_fold(value, "Up") {
		return CardinalUp
	}
	if strings.equal_fold(value, "Down") {
		return CardinalDown
	}
	return CardinalRight
}

CardinalFromSignX :: proc(value: int) -> Cardinal {
	if value < 0 {
		return CardinalLeft
	}
	return CardinalRight
}

CardinalFromSignY :: proc(value: int) -> Cardinal {
	if value < 0 {
		return CardinalUp
	}
	return CardinalDown
}

// ==============================================================================
// Spatial / Circle
// ==============================================================================

Circle :: struct {
	Position: Vec2,
	Radius:   f32,
}

CircleMake :: proc(position: Vec2, radius: f32) -> Circle {
	return Circle{Position = position, Radius = radius}
}

CircleArea :: proc(circle: Circle) -> f32 {
	return f32(math.PI) * circle.Radius * circle.Radius
}

CircleCircumference :: proc(circle: Circle) -> f32 {
	return f32(math.TAU) * circle.Radius
}

CircleBounds :: proc(circle: Circle) -> Rect {
	diameter := circle.Radius * 2
	return RectCentered(circle.Position, Vec2{diameter, diameter})
}

CircleContains :: proc(circle: Circle, point: Vec2) -> bool {
	return vec2_length_squared(vec2_sub(circle.Position, point)) < circle.Radius * circle.Radius
}

circle_overlaps_circle :: proc(circle, other: Circle) -> (overlaps: bool, pushout: Vec2) {
	combined := circle.Radius + other.Radius
	delta := vec2_sub(circle.Position, other.Position)
	distance_squared := vec2_length_squared(delta)
	if distance_squared >= combined * combined {
		return false, Vec2{}
	}
	distance := math.sqrt(distance_squared)
	if distance <= 0 {
		return true, Vec2{combined, 0}
	}
	return true, vec2_scale(delta, (combined - distance) / distance)
}

CircleOverlapsCenter :: proc(circle: Circle, center: Vec2, radius: f32) -> bool {
	delta := vec2_sub(circle.Position, center)
	combined := circle.Radius + radius
	return vec2_length_squared(delta) < combined * combined
}
CircleOverlaps :: proc {
	circle_overlaps_circle,
	CircleOverlapsCenter,
}

CircleOverlapsLine :: proc(circle: Circle, line: Line) -> bool {
	return LineDistanceSquared(line, circle.Position) < circle.Radius * circle.Radius
}

CircleProject :: proc(circle: Circle, axis: Vec2) -> (min, max: f32) {
	unit := vec2_normalized(axis)
	center := vec2_dot(circle.Position, unit)
	return center - circle.Radius, center + circle.Radius
}

CircleAt :: proc(circle: Circle, position: Vec2) -> Circle {
	return Circle{position, circle.Radius}
}

CircleAtXY :: proc(circle: Circle, x, y: f32) -> Circle {
	return Circle{Vec2{x, y}, circle.Radius}
}

CircleInflate :: proc(circle: Circle, amount: f32) -> Circle {
	return Circle{circle.Position, circle.Radius + amount}
}

CircleTranslate :: proc(circle: Circle, by: Vec2) -> Circle {
	return Circle{vec2_add(circle.Position, by), circle.Radius}
}

CircleIntersectsLine :: proc(circle: Circle, line: Line) -> bool {
	return CircleOverlapsLine(circle, line)
}

// ==============================================================================
// Spatial / ConvexPolygon
// ==============================================================================

ConvexPolygon :: struct {
	Vertices: [dynamic]Vec2,
}

ConvexPolygonMake :: proc(vertices: ..Vec2) -> ConvexPolygon {
	result: ConvexPolygon
	for vertex in vertices {
		append(&result.Vertices, vertex)
	}
	return result
}

ConvexPolygonHull :: proc(points: []Vec2) -> ConvexPolygon {
	result: ConvexPolygon
	if len(points) <= 1 {
		for p in points {
			append(&result.Vertices, p)
		}
		return result
	}
	sorted: [dynamic]Vec2 = {}
	append(&sorted, ..points)
	for i := 1; i < len(sorted); i += 1 {
		value := sorted[i]
		j := i - 1
		for j >= 0 &&
		    (sorted[j][0] > value[0] || (sorted[j][0] == value[0] && sorted[j][1] > value[1])) {
			sorted[j + 1] = sorted[j]
			j -= 1
		}
		sorted[j + 1] = value
	}
	cross := proc(o, a, b: Vec2) -> f32 {
		return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
	}
	hull: [dynamic]Vec2 = {}
	for p in sorted {
		for len(hull) >= 2 && cross(hull[len(hull) - 2], hull[len(hull) - 1], p) <= 0 {
			resize(&hull, len(hull) - 1)
		}
		append(&hull, p)
	}
	lower_count := len(hull)
	for i := len(sorted) - 2; i >= 0; i -= 1 {
		p := sorted[i]
		for len(hull) > lower_count && cross(hull[len(hull) - 2], hull[len(hull) - 1], p) <= 0 {
			resize(&hull, len(hull) - 1)
		}
		append(&hull, p)
	}
	if len(hull) > 1 {
		resize(&hull, len(hull) - 1)
	}
	result.Vertices = hull
	return result
}

ConvexHull :: ConvexPolygonHull

ConvexPolygonAdd :: proc(polygon: ^ConvexPolygon, vertex: Vec2) {
	append(&polygon.Vertices, vertex)
}

ConvexPolygonCount :: proc(polygon: ConvexPolygon) -> int {
	return len(polygon.Vertices)
}

ConvexPolygonBounds :: proc(polygon: ConvexPolygon) -> Rect {
	if len(polygon.Vertices) == 0 {
		return Rect{}
	}
	min := polygon.Vertices[0]
	max := min
	for p in polygon.Vertices[1:] {
		min[0] = math.min(min[0], p[0])
		min[1] = math.min(min[1], p[1])
		max[0] = math.max(max[0], p[0])
		max[1] = math.max(max[1], p[1])
	}
	return RectBetween(min, max)
}

ConvexPolygonCenter :: proc(polygon: ConvexPolygon) -> Vec2 {
	return RectCenter(ConvexPolygonBounds(polygon))
}

ConvexPolygonAverage :: proc(polygon: ConvexPolygon) -> Vec2 {
	result: Vec2
	for p in polygon.Vertices {
		result = vec2_add(result, p)
	}
	if len(polygon.Vertices) > 0 {
		result = vec2_scale(result, 1 / f32(len(polygon.Vertices)))
	}
	return result
}

ConvexPolygonContains :: proc(polygon: ConvexPolygon, point: Vec2) -> bool {
	if len(polygon.Vertices) < 3 {
		return false
	}
	sign := 0
	for i := 0; i < len(polygon.Vertices); i += 1 {
		cross := triangle_cross(
			vec2_sub(polygon.Vertices[(i + 1) % len(polygon.Vertices)], polygon.Vertices[i]),
			vec2_sub(point, polygon.Vertices[i]),
		)
		if cross != 0 {
			current := 1
			if cross < 0 {
				current = -1
			}
			if sign == 0 {
				sign = current
			} else if sign != current {
				return false
			}
		}
	}
	return true
}

ConvexPolygonProject :: proc(polygon: ConvexPolygon, axis: Vec2) -> (min, max: f32) {
	if len(polygon.Vertices) == 0 {
		return 0, 0
	}
	min = vec2_dot(polygon.Vertices[0], axis)
	max = min
	for p in polygon.Vertices[1:] {
		d := vec2_dot(p, axis)
		min = math.min(min, d)
		max = math.max(max, d)
	}
	return
}

ConvexPolygonEdges :: proc(polygon: ConvexPolygon) -> [dynamic]Line {
	edges: [dynamic]Line
	for i := 0; i < len(polygon.Vertices); i += 1 {
		append(
			&edges,
			Line{polygon.Vertices[i], polygon.Vertices[(i + 1) % len(polygon.Vertices)]},
		)
	}
	return edges
}

// ==============================================================================
// Spatial / IConvexShape
// ==============================================================================
// Convex shapes share point/axis projection conventions.
ConvexShapeProjection :: proc(axis: Vec2) -> (min, max: f32)

// ==============================================================================
// Spatial / IProjectable
// ==============================================================================
// Shapes expose projection through their dedicated Project procedures.
ProjectableProjection :: proc(axis: Vec2) -> (min, max: f32)

// 传入每个形状的 Project 结果；保持上游严格相交和有符号最小位移语义。

AxisOverlaps :: proc(min_a, max_a, min_b, max_b: f32) -> (overlaps: bool, amount: f32) {
	amount = max_b - min_a
	if math.abs(min_b - max_a) < math.abs(amount) {
		amount = min_b - max_a
	}
	return min_a < max_b && max_a > min_b, amount
}

// ==============================================================================
// Spatial / Line
// ==============================================================================
Vec2 :: [2]f32

vec2_add :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a[0] + b[0], a[1] + b[1]}
}

vec2_sub :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a[0] - b[0], a[1] - b[1]}
}

vec2_scale :: proc(v: Vec2, scalar: f32) -> Vec2 {
	return Vec2{v[0] * scalar, v[1] * scalar}
}

vec2_dot :: proc(a, b: Vec2) -> f32 {
	return a[0] * b[0] + a[1] * b[1]
}

vec2_length_squared :: proc(v: Vec2) -> f32 {
	return vec2_dot(v, v)
}

vec2_length :: proc(v: Vec2) -> f32 {
	return math.sqrt(vec2_length_squared(v))
}

vec2_normalized :: proc(v: Vec2) -> Vec2 {
	length := vec2_length(v)
	if length == 0 {
		return Vec2{}
	}
	return vec2_scale(v, 1 / length)
}

vec2_lerp :: proc(a, b: Vec2, t: f32) -> Vec2 {
	return vec2_add(a, vec2_scale(vec2_sub(b, a), t))
}

clamp01 :: proc(value: f32) -> f32 {
	return math.clamp(value, 0, 1)
}

Line :: struct {
	From: Vec2,
	To:   Vec2,
}

LineMakeVec :: proc(from, to: Vec2) -> Line {
	return Line{From = from, To = to}
}

LineMakeXY :: proc(x1, y1, x2, y2: f32) -> Line {
	return Line{From = Vec2{x1, y1}, To = Vec2{x2, y2}}
}
LineMake :: proc {
	LineMakeVec,
	LineMakeXY,
}

LineCenter :: proc(line: Line) -> Vec2 {
	return vec2_scale(vec2_add(line.From, line.To), 0.5)
}

LineLengthSquared :: proc(line: Line) -> f32 {
	return vec2_length_squared(vec2_sub(line.To, line.From))
}

LineLength :: proc(line: Line) -> f32 {
	return math.sqrt(LineLengthSquared(line))
}

LineNormal :: proc(line: Line) -> Vec2 {
	return vec2_normalized(vec2_sub(line.To, line.From))
}

LineBounds :: proc(line: Line) -> Rect {
	return RectBetween(line.From, line.To)
}

LineGetAxis :: proc(line: Line, index: int) -> Vec2 {
	if index < 0 || index >= 1 {
		panic("Line axis index out of range")
	}
	normal := LineNormal(line)
	return Vec2{normal[1], -normal[0]}
}

LineGetPoint :: proc(line: Line, index: int) -> Vec2 {
	if index == 0 {
		return line.From
	}
	if index == 1 {
		return line.To
	}
	panic("Line point index out of range")
}

LineOn :: proc(line: Line, percent: f32) -> Vec2 {
	return vec2_lerp(line.From, line.To, percent)
}

LineOnClamped :: proc(line: Line, percent: f32) -> Vec2 {
	return LineOn(line, clamp01(percent))
}

LineProject :: proc(line: Line, axis: Vec2) -> (min, max: f32) {
	a := vec2_dot(line.From, axis)
	b := vec2_dot(line.To, axis)
	return math.min(a, b), math.max(a, b)
}

LineClosestTUnclamped :: proc(line: Line, point: Vec2) -> f32 {
	delta := vec2_sub(line.To, line.From)
	denominator := vec2_length_squared(delta)
	if denominator == 0 {
		return 0
	}
	return vec2_dot(vec2_sub(point, line.From), delta) / denominator
}

LineClosestT :: proc(line: Line, point: Vec2) -> f32 {
	return clamp01(LineClosestTUnclamped(line, point))
}

LineClosestPoint :: proc(line: Line, point: Vec2) -> Vec2 {
	return LineOn(line, LineClosestT(line, point))
}

LineDistanceSquared :: proc(line: Line, point: Vec2) -> f32 {
	return vec2_length_squared(vec2_sub(LineClosestPoint(line, point), point))
}

LineDistance :: proc(line: Line, point: Vec2) -> f32 {
	return math.sqrt(LineDistanceSquared(line, point))
}

LineClosestPoints :: proc(line, other: Line) -> (Vec2, Vec2) {
	v1 := vec2_sub(line.To, line.From)
	v2 := vec2_sub(other.To, other.From)
	w := vec2_sub(line.From, other.From)
	a := vec2_dot(v1, v1)
	b := vec2_dot(v1, v2)
	c := vec2_dot(v2, v2)
	d := vec2_dot(v1, w)
	e := vec2_dot(v2, w)
	denom := a * c - b * b
	s: f32 = 0
	t: f32 = 0
	if denom < 1e-8 {
		if c > 0 {
			t = clamp01(e / c)
		}
	} else {
		s = clamp01((b * e - c * d) / denom)
		t = clamp01((a * e - b * d) / denom)
	}
	return LineOn(line, s), LineOn(other, t)
}

LineClosestDistance :: proc(line, other: Line) -> f32 {
	a, b := LineClosestPoints(line, other)
	return vec2_length(vec2_sub(a, b))
}

LineClosestDistanceSquared :: proc(line, other: Line) -> f32 {
	a, b := LineClosestPoints(line, other)
	return vec2_length_squared(vec2_sub(a, b))
}

LinePoints :: proc(line: Line) -> int {
	return 2
}

LineAxes :: proc(line: Line) -> int {
	return 1
}

LineIntersects :: proc(a, b: Line) -> (hit: bool, point: Vec2) {
	ab := vec2_sub(a.To, a.From)
	bd := vec2_sub(b.To, b.From)
	denom := ab[0] * bd[1] - ab[1] * bd[0]
	if denom == 0 {
		return false, Vec2{}
	}
	c := vec2_sub(b.From, a.From)
	t := (c[0] * bd[1] - c[1] * bd[0]) / denom
	u := (c[0] * ab[1] - c[1] * ab[0]) / denom
	if t < 0 || t > 1 || u < 0 || u > 1 {
		return false, Vec2{}
	}
	return true, vec2_add(a.From, vec2_scale(ab, t))
}

LineIntersectsRect :: proc(line: Line, rect: Rect) -> (bool, Vec2) {
	return RectOverlapsLine(rect, line)
}

LineIntersectsCircle :: proc(line: Line, circle: Circle) -> bool {
	return CircleOverlapsLine(circle, line)
}

LineIntersectsBool :: proc(a, b: Line) -> bool {
	hit, _ := LineIntersects(a, b)
	return hit
}

LineTranslate :: proc(line: Line, by: Vec2) -> Line {
	return Line{vec2_add(line.From, by), vec2_add(line.To, by)}
}

// ==============================================================================
// Spatial / LineInt
// ==============================================================================

LineInt :: struct {
	From: Point2,
	To:   Point2,
}

LineIntMake :: proc(from, to: Point2) -> LineInt {
	return LineInt{From = from, To = to}
}

LineIntPoints :: proc(line: LineInt) -> int {
	return 2
}

LineIntAxes :: proc(line: LineInt) -> int {
	return 1
}

LineIntBounds :: proc(line: LineInt) -> RectInt {
	return RectIntBetween(line.From, line.To)
}

LineIntGetAxis :: proc(line: LineInt, index: int) -> [2]f32 {
	if index != 0 {
		return [2]f32{}
	}
	dx := f32(line.To.X - line.From.X)
	dy := f32(line.To.Y - line.From.Y)
	length := math.sqrt(dx * dx + dy * dy)
	if length == 0 {
		return [2]f32{}
	}
	return [2]f32{dy / length, -dx / length}
}

LineIntGetPoint :: proc(line: LineInt, index: int) -> Point2 {
	switch index {
	case 0:
		return line.From
	case 1:
		return line.To
	}
	return Point2{}
}

LineIntProject :: proc(line: LineInt, axis: [2]f32) -> (min, max: f32) {
	min = 1e30
	max = -1e30
	points := [2]Point2{line.From, line.To}
	for p in points {
		dot := f32(p.X) * axis[0] + f32(p.Y) * axis[1]
		min = math.min(min, dot)
		max = math.max(max, dot)
	}
	return
}

LineIntIntersects :: proc(a, b: LineInt) -> bool {
	bx := f32(a.To.X - a.From.X)
	by := f32(a.To.Y - a.From.Y)
	dx := f32(b.To.X - b.From.X)
	dy := f32(b.To.Y - b.From.Y)
	denom := bx * dy - by * dx
	if denom == 0 {
		return false
	}
	cx := f32(b.From.X - a.From.X)
	cy := f32(b.From.Y - a.From.Y)
	t := (cx * dy - cy * dx) / denom
	u := (cx * by - cy * bx) / denom
	return t >= 0 && t <= 1 && u >= 0 && u <= 1
}

LineIntTranslate :: proc(line: LineInt, by: Point2) -> LineInt {
	return LineInt {
		From = Point2{line.From.X + by.X, line.From.Y + by.Y},
		To   = Point2{line.To.X + by.X, line.To.Y + by.Y},
	}
}

// ==============================================================================
// Spatial / Point3
// ==============================================================================
Vec3 :: [3]f32

Point3 :: struct {
	X, Y, Z: int,
}

Point3Make1 :: proc(value: int) -> Point3 {
	return Point3{value, value, value}
}

Point3Make2 :: proc(x, y: int) -> Point3 {
	return Point3{x, y, 0}
}

Point3Make3 :: proc(x, y, z: int) -> Point3 {
	return Point3{x, y, z}
}
Point3Make :: proc {
	Point3Make1,
	Point3Make2,
	Point3Make3,
}
Point3Zero :: Point3{}
Point3One :: Point3{1, 1, 1}
Point3Left :: Point3{-1, 0, 0}
Point3Right :: Point3{1, 0, 0}
Point3Up :: Point3{0, -1, 0}
Point3Down :: Point3{0, 1, 0}
Point3Forward :: Point3{0, 0, 1}
Point3Backward :: Point3{0, 0, -1}

Point3Length :: proc(p: Point3) -> f32 {
	return math.sqrt(f32(p.X * p.X + p.Y * p.Y + p.Z * p.Z))
}

Point3LengthSquared :: proc(p: Point3) -> f32 {
	return f32(p.X * p.X + p.Y * p.Y + p.Z * p.Z)
}

Point3Vector3 :: proc(p: Point3) -> Vec3 {
	return Vec3{f32(p.X), f32(p.Y), f32(p.Z)}
}

Point3Normalized :: proc(p: Point3) -> Vec3 {
	v := Point3Vector3(p)
	l := math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	if l == 0 {
		return Vec3{}
	}
	return Vec3{v[0] / l, v[1] / l, v[2] / l}
}

Point3GetLengthAndNormalize :: proc(
	p: Point3,
	fallback: Vec3 = {},
) -> (
	result: Vec3,
	length: f32,
) {
	result = Point3Vector3(p)
	length = math.sqrt(result[0] * result[0] + result[1] * result[1] + result[2] * result[2])
	if length == 0 {
		result = fallback
		return
	}
	result = Vec3{result[0] / length, result[1] / length, result[2] / length}
	return
}

Point3Add :: proc(a, b: Point3) -> Point3 {
	return Point3{a.X + b.X, a.Y + b.Y, a.Z + b.Z}
}

Point3Sub :: proc(a, b: Point3) -> Point3 {
	return Point3{a.X - b.X, a.Y - b.Y, a.Z - b.Z}
}

Point3Scale :: proc(p: Point3, scalar: int) -> Point3 {
	return Point3{p.X * scalar, p.Y * scalar, p.Z * scalar}
}

Point3ScaleFloat :: proc(p: Point3, scalar: f32) -> Vec3 {
	return Vec3{f32(p.X) * scalar, f32(p.Y) * scalar, f32(p.Z) * scalar}
}

Point3Negate :: proc(p: Point3) -> Point3 {
	return Point3{-p.X, -p.Y, -p.Z}
}

Point3Div :: proc(p: Point3, scalar: int) -> Point3 {
	if scalar == 0 {
		return {}
	}
	return Point3{p.X / scalar, p.Y / scalar, p.Z / scalar}
}

Point3Mod :: proc(p: Point3, scalar: int) -> Point3 {
	if scalar == 0 {
		return {}
	}
	return Point3{p.X % scalar, p.Y % scalar, p.Z % scalar}
}

Point3DivFloat :: proc(p: Point3, scalar: f32) -> Vec3 {
	if scalar == 0 {
		return {}
	}
	return Vec3{f32(p.X) / scalar, f32(p.Y) / scalar, f32(p.Z) / scalar}
}

Point3ModFloat :: proc(p: Point3, scalar: f32) -> Vec3 {
	if scalar == 0 {
		return {}
	}
	return Vec3{math.mod(f32(p.X), scalar), math.mod(f32(p.Y), scalar), math.mod(f32(p.Z), scalar)}
}

// ==============================================================================
// Spatial / Polygon
// ==============================================================================

Polygon :: struct {
	Vertices: [dynamic]Vec2,
	Indices:  [dynamic]u32,
}

PolygonMake :: proc(vertices: ..Vec2) -> Polygon {
	result: Polygon
	for vertex in vertices {
		append(&result.Vertices, vertex)
	}
	PolygonTriangulate(&result)
	return result
}

PolygonAdd :: proc(polygon: ^Polygon, vertex: Vec2) {
	append(&polygon.Vertices, vertex)
	PolygonTriangulate(polygon)
}

PolygonIndexOf :: proc(polygon: ^Polygon, vertex: Vec2) -> int {
	for value, index in polygon.Vertices {
		if value == vertex {
			return index
		}
	}
	return -1
}

PolygonInsert :: proc(polygon: ^Polygon, index: int, vertex: Vec2) {
	assert(index >= 0 && index <= len(polygon.Vertices))
	append(&polygon.Vertices, vertex)
	for i := len(polygon.Vertices) - 1; i > index; i -= 1 {
		polygon.Vertices[i] = polygon.Vertices[i - 1]
	}
	polygon.Vertices[index] = vertex
	PolygonTriangulate(polygon)
}

PolygonSetVertex :: proc(polygon: ^Polygon, index: int, vertex: Vec2) {
	assert(index >= 0 && index < len(polygon.Vertices))
	polygon.Vertices[index] = vertex
	PolygonTriangulate(polygon)
}

PolygonRemove :: proc(polygon: ^Polygon, vertex: Vec2) -> bool {
	index := PolygonIndexOf(polygon, vertex)
	if index < 0 {
		return false
	}
	PolygonRemoveAt(polygon, index)
	return true
}

PolygonClear :: proc(polygon: ^Polygon) {
	clear(&polygon.Vertices)
	clear(&polygon.Indices)
}

PolygonCount :: proc(polygon: Polygon) -> int {
	return len(polygon.Vertices)
}

PolygonArea :: proc(polygon: ^Polygon) -> f32 {
	return math.abs(tri_area(polygon.Vertices[:]))
}

PolygonTriangulate :: proc(polygon: ^Polygon) {
	clear(&polygon.Indices)
	indices: [dynamic]int
	defer delete(indices)
	Triangulate(polygon.Vertices[:], &indices)
	for index in indices {
		append(&polygon.Indices, u32(index))
	}
}

PolygonBounds :: proc(polygon: Polygon) -> Rect {
	if len(polygon.Vertices) == 0 {
		return Rect{}
	}
	min := polygon.Vertices[0]
	max := min
	for point in polygon.Vertices[1:] {
		min[0] = math.min(min[0], point[0])
		min[1] = math.min(min[1], point[1])
		max[0] = math.max(max[0], point[0])
		max[1] = math.max(max[1], point[1])
	}
	return RectBetween(min, max)
}

PolygonContains :: proc(polygon: Polygon, point: Vec2) -> bool {
	inside := false
	count := len(polygon.Vertices)
	if count < 3 {
		return false
	}
	for i := 0; i < count; i += 1 {
		a := polygon.Vertices[i]
		b := polygon.Vertices[(i + 1) % count]
		if ((a[1] > point[1]) != (b[1] > point[1])) &&
		   point[0] < (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]) + a[0] {
			inside = !inside
		}
	}
	return inside
}

PolygonMove :: proc(polygon: ^Polygon, offset: Vec2) {
	for i := 0; i < len(polygon.Vertices); i += 1 {
		polygon.Vertices[i] = vec2_add(polygon.Vertices[i], offset)
	}
}

PolygonRemoveAt :: proc(polygon: ^Polygon, index: int) {
	assert(index >= 0 && index < len(polygon.Vertices))
	for i in index ..< len(polygon.Vertices) - 1 {
		polygon.Vertices[i] = polygon.Vertices[i + 1]
	}
	resize(&polygon.Vertices, len(polygon.Vertices) - 1)
	PolygonTriangulate(polygon)
}

PolygonGetTriangles :: proc(polygon: ^Polygon) -> ([]Vec2, []u32) {
	PolygonTriangulate(polygon)
	return polygon.Vertices[:], polygon.Indices[:]
}

PolygonGetClosestEdge :: proc(polygon: ^Polygon, point: Vec2) -> int {
	if len(polygon.Vertices) <= 2 {
		return 0
	}
	best := 0
	distance := f32(1e30)
	for p, i in polygon.Vertices {
		next := polygon.Vertices[(i + 1) % len(polygon.Vertices)]
		d := LineDistanceSquared(Line{p, next}, point)
		if d < distance {
			distance = d
			best = i
		}
	}
	return best
}

PolygonRenderLine :: proc(polygon: ^Polygon, batcher: ^Batcher, thickness: f32, color: Color) {
	if len(polygon.Vertices) < 2 {
		return
	}
	for p, i in polygon.Vertices {
		BatcherLine(
			batcher,
			p,
			polygon.Vertices[(i + 1) % len(polygon.Vertices)],
			thickness,
			color,
		)
	}
}

// ==============================================================================
// Spatial / Quad
// ==============================================================================

Quad :: struct {
	A, B, C, D: Vec2,
}

QuadMake :: proc(a, b, c, d: Vec2) -> Quad {
	return Quad{a, b, c, d}
}

QuadFromRect :: proc(rect: Rect) -> Quad {
	return Quad{RectTopLeft(rect), RectTopRight(rect), RectBottomRight(rect), RectBottomLeft(rect)}
}

QuadBounds :: proc(q: Quad) -> Rect {
	min := Vec2 {
		math.min(q.A[0], math.min(q.B[0], math.min(q.C[0], q.D[0]))),
		math.min(q.A[1], math.min(q.B[1], math.min(q.C[1], q.D[1]))),
	}
	max := Vec2 {
		math.max(q.A[0], math.max(q.B[0], math.max(q.C[0], q.D[0]))),
		math.max(q.A[1], math.max(q.B[1], math.max(q.C[1], q.D[1]))),
	}
	return RectBetween(min, max)
}

QuadCenter :: proc(q: Quad) -> Vec2 {
	return RectCenter(QuadBounds(q))
}

QuadAverage :: proc(q: Quad) -> Vec2 {
	return vec2_scale(vec2_add(vec2_add(q.A, q.B), vec2_add(q.C, q.D)), 0.25)
}

QuadEdges :: proc(q: Quad) -> [4]Line {
	return [4]Line{Line{q.A, q.B}, Line{q.B, q.C}, Line{q.C, q.D}, Line{q.D, q.A}}
}

QuadTranslated :: proc(q: Quad, offset: Vec2) -> Quad {
	return Quad{q.A + offset, q.B + offset, q.C + offset, q.D + offset}
}

QuadProject :: proc(q: Quad, axis: Vec2) -> (min, max: f32) {
	points := [4]Vec2{q.A, q.B, q.C, q.D}
	min = 1e30
	max = -1e30
	for p in points {
		d := vec2_dot(p, axis)
		min = math.min(min, d)
		max = math.max(max, d)
	}
	return
}

// ==============================================================================
// Spatial / Ray
// ==============================================================================

Ray :: struct {
	Position:  Vec2,
	Direction: Vec2,
}

RayMake :: proc(position, direction: Vec2) -> Ray {
	return Ray{position, direction}
}

RayAt :: proc(ray: Ray, distance: f32) -> Vec2 {
	return vec2_add(ray.Position, vec2_scale(ray.Direction, distance))
}

// ==============================================================================
// Spatial / Rect
// ==============================================================================

Rect :: struct {
	X, Y:          f32,
	Width, Height: f32,
}

RectIdentity :: Rect{0, 0, 1, 1}

RectPosition :: proc(rect: Rect) -> Vec2 {
	return Vec2{rect.X, rect.Y}
}

RectSize :: proc(rect: Rect) -> Vec2 {
	return Vec2{rect.Width, rect.Height}
}

RectArea :: proc(rect: Rect) -> f32 {
	return math.abs(rect.Width * rect.Height)
}

RectLeft :: proc(rect: Rect) -> f32 {
	return rect.X
}

RectRight :: proc(rect: Rect) -> f32 {
	return rect.X + rect.Width
}

RectTop :: proc(rect: Rect) -> f32 {
	return rect.Y
}

RectBottom :: proc(rect: Rect) -> f32 {
	return rect.Y + rect.Height
}

RectCenter :: proc(rect: Rect) -> Vec2 {
	return Vec2{rect.X + rect.Width * 0.5, rect.Y + rect.Height * 0.5}
}

RectCenterX :: proc(rect: Rect) -> f32 {
	return rect.X + rect.Width * 0.5
}

RectCenterY :: proc(rect: Rect) -> f32 {
	return rect.Y + rect.Height * 0.5
}

RectMin :: proc(rect: Rect) -> Vec2 {
	return Vec2 {
		math.min(RectLeft(rect), RectRight(rect)),
		math.min(RectTop(rect), RectBottom(rect)),
	}
}

RectMax :: proc(rect: Rect) -> Vec2 {
	return Vec2 {
		math.max(RectLeft(rect), RectRight(rect)),
		math.max(RectTop(rect), RectBottom(rect)),
	}
}

RectTopLeft :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectLeft(rect), RectTop(rect)}
}

RectTopCenter :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectCenterX(rect), RectTop(rect)}
}

RectTopRight :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectRight(rect), RectTop(rect)}
}

RectCenterLeft :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectLeft(rect), RectCenterY(rect)}
}

RectCenterRight :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectRight(rect), RectCenterY(rect)}
}

RectBottomLeft :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectLeft(rect), RectBottom(rect)}
}

RectBottomCenter :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectCenterX(rect), RectBottom(rect)}
}

RectBottomRight :: proc(rect: Rect) -> Vec2 {
	return Vec2{RectRight(rect), RectBottom(rect)}
}

RectOn :: proc(rect: Rect, x, y: f32) -> Vec2 {
	return Vec2{rect.X + rect.Width * x, rect.Y + rect.Height * y}
}

RectOnVec :: proc(rect: Rect, vec: Vec2) -> Vec2 {
	return RectOn(rect, vec[0], vec[1])
}

RectContains :: proc(rect: Rect, point: Vec2) -> bool {
	return(
		point[0] >= rect.X &&
		point[1] >= rect.Y &&
		point[0] < RectRight(rect) &&
		point[1] < RectBottom(rect) \
	)
}

RectContainsRect :: proc(rect, other: Rect) -> bool {
	return(
		RectLeft(rect) <= RectLeft(other) &&
		RectTop(rect) <= RectTop(other) &&
		RectRight(rect) >= RectRight(other) &&
		RectBottom(rect) >= RectBottom(other) \
	)
}

RectOverlaps :: proc(rect, other: Rect) -> bool {
	return(
		RectRight(rect) > RectLeft(other) &&
		RectBottom(rect) > RectTop(other) &&
		RectLeft(rect) < RectRight(other) &&
		RectTop(rect) < RectBottom(other) \
	)
}

RectIntersection :: proc(rect, other: Rect) -> Rect {
	left := math.max(RectLeft(rect), RectLeft(other))
	top := math.max(RectTop(rect), RectTop(other))
	right := math.min(RectRight(rect), RectRight(other))
	bottom := math.min(RectBottom(rect), RectBottom(other))
	if right <= left || bottom <= top {
		return Rect{}
	}
	return Rect{left, top, right - left, bottom - top}
}

RectDifference :: proc(rect, other: Rect) -> [dynamic]Rect {
	result: [dynamic]Rect
	r := RectValidateSize(rect)
	o := RectValidateSize(other)
	i := RectIntersection(r, o)
	if i.Width <= 0 || i.Height <= 0 {
		append(&result, r)
		return result
	}
	if i.Y > r.Y {
		append(&result, Rect{r.X, r.Y, r.Width, i.Y - r.Y})
	}
	if RectBottom(i) < RectBottom(r) {
		append(&result, Rect{r.X, RectBottom(i), r.Width, RectBottom(r) - RectBottom(i)})
	}
	if i.X > r.X {
		append(&result, Rect{r.X, i.Y, i.X - r.X, i.Height})
	}
	if RectRight(i) < RectRight(r) {
		append(&result, Rect{RectRight(i), i.Y, RectRight(r) - RectRight(i), i.Height})
	}
	return result
}

RectGetPointSector :: proc(rect: Rect, point: Vec2) -> u8 {
	sector: u8 = 0
	if point[0] < rect.X {
		sector |= 0b0001
	} else if point[0] >= RectRight(rect) {
		sector |= 0b0010
	}
	if point[1] < rect.Y {
		sector |= 0b0100
	} else if point[1] >= RectBottom(rect) {
		sector |= 0b1000
	}
	return sector
}

RectClosestPoint :: proc(rect: Rect, point: Vec2) -> Vec2 {
	return Vec2 {
		math.clamp(point[0], RectLeft(rect), RectRight(rect)),
		math.clamp(point[1], RectTop(rect), RectBottom(rect)),
	}
}

RectClosestPointOnEdges :: proc(rect: Rect, point: Vec2) -> Vec2 {
	result := RectClosestPoint(rect, point)
	if result != point {
		return result
	}
	distances := [4]f32 {
		point[0] - RectLeft(rect),
		RectRight(rect) - point[0],
		point[1] - RectTop(rect),
		RectBottom(rect) - point[1],
	}
	switch IndexOfSmallest(distances[:]) {
	case 0:
		result[0] = RectLeft(rect)
	case 1:
		result[0] = RectRight(rect)
	case 2:
		result[1] = RectTop(rect)
	case 3:
		result[1] = RectBottom(rect)
	}
	return result
}

RectContaining :: proc(points: []Vec2) -> Rect {
	if len(points) == 0 {
		return {}
	}
	lo, hi := points[0], points[0]
	for p in points[1:] {
		lo[0] = min(lo[0], p[0])
		lo[1] = min(lo[1], p[1])
		hi[0] = max(hi[0], p[0])
		hi[1] = max(hi[1], p[1])
	}
	return RectBetween(lo, hi)
}

RectCenteredAt :: proc(rect: Rect, position: Vec2) -> Rect {
	return RectCentered(position, RectSize(rect))
}

RectRandomPoint :: proc(rect: Rect, rng: ^Rng) -> Vec2 {
	return RngPointInside(rng, rect)
}
RectGetIntersection :: RectIntersection
RectIntGetIntersection :: RectIntIntersection

RectIntClosestPointOnEdges :: proc(rect: RectInt, point: Vec2) -> Vec2 {
	return RectClosestPointOnEdges(
		Rect{f32(rect.X), f32(rect.Y), f32(rect.Width), f32(rect.Height)},
		point,
	)
}

SignsParse :: proc(value: string) -> Signs {
	if value == "-" {
		return .Negative
	}
	return .Positive
}

SignsFromInt :: proc(value: int, if_zero: Signs = .Positive) -> Signs {
	if value == 0 {
		return if_zero
	}
	if value < 0 {
		return .Negative
	}
	return .Positive
}

SignsFromFloat :: proc(value: f32, if_zero: Signs = .Positive) -> Signs {
	if value == 0 {
		return if_zero
	}
	if value < 0 {
		return .Negative
	}
	return .Positive
}

RectEdges :: proc(rect: Rect) -> [4]Line {
	return [4]Line {
		Line{RectTopRight(rect), RectBottomRight(rect)},
		Line{RectBottomRight(rect), RectBottomLeft(rect)},
		Line{RectBottomLeft(rect), RectTopLeft(rect)},
		Line{RectTopLeft(rect), RectTopRight(rect)},
	}
}

RectOverlapsLine :: proc(rect: Rect, line: Line) -> (bool, Vec2) {
	if RectContains(rect, line.From) {
		return true, line.From
	}
	if RectContains(rect, line.To) {
		return true, line.To
	}
	for edge in RectEdges(rect) {
		hit, point := LineIntersects(edge, line)
		if hit {
			return true, point
		}
	}
	return false, Vec2{}
}

RectOverlapsTriangle :: proc(rect: Rect, tri: Triangle) -> bool {
	if TriangleContains(tri, RectTopLeft(rect)) {
		return true
	}
	hit, _ := RectOverlapsLine(rect, TriangleAB(tri))
	if hit {
		return true
	}
	hit, _ = RectOverlapsLine(rect, TriangleBC(tri))
	if hit {
		return true
	}
	hit, _ = RectOverlapsLine(rect, TriangleCA(tri))
	return hit
}

RectIntValue :: proc(rect: Rect) -> RectInt {
	return RectInt{int(rect.X), int(rect.Y), int(rect.Width), int(rect.Height)}
}

rect_at_vec :: proc(rect: Rect, position: Vec2) -> Rect {
	return Rect{position[0], position[1], rect.Width, rect.Height}
}

RectAtXY :: proc(rect: Rect, x, y: f32) -> Rect {
	return Rect{x, y, rect.Width, rect.Height}
}

RectAtX :: proc(rect: Rect, x: f32) -> Rect {
	return Rect{x, rect.Y, rect.Width, rect.Height}
}

RectAtY :: proc(rect: Rect, y: f32) -> Rect {
	return Rect{rect.X, y, rect.Width, rect.Height}
}
RectAt :: proc {
	rect_at_vec,
	RectAtXY,
}

RectTranslate :: proc(rect: Rect, by: Vec2) -> Rect {
	return Rect{rect.X + by[0], rect.Y + by[1], rect.Width, rect.Height}
}

RectTranslateXY :: proc(rect: Rect, x, y: f32) -> Rect {
	return Rect{rect.X + x, rect.Y + y, rect.Width, rect.Height}
}

rect_inflate :: proc(rect: Rect, by: f32) -> Rect {
	return Rect{rect.X - by, rect.Y - by, rect.Width + by * 2, rect.Height + by * 2}
}

RectInflateXY :: proc(rect: Rect, by_x, by_y: f32) -> Rect {
	return Rect{rect.X - by_x, rect.Y - by_y, rect.Width + by_x * 2, rect.Height + by_y * 2}
}

RectInflateX :: proc(rect: Rect, by_x: f32) -> Rect {
	return Rect{rect.X - by_x, rect.Y, rect.Width + by_x * 2, rect.Height}
}

RectInflateY :: proc(rect: Rect, by_y: f32) -> Rect {
	return Rect{rect.X, rect.Y - by_y, rect.Width, rect.Height + by_y * 2}
}

RectInflateLTRB :: proc(rect: Rect, left, top, right, bottom: f32) -> Rect {
	return Rect{rect.X - left, rect.Y - top, rect.Width + left + right, rect.Height + top + bottom}
}
RectInflate :: proc {
	rect_inflate,
	RectInflateXY,
	RectInflateLTRB,
}

rect_scale :: proc(rect: Rect, by: f32) -> Rect {
	return RectValidateSize(Rect{rect.X * by, rect.Y * by, rect.Width * by, rect.Height * by})
}

RectScaleXY :: proc(rect: Rect, by_x, by_y: f32) -> Rect {
	return RectValidateSize(
		Rect{rect.X * by_x, rect.Y * by_y, rect.Width * by_x, rect.Height * by_y},
	)
}

RectScaleVec :: proc(rect: Rect, by: Vec2) -> Rect {
	return RectScaleXY(rect, by[0], by[1])
}

RectScaleX :: proc(rect: Rect, by_x: f32) -> Rect {
	return RectValidateSize(Rect{rect.X * by_x, rect.Y, rect.Width * by_x, rect.Height})
}

RectScaleY :: proc(rect: Rect, by_y: f32) -> Rect {
	return RectValidateSize(Rect{rect.X, rect.Y * by_y, rect.Width, rect.Height * by_y})
}
RectScale :: proc {
	rect_scale,
	RectScaleXY,
	RectScaleVec,
}

RectValidateSize :: proc(rect: Rect) -> Rect {
	r := rect
	if r.Width < 0 {
		r.X += r.Width
		r.Width = -r.Width
	}
	if r.Height < 0 {
		r.Y += r.Height
		r.Height = -r.Height
	}
	return r
}

RectConflate :: proc(rect, other: Rect) -> Rect {
	return RectBetween(
		Vec2{math.min(RectLeft(rect), RectLeft(other)), math.min(RectTop(rect), RectTop(other))},
		Vec2 {
			math.max(RectRight(rect), RectRight(other)),
			math.max(RectBottom(rect), RectBottom(other)),
		},
	)
}

RectProject :: proc(rect: Rect, axis: Vec2) -> (min, max: f32) {
	points := [4]Vec2 {
		RectTopLeft(rect),
		RectTopRight(rect),
		RectBottomRight(rect),
		RectBottomLeft(rect),
	}
	min = 1e30
	max = -1e30
	for point in points {
		dot := vec2_dot(point, axis)
		min = math.min(min, dot)
		max = math.max(max, dot)
	}
	return
}

RectCentered :: proc(center, size: Vec2) -> Rect {
	return Rect{center[0] - size[0] * 0.5, center[1] - size[1] * 0.5, size[0], size[1]}
}

RectCenteredXY :: proc(cx, cy, width, height: f32) -> Rect {
	return Rect{cx - width * 0.5, cy - height * 0.5, width, height}
}

RectCenteredSize :: proc(size: Vec2) -> Rect {
	return RectCentered(Vec2{}, size)
}

RectJustifiedOrigin :: proc(origin, size, justify: Vec2) -> Rect {
	return Rect {
		origin[0] - size[0] * justify[0],
		origin[1] - size[1] * justify[1],
		size[0],
		size[1],
	}
}

RectJustifiedXY :: proc(origin: Vec2, width, height, justify_x, justify_y: f32) -> Rect {
	return RectJustifiedOrigin(origin, Vec2{width, height}, Vec2{justify_x, justify_y})
}

RectJustifiedSize :: proc(width, height, justify_x, justify_y: f32) -> Rect {
	return RectJustifiedXY(Vec2{}, width, height, justify_x, justify_y)
}
RectJustified :: proc {
	RectJustifiedOrigin,
	RectJustifiedXY,
	RectJustifiedSize,
}

RectJustifiedAt :: proc(rect: Rect, pos, justify: Vec2) -> Rect {
	return Rect {
		pos[0] - rect.Width * justify[0],
		pos[1] - rect.Height * justify[1],
		rect.Width,
		rect.Height,
	}
}

RectBetween :: proc(a, b: Vec2) -> Rect {
	min_x := math.min(a[0], b[0])
	min_y := math.min(a[1], b[1])
	return Rect{min_x, min_y, math.max(a[0], b[0]) - min_x, math.max(a[1], b[1]) - min_y}
}

RectTransform :: proc(rect: Rect, m: Matrix3x2) -> Quad {
	return Quad {
		Matrix3x2TransformPoint(m, RectTopLeft(rect)),
		Matrix3x2TransformPoint(m, RectTopRight(rect)),
		Matrix3x2TransformPoint(m, RectBottomRight(rect)),
		Matrix3x2TransformPoint(m, RectBottomLeft(rect)),
	}
}

RectGetPoint :: proc(rect: Rect, index: int) -> Vec2 {
	switch index {
	case 0:
		return RectTopLeft(rect)
	case 1:
		return RectTopRight(rect)
	case 2:
		return RectBottomRight(rect)
	case 3:
		return RectBottomLeft(rect)
	}
	return Vec2{}
}

RectGetAxis :: proc(rect: Rect, index: int) -> Vec2 {
	if index == 0 {
		return Vec2{1, 0}
	}
	if index == 1 {
		return Vec2{0, 1}
	}
	return Vec2{}
}

// ==============================================================================
// Spatial / RectInt
// ==============================================================================

RectInt :: struct {
	X, Y:          int,
	Width, Height: int,
}

RectIntIdentity :: RectInt{0, 0, 1, 1}

RectIntPosition :: proc(rect: RectInt) -> Point2 {
	return Point2{rect.X, rect.Y}
}

RectIntSize :: proc(rect: RectInt) -> Point2 {
	return Point2{rect.Width, rect.Height}
}

RectIntArea :: proc(rect: RectInt) -> int {
	return rect.Width * rect.Height
}

RectIntLeft :: proc(rect: RectInt) -> int {
	return rect.X
}

RectIntRight :: proc(rect: RectInt) -> int {
	return rect.X + rect.Width
}

RectIntTop :: proc(rect: RectInt) -> int {
	return rect.Y
}

RectIntBottom :: proc(rect: RectInt) -> int {
	return rect.Y + rect.Height
}

RectIntCenter :: proc(rect: RectInt) -> Point2 {
	return Point2{rect.X + rect.Width / 2, rect.Y + rect.Height / 2}
}

RectIntCenterX :: proc(rect: RectInt) -> int {
	return rect.X + rect.Width / 2
}

RectIntCenterY :: proc(rect: RectInt) -> int {
	return rect.Y + rect.Height / 2
}

RectIntMin :: proc(rect: RectInt) -> Point2 {
	return Point2 {
		math.min(RectIntLeft(rect), RectIntRight(rect)),
		math.min(RectIntTop(rect), RectIntBottom(rect)),
	}
}

RectIntMax :: proc(rect: RectInt) -> Point2 {
	return Point2 {
		math.max(RectIntLeft(rect), RectIntRight(rect)),
		math.max(RectIntTop(rect), RectIntBottom(rect)),
	}
}

RectIntTopLeft :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntLeft(rect), RectIntTop(rect)}
}

RectIntTopCenter :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntCenterX(rect), RectIntTop(rect)}
}

RectIntTopRight :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntRight(rect), RectIntTop(rect)}
}

RectIntCenterLeft :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntLeft(rect), RectIntCenterY(rect)}
}

RectIntCenterPoint :: proc(rect: RectInt) -> Point2 {
	return RectIntCenter(rect)
}

RectIntCenterRight :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntRight(rect), RectIntCenterY(rect)}
}

RectIntBottomLeft :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntLeft(rect), RectIntBottom(rect)}
}

RectIntBottomCenter :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntCenterX(rect), RectIntBottom(rect)}
}

RectIntBottomRight :: proc(rect: RectInt) -> Point2 {
	return Point2{RectIntRight(rect), RectIntBottom(rect)}
}

RectIntCenterXF :: proc(rect: RectInt) -> f32 {
	return f32(rect.X) + f32(rect.Width) * 0.5
}

RectIntCenterYF :: proc(rect: RectInt) -> f32 {
	return f32(rect.Y) + f32(rect.Height) * 0.5
}

RectIntTopCenterF :: proc(rect: RectInt) -> Vec2 {
	return Vec2{RectIntCenterXF(rect), f32(RectIntTop(rect))}
}

RectIntCenterLeftF :: proc(rect: RectInt) -> Vec2 {
	return Vec2{f32(RectIntLeft(rect)), RectIntCenterYF(rect)}
}

RectIntCenterF :: proc(rect: RectInt) -> Vec2 {
	return Vec2{RectIntCenterXF(rect), RectIntCenterYF(rect)}
}

RectIntCenterRightF :: proc(rect: RectInt) -> Vec2 {
	return Vec2{f32(RectIntRight(rect)), RectIntCenterYF(rect)}
}

RectIntBottomCenterF :: proc(rect: RectInt) -> Vec2 {
	return Vec2{RectIntCenterXF(rect), f32(RectIntBottom(rect))}
}

rect_int_contains_point :: proc(rect: RectInt, point: Point2) -> bool {
	return(
		point.X >= rect.X &&
		point.Y >= rect.Y &&
		point.X < RectIntRight(rect) &&
		point.Y < RectIntBottom(rect) \
	)
}

RectIntContainsVec2 :: proc(rect: RectInt, point: Vec2) -> bool {
	return(
		point[0] >= f32(rect.X) &&
		point[1] >= f32(rect.Y) &&
		point[0] < f32(RectIntRight(rect)) &&
		point[1] < f32(RectIntBottom(rect)) \
	)
}

RectIntContains :: proc {
	rect_int_contains_point,
	RectIntContainsVec2,
}

RectIntContainsRect :: proc(rect, other: RectInt) -> bool {
	return(
		RectIntLeft(rect) < RectIntLeft(other) &&
		RectIntTop(rect) < RectIntTop(other) &&
		RectIntRight(rect) > RectIntRight(other) &&
		RectIntBottom(rect) > RectIntBottom(other) \
	)
}

rect_int_overlaps_rectint :: proc(rect, other: RectInt) -> bool {
	return(
		RectIntRight(rect) > RectIntLeft(other) &&
		RectIntBottom(rect) > RectIntTop(other) &&
		RectIntLeft(rect) < RectIntRight(other) &&
		RectIntTop(rect) < RectIntBottom(other) \
	)
}

RectIntOverlapsRect :: proc(rect: RectInt, other: Rect) -> bool {
	return(
		f32(RectIntRight(rect)) > RectRight(other) &&
		f32(RectIntBottom(rect)) > RectTop(other) &&
		f32(RectIntLeft(rect)) < RectRight(other) &&
		f32(RectIntTop(rect)) < RectBottom(other) \
	)
}

RectIntConflatePoint :: proc(rect: RectInt, other: Point2) -> RectInt {
	return RectIntBetween(
		Point2{math.min(RectIntLeft(rect), other.X), math.min(RectIntTop(rect), other.Y)},
		Point2{math.max(RectIntRight(rect), other.X), math.max(RectIntBottom(rect), other.Y)},
	)
}

rect_int_conflate_rect :: proc(rect, other: RectInt) -> RectInt {
	min_x := math.min(RectIntLeft(rect), RectIntLeft(other))
	min_y := math.min(RectIntTop(rect), RectIntTop(other))
	max_x := math.max(RectIntRight(rect), RectIntRight(other))
	max_y := math.max(RectIntBottom(rect), RectIntBottom(other))
	return RectInt{min_x, min_y, max_x - min_x, max_y - min_y}
}
RectIntConflate :: proc {
	rect_int_conflate_rect,
	RectIntConflatePoint,
}

RectIntIntersection :: proc(rect, other: RectInt) -> RectInt {
	left := math.max(RectIntLeft(rect), RectIntLeft(other))
	top := math.max(RectIntTop(rect), RectIntTop(other))
	right := math.min(RectIntRight(rect), RectIntRight(other))
	bottom := math.min(RectIntBottom(rect), RectIntBottom(other))
	if right <= left || bottom <= top {
		return RectInt{}
	}
	return RectInt{left, top, right - left, bottom - top}
}

RectIntDifference :: proc(rect, other: RectInt) -> [dynamic]RectInt {
	result: [dynamic]RectInt
	r := RectIntValidateSize(rect)
	o := RectIntValidateSize(other)
	i := RectIntIntersection(r, o)
	if i.Width <= 0 || i.Height <= 0 {
		append(&result, r)
		return result
	}
	if i.Y > r.Y {
		append(&result, RectInt{r.X, r.Y, r.Width, i.Y - r.Y})
	}
	if RectIntBottom(i) < RectIntBottom(r) {
		append(
			&result,
			RectInt{r.X, RectIntBottom(i), r.Width, RectIntBottom(r) - RectIntBottom(i)},
		)
	}
	if i.X > r.X {
		append(&result, RectInt{r.X, i.Y, i.X - r.X, i.Height})
	}
	if RectIntRight(i) < RectIntRight(r) {
		append(&result, RectInt{RectIntRight(i), i.Y, RectIntRight(r) - RectIntRight(i), i.Height})
	}
	return result
}

RectIntAt :: proc(rect: RectInt, position: Point2) -> RectInt {
	return RectInt{position.X, position.Y, rect.Width, rect.Height}
}

RectIntAtXY :: proc(rect: RectInt, x, y: int) -> RectInt {
	return RectInt{x, y, rect.Width, rect.Height}
}

RectIntAtX :: proc(rect: RectInt, x: int) -> RectInt {
	return RectInt{x, rect.Y, rect.Width, rect.Height}
}

RectIntAtY :: proc(rect: RectInt, y: int) -> RectInt {
	return RectInt{rect.X, y, rect.Width, rect.Height}
}

RectIntTranslate :: proc(rect: RectInt, by: Point2) -> RectInt {
	return RectInt{rect.X + by.X, rect.Y + by.Y, rect.Width, rect.Height}
}

RectIntTranslateXY :: proc(rect: RectInt, x, y: int) -> RectInt {
	return RectInt{rect.X + x, rect.Y + y, rect.Width, rect.Height}
}

rect_int_scale :: proc(rect: RectInt, by: int) -> RectInt {
	return RectIntValidateSize(
		RectInt{rect.X * by, rect.Y * by, rect.Width * by, rect.Height * by},
	)
}

RectIntScaleXY :: proc(rect: RectInt, by_x, by_y: int) -> RectInt {
	return RectIntValidateSize(
		RectInt{rect.X * by_x, rect.Y * by_y, rect.Width * by_x, rect.Height * by_y},
	)
}

RectIntScalePoint :: proc(rect: RectInt, by: Point2) -> RectInt {
	return RectIntScaleXY(rect, by.X, by.Y)
}

rect_int_scale_x :: proc(rect: RectInt, by: int) -> RectInt {
	return RectIntValidateSize(RectInt{rect.X * by, rect.Y, rect.Width * by, rect.Height})
}

rect_int_scale_y :: proc(rect: RectInt, by: int) -> RectInt {
	return RectIntValidateSize(RectInt{rect.X, rect.Y * by, rect.Width, rect.Height * by})
}

rect_int_scale_float :: proc(rect: RectInt, by: f32) -> Rect {
	return RectValidateSize(
		Rect{f32(rect.X) * by, f32(rect.Y) * by, f32(rect.Width) * by, f32(rect.Height) * by},
	)
}

RectIntScaleFloatXY :: proc(rect: RectInt, by_x, by_y: f32) -> Rect {
	return RectValidateSize(Rect {
		f32(rect.X) * by_x,
		f32(rect.Y) * by_y,
		f32(rect.Width) * by_x,
		f32(rect.Height) * by_y,
	})
}

RectIntScaleFloatInt :: proc(rect: RectInt, by_x: f32, by_y: int) -> Rect {
	return RectValidateSize(Rect {
		f32(rect.X) * by_x,
		f32(rect.Y) * f32(by_y),
		f32(rect.Width) * by_x,
		f32(rect.Height) * f32(by_y),
	})
}

RectIntScaleIntFloat :: proc(rect: RectInt, by_x: int, by_y: f32) -> Rect {
	return RectValidateSize(Rect {
		f32(rect.X) * f32(by_x),
		f32(rect.Y) * by_y,
		f32(rect.Width) * f32(by_x),
		f32(rect.Height) * by_y,
	})
}

RectIntScaleVec :: proc(rect: RectInt, by: Vec2) -> Rect {
	return RectIntScaleFloatXY(rect, by[0], by[1])
}

RectIntScaleXFloat :: proc(rect: RectInt, by: f32) -> Rect {
	return RectValidateSize(
		Rect{f32(rect.X) * by, f32(rect.Y), f32(rect.Width) * by, f32(rect.Height)},
	)
}

RectIntScaleYFloat :: proc(rect: RectInt, by: f32) -> Rect {
	return RectValidateSize(
		Rect{f32(rect.X), f32(rect.Y) * by, f32(rect.Width), f32(rect.Height) * by},
	)
}
RectIntScaleX :: proc {
	rect_int_scale_x,
	RectIntScaleXFloat,
}
RectIntScaleY :: proc {
	rect_int_scale_y,
	RectIntScaleYFloat,
}
RectIntScale :: proc {
	rect_int_scale,
	RectIntScaleXY,
	RectIntScalePoint,
	rect_int_scale_float,
	RectIntScaleFloatXY,
	RectIntScaleFloatInt,
	RectIntScaleIntFloat,
	RectIntScaleVec,
}

rect_int_inflate :: proc(rect: RectInt, by: int) -> RectInt {
	return RectInt{rect.X - by, rect.Y - by, rect.Width + by * 2, rect.Height + by * 2}
}

RectIntInflateXY :: proc(rect: RectInt, by_x, by_y: int) -> RectInt {
	return RectInt{rect.X - by_x, rect.Y - by_y, rect.Width + by_x * 2, rect.Height + by_y * 2}
}

RectIntInflatePoint :: proc(rect: RectInt, by: Point2) -> RectInt {
	return RectIntInflateXY(rect, by.X, by.Y)
}

rect_int_inflate_x :: proc(rect: RectInt, by: int) -> RectInt {
	return RectInt{rect.X - by, rect.Y, rect.Width + by * 2, rect.Height}
}

rect_int_inflate_y :: proc(rect: RectInt, by: int) -> RectInt {
	return RectInt{rect.X, rect.Y - by, rect.Width, rect.Height + by * 2}
}

RectIntInflateLTRB :: proc(rect: RectInt, left, top, right, bottom: int) -> RectInt {
	return RectInt {
		rect.X - left,
		rect.Y - top,
		rect.Width + left + right,
		rect.Height + top + bottom,
	}
}

rect_int_inflate_float :: proc(rect: RectInt, by: f32) -> Rect {
	return Rect {
		f32(rect.X) - by,
		f32(rect.Y) - by,
		f32(rect.Width) + by * 2,
		f32(rect.Height) + by * 2,
	}
}

RectIntInflateFloatXY :: proc(rect: RectInt, by_x, by_y: f32) -> Rect {
	return Rect {
		f32(rect.X) - by_x,
		f32(rect.Y) - by_y,
		f32(rect.Width) + by_x * 2,
		f32(rect.Height) + by_y * 2,
	}
}

RectIntInflateFloatInt :: proc(rect: RectInt, by_x: f32, by_y: int) -> Rect {
	return Rect {
		f32(rect.X) - by_x,
		f32(rect.Y) - f32(by_y),
		f32(rect.Width) + by_x * 2,
		f32(rect.Height) + f32(by_y) * 2,
	}
}

RectIntInflateIntFloat :: proc(rect: RectInt, by_x: int, by_y: f32) -> Rect {
	return Rect {
		f32(rect.X) - f32(by_x),
		f32(rect.Y) - by_y,
		f32(rect.Width) + f32(by_x) * 2,
		f32(rect.Height) + by_y * 2,
	}
}

RectIntInflateVec :: proc(rect: RectInt, by: Vec2) -> Rect {
	return RectIntInflateFloatXY(rect, by[0], by[1])
}

RectIntInflateFloatLTRB :: proc(rect: RectInt, left, top, right, bottom: f32) -> Rect {
	return Rect {
		f32(rect.X) - left,
		f32(rect.Y) - top,
		f32(rect.Width) + left + right,
		f32(rect.Height) + top + bottom,
	}
}

RectIntInflateXFloat :: proc(rect: RectInt, by: f32) -> Rect {
	return Rect{f32(rect.X) - by, f32(rect.Y), f32(rect.Width) + by * 2, f32(rect.Height)}
}

RectIntInflateYFloat :: proc(rect: RectInt, by: f32) -> Rect {
	return Rect{f32(rect.X), f32(rect.Y) - by, f32(rect.Width), f32(rect.Height) + by * 2}
}
RectIntInflateX :: proc {
	rect_int_inflate_x,
	RectIntInflateXFloat,
}
RectIntInflateY :: proc {
	rect_int_inflate_y,
	RectIntInflateYFloat,
}
RectIntInflate :: proc {
	rect_int_inflate,
	RectIntInflateXY,
	RectIntInflatePoint,
	RectIntInflateLTRB,
	rect_int_inflate_float,
	RectIntInflateFloatXY,
	RectIntInflateFloatInt,
	RectIntInflateIntFloat,
	RectIntInflateVec,
	RectIntInflateFloatLTRB,
}

RectIntValidateSize :: proc(rect: RectInt) -> RectInt {
	r := rect
	if r.Width < 0 {
		r.X += r.Width
		r.Width = -r.Width
	}
	if r.Height < 0 {
		r.Y += r.Height
		r.Height = -r.Height
	}
	return r
}

RectIntCentered :: proc(center, size: Point2) -> RectInt {
	return RectInt{center.X - size.X / 2, center.Y - size.Y / 2, size.X, size.Y}
}

RectIntCenteredXY :: proc(cx, cy, width, height: int) -> RectInt {
	return RectInt{cx - width / 2, cy - height / 2, width, height}
}

RectIntCenteredSize :: proc(size: Point2) -> RectInt {
	return RectIntCentered(Point2{}, size)
}

RectIntJustified :: proc(origin, size: Point2, justify: Vec2) -> RectInt {
	return RectInt {
		origin.X - int(math.round(justify[0] * f32(size.X))),
		origin.Y - int(math.round(justify[1] * f32(size.Y))),
		size.X,
		size.Y,
	}
}

RectIntJustifiedXY :: proc(
	origin: Point2,
	width, height: int,
	justify_x, justify_y: f32,
) -> RectInt {
	return RectIntJustified(origin, Point2{width, height}, Vec2{justify_x, justify_y})
}

RectIntBetween :: proc(a, b: Point2) -> RectInt {
	min_x := math.min(a.X, b.X)
	min_y := math.min(a.Y, b.Y)
	return RectInt{min_x, min_y, math.max(a.X, b.X) - min_x, math.max(a.Y, b.Y) - min_y}
}

RectIntGetPointSector :: proc(rect: RectInt, point: [2]f32) -> u8 {
	sector: u8 = 0
	if point[0] < f32(rect.X) {
		sector |= 0b0001
	}
	if point[0] >= f32(RectIntRight(rect)) {
		sector |= 0b0010
	}
	if point[1] < f32(rect.Y) {
		sector |= 0b0100
	}
	if point[1] >= f32(RectIntBottom(rect)) {
		sector |= 0b1000
	}
	return sector
}

RectIntEdges :: proc(rect: RectInt) -> [4]LineInt {
	return [4]LineInt {
		LineInt{RectIntTopRight(rect), RectIntBottomRight(rect)},
		LineInt{RectIntBottomRight(rect), RectIntBottomLeft(rect)},
		LineInt{RectIntBottomLeft(rect), RectIntTopLeft(rect)},
		LineInt{RectIntTopLeft(rect), RectIntTopRight(rect)},
	}
}

rect_int_rotate_left_origin :: proc(rect: RectInt, origin: Point2) -> RectInt {
	points := [4]Point2 {
		RectIntTopLeft(rect),
		RectIntTopRight(rect),
		RectIntBottomRight(rect),
		RectIntBottomLeft(rect),
	}
	min_p := Point2{1 << 30, 1 << 30}
	max_p := Point2{-1 << 30, -1 << 30}
	for p in points {
		d := Point2{p.X - origin.X, p.Y - origin.Y}
		q := Point2{d.Y, -d.X}
		min_p = Point2{math.min(min_p.X, q.X), math.min(min_p.Y, q.Y)}
		max_p = Point2{math.max(max_p.X, q.X), math.max(max_p.Y, q.Y)}
	}
	return RectInt{min_p.X, min_p.Y, max_p.X - min_p.X, max_p.Y - min_p.Y}
}

rect_int_rotate_right_origin :: proc(rect: RectInt, origin: Point2) -> RectInt {
	points := [4]Point2 {
		RectIntTopLeft(rect),
		RectIntTopRight(rect),
		RectIntBottomRight(rect),
		RectIntBottomLeft(rect),
	}
	min_p := Point2{1 << 30, 1 << 30}
	max_p := Point2{-1 << 30, -1 << 30}
	for p in points {
		d := Point2{p.X - origin.X, p.Y - origin.Y}
		q := Point2{-d.Y, d.X}
		min_p = Point2{math.min(min_p.X, q.X), math.min(min_p.Y, q.Y)}
		max_p = Point2{math.max(max_p.X, q.X), math.max(max_p.Y, q.Y)}
	}
	return RectInt{min_p.X, min_p.Y, max_p.X - min_p.X, max_p.Y - min_p.Y}
}

rect_int_rotate_left :: proc(rect: RectInt) -> RectInt {
	return rect_int_rotate_left_origin(rect, Point2Zero)
}

rect_int_rotate_left_count :: proc(rect: RectInt, count: int) -> RectInt {
	r := rect
	for i := 0; i < count; i += 1 {
		r = rect_int_rotate_left_origin(r, Point2Zero)
	}
	return r
}

rect_int_rotate_left_origin_count :: proc(rect: RectInt, origin: Point2, count: int) -> RectInt {
	r := rect
	for i := 0; i < count; i += 1 {
		r = rect_int_rotate_left_origin(r, origin)
	}
	return r
}

rect_int_rotate_right :: proc(rect: RectInt) -> RectInt {
	return rect_int_rotate_right_origin(rect, Point2Zero)
}

rect_int_rotate_right_count :: proc(rect: RectInt, count: int) -> RectInt {
	r := rect
	for i := 0; i < count; i += 1 {
		r = rect_int_rotate_right_origin(r, Point2Zero)
	}
	return r
}

rect_int_rotate_right_origin_count :: proc(rect: RectInt, origin: Point2, count: int) -> RectInt {
	r := rect
	for i := 0; i < count; i += 1 {
		r = rect_int_rotate_right_origin(r, origin)
	}
	return r
}
RectIntRotateLeft :: proc {
	rect_int_rotate_left,
	rect_int_rotate_left_origin,
	rect_int_rotate_left_count,
	rect_int_rotate_left_origin_count,
}
RectIntRotateRight :: proc {
	rect_int_rotate_right,
	rect_int_rotate_right_origin,
	rect_int_rotate_right_count,
	rect_int_rotate_right_origin_count,
}

RectIntRotate :: proc(rect: RectInt, direction: Cardinal) -> RectInt {
	return rect_int_rotate_right_count(rect, direction.Value)
}

RectIntGetSweep :: proc(rect: RectInt, direction: Cardinal, distance: int) -> RectInt {
	d := distance
	c := direction
	if d < 0 {
		d = -d
		c = CardinalReverse(c)
	}
	switch c.Value {
	case CardinalRightValue:
		return RectInt{rect.X + rect.Width, rect.Y, d, rect.Height}
	case CardinalLeftValue:
		return RectInt{rect.X - d, rect.Y, d, rect.Height}
	case CardinalDownValue:
		return RectInt{rect.X, rect.Y + rect.Height, rect.Width, d}
	case:
		return RectInt{rect.X, rect.Y - d, rect.Width, d}
	}
}

RectIntGetPoint :: proc(rect: RectInt, index: int) -> [2]f32 {
	switch index {
	case 0:
		return [2]f32{f32(rect.X), f32(rect.Y)}
	case 1:
		return [2]f32{f32(RectIntRight(rect)), f32(rect.Y)}
	case 2:
		return [2]f32{f32(RectIntRight(rect)), f32(RectIntBottom(rect))}
	case 3:
		return [2]f32{f32(rect.X), f32(RectIntBottom(rect))}
	}
	panic("RectInt point index out of range")
}

RectIntGetAxis :: proc(rect: RectInt, index: int) -> [2]f32 {
	if index == 0 {
		return [2]f32{1, 0}
	}
	if index == 1 {
		return [2]f32{0, 1}
	}
	panic("RectInt axis index out of range")
}

RectIntPoints :: proc(rect: RectInt) -> int {
	return 4
}

RectIntAxes :: proc(rect: RectInt) -> int {
	return 2
}

RectIntEnumeratePoints :: proc(rect: RectInt) -> [dynamic]Point2 {
	points: [dynamic]Point2
	if rect.Width <= 0 || rect.Height <= 0 {
		return points
	}
	reserve(&points, rect.Width * rect.Height)
	for y := 0; y < rect.Height; y += 1 {
		for x := 0; x < rect.Width; x += 1 {
			append(&points, Point2{rect.X + x, rect.Y + y})
		}
	}
	return points
}

RectIntEnumerateEdges :: proc(rect: RectInt) -> [4]LineInt {
	return RectIntEdges(rect)
}

RectIntOverlapsLine :: proc(rect: RectInt, line: Line) -> bool {
	sec_a := RectIntGetPointSector(rect, line.From)
	sec_b := RectIntGetPointSector(rect, line.To)
	if sec_a == 0 || sec_b == 0 {
		return true
	}
	if (sec_a & sec_b) != 0 {
		return false
	}
	for edge in RectIntEdges(rect) {
		edge_line := Line {
			Vec2{f32(edge.From.X), f32(edge.From.Y)},
			Vec2{f32(edge.To.X), f32(edge.To.Y)},
		}
		if hit, _ := LineIntersects(edge_line, line); hit {
			return true
		}
	}
	return false
}

RectIntOverlapsLineInt :: proc(rect: RectInt, line: LineInt) -> bool {
	sec_a := RectIntGetPointSector(rect, [2]f32{f32(line.From.X), f32(line.From.Y)})
	sec_b := RectIntGetPointSector(rect, [2]f32{f32(line.To.X), f32(line.To.Y)})
	if sec_a == 0 || sec_b == 0 {
		return true
	}
	if (sec_a & sec_b) != 0 {
		return false
	}
	for edge in RectIntEdges(rect) {
		if LineIntIntersects(edge, line) {
			return true
		}
	}
	return false
}

RectIntOverlaps :: proc {
	rect_int_overlaps_rectint,
	RectIntOverlapsRect,
	RectIntOverlapsLine,
	RectIntOverlapsLineInt,
}

// ==============================================================================
// Spatial / Signs
// ==============================================================================

Signs :: enum {
	Positive,
	Negative,
}

// ==============================================================================
// Spatial / Transform
// ==============================================================================

// ------------------------------------------------------------------------------
// Spatial / Transform / Matrix3x2 — 仿射变换适配
// ------------------------------------------------------------------------------

Matrix3x2 :: struct {
	M11, M12: f32,
	M21, M22: f32,
	M31, M32: f32,
}

Matrix3x2Identity :: Matrix3x2{1, 0, 0, 1, 0, 0}

Matrix3x2TransformPoint :: proc(m: Matrix3x2, point: Vec2) -> Vec2 {
	return Vec2 {
		point[0] * m.M11 + point[1] * m.M21 + m.M31,
		point[0] * m.M12 + point[1] * m.M22 + m.M32,
	}
}

Matrix3x2Inverse :: proc(m: Matrix3x2) -> (Matrix3x2, bool) {
	determinant := m.M11 * m.M22 - m.M12 * m.M21
	if math.abs(determinant) <= 1e-8 {
		return Matrix3x2Identity, false
	}
	inv := 1 / determinant
	result := Matrix3x2 {
		M11 = m.M22 * inv,
		M12 = -m.M12 * inv,
		M21 = -m.M21 * inv,
		M22 = m.M11 * inv,
	}
	result.M31 = -(m.M31 * result.M11 + m.M32 * result.M21)
	result.M32 = -(m.M31 * result.M12 + m.M32 * result.M22)
	return result, true
}

Matrix3x2Translation :: proc(x, y: f32) -> Matrix3x2 {
	return Matrix3x2{1, 0, 0, 1, x, y}
}

Matrix3x2Rotation :: proc(radians: f32) -> Matrix3x2 {
	c, s := math.cos(radians), math.sin(radians)
	return Matrix3x2{c, s, -s, c, 0, 0}
}

// 缩放矩阵。注意与 Matrix3x2Scale（从矩阵提取缩放）方向相反。

Matrix3x2Scaling :: proc(x, y: f32) -> Matrix3x2 {
	return Matrix3x2{x, 0, 0, y, 0, 0}
}

// 复合矩阵 a*b：行向量约定下（v' = v*M），先应用 a 再应用 b，
// 与 System.Numerics 的 Matrix3x2.Multiply 一致。

Matrix3x2Multiply :: proc(a, b: Matrix3x2) -> Matrix3x2 {
	return Matrix3x2 {
		a.M11 * b.M11 + a.M12 * b.M21,
		a.M11 * b.M12 + a.M12 * b.M22,
		a.M21 * b.M11 + a.M22 * b.M21,
		a.M21 * b.M12 + a.M22 * b.M22,
		a.M31 * b.M11 + a.M32 * b.M21 + b.M31,
		a.M31 * b.M12 + a.M32 * b.M22 + b.M32,
	}
}

Transform :: struct {
	Position:       Vec2,
	Scale:          Vec2,
	Rotation:       f32,
	TransformIndex: int,
	matrix_dirty:   bool,
	inverse_dirty:  bool,
	cached_matrix:  Matrix3x2,
	cached_inverse: Matrix3x2,
}

TransformIdentity :: Transform {
	Scale          = Vec2{1, 1},
	cached_matrix  = Matrix3x2Identity,
	cached_inverse = Matrix3x2Identity,
}

TransformMake :: proc(position: Vec2 = {}, scale: Vec2 = {1, 1}, rotation: f32 = 0) -> Transform {
	return Transform {
		Position      = position,
		Scale         = scale,
		Rotation      = rotation,
		matrix_dirty  = true,
		inverse_dirty = true,
	}
}

TransformCreateMatrix :: proc(position, origin, scale: Vec2, rotation: f32) -> Matrix3x2 {
	cosine := math.cos(rotation)
	sine := math.sin(rotation)
	m := Matrix3x2 {
		M11 = cosine * scale[0],
		M12 = sine * scale[0],
		M21 = -sine * scale[1],
		M22 = cosine * scale[1],
	}
	m.M31 = position[0] - origin[0] * m.M11 - origin[1] * m.M21
	m.M32 = position[1] - origin[0] * m.M12 - origin[1] * m.M22
	return m
}

transform_dirty :: proc(transform: ^Transform) {
	transform.TransformIndex += 1
	transform.matrix_dirty = true
	transform.inverse_dirty = true
}

TransformSetPosition :: proc(transform: ^Transform, position: Vec2) {
	if transform.Position != position {
		transform.Position = position
		transform_dirty(transform)
	}
}

TransformSetScale :: proc(transform: ^Transform, scale: Vec2) {
	if transform.Scale != scale {
		transform.Scale = scale
		transform_dirty(transform)
	}
}

TransformSetRotation :: proc(transform: ^Transform, rotation: f32) {
	if transform.Rotation != rotation {
		transform.Rotation = rotation
		transform_dirty(transform)
	}
}

TransformMatrix :: proc(transform: ^Transform) -> Matrix3x2 {
	if transform.matrix_dirty {
		transform.cached_matrix = TransformCreateMatrix(
			transform.Position,
			Vec2{},
			transform.Scale,
			transform.Rotation,
		)
		transform.matrix_dirty = false
	}
	return transform.cached_matrix
}

TransformMatrixInverse :: proc(transform: ^Transform) -> Matrix3x2 {
	if transform.inverse_dirty {
		transform.cached_inverse, _ = Matrix3x2Inverse(TransformMatrix(transform))
		transform.inverse_dirty = false
	}
	return transform.cached_inverse
}

TransformPoint :: proc(transform: ^Transform, point: Vec2) -> Vec2 {
	return Matrix3x2TransformPoint(TransformMatrix(transform), point)
}

TransformPointInverse :: proc(transform: ^Transform, point: Vec2) -> Vec2 {
	return Matrix3x2TransformPoint(TransformMatrixInverse(transform), point)
}

// ==============================================================================
// Spatial / Triangle
// ==============================================================================

Triangle :: struct {
	A, B, C: Vec2,
}

TriangleMake :: proc(a, b, c: Vec2) -> Triangle {
	return Triangle{a, b, c}
}

TriangleAB :: proc(t: Triangle) -> Line {
	return Line{t.A, t.B}
}

TriangleBC :: proc(t: Triangle) -> Line {
	return Line{t.B, t.C}
}

TriangleCA :: proc(t: Triangle) -> Line {
	return Line{t.C, t.A}
}

TriangleArea :: proc(t: Triangle) -> f32 {
	return math.abs(
		(t.A[0] * (t.B[1] - t.C[1]) + t.B[0] * (t.C[1] - t.A[1]) + t.C[0] * (t.A[1] - t.B[1])) *
		0.5,
	)
}

TriangleBounds :: proc(t: Triangle) -> Rect {
	return RectBetween(Vec2 {
		math.min(t.A[0], math.min(t.B[0], t.C[0])),
		math.min(t.A[1], math.min(t.B[1], t.C[1])),
	}, Vec2 {
		math.max(t.A[0], math.max(t.B[0], t.C[0])),
		math.max(t.A[1], math.max(t.B[1], t.C[1])),
	})
}

TriangleCenter :: proc(t: Triangle) -> Vec2 {
	return RectCenter(TriangleBounds(t))
}

TriangleAverage :: proc(t: Triangle) -> Vec2 {
	return vec2_scale(vec2_add(vec2_add(t.A, t.B), t.C), 1.0 / 3.0)
}

triangle_cross :: proc(a, b: Vec2) -> f32 {
	return a[0] * b[1] - a[1] * b[0]
}

TriangleContains :: proc(t: Triangle, point: Vec2) -> bool {
	d0 := triangle_cross(vec2_sub(t.B, t.A), vec2_sub(point, t.A))
	d1 := triangle_cross(vec2_sub(t.C, t.B), vec2_sub(point, t.B))
	d2 := triangle_cross(vec2_sub(t.A, t.C), vec2_sub(point, t.C))
	return (d0 >= 0 && d1 >= 0 && d2 >= 0) || (d0 <= 0 && d1 <= 0 && d2 <= 0)
}

TriangleProject :: proc(t: Triangle, axis: Vec2) -> (min, max: f32) {
	a := vec2_dot(t.A, axis)
	b := vec2_dot(t.B, axis)
	c := vec2_dot(t.C, axis)
	return math.min(a, math.min(b, c)), math.max(a, math.max(b, c))
}
