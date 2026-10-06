// olib:engine/asset —— ofoster 资源管线 v1。
//
// 架构（.meta 管身份，Library 管派生物，blob 是 Importer/Runtime 边界）：
//
//   Assets/                  Library/                    Runtime
//   demo.qoi        --Importer-->  31d0a7c9.blob  --Loader-->  Asset_Handle
//   demo.qoi.meta   (身份, git)    (派生缓存,       (按 guid 零表直查,
//                                  可删重建)         不知道文件名)
//
// 分层纪律：
//   - .meta 是资产身份（{"guid":"..."}），提交进版本控制，移动源文件时跟着走；
//     GUID 一旦发布就永不改变，关卡/存档里只存 GUID。
//   - Library/ 是纯派生缓存，不进版本控制；删除整个 Library 后跑一次
//     import_all 即可完整恢复——这是本管线"干净"的不变量。
//   - blob 是 Importer 与 Runtime 的唯一边界；将来的 pak 只是给
//     Asset_Storage 换一个后端（guid -> pak 索引 -> offset/size），
//     Runtime 代码零改动。
//   - manifest（保留 GUID 的 Raw blob，import_all 收尾全量重写）记录
//     path -> guid，让 assets_load_path 在打包形态（只带 Library/pak）下
//     原样可用——开发期与打包期加载代码完全相同。
//
// 典型用法（开发期，编辑器/工具侧每次启动时）：
//
//   stats, err := asset.import_all("Assets", "Library")
//
// 游戏侧（startup 一次，update/render 里用句柄取对象；开发/打包同一段代码）：
//
//   m: asset.Asset_Manager
//   asset.assets_init(&m, .{
//       assets_root  = "Assets",          // assets_load_path 的 .meta 回退用；
//       library_root = "Library",         //   打包发行时可为 ""（纯 manifest）
//       device       = &app.GraphicsDevice, // 传了则贴图自动上 GPU
//   })
//   defer asset.assets_dispose(&m)
//   tex, err := asset.assets_load_path(&m, "textures/belt.png")
//   // render: foster.BatcherQuadTexture(&batcher, asset.assets_get_texture(&m, tex), ...)
//
// 构建（native；本包 v1 仅支持 native 目标，扫描/mtime 依赖 core:os）：
//   odin build <app> -collection:olib=<olib 根> -collection:ofoster=<ofoster src 根>
package asset

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import ha "olib:core/handle/array"
import foster "ofoster:."

// ===========================================================================
// Guid —— 资产身份
// ===========================================================================

// 128-bit 资产身份。属于源资产（存放在 .meta 里），与路径解耦：
// 移动/重命名文件只要 .meta 跟着走，所有 GUID 引用不断。
Guid :: distinct [16]u8

GUID_NONE :: Guid{}

// 进程内计数器 + 墙钟 + pid 混合熵；128-bit 随机空间下碰撞概率可忽略。
// 不做"撞表重生"：库层没有全局表，冲突由 import_all 扫描 .meta 时以
// Duplicate_Guid 显式报错（静默换 GUID 会破坏既有引用）。
@(private)
guid_counter: u64 = 0x51ED270B4C9D3F1A

@(private) @(cold)
splitmix64 :: proc "contextless" (s: ^u64) -> u64 {
	s^ += 0x9E3779B97F4A7C15
	z := s^
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

guid_generate :: proc() -> Guid {
	guid_counter += 0x9E3779B97F4A7C15
	s := u64(time.time_to_unix_nano(time.now())) ~ guid_counter ~ (u64(os.get_pid()) << 32)

	bytes: [16]u8
	for i in 0..<2 {
		v := splitmix64(&s)
		for j in 0..<8 {
			bytes[i * 8 + j] = u8(v >> cast(u64)(8 * j))
		}
	}
	return Guid(bytes)
}

// 32 位小写 hex（分配于 allocator，调用方负责释放）。
guid_to_string :: proc(g: Guid, allocator := context.allocator) -> string {
	buf: [32]u8
	guid_hex_into(g, buf[:])
	res, err := strings.clone(string(buf[:]), allocator)
	if err != .None do return ""
	return res
}

// 解析 32 位 hex（大小写均可，容忍 '-' 分隔）。失败返回 (GUID_NONE, false)。
guid_from_string :: proc(s: string) -> (Guid, bool) {
	out: [16]u8
	n := 0
	for c in s {
		if c == '-' do continue
		v: u8
		switch {
		case c >= '0' && c <= '9': v = u8(c - '0')
		case c >= 'a' && c <= 'f': v = u8(c - 'a') + 10
		case c >= 'A' && c <= 'F': v = u8(c - 'A') + 10
		case:                       return GUID_NONE, false
		}
		if n >= 32 do return GUID_NONE, false
		if n % 2 == 0 {
			out[n / 2] = v << 4
		} else {
			out[n / 2] |= v
		}
		n += 1
	}
	if n != 32 do return GUID_NONE, false
	return Guid(out), true
}

// 把 guid 写成 32 字符小写 hex 到 dst（不分配；dst 需 >= 32 字节）。
guid_hex_into :: proc(g: Guid, dst: []u8) {
	for i in 0..<16 {
		hi := (cast([16]u8)g)[i] >> 4
		lo := (cast([16]u8)g)[i] & 0xF
		dst[i * 2 + 0] = hi < 10 ? u8('0') + hi : u8('a') + hi - 10
		dst[i * 2 + 1] = lo < 10 ? u8('0') + lo : u8('a') + lo - 10
	}
}

// Library 内的 blob 文件名（"<32hex>.blob"）。写入调用方的栈缓冲并返回视图，
// 视图只在缓冲存活期间有效——用于免分配地构造后端读取路径。
guid_filename :: proc(g: Guid, dst: []u8) -> (name: string, ok: bool) {
	if len(dst) < 37 do return "", false
	guid_hex_into(g, dst[:32])
	dst[32] = '.'; dst[33] = 'b'; dst[34] = 'l'; dst[35] = 'o'; dst[36] = 'b'
	return string(dst[:37]), true
}

// ===========================================================================
// 句柄 / 错误 / 种类
// ===========================================================================

// blob payload 的运行时形态（决定 loader 建什么对象）。
Asset_Kind :: enum u8 {
	Raw,     // 原样字节：shader blob / .cache / .field 等自定义二进制
	Texture, // 解码后的 RGBA8 像素
	Json,    // utf8 JSON 文本
}

Asset_Error :: enum {
	None,
	File_Not_Found,  // Library 里没有该 guid 的 blob
	Meta_Missing,    // 源文件旁没有 .meta（先跑 import_all）
	Parse_Error,     // blob/JSON/.meta 内容不合法，或 blob 内 guid 与请求不符
	Write_Error,     // blob/.meta 写盘失败
	Import_Failed,   // 导入器无法处理该源文件
	Kind_Mismatch,   // 用 Texture 的 getter 取 Json 资产之类
	Duplicate_Guid,  // 两个 .meta 持有同一 GUID（人为复制 .meta 所致，需手动处理）
	Not_Supported,   // 未配置 assets_root 却调用 assets_load_path 等
}

// 运行时资产句柄。带代数（ha.Handle），卸载后旧句柄自动失效。
// 不依赖 ECS：任何 struct 里放一个 Asset_Handle 即可引用资产。
Asset_Handle :: distinct ha.Handle

ASSET_HANDLE_NONE :: Asset_Handle{}

// ===========================================================================
// Asset_Manager —— 运行时加载与缓存
// ===========================================================================

// 一条已加载资产。payload 按 kind 有效，其余字段为零值。
Asset_Record :: struct {
	guid:      Guid,
	kind:      Asset_Kind,
	allocator: mem.Allocator, // 载荷分配器（卸载时释放用）

	has_texture: bool,          // .Texture：texture 有效（已上 GPU）
	texture:     foster.Texture, // .Texture 且 device != nil
	image:       foster.Image,   // .Texture 且 device == nil（保留 CPU 副本）
	json:        json.Value,     // .Json
	bytes:       []u8,           // .Raw
}

// assets_init 的缺省 Library 根（config.library_root 留空时使用）。
DEFAULT_LIBRARY_ROOT :: "Library"

Asset_Manager_Config :: struct {
	// 源根目录。只影响 assets_load_path（去源文件旁读 .meta）；纯 guid 加载不需要。
	assets_root: string,

	// Library 根目录。留空 = DEFAULT_LIBRARY_ROOT；
	// storage 显式指定时本字段不参与后端构造。
	library_root: string,

	// 可选覆盖存储后端（.read != nil 时生效），例如测试/内嵌用 storage_map。
	storage: Asset_Storage,

	// 传入后 .Texture 资产自动建 GPU Texture；nil 则保留 CPU Image。
	device: ^foster.GraphicsDevice,

	// 载荷分配器；留零值 = context.allocator。
	allocator: mem.Allocator,
}

Asset_Manager :: struct {
	records: ha.Pool(Asset_Record, Asset_Handle),
	by_guid: map[Guid]Asset_Handle,

	storage:         Asset_Storage,
	directory_state: Directory_State, // 默认后端的状态
	map_state:       Map_State,

	manifest:        map[string]Guid, // path -> guid（manifest blob 惰性加载）
	manifest_loaded: bool,

	assets_root: string,
	device:      ^foster.GraphicsDevice,
	allocator:   mem.Allocator,
}

assets_init :: proc(m: ^Asset_Manager, config: Asset_Manager_Config) -> Asset_Error {
	m^ = {}
	m.allocator = config.allocator.procedure != nil ? config.allocator : context.allocator
	m.assets_root = config.assets_root // 借用调用方字符串（通常是字面量）
	m.device = config.device

	if config.storage.read != nil {
		m.storage = config.storage
	} else {
		library_root := config.library_root != "" ? config.library_root : DEFAULT_LIBRARY_ROOT
		storage_directory_init(&m.directory_state, library_root)
		m.storage = storage_directory(&m.directory_state)
	}
	return .None
}

// 卸载全部资产并释放管理器。终止态调用，之后 manager 不可再用。
assets_dispose :: proc(m: ^Asset_Manager) {
	for it := ha.begin(&m.records); rec, _ in ha.next(&it) {
		destroy_record(rec)
	}
	ha.delete(&m.records)
	delete(m.by_guid)
	for path in m.manifest { // 键是克隆的 path 字符串，map delete 本身不释放它们
		delete(path, m.allocator)
	}
	delete(m.manifest)
	m^ = {}
}

// 主 API：按 guid 加载（重复加载直接返回缓存句柄）。
assets_load :: proc(m: ^Asset_Manager, guid: Guid) -> (Asset_Handle, Asset_Error) {
	if existing, ok := m.by_guid[guid]; ok {
		return existing, .None
	}

	data, found := m.storage.read(&m.storage, guid, m.allocator)
	if !found do return ASSET_HANDLE_NONE, .File_Not_Found
	defer delete(data, m.allocator)

	header, payload, ok := blob_parse(data)
	if !ok do return ASSET_HANDLE_NONE, .Parse_Error
	if header.guid != cast([16]u8)guid {
		fmt.eprintf("asset: blob guid mismatch (requested %s)\n", guid_to_string(guid, context.temp_allocator))
		return ASSET_HANDLE_NONE, .Parse_Error
	}

	rec := Asset_Record{
		guid      = guid,
		kind      = cast(Asset_Kind)header.kind,
		allocator = m.allocator,
	}

	switch rec.kind {
	case .Texture:
		w, h, _, pixels, ok := blob_texture_parse(payload)
		if !ok do return ASSET_HANDLE_NONE, .Parse_Error

		pixel_buf, aerr := make([dynamic]foster.Color, len(pixels) / 4, m.allocator)
		if aerr != .None do return ASSET_HANDLE_NONE, .Import_Failed
		rec.image = foster.Image{ Width = int(w), Height = int(h), Pixels = pixel_buf }
		mem.copy(raw_data(rec.image.Pixels), raw_data(pixels), len(pixels))

		if m.device != nil {
			tex := foster.TextureFromImage(m.device, &rec.image, "")
			delete(rec.image.Pixels)
			rec.image = {}
			if tex.Resource == nil do return ASSET_HANDLE_NONE, .Import_Failed
			rec.texture = tex
			rec.has_texture = true
		}

	case .Json:
		value, jerr := json.parse(payload, parse_integers = true, allocator = m.allocator)
		if jerr != .None do return ASSET_HANDLE_NONE, .Parse_Error
		rec.json = value

	case .Raw:
		bytes, err := make([]u8, len(payload), m.allocator)
		if err != .None do return ASSET_HANDLE_NONE, .Import_Failed
		copy(bytes, payload)
		rec.bytes = bytes
	}

	handle := ha.add(&m.records, rec)
	m.by_guid[guid] = handle
	return handle, .None
}

// 便捷 API：按源相对路径加载。先查 Library 的 manifest blob（打包形态：
// 只发行 Library/pak 也走这条路），查不到再回退读源文件旁的 .meta（开发期
// 新丢进来还没导入的文件）。两条路收敛到同一 guid——开发期与打包期
// 用的是完全相同的代码。
assets_load_path :: proc(m: ^Asset_Manager, rel_path: string) -> (Asset_Handle, Asset_Error) {
	if !m.manifest_loaded {
		m.manifest_loaded = true
		manifest_load(m)
	}
	if guid, ok := m.manifest[rel_path]; ok {
		return assets_load(m, guid)
	}

	if m.assets_root == "" do return ASSET_HANDLE_NONE, .Not_Supported

	ds: foster.DirectoryStorage
	foster.directory_storage_init(&ds, m.assets_root, false)
	guid, err := meta_read(foster.directory_storage_as_container(&ds), rel_path)
	if err != .None do return ASSET_HANDLE_NONE, err
	return assets_load(m, guid)
}

// 卸载单个资产（GPU 贴图/JSON 树/字节随记录一起释放）。
assets_unload :: proc(m: ^Asset_Manager, handle: Asset_Handle) {
	rec := ha.get(m.records, handle)
	if rec == nil do return
	delete_key(&m.by_guid, rec.guid)
	ha.remove(&m.records, handle, destroy_record)
}

// ---- 类型化获取（kind 不匹配返回零值，便于调用方写防御代码） ----

assets_get_texture :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> ^foster.Texture {
	rec := ha.get(m.records, handle)
	if rec == nil || rec.kind != .Texture || !rec.has_texture do return nil
	return &rec.texture
}

// device == nil 时 Texture 资产保留的 CPU 副本（测试/无 GPU 场景）。
assets_get_image :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> ^foster.Image {
	rec := ha.get(m.records, handle)
	if rec == nil || rec.kind != .Texture || rec.has_texture do return nil
	return &rec.image
}

assets_get_json :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> ^json.Value {
	rec := ha.get(m.records, handle)
	if rec == nil || rec.kind != .Json do return nil
	return &rec.json
}

assets_get_bytes :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> []u8 {
	rec := ha.get(m.records, handle)
	if rec == nil || rec.kind != .Raw do return nil
	return rec.bytes
}

assets_kind :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> (Asset_Kind, bool) {
	rec := ha.get(m.records, handle)
	if rec == nil do return Asset_Kind{}, false
	return rec.kind, true
}

assets_guid :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> Guid {
	rec := ha.get(m.records, handle)
	if rec == nil do return GUID_NONE
	return rec.guid
}

assets_valid :: proc(m: ^Asset_Manager, handle: Asset_Handle) -> bool {
	return ha.valid(m.records, handle)
}

assets_len :: proc(m: ^Asset_Manager) -> int {
	return m.records.num
}

// ---- 内部 ----

@(private)
destroy_record :: proc(rec: ^Asset_Record) {
	switch rec.kind {
	case .Texture:
		if rec.has_texture do foster.TextureDispose(&rec.texture)
		if len(rec.image.Pixels) > 0 do delete(rec.image.Pixels)
	case .Json:
		if rec.json != nil do json.destroy_value(rec.json, rec.allocator)
	case .Raw:
		if rec.bytes != nil do delete(rec.bytes, rec.allocator)
	}
	rec^ = {}
}
