// 创建独立游戏项目；模板是工具输入，不是 olib 的运行时依赖。
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// 分区：参数与边界 / 模板展开。
main :: proc() {
	if len(os.args) != 3 {
		fmt.eprintln("用法: odin run tools/new-game -- <新目录> <英文项目名>")
		os.exit(2)
	}
	destination, err := filepath.abs(os.args[1], context.temp_allocator)
	name := os.args[2]
	if err != nil || !valid_name(name) {
		fmt.eprintln("项目名仅允许英文字母、数字和下划线，且以字母开头。")
		os.exit(2)
	}
	root, _ := filepath.abs(#directory + "/../..", context.temp_allocator)
	if os.exists(destination) {
		fmt.eprintln("目标已存在，拒绝覆盖:", destination)
		os.exit(1)
	}
	// 模板生成到独立仓库，拒绝在 olib 内创建游戏（含 build 下）。
	relative, rel_err := filepath.rel(root, destination, context.temp_allocator)
	if rel_err == nil && relative != ".." && !strings.has_prefix(relative, "../") &&
	   !strings.has_prefix(relative, "..\\") {
		fmt.eprintln("新游戏必须位于 olib 之外。")
		os.exit(1)
	}
	if os.make_directory_all(destination) != nil ||
	   !expand(#directory + "/template", destination, name, root) {
		fmt.eprintln("创建失败；保留已写文件供检查:", destination)
		os.exit(1)
	}
	fmt.println("已创建:", destination)
	fmt.println("进入目录运行 play.bat；验证运行 odin run tools/check。")
}

valid_name :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 64 do return false
	for c, i in name {
		letter := c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
		if !letter && (i == 0 || !(c >= '0' && c <= '9' || c == '_')) do return false
	}
	upper := strings.to_upper(name, context.temp_allocator)
	for reserved in ([]string{"CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4",
		"COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5",
		"LPT6", "LPT7", "LPT8", "LPT9"}) {
		if upper == reserved do return false
	}
	return true
}

expand :: proc(source, destination, name, library: string) -> bool {
	entries, err := os.read_all_directory_by_path(source, context.temp_allocator)
	if err != nil do return false
	for entry in entries {
		path := fmt.tprintf("%s/%s", destination, strings.trim_suffix(entry.name, ".in"))
		if entry.type == .Directory {
			if os.make_directory(path) != nil || !expand(entry.fullpath, path, name, library) do return false
		} else if entry.type == .Regular {
			bytes, read_err := os.read_entire_file(entry.fullpath, context.temp_allocator)
			if read_err != nil do return false
			if strings.has_suffix(entry.name, ".in") {
				value, _ := strings.replace_all(string(bytes), "__PROJECT__", name, context.temp_allocator)
				// JSON 与 Odin 字符串采用正斜线，Windows 路径同样可用。
				portable, _ := strings.replace_all(library, "\\", "/", context.temp_allocator)
				value, _ = strings.replace_all(value, "__OLIB__", portable, context.temp_allocator)
				bytes = transmute([]u8)value
			}
			if os.write_entire_file(path, bytes) != nil do return false
		} else {
			fmt.eprintln("模板不支持链接或特殊文件:", entry.fullpath)
			return false
		}
	}
	return true
}
