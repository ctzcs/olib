// Importer —— 源文件到 Library blob 的导入层（编辑器/工具侧）。
//
//   import_all("Assets", "Library")
//     1. 递归扫描 Assets/（.meta 不算源文件）
//     2. 每个源文件 meta_ensure：缺 .meta 就生成 GUID 写盘（新资产全自动入伙）
//     3. GUID 查重：两个 .meta 持同一 GUID -> Duplicate_Guid 报错（绝不静默换）
//     4. 新鲜度：blob 存在 且 源 mtime/size 相同 且 importer 版本相同 -> 跳过
//     5. 过期/缺失 -> 按扩展名分派 Importer 产出 payload -> 写 Library/<guid>.blob
//     6. 孤儿 .meta（源文件没了）打警告，不删除
//
// Library 是纯派生缓存：删除整个 Library 再 import_all 即完整恢复。
// 本文件只在 native 目标可用（枚举/mtime 依赖 core:os）。
// 分区：
//   导入器 —— Importer 注册表与内建分派
//   import_all —— 扫描/发 GUID/查重/新鲜度/导入/manifest 重写
//   内部 —— 路径与 IO 辅助
package asset

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import foster "olib:foster"

// =============================================================================
// 导入器
// =============================================================================

// Importer 的产出。data 所有权归导入器（分配于传入 allocator），
// import_all 打包进 blob 后立即释放；调用方无需长期持有。
Payload_Builder :: struct {
	width:  u32, // 仅 .Texture
	height: u32, // 仅 .Texture
	format: u32, // 仅 .Texture（TEXTURE_FORMAT_*）
	data:   []u8, // .Texture: 纯像素；.Json/.Raw: payload 全量字节
}

// 自定义导入器签名。source 是源文件字节，ext 是小写含点扩展名（".aseprite"），
// 仅在导入调用期间有效。非 contextless：内建贴图导入要走 ofoster 的解码路径。
Import_Proc :: #type proc (
	source:    []u8,
	ext:       string,
	out:       ^Payload_Builder,
	allocator: mem.Allocator,
) -> Asset_Error

Importer :: struct {
	kind:    Asset_Kind, // 产出 blob 的 kind
	version: u32,        // 导入逻辑版本：改了导入算法就 +1，旧缓存自动过期
	run:     Import_Proc,
}

// 内建导入器的当前版本。
BUILTIN_VERSION_TEXTURE :: u32(1)
BUILTIN_VERSION_JSON    :: u32(1)
BUILTIN_VERSION_RAW     :: u32(1)

@(private)
custom_importers: map[string]Importer

// 注册/覆盖某扩展名的导入器（key 小写含点，如 ".aseprite"；也可传 "aseprite"）。
// 优先级高于内建分派；版本号升级会令旧 blob 过期重导。
importer_register :: proc(ext: string, imp: Importer) {
	key := ext
	owned: string
	if !strings.contains(key, ".") {
		owned, _ = strings.join({".", key}, "", context.allocator)
		key = owned
	}
	key_lower, _ := strings.to_lower(key, context.allocator)
	custom_importers[key_lower] = imp // key 随注册表存活，不释放
	delete(owned)
}

// 按扩展名选导入器：自定义注册优先，其次内建（贴图格式 -> Texture，
// .json -> Json，其余 -> Raw 直通）。
importer_for_ext :: proc(ext: string) -> Importer {
	if imp, ok := custom_importers[ext]; ok {
		return imp
	}
	switch ext {
	case ".png", ".jpg", ".jpeg", ".qoi", ".bmp", ".tga":
		return Importer{ kind = .Texture, version = BUILTIN_VERSION_TEXTURE, run = import_texture }
	case ".json":
		return Importer{ kind = .Json, version = BUILTIN_VERSION_JSON, run = import_passthrough }
	case:
		return Importer{ kind = .Raw, version = BUILTIN_VERSION_RAW, run = import_passthrough }
	}
}

// 内建贴图导入：png/jpg/qoi/bmp/tga -> 解码为 RGBA8 像素。
// 解码中间量走 context，产出像素克隆到传入 allocator。
@(private)
import_texture :: proc(source: []u8, ext: string, out: ^Payload_Builder, allocator: mem.Allocator) -> Asset_Error {
	image := foster.ImageFromEncoded(source)
	if image.Width <= 0 || image.Height <= 0 {
		return .Import_Failed
	}
	defer delete(image.Pixels)

	data, err := make([]u8, len(image.Pixels) * 4, allocator)
	if err != .None {
		return .Import_Failed
	}
	// 注意：transmute 切片在此版本保留元素个数而非字节数，必须按 rawptr+字节数拷贝
	mem.copy(raw_data(data), raw_data(image.Pixels), len(data))

	out.width  = u32(image.Width)
	out.height = u32(image.Height)
	out.format = TEXTURE_FORMAT_RGBA8
	out.data   = data
	return .None
}

// 内建直通导入：Json / Raw 的 payload 就是源字节本身。
@(private)
import_passthrough :: proc(source: []u8, ext: string, out: ^Payload_Builder, allocator: mem.Allocator) -> Asset_Error {
	data, err := make([]u8, len(source), allocator)
	if err != .None {
		return .Import_Failed
	}
	copy(data, source)
	out.data = data
	return .None
}

// =============================================================================
// import_all
// =============================================================================

Import_Stats :: struct {
	scanned:        int, // 源文件数（不含 .meta）
	imported:       int,
	skipped:        int,
	guid_generated: int, // 本次新发 GUID 的资产数
	orphaned_meta:  int, // 孤儿 .meta 数（只警告）
}

import_all :: proc(assets_root: string, library_root: string) -> (Import_Stats, Asset_Error) {
	stats: Import_Stats

	assets_ds: foster.DirectoryStorage
	foster.directory_storage_init(&assets_ds, assets_root, true)
	assets := foster.directory_storage_as_container(&assets_ds)

	library_ds: foster.DirectoryStorage
	foster.directory_storage_init(&library_ds, library_root, true)
	library := foster.directory_storage_as_container(&library_ds)
	_ = foster.storage_create_directory(library, "")

	// 收集源文件与 .meta 的相对路径（context 分配，末尾统一释放）
	sources: [dynamic]string
	metas: [dynamic]string
	defer {
		for rel in sources do delete(rel)
		for rel in metas do delete(rel)
		delete(sources)
		delete(metas)
	}
	collect_sources(assets, "", &sources, &metas)
	stats.scanned = len(sources)

	// ---- 第一遍：身份。发 GUID + 查重 ----
	guid_by_path := make(map[string]Guid)
	path_by_guid := make(map[Guid]string)
	defer {
		delete(guid_by_path)
		delete(path_by_guid)
	}

	for rel in sources {
		meta_rel := strings.join({rel, META_EXT}, "")
		had_meta := foster.storage_file_exists(assets, meta_rel)
		delete(meta_rel)

		guid, err := meta_ensure(assets, rel)
		if err != .None do return stats, err
		if !had_meta do stats.guid_generated += 1

		if other, ok := path_by_guid[guid]; ok {
			guid_hex := guid_to_string(guid, context.temp_allocator)
			fmt.eprintf(
				"asset: duplicate guid %s\n  %s\n  %s\n  (复制了 .meta？删掉其中一个 .meta 重新生成)\n",
				guid_hex, other, rel,
			)
			return stats, .Duplicate_Guid
		}
		path_by_guid[guid] = rel // 借用 sources 持有的字符串
		guid_by_path[rel] = guid
	}

	// ---- 第二遍：新鲜度 + 导入 ----
	for rel in sources {
		guid := guid_by_path[rel]
		ext := path_ext_lower(rel)
		imp := importer_for_ext(ext)

		full_src := join_owned(assets.Root, rel)
		fi, serr := os.stat(full_src, context.temp_allocator)
		delete(full_src)
		if serr != nil do return stats, .File_Not_Found
		mtime := time.time_to_unix_nano(fi.modification_time)
		size := fi.size

		if hdr, ok := read_blob_header(library, guid); ok {
			if hdr.kind == u8(imp.kind) &&
			   hdr.importer_version == imp.version &&
			   hdr.src_mtime == mtime &&
			   hdr.src_size == size {
				stats.skipped += 1
				continue
			}
		}

		source := foster.storage_read_all_bytes(assets, rel)
		if source == nil {
			fmt.eprintf("asset: 读不到源文件 %s\n", rel)
			return stats, .File_Not_Found
		}

		builder: Payload_Builder
		ierr := imp.run(source, ext, &builder, context.allocator)
		delete(source)
		if ierr != .None {
			fmt.eprintf("asset: 导入失败 %s (%s)\n", rel, ext)
			if builder.data != nil do delete(builder.data)
			return stats, .Import_Failed
		}

		payload := builder.data
		if imp.kind == .Texture {
			// Texture 的 payload = 迷你头 + 像素（新分配），打包后统一 delete(payload)
			p, pok := blob_payload_texture(&builder, context.allocator)
			delete(builder.data)
			if !pok do return stats, .Write_Error
			payload = p
		}

		blob, bok := blob_build(guid, imp.kind, imp.version, mtime, size, payload, context.allocator)
		delete(payload)
		if !bok do return stats, .Write_Error

		name_buf: [37]u8
		name, _ := guid_filename(guid, name_buf[:])
		written := foster.storage_write_all_bytes(library, name, blob)
		delete(blob)
		if !written {
			fmt.eprintf("asset: 写 blob 失败 %s\n", rel)
			return stats, .Write_Error
		}
		stats.imported += 1
	}

	// ---- 孤儿 .meta：只警告不删（防止误删身份） ----
	for meta_rel in metas {
		src_rel := meta_refers_to(meta_rel)
		if _, ok := guid_by_path[src_rel]; !ok {
			stats.orphaned_meta += 1
			fmt.eprintf("asset: 孤儿 .meta（源文件不存在，保留不删）: %s\n", meta_rel)
		}
	}

	// ---- manifest：path→guid 全量重写（打包后 assets_load_path 零改动） ----
	if werr := manifest_write(library, guid_by_path); werr != .None {
		return stats, werr
	}

	return stats, .None
}

// =============================================================================
// 内部
// =============================================================================

// 拼接 root/rel，结果总是新分配（context），可安全 delete。
// 不直接用 foster.storage_join_path：filepath.Clean 可能返回输入的子切片，
// 对借用内存 delete 会导致 bad free。
@(private)
join_owned :: proc(root, rel: string) -> string {
	if root == "" {
		return strings.clone(rel, context.allocator)
	}
	return strings.join({root, rel}, "/", context.allocator)
}

// 递归收集。sources/metas 里的字符串由本 proc 用 context 分配，调用方负责释放。
@(private)
collect_sources :: proc(
	assets:  ^foster.StorageContainer,
	rel_dir: string,
	sources: ^[dynamic]string,
	metas:   ^[dynamic]string,
) {
	names := foster.storage_enumerate_directory(assets, rel_dir, context.allocator)
	for name in names {
		rel := name
		if rel_dir != "" {
			rel = strings.join({rel_dir, "/", name}, "")
		} else {
			cloned, cerr := strings.clone(name, context.allocator)
			if cerr == .None do rel = cloned
		}
		if foster.storage_directory_exists(assets, rel) {
			collect_sources(assets, rel, sources, metas)
			delete(rel)
		} else if has_meta_ext(rel) {
			append(metas, rel)
		} else {
			append(sources, rel)
		}
		delete(name)
	}
	delete(names)
}

// "x.png.meta" -> "x.png"（视图切片，借用入参）。
@(private)
meta_refers_to :: proc(meta_rel: string) -> string {
	if len(meta_rel) > len(META_EXT) {
		return meta_rel[: len(meta_rel) - len(META_EXT)]
	}
	return meta_rel
}

@(private)
has_meta_ext :: proc(path: string) -> bool {
	return len(path) > len(META_EXT) && path[len(path) - len(META_EXT):] == META_EXT
}

// 小写含点扩展名（temp 分配，仅当场使用）；无扩展名返回 ""。
@(private)
path_ext_lower :: proc(path: string) -> string {
	dot := strings.last_index(path, ".")
	if dot < 0 do return ""
	slash := strings.last_index(path, "/")
	if slash > dot do return "" // 点在目录名里，不是扩展名
	ext, _ := strings.to_lower(path[dot:], context.temp_allocator)
	return ext
}

// 只读 blob 头（新鲜度检查用，避免为比对而整读大 blob）。
@(private)
read_blob_header :: proc(library: ^foster.StorageContainer, guid: Guid) -> (Blob_Header, bool) {
	buf: [37]u8
	name, ok := guid_filename(guid, buf[:])
	if !ok do return {}, false
	full := join_owned(library.Root, name)
	defer delete(full)

	f, err := os.open(full)
	if err != nil do return {}, false
	defer os.close(f)

	raw: [size_of(Blob_Header)]u8
	n, rerr := os.read(f, raw[:])
	if rerr != nil || n != len(raw) do return {}, false
	h := (^Blob_Header)(&raw[0])
	if h.magic != BLOB_MAGIC do return {}, false
	return h^, true
}
