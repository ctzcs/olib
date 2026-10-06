# olib:engine/asset —— ofoster 资源管线 v1

`.meta` 管身份，`Library/` 管派生物，blob 是 Importer 与 Runtime 的边界，pak 将来只是 Storage 后端的变化。

## 架构

```
Project/
├── Assets/                  # 人编辑的源资源
│   └── textures/
│       ├── belt.png
│       └── belt.png.meta    # {"guid": "31d0…"} —— 身份，进 Git，跟着文件走
└── Library/                 # 机器生成，gitignore
    └── 31d0a7c9.blob        # blob 名 = GUID；运行时按 guid 零表直查

     Assets/ 源文件 ──(import_all)──> Library/<guid>.blob ──(assets_load)──> Asset_Handle
```

三条不变量（判断这套管线干不干净的标尺，均有测试覆盖）：

1. **删除整个 `Library/` → `import_all` → 完整恢复**（Library 是纯派生缓存）
2. **移动源文件 + .meta → GUID 不变 → 不重新导入**（blob 按 GUID 定位，freshness 只看源 mtime+size）
3. **源与 mtime/size 都没变 → 跳过导入**（改了导入逻辑则靠 importer version 强制重导）

## 快速上手

工具/编辑器侧（每次启动时跑一次）：

```odin
import asset "olib:engine/asset"

stats, err := asset.import_all("Assets", "Library")
// stats: {scanned, imported, skipped, guid_generated, orphaned_meta}
```

游戏侧（startup 一次；update/render 里用句柄取对象；**开发与打包是同一段代码**）：

```odin
m: asset.Asset_Manager
asset.assets_init(&m, .{
    assets_root  = "Assets",   // 打包发行时可留 ""（纯 manifest，见下）
    library_root = "Library",
    device       = &app.GraphicsDevice, // 传入则 .Texture 自动建 GPU 贴图
})
defer asset.assets_dispose(&m)

tex, err := asset.assets_load_path(&m, "textures/belt.png")   // 先查 manifest，miss 回退 .meta
// 或 asset.assets_load(&m, guid) —— 正式数据里存 guid，零表直查

foster.BatcherQuadTexture(&batcher, asset.assets_get_texture(&m, tex), …)
```

Asset_Handle 带 `array` 代数，不依赖 ECS，任何 struct 里放一个即可引用资产。

## manifest：打包零改动

`import_all` 收尾会把全部 `path → GUID` 全量重写进**一个保留 GUID 的 Raw blob**
（和其他派生物一样躺在 Library 里）。`assets_load_path` 先查它，查不到再回退读
源文件旁的 `.meta`：

- 开发期：两条路都在；新丢进 Assets 还没导入的文件自动落到 `.meta` 回退
- 打包后：只发行 `Library/`（将来 pak），`assets_load_path` 原样工作——
  `assets_root` 留空即可，**加载代码一行不用改**
- manifest 是纯派生物（从 .meta 推导），不进版本控制；用保留 GUID 的 blob
  而非散文件，是为了和其他 blob 共用同一条 `Asset_Storage` 通道，pak 后端
  不需要任何特殊处理

## .meta 纪律

- `.meta` **进版本控制**（它是身份，不是缓存）；`Library/` 不进
- 移动/重命名源文件时**把 .meta 一起带走**，所有 GUID 引用不断
- **绝不手动编辑 guid**；复制 .meta 会撞出 `Duplicate_Guid`（import_all 报错，绝不静默换 GUID——静默换会破坏既有引用）
- 删除资产 = 源文件 + .meta 一起删；孤立的 .meta（源没了）import_all 只警告不删，防误删身份
- GUID 是 128-bit 随机数，由时间+pid+计数器混合熵生成

## 自定义导入器

```odin
asset.importer_register(".aseprite", .{
    kind    = .Raw,          // 产出 blob 的 Asset_Kind（Raw/Texture/Json）
    version = 3,             // 改了导入逻辑就 +1：旧 blob 自动过期重导
    run     = my_import_proc, // (source, ext, ^Payload_Builder, allocator) -> Asset_Error
})
```

内建：`.png/.jpg/.jpeg/.qoi/.bmp/.tga → Texture`（解码为 RGBA8 像素）、`.json → Json`、
其余扩展名 → Raw 直通（shader blob / .cache / .field 等）。

Texture 的 `Payload_Builder` 填 `width/height/format + data(像素)`；
Json/Raw 只填 `data`。

## Asset_Storage 与 pak 演进

Runtime 只以 Guid 请求 blob，不知道文件名（`31d0….blob` 是 directory 后端的实现细节）：

```odin
Asset_Storage :: struct {
    read:     proc (storage: ^Asset_Storage, guid: Guid, allocator) -> ([]u8, bool),
    exists:   proc (storage: ^Asset_Storage, guid: Guid) -> bool,
    userdata: rawptr,
}
```

- `storage_directory(library_root)` —— 开发期默认
- `storage_map(&state)` —— 内存后端（测试；将来 web 目标把 `#load` 预烘焙的 blob 塞进来）
- **pak（未实现）**：再加一个同签名后端（read = pak 索引 → offset/size），Runtime 代码零改动

blob 头含 `importer_version` 与源的 `mtime/size`；新鲜度 = 三者全部一致才跳过。

## 资产间引用

引用一律存 GUID（关卡/prefab 数据里写 32-hex 字符串，运行期
`guid_from_string` + `assets_load`，开发/打包同一段代码——GUID 引用位置无关，
被引用资产的 blob 就在同一个 Library/pak 里）。

**暂缓**：源格式内部的路径引用（gltf/tiled/aseprite 引用外部文件）。
届时给 `Import_Proc` 签名加一个 `source_rel: string` 参数，导入器即可在导入时
把相对路径解析成 GUID 烘焙进 payload；架构不变，仅注册方签名要同步改。

## 文件

| 文件 | 职责 |
|---|---|
| `asset.odin` | Guid、Asset_Kind/Handle/Error、Asset_Manager（load/get/unload/缓存） |
| `meta.odin` | .meta 读写与 ensure（复用 `olib:encoding`） |
| `blob.odin` | OLASBLOB 格式（header + 各 Kind payload）读写 |
| `importer.odin` | import_all：扫描→发 GUID→查重→新鲜度→分派导入→孤儿警告→重写 manifest |
| `manifest.odin` | path→GUID 寻址层（保留 GUID 的 Raw blob；打包后 load_path 零改动） |
| `loader.odin` | Asset_Storage 后端（directory/map） |
| `asset_test.odin` | 8 个测试，覆盖全部不变量（含打包形态：只带 Library、无 Assets） |

## 构建与测试

```bash
odin test engine/asset -collection:olib=. -collection:ofoster=<ofoster src 根>
```

v1 仅支持 native 目标（扫描/mtime 依赖 `core:os`）。web 路线：`storage_map` + `#load`
预烘焙 blob；前置任务是 `olib:encoding` 的 js 兼容（其 json_load/save 目前走 core:os）。

## 已知上游问题（与本模块无关，绕开或等待修复）

- Odin `os.remove_all` 在 Windows 崩溃：master 仍未修（`SHFileOperationW` 要求双 NUL 终止路径，core 的 `win32_utf8_to_wstring` 只给单 NUL；已提 issue [#7547](https://github.com/odin-lang/Odin/issues/7547)）；测试自带递归删除绕开
- 切片 `transmute` 保留 len 数值而非按字节数换算：这是**设计语义**，不会随版本更新改变（编译器对 transmute 仅要求两个切片头部同为 24 字节，之后纯位拷贝）——跨类型字节拷贝一律用 `mem.copy(rawptr, rawptr, 字节数)`
- `odin check` 对库包也要求入口点，本环境用 `-no-entry-point`（`odin test` 不受影响）
