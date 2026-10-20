#+test
package main

import "core:fmt"
import "core:os"
import "core:testing"

@(private = "file")
write_text :: proc(t: ^testing.T, path, text: string) {
	testing.expectf(t, os.write_entire_file(path, text) == nil, "cannot write %s", path)
}

// 记录收集 .oshader / .hlsl / .hlsli（含子目录），跳过 Compiled、隐藏目录与其他文件；
// 只有含 .oshader 的目录才带上 olib 标准 include。
@(test)
sources_collect_picks_shader_sources :: proc(t: ^testing.T) {
	dir, err := os.make_directory_temp("", "olib_sources_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	defer remove_workspace(dir)
	for sub in ([]string{"common", "Compiled", ".cache"}) {
		testing.expect(t, os.make_directory(fmt.tprintf("%s/%s", dir, sub)) == nil)
	}
	write_text(t, fmt.tprintf("%s/Effect.hlsl", dir), "float4 main() : SV_Target0 { return 1; }\n")
	write_text(t, fmt.tprintf("%s/common/Shared.hlsli", dir), "float shared_value() { return 1; }\n")
	write_text(t, fmt.tprintf("%s/Compiled/Effect.vertex.spv", dir), "binary")
	write_text(t, fmt.tprintf("%s/.cache/Hidden.hlsli", dir), "ignored")
	write_text(t, fmt.tprintf("%s/notes.txt", dir), "ignored")

	record, reason := sources_collect(dir)
	testing.expect_value(t, reason, "")
	if testing.expect_value(t, len(record.files), 2) {
		testing.expect_value(t, record.files[0].path, "Effect.hlsl")
		testing.expect_value(t, record.files[1].path, "common/Shared.hlsli")
	}

	write_text(t, fmt.tprintf("%s/Material.oshader", dir), "Shader \"Material\" {}\n")
	with_oshader, oshader_reason := sources_collect(dir)
	testing.expect_value(t, oshader_reason, "")
	paths := make(map[string]bool, context.temp_allocator)
	for entry in with_oshader.files do paths[entry.path] = true
	for name in ([]string{"Material.oshader", "olib/model.hlsli", "olib/sprite.hlsli", "olib/fullscreen.hlsli"}) {
		testing.expectf(t, paths[name], "missing %s", name)
	}

	// olib/ 是保留的 include 目录名。
	testing.expect(t, os.make_directory(fmt.tprintf("%s/olib", dir)) == nil)
	_, reserved := sources_collect(dir)
	testing.expect(t, reserved != "")
}

// 换行不同不算修改：Windows 上 git 的 autocrlf 会把检出的文本改成 CRLF。
@(test)
source_hash_ignores_carriage_returns :: proc(t: ^testing.T) {
	testing.expect_value(t, source_hash(transmute([]u8)string("a\r\nb\r\n")), source_hash(transmute([]u8)string("a\nb\n")))
	testing.expect(t, source_hash(transmute([]u8)string("a\nb\n")) != source_hash(transmute([]u8)string("a\nc\n")))
}

// 写下记录后 -check 通过；改、增、删任一源码都报过期并指出文件，只改换行符不报。
@(test)
sources_check_reports_stale_files :: proc(t: ^testing.T) {
	dir, err := os.make_directory_temp("", "olib_sources_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	defer remove_workspace(dir)
	out := fmt.tprintf("%s/Compiled", dir)
	testing.expect(t, os.make_directory(out) == nil)
	write_text(t, fmt.tprintf("%s/A.hlsl", dir), "a\n")
	write_text(t, fmt.tprintf("%s/B.hlsli", dir), "b\n")

	testing.expect(t, !sources_check(dir)) // 还没有记录
	record, reason := sources_collect(dir)
	testing.expect_value(t, reason, "")
	text, ok := sources_encode(record, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, write_shader_file(fmt.tprintf("%s/%s", out, SOURCES_RECORD), text))
	testing.expect(t, sources_check(dir))

	write_text(t, fmt.tprintf("%s/B.hlsli", dir), "b\r\n")
	testing.expect(t, sources_check(dir))

	write_text(t, fmt.tprintf("%s/A.hlsl", dir), "a changed\n")
	write_text(t, fmt.tprintf("%s/C.hlsli", dir), "c\n")
	testing.expect(t, os.remove(fmt.tprintf("%s/B.hlsli", dir)) == nil)
	recorded, found, read_reason := sources_read(out)
	testing.expect(t, found && read_reason == "")
	current, _ := sources_collect(dir)
	lines := sources_diff(recorded, current)
	if testing.expect_value(t, len(lines), 3) {
		testing.expect_value(t, lines[0], "修改 A.hlsl")
		testing.expect_value(t, lines[1], "新增 C.hlsli")
		testing.expect_value(t, lines[2], "删除 B.hlsli")
	}
	testing.expect(t, !sources_check(dir))
}
