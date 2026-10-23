#+build windows
package hotreload

import "base:runtime"
import "core:strings"
import win "core:sys/windows"

// Windows 扫描平台层：FindFirstFileW 随目录项返回大小和修改时间，不逐个打开文件；
// core:os 的目录遍历会为每一项打开句柄，打开时又不带 FILE_SHARE_DELETE。

// 列出目录项（不含 . 和 ..），名字分配在 allocator 上；目录不存在或读取中断时返回 false。
@(private)
scan_list :: proc(dir: string, entries: ^[dynamic]Scan_Entry, allocator: runtime.Allocator) -> bool {
	pattern := win.utf8_to_wstring_alloc(strings.concatenate({dir, `\*`}, allocator), allocator)
	data: win.WIN32_FIND_DATAW
	handle := win.FindFirstFileW(pattern, &data)
	if handle == win.INVALID_HANDLE_VALUE do return false
	defer win.FindClose(handle)
	for {
		name, err := win.wstring_to_utf8_alloc(cstring16(raw_data(data.cFileName[:])), -1, allocator)
		if err != nil do return false
		// 转换失败（非法 UTF-16 名字）时得到空串，跳过。
		if name != "" && name != "." && name != ".." {
			append(entries, scan_entry(name, data.dwFileAttributes, data.ftLastWriteTime,
				data.nFileSizeHigh, data.nFileSizeLow))
		}
		if !win.FindNextFileW(handle, &data) do break
	}
	return win.GetLastError() == win.ERROR_NO_MORE_FILES
}

// 查询单个路径的元数据；GetFileAttributesExW 返回链接自身的属性，不跟随符号链接。
@(private)
scan_stat :: proc(path: string) -> (entry: Scan_Entry, ok: bool) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	data: win.WIN32_FILE_ATTRIBUTE_DATA
	wide := win.utf8_to_wstring_alloc(path, context.temp_allocator)
	if !win.GetFileAttributesExW(wide, win.GetFileExInfoStandard, &data) do return {}, false
	entry = scan_entry("", data.dwFileAttributes, data.ftLastWriteTime, data.nFileSizeHigh,
		data.nFileSizeLow)
	return entry, true
}

// 分块读取并计算内容哈希（长度参与）。共享读写、删除和改名，扫描不会让编辑器保存或原子替换失败。
@(private)
scan_hash_file :: proc(path: string) -> (hash: u64, ok: bool) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	wide := win.utf8_to_wstring_alloc(path, context.temp_allocator)
	share := win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE
	handle := win.CreateFileW(wide, win.GENERIC_READ, share, nil, win.OPEN_EXISTING,
		win.FILE_FLAG_SEQUENTIAL_SCAN, nil)
	if handle == win.INVALID_HANDLE_VALUE do return 0, false
	defer win.CloseHandle(handle)
	buffer: [32 * 1024]u8
	hash = FNV_OFFSET
	total: u64
	for {
		read: win.DWORD
		if !win.ReadFile(handle, &buffer[0], win.DWORD(len(buffer)), &read, nil) do return 0, false
		if read == 0 do break
		hash = fnv_bytes(hash, buffer[:read])
		total += u64(read)
	}
	return (hash ~ total) * FNV_PRIME, true
}

@(private = "file")
scan_entry :: proc(name: string, attributes: win.DWORD, modified: win.FILETIME,
	high, low: win.DWORD) -> Scan_Entry {
	kind := Scan_Kind.File
	if attributes & win.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		kind = .Other
	} else if attributes & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		kind = .Directory
	}
	return {
		name = name,
		kind = kind,
		size = i64(high) << 32 | i64(low),
		modified = win.FILETIME_as_unix_nanoseconds(modified),
	}
}
