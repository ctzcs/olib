#+build !js
package storage

import "core:os"
import "core:strings"

// ------------------------------------------------------------------------------
// 资源根 —— 开发期 cwd / 发布版 exe 目录
// ------------------------------------------------------------------------------

// 开发期资源根：当前目录（把工作目录设到项目根，编辑器改的文件立即可见）。
resources_root_dev :: proc(allocator := context.allocator) -> string {
	dir, err := os.get_working_directory(allocator)
	if err != nil do return ""
	return dir
}

// 发布版资源根：exe 所在目录（游戏连同 Resources/ 一起分发时用）；
// 取不到 exe 路径时退回 cwd。
resources_root_release :: proc(allocator := context.allocator) -> string {
	exe, err := os.get_executable_path(allocator)
	if err != nil do return resources_root_dev(allocator)
	defer delete(exe, allocator)

	slash := strings.last_index(exe, "/")
	back := strings.last_index(exe, "\\")
	sep := max(slash, back)
	return sep >= 0 ? strings.clone(exe[:sep], allocator) or_else "" : ""
}

// ------------------------------------------------------------------------------
// 用户根 —— 平台 pref 路径（自动建目录）
// ------------------------------------------------------------------------------

// 计算用户数据根目录并确保存在；失败（无 HOME/APPDATA 等）返回 ""。
// 路径分配于传入 allocator（默认 context），调用方持有。
user_root :: proc(app_name: string, allocator := context.allocator) -> string {
	if !valid_app_name(app_name) do return ""
	when ODIN_OS == .Windows {
		base := os.get_env_alloc("APPDATA", allocator)
		defer delete(base, allocator)
		if base == "" do return ""
		root := path_join(base, app_name, allocator)
		if os.make_directory_all(root) != nil {
			delete(root, allocator)
			return ""
		}
		return root
	} else when ODIN_OS == .Darwin {
		home := os.get_env_alloc("HOME", allocator)
		defer delete(home, allocator)
		if home == "" do return ""
		support := path_join(home, "Library/Application Support", allocator)
		root := path_join(support, app_name, allocator)
		delete(support, allocator)
		if os.make_directory_all(root) != nil {
			delete(root, allocator)
			return ""
		}
		return root
	} else {
		base := os.get_env_alloc("XDG_CONFIG_HOME", allocator)
		defer delete(base, allocator)
		if base == "" {
			home := os.get_env_alloc("HOME", allocator)
			defer delete(home, allocator)
			if home == "" do return ""
			base = path_join(home, ".config", allocator)
		}
		root := path_join(base, app_name, allocator)
		if os.make_directory_all(root) != nil {
			delete(root, allocator)
			return ""
		}
		return root
	}
}
