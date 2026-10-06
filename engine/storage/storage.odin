// storage —— 游戏资源与用户数据的平台路径策略（对位 DragonLib GameStorage）。
//
// 职责：决定"资源在哪、用户数据（设置/存档/截图）在哪"，读写本身交给
// ofoster 的 DirectoryStorage。独立于 App（可在创建游戏之前用），
// 路径算法与 SDL GetPrefPath 一致（env 直算，不依赖 SDL 初始化）：
//
//   Windows: %APPDATA%\<app>
//   Linux:   $XDG_CONFIG_HOME\<app>（缺省 ~/.config/<app>）
//   macOS:   ~/Library/Application Support/<app>
//
// 路径分隔符统一用 '/'（Windows API 同样接受）。
//
// 分区：
//   资源根 —— 开发期 cwd / 发布版 exe 目录
//   用户根 —— 平台 pref 路径（自动建目录）
//   便捷读写 —— with_user_storage / user_file_path
package storage

import "core:mem"
import "core:os"
import "core:strings"

import foster "ofoster:."

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
	when ODIN_OS == .Windows {
		base := os.get_env_alloc("APPDATA", allocator)
		defer delete(base, allocator)
		if base == "" do return ""
		root := path_join(base, app_name, allocator)
		os.make_directory_all(root)
		return root
	} else when ODIN_OS == .Darwin {
		home := os.get_env_alloc("HOME", allocator)
		defer delete(home, allocator)
		if home == "" do return ""
		support := path_join(home, "Library/Application Support", allocator)
		root := path_join(support, app_name, allocator)
		delete(support, allocator)
		os.make_directory_all(root)
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
		os.make_directory_all(root)
		return root
	}
}

// ------------------------------------------------------------------------------
// 便捷读写
// ------------------------------------------------------------------------------

// 打开用户存储执行 use 后立即释放（桌面同步完成返回 true）。
// use 内部完成全部读写；不要把 storage 带出回调。
with_user_storage :: proc(
	app_name: string,
	use:      proc(storage: ^foster.DirectoryStorage, userdata: rawptr),
	userdata: rawptr = nil,
) -> bool {
	root := user_root(app_name)
	if root == "" do return false
	defer delete(root)

	ds: foster.DirectoryStorage
	foster.directory_storage_init(&ds, root, true)
	use(&ds, userdata)
	return true
}

// 用户数据内某文件的完整显示路径（temp 分配；资源管理器可直接打开）。
user_file_path :: proc(app_name: string, rel_path: string) -> string {
	root := user_root(app_name, context.temp_allocator)
	if root == "" do return rel_path
	return path_join(root, rel_path, context.temp_allocator)
}

// ------------------------------------------------------------------------------
// 内部 —— 路径拼接（'/' 分隔，总是新分配）
// ------------------------------------------------------------------------------

@(private)
path_join :: proc(a, b: string, allocator: mem.Allocator) -> string {
	return strings.join({a, b}, "/", allocator) or_else ""
}
