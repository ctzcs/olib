# Render3D

用 `model / models` 记录静态模型，用 `line / aabb` 等记录调试线，最后 `submit`。
同一份记录可以提交给多个视图和 Pass，只有 `clear` 才清空。
直接使用 Foster Mesh、公共材质和原来的 Camera3D，不需要再创建模型或相机包装对象。

## 最小用法

```odin
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// 初始化：materials 已登记 Shader，mesh 已通过 mesh_upload 上传。
material, reason := mat.material_load(&materials, "materials/hero.json")
renderer: r3d.Render3D
reason = r3d.init(&renderer, &materials) // 空串成功

// 每帧：先用 Foster 清理 scene 的颜色/深度附件，再记录。
r3d.clear(&renderer)
err := r3d.model(&renderer, &mesh, material, transform, bounds = &primitive.bounds)
r3d.aabb(&renderer, world_bounds, {1, 0.6, 0.2, 1})
world.camera3d_set_viewport(&camera, scene.WidthInPixels, scene.HeightInPixels)
view := r3d.View{
	target = scene,
	view_projection = world.camera3d_view_projection(&camera),
	view_matrix = world.camera3d_view(&camera), time = elapsed,
}
err = r3d.submit(&renderer, view)
// 检查每个 err：.None 成功，mat.draw_error_text(err) 给出原因。

// 退出：先释放记录器，再释放它借用的资源。
r3d.dispose(&renderer)
r3d.mesh_dispose(&mesh)
mat.material_library_dispose(&materials)
```

`model` 的 tint 为白色；`models` 直接接收已有的 `[]Model_Item`，使用每项的 world 和 tint：

```odin
err := r3d.models(&renderer, &tree_mesh, tree_material, trees, bounds = &tree_bounds)
```

普通材质逐个画。声明 instanced 的材质自动使用实例缓冲：排序后相邻的同 Mesh、同材质、
相同参数/贴图绑定记录合成一次实例化 Draw；单个 `model` 也能画，不要求业务创建缓冲。
不同的实例字段值不会拆批。`model(..., values = &overrides)` 使用 `mat.Instance_Values`；
`models(..., values = values)` 使用平铺 `[][4]f32`，每个实例连续 `mat.instance_slot_count(material)` 个 float4。
省略 values 沿用材质默认值，覆盖优先级是材质 → 本次实例值 → 各 Pass 固定值。

## 多视图与 Pass

```odin
err := r3d.submit(&renderer, shadow_view, "shadow")
err = r3d.submit(&renderer, main_view, "body")
main_view.draw_debug = true // 分阶段提交默认不画调试线，只在最后一次开启
err = r3d.submit(&renderer, main_view, "outline")
// 记录仍完整，可以再次提交；下一帧重新记录前 clear。
```

目标创建、清理和阶段间资源绑定由游戏负责。View 也可直接填写游戏自己的正交矩阵；
view_matrix 必填（相机用 `world.camera3d_view`）：排序深度、调试线朝向和材质的 CameraPosition 都靠它，
零矩阵时 submit 返回 `.Missing_View_Matrix`。
draw_debug 未指定时只在空 pass_id（画全部 Pass）的提交里画调试线，指定 pass_id 的分阶段提交默认不画，
不会重复叠加或画进阴影图；显式 true/false 优先。调试线在模型之后画，默认深度测试、不写深度，不参与材质 Pass。
线宽和深度开关在 `renderer.debug.thickness / depth_test_enabled`，还有 `sphere / frustum / axis / grid / skeleton`。

非空 pass_id 只选同名 Pass：不含该 ID 的材质跳过；所有模型记录都没有这个 ID 才返回 `.Unknown_Pass`，
已声明但禁用的 Pass 不绘制。空 pass_id 按 Shader 声明顺序画所有启用的 Pass。
含透明 Pass 的多 Pass 对象保留逐对象的 Pass 顺序；要全场景分阶段就显式多次 submit。

**剪影**（角色被墙挡住的部分画成纯色）用 `ZTest Greater`、`ZWrite Off` 的 Pass，按 场景 → 剪影 → 角色本体 分三次提交：
剪影要在遮挡物写完深度之后、本体写深度之前画，否则会叠到角色自己被挡住的部位上。
pass_id 只按名字筛选，所以场景材质与角色要用不同的 Pass id（如 `scene` / `silhouette` / `body`），或把角色放进另一个 Render3D。
ZTest 支持 `Less / Less_Equal / Equal / Always / Greater / Greater_Equal / Not_Equal / Never`，`Off` 关闭测试。
完整示例见 olib_sample 的 `stylized3d`。

## 相机、视图块与运行时贴图

材质 Shader 从宿主帧块和视图块拿到每个视图的数据，从材质参数和贴图拿到逐材质的数据：

- **相机位置**：顶点 b0 与片元 b0 都带 `CameraPosition`（世界坐标 xyz，w = 1），由 View 的 view_matrix 求逆得到。
  同一份记录提交给多个视图时各自正确，菲涅尔、边缘光、高光用它算视线方向。布局见 [REFERENCE](REFERENCE.md#模型材质-shader-布局)。
- **视图块**：`View.globals` 是游戏按 std140 打包的字节（太阳方向、雾色、billboard 的相机轴等），库不定义其中字段。
  Model Pass 从顶点 b1 / 片元 b2 读取同一份数据；每次 Draw 提交 `mat.VIEW_GLOBALS_SIZE`（1024）字节，不足补零，
  超长时 submit 返回 `.View_Globals_Too_Large`，Shader 声明的块不能超过这个大小。只在 submit 期间借用。
- **数据放哪**：逐视图的值（相机轴、某个视图关雾）只能放视图块，因为同一份记录会提交给多个视图，记录时已快照材质值；
  所有材质共用的值（太阳、雾）放视图块写一次即可，不必逐个材质设置；逐材质的值用材质参数，记录前 `mat.material_set_number`。
- **运行时贴图**：阴影图、反射等 Target 附件用 `mat.material_set_texture(material, "Body", "shadow", foster.TargetAttachment(&shadow))`
  绑进材质的 Texture 字段，nil 恢复白色默认贴图。贴图借用到 clear；`material_reload` 会恢复材质文件里的贴图。
  `TargetAttachment` 默认取颜色附件；深度附件（index 1）只有单采样才能采样，多采样深度会被拒绝（返回 false）。
- **读场景深度**：后处理采样场景深度附件时要画到另一张 Target，深度附件不能在仍是当前深度目标时采样。
  采样得到的是 [0,1] 的硬件深度，换回距离：`near * far / (far - d * (far - near))`（kit/world 透视矩阵），near/far 由游戏传入。
- **采样方式**：在 .oshader 的 2D 属性前写 `[Filter(Nearest)]`、`[Wrap(Repeat)]`（默认 Linear、Clamp），
  平铺地面、像素风贴图按字段声明，材质库与 material_set_texture 都按它创建采样器。

```odin
// 布局与 Shader 里的 SceneView 一致；全用 float4 时 std140 不需要补齐。
Scene_View :: struct { sun_direction, fog_color, camera_right, camera_up: [4]f32 }
globals := Scene_View{...} // 每个视图一份
view.globals = mem.ptr_to_bytes(&globals)
err := r3d.submit(&renderer, view, "scene")
```

```hlsl
#include "olib/model.hlsli"   // 引擎块；片元 b0 为 Clock、Pointer、Tint、CameraPosition
struct SceneView { float4 sun_direction; float4 fog_color; float4 camera_right; float4 camera_up; };
cbuffer VertexViewBlock : register(b1, space1) { SceneView VertexView; };   // 顶点读视图块
cbuffer FragmentViewBlock : register(b2, space3) { SceneView FragmentView; }; // 片元读同一份
// 片元里：float3 view_dir = normalize(CameraPosition.xyz - v.WorldPosition);
```

Shader Lab 预览提交全零的视图块；Shader 可以按某个标记分量为零时换成默认值，同一份源码不改就能预览。

## 剔除、排序与生命周期

- model/models 的 bounds 是网格的**局部 AABB**，记录时变换八角得到世界盒，每次 submit 用当前 VP 独立剔除。
  不传 bounds 就保守保留。Shader 外扩、位移的范围需要包含在盒内。
- 深度取视矩阵下的世界盒中心，无盒时取矩阵平移点。不透明按材质和绑定快照分组，组按最近深度排列，
  组内前到后；透明全局后到前，同深度稳定。透明合批不会跨越其他对象。
- 同网格不保证只有一次 Draw：材质快照不同、排序中的其他网格、透明多 Pass 都会形成批次边界。
- 记录复制 CPU 实例、矩阵、bounds、材质数值/贴图绑定以及当时的 Shader；之后修改或重载材质只影响新记录，
  已记录的对象仍按原快照绘制。Mesh、Shader、纹理和常驻缓冲仍借用到 clear/dispose，**销毁这些资源前先 clear**。
- submit 先验证候选再绘制，错误不消耗记录；空提交成功。clear 保留容量，不清颜色/深度附件。
- **Render2D 的 submit 会清空，Render3D 的 submit 会保留**。混合绘制时由游戏安排两者的提交顺序，
  UI 在最终输出像素尺寸绘制。

常驻 `Model_Buffer`、手写 `Render_Queue`、LOD 和 Shader Lab 集成见 [REFERENCE](REFERENCE.md)。
材质登记/重载见 [公共材质资源](../material/README.md#公共材质资源)。
可运行示例：olib_sample 的 `material3d`；手写光照渲染器：`forward3d`。
