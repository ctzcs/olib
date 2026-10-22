# 本地修改清单（olib 对 Foster 的主动改动）

本文档记录 olib **主动**对 Foster 移植做的修改：新增、行为变更、修复、删除。
因 Odin 语言限制而产生的命名/签名差异不在此列，见 [PORTING_MAP.md](PORTING_MAP.md#有意的-api-差异)。

目的：同步上游 C# Foster 时，能逐条判断每处本地修改是保留、删除还是需要重新评估。

## 规则

1. **每处修改一条记录**，编号 `L-001` 起递增，编号不复用（撤销的修改删掉整行，编号作废）。
2. **代码打标记**：修改点写一行注释 `// [olib L-001] 简述`。一条记录涉及多处时，每处都要打标记。
   删除类修改在原位置留下标记，说明删掉了什么。
3. **优先新增、少改原文件**：纯新增能力放在 `olib_ext.odin`（或按主题的 `olib_*.odin`），
   移植文件尽量保持与 C# 一一对应；只有新增无法实现时才改移植代码。
4. **提交前缀**：本地修改用 `foster(local): L-001 简述`；同步上游用 `foster(port): sync Foster vX.Y.Z`。
5. **检查**：提交前运行 `odin run tools/check -- -only:local`（全量检查也包含），
   代码标记与本表编号必须一一对应。

字段说明：

- **类型**：`新增` / `行为变更` / `修复` / `删除`
- **位置**：`文件 / 分区或符号`，与 CODE_STYLE 的分区路径一致
- **上游对应**：C# 文件与成员（如 `Batcher.cs / PushQuad`）；纯新增写 `无`
- **同步策略**：`保留` / `上游修复后删除` / `同步时重新评估`

## 清单

| 编号 | 日期 | 类型 | 位置 | 上游对应 | 原因 | 同步策略 |
| --- | --- | --- | --- | --- | --- | --- |
| L-001 | 2026-10-08 | 行为变更 | framework.odin / Tick；storage.odin / OpenTitleStorage、RelativeStorage 路径所有权 | App.cs / 主循环（C# 有 GC，无对应） | 每帧 Render/end_frame 后清空临时分配器；Startup 临时数据在第一帧末失效。标题存储回退为空 Root（相对 cwd）；RelativeStorage 持有长期拼接路径，返回的容器借用直到路径改变或 RelativeStorageDispose，由调用方释放 | 保留 |
| L-002 | 2026-10-08 | 修复 | storage.odin / zip_storage_decode；images.odin / AsepriteLoad | 无（Odin 写法） | 未使用循环索引改为 _；拷贝后的 Aseprite 数据改名 source_data，避免遮蔽输入参数；只改写法，不改行为 | 保留 |
| L-003 | 2026-10-08 | 修复 | graphics.odin / GraphicsBuffer、Texture 名字所有权；Mesh、Target 派生名字；TargetDispose 附件释放 | GraphicsBuffer.cs / Texture.cs / Target.Dispose（C# 有 GC，无对应） | 缓冲区和纹理克隆名字并用原分配器释放；派生名字临时分配；Target 释放附件 CPU 像素与名字，GPU 释放顺序和次数保持不变 | 保留 |
| L-004 | 2026-10-12 | 新增 | olib_ext.odin / AppGetUserDataAs | 无（C# 用 App 子类持有游戏状态） | 按类型取回 App.UserData，回调里不用再手写 cast；不做类型校验 | 保留 |
| L-005 | 2026-10-15 | 修复 | graphics.odin / target_init_with_attachments、graphics_device_begin_render_pass | Target.cs / 多采样附件及 SDL 渲染通道 | SDL 多采样颜色附件禁止 SAMPLER 标志，仅解析纹理可采样；解析后保留多采样内容，保证上传/调试绘制打断通道后 LOAD 有效。port_regression 覆盖 4× MSAA 创建、分通道绘制及解析回读 | 同步时重新评估 |
| L-006 | 2026-10-15 | 修复 | graphics.odin / graphics_device_begin_render_pass 深度与模板清理 | GraphicsDeviceSDL / 渲染通道清理 | 无模板附件使用 DONT_CARE 模板操作；仅当深度与有效模板都不需要 LOAD 时才能 cycle，修复清深度时模板 LOAD 与 cycle 冲突的 SDL 验证错误 | 同步时重新评估 |
| L-007 | 2026-10-15 | 修复 | framework.odin / GraphicsDeviceEndFrame | GraphicsDeviceSDL / EndFrame | 提交帧命令缓冲前结束尚未关闭的 render pass，避免 SDL 验证报错及未完成的 MSAA 解析；port_regression 覆盖 EndFrame 后读取清理结果 | 同步时重新评估 |
| L-008 | 2026-10-15 | 修复 | graphics.odin / GraphicsDeviceUploadToBuffer | GraphicsDeviceSDL / 缓冲上传 | 帧内上传即使存在绘制通道也先结束通道并复用当前命令缓冲，避免每个 UI 网格的上传进入独立提交及 WaitForGPUIdle；每帧首次映射暂存缓冲使用 cycle，避免覆盖仍被 GPU 读取的上帧数据 | 同步时重新评估 |
| L-009 | 2026-10-15 | 行为变更 | graphics.odin / MaterialStageSetUniformBuffer | Material.cs / uniform 更新 | 复用已有 CPU 缓冲容量，避免每个物体每个 uniform 槽反复释放和分配；仍拷贝入参并同步 UniformBufferObjects，缩短和清空语义不变，回归检查稳定尺寸下零新增分配 | 同步时重新评估 |
| L-010 | 2026-10-15 | 修复 | framework.odin / InitApp 版本日志 | App.cs / 启动日志（C# 有 GC，无对应） | 释放 VersionString 与 SDLVersionString 的调用方所有权，消除每次原生启动的两笔共 16 字节泄漏 | 保留 |
| L-011 | 2026-10-15 | 修复 | graphics.odin / create_pipeline_for_draw_command | GraphicsDeviceSDL / 管线目标格式 | 窗口目标使用真实 SwapchainFormat 参与管线描述和缓存键，避免 Vulkan 的 BGRA 交换链复用 RGBA 离屏管线而触发验证错误 | 同步时重新评估 |
| L-012 | 2026-10-17 | 新增 | graphics.odin / ShaderTryInit；olib_shader_reload.odin / ShaderPairTryReplace | 无 | 开发期 Shader 创建返回错误；候选顶点/片元及实际绘制管线全部成功后原位替换，失败保留旧资源与材质引用，支持 2D/3D 热重载 | 保留 |
| L-013 | 2026-10-17 | 修复 | framework.odin / 默认 Shader 嵌入路径；assets/shaders/ | Framework/Content/Shaders | 原生产物统一移至 Compiled，保留字节内容；补回同步基线 06213b9 的 Batcher.hlsl，使 tools/shaders 能重建全部默认 Shader；Web GLSL 仍为手工适配源码 | 保留 |
| L-014 | 2026-10-18 | 修复 | web.odin / web_relocate_app | 无（Odin Web App 堆迁移） | 搬移 App 时重绑默认材质的 Shader 指针及 Shader 的 GraphicsDevice，避免 main 返回后引用旧栈地址，修复 Web MSDF 文字不显示 | 保留 |
| L-015 | 2026-10-19 | 新增 | olib_ext.odin / WriteAllBytesAtomic、WriteAllTextAtomic；platform_native.odin、platform_web.odin / storage_os_write_file_atomic | 无 | Storage 统一提供单文件原子替换，桌面同步同目录临时文件后重命名，Web 复用虚拟文件单键替换；ShaderLab 和游戏共用，拒绝只读/ZIP 写入，保留旧版直接写入 API | 保留 |
| L-016 | 2026-10-19 | 修复 | images.odin / ImageWritePng 与 imports | Image.cs / WritePng | 原生 PNG 路径转换复用包内 to_cstring，移除 Web 分支未使用的 strings 导入，使 Web -vet 通过，保持原有分配与写入行为 | 保留 |
| L-017 | 2026-10-20 | 新增 | graphics.odin / DrawCommand.InstanceOffset、DrawCommandInit、GraphicsDeviceDraw 的 SDL 绘制调用 | DrawCommand.cs（无实例偏移） | 实例属性从第 InstanceOffset 个实例读取（SDL first_instance），Render3D 每次提交只上传一次全部批次的实例数据，再按偏移逐批绘制，避免每批上传打断渲染通道；默认 0 行为不变，Web 忽略 | 保留 |
| L-018 | 2026-10-20 | 行为变更 | graphics.odin / target_init_with_attachments；olib_ext.odin / TextureIsSampleable、depth_attachment_sampleable | Target.cs / 构造附件纹理（深度附件只作深度目标）；采样判定无对应 | 单采样且格式支持采样的深度附件加 SAMPLER 用途，后处理可读场景深度（如深度描边）；TextureIsSampleable 用同一规则判定贴图能否绑定采样器，多采样深度（SDL 无深度解析）返回 false，材质绑定据此拒绝 | 保留 |
| L-019 | 2026-10-21 | 新增 | assets/shaders/Compiled/ 默认 Shader 产物与 sources.json；framework.odin / 默认 Shader 嵌入路径 | Framework/Content/Shaders（上游预编译产物） | 用 tools/shaders（shadercross 内置 DXC 1.8.2502）重建 Batcher/Textured/Msdf 并写入 Compiled/sources.json，tools/check 据此检查产物是否过期；源码未改。SPIR-V/MSL 只去掉各阶段未用的资源声明并重编 ID（Msdf 片元复用同一次纹理读取），DXIL 指令不变，只差编译器与验证器版本元数据；olib_sample 各示例截图在 D3D12/Vulkan 逐像素一致（Textured 无示例使用，另用临时程序对比），port_regression 通过。同步上游 shader 后用 tools/shaders 重新生成并验收 | 保留 |
| L-020 | 2026-10-22 | 新增 | framework.odin / AppFlag、window_init；olib_ext.odin / window_apply_logical_size | 无（App.cs 窗口尺寸直接交给 SDL） | 可选 AppFlag.LogicalWindowSize：Windows 上 SDL3 窗口坐标是物理像素，系统缩放 150% 时 960×720 只占设计尺寸的 2/3；打开后在窗口仍隐藏时按显示缩放 ÷ 像素密度放大配置宽高（macOS 为 1 不变），限制在显示器可用区域内并居中。默认关闭，示例与截图检查的像素尺寸不变 | 保留 |
| L-021 | 2026-10-22 | 修复 | framework.odin / ContentScale | Window.cs / ContentScale（SDL_GetWindowDisplayScale） | Web 端没有 SDL 窗口，原实现仍引用 SDL_GetWindowDisplayScale，WASM 因此带入 SDL 函数导入；改为画布像素 ÷ CSS 尺寸（即 devicePixelRatio），与桌面同为逻辑单位到绘制像素的比例 | 保留 |
