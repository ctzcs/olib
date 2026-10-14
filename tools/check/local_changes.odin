package main

// foster 本地修改校验：代码中的 `[olib L-xxx]` 标记与 foster/docs/LOCAL_CHANGES.md
// 清单一一对应。清单编号取表格行首列（形如 `| L-001 |`）；编号重复、代码有标记但
// 清单缺少、清单有记录但代码中找不到，都算失败，日志给出文件与行号。

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// 分区：
//   校验 —— 收集两侧编号并比对
//   解析 —— 清单表格行 / 代码标记

// ==============================================================================
// 校验
// ==============================================================================

// 返回是否一致与日志（成功时日志为汇总行）。临时数据都在 temp 分配器上。
check_local_changes :: proc(root: string) -> (ok: bool, log: string) {
	b := strings.builder_make(context.temp_allocator)
	foster_root := path_join(root, "foster")

	doc_path := path_join(foster_root, "docs", "LOCAL_CHANGES.md")
	doc, err := os.read_entire_file(doc_path, context.temp_allocator)
	if err != nil {
		fmt.sbprintfln(&b, "无法读取 %s: %v", doc_path, err)
		return false, strings.to_string(b)
	}

	// ---- 清单编号 ----
	doc_ids := make(map[string]bool, context.temp_allocator)
	text := string(doc)
	for line in strings.split_lines_iterator(&text) {
		id := doc_row_id(line) or_continue
		if id in doc_ids {
			fmt.sbprintfln(&b, "清单中编号重复: %s", id)
			return false, strings.to_string(b)
		}
		doc_ids[id] = true
	}

	// ---- 代码标记：编号 -> 出现位置列表 ----
	code_ids := make(map[string][dynamic]string, context.temp_allocator)
	collect_markers(foster_root, "", &code_ids)

	ok = true
	for id in sorted_keys(code_ids) {
		if id not_in doc_ids {
			locations := strings.join(code_ids[id][:], ", ", context.temp_allocator)
			fmt.sbprintfln(&b, "代码有标记但清单缺少 %s: %s", id, locations)
			ok = false
		}
	}
	for id in sorted_keys(doc_ids) {
		if id not_in code_ids {
			fmt.sbprintfln(&b, "清单有记录但代码中找不到标记: %s", id)
			ok = false
		}
	}
	if ok {
		fmt.sbprintf(&b, "本地修改标记一致：%d 条记录", len(doc_ids))
	}
	return ok, strings.to_string(b)
}

// 递归扫描 foster 下所有 .odin，位置记为 `相对路径:行号`（/ 分隔）。
@(private = "file")
collect_markers :: proc(foster_root, rel: string, code_ids: ^map[string][dynamic]string) {
	entries, err := os.read_all_directory_by_path(path_join(foster_root, rel), context.temp_allocator)
	if err != nil do return

	for e in entries {
		child := len(rel) == 0 ? e.name : strings.concatenate({rel, "/", e.name}, context.temp_allocator)
		if e.type == .Directory {
			collect_markers(foster_root, child, code_ids)
			continue
		}
		if !strings.has_suffix(e.name, ".odin") do continue
		data, read_err := os.read_entire_file(e.fullpath, context.temp_allocator)
		if read_err != nil do continue

		text := string(data)
		line_number := 0
		for line in strings.split_lines_iterator(&text) {
			line_number += 1
			rest := line
			for id in next_marker(&rest) {
				if id not_in code_ids {
					code_ids[id] = make([dynamic]string, context.temp_allocator)
				}
				append(&code_ids[id], fmt.tprintf("%s:%d", child, line_number))
			}
		}
	}
}

@(private = "file")
sorted_keys :: proc(m: map[string]$V) -> []string {
	keys, _ := slice.map_keys(m, context.temp_allocator)
	slice.sort(keys)
	return keys
}

// ==============================================================================
// 解析
// ==============================================================================

// 清单表格行首列的编号：`| L-001 | ...` -> "L-001"。
@(private = "file")
doc_row_id :: proc(line: string) -> (id: string, ok: bool) {
	if !strings.has_prefix(line, "|") do return
	cell := line[1:]
	end := strings.index_byte(cell, '|')
	if end < 0 do return
	id = strings.trim_space(cell[:end])
	return id, is_change_id(id)
}

// 依次取出一行里的 `[olib L-xxx]` 标记编号，每次调用推进 rest。
@(private = "file")
next_marker :: proc(rest: ^string) -> (id: string, ok: bool) {
	PREFIX :: "[olib "
	for {
		start := strings.index(rest^, PREFIX)
		if start < 0 do return
		candidate := rest[start + len(PREFIX):]
		rest^ = candidate
		if len(candidate) >= 6 && candidate[5] == ']' && is_change_id(candidate[:5]) {
			rest^ = candidate[6:]
			return candidate[:5], true
		}
	}
}

// 形如 `L-` 加三位数字。
@(private = "file")
is_change_id :: proc(s: string) -> bool {
	if len(s) != 5 || !strings.has_prefix(s, "L-") do return false
	for ch in s[2:] {
		if ch < '0' || ch > '9' do return false
	}
	return true
}
