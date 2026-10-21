package lang

// 两条来自 shadercross 的 D3D12 规则：D3D12 按“实际用到的”属性重新编号语义，Vulkan 不会，二者不一致时
// 创建管线失败或画错，而且只在 D3D12 上出现、很难从现象找到原因。解析时按文本检查，给出指向源码行的错误：
//   1. 顶点入口的输入结构体以引擎接口开头：Sprite 为 OlibSpriteInput，instanced Model 为 OlibInstanceInput；
//   2. 顶点输出里除 SV_ 语义外的成员，都要在片元入口里用到。
// 只认 vertex_main / fragment_main 和 HLSLINCLUDE、HLSLPROGRAM 里的 struct；结构体定义在 #include 的文件里、
// 或片元把整个输入传给别的函数时无法判断，不报错。
import "core:fmt"
import "core:strings"

import sh ".."

@(private)
hlsl_rules_check :: proc(p: ^Parser, pass: sh.Pass_Desc, instanced: bool, shared, code: Code) {
	if p.error != "" do return
	blocks := [2]Code{hlsl_strip_comments(shared), hlsl_strip_comments(code)}
	vertex, vertex_ok := hlsl_entry(blocks[:], "vertex_main")
	if !vertex_ok do return

	// 规则 1：输入以引擎接口开头。
	head := ""
	switch {
	case pass.draw == .Sprite: head = "OlibSpriteInput"
	case pass.draw == .Model && instanced: head = "OlibInstanceInput"
	}
	if head != "" && len(vertex.params) > 0 && vertex.params[0].type != head {
		if input, ok := hlsl_struct(blocks[:], vertex.params[0].type); ok {
			first, has_first := hlsl_first_attribute(input.members)
			if !has_first || first.type != head {
				line := has_first ? first.line : input.line
				hlsl_fail(p, line, fmt.tprintf("Pass %q: %s must start with %s (D3D12 renumbers vertex attributes " +
					"by use, so the engine attributes have to come first)", string(pass.id), input.name, head))
				return
			}
		}
	}

	// 规则 2：传给片元的成员都要用到。
	output, output_ok := hlsl_struct(blocks[:], vertex.return_type)
	fragment, fragment_ok := hlsl_entry(blocks[:], "fragment_main")
	if !output_ok || !fragment_ok do return
	name := ""
	for param in fragment.params {
		if param.type == output.name do name = param.name
	}
	if name == "" || hlsl_used_whole(fragment.body, name) do return
	for member in output.members {
		if strings.has_prefix(strings.to_upper(member.semantic, context.temp_allocator), "SV_") do continue
		if !hlsl_contains_access(fragment.body, name, member.name) {
			hlsl_fail(p, member.line, fmt.tprintf("Pass %q: %s.%s is passed to fragment_main but never used there " +
				"(D3D12 drops unused inputs and the stages no longer match); use it or remove it",
				string(pass.id), output.name, member.name))
			return
		}
	}
}

// ------------------------------------------------------------------------------
// 文本解析：只认这两条规则需要的形状
// ------------------------------------------------------------------------------

@(private)
Hlsl_Param :: struct {
	type, name: string,
}

@(private)
Hlsl_Entry :: struct {
	return_type: string,
	params: []Hlsl_Param,
	body: string,
}

@(private)
Hlsl_Member :: struct {
	type, name, semantic: string,
	line: int, // 源文件行号
}

@(private)
Hlsl_Struct :: struct {
	name: string,
	members: []Hlsl_Member,
	line: int,
}

@(private)
hlsl_fail :: proc(p: ^Parser, line: int, message: string) {
	if p.error == "" do p.error = fmt.aprintf("%s:%d:1: %s", p.path, line, message)
}

// 注释换成空格（保留换行），之后的查找不会命中注释里的文字，行号不变。
@(private)
hlsl_strip_comments :: proc(code: Code) -> Code {
	out := transmute([]u8)strings.clone(code.text, context.temp_allocator)
	i := 0
	for i < len(out) {
		switch {
		case out[i] == '"':
			i += 1
			for i < len(out) && out[i] != '"' && out[i] != '\n' do i += 1
			i += 1
		case i+1 < len(out) && out[i] == '/' && out[i+1] == '/':
			for i < len(out) && out[i] != '\n' {
				out[i] = ' '
				i += 1
			}
		case i+1 < len(out) && out[i] == '/' && out[i+1] == '*':
			for i < len(out) && !(i+1 < len(out) && out[i] == '*' && out[i+1] == '/') {
				if out[i] != '\n' do out[i] = ' '
				i += 1
			}
			for _ in 0..<2 do if i < len(out) {
				out[i] = ' '
				i += 1
			}
		case:
			i += 1
		}
	}
	return {string(out), code.line}
}

@(private)
hlsl_is_word :: proc(c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// text 里独立单词 word 的位置（前后不是标识符字符），从 from 开始找。
@(private)
hlsl_find_word :: proc(text, word: string, from := 0) -> int {
	start := from
	for start <= len(text) {
		i := strings.index(text[start:], word)
		if i < 0 do return -1
		at := start + i
		end := at + len(word)
		if (at == 0 || !hlsl_is_word(text[at-1])) && (end >= len(text) || !hlsl_is_word(text[end])) do return at
		start = at + 1
	}
	return -1
}

// 从 open（'{' 或 '('）开始找配对的闭括号；找不到返回 -1。
@(private)
hlsl_match :: proc(text: string, open: int) -> int {
	opening, closing := text[open], text[open] == '{' ? u8('}') : u8(')')
	depth := 0
	for i in open..<len(text) {
		switch text[i] {
		case opening: depth += 1
		case closing:
			depth -= 1
			if depth == 0 do return i
		}
	}
	return -1
}

@(private)
hlsl_words :: proc(text: string) -> []string {
	words := make([dynamic]string, context.temp_allocator)
	i := 0
	for i < len(text) {
		if !hlsl_is_word(text[i]) {
			i += 1
			continue
		}
		start := i
		for i < len(text) && hlsl_is_word(text[i]) do i += 1
		append(&words, text[start:i])
	}
	return words[:]
}

@(private)
hlsl_line_at :: proc(code: Code, offset: int) -> int {
	return code.line + strings.count(code.text[:offset], "\n")
}

// 入口函数：返回类型、形参（去掉 in / out / 语义）与函数体。
@(private)
hlsl_entry :: proc(blocks: []Code, name: string) -> (entry: Hlsl_Entry, ok: bool) {
	for block in blocks {
		text := block.text
		at := hlsl_find_word(text, name)
		for at >= 0 {
			open := at + len(name)
			for open < len(text) && (text[open] == ' ' || text[open] == '\t') do open += 1
			if open < len(text) && text[open] == '(' {
				close := hlsl_match(text, open)
				brace := close < 0 ? -1 : strings.index_byte(text[close:], '{')
				if brace < 0 do return
				brace += close
				end := hlsl_match(text, brace)
				if end < 0 do return
				before := hlsl_words(text[max(0, strings.last_index_byte(text[:at], '\n')):at])
				if len(before) > 0 do entry.return_type = before[len(before)-1]
				params := make([dynamic]Hlsl_Param, context.temp_allocator)
				for part in strings.split(text[open+1:close], ",", context.temp_allocator) {
					declaration := part
					if colon := strings.index_byte(declaration, ':'); colon >= 0 do declaration = declaration[:colon]
					words := hlsl_words(declaration)
					if len(words) >= 2 do append(&params, Hlsl_Param{words[len(words)-2], words[len(words)-1]})
				}
				entry.params = params[:]
				entry.body = text[brace:end+1]
				return entry, true
			}
			at = hlsl_find_word(text, name, at + 1)
		}
	}
	return
}

// struct name { ... }：成员的类型、名字、语义与源文件行号（修饰词如 nointerpolation 忽略）。
@(private)
hlsl_struct :: proc(blocks: []Code, name: string) -> (result: Hlsl_Struct, ok: bool) {
	for block in blocks {
		text := block.text
		at := hlsl_find_word(text, "struct")
		for at >= 0 {
			words := hlsl_words(text[at:min(len(text), at + len("struct") + len(name) + 64)])
			brace := strings.index_byte(text[at:], '{')
			if len(words) >= 2 && words[1] == name && brace >= 0 {
				brace += at
				end := hlsl_match(text, brace)
				if end < 0 do return
				members := make([dynamic]Hlsl_Member, context.temp_allocator)
				offset := brace + 1
				for part in strings.split(text[brace+1:end], ";", context.temp_allocator) {
					declaration, semantic := part, ""
					if colon := strings.index_byte(part, ':'); colon >= 0 {
						declaration = part[:colon]
						semantic = strings.trim_space(part[colon+1:])
					}
					names := hlsl_words(declaration)
					if len(names) >= 2 {
						first := strings.index(part, names[0])
						append(&members, Hlsl_Member{type = hlsl_member_type(names), name = names[len(names)-1],
							semantic = semantic, line = hlsl_line_at(block, offset + max(first, 0))})
					}
					offset += len(part) + 1
				}
				return {name, members[:], hlsl_line_at(block, at)}, true
			}
			at = hlsl_find_word(text, "struct", at + 1)
		}
	}
	return
}

// 去掉插值与存储修饰词后的类型名。
@(private)
hlsl_member_type :: proc(words: []string) -> string {
	for word in words[:len(words)-1] {
		switch word {
		case "nointerpolation", "linear", "centroid", "noperspective", "sample", "precise", "const", "static", "uniform":
			continue
		}
		return word
	}
	return words[0]
}

// 第一个占顶点属性的成员（SV_ 语义的系统值不占）。
@(private)
hlsl_first_attribute :: proc(members: []Hlsl_Member) -> (Hlsl_Member, bool) {
	for member in members {
		if strings.has_prefix(strings.to_upper(member.semantic, context.temp_allocator), "SV_") do continue
		return member, true
	}
	return {}, false
}

// body 里有 name.member 访问。
@(private)
hlsl_contains_access :: proc(body, name, member: string) -> bool {
	at := hlsl_find_word(body, name)
	for at >= 0 {
		rest := strings.trim_left_space(body[at+len(name):])
		if strings.has_prefix(rest, ".") {
			field := strings.trim_left_space(rest[1:])
			if strings.has_prefix(field, member) && (len(field) == len(member) || !hlsl_is_word(field[len(member)])) {
				return true
			}
		}
		at = hlsl_find_word(body, name, at + 1)
	}
	return false
}

// 片元把整个输入（不带 .成员）交给别处时，无法判断哪些成员被用到。
@(private)
hlsl_used_whole :: proc(body, name: string) -> bool {
	at := hlsl_find_word(body, name)
	for at >= 0 {
		rest := strings.trim_left_space(body[at+len(name):])
		if !strings.has_prefix(rest, ".") do return true
		at = hlsl_find_word(body, name, at + 1)
	}
	return false
}
