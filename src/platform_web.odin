#+build js wasm32, js wasm64p32

package foster_framework

// ==============================================================================
// Platform / Web — 浏览器存储、路径与线程
// ==============================================================================

// Web(js_wasm32) 平台实现：storage 的 OS 层/路径层 + 线程 ID。
// 本机平台对应 platform_native.odin（拆分原因见该文件头注释）。

import slashpath "core:path/slashpath"
import "core:strings"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Platform / Web — 浏览器存储、路径与线程
//   Platform / Storage / Files
//   Platform / Storage / Paths
//   Platform / Thread

// ==============================================================================
// Platform / Storage / Files
// ==============================================================================
// 存储层 Web 文件后端(M4): 经 foster_web 桥落到 foster.js 的
// localStorage 虚拟文件系统(每个文件一个键, base64 载荷, 二进制安全)。
// 路径为虚拟绝对路径(如 /foster/<app>/settings.txt)。目录标记和文件前缀
// 支持空目录、子项枚举及递归删除；每个文件的 base64 载荷保持二进制安全。

storage_os_exists :: proc(path: string) -> bool {
	if len(path) == 0 {
		return false
	}
	ptr, length := web_string_bytes(path)
	return fw_fs_exists(ptr, length) != 0
}

storage_os_is_directory :: proc(path: string) -> bool {
	ptr, length := web_string_bytes(path)
	return fw_fs_is_directory(ptr, length)
}

storage_os_enumerate :: proc(path: string, allocator := context.allocator) -> []string {
	ptr, length := web_string_bytes(path)
	size := fw_fs_enumerate(ptr, length, nil, 0)
	if size <= 0 {
		return nil
	}
	data := make([]u8, int(size), context.temp_allocator)
	if fw_fs_enumerate(ptr, length, raw_data(data), size) != size {
		return nil
	}
	parts := strings.split(string(data), "\x00", context.temp_allocator)
	result := make([]string, len(parts), allocator)
	for part, i in parts {
		result[i], _ = strings.clone(part, allocator)
	}
	return result
}

storage_os_make_directory_all :: proc(path: string) -> bool {
	ptr, length := web_string_bytes(path)
	return fw_fs_make_directory(ptr, length)
}

storage_os_remove :: proc(path: string) -> bool {
	if len(path) == 0 {
		return false
	}
	ptr, length := web_string_bytes(path)
	return fw_fs_remove(ptr, length) != 0
}

storage_os_read_file :: proc(path: string, allocator := context.allocator) -> []byte {
	if len(path) == 0 {
		return nil
	}
	ptr, length := web_string_bytes(path)
	size := fw_fs_size(ptr, length)
	if size < 0 {
		return nil
	}
	data := make([]byte, size, allocator)
	if size > 0 {
		read := fw_fs_read(ptr, length, &data[0], size)
		if read != size {
			delete(data)
			return nil
		}
	}
	return data
}

storage_os_write_file :: proc(path: string, data: []byte) -> bool {
	if len(path) == 0 {
		return false
	}
	path_ptr, path_len := web_string_bytes(path)
	if len(data) == 0 {
		return fw_fs_write(path_ptr, path_len, nil, 0) != 0
	}
	return fw_fs_write(path_ptr, path_len, &data[0], i32(len(data))) != 0
}

storage_os_working_directory :: proc(allocator := context.allocator) -> string {
	_ = allocator
	return ""
}

// ==============================================================================
// Platform / Storage / Paths
// ==============================================================================
// 存储层 Web 路径后端: 用 core:path/slashpath 的纯斜杠实现。
// Web 侧根路径都是虚拟路径("/foster/<app>/"), 斜杠语义正确。

storage_path_clean :: proc(path: string, allocator := context.temp_allocator) -> string {
	return slashpath.clean(path, allocator)
}

storage_path_join :: proc(parts: []string, allocator := context.temp_allocator) -> string {
	return slashpath.join(parts, allocator)
}

storage_path_split :: proc(path: string) -> (dir, file: string) {
	return slashpath.split(path)
}

// ==============================================================================
// Platform / Thread
// ==============================================================================
// Web 平台的线程 ID: wasm 无并发(Phase 1 无线程), 恒为主线程

platform_current_thread_id :: proc() -> int {
	return 1
}
