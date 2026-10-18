// storage —— 游戏资源与用户数据的跨平台路径策略。
//
// 桌面使用系统用户目录；Web 使用 Foster 虚拟文件系统，由浏览器 localStorage 持久化。
// 本包只选择根与应用命名空间，读写直接使用 Foster 的存储类型和操作，不封装运行时。
// 路径返回值归指定 allocator 所有；存储容器借用根字符串，容器结束使用后才可释放。
//
// 分区：便捷用户存储 / 应用命名空间 / 路径拼接；平台路径在 storage_native/web.odin。
package storage

import "core:mem"
import "core:strings"

import foster "olib:foster"

// ------------------------------------------------------------------------------
// 便捷读写
// ------------------------------------------------------------------------------

// 打开用户存储执行 use 后立即释放（桌面和 Web 均同步调用；true 表示打开成功，读写结果由 use 检查）。
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
	foster.DirectoryStorageInit(&ds, root, true)
	use(&ds, userdata)
	return true
}

// 用户数据内某文件的路径（temp 分配）；Web 为虚拟路径，不能传给系统文件 API。
// 根不可用时返回空字符串，不回退到当前工作目录。
user_file_path :: proc(app_name: string, rel_path: string) -> string {
	root := user_root(app_name, context.temp_allocator)
	if root == "" do return ""
	return path_join(root, rel_path, context.temp_allocator)
}

// ------------------------------------------------------------------------------
// 内部 —— 路径拼接（'/' 分隔，总是新分配）
// ------------------------------------------------------------------------------

@(private)
path_join :: proc(a, b: string, allocator: mem.Allocator) -> string {
	return strings.join({a, b}, "/", allocator) or_else ""
}

// app_name 是稳定的命名空间，不是路径，也不取自可变窗口标题。
@(private)
valid_app_name :: proc(app_name: string) -> bool {
	if app_name == "" || app_name == "." || app_name == ".." do return false
	for c in app_name {
		if c < 32 || c == '/' || c == '\\' || c == ':' do return false
	}
	return true
}
