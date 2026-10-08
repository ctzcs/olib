# Plan：修复 foster 资源名字与 Target 附件像素的内存泄漏

## 背景

Proj_Sand 的 `src/view/view.odin:31` 为了绕开泄漏，初始化 Batcher 时特意不传名字（注释：“当前 Foster 不回收命名 Mesh 的派生名称”）。排查后发现两类泄漏，都用 Tracking_Allocator 复现过：创建一个 Batcher 和一个 64×64 Target 再释放，统计残留分配。

| 传入名字 | 残留分配 | 内容 |
|---|---|---|
| `""` | 1 个 | 16384 字节（64×64×4），来自 `graphics.odin:3144` 的 `resize(&tex.Pixels, ...)` |
| `"hud"` | 4 个 | 上面那块，加上 `"hud-Vertices"`、`"hud-Indices"`、`"hud-Attachment0"` |

**泄漏一：派生名字没人释放**

foster 用 `fmt.aprintf`（长期分配器）拼出派生名字，传给缓冲区或纹理；但 `GraphicsBuffer`、`Texture` 只是借用 `Name`，释放时不删除：

- `foster/graphics.odin:928-929`：`mesh_init_with_format` 拼 `"<name>-Vertices"`、`"<name>-Indices"`（Batcher 内部 Mesh 走这里）；
- `foster/graphics.odin:962`：`mesh_init_instanced_with_format` 拼 `"<name>-Instances"`；
- `foster/graphics.odin:614`：`target_init_with_attachments` 为每个附件拼 `"<name>-Attachment<i>"`。

名字保存在 `graphics_buffer_init`（`buf.Name = name`，Web 与桌面两处，约第 3925、3960 行）和 `texture_init_ex`（`tex.Name = name`，约第 3078、3133 行）。

**泄漏二：Target 释放时不释放附件的 CPU 像素**

`texture_init_ex` 给每张纹理分配一块 `宽 × 高 × 每像素字节` 的 CPU 像素缓冲（`tex.Pixels`）。`texture_dispose`（约第 3187 行）会 `delete(tex.Pixels)`，但对 Target 附件不适用。`target_dispose`（约第 650 行）只释放了附件的 GPU 资源，没有 `delete` 附件的 `Pixels`，Web 和桌面两条路径都这样。一个 1280×800 的 Target 每次释放泄漏约 4MB（颜色附件），窗口大小改变时重建 Target 的游戏会持续泄漏。

注意：`texture_dispose` 对 `IsTargetAttachment` 的纹理**故意不释放** `Resource`（由 `target_dispose` 负责）。所以不能简单地在 `target_dispose` 里对附件再调一次 `texture_dispose` 了事，必须保证 GPU 资源只释放一次。

## 已定决策（执行时不要改）

1. **`GraphicsBuffer` 和 `Texture` 拥有自己 `Name` 的副本**：`graphics_buffer_init`、`texture_init_ex` 里 `strings.clone(name)`（空串不分配），记录所用分配器，在 `graphics_buffer_dispose`、`texture_dispose` 里删除。如果这两个 init 会被用于重新初始化已有对象（例如 `texture_init_ex` 在第 3143 行先 `delete(tex.Pixels)`，说明存在重入），在赋新名字前先删除旧名字。
2. 派生名字改用临时分配器拼接（`fmt.tprintf`），因为接收方会自己克隆。
3. `Mesh.Name`、`Target.Name`、`Shader.Name` 保持**借用**不变（调用方通常传字符串字面量），只在声明处的注释里写明“借用，调用方保证在资源存活期间有效”。
4. `target_dispose`：在释放每个附件 GPU 资源之后，删除该附件的 `Pixels` 和 `Name`（Web 与桌面两条路径都要）。GPU 资源仍只由 `target_dispose` 释放一次。如果能把附件释放整理成一个内部小函数供两条路径共用，可以做，但不要改变 GPU 释放的顺序和次数。
5. 这是对 foster 的修复，按 `foster/docs/LOCAL_CHANGES.md` 登记为 **L-003**：类型“修复”，上游对应写 `GraphicsBuffer.cs / Texture.cs / Target.Dispose（C# 有 GC，无对应）`，同步策略“保留”。所有修改点打 `// [olib L-003]` 标记。
6. **不改**“每张纹理保留一份 CPU 像素副本”的设计（这是另一个话题，本次只修泄漏）。不改 `thirdparty/`，不改 kit。

## 执行步骤

在 master 上新建分支 `foster-resource-leaks`，每一步一个 commit。开始前运行 `powershell -File check.ps1` 确认全部通过。

### 0. 复现程序

在 `build/scratch/foster-resource-leaks/` 写一个复现程序（不提交）：

```odin
package main

import "core:fmt"
import "core:mem"

import foster "olib:foster"

game: foster.App
track: mem.Tracking_Allocator

startup :: proc(app: ^foster.App) {
	context.allocator = mem.tracking_allocator(&track)
	for name in ([]string{"", "hud"}) {
		before := len(track.allocation_map)
		b: foster.Batcher
		foster.BatcherInit(&b, &app.GraphicsDevice, name)
		foster.BatcherDispose(&b)
		t: foster.Target
		foster.TargetInit(&t, &app.GraphicsDevice, 64, 64, name)
		foster.TargetDispose(&t)
		fmt.printfln("name=%q 残留分配: %d", name, len(track.allocation_map) - before)
		for _, entry in track.allocation_map {
			fmt.printfln("    size=%d @ %v", entry.size, entry.location)
		}
	}
	foster.Exit(app)
}

main :: proc() {
	mem.tracking_allocator_init(&track, context.allocator)
	foster.InitApp(&game, foster.DefaultAppConfig("leak", 320, 240))
	defer foster.Dispose(&game)
	game.StartupProc = startup
	foster.Run(&game)
}
```

用 `odin run <目录> -collection:olib=. -debug` 运行。改动前应输出 `name="" 残留分配: 1`、`name="hud" 残留分配: 4`，记录下来。
再扩展覆盖：带实例数据的 Mesh（`MeshInitInstanced` 传名字）、单独创建并释放的命名 `Texture`、命名的 `StorageBufferInit`（`graphics.odin:4259`）与 `ComputeStorageBufferInit`（约第 4305 行）。

### 1. 名字所有权（泄漏一）

按“已定决策”第 1 到 3 条修改。复现程序中所有命名资源释放后残留为 0。

Commit：`foster: GraphicsBuffer / Texture 拥有名字副本，修复派生名字泄漏（L-003）`

### 2. Target 附件像素与名字（泄漏二）

按“已定决策”第 4 条修改 `target_dispose`。复现程序两种情况都残留 0；再加一个用例：同一个 Target 连续 `TargetInit` / `TargetDispose` 100 次（模拟窗口缩放重建），残留仍为 0。

Commit：`foster: target_dispose 释放附件像素与名字（L-003）`

### 3. 登记与回归

- 在 `foster/docs/LOCAL_CHANGES.md` 添加 L-003 一行；`powershell -File foster/tests/check_local_changes.ps1` 通过。
- `powershell -File check.ps1` 全部通过。
- 实际运行 `odin run foster/tests/port_regression -collection:olib=.`，全部 PASS（它有“零未释放分配”检查）。
- OFoster_Sample 截图回归：改动前后各跑 `run.bat game_ui shot`、`run.bat ui_gallery shot`、`run.bat ui_gallery shot msdf`，逐像素一致（game_ui 的 `shot` 会创建并释放 capture Target，正好覆盖本次修改）。
- 如果能开窗口，运行 `foster/tests/graphics_regression`（见其 README）。不能运行的如实说明。

LOCAL_CHANGES 的修改并入第 2 步的 commit，或单独提交 `foster: 登记 L-003`。

### 4. 移除 Proj_Sand 的绕开写法

在 `D:\MySpace\Github\Proj_Sand` 的 `src/view/view.odin:31`：删掉“当前 Foster 不回收命名 Mesh 的派生名称”的注释，`BatcherInit` 传一个有意义的名字（如 `"view"`），运行 Proj_Sand 的 `check.ps1`。**Proj_Sand 还没有任何提交，不要替用户提交**，只改文件并在汇报中说明。

### 5. 归档本计划

按 [docs/plans/README.md](README.md) 归档本计划。

## 验收

- 复现程序：改动前 1 / 4 个残留，改动后全部为 0（含实例 Mesh、Texture、StorageBuffer / ComputeStorageBuffer、Target 重建 100 次）；
- `check.ps1`、`port_regression`、`check_local_changes.ps1` 全部通过；
- OFoster_Sample 截图逐像素一致。

## 禁止事项

- 不改 CPU 像素副本的设计；不改 kit、`thirdparty/`。
- GPU 资源不能重复释放，也不能漏释放；修改 `target_dispose` 时保持 Web 与桌面两条路径一致。
- 不替用户提交 Proj_Sand；不 push；不合并回 master。

## 汇报内容

- commit 列表；
- 复现程序改动前后的输出；
- 回归结果（check.ps1、port_regression、截图、graphics_regression 是否运行）；
- 是否发现 `texture_init_ex` / `graphics_buffer_init` 的重入调用，以及如何处理；
- 任何偏离本计划的地方及原因。
