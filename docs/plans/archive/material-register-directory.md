# Plan：材质效果按目录登记，去掉手写 #load

> **状态：已完成（2026-10-20）** · 提交 `c42a910`..`216e6bc`（olib_sample：`e6b42e7`）
> 偏离：① 第 4 步按决策 9 跳过：stylized3d 的 `shaders.odin`、`main.odin` 仍有未提交改动，AmbientOcclusion、SunShadow 等文件未跟踪，等这些改动提交后再迁移。② 计划文件先单独提交（`c42a910`），归档的 `git mv` 需要它已被跟踪。③ material3d 没有选择驱动的参数，Vulkan 那次用环境变量 `SDL_GPU_DRIVER=vulkan` 指定，并用无效驱动名确认该变量确实生效。

## 背景

`.oshader` 材质效果经 `tools/shaders` 编译后，`Compiled/` 里有清单 `<Effect>.shader.json` 和每个参数组的
`<组名>.vertex/.fragment.<spv|dxil|msl>`（instanced 精灵另有 `<组名>.instanced.vertex.*`）。游戏要用这些效果，
目前得逐个 `#load` 拼出 `[]mat.Pass_Binaries` 再调 `mat.material_register_manifest`：

| 位置 | 手写 `#load` 行数（2026-10-20 工作区） |
| --- | ---: |
| olib_sample `src/material2d/shaders.odin`（SpriteShadow） | 19 |
| olib_sample `src/material3d/shaders.odin`（Outlined、Swarm） | 20 |
| olib_sample `src/stylized3d/shaders.odin`（8 个效果） | 62 |

`.oshader` 每加一个 Pass 要回来手抄 6～9 行，`tools/shaders/README.md` 也要求“新增 shader 时同步更新相应模块的 `#load`”。
这些信息清单里都有：清单的 `schemas[i].name` 就是该 Pass 产物的文件名前缀（如 `SpriteShadow_shadow`）。

已核对的事实：

- Odin（dev-2026-10-nightly）支持 `#load_directory(path) -> []runtime.Load_Directory_File`，元素是
  `{name: string, data: []byte}`，`name` 为不带目录的文件名。它必须作变量初始化或直接作参数；
  写成 `X :: #load_directory(...)` 会报 “is not a compile-time known constant”。
- 示例共用目录 `olib_sample/src/shader_lab/shaders/Compiled` 有 8 个效果、116 个文件、共 320,118 字节；
  其中 SpriteShadow 的产物 66,860 字节。
- 这 8 个效果里只有 Outlined、Swarm（首个 Pass 为 Model）和 SpriteShadow（Sprite）是材质；
  Preview2D、Preview3D（Preview_Model）和 Trail2D、Trail3D、Unified（Fullscreen）只供 Shader Lab 预览，
  `material_register` 会以 “Expected Model or Sprite material effect” 拒绝。stylized3d 的 8 个效果都是材质。
- 登记只保存字节码切片，GPU Shader 在首次 `material_create` 时才创建（`material_effect_prepare`），
  所以多登记几个用不到的效果只多占嵌入字节和一次清单解析。
- 现有测试 `material_register_manifest_selects_backend_and_validates` 用 `foster.GraphicsDevice{Driver = .D3D12}`
  这样的假设备和 `json.marshal` 生成的清单测试登记，不需要 GPU。
- `tools/check` 的单元测试隔离编译只改写字面量 `#load(...)` 的相对路径；本计划的 `#load_directory`
  只出现在示例/游戏代码里，kit 不调用它，所以不受影响。
- 热重载 Watch 默认只监听 `.odin`，`#load` 的数据文件要列入 `roots` 或 `extensions`（core/hotreload/REFERENCE.md）；
  `#load_directory` 同理。

## 已定决策（执行时不要改）

1. **新增一个函数，放在 `kit/rendering/material/shader_code.odin`**：

   ```odin
   material_register_directory :: proc(library: ^Material_Library,
   	files: []runtime.Load_Directory_File) -> string
   ```

   用法只有一行：

   ```odin
   reason := mat.material_register_directory(&materials, #load_directory("shaders/Compiled"))
   ```

   不新增结构体，不改 `tools/shaders` 的产物格式和命名，不升 `MANIFEST_VERSION`。
2. **查找规则**：遍历 `files` 中所有 `*.shader.json`；对清单里每个参数组名 `S`，找
   `S.vertex.<格式>`、`S.fragment.<格式>`，效果是 Sprite 且 `instanced` 时再找 `S.instanced.vertex.<格式>`。
   `<格式>` 按驱动只取当前后端：D3D12 → `dxil`，Vulkan → `spv`，Metal → `msl`，与 `shader_pick` 的映射一致。
   其他文件（别的后端格式、无关文件）忽略。
3. **非材质效果跳过**：首个 Pass 不是 Model 或 Sprite 的效果（Shader Lab 预览用的 Fullscreen、Preview_Model）
   不登记、不报错。
4. **错误**：设备为空、后端不支持时，在扫描前返回与 `material_register_manifest` 相同的文本。
   一个 `*.shader.json` 都没有时返回错误（目录写错）。其余错误遇到第一个就返回，文本以文件名开头，例如
   `SpriteShadow_body.fragment.dxil: missing compiled shader; re-run tools/shaders`、
   `Hero.shader.json: Compiled shader manifest is outdated; re-run tools/shaders`。之前已登记的效果保留，
   与逐个调用 `material_register_manifest` 时相同。
5. **共用一份清单处理**：清单解析、版本检查、按驱动选择和调用 `material_register` 抽成两个函数共用的私有过程，
   错误文本只有一处。
6. **字节码借用嵌入数据**，不复制，生命周期与 `#load` 相同。
7. **保留 `material_register_manifest`、`Pass_Binaries`、`Shader_Binaries`、`shader_pick` 的公开签名**，
   供字节码来自别处（自定义打包、网络等）时使用；外部项目不受影响。
8. **示例**：material2d、material3d 删除 `shaders.odin`，在 `main.odin` 原来的登记处直接调用新函数。
   两者共用的 `shader_lab/shaders/Compiled` 会登记 Outlined、SpriteShadow、Swarm，跳过 5 个预览效果；
   接受每个示例嵌入整个目录（约 320 KB）。
9. **stylized3d 只在它的进行中改动提交之后再迁移**：当前工作区里 `shaders.odin`、`main.odin` 有未提交修改，
   AmbientOcclusion、SunShadow 等文件未跟踪。执行到该步时若仍未提交，就跳过并在汇报里说明，不动这些文件。

## 执行步骤

前置：olib 与 olib_sample 都从 `master` 新建分支 `material-register-directory`。两个仓库的工作区都有不属于本计划的
未提交改动（olib：`kit/tools/shader_lab/bank.odin`；olib_sample：stylized3d 下的修改与新文件、根 `README.md`），
全程不提交它们，每次提交只 `git add` 本计划的文件。开始前运行 `odin run tools/check` 记录基线；若基线就因这些改动失败，
停下来汇报。再用 `shot` 参数为 material2d（默认、`swarm`）和 material3d（默认、`models`、`swarm`）各截一张基线图，
复制到 olib_sample `library/tmp/register-directory-baseline/`，并记下 `build/material2d.exe`、`build/material3d.exe` 的大小。

### 1. olib：material_register_directory 与单元测试

按决策 1～7 实现。测试加在 `tests/kit/rendering/material/draw_test.odin` 现有清单登记测试旁边，
用假设备和内存里的 `runtime.Load_Directory_File` 列表，至少覆盖：

- 一个 Model 效果和一个 instanced Sprite 效果一起登记成功，登记的代码切片指向当前后端的那份文件；
  换成 `.Vulkan` 的库选到 `spv`。
- Fullscreen 效果被跳过，不报错。
- 缺 `.fragment.<格式>`、缺 instanced 精灵的 `.instanced.vertex.<格式>`：错误以缺失的文件名开头。
- 清单版本过旧：错误以清单文件名开头。
- 没有任何 `*.shader.json`：返回错误。
- 设备为空、后端不支持：与 `material_register_manifest` 的文本一致。

运行 `odin run tools/check -- -only:kit/rendering/material`，再跑完整 `odin run tools/check`。

提交：olib `material: material_register_directory 按目录登记 tools/shaders 产物`

### 2. olib：文档

- `kit/rendering/material/README.md`：文件表里 `shader_code.odin` 一行加上新函数；“公共材质资源”的示例改用
  `material_register_directory`，说明查找规则、非材质效果跳过、`#load_directory` 必须作变量初始化或参数、
  热重载 Watch 要把 Compiled 目录或对应扩展名列入监听；`material_register_manifest` 改为“字节码来自别处时”的用法。
- `kit/rendering/README.md` 第 27、37 行：登记效果改为以 `material_register_directory` 为主。
- `tools/shaders/README.md`：第 8 行改为运行时由 `material_register_directory` 按文件名找到产物；
  第 75 行“同步更新相应模块的 `#load`”限定为手写 `.hlsl`，`.oshader` 材质不需要改任何 Odin 代码。

提交：olib `docs: 材质效果按目录登记`

### 3. olib_sample：material2d、material3d 改用目录登记

按决策 8 删除两个 `shaders.odin`，`main.odin` 改为一次调用（material3d 原来的 `register_materials` 与
`register_swarm` 合成一次）。更新 `src/material3d/README.md` 第 31 行等提到 `shaders.odin` 的说明。

验证：`odin run tools/check`（在 olib 根目录运行，包含示例编译）全部通过；重跑前置里的 5 张 `shot`，
与基线逐像素一致；记录两个 exe 迁移后的大小。

提交：olib_sample `samples: material2d/material3d 按目录登记材质效果`

### 4. olib_sample：stylized3d 改用目录登记（有条件）

只在决策 9 的条件满足时执行：删除 `register_effects` 的手写列表，`main.odin` 第 116 行附近改为一次调用
`#load_directory("shaders/Compiled")`；更新 `src/stylized3d/README.md` 中对应说明。改前改后各跑一次
`run.bat stylized3d shot`，画面一致。

提交：olib_sample `samples: stylized3d 按目录登记材质效果`

### 5. 按 docs/plans/README.md 归档本计划

## 验收

- `odin run tools/check` 全部通过，包含第 1 步新增的单元测试。
- olib_sample 已迁移的示例里不再出现 `Pass_Binaries`、`material_register_manifest` 和指向 `Compiled/` 的 `#load`
  （`grep -rn "Pass_Binaries\|material_register_manifest" src` 只剩跳过的 stylized3d，或为空）。
- material2d、material3d 的 `shot` 与基线逐像素一致（D3D12），material3d `swarm` 再在 Vulkan 下跑一次正常退出。
- 之后在 `.oshader` 里增删 Pass 或效果，只需重新运行 `tools/shaders`，不改任何 Odin 文件。

## 禁止事项

- 不改 `tools/shaders` 的产物格式与命名，不升 `MANIFEST_VERSION`。
- 不删除、不改名 `material_register_manifest`、`Pass_Binaries`、`Shader_Binaries`、`shader_pick`。
- 不迁移手写 `.hlsl` 渲染器的 `#load`（forward3d、book_ui、kit/gizmo、kit/rendering/3d 的调试线、foster 内置 Shader），
  它们需要逐个指定资源数量，不走清单。
- kit 内不调用 `#load_directory`，不改 `tools/check`。
- 不提交、不修改不属于本计划的未提交改动（见前置）；不碰 Proj_Sand；不 push。
- 不改 `docs/plans/archive/` 里历史计划的正文。

## 汇报内容

- 两个仓库各自的 commit 列表。
- `tools/check` 结果，有失败就贴输出；新增单元测试的名字。
- 5 张 `shot` 与基线的对比结果，以及 material3d `swarm` 的 Vulkan 运行结果。
- material2d、material3d 的 exe 迁移前后大小。
- stylized3d 是否迁移；跳过时说明原因。
- 与计划不一致的地方及原因。
