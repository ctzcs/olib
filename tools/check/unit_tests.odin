package main

// 集中测试仍与被测包一起编译，可验证私有实现；源码树始终只读。
// 分区：隔离执行 / 源路径保持 / 临时目录清理。
import "core:fmt"
import "core:os"
import tokenizer "core:odin/tokenizer"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

run_unit :: proc(c: ^Checker, p: Package) {
	rel := strings.trim_prefix(p.path, "tests/")
	name := fmt.tprintf("test   %s", rel)
	if !selected(c, name) do return
	workspace, err := os.make_directory_temp("", "olib_unit_", context.allocator)
	if err != nil {
		report(c, name, false, fmt.tprintf("Cannot create test workspace: %v", err))
		return
	}
	defer delete(workspace)
	defer remove_unit_workspace(workspace)
	for directory in ([]string{path_join(c.root, rel), path_join(c.root, p.path)}) {
		entries, read_error := os.read_all_directory_by_path(directory, context.temp_allocator)
		if read_error != nil {
			report(c, name, false, fmt.tprintf("Cannot read %s: %v", directory, read_error))
			return
		}
		for entry in entries {
			if entry.type == .Directory || !strings.has_suffix(entry.name, ".odin") do continue
			destination := path_join(workspace, entry.name)
			if os.exists(destination) {
				report(c, name, false, fmt.tprintf("Duplicate source/test filename: %s", entry.name))
				return
			}
			bytes, source_error := os.read_entire_file(entry.fullpath, context.temp_allocator)
			if source_error != nil {
				report(c, name, false, fmt.tprintf("Cannot read %s: %v", entry.fullpath, source_error))
				return
			}
			content, ok := unit_source_paths(string(bytes), entry.fullpath)
			if !ok || os.write_entire_file(destination, content) != nil {
				report(c, name, false, fmt.tprintf("Cannot prepare test source: %s", entry.fullpath))
				return
			}
		}
	}
	exe_name, _ := strings.replace_all(rel, "/", "_", context.temp_allocator)
	run(c, name, "odin", "test", workspace, fmt.tprintf("-collection:olib=%s", c.root),
		"-vet", fmt.tprintf("-vet-packages:%s", p.name),
		fmt.tprintf("-out:%s/test_%s%s", c.out, exe_name, EXE))
}

// 移到临时目录后，#directory、字面量 #load 和相对 import 仍解析到原文件。
// 用 Odin tokenizer 定位；不改注释、字符串内容或其他代码，也不维护私有 API 导出表。
unit_source_paths :: proc(source, path: string) -> (string, bool) {
	lexer: tokenizer.Tokenizer
	tokenizer.init(&lexer, source, path)
	tokens := make([dynamic]tokenizer.Token, context.temp_allocator)
	for {
		token := tokenizer.scan(&lexer)
		if token.kind == .EOF do break
		if token.kind != .Comment do append(&tokens, token)
	}
	if lexer.error_count > 0 do return "", false
	directory := filepath.dir(path)
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	last := 0
	import_path := false
	for token, i in tokens {
		start, end := token.pos.offset, token.pos.offset+len(token.text)
		replacement := ""
		if token.kind == .Import do import_path = true
		if token.kind == .Semicolon do import_path = false
		if token.kind == .Hash && i+1 < len(tokens) && tokens[i+1].text == "directory" {
			replacement = fmt.tprintf("%q", directory)
			end = tokens[i+1].pos.offset+len(tokens[i+1].text)
		}
		load_path := i >= 3 && tokens[i-3].kind == .Hash &&
			tokens[i-2].text == "load" && tokens[i-1].kind == .Open_Paren
		if token.kind == .String && (import_path || load_path) {
			value, _, ok := strconv.unquote_string(token.text, context.temp_allocator)
			if !ok do return "", false
			if !filepath.is_abs(value) && !strings.contains(value, ":") {
				resolved := path_clean(path_join(directory, value))
				// Windows 盘符不能用于 Odin import；借用检查入口已配置的 collection。
				if import_path {
					root := path_clean(path_join(#directory, "../.."))
					resolved, _ = filepath.rel(root, resolved, context.temp_allocator)
					resolved, _ = strings.replace_all(resolved, "\\", "/", context.temp_allocator)
					resolved = fmt.tprintf("olib:%s", resolved)
				}
				replacement = fmt.tprintf("%q", resolved)
			}
			import_path = false
		}
		if replacement == "" do continue
		strings.write_string(&builder, source[last:start])
		strings.write_string(&builder, replacement)
		last = end
	}
	strings.write_string(&builder, source[last:])
	return strings.to_string(builder), true
}

// 此目录由 make_directory_temp 独占创建，只有本轮写入的平面 .odin 文件。
remove_unit_workspace :: proc(workspace: string) {
	entries, err := os.read_all_directory_by_path(workspace, context.temp_allocator)
	if err == nil {
		for entry in entries do assert(os.remove(entry.fullpath) == nil)
	}
	assert(os.remove(workspace) == nil)
}
