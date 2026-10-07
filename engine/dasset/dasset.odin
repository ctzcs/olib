// dasset —— .dasset 模型格式的数据层（对位 DragonLib Assets/Dasset）。
//
// cook 产物（纯数据，不碰 GPU）：贴图表 + 逐 primitive 顶点/索引/材质/AABB
// + 骨架/动画剪辑。静态 primitive 的节点变换烘焙进顶点；蒙皮 primitive
// 顶点保持 mesh bind 空间，由骨骼 palette 驱动（见 SkeletonAnimator）。
//
// 类型只用裸数组（[3]f32 / [4]f32），不依赖 Foster/world——数据层可独立
// 测试；矩阵按 System.Numerics 的 M11..M44 行主序存 [16]f32。
//
// 分区：
//   格式常量 —— magic/version/顶点步长
//   基础类型 —— Bounds / 顶点 / 贴图 / 材质
//   几何 —— Primitive / Model
//   蒙皮与动画 —— Joint / Skeleton / Channel / Clip
package dasset

import "core:math"

// ------------------------------------------------------------------------------
// 格式常量
// ------------------------------------------------------------------------------

// 文件头魔数，little-endian 写出即 ASCII "DAST"。
DASSET_MAGIC :: u32(0x54534144)

// 当前格式版本（v3:PBR 材质；v4:channel 插值与 cubic 切线）。
// Reader 兼容 1..4；布局变更时 bump 并同步读写两端。
DASSET_VERSION :: i32(4)

DASSET_VERTEX_STRIDE_STATIC :: 48 // PositionNormalUv：pos3+normal3+uv2+tangent4
DASSET_VERTEX_STRIDE_SKIN :: 68 // 上者 + joints(u32) + weights4

// 顶点布局标记（随 primitive 写入文件）。
Dasset_Vertex_Layout :: enum i32 {
	Position_Normal_Uv = 0, // 静态，节点变换已烘焙
	Position_Normal_Uv_Skin = 1, // 蒙皮，顶点在 mesh bind 空间
}

// 材质透明模式（与 glTF alphaMode 对齐）。
Dasset_Alpha_Mode :: enum i32 {
	Opaque = 0,
	Mask = 1,
	Blend = 2,
}

// 贴图字节编码。新版 cooker 将 JPEG 转 PNG；Jpg 保留以读旧数据。
Dasset_Texture_Codec :: enum i32 {
	Png = 0,
	Jpg = 1,
}

// 动画 channel 的目标分量（与 glTF PropertyPath 对齐）。
Dasset_Anim_Path :: enum i32 {
	Translation = 0,
	Rotation = 1,
	Scale = 2,
}

Dasset_Interpolation :: enum i32 {
	Linear = 0,
	Step = 1,
	Cubic_Spline = 2,
}

// ------------------------------------------------------------------------------
// 基础类型 —— Bounds / 顶点 / 贴图 / 材质
// ------------------------------------------------------------------------------

// 轴对齐包围盒（min/max）。cook 时由烘焙后的顶点算出，运行时供视锥剔除用。
Dasset_Bounds :: struct {
	min: [3]f32,
	max: [3]f32,
}

// 反转极值的"空"盒：encapsulate 任意点后即为正常盒。
DASSET_BOUNDS_EMPTY :: Dasset_Bounds{
	min = {math.INF_F32, math.INF_F32, math.INF_F32},
	max = {-math.INF_F32, -math.INF_F32, -math.INF_F32},
}

// 与 DragonLib PositionNormalUvVertex 二进制一致（48B）。
Dasset_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
	tangent:  [4]f32,
}

// 与 DragonLib PositionNormalUvSkinVertex 二进制一致（68B）：
// 4 个关节下标打包进 joints（byte0 | byte1<<8 | …）。
Dasset_Skin_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
	tangent:  [4]f32,
	joints:   u32,
	weights:  [4]f32,
}

// 贴图表条目：编码后的 PNG 字节，运行时由解码器解出；JPEG 在 cook 阶段转换。
Dasset_Texture_Entry :: struct {
	name:  string, // 克隆，随 model dispose
	codec: Dasset_Texture_Codec,
	bytes: []u8, // 克隆
}

// 材质的纯数据记录：PBR 数值参数 + 贴图表索引（-1 表示无）。
Dasset_Material :: struct {
	base_color_factor:               [4]f32,
	metallic:                        f32,
	roughness:                       f32,
	double_sided:                    bool,
	alpha_mode:                      Dasset_Alpha_Mode,
	alpha_cutoff:                    f32,
	albedo_texture_index:            i32,
	normal_texture_index:            i32,
	metallic_roughness_texture_index: i32, // v3+
	occlusion_texture_index:         i32, // v3+
	occlusion_strength:              f32, // v3+
	emissive_texture_index:          i32, // v3+
	emissive_factor:                 [3]f32, // v3+
	normal_scale:                    f32, // v3+
}

DASSET_MATERIAL_DEFAULT :: Dasset_Material{
	base_color_factor = {1, 1, 1, 1},
	roughness         = 1,
	alpha_cutoff      = 0.5,
	albedo_texture_index = -1,
	normal_texture_index = -1,
	metallic_roughness_texture_index = -1,
	occlusion_texture_index = -1,
	emissive_texture_index = -1,
	occlusion_strength = 1,
	normal_scale = 1,
}

// ------------------------------------------------------------------------------
// 几何 —— Primitive / Model
// ------------------------------------------------------------------------------

// 一个可绘制单元的纯数据：顶点/索引 + 材质 + 自身 AABB。
// 静态与蒙皮二选一：skin_vertices 非空即蒙皮（skin_index 指向模型骨架表）。
Dasset_Primitive :: struct {
	vertices:     []Dasset_Vertex, // 静态顶点（非蒙皮时有效）
	skin_vertices: []Dasset_Skin_Vertex, // 蒙皮顶点（非空即蒙皮）
	skin_index:   i32, // 使用的骨架下标；静态为 -1

	indices:  []u32, // 从外侧看 CCW 的三角形列表
	material: Dasset_Material,
	bounds:   Dasset_Bounds,
}

dasset_primitive_is_skinned :: proc(p: ^Dasset_Primitive) -> bool {
	return p.skin_vertices != nil
}

// cook 产物。所有字符串/字节/数组均为深拷贝，dasset_model_dispose 统一释放。
Dasset_Model :: struct {
	textures:   [dynamic]Dasset_Texture_Entry,
	primitives: [dynamic]Dasset_Primitive,
	skeletons:  [dynamic]Dasset_Skeleton, // v2+；蒙皮模型通常 1 个
	clips:      [dynamic]Dasset_Animation_Clip, // v2+
	bounds:     Dasset_Bounds,
}

// ------------------------------------------------------------------------------
// 蒙皮与动画 —— Joint / Skeleton / Channel / Clip
// ------------------------------------------------------------------------------

// 骨架中的一个关节。joints 按拓扑序存储（父先于子），传播时一次线性扫描即可。
Dasset_Joint :: struct {
	name: string, // 克隆

	parent_index: i32, // 父关节下标；-1 为根

	bind_translation: [3]f32, // bind pose 本地 TRS（channel 未覆盖时的静止值）
	bind_rotation:    [4]f32, // 四元数 xyzw
	bind_scale:       [3]f32,

	// inverse bind matrix：mesh bind 空间 -> 关节 bind 局部空间（M11..M44 行主序）。
	inverse_bind_matrix: [16]f32,
}

// 骨架（蒙皮 skin）：拓扑序的关节列表。运行时姿态 = 采样剪辑改本地 TRS ->
// 沿树传播全局矩阵 -> palette[i] = InverseBind[i] * Global[i]（行向量约定）。
Dasset_Skeleton :: struct {
	joints: [dynamic]Dasset_Joint,
}

// 关键帧值与 cubic 入/出切线分别存储；rotation 是 xyzw，其余用 xyz(w)。
Dasset_Animation_Channel :: struct {
	joint_index:   i32,
	path:          Dasset_Anim_Path,
	interpolation: Dasset_Interpolation,
	times:         []f32,
	values:        [][4]f32,
	in_tangents:   [][4]f32, // 仅 Cubic_Spline
	out_tangents:  [][4]f32, // 仅 Cubic_Spline
}

// 一条动画剪辑。
Dasset_Animation_Clip :: struct {
	name:    string,
	skin_index: i32, // 作用的骨架下标
	duration:   f32,
	channels:   [dynamic]Dasset_Animation_Channel,
}
