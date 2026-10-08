package foster_framework

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:bytes"
import "core:io"
import "core:hash"
import zlib "core:compress/zlib"
import "core:strings"
import SDL "vendor:sdl3"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Storage / FileSystem / Dialogs — 文件对话框类型
//   Storage / StorageContainer — 公共容器与后端类型
//   Storage / FileSystem / Dialogs — SDL 对话框实现
//   Storage / DirectoryStorage — 目录后端
//   Storage / RelativeStorage — 相对路径视图
//   Storage / ContentStorage — 只读内容
//   Storage / ZipStorage — ZIP 索引、解码与查询
//   Storage / FileSystem — 用户存储、标题存储与对话框
//   Storage / StorageContainer / Streams — 读取流

// core:os 与 core:path/filepath 分别经 storage_os_* 与 storage_path_* 平台层使用
// (两者在 js 目标不可用)

// ==============================================================================
// Storage / FileSystem / Dialogs — 文件对话框类型
// ==============================================================================

DialogResult :: struct {
	Files:     []string,
	Cancelled: bool,
}

DialogCallback :: #type proc(result: DialogResult)
DialogCallbackSingleFile :: #type proc(file: string)

DialogFilter :: struct {
	Name:    string,
	Pattern: string,
}

// ==============================================================================
// Storage / StorageContainer — 公共容器与后端类型
// ==============================================================================

StorageContainer :: struct {
	Root:       string,
	Writable:   bool,
	ZipEntries: ^map[string][dynamic]u8,
}

Storage :: StorageContainer

// Concrete storage implementations mirror Foster's storage backends while
// keeping the small StorageContainer value type usable by existing code.

DirectoryStorage :: struct {
	Container: StorageContainer,
}

RelativeStorage :: struct {
	Container: StorageContainer,
	Prefix:    string,
	// [olib L-001] 返回的容器借用此路径，直到路径改变或 RelativeStorageDispose。
	owned_root:     string,
	root_allocator: runtime.Allocator,
}

ContentStorage :: struct {
	Container: StorageContainer,
}

ZipStorageError :: enum {
	None,
	InvalidArchive,
	UnsupportedArchive,
	ChecksumMismatch,
}

ZipStorage :: struct {
	Error:     ZipStorageError,
	Container: StorageContainer,
	Entries:   map[string][dynamic]u8,
}

FileSystem :: struct {
	App: ^App,
}

// ------------------------------------------------------------------------------
// Storage / StorageContainer / Operations — 路径与读写操作
// ------------------------------------------------------------------------------

storage_join_path :: proc(container: ^StorageContainer, path: string) -> string {
	if container.Root == "" {
		return storage_path_clean(path)
	}
	if strings.trim_space(path) == "" {
		return container.Root
	}
	joined := storage_path_join({container.Root, path})
	return storage_path_clean(joined)
}

storage_exists :: proc(container: ^StorageContainer, path: string) -> bool {
	if container.ZipEntries != nil {
		return storage_file_exists(container, path) || storage_directory_exists(container, path)
	}
	return storage_os_exists(storage_join_path(container, path))
}

storage_file_exists :: proc(container: ^StorageContainer, path: string) -> bool {
	if container.ZipEntries != nil {
		_, ok := container.ZipEntries^[storage_zip_path(container, path)]
		return ok
	}
	full := storage_join_path(container, path)
	return storage_os_exists(full) && !storage_os_is_directory(full)
}

storage_directory_exists :: proc(container: ^StorageContainer, path: string) -> bool {
	if container.ZipEntries != nil {
		name := storage_zip_path(container, path)
		if name == "" {
			return container.ZipEntries^ != nil
		}
		prefix := strings.concatenate({name, "/"}, context.temp_allocator)
		for entry in container.ZipEntries^ {
			if strings.starts_with(entry, prefix) {
				return true
			}
		}
		return false
	}
	return storage_os_is_directory(storage_join_path(container, path))
}

storage_enumerate_immediate :: proc(
	container: ^StorageContainer,
	path: string,
	allocator := context.allocator,
) -> []string {
	if container.ZipEntries != nil {
		name := storage_zip_path(container, path)
		prefix := name
		if name != "" {
			prefix = strings.concatenate({name, "/"}, context.temp_allocator)
		}
		names := make(map[string]bool, context.temp_allocator)
		for entry in container.ZipEntries^ {
			if !strings.starts_with(entry, prefix) || entry == prefix {
				continue
			}
			relative := entry[len(prefix):]
			parts := strings.split(relative, "/", context.temp_allocator)
			if len(parts) > 0 && len(parts[0]) > 0 {
				names[parts[0]] = true
			}
		}
		result := make([]string, len(names), allocator)
		i := 0
		for entry_name in names {
			result[i], _ = strings.clone(entry_name, allocator)
			i += 1
		}
		return result
	}
	return storage_os_enumerate(storage_join_path(container, path), allocator)
}

storage_match_pattern :: proc(name, pattern: string) -> bool {
	if pattern == "" || pattern == "*" {
		return true
	}
	i, j, star, retry := 0, 0, -1, 0
	for i < len(name) {
		if j < len(pattern) && (pattern[j] == '?' || pattern[j] == name[i]) {
			i += 1
			j += 1
		} else if j < len(pattern) && pattern[j] == '*' {
			star = j
			j += 1
			retry = i
		} else if star >= 0 {
			retry += 1
			i = retry
			j = star + 1
		} else {
			return false
		}
	}
	for j < len(pattern) && pattern[j] == '*' {
		j += 1
	}
	return j == len(pattern)
}

storage_enumerate_directory :: proc(
	container: ^StorageContainer,
	path: string = "",
	allocator := context.allocator,
	search_pattern: string = "",
	recursive: bool = false,
) -> []string {
	if search_pattern == "" && !recursive {
		return storage_enumerate_immediate(container, path, allocator)
	}
	result := make([dynamic]string, allocator = allocator)
	storage_enumerate_filtered(container, path, "", search_pattern, recursive, &result)
	return result[:]
}

storage_enumerate_filtered :: proc(
	container: ^StorageContainer,
	path, prefix, pattern: string,
	recursive: bool,
	result: ^[dynamic]string,
) {
	names := storage_enumerate_immediate(container, path)
	defer delete(names)
	for name in names {
		relative :=
			prefix == "" ? name : strings.concatenate({prefix, "/", name}, context.temp_allocator)
		if storage_match_pattern(name, pattern) {
			owned, _ := strings.clone(relative, result.allocator)
			append(result, owned)
		}
		if recursive {
			child := strings.concatenate({path, "/", name}, context.temp_allocator)
			if path == "" {
				child = name
			}
			if storage_directory_exists(container, child) {
				storage_enumerate_filtered(container, child, relative, pattern, true, result)
			}
		}
		delete(name)
	}
}

storage_create_directory :: proc(container: ^StorageContainer, path: string) -> bool {
	if !container.Writable {
		return false
	}
	return storage_os_make_directory_all(storage_join_path(container, path))
}

storage_remove :: proc(container: ^StorageContainer, path: string) -> bool {
	if !container.Writable {
		return false
	}
	return storage_os_remove(storage_join_path(container, path))
}

storage_read_all_bytes :: proc(
	container: ^StorageContainer,
	path: string,
	allocator := context.allocator,
) -> []byte {
	if container.ZipEntries != nil {
		data, ok := container.ZipEntries^[storage_zip_path(container, path)]
		if !ok {
			return nil
		}
		result := make([]u8, len(data), allocator)
		copy(result, data[:])
		return result
	}
	return storage_os_read_file(storage_join_path(container, path), allocator)
}

storage_read_all_text :: proc(
	container: ^StorageContainer,
	path: string,
	allocator := context.allocator,
) -> string {
	data := storage_read_all_bytes(container, path, allocator)
	if len(data) == 0 {
		return ""
	}
	return string(data)
}

storage_write_all_bytes :: proc(container: ^StorageContainer, path: string, data: []byte) -> bool {
	if !container.Writable {
		return false
	}
	full := storage_join_path(container, path)
	parent, _ := storage_path_split(full)
	if parent != "" {
		_ = storage_os_make_directory_all(parent)
	}
	return storage_os_write_file(full, data)
}

storage_write_all_text :: proc(container: ^StorageContainer, path, data: string) -> bool {
	return storage_write_all_bytes(container, path, transmute([]byte)data)
}

storage_dispose :: proc(container: ^StorageContainer) {
	if container == nil || container.ZipEntries == nil {
		return
	}
	for name, data in container.ZipEntries^ {
		delete(name)
		delete(data)
	}
	delete(container.ZipEntries^)
	container.ZipEntries^ = nil
}

storage_zip_path :: proc(container: ^StorageContainer, path: string) -> string {
	name := storage_join_path(container, path)
	name, _ = strings.replace_all(name, "\\", "/", context.temp_allocator)
	if name == "." {
		return ""
	}
	return strings.trim(name, "/")
}

// ==============================================================================
// Storage / FileSystem / Dialogs — SDL 对话框实现
// ==============================================================================

DialogRequestKind :: enum {
	OpenFiles,
	OpenFolder,
	SaveFile,
}

DialogRequest :: struct {
	Kind:           DialogRequestKind,
	FilesCallback:  DialogCallback,
	SingleCallback: DialogCallbackSingleFile,
	Filters:        [dynamic]SDL.DialogFileFilter,
	Allocator:      runtime.Allocator,
}

storage_dialog_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {
	context = runtime.default_context()
	request := cast(^DialogRequest)userdata
	if request == nil {
		return
	}
	context.allocator = request.Allocator
	files: [dynamic]string
	if filelist != nil {
		for i := 0; filelist[i] != nil; i += 1 {
			append(&files, string(filelist[i]))
		}
	}
	cancelled := len(files) == 0
	if request.Kind == .OpenFiles {
		if request.FilesCallback != nil {
			request.FilesCallback(DialogResult{Files = files[:], Cancelled = cancelled})
		}
	} else {
		if request.SingleCallback != nil {
			path := ""
			if len(files) > 0 {
				path = files[0]
			}
			request.SingleCallback(path)
		}
	}
	delete(files)
	storage_dialog_dispose(request)
	_ = filter
}

storage_dialog_dispose :: proc(request: ^DialogRequest) {
	for filter in request.Filters {
		delete(filter.name, request.Allocator)
		delete(filter.pattern, request.Allocator)
	}
	delete(request.Filters)
	free(request, request.Allocator)
}

storage_dialog_filters :: proc(filters: []DialogFilter) -> [dynamic]SDL.DialogFileFilter {
	result: [dynamic]SDL.DialogFileFilter
	for filter in filters {
		name, _ := strings.clone_to_cstring(filter.Name)
		pattern, _ := strings.clone_to_cstring(filter.Pattern)
		append(&result, SDL.DialogFileFilter{name, pattern})
	}
	return result
}

storage_dialog_properties :: proc(
	fs: ^FileSystem,
	title: string,
	filters: []DialogFilter,
	many: bool,
	request: ^DialogRequest,
) -> SDL.PropertiesID {
	props := SDL.CreateProperties()
	if props == 0 {
		return 0
	}
	_ = SDL.SetStringProperty(
		props,
		to_cstring(SDL.PROP_FILE_DIALOG_TITLE_STRING),
		to_cstring(title),
	)
	if fs != nil && fs.App != nil && fs.App.Window.Handle != nil {
		_ = SDL.SetPointerProperty(
			props,
			to_cstring(SDL.PROP_FILE_DIALOG_WINDOW_POINTER),
			fs.App.Window.Handle,
		)
	}
	if len(filters) > 0 {
		request.Filters = storage_dialog_filters(filters)
		converted := request.Filters
		_ = SDL.SetPointerProperty(
			props,
			to_cstring(SDL.PROP_FILE_DIALOG_FILTERS_POINTER),
			raw_data(converted),
		)
		_ = SDL.SetNumberProperty(
			props,
			to_cstring(SDL.PROP_FILE_DIALOG_NFILTERS_NUMBER),
			i64(len(converted)),
		)
	}
	_ = SDL.SetBooleanProperty(props, to_cstring(SDL.PROP_FILE_DIALOG_MANY_BOOLEAN), many)
	return props
}

// ==============================================================================
// Storage / DirectoryStorage — 目录后端
// ==============================================================================

directory_storage_init :: proc(storage: ^DirectoryStorage, root: string, writable := true) {
	storage.Container = StorageContainer {
		Root     = root,
		Writable = writable,
	}
}

directory_storage_as_container :: proc(storage: ^DirectoryStorage) -> ^StorageContainer {
	if storage == nil {
		return nil
	}
	return &storage.Container
}

// ==============================================================================
// Storage / RelativeStorage — 相对路径视图
// ==============================================================================

relative_storage_init :: proc(storage: ^RelativeStorage, base: StorageContainer, prefix: string) {
	storage.Container = base
	storage.Prefix = prefix
}

relative_storage_as_container :: proc(storage: ^RelativeStorage) -> StorageContainer {
	if storage == nil {
		return {}
	}
	root := storage_join_path(&storage.Container, storage.Prefix)
	// [olib L-001] 拼接路径必须跨帧有效；临时路径只用于比较与克隆。
	if storage.owned_root != root {
		owned, _ := strings.clone(root)
		delete(storage.owned_root, storage.root_allocator)
		storage.owned_root = owned
		storage.root_allocator = context.allocator
	}
	result := storage.Container
	result.Root = storage.owned_root
	return result
}

// [olib L-001] 释放 RelativeStorage 持有的拼接路径；不释放借用的 base/prefix。
relative_storage_dispose :: proc(storage: ^RelativeStorage) {
	if storage == nil {
		return
	}
	delete(storage.owned_root, storage.root_allocator)
	storage^ = {}
}

// ==============================================================================
// Storage / ContentStorage — 只读内容
// ==============================================================================

content_storage_init :: proc(storage: ^ContentStorage, root: string, writable := false) {
	storage.Container = StorageContainer {
		Root     = root,
		Writable = writable,
	}
}

content_storage_as_container :: proc(storage: ^ContentStorage) -> ^StorageContainer {
	if storage == nil {
		return nil
	}
	return &storage.Container
}

// ==============================================================================
// Storage / ZipStorage — ZIP 索引、解码与查询
// ==============================================================================

zip_storage_init :: proc(storage: ^ZipStorage, root: string) {
	data := storage_os_read_file(root, context.temp_allocator)
	zip_storage_init_bytes(storage, data)
}

// 输入数据在解码时复制；调用方可以在初始化完成后释放原始 ZIP 数据。
// 出错时释放所有已解码条目，通过 Error 区分损坏或不支持的归档。

zip_storage_init_bytes :: proc(storage: ^ZipStorage, data: []u8) {
	zip_storage_dispose(storage)
	storage.Container = StorageContainer {
		Writable   = false,
		ZipEntries = &storage.Entries,
	}
	storage.Entries = make(map[string][dynamic]u8)
	storage.Error = zip_storage_decode(data, &storage.Entries)
	if storage.Error != .None {
		storage_dispose(&storage.Container)
	}
}

zip_storage_decode :: proc(data: []u8, entries: ^map[string][dynamic]u8) -> ZipStorageError {
	read16 := proc(data: []u8, at: int) -> u16 {
		return u16(data[at]) | u16(data[at + 1]) << 8
	}
	read32 := proc(data: []u8, at: int) -> u32 {
		return(
			u32(data[at]) |
			u32(data[at + 1]) << 8 |
			u32(data[at + 2]) << 16 |
			u32(data[at + 3]) << 24 \
		)
	}
	read64 := proc(data: []u8, at: int) -> u64 {
		value: u64
		for i in 0 ..< 8 {
			value |= u64(data[at + i]) << uint(8 * i)
		}
		return value
	}
	// 检查注释长度，避免把注释中的签名误当成目录结束记录。
	eocd := -1
	for i := len(data) - 22; i >= 0 && i >= len(data) - 65557; i -= 1 {
		if read32(data, i) == 0x06054b50 && i + 22 + int(read16(data, i + 20)) == len(data) {
			eocd = i
			break
		}
	}
	if eocd < 0 {
		return .InvalidArchive
	}
	if read16(data, eocd + 4) != 0 || read16(data, eocd + 6) != 0 {
		return .UnsupportedArchive
	}
	count := u64(read16(data, eocd + 10))
	central_size := u64(read32(data, eocd + 12))
	central_start := u64(read32(data, eocd + 16))
	central_limit := eocd
	if count == 0xffff || central_size == 0xffffffff || central_start == 0xffffffff {
		locator := eocd - 20
		if locator < 0 || read32(data, locator) != 0x07064b50 {
			return .InvalidArchive
		}
		if read32(data, locator + 4) != 0 || read32(data, locator + 16) != 1 {
			return .UnsupportedArchive
		}
		record64 := read64(data, locator + 8)
		if record64 > u64(locator) || u64(locator) - record64 < 56 {
			return .InvalidArchive
		}
		record := int(record64)
		if read32(data, record) != 0x06064b50 {
			return .InvalidArchive
		}
		record_size := read64(data, record + 4)
		if record_size < 44 || record_size > u64(locator - record - 12) {
			return .InvalidArchive
		}
		if read32(data, record + 16) != 0 ||
		   read32(data, record + 20) != 0 ||
		   read64(data, record + 24) != read64(data, record + 32) {
			return .UnsupportedArchive
		}
		count = read64(data, record + 32)
		central_size = read64(data, record + 40)
		central_start = read64(data, record + 48)
		central_limit = record
	} else if read16(data, eocd + 8) != u16(count) {
		return .UnsupportedArchive
	}
	if central_start > u64(central_limit) ||
	   central_size > u64(central_limit) - central_start ||
	   count > central_size / 46 {
		return .InvalidArchive
	}
	central := int(central_start)
	central_end := central + int(central_size)
	// [olib L-002] 条目计数循环不使用索引，避免 unused vet 报错。
	for _ in 0 ..< count {
		if central_end - central < 46 || read32(data, central) != 0x02014b50 {
			return .InvalidArchive
		}
		method := read16(data, central + 10)
		flags := read16(data, central + 8)
		checksum := read32(data, central + 16)
		compressed_size := u64(read32(data, central + 20))
		uncompressed_size := u64(read32(data, central + 24))
		name_size := int(read16(data, central + 28))
		extra_size := int(read16(data, central + 30))
		comment_size := int(read16(data, central + 32))
		disk := u32(read16(data, central + 34))
		local_offset := u64(read32(data, central + 42))
		record_size := 46 + name_size + extra_size + comment_size
		if record_size > central_end - central {
			return .InvalidArchive
		}
		name := string(data[central + 46:central + 46 + name_size])
		needs64 :=
			compressed_size == 0xffffffff ||
			uncompressed_size == 0xffffffff ||
			local_offset == 0xffffffff ||
			disk == 0xffff
		if needs64 {
			extra := central + 46 + name_size
			extra_end := extra + extra_size
			found := false
			for extra_end - extra >= 4 {
				kind := read16(data, extra)
				size := int(read16(data, extra + 2))
				extra += 4
				if size > extra_end - extra {
					return .InvalidArchive
				}
				if kind == 1 {
					end := extra + size
					fields := [3]^u64{&uncompressed_size, &compressed_size, &local_offset}
					for field in fields {
						if field^ == 0xffffffff {
							if end - extra < 8 {
								return .InvalidArchive
							}
							field^ = read64(data, extra)
							extra += 8
						}
					}
					if disk == 0xffff {
						if end - extra < 4 {
							return .InvalidArchive
						}
						disk = read32(data, extra)
					}
					found = true
					break
				}
				extra += size
			}
			if !found {
				return .InvalidArchive
			}
		}
		if disk != 0 || flags & 0x41 != 0 || (method != 0 && method != 8) {
			return .UnsupportedArchive
		}
		if local_offset > u64(central_start) || central_start - local_offset < 30 {
			return .InvalidArchive
		}
		local := int(local_offset)
		if read32(data, local) != 0x04034b50 ||
		   read16(data, local + 8) != method ||
		   read16(data, local + 6) != flags {
			return .InvalidArchive
		}
		local_name_size := int(read16(data, local + 26))
		local_extra_size := int(read16(data, local + 28))
		header_size := 30 + local_name_size + local_extra_size
		if u64(header_size) > central_start - local_offset {
			return .InvalidArchive
		}
		if name != string(data[local + 30:local + 30 + local_name_size]) {
			return .InvalidArchive
		}
		content_start := local + header_size
		if compressed_size > central_start - u64(content_start) ||
		   uncompressed_size > u64(~uint(0) >> 1) {
			return .InvalidArchive
		}
		decoded: [dynamic]u8
		compressed := data[content_start:content_start + int(compressed_size)]
		switch method {
		case 0:
			append(&decoded, ..compressed)
		case 8:
			buffer: bytes.Buffer
			err := zlib.inflate_from_byte_array_raw(compressed, &buffer)
			if err == nil {
				append(&decoded, ..bytes.buffer_to_bytes(&buffer))
			}
			bytes.buffer_destroy(&buffer)
			if err != nil {
				delete(decoded)
				return .InvalidArchive
			}
		}
		if u64(len(decoded)) != uncompressed_size {
			delete(decoded)
			return .InvalidArchive
		}
		if hash.crc32(decoded[:]) != checksum {
			delete(decoded)
			return .ChecksumMismatch
		}
		name, _ = strings.replace_all(name, "\\", "/", context.temp_allocator)
		// 重名条目以后出现的版本为准，释放先前拥有的数据和名称。
		if old, ok := entries^[name]; ok {
			for key in entries^ {
				if key == name {
					delete_key(entries, key)
					delete(key)
					break
				}
			}
			delete(old)
		}
		owned_name, _ := strings.clone(name)
		entries^[owned_name] = decoded
		central += record_size
	}
	return .None
}

zip_storage_init_container :: proc(storage: ^ZipStorage, source: ^StorageContainer, path: string) {
	data := storage_read_all_bytes(source, path)
	defer delete(data)
	zip_storage_init_bytes(storage, data)
}

zip_storage_as_container :: proc(storage: ^ZipStorage) -> ^StorageContainer {
	if storage == nil {
		return nil
	}
	storage.Container.ZipEntries = &storage.Entries
	return &storage.Container
}

zip_storage_exists :: proc(storage: ^ZipStorage, path: string) -> bool {
	if storage == nil || storage.Entries == nil {
		return false
	}
	return storage_exists(zip_storage_as_container(storage), path)
}

zip_storage_read_all_bytes :: proc(
	storage: ^ZipStorage,
	path: string,
	allocator := context.allocator,
) -> []byte {
	if storage == nil || storage.Entries == nil {
		return nil
	}
	return storage_read_all_bytes(zip_storage_as_container(storage), path, allocator)
}

zip_storage_enumerate_directory :: proc(
	storage: ^ZipStorage,
	path: string,
	allocator := context.allocator,
) -> []string {
	return storage_enumerate_directory(zip_storage_as_container(storage), path, allocator)
}

zip_storage_dispose :: proc(storage: ^ZipStorage) {
	if storage == nil {
		return
	}
	storage.Container.ZipEntries = &storage.Entries
	storage_dispose(&storage.Container)
}

// ==============================================================================
// Storage / FileSystem — 用户存储、标题存储与对话框
// ==============================================================================

file_system_init :: proc(fs: ^FileSystem, app: ^App) {
	fs.App = app
}

// 等待浏览器所选文件的异步写入；普通存储同步成功即可回调。
// 等待之前的写入任务，报告最近一次完整快照写入的结果；原生端可立即回调。
StorageFileCallback :: #type proc(succeeded: bool)

FlushStorageFileAsync :: proc(
	container: ^StorageContainer,
	path: string,
	callback: StorageFileCallback,
) {
	if callback == nil {
		return
	}
	when ODIN_OS == .JS {
		full_path := storage_join_path(container, path)
		web_storage_flush(full_path, callback)
	} else {
		callback(storage_file_exists(container, path))
	}
}

file_system_open_user_storage :: proc(fs: ^FileSystem) -> StorageContainer {
	root := ""
	if fs.App != nil {
		root = fs.App.UserPath
	}
	when ODIN_OS != .JS {
		if root == "" {
			pref_path := SDL.GetPrefPath("", to_cstring(fs.App.Name))
			if pref_path != nil {
				root = string(cstring(pref_path))
			}
		}
		if root != "" {
			_ = storage_os_make_directory_all(root)
		}
	}
	// web: UserPath 恒为虚拟前缀(/foster/<app>/), 由 storage_os_web 落到 localStorage
	return StorageContainer{Root = root, Writable = true}
}

file_system_open_title_storage :: proc(fs: ^FileSystem) -> StorageContainer {
	when ODIN_OS == .JS {
		// web: 无基路径概念(资产内嵌 wasm 或走虚拟 FS), 标题存储指向虚拟 FS 根
		_ = fs
		return StorageContainer{Root = "", Writable = false}
	}
	base_path := SDL.GetBasePath()
	root := ""
	if base_path != nil {
		root = string(base_path)
	}
	// [olib L-001] SDL.GetBasePath 失败时保留空 Root，即相对当前工作目录（与 web 一致）。
	return StorageContainer{Root = root, Writable = false}
}

file_system_open_user_storage_async :: proc(
	fs: ^FileSystem,
	callback: proc(storage: StorageContainer),
) {
	if callback != nil {
		callback(file_system_open_user_storage(fs))
	}
}

file_system_open_title_storage_async :: proc(
	fs: ^FileSystem,
	callback: proc(storage: StorageContainer),
) {
	if callback != nil {
		callback(file_system_open_title_storage(fs))
	}
}

file_system_open_file_dialog :: proc(
	fs: ^FileSystem,
	title: string,
	filters: []DialogFilter,
	callback: DialogCallback,
) {
	if callback == nil {
		return
	}
	request := new(DialogRequest)
	request.Allocator = context.allocator
	request.Kind = .OpenFiles
	request.FilesCallback = callback
	when ODIN_OS == .JS {
		web_dialog_start(request, filters)
		return
	}
	props := storage_dialog_properties(fs, title, filters, true, request)
	if props != 0 {
		SDL.ShowFileDialogWithProperties(
			.OPENFILE,
			storage_dialog_callback,
			rawptr(request),
			props,
		)
		SDL.DestroyProperties(props)
	} else {
		storage_dialog_dispose(request)
		callback(DialogResult{Cancelled = true})
	}
}

file_system_open_folder_dialog :: proc(
	fs: ^FileSystem,
	title: string,
	callback: DialogCallbackSingleFile,
) {
	if callback == nil {
		return
	}
	request := new(DialogRequest)
	request.Allocator = context.allocator
	request.Kind = .OpenFolder
	request.SingleCallback = callback
	when ODIN_OS == .JS {
		web_dialog_start(request, nil)
		return
	}
	props := storage_dialog_properties(fs, title, nil, false, request)
	if props != 0 {
		SDL.ShowFileDialogWithProperties(
			.OPENFOLDER,
			storage_dialog_callback,
			rawptr(request),
			props,
		)
		SDL.DestroyProperties(props)
	} else {
		storage_dialog_dispose(request)
		callback("")
	}
}

file_system_save_file_dialog :: proc(
	fs: ^FileSystem,
	title: string,
	filters: []DialogFilter,
	callback: DialogCallbackSingleFile,
) {
	if callback == nil {
		return
	}
	request := new(DialogRequest)
	request.Allocator = context.allocator
	request.Kind = .SaveFile
	request.SingleCallback = callback
	when ODIN_OS == .JS {
		web_dialog_start(request, filters)
		return
	}
	props := storage_dialog_properties(fs, title, filters, false, request)
	if props != 0 {
		SDL.ShowFileDialogWithProperties(
			.SAVEFILE,
			storage_dialog_callback,
			rawptr(request),
			props,
		)
		SDL.DestroyProperties(props)
	} else {
		storage_dialog_dispose(request)
		callback("")
	}
}

open_user_storage :: file_system_open_user_storage
open_title_storage :: file_system_open_title_storage
open_user_storage_async :: file_system_open_user_storage_async
open_title_storage_async :: file_system_open_title_storage_async
open_file_dialog :: file_system_open_file_dialog
open_folder_dialog :: file_system_open_folder_dialog
save_file_dialog :: file_system_save_file_dialog

FileSystemInit :: file_system_init
OpenUserStorage :: file_system_open_user_storage
OpenTitleStorage :: file_system_open_title_storage
OpenUserStorageAsync :: file_system_open_user_storage_async
OpenTitleStorageAsync :: file_system_open_title_storage_async
OpenFileDialog :: file_system_open_file_dialog
OpenFolderDialog :: file_system_open_folder_dialog
SaveFileDialog :: file_system_save_file_dialog

// ------------------------------------------------------------------------------
// Storage / Public API — 公共过程别名
// ------------------------------------------------------------------------------

Exists :: storage_exists
FileExists :: storage_file_exists
DirectoryExists :: storage_directory_exists
EnumerateDirectory :: storage_enumerate_directory
CreateDirectory :: storage_create_directory
Remove :: storage_remove
ReadAllBytes :: storage_read_all_bytes
ReadAllText :: storage_read_all_text
WriteAllBytes :: storage_write_all_bytes
WriteAllText :: storage_write_all_text
DisposeStorage :: storage_dispose

DirectoryStorageInit :: directory_storage_init
DirectoryStorageContainer :: directory_storage_as_container
RelativeStorageInit :: relative_storage_init
// [olib L-001] RelativeStorage 持有的拼接路径释放入口。
RelativeStorageDispose :: relative_storage_dispose
RelativeStorageContainer :: relative_storage_as_container
ContentStorageInit :: content_storage_init
ContentStorageContainer :: content_storage_as_container
ZipStorageInit :: zip_storage_init
ZipStorageInitBytes :: zip_storage_init_bytes
ZipStorageInitContainer :: zip_storage_init_container
ZipStorageContainer :: zip_storage_as_container
ZipStorageExists :: zip_storage_exists
ZipStorageReadAllBytes :: zip_storage_read_all_bytes
ZipStorageEnumerateDirectory :: zip_storage_enumerate_directory
ZipStorageDispose :: zip_storage_dispose

StorageDebugString :: proc(container: ^StorageContainer) -> string {
	return fmt.aprintf(
		"StorageContainer{root=%q, writable=%v}",
		container.Root,
		container.Writable,
	)
}

// ==============================================================================
// Storage / StorageContainer / Streams — 读取流
// ==============================================================================

StorageReadStream :: struct {
	Data:      []u8,
	Offset:    i64,
	Closed:    bool,
	Allocator: runtime.Allocator,
}

storage_read_stream_proc :: proc(
	data: rawptr,
	mode: io.Stream_Mode,
	destination: []u8,
	offset: i64,
	whence: io.Seek_From,
) -> (
	i64,
	io.Error,
) {
	state := cast(^StorageReadStream)data
	if mode == .Destroy {
		delete(state.Data, state.Allocator)
		free(state, state.Allocator)
		return 0, .None
	}
	if mode == .Query {
		return io.query_utility({.Read, .Read_At, .Seek, .Size, .Close, .Destroy, .Query})
	}
	if mode == .Close {
		state.Closed = true
		return 0, .None
	}
	if state.Closed {
		return 0, .Closed
	}
	#partial switch mode {
	case .Size:
		return i64(len(state.Data)), .None
	case .Seek:
		position := offset
		switch whence {
		case .Start:
		case .Current:
			position += state.Offset
		case .End:
			position += i64(len(state.Data))
		}
		if position < 0 {
			return 0, .Invalid_Offset
		}
		state.Offset = position
		return position, .None
	case .Read, .Read_At:
		position := mode == .Read ? state.Offset : offset
		if position < 0 {
			return 0, .Invalid_Offset
		}
		if len(destination) == 0 {
			return 0, .None
		}
		if position >= i64(len(state.Data)) {
			return 0, .EOF
		}
		n := copy(destination, state.Data[int(position):])
		if mode == .Read {
			state.Offset += i64(n)
		}
		if mode == .Read_At && n < len(destination) {
			return i64(n), .EOF
		}
		return i64(n), .None
	}
	return 0, .Unsupported
}

storage_open_read :: proc(
	container: ^StorageContainer,
	path: string,
	allocator := context.allocator,
) -> (
	io.Stream,
	io.Error,
) {
	if container == nil || !storage_file_exists(container, path) {
		return {}, .Unknown
	}
	data := storage_read_all_bytes(container, path, allocator)
	if data == nil && container.ZipEntries == nil {
		// An empty file can also produce a nil slice. Existence was checked above.
		if !storage_file_exists(container, path) {
			return {}, .Unknown
		}
	}
	state := new(StorageReadStream, allocator)
	state^ = StorageReadStream {
		Data      = data,
		Allocator = allocator,
	}
	return io.Stream{procedure = storage_read_stream_proc, data = state}, .None
}
OpenRead :: storage_open_read

// ------------------------------------------------------------------------------
// Storage / StorageContainer / Streams — 可写创建流
// ------------------------------------------------------------------------------

StorageWriteStream :: struct {
	Path:          string,
	Data:          [dynamic]u8,
	Offset:        i64,
	Closed, Dirty: bool,
	Allocator:     runtime.Allocator,
}

storage_write_stream_flush :: proc(state: ^StorageWriteStream) -> io.Error {
	if !state.Dirty {
		return .None
	}
	if !storage_os_write_file(state.Path, state.Data[:]) {
		return .Unknown
	}
	state.Dirty = false
	return .None
}

storage_write_stream_proc :: proc(
	data: rawptr,
	mode: io.Stream_Mode,
	bytes: []u8,
	offset: i64,
	whence: io.Seek_From,
) -> (
	i64,
	io.Error,
) {
	state := cast(^StorageWriteStream)data
	if mode == .Query {
		return io.query_utility(
			{.Write, .Write_At, .Read, .Read_At, .Seek, .Size, .Flush, .Close, .Destroy, .Query},
		)
	}
	if mode == .Destroy {
		err := state.Closed ? io.Error.None : storage_write_stream_flush(state)
		delete(state.Data)
		delete(state.Path, state.Allocator)
		free(state, state.Allocator)
		return 0, err
	}
	if state.Closed {
		return 0, .Closed
	}
	#partial switch mode {
	case .Flush:
		return 0, storage_write_stream_flush(state)
	case .Close:
		err := storage_write_stream_flush(state)
		if err == .None {
			state.Closed = true
		}
		return 0, err
	case .Size:
		return i64(len(state.Data)), .None
	case .Seek:
		position := offset
		switch whence {
		case .Start:
		case .Current:
			position += state.Offset
		case .End:
			position += i64(len(state.Data))
		}
		if position < 0 {
			return 0, .Invalid_Offset
		}
		state.Offset = position
		return position, .None
	case .Write, .Write_At:
		position := mode == .Write ? state.Offset : offset
		if position < 0 || position > i64(max(int)) - i64(len(bytes)) {
			return 0, .Invalid_Offset
		}
		if len(bytes) == 0 {
			return 0, .None
		}
		end := int(position) + len(bytes)
		if end > len(state.Data) {
			resize(&state.Data, end)
		}
		copy(state.Data[int(position):end], bytes)
		state.Dirty = true
		if mode == .Write {
			state.Offset = i64(end)
		}
		return i64(len(bytes)), .None
	case .Read, .Read_At:
		position := mode == .Read ? state.Offset : offset
		if position < 0 {
			return 0, .Invalid_Offset
		}
		if len(bytes) == 0 {
			return 0, .None
		}
		if position >= i64(len(state.Data)) {
			return 0, .EOF
		}
		n := copy(bytes, state.Data[int(position):])
		if mode == .Read {
			state.Offset += i64(n)
		}
		if mode == .Read_At && n < len(bytes) {
			return i64(n), .EOF
		}
		return i64(n), .None
	}
	return 0, .Unsupported
}

// Create truncates immediately; Flush/Close/Destroy persist the buffered data.

storage_create :: proc(
	container: ^StorageContainer,
	path: string,
	allocator := context.allocator,
) -> (
	io.Stream,
	io.Error,
) {
	if container == nil || !container.Writable || container.ZipEntries != nil {
		return {}, .Permission_Denied
	}
	if !storage_write_all_bytes(container, path, nil) {
		return {}, .Unknown
	}
	state := new(StorageWriteStream, allocator)
	state.Path, _ = strings.clone(storage_join_path(container, path), allocator)
	state.Data = make([dynamic]u8, allocator = allocator)
	state.Allocator = allocator
	return io.Stream{procedure = storage_write_stream_proc, data = state}, .None
}
Create :: storage_create
