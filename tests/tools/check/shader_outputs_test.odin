#+test
package main

import "core:fmt"
import "core:os"
import "core:testing"

// 找出含 Compiled/ 的 shader 目录并标出是否有源码记录；隐藏目录、build 与 library 下的不算。
@(test)
discover_shader_dirs_marks_recorded_outputs :: proc(t: ^testing.T) {
	base, err := os.make_directory_temp("", "olib_check_shaders_*", context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	defer os.remove_all(base)
	for dir in ([]string{"src/a/shaders/Compiled", "src/b/shaders/Compiled", "src/.cache/shaders/Compiled",
		"src/build/shaders/Compiled", "src/library/shaders/Compiled"}) {
		testing.expect(t, os.make_directory_all(fmt.tprintf("%s/%s", base, dir)) == nil)
	}
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/src/a/shaders/Compiled/sources.json", base), "{}") == nil)

	dirs := discover_shader_dirs(base, {fmt.tprintf("%s/src", base), fmt.tprintf("%s/missing", base)})
	if testing.expect_value(t, len(dirs), 2) {
		testing.expect_value(t, dirs[0].name, "src/a/shaders")
		testing.expect(t, dirs[0].recorded)
		testing.expect_value(t, dirs[1].name, "src/b/shaders")
		testing.expect(t, !dirs[1].recorded)
	}
}
