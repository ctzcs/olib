# Foster → OFoster 移植映射

本文档记录上游 C# Foster 源文件与本项目 Odin 文件的对应关系，以及移植中
有意做出的 API 差异。同步上游时，先对照本表定位每个上游文件在 Odin 侧的
落点，再更新 `README.md` 的 sync baseline 一节与 `framework.odin`
里的版本号。olib 主动做的修改（新增 / 行为变更 / 修复 / 删除）另见
[LOCAL_CHANGES.md](LOCAL_CHANGES.md)。

## 当前覆盖（2026-10-06）

下表的“已移植”表示该模块已有 Odin 实现，并不代表每个 C# 重载逐一等价，
也不代表所有平台都已验证。本轮以 README 中的 `06213b9` 基线补齐以下缺口：

- 计算管线：只读/可写纹理、只读/可写存储缓冲、采样器、uniform 数据、线程组
  和命令提交生命周期；D3D12、Vulkan 的实际计算输出已验证。
- 纹理：区域更新保留已有 GPU 内容，Clone 从 GPU 复制，Blit 支持缩放；三个
  后端均以实际像素验证。原生读回需要先提交产生纹理内容的命令缓冲。
- Batcher：模板状态及 Push/Pop，材质数据和自带着色器释放；原生与 Web
  模板裁剪、颜色写入掩码、深度写入/比较已验证。
- 空间与工具：凹多边形面积和双向绕序三角化、矩形边界辅助、缓动和时间函数、
  泛型集合辅助、随机选择/移除、整数类型助手、日志回调；凹多边形回归采用 L 形面积
  与内部点验证。RngInt 的 32 位语义及 Float/Double 位生成规则对齐上游，并以固定
  种子验证原生/Web 一致；这些方法的输出序列会与旧版 OFoster 不同，U64 序列不变。
- 输入：BindingFilters 和 Masks 筛选、方向 Pressed 转换、鼠标移动距离归一化与
  按下/释放转换、InputProvider 文本、控制器供给、常用绑定组助手。
- 存储：ZIP 统一接口、Store/Deflate 解码、显式和隐式目录、相对根目录、名称
  所有权、通配符/递归枚举、可 seek 的读取流，以及普通存储的可写 Create 流。
  新增内存/存储容器加载、ZIP64 目录和条目扩展字段、CRC32 校验、损坏数据边界检查。
  `ZipStorage.Error` 区分损坏、校验失败与不支持的归档；失败时释放全部条目。
  加密、多卷 ZIP 和 Store/Deflate 以外的压缩方式仍不支持。
- 常用接口：StackList 的插入/删除/查找/复制与清空，Polygon 的插入/修改/删除，
  颜色灰度值及按组件顺序的十六进制读写，Cardinal/Signs 解析，AxisOverlaps，
  三角化枚举与四分量整数向量转点。
- 字体与图像：SpriteFont 增量 GPU 图集、pixel-perfect 字形、正弦偏移、缩放字距及
  换行对齐；FontGetKerning 先将码点映射为字形。Image/Packer/Font/SpriteFont/
  Aseprite/MsdfFont/InputProvider 的释放接口已补齐；关联 cel 复制及 Aseprite
  输入数据所有权已修正。真实字体、PNG 往返、Aseprite 关联帧、MSDF 与多页打包
  通过内存跟踪回归，测试范围内没有剩余拥有的分配。
- JSON：向量读入支持数组及忽略大小写的命名对象，输出命名对象；矩阵使用
  六分量数组。用 `Vector2/3/4FromJson/ToJson`、`Matrix3x2FromJson/ToJson`，
  自定义分量别名用 `Float/IntVectorJsonRead/Write`。C# serializer attribute
  和 converter 注册机制改成显式 Odin proc。
- Web：离屏目标、depth/stencil 状态、GPU 纹理读回/复制、区域上传、目录
  查询/枚举/递归删除。RG/单通道与 RGBA32F 读回路径已实现；浏览器像素回归
  覆盖 RGBA8，浮点格式取决于 `EXT_color_buffer_float`。新增手柄标准映射、原始
  按钮/轴、震动请求，UTF-8/IME 输入及同帧文本累计，CSS/图像光标，异步剪贴板，
  PNG 写入与文件/目录选择、保存写入完成回调。

验证范围是当前 Windows 的 D3D12、Vulkan 和 Chromium WebGL2；Metal、Linux、
macOS、其他浏览器尚未重跑。Web 不支持 compute、SSBO、线框填充及离屏 MSAA，
浏览器原生文件选择依赖 File System Access API 支持、安全上下文与用户手势；
不支持或取消时返回取消结果。Web 自定义 uniform
沿用命名约定，不能直接使用任意原生 UBO 布局。

资源生命周期：MaterialDispose 只释放自己拥有的 uniform 数据，shader/texture
为借用；BatcherDispose 同时释放自己的两个默认 shader。ZIP 视图借用稳定地址的
ZipStorage；枚举结果中的每个字符串及结果切片由调用方释放。OpenRead 的流拥有
读取快照，Create 流在打开时截断文件，随后写入先缓冲在内存中，Flush/Close/Destroy
时持久化。两个流最终均用 `io.destroy` 释放。递归枚举返回相对于查询目录的路径，
通配符匹配每层子项的名称。

新增资源规则：`ImageClear` 保留像素容量；`ImageDispose` 释放它。Packer 在 Trim
模式拥有裁剪后的副本，否则借用输入图像；Name 为借用，结果通过
`PackerOutputDispose` 释放。`SpriteFont` 借用 KerningFont，自行释放生成的纹理；
`MsdfFontMake` 借用 atlas，`MsdfFontLoadFiles` 拥有 atlas，均用 `MsdfFontDispose`
释放自己拥有的部分。`AsepriteLoad` 拷贝输入作为字符串后备，并拥有解码后的图像；
用 `AsepriteDispose` 释放。不要复制拥有资源的结构后分别 Dispose。
`InputProviderMake` 拥有创建的 Input，`InputProviderDispose` 同时释放它；手动传入
Input 的 provider 默认借用，独立 Input 用 `InputDispose` 释放。

`GetClipboardString` 的字符串由调用方 delete，异步剪贴板回调的文本只在回调期间
有效。Web 同步读取返回缓存、同步写入结果表示请求已启动；异步方法报告实际结果。
文件对话框回调的路径/列表同样为借用，跨回调保存需复制。Web 选择的文件和目录
导入到 `/foster-dialog/<session>/<request>/...` 快照；用 Storage API 查询及删除。
打开的文件/目录是快照，不自动追踪本地修改；保存选择绑定可写句柄，写入按路径
排队，`FlushStorageFileAsync` 等待本次调用前的队列，报告最后一次快照写入结果。同步写入成功仅保证
虚拟存储成功；本地文件句柄仅在当前页面有效。浏览器选择器标题由浏览器控制，
筛选器转换支持扩展名列表。失败和取消使用现有取消/空路径回调。

浏览器新增输入、震动、剪贴板和文件选择测试使用 DOM 事件及模拟设备/句柄，
不读取系统剪贴板或修改真实选中文件。真实手柄硬件、系统 IME 与原生选择/权限
对话框还需人工验收；不能将模拟测试解释为所有设备、浏览器都已通过。

## 布局原则

新增和维护代码时遵循 [源码布局与排版规范](CODE_STYLE.md)，其中包含分区层级、
顶部导航、多行排版示例和格式化命令。本节说明移植时的文件归属。

- 上游仓库是 C# 的"一类型一文件 + 命名空间目录"结构；OFoster 保留单一包、
  按主题分文件，并通过文件内分区注释保留上游目录与类型的层级。
- 每个主题文件顶部提供分区导航；`// ===` 标记大模块，`// ---` 标记类型或
  子功能。标题使用 `Graphics / Batcher`、`Input / Bindings / KeyboardKeyBinding`
  这样的路径，便于搜索与对照上游。平台适配按 `Platform / ...` 分区。
- 函数体、分支、循环和结构体字段使用多行排版；较长的参数列表与复合字面量
  也拆行。根目录 `odinfmt.json` 保存统一格式配置。
- 公共 API 全部在根包 `foster`（`import foster "olib:foster"`），
  以少量主题文件组织（`framework`/`foundation`/`graphics`/`images`/`input`/
  `spatial`/`utility`/`storage`/`web`，外加 `#+build` 平台对与 `web.odin`）。
  仅保留两个内部子包：`internal/third_party`（vendored C 绑定）与
  `internal/web`（js 桥的 JS 侧）。
- 历史上的 `Graphics/`、`Input/`、`Storage/`、`Spatial/`、`Utility/`、
  `Images/`、`Extensions/` 别名转发层已于 2026-09 移除。

## 文件映射

| 上游 Foster (C#) | OFoster (Odin) | 状态 |
| --- | --- | --- |
| `Framework/App.cs`、`Framework/Window.cs`、`Framework/Platform*.cs`、主循环 | `framework.odin` | 已移植（App/Window 合于一文件） |
| `Framework/Time.cs` 等基础数值/颜色/Point2 | `foundation.odin` | 已移植 |
| `Framework/Graphics/GraphicsDevice.cs` | `graphics.odin` | 已移植 |
| `Framework/Graphics/Texture.cs`、`Target.cs`、`Shader.cs`、`Material.cs`、`Mesh.cs`、`GraphicsBuffer.cs`、`UniformBuffer.cs` | `graphics.odin` | 已移植 |
| `Framework/Graphics/Batcher.cs` | `graphics.odin`（Batcher 一节） | 已移植 |
| `Framework/Graphics/SpriteFont.cs` | `images.odin` | 已移植 |
| `Framework/Graphics/Subtexture.cs` | `graphics.odin`（Subtexture 一节） | 已移植 |
| 顶点类型 / 类型化初始化辅助（PosTexColVertex、`MeshInitTyped` 等） | `graphics.odin` | 已移植 |
| 计算管线 / uniform buffer | `graphics.odin` | 已移植 |
| `Framework/Graphics/Defaults/*` | `graphics.odin`（`DefaultResources*` 一节） | 已移植 |
| `Framework/Input/*`（Input、States、Controller） | `input.odin` | 已移植 |
| `Framework/Input/Bindings/*`、`BindingSet` | `input.odin`（Bindings/Sets 一节） | 已移植 |
| `Framework/Input/VirtualInput/*` | `input.odin`（Virtual 一节） | 已移植 |
| 光标 / 独立输入供给（工具、测试用） | `input.odin`（Provider/Cursor 一节） | 已移植 |
| `Framework/Storage/*` | `storage.odin` + `platform_native/web.odin`（OS/路径层按 `#+build` 分侧） | 已移植 |
| Web (js_wasm32) 桥 | `web.odin` + `internal/web/foster.js` | 已移植 |
| 线程 ID 平台差异 | `platform_native.odin` / `platform_web.odin`（线程 ID 一节） | 已移植 |
| `Framework/Spatial/*`（Rect、Circle、Polygon 等） | `spatial.odin` | 已移植（RectInt 以本文件实现为准） |
| `Framework/Utility/*`（Calc、Ease、Log、Pool、Rng 等） | `utility.odin` | 已移植 |
| `Framework/Extensions/*` | `utility.odin`（Extensions 一节） | 已移植 |
| `Framework/Images/*`（Image、Packer、Aseprite、Font、MsdfFont） | `images.odin` | 已移植 |
| QOI / stb_truetype 绑定 | `internal/third_party/`（唯一保留的子包） | vendored |

C# 的接口（`IVertex`、`IProvideKerning`、`IDrawableTarget` 等）在 Odin 侧
不设占位类型：顶点布局由 `VertexFormat` 运行时描述，字距由数据字段提供，
可绘制目标由 `DrawableTarget` 值类型表达。

## 有意的 API 差异

C# 的重载/实例方法在 Odin 侧多为"前缀 + 显式名"或 proc group，调用方需要注意：

| C# / 旧门面 | OFoster | 说明 |
| --- | --- | --- |
| `Calc.Approach(f/Vector2/Vector3, ...)` | `Approach`（proc group：`ApproachScalar`/`ApproachVec2`/`Approach3`） | 标量版即原根包 `Approach`，已更名 `ApproachScalar`，组名 `Approach` 可按参数分发 |
| `Calc.Map(val,min,max)` / `Calc.Map(val,min,max,nmin,nmax)` | `Map` / `MapTo` | 展开域版本不设 `MapExtended`/`MapRange` 别名（与 `MapTo` 重复） |
| `Calc.Down` 等方向常量 | `Down`/`Up`/`Left`/`Right`... | 键盘态辅助原名 `Down`/`Pressed`/`Released` 已更名 `KeyboardDown`/`KeyboardPressed`/`KeyboardReleased`，让出常量名 |
| `Calc.TriangleArea(a,b,c)` | `TriangleAreaVec2` | `TriangleArea` 保留给 `Triangle` 结构版本 |
| `Texture.SetData` 区域重载 | `TextureSetDataRegion` / `TextureSetDataRegionRect` | 两个显式名，不设同名 proc group |
| `KeyboardState.Down(key)` 等 | `KeyboardDown(state, key)` 等 | 见上 |
| `Calc.TriangulatePooled` / `TriangulateAndEnumeratePooled` | 同名 Odin proc，使用 `context.temp_allocator` | 结果在 temp allocator 清理时失效；`TriangulateOwned` 返回调用方 delete 的动态数组，普通枚举借用传入的顶点/索引 |
| `IProjectableExt.AxisOverlaps(a,b,axis)` | `AxisOverlaps(minA,maxA,minB,maxB)` | 将两个形状 Project 的区间传入，返回严格相交与有符号位移 |
| `Vector128<int>.AsPoint2/3` | `AsPoint2/3([4]i32)` | 四分量整数数组代替 C# SIMD 类型 |
| `Batcher.Text/ TextWrapped` | `BatcherText/BatcherTextWrapped` | 使用 SpriteFontDraw 的参数顺序；传入显式 font，默认字体调用由应用持有 font |
| 子包导入（`ofoster:Graphics` 等） | 一律 `import foster "olib:foster"` | 门面层已删除 |

另有若干类型并存但语义不同，属于历史形态，暂不合并：

- `Point2`（struct，根包）与 `Vec2`（`[2]f32`，spatial）——整数像素坐标 vs 浮点向量。
- `Vec2f`（input 内部鼠标数据）。

## 命名规则

foster 对外 API 只用上游 Foster 的 PascalCase，每个函数一个名字；snake_case 只用于标了
`@(private)` 的包内实现（规则见 [CODE_STYLE](CODE_STYLE.md#命名)）。2026-10 起删除了全部
`PascalName :: snake_name` 别名，原来能在包外调用的 snake 名字按下表迁移；表外的 snake proc
（约 300 个）改为 `@(private)`，没有对外替代名，外部项目用到时改用对应的 PascalCase API。

<details>
<summary>旧 snake 名 → 新名对照（240 项）</summary>

| 旧名 | 新名 |
| --- | --- |
| `advance_render_frame` | `AdvanceRenderFrame` |
| `advance_time` | `Advance` |
| `batcher_image_fit` | `BatcherImageFit` |
| `batcher_image_stretch` | `BatcherImageStretch` |
| `batcher_push_matrix_raw` | `BatcherPushMatrixRaw` |
| `begin_frame` | `GraphicsDeviceBeginFrame` |
| `clamped_map_range` | `ClampedMapTo` |
| `compute_command_dispose` | `ComputeCommandDispose` |
| `compute_command_init` | `ComputeCommandInit` |
| `compute_command_set_groups` | `ComputeCommandSetGroups` |
| `content_storage_as_container` | `ContentStorageContainer` |
| `content_storage_init` | `ContentStorageInit` |
| `create_device` | `GraphicsDeviceCreateDevice` |
| `create_error_from_sdl` | `CreateExceptionFromSDL` |
| `default_app_config` | `DefaultAppConfig` |
| `default_batcher_vertex_format` | `BatcherVertexFormat` |
| `default_pos_tex_col_vertex_format` | `PosTexColVertexFormat` |
| `default_resources_dispose` | `DefaultResourcesDispose` |
| `default_resources_init` | `DefaultResourcesInit` |
| `default_shader_create_info` | `DefaultShaderCreateInfo` |
| `destroy_device` | `GraphicsDeviceDestroyDevice` |
| `directory_storage_as_container` | `DirectoryStorageContainer` |
| `directory_storage_init` | `DirectoryStorageInit` |
| `dispose_app` | `Dispose` |
| `draw_command_dispose` | `DrawCommandDispose` |
| `draw_command_from_mesh` | `DrawCommandFromMesh` |
| `draw_command_from_vertex_buffer` | `DrawCommandFromVertexBuffer` |
| `draw_command_init` | `DrawCommandInit` |
| `draw_test_quad` | `DrawTestQuad` |
| `draw_test_triangle` | `DrawTestTriangle` |
| `drawable_target_bounds_in_pixels` | `DrawableTargetBoundsInPixels` |
| `drawable_target_from_target` | `DrawableTargetFromTarget` |
| `drawable_target_from_window` | `DrawableTargetFromWindow` |
| `drawable_target_size_in_pixels` | `DrawableTargetSizeInPixels` |
| `end_frame` | `GraphicsDeviceEndFrame` |
| `end_render_pass` | `GraphicsDeviceEndRenderPass` |
| `exit` | `Exit` |
| `file_system_init` | `FileSystemInit` |
| `file_system_open_file_dialog` | `OpenFileDialog` |
| `file_system_open_folder_dialog` | `OpenFolderDialog` |
| `file_system_open_title_storage` | `OpenTitleStorage` |
| `file_system_open_title_storage_async` | `OpenTitleStorageAsync` |
| `file_system_open_user_storage` | `OpenUserStorage` |
| `file_system_open_user_storage_async` | `OpenUserStorageAsync` |
| `file_system_save_file_dialog` | `SaveFileDialog` |
| `get_controller` | `GetController` |
| `graphics_buffer_clear` | `GraphicsBufferClear` |
| `graphics_buffer_dispose` | `GraphicsBufferDispose` |
| `graphics_buffer_init` | `GraphicsBufferInit` |
| `graphics_buffer_reserve` | `GraphicsBufferReserve` |
| `graphics_buffer_upload` | `GraphicsBufferUpload` |
| `graphics_device_destroy_resource` | `GraphicsDeviceDestroyResource` |
| `graphics_device_dispatch` | `GraphicsDeviceDispatch` |
| `graphics_device_dispose_caches` | `GraphicsDeviceDisposeCaches` |
| `graphics_device_draw` | `GraphicsDeviceDraw` |
| `graphics_device_is_texture_format_supported` | `GraphicsDeviceIsTextureFormatSupported` |
| `graphics_device_is_texture_multisample_supported` | `GraphicsDeviceIsTextureMultiSampleSupported` |
| `graphics_device_origin_bottom_left` | `GraphicsDeviceOriginBottomLeft` |
| `graphics_device_resource_handle` | `GraphicsDeviceResourceHandle` |
| `graphics_device_upload_to_buffer` | `GraphicsDeviceUploadToBuffer` |
| `graphics_driver_shader_extension` | `GetShaderExtension` |
| `index_buffer_clear` | `IndexBufferClear` |
| `index_buffer_dispose` | `IndexBufferDispose` |
| `index_buffer_init` | `IndexBufferInit` |
| `index_buffer_init_typed` | `IndexBufferInitTyped` |
| `index_buffer_upload` | `IndexBufferUpload` |
| `index_buffer_upload_typed` | `IndexBufferUploadTyped` |
| `index_format_of` | `IndexFormatOf` |
| `index_format_size_in_bytes` | `IndexFormatSizeInBytes` |
| `index_format_to_sdl` | `IndexFormatToSDL` |
| `init_app` | `InitApp` |
| `init_default_batch_material` | `InitDefaultBatchMaterial` |
| `init_default_msdf_material` | `InitDefaultMsdfMaterial` |
| `init_default_textured_material` | `InitDefaultTexturedMaterial` |
| `input_controller_axis` | `InputControllerAxis` |
| `input_controller_button` | `InputControllerButton` |
| `input_get_clipboard` | `GetClipboardString` |
| `input_init` | `InputInit` |
| `input_key` | `InputKey` |
| `input_mouse_button` | `InputMouseButton` |
| `input_mouse_move` | `InputMouseMove` |
| `input_mouse_wheel` | `InputMouseWheel` |
| `input_rumble` | `Rumble` |
| `input_set_clipboard` | `SetClipboardString` |
| `input_step` | `InputStep` |
| `input_text` | `InputText` |
| `is_main_thread` | `IsMainThread` |
| `make_batcher_vertex` | `MakeBatcherVertex` |
| `make_pos_tex_col_vertex` | `MakePosTexColVertex` |
| `map_range` | `MapTo` |
| `material_clone` | `MaterialClone` |
| `material_copy_from` | `MaterialCopyFrom` |
| `material_copy_to` | `MaterialCopyTo` |
| `material_init_with_shaders` | `MaterialInitWithShaders` |
| `material_stage_copy_to` | `MaterialStageCopyTo` |
| `material_stage_get_uniform_buffer` | `MaterialStageGetUniformBuffer` |
| `material_stage_init` | `MaterialStageInit` |
| `material_stage_set_shader` | `MaterialStageSetShader` |
| `material_stage_set_uniform_buffer` | `MaterialStageSetUniformBuffer` |
| `mesh_clear` | `MeshClear` |
| `mesh_dispose` | `MeshDispose` |
| `mesh_init_with_format` | `MeshInitWithFormat` |
| `mesh_set_index_count` | `MeshSetIndexCount` |
| `mesh_set_indices` | `MeshSetIndices` |
| `mesh_set_indices_typed` | `MeshSetIndicesTyped` |
| `mesh_set_instance_count` | `MeshSetInstanceCount` |
| `mesh_set_instances` | `MeshSetInstances` |
| `mesh_set_instances_typed` | `MeshSetInstancesTyped` |
| `mesh_set_vertex_count` | `MeshSetVertexCount` |
| `mesh_set_vertices` | `MeshSetVertices` |
| `mesh_set_vertices_typed` | `MeshSetVerticesTyped` |
| `point2_abs` | `Point2Abs` |
| `point2_add` | `Point2Add` |
| `point2_from_bools` | `Point2FromBools` |
| `point2_get_length_and_normalize` | `Point2GetLengthAndNormalize` |
| `point2_length` | `Point2Length` |
| `point2_length_squared` | `Point2LengthSquared` |
| `point2_manhattan_dist` | `Point2ManhattanDist` |
| `point2_negate` | `Point2Negate` |
| `point2_normalized` | `Point2Normalized` |
| `point2_only_x` | `Point2OnlyX` |
| `point2_only_y` | `Point2OnlyY` |
| `point2_sign` | `Point2Sign` |
| `point2_sub` | `Point2Sub` |
| `point2_turn_left` | `Point2TurnLeft` |
| `point2_turn_right` | `Point2TurnRight` |
| `point2_vector2` | `Point2Vector2` |
| `poll_events` | `PollEvents` |
| `present` | `Present` |
| `relative_storage_as_container` | `RelativeStorageContainer` |
| `relative_storage_dispose` | `RelativeStorageDispose` |
| `relative_storage_init` | `RelativeStorageInit` |
| `run` | `Run` |
| `run_on_main_thread` | `RunOnMainThread` |
| `sample_count_to_sdl` | `SampleCountToSDL` |
| `sdl_version_string` | `SDLVersionString` |
| `shader_dispose` | `ShaderDispose` |
| `shader_init` | `ShaderInit` |
| `shader_recreate` | `ShaderRecreate` |
| `shader_stage_to_sdl` | `ShaderStageToSDL` |
| `shutdown_graphics_device` | `GraphicsDeviceShutdown` |
| `stack_add` | `StackListAdd` |
| `startup_graphics_device` | `GraphicsDeviceStartup` |
| `storage_buffer_clear` | `StorageBufferClear` |
| `storage_buffer_dispose` | `StorageBufferDispose` |
| `storage_buffer_init` | `StorageBufferInit` |
| `storage_buffer_init_typed` | `StorageBufferInitTyped` |
| `storage_buffer_upload` | `StorageBufferUpload` |
| `storage_buffer_upload_typed` | `StorageBufferUploadTyped` |
| `storage_create` | `Create` |
| `storage_create_directory` | `CreateDirectory` |
| `storage_dialog_dispose` | `StorageDialogDispose` |
| `storage_dialog_filters` | `StorageDialogFilters` |
| `storage_directory_exists` | `DirectoryExists` |
| `storage_dispose` | `DisposeStorage` |
| `storage_enumerate_directory` | `EnumerateDirectory` |
| `storage_exists` | `Exists` |
| `storage_file_exists` | `FileExists` |
| `storage_join_path` | `StorageJoinPath` |
| `storage_open_read` | `OpenRead` |
| `storage_read_all_bytes` | `ReadAllBytes` |
| `storage_read_all_text` | `ReadAllText` |
| `storage_remove` | `Remove` |
| `storage_write_all_bytes` | `WriteAllBytes` |
| `storage_write_all_text` | `WriteAllText` |
| `target_attachment` | `TargetAttachment` |
| `target_dispose` | `TargetDispose` |
| `texture_blit` | `TextureBlit` |
| `texture_clone` | `TextureClone` |
| `texture_dispose` | `TextureDispose` |
| `texture_download_data` | `TextureDownloadData` |
| `texture_format_is_color_format` | `TextureFormatIsColorFormat` |
| `texture_format_size` | `TextureFormatSize` |
| `texture_format_to_sdl` | `TextureFormatToSDL` |
| `texture_get_data` | `TextureGetData` |
| `texture_init` | `TextureInit` |
| `texture_init_ex` | `TextureInitEx` |
| `texture_init_flags` | `TextureInitFlags` |
| `texture_memory_size` | `TextureMemorySize` |
| `texture_sample_resource` | `TextureSampleResource` |
| `texture_set_data` | `TextureSetData` |
| `texture_set_data_region` | `TextureSetDataRegion` |
| `texture_set_data_region_rect` | `TextureSetDataRegionRect` |
| `tick_app` | `Tick` |
| `time_between_interval` | `TimeBetweenInterval` |
| `time_seconds_f` | `TimeSecondsF` |
| `uniform_buffer_clear` | `UniformBufferClear` |
| `uniform_buffer_dispose` | `UniformBufferDispose` |
| `uniform_buffer_get` | `UniformBufferGet` |
| `uniform_buffer_init` | `UniformBufferInit` |
| `uniform_buffer_set` | `UniformBufferSet` |
| `uniform_buffer_set_value` | `UniformBufferSetValue` |
| `unlocked_step` | `UnlockedStep` |
| `vec2_length_squared` | `Vec2LengthSquared` |
| `vec2_normalized` | `Vec2Normalized` |
| `version_string` | `VersionString` |
| `vertex_buffer_clear` | `VertexBufferClear` |
| `vertex_buffer_dispose` | `VertexBufferDispose` |
| `vertex_buffer_init_typed` | `VertexBufferInitTyped` |
| `vertex_buffer_upload` | `VertexBufferUpload` |
| `vertex_buffer_upload_typed` | `VertexBufferUploadTyped` |
| `vertex_format_clone` | `VertexFormatClone` |
| `vertex_format_dispose` | `VertexFormatDispose` |
| `vertex_format_equals` | `VertexFormatEquals` |
| `vertex_format_make` | `VertexFormatMake` |
| `vertex_format_of` | `VertexFormatOf` |
| `vertex_type_size_in_bytes` | `VertexTypeSizeInBytes` |
| `vertex_type_to_sdl` | `VertexTypeToSDL` |
| `window_close` | `Close` |
| `window_content_scale` | `ContentScale` |
| `window_display_size` | `DisplaySize` |
| `window_focus` | `Focus` |
| `window_focused` | `Focused` |
| `window_fullscreen` | `Fullscreen` |
| `window_hide` | `Hide` |
| `window_maximized` | `Maximized` |
| `window_on_event` | `OnEvent` |
| `window_position` | `Position` |
| `window_resizable` | `Resizable` |
| `window_set_fullscreen` | `SetWindowFullscreen` |
| `window_set_mouse_cursor` | `SetMouseCursor` |
| `window_set_mouse_position` | `SetMousePosition` |
| `window_set_mouse_relative_mode` | `SetMouseRelativeMode` |
| `window_set_mouse_visible` | `SetMouseVisible` |
| `window_set_resizable` | `SetWindowResizable` |
| `window_set_size` | `SetWindowSize` |
| `window_set_text_input` | `SetTextInput` |
| `window_show` | `Show` |
| `window_size` | `Size` |
| `window_size_in_pixels` | `SizeInPixels` |
| `window_start_text_input` | `StartTextInput` |
| `window_stop_text_input` | `StopTextInput` |
| `zip_storage_as_container` | `ZipStorageContainer` |
| `zip_storage_dispose` | `ZipStorageDispose` |
| `zip_storage_enumerate_directory` | `ZipStorageEnumerateDirectory` |
| `zip_storage_exists` | `ZipStorageExists` |
| `zip_storage_init` | `ZipStorageInit` |
| `zip_storage_init_bytes` | `ZipStorageInitBytes` |
| `zip_storage_init_container` | `ZipStorageInitContainer` |
| `zip_storage_read_all_bytes` | `ZipStorageReadAllBytes` |

</details>

## 同步上游的流程

1. 在上游仓库对比 sync baseline commit 之后的变更清单。
2. 对照 [LOCAL_CHANGES.md](LOCAL_CHANGES.md)，找出与上游改动落在同一位置的本地修改
   （`grep -rn "\[olib L-" foster`），按各条的同步策略处理：`保留` 的手工合并；
   `上游修复后删除` 的确认上游已修复后移除代码标记与清单行；`同步时重新评估` 的逐条决定。
3. 按本表把每个改动的 C# 文件映射到对应 Odin 文件并移植。
4. 跑 `tests/webtest`（native + `js_wasm32`）与 `tests/graphics_regression`，以及
   `build/glade-regression` 与 `build/exhaustive-format-check`（若适用）。
5. 运行 `tests/check_local_changes.ps1`；更新 `README.md` 的 baseline、`framework.odin` 的版本号和本表。
