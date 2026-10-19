package main

// 分区：目录收集 / AST 标记识别 / 枚举输出。
import "core:fmt"
import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

// ------------------------------------------------------------------------------
// 目录收集
// ------------------------------------------------------------------------------

Catalog :: struct {
	package_name: string,
	names:        [dynamic]string,
	locations:    map[string]tokenizer.Pos,
}

// 所有结果借用本次调用的 context.allocator；调用方使用 arena 统一回收 AST 和源码。
generate :: proc(options: Options) -> (string, string) {
	entries, read_error := os.read_all_directory_by_path(options.source, context.allocator)
	if read_error != nil do return "", fmt.aprintf("无法读取目录 %s: %v", options.source, read_error)
	paths: [dynamic]string
	for entry in entries {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") ||
		   strings.has_suffix(entry.name, "_test.odin") {
			continue
		}
		path, _ := filepath.abs(entry.fullpath)
		if !same_path(path, options.output) do append(&paths, path)
	}
	slice.sort(paths[:])
	catalog: Catalog
	for path in paths {
		source, err := os.read_entire_file(path, context.allocator)
		if err != nil do return "", fmt.aprintf("无法读取 %s: %v", path, err)
		if error := collect_source(&catalog, string(source), path, options); error != "" {
			return "", error
		}
	}
	if len(catalog.names) == 0 do return "", fmt.aprintf("未找到 tag=%q 的声明。", options.tag)
	slice.sort(catalog.names[:])
	return render_enum(catalog, options), ""
}

collect_source :: proc(catalog: ^Catalog, source, path: string, options: Options) -> string {
	file := ast.File{src = source, fullpath = path}
	p := parser.default_parser()
	if !parser.parse_file(&p, &file) || file.syntax_error_count != 0 {
		return fmt.aprintf("Odin 语法解析失败: %s", path)
	}
	for tag in file.tags {
		text := strings.trim_space(tag.text)
		if text == "#+test" || text == "#+ignore" do return ""
	}
	if catalog.package_name == "" {
		catalog.package_name = file.pkg_name
	} else if catalog.package_name != file.pkg_name {
		return fmt.aprintf("包名不一致: %s 中为 %s，预期 %s", path, file.pkg_name, catalog.package_name)
	}
	conditional := conditional_filename(path)
	for tag in file.tags {
		if strings.has_prefix(tag.text, "#+build") do conditional = true
	}
	for declaration in file.decls {
		if error := collect_statement(catalog, declaration, options, conditional); error != "" {
			return error
		}
	}
	return ""
}

// 不模拟目标平台选择；平台后缀文件中的匹配标记也必须明确报错。
conditional_filename :: proc(path: string) -> bool {
	stem := strings.trim_suffix(filepath.base(path), ".odin")
	separator := strings.last_index(stem, "_")
	if separator < 0 do return false
	suffix := stem[separator+1:]
	build_os, _ := parser.get_build_os_from_string(suffix)
	return build_os != .Unknown || parser.get_build_arch_from_string(suffix) != .Unknown
}

// ------------------------------------------------------------------------------
// AST 标记识别
// ------------------------------------------------------------------------------

collect_statement :: proc(
	catalog: ^Catalog,
	statement: ^ast.Stmt,
	options: Options,
	conditional: bool,
) -> string {
	if statement == nil do return ""
	#partial switch node in statement.derived {
	case ^ast.Value_Decl:
		// 不进入函数体或类型字段；枚举仅来源于包级声明。
		for expression in node.names {
			name := expression.derived.(^ast.Ident) or_continue
			if name.name == options.enum_name {
				return at(name.pos, fmt.aprintf("枚举名 %s 与现有声明冲突", name.name))
			}
		}
		matched, error := matches_tag(node.attributes[:], options.tag)
		if error != "" do return error
		if !matched do return ""
		if conditional do return at(node.pos, "标记声明位于条件编译中；请移到无条件声明文件")
		for expression in node.names {
			name, ok := expression.derived.(^ast.Ident)
			if !ok || !valid_identifier(name.name) do return at(expression.pos, "无法作为枚举成员的声明名")
			if previous, exists := catalog.locations[name.name]; exists {
				message := fmt.aprintf("重复成员 %s；首次声明在 %s:%d",
					name.name, previous.file, previous.line)
				return at(name.pos, message)
			}
			catalog.locations[name.name] = name.pos
			append(&catalog.names, name.name)
		}
	case ^ast.When_Stmt:
		if error := collect_statement(catalog, node.body, options, true); error != "" do return error
		return collect_statement(catalog, node.else_stmt, options, true)
	case ^ast.Block_Stmt:
		for child in node.stmts {
			if error := collect_statement(catalog, child, options, conditional); error != "" do return error
		}
	case ^ast.Foreign_Block_Decl:
		return collect_statement(catalog, node.body, options, true)
	case:
		return ""
	}
	return ""
}

matches_tag :: proc(attributes: []^ast.Attribute, wanted: string) -> (bool, string) {
	matched := false
	for attribute in attributes {
		for element in attribute.elems {
			field := element.derived.(^ast.Field_Value) or_continue
			name := field.field.derived.(^ast.Ident) or_continue
			if name.name != "tag" do continue
			literal, ok := field.value.derived.(^ast.Basic_Lit)
			if !ok || literal.tok.kind != .String {
				return false, at(field.pos, "auto_gen 要求 tag 使用字符串字面量")
			}
			value, _, decoded := strconv.unquote_string(literal.tok.text)
			if !decoded do return false, at(field.pos, "无法解码 tag 字符串")
			if value == wanted do matched = true
		}
	}
	return matched, ""
}

valid_identifier :: proc(name: string) -> bool {
	if name == "" || name == "_" do return false
	lexer: tokenizer.Tokenizer
	tokenizer.init(&lexer, name, "<identifier>", nil)
	token := tokenizer.scan(&lexer)
	return token.kind == .Ident && token.text == name &&
	       tokenizer.scan(&lexer).kind == .EOF && lexer.error_count == 0
}

at :: proc(pos: tokenizer.Pos, message: string) -> string {
	return fmt.aprintf("%s:%d:%d: %s", pos.file, pos.line, pos.column, message)
}

// ------------------------------------------------------------------------------
// 枚举输出
// ------------------------------------------------------------------------------

render_enum :: proc(catalog: Catalog, options: Options) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.allocator)
	strings.write_string(&builder, GENERATED_HEADER)
	fmt.sbprintf(&builder, "// tag = %q; members sorted by declaration name.\n", options.tag)
	fmt.sbprintf(&builder, "package %s\n\n%s :: enum {{\n", catalog.package_name, options.enum_name)
	for name in catalog.names {
		fmt.sbprintf(&builder, "\t%s,\n", name)
	}
	strings.write_string(&builder, "}\n")
	return strings.to_string(builder)
}
