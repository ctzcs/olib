// manifest —— path → GUID 寻址层（开发期与打包共用同一套加载代码的关键）。
//
// import_all 收尾时，把扫描到的全部（源相对路径, GUID）全量重写进一个
// 保留 GUID 的 Raw blob。assets_load_path 先查它，查不到再回退读源目录
// 旁侧 .meta：
//
//   开发期：两条路都在，新丢进的文件没导入过时自动落到 .meta 回退；
//   打包后：只发行 Library/（将来 pak），manifest 随其他 blob 一起进包，
//           assets_load_path 一行代码都不用改。
//
// 为什么是保留 GUID 的 blob 而不是 Library 根下一个散文件：manifest 和
// 其他派生物走同一条 Asset_Storage(Guid) 通道，pak 后端不需要任何特殊
// 处理。manifest 是纯派生物（从 .meta 推导），不进版本控制、不承担身份。
package asset

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import enc "olib:encoding"
import foster "ofoster:."

MANIFEST_VERSION :: u32(1)

// 保留 GUID（前缀 "manifest"）。128-bit 随机生成撞上它的概率可忽略；
// 它没有 .meta，不会参与 import_all 的 Duplicate_Guid 检查。
GUID_MANIFEST :: Guid{'m', 'a', 'n', 'i', 'f', 'e', 's', 't', 0, 0, 0, 0, 0, 0, 0, 1}

Manifest_Entry :: struct {
	path: string, // 相对 assets_root，'/' 分隔
	guid: string, // 32-hex
}

Asset_Manifest :: struct {
	version: u32,
	entries: [dynamic]Manifest_Entry,
}

// import_all 收尾调用：把 path→guid 表全量写成 manifest blob。
// 按路径排序保证输出稳定，便于人工比对两次导入的 manifest。
manifest_write :: proc(library: ^foster.StorageContainer, guid_by_path: map[string]Guid) -> Asset_Error {
	m := Asset_Manifest{ version = MANIFEST_VERSION }
	defer {
		for &e in m.entries {
			delete(e.path)
			delete(e.guid)
		}
		delete(m.entries)
	}

	for path, guid in guid_by_path {
		e := Manifest_Entry{
			path = strings.clone(path, context.allocator),
			guid = guid_to_string(guid, context.allocator),
		}
		append(&m.entries, e)
	}
	manifest_sort(&m.entries)

	data, merr := json.marshal(m, enc.DEFAULT_MARSHAL_OPT)
	if merr != nil do return .Write_Error
	defer delete(data)

	blob, ok := blob_build(GUID_MANIFEST, .Raw, MANIFEST_VERSION, 0, 0, data, context.allocator)
	if !ok do return .Write_Error
	defer delete(blob)

	name_buf: [37]u8
	name, _ := guid_filename(GUID_MANIFEST, name_buf[:])
	if !foster.storage_write_all_bytes(library, name, blob) {
		fmt.eprintf("asset: 写 manifest 失败\n")
		return .Write_Error
	}
	return .None
}

// 把 manifest blob 解析进管理器的 path→guid 缓存（惰性加载一次）。
// 返回 false = 存储 backend 里没有 manifest 或内容不合法；
// 调用方按"无 manifest"处理，走 .meta 回退。
manifest_load :: proc(m: ^Asset_Manager) -> bool {
	data, found := m.storage.read(&m.storage, GUID_MANIFEST, m.allocator)
	if !found do return false
	defer delete(data, m.allocator)

	header, payload, ok := blob_parse(data)
	if !ok || header.kind != u8(Asset_Kind.Raw) do return false

	mf: Asset_Manifest
	if json.unmarshal(payload, &mf) != nil do return false
	defer {
		for &e in mf.entries {
			delete(e.path)
			delete(e.guid)
		}
		delete(mf.entries)
	}

	for &e in mf.entries {
		guid, gok := guid_from_string(e.guid)
		if !gok do continue
		path, _ := strings.clone(e.path, m.allocator)
		m.manifest[path] = guid
	}
	return true
}

// 插入排序：manifest 条目量级在几十~几千，不值得引 sort.Interface。
@(private)
manifest_sort :: proc(entries: ^[dynamic]Manifest_Entry) {
	for i in 1..<len(entries) {
		e := entries[i]
		j := i
		for j > 0 && entries[j - 1].path > e.path {
			entries[j] = entries[j - 1]
			j -= 1
		}
		entries[j] = e
	}
}
