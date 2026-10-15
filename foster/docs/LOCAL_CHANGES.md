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
