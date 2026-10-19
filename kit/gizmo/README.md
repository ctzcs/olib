# Gizmo

`olib:kit/gizmo` 提供二维 `Transform_Gizmo2D`、三维 `Transform_Gizmo`，
并保留移动专用的 `Translation_Gizmo`。使用现有的 `world.Camera2D` / `world.Camera3D`，
三维手柄使用世界空间网格与深度测试，二维手柄使用 Render2D，返回拖拽结果；不读取窗口输入、不依赖 Clay、不识别模型、
不修改场景或保存文件。目前没有三维平面移动手柄、矩形边角编辑、吸附与负缩放。

## 二维操作

`Transform_Gizmo2D` 零值可用，接口为 `transform2d_update / geometry / hit / draw`。
共用 `Mode`、`Translation_Input`、`DEFAULT_TRANSLATION_STYLE` 和拖拽生命周期；
二维数学独立使用 Camera2D 的正逆变换，不需要三维射线。

| Mode | 手柄 | axis |
| --- | --- | --- |
| `.Translate` | 世界 X/Y 箭头，中心方块自由移动 | 0 / 1 / 3 |
| `.Rotate` | 绕对象原点的单个圆环 | 2（Z） |
| `.Scale` | 局部 X/Y 轴端方块，中心方块等比缩放 | 0 / 1 / 3 |

`Transform2D` 包含 position: Vec2、rotation: f32、scale: Vec2。
与 Camera2D 一致，Y 向下，rotation 单位弧度；正角度在未旋转的相机中顺时针。
对象先缩放，再绕原点旋转，再平移。单位 scale 必须显式写 `{1, 1}`。
轴长、环半径、命中范围按最终输出像素和 UI scale 计算，不随相机 zoom 放大。
缩放中心向右上拖动放大、左下缩小，默认正值范围同三维工具。

```odin
handle: gizmo.Transform_Gizmo2D // 由调用方跨帧保存
value := gizmo.Transform2D{scale = {1, 1}}
result := gizmo.transform2d_update(&handle, camera2d, value, viewport, mode, input, ui_scale)
if result.changed {
	// 提交 result.transform 给自己的规则 / 编辑命令。
}
geometry := gizmo.transform2d_geometry(camera2d, accepted_value, viewport, mode, ui_scale)
labels := gizmo.transform2d_draw(batch, &handle, geometry, input.pointer, ui_scale)
```

`viewport` 与 pointer 均为最终输出像素，支持非零偏移；相机 viewport_size 必须等于其宽高。
`project2d` 返回世界点的最终屏幕坐标。使用 Camera2D 的 setter 更新相机，直接写字段后要 set_dirty。
相机必须可逆，zoom / ppu 必须为有限正数；不匹配视口或无效变换不能开始拖动。
相机平移、旋转、缩放、视口、模式或 UI scale 变化会中断拖动，捕获保持至松开。
对象切换由调用方显式传 cancel；取消不回滚已经接受的变换。圆心角度未定义时忽略旋转采样。
每帧调用包括释放/离焦帧，`allow_start=false` 只阻止开始，已有拖拽经过 UI 仍继续。
调用方负责选中哪个对象、消费 captured 输入、应用变换和保存。

`transform2d_draw` 使用最终像素 Render2D 和调用方设置的视口裁剪，
返回三个 XYZ 标签槽位：移动/缩放使用前两个，旋转只使用 Z 槽。字体由调用方提供。
状态与几何无堆分配，不拥有 GPU 资源。

可运行示例在同级 `olib_sample`：

```powershell
.\run.bat gizmo2d
.\run.bat gizmo2d shot
.\run.bat gizmo2d shot scaled
.\run.bat gizmo2d shot narrow vulkan
```

三个视口分别演示移动、旋转、缩放；方向键平移相机，Q/E 旋转，Z/X 缩放，R 重置。
shot 通过真实鼠标输入检查编辑结果，并生成 `library/screenshots/gizmo2d-宽x高.png`，包含运行中 resize。

## 三维操作模式

| Mode | 手柄与坐标空间 | 结果 |
| --- | --- | --- |
| `.Translate` | 世界 XYZ 箭头 | 沿选定世界轴改变 position |
| `.Rotate` | 世界 XYZ 圆环 | 绕原点叠加世界轴旋转，保持位置、缩放 |
| `.Scale` | 模型局部 XYZ 轴端方块、原点方块 | 单轴缩放，或保持原有三轴比例整体缩放 |

旋转和缩放都围绕 `Transform.position`，不会自动寻找网格中心。
`Transform.rotation` 是固定轴 X→Y→Z 欧拉角，单位弧度（Rz * Ry * Rx），与带正缩放的 TRS 对应。
世界轴旋转左乘已有姿态，返回靠近当前值的等价欧拉角；不能把世界轴角度直接加到某个 Euler 分量。
连续输入的相邻指针采样角差需小于 π，累计角度允许多圈；万向锁附近欧拉分量仍可能快速变化，姿态保持等价。
近乎侧视、无法稳定求交的旋转环隐藏，可调整观察相机。

缩放使用按下时的屏幕轴方向，向轴外拖动放大；中心方块向右上放大、左下缩小。
移动 `style.length * ui_scale` 像素增加一个初始比例，不逐帧累乘。
默认限制 0.001～10000，可用 `min_scale` / `max_scale` 参数改变；等比缩放共同约束比例，保留非均匀比例。
`Transform.scale` 必须为有限正值，不能用全零 Transform 代替单位变换。

```odin
// 会话启动/结束时成对调用；renderer 拥有 CPU 顶点、Mesh、Shader、Material。
renderer: gizmo.Renderer3D
ok := gizmo.renderer3d_init(&renderer, device)
// 初始化失败应报错；结束时调用 gizmo.renderer3d_destroy(&renderer)。

// 每帧先处理交互与事务，重新读取已接受的变换。
result := gizmo.transform_update(&handle, camera, value, viewport, mode, input, ui_scale)
// started / changed / cancelled / ended 的接法见编辑工具开发约定。
labels := gizmo.transform_draw(&renderer, target, camera, accepted_value, viewport,
    mode, &handle, input.pointer, ui_scale)
// labels 是最终像素坐标，文字由调用方的 UI 绘制。
```

`transform_draw` 不再接收 Batcher。箭头为圆柱与圆锥，旋转环由三维管段组成，
缩放手柄为旋转后的局部轴与立方体。网格随相机距离补偿世界尺寸，维持可用的屏幕大小，
透视缩短和空间遮挡仍然真实存在。悬停/拖动颜色与 `transform_hit` 使用同一几何。

`Renderer3D` 独占 GPU 资源及复用顶点缓冲，必须 init/destroy；交互状态依然零值可用、无资源。
`transform_mesh` 可单独生成世界空间 `Vertex3D` 三角列表，供自定义渲染器和无窗口测试使用。
`shaders/Gizmo3D.hlsl` 及预编译 SPIR-V/DXIL/MSL 随包提供；修改后运行：

```powershell
odin run tools/shaders -- -dir:kit/gizmo/shaders
```

## 三维目标、深度与绘制顺序

`target` 必须有已经写入场景几何的深度附件，使用常规 0..1 深度（近小远大）。
宿主负责清除深度为 1、绘制场景深度，并保证它与 camera/viewport 的投影、尺寸和偏移一致。
`transform_draw` 自己设置 viewport/scissor，不修改相机或调用方的 Batcher 状态。

两次 Mesh/DrawCommand 提交都开启深度测试、关闭深度写入：Greater 通道淡化被遮挡的片元，
LessOrEqual 通道正常显示可见片元。被遮挡手柄仍可命中，方便从模型内部拖出；文字标签不做深度遮挡。
着色器提供固定的柔和明暗来显示体积，不依赖游戏灯光。手柄不进入模型资源或场景存档。

手柄按最终像素目标绘制，再叠加文字/面板。低分辨率场景不能直接把手柄一起放大：
接入方可在原生尺寸重建场景深度，再绘制手柄、合成到最终输出。
SIGNAL 使用独立颜色+深度工具目标（匹配 MSAA），重绘不透明/MASK 场景深度；
BLEND 透明物体不遮挡手柄。额外深度提交仅在编辑器有选中对象时发生。

## 移动专用接口

`Translation_Gizmo` 的交互接口仍为 `translation_update / geometry / hit`，保持原有输入契约。
移动专用绘制同样使用三维渲染器：

```odin
labels := gizmo.translation_draw(&renderer, target, camera, accepted_position,
    viewport, &translation_handle, input.pointer, ui_scale)
```

三维 `transform_draw` 和 `translation_draw` 的旧 Batcher 调用签名已更换；
二维 `transform2d_draw` 的签名保持不变。投影命中几何仍可单独使用。
项目事务、取消、撤销与保存统一见 [编辑工具开发约定](../../prompts/editor-guidelines.md)。

## 输入与结果

- 每帧调用，包括鼠标释放、离焦、面板关闭等状态变化帧。`pressed` 是由调用方提供的按下边沿，不能连续为 true。
- `enabled` 控制工具是否可用；`allow_start` 仅控制能否开始，已有拖拽经过 UI 仍继续。
- `started` 表示本次刚抓住轴；按下时保留偏移，不会把模型突然移到鼠标下。
- `changed` 表示输出位置不同于调用方传入的位置；`delta` 在拖拽及其结束帧表示相对按下原点的总位移。
- `ended` 表示释放或中断；`cancelled` 表示停用、显式取消、相机/视口变化导致的中断。
  库不自动恢复对象位置，编辑接入方负责取消事务和恢复内容。
- `captured` 表示本帧鼠标输入已归工具所有，包含释放帧；调用方应阻止其他工具或 UI 再消费。
  中断后按住仍保持捕获到松开，避免同一次鼠标操作触发另一对象或按钮。
- `axis` 在拖拽及结束帧为 0/1/2，其他情况为 -1。拖动限于世界坐标轴，不改变旋转和缩放。

工具使用包含选中轴、尽量朝向相机的平面计算位移，过程不做逐帧堆分配。
相机观察矩阵或投影矩阵、视口改变时会结束当前拖拽；无效鼠标坐标和射线平行时不输出修改。

## 验证

```powershell
odin run tools/check -- -only:kit/gizmo
odin run tools/check
```

测试覆盖带偏移视口、多种尺寸与缩放、三轴位移、中心命中排除、视线退化、
UI 捕获、释放事件、取消后重新开始、相机/窗口变化及非有限鼠标输入；
统一工具还覆盖混合姿态与万向锁的世界轴旋转、跨 ±π 的多圈拖拽、局部与等比缩放、
缩放上下限、返回原点恢复原值，以及三种模式的切换/取消/离焦/窗口变化。
二维测试覆盖带偏移视口、相机旋转/zoom、轴约束/自由移动、多圈旋转、局部/等比缩放及中断捕获。
实际绘制改动由接入项目或 gizmo2d 示例的最终画面按需验收。必要截图归入所属项目的
`library/screenshots/`，遵循 [生成文件规则](../../prompts/new-project.md#生成文件与目录纪律)；
不为目录、文档或配置调整额外生成截图。

项目编辑会话、事务取消和保存策略统一遵循 [编辑工具开发约定](../../prompts/editor-guidelines.md)，
本包仅提供交互候选，不拥有项目文档或历史。当前 update 在 `down=false` 时直接结束；
若宿主释放事件带有最后一次移动，应先以 `down=true, pressed=false` 处理该位置并接受结果，
再传释放事件结束事务，且每次都优先处理 `cancelled`。游戏和 gizmo2d 示例已覆盖此接法。

三维网格测试验证世界几何、投影命中对齐与距离补偿；SIGNAL 冒烟用 GPU 读回比较保留/清空场景深度的真实像素，验证可见和淡化两类区域。
