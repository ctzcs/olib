#+build !js

package foster_framework

// ==============================================================================
// Platform / Native — 本机存储、路径与线程
// ==============================================================================

// 本机平台实现：storage 的 OS 层/路径层 + 线程 ID。
// 拆分原因：core:os 与 core:path/filepath 在 js 目标不可用，且 import
// 不能放进 when 块（编译器要求用 #+build 分文件），Web 对应在
// platform_web.odin。

import "core:strings"
import os "core:os"
import filepath "core:path/filepath"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Platform / Native — 本机存储、路径与线程
//   Platform / Storage / Files
//   Platform / Storage / Paths
//   Platform / Thread

// ==============================================================================
// Platform / Storage / Files
// ==============================================================================
// 存储层本机文件后端: 所有 core:os 调用收口在这里(core:os 在 js 目标不可用,
// storage_runtime.odin 通过本层间接使用)。Web 对应实现在 storage_os_web.odin。

storage_os_exists :: proc(path: string) -> bool {
	return os.exists(path)
}

storage_os_is_directory :: proc(path: string) -> bool {
	return os.is_directory(path)
}

storage_os_enumerate :: proc(path: string, allocator := context.allocator) -> []string {
	infos, err := os.read_all_directory_by_path(path, allocator)
	if err != nil {
		return nil
	}
	defer os.file_info_slice_delete(infos, allocator)

	result := make([dynamic]string, 0, len(infos), allocator)
	for info in infos {
		name, clone_err := strings.clone(info.name, allocator)
		if clone_err != nil {
			continue
		}
		append(&result, name)
	}
	return result[:]
}

storage_os_make_directory_all :: proc(path: string) -> bool {
	return os.make_directory_all(path) == nil
}

storage_os_remove :: proc(path: string) -> bool {
	if os.is_directory(path) {
		return os.remove_all(path) == nil
	}
	return os.remove(path) == nil
}

storage_os_read_file :: proc(path: string, allocator := context.allocator) -> []byte {
	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		return nil
	}
	return data
}

storage_os_write_file :: proc(path: string, data: []byte) -> bool {
	return os.write_entire_file(path, data) == nil
}

storage_os_working_directory :: proc(allocator := context.allocator) -> string {
	dir, err := os.get_working_directory(allocator)
	if err != nil {
		return ""
	}
	return dir
}

// ==============================================================================
// Platform / Storage / Paths
// ==============================================================================
// 存储层本机路径后端(core:path/filepath 的 path.odin 无条件依赖 core:os,
// js 目标不可用, 故收口到本层; Web 对应实现在 storage_path_web.odin)。
// 行为与原先直接调用 core:path/filepath 完全一致(平台分隔符语义)。

storage_path_clean :: proc(path: string, allocator := context.temp_allocator) -> string {
	cleaned, _ := filepath.clean(path, allocator)
	return cleaned
}

storage_path_join :: proc(parts: []string, allocator := context.temp_allocator) -> string {
	joined, _ := filepath.join(parts, allocator)
	return joined
}

storage_path_split :: proc(path: string) -> (dir, file: string) {
	return filepath.split(path)
}

// ==============================================================================
// Platform / Thread
// ==============================================================================
// 桌面/本机平台的线程 ID(core:os 在 js 目标不可用, 见 platform_thread_web.odin)

platform_current_thread_id :: proc() -> int {
	return os.get_current_thread_id()
}
