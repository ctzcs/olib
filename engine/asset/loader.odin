// Asset_Storage —— Runtime 的存储后端抽象（以 Guid 为键）。
//
// Runtime 从始至终只以 Guid 请求 blob，不知道也不需要知道
// "31d0a7c9.blob" 这样的文件名；文件名/布局是后端实现细节：
//
//   开发期: guid -> Library/<guid>.blob        (storage_directory)
//   测试/内嵌: guid -> 内存 map                 (storage_map)
//   将来发布: guid -> pak 索引 -> offset/size   (再加一个后端即可)
//
// 注：read/exists 故意不是 contextless——directory 后端内部要走 ofoster 的
// storage 读路径（带隐式 context）；allocator 显式传入这一点保持不变。
// 分区：
//   Directory 后端 —— 开发期默认（Library/ 目录）
//   Map 后端 —— 测试 / 将来 web 目标
package asset

import "core:mem"

import foster "olib:foster"

Asset_Storage :: struct {
	read:     proc (storage: ^Asset_Storage, guid: Guid, allocator: mem.Allocator) -> ([]u8, bool),
	exists:   proc (storage: ^Asset_Storage, guid: Guid) -> bool,
	userdata: rawptr,
}

// =============================================================================
// Directory 后端（开发期默认）
// =============================================================================

Directory_State :: struct {
	container: foster.StorageContainer,
}

storage_directory_init :: proc(state: ^Directory_State, library_root: string) {
	state.container = foster.StorageContainer{ Root = library_root, Writable = false }
}

storage_directory :: proc(state: ^Directory_State) -> Asset_Storage {
	return Asset_Storage{
		read     = directory_read,
		exists   = directory_exists,
		userdata = state,
	}
}

@(private)
directory_read :: proc(storage: ^Asset_Storage, guid: Guid, allocator: mem.Allocator) -> ([]u8, bool) {
	state := (^Directory_State)(storage.userdata)
	buf: [37]u8
	name, ok := guid_filename(guid, buf[:])
	if !ok do return nil, false
	data := foster.storage_read_all_bytes(&state.container, name, allocator)
	if data == nil do return nil, false
	return data, true
}

@(private)
directory_exists :: proc(storage: ^Asset_Storage, guid: Guid) -> bool {
	state := (^Directory_State)(storage.userdata)
	buf: [37]u8
	name, ok := guid_filename(guid, buf[:])
	if !ok do return false
	return foster.storage_file_exists(&state.container, name)
}

// =============================================================================
// Map 后端（测试 / 将来 web 目标把 #load 预烘焙的 blob 塞进来）
// =============================================================================

Map_State :: struct {
	blobs: map[Guid][]u8,
}

storage_map_init :: proc(state: ^Map_State, allocator := context.allocator) {
	state.blobs = make(map[Guid][]u8, allocator)
}

storage_map_dispose :: proc(state: ^Map_State) {
	delete(state.blobs)
	state.blobs = nil
}

storage_map :: proc(state: ^Map_State) -> Asset_Storage {
	return Asset_Storage{
		read     = map_read,
		exists   = map_exists,
		userdata = state,
	}
}

// read 会把字节克隆到传入 allocator——与 directory 后端语义一致，
// 调用方（assets_load）可以统一 delete。
@(private)
map_read :: proc(storage: ^Asset_Storage, guid: Guid, allocator: mem.Allocator) -> ([]u8, bool) {
	state := (^Map_State)(storage.userdata)
	src, ok := state.blobs[guid]
	if !ok do return nil, false
	out, err := make([]u8, len(src), allocator)
	if err != .None do return nil, false
	copy(out, src)
	return out, true
}

@(private)
map_exists :: proc(storage: ^Asset_Storage, guid: Guid) -> bool {
	state := (^Map_State)(storage.userdata)
	_, ok := state.blobs[guid]
	return ok
}
