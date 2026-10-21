#+test
package dev

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

SINGLE_FILE :: `Shader "Single" {
Properties { _Tint ("Tint", Color) = (0.2, 0.4, 0.8, 1) }
Pass "main" { Draw Fullscreen
HLSLPROGRAM
struct Input { float2 position : TEXCOORD0; float2 uv : TEXCOORD1; };
float4 vertex_main(Input v) : SV_Position { return float4(v.position, 0, 1); }
float4 fragment_main() : SV_Target0 { return _Tint; }
ENDHLSL
}
}`

@(test)
single_file_build_snapshot_and_stale_watch_result :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "olib_shader_files_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) {
		return
	}
	defer remove_workspace(root)
	path := fmt.tprintf("%s/single.oshader", root)
	testing.expect(t, os.write_entire_file(path, SINGLE_FILE) == nil)
	before, ok := parameters_fingerprint(root)
	testing.expect(t, ok)
	// Odin 声明已退出发现流程：即使同目录存在无效 Odin 文件，也不解析或执行。
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/unused.odin", root), string("not an Odin package")) == nil)
	ignored, _ := parameters_fingerprint(root)
	testing.expect(t, ignored == before)
	build := parameters_compile(root)
	defer parameter_build_dispose(&build)
	if !testing.expectf(t, build.error == "", "%s", build.error) {
		return
	}
	testing.expect(t, len(build.schemas) == 1 && len(build.shaders) == 1 && len(build.programs) == 1)
	testing.expect(t, build.programs[0].group == "Single_main")
	testing.expect(t, build.schemas[0].shader == "single.oshader")
	changed, _ := strings.replace_all(SINGLE_FILE, "0.2", "0.3", context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, changed) == nil)
	after, _ := parameters_fingerprint(root)
	testing.expect(t, before != after && build.schemas[0].fields[0].initial[0] == 0.2)
	watch: Parameter_Watch
	parameters_init(&watch, root)
	defer parameters_dispose(&watch)
	watch.status = .Ready
	watch.job.fingerprint = before
	stale := parameters_take(&watch)
	defer parameter_build_dispose(&stale)
	testing.expect(t, len(stale.schemas) == 0)
	// 编译已提取的程序，不重新读取被修改的属性；错误也必须指向原始 .oshader。
	compiled := compile(path, "spv", build.programs[0].text)
	defer build_dispose(&compiled)
	testing.expectf(t, compiled.error == "", "%s", compiled.error)
	bad, _ := strings.replace_all(build.programs[0].text, "return _Tint;", "return missing_symbol;", context.temp_allocator)
	failed := compile(path, "spv", bad)
	defer build_dispose(&failed)
	testing.expectf(t, strings.contains(failed.error, "single.oshader") && strings.contains(failed.error, "missing_symbol"), "%s", failed.error)
	// includes 变化也使整包候选过期。
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/common.hlsli", root), "// changed") == nil)
	include_hash, _ := parameters_fingerprint(root)
	testing.expect(t, include_hash != after)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/duplicate.oshader", root), SINGLE_FILE) == nil)
	duplicate := parameters_compile(root)
	defer parameter_build_dispose(&duplicate)
	testing.expect(t, strings.contains(duplicate.error, "duplicate shader"))
	testing.expect(t, os.remove(path) == nil)
	testing.expect(t, os.remove(fmt.tprintf("%s/duplicate.oshader", root)) == nil)
	empty := parameters_compile(root)
	defer parameter_build_dispose(&empty)
	testing.expect(t, empty.error == "" && len(empty.schemas) == 0 && len(empty.shaders) == 0)
}

// 编译目录里要有 olib 标准 include，且 olib/ 子目录能随临时目录一起删掉。
@(test)
snapshot_includes_copies_standard_include :: proc(t: ^testing.T) {
	directory, err := os.make_directory_temp("", "olib_include_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) {
		return
	}
	testing.expect(t, snapshot_includes(directory))
	for name in ([]string{"model.hlsli", "sprite.hlsli", "fullscreen.hlsli"}) {
		testing.expectf(t, os.is_file(fmt.tprintf("%s/olib/%s", directory, name)), "missing olib/%s", name)
	}
	remove_workspace(directory)
	testing.expect(t, !os.exists(directory))
}
