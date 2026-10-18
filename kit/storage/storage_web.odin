#+build js
package storage

import "core:strings"

import foster "olib:foster"

// 浏览器资源根指向 Foster 虚拟 FS；不是网页 URL，不会自动下载服务器文件。
// #load 资源无需读取此根；外部资源须先由应用加载/挂载到虚拟 FS。
resources_root_dev :: proc(allocator := context.allocator) -> string {
	return strings.clone("/", allocator) or_else ""
}

resources_root_release :: proc(allocator := context.allocator) -> string {
	return resources_root_dev(allocator)
}

// 与 Foster OpenUserStorage 使用同一 /foster/<app>/ 命名空间。
// localStorage 按浏览器源隔离；创建失败（例如禁用存储）返回空字符串。
user_root :: proc(app_name: string, allocator := context.allocator) -> string {
	if !valid_app_name(app_name) do return ""
	root := strings.join({"/foster/", app_name, "/"}, "", allocator) or_else ""
	if root == "" do return ""
	container := foster.StorageContainer{Root = root, Writable = true}
	if !foster.CreateDirectory(&container, "") {
		delete(root, allocator)
		return ""
	}
	return root
}
