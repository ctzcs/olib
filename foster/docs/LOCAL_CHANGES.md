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
5. **检查**：提交前运行 `powershell -File foster/tests/check_local_changes.ps1`，
   代码标记与本表编号必须一一对应。

字段说明：

- **类型**：`新增` / `行为变更` / `修复` / `删除`
- **位置**：`文件 / 分区或符号`，与 CODE_STYLE 的分区路径一致
- **上游对应**：C# 文件与成员（如 `Batcher.cs / PushQuad`）；纯新增写 `无`
- **同步策略**：`保留` / `上游修复后删除` / `同步时重新评估`

## 清单

| 编号 | 日期 | 类型 | 位置 | 上游对应 | 原因 | 同步策略 |
| --- | --- | --- | --- | --- | --- | --- |
| L-001 | 2026-10-08 | 行为变更 | framework.odin / tick_app；storage.odin / file_system_open_title_storage、RelativeStorage 路径所有权 | App.cs / 主循环（C# 有 GC，无对应） | 每帧 Render/end_frame 后清空临时分配器；Startup 临时数据在第一帧末失效。标题存储回退为空 Root（相对 cwd）；RelativeStorage 持有长期拼接路径，返回的容器借用直到路径改变或 RelativeStorageDispose，由调用方释放 | 保留 |
| L-002 | 2026-10-08 | 修复 | storage.odin / zip_storage_decode；images.odin / AsepriteLoad | 无（Odin 写法） | 未使用循环索引改为 _；拷贝后的 Aseprite 数据改名 source_data，避免遮蔽输入参数；只改写法，不改行为 | 保留 |
