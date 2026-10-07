// .meta —— 资产身份文件。
//
// 每个源资产旁边一个（Assets/textures/belt.png + belt.png.meta），
// 内容是一行 JSON：{"guid": "31d0a7c9e2f4..."}。
//
// 纪律：
//   - .meta 提交进版本控制（它是身份，不是缓存）；
//   - 移动/重命名源文件时把 .meta 一起带走（身份随文件走，引用不断）；
//   - 绝不手动编辑 guid；复制 .meta 会造成 Duplicate_Guid，import_all 会报错；
//   - 删除资产 = 源文件 + .meta 一起删；孤立的 .meta（源没了）import_all
//     只警告不删除，防止误删身份。
package asset

import "core:strings"

import enc "olib:core/encoding"
import foster "olib:foster"

META_EXT :: ".meta"

// .meta 的 JSON 形态。保持单字段：管线内部信息（新鲜度等）都记在 blob
// header 里，不污染身份文件。
Asset_Meta :: struct {
	guid: string,
}

// 读取源文件旁的 .meta。缺失返回 Meta_Missing；内容不合法返回 Parse_Error。
meta_read :: proc(assets: ^foster.StorageContainer, rel_path: string) -> (Guid, Asset_Error) {
	meta_rel := strings.join({rel_path, META_EXT}, "")
	defer delete(meta_rel)

	if !foster.storage_file_exists(assets, meta_rel) {
		return GUID_NONE, .Meta_Missing
	}

	full := join_owned(assets.Root, meta_rel)
	defer delete(full)

	meta: Asset_Meta
	if enc.json_load_struct(full, &meta) != .None {
		return GUID_NONE, .Parse_Error
	}
	defer delete(meta.guid)

	guid, ok := guid_from_string(meta.guid)
	if !ok {
		return GUID_NONE, .Parse_Error
	}
	return guid, .None
}

// 写出 .meta（pretty JSON，diff 友好）。
meta_write :: proc(assets: ^foster.StorageContainer, rel_path: string, guid: Guid) -> Asset_Error {
	meta := Asset_Meta{ guid = guid_to_string(guid, context.allocator) }
	defer delete(meta.guid)

	meta_rel := strings.join({rel_path, META_EXT}, "")
	defer delete(meta_rel)

	full := join_owned(assets.Root, meta_rel)
	defer delete(full)

	if enc.json_save_struct(full, &meta) != .None {
		return .Write_Error
	}
	return .None
}

// ensure 语义：有 .meta 则读，没有则生成新 GUID 并写盘。
// import_all 对每个源文件调它，所以新资产入伙是全自动的。
meta_ensure :: proc(assets: ^foster.StorageContainer, rel_path: string) -> (Guid, Asset_Error) {
	guid, err := meta_read(assets, rel_path)
	if err == .None {
		return guid, .None
	}
	if err != .Meta_Missing {
		return GUID_NONE, err
	}

	guid = guid_generate()
	if werr := meta_write(assets, rel_path, guid); werr != .None {
		return GUID_NONE, werr
	}
	return guid, .None
}
