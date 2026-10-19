# Render3D

用 `model / models` 记录静态模型，用 `line / aabb` 等记录调试线，最后 `submit`。
同一份记录可以提交给多个视图和 Pass，只有 `clear` 才清空。
直接使用 Foster Mesh、公共材质和原来的 Camera3D，不需要再创建模型或相机包装对象。

## 最小用法

```odin
import r3d "olib:kit/rendering/3d"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// 初始化：materials 已登记效果，mesh 已通过 mesh_upload 上传。
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
shadow_view.draw_debug = false
err := r3d.submit(&renderer, shadow_view, "shadow")
err = r3d.submit(&renderer, main_view, "body")
err = r3d.submit(&renderer, main_view, "outline")
// 记录仍完整，可以再次提交；下一帧重新记录前 clear。
```

目标创建、清理和阶段间资源绑定由游戏负责。View 也可直接填写游戏自己的正交矩阵；
view_matrix 必填（相机用 `world.camera3d_view`）：排序深度和调试线朝向都靠它，零矩阵时 submit 返回 `.Missing_View_Matrix`。
draw_debug 未指定时开启；调试线在模型之后画，默认深度测试、不写深度，不参与材质 Pass。
线宽和深度开关在 `renderer.debug.thickness / depth_test_enabled`，还有 `sphere / frustum / axis / grid / skeleton`。

非空 pass_id 只选同名 Pass：不含该 ID 的材质跳过；所有模型记录都没有这个 ID 才返回 `.Unknown_Pass`，
已声明但禁用的 Pass 不绘制。空 pass_id 按效果声明顺序画所有启用的 Pass。
含透明 Pass 的多 Pass 对象保留逐对象的 Pass 顺序；要全场景分阶段就显式多次 submit。

## 剔除、排序与生命周期

- model/models 的 bounds 是网格的**局部 AABB**，记录时变换八角得到世界盒，每次 submit 用当前 VP 独立剔除。
  不传 bounds 就保守保留。Shader 外扩、位移的范围需要包含在盒内。
- 深度取视矩阵下的世界盒中心，无盒时取矩阵平移点。不透明按材质和绑定快照分组，组按最近深度排列，
  组内前到后；透明全局后到前，同深度稳定。透明合批不会跨越其他对象。
- 同网格不保证只有一次 Draw：材质快照不同、排序中的其他网格、透明多 Pass 都会形成批次边界。
- 记录复制 CPU 实例、矩阵、bounds 和材质数值/贴图绑定；之后修改材质值只影响新记录。
  Mesh、Shader、纹理和常驻缓冲仍借用到 clear/dispose，**重载或销毁资源前先 clear**。
- submit 先验证候选再绘制，错误不消耗记录；空提交成功。clear 保留容量，不清颜色/深度附件。
- **Render2D 的 submit 会清空，Render3D 的 submit 会保留**。混合绘制时由游戏安排两者的提交顺序，
  UI 在最终输出像素尺寸绘制。

常驻 `Model_Buffer`、手写 `Render_Queue`、LOD 和 Shader Lab 集成见 [REFERENCE](REFERENCE.md)。
材质登记/重载见 [公共材质资源](../material/README.md#公共材质资源)。
可运行示例：olib_sample 的 `material3d`；手写光照渲染器：`forward3d`。
