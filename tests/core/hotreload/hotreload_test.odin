#+build !js
#+test
package hotreload

import "core:fmt"
import "core:os"
import "core:testing"

// 内容监听须发现文件增删、子目录与不改变大小的编辑；不依赖时间戳精度。
@(test)
source_changes_and_disposal :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "olib_hotreload_test_", context.allocator)
	testing.expect(t, err == nil)
	if err != nil do return
	defer delete(root)
	sub := fmt.tprintf("%s/nested", root)
	file := fmt.tprintf("%s/main.odin", sub)
	added := fmt.tprintf("%s/new.odin", root)
	ignored := fmt.tprintf("%s/cache.dll", root)
	_ = os.make_directory(sub)
	defer {
		_ = os.remove(file)
		_ = os.remove(added)
		_ = os.remove(ignored)
		_ = os.remove(sub)
		_ = os.remove(root)
	}
	testing.expect(t, os.write_entire_file(file, "AAAA") == nil)
	w: Watch
	testing.expect(t, watch_init(&w, {command = {"odin", "-out:{output}"}, roots = {root}}))
	defer watch_dispose(&w)
	first, ok := watch_fingerprint(&w)
	testing.expect(t, ok)
	_ = os.write_entire_file(file, "BBBB")
	second, ok2 := watch_fingerprint(&w)
	testing.expect(t, ok2 && first != second)
	_ = os.write_entire_file(ignored, "unwatched")
	third, _ := watch_fingerprint(&w)
	testing.expect(t, third == second)
	_ = os.write_entire_file(added, "package extra")
	fourth, _ := watch_fingerprint(&w)
	testing.expect(t, fourth != third)
	_ = os.remove(added)
	fifth, _ := watch_fingerprint(&w)
	testing.expect(t, fifth == third)
	_ = os.remove(file)
	sixth, _ := watch_fingerprint(&w)
	testing.expect(t, sixth != fifth)
	_ = os.remove(sub)
	_ = os.remove(ignored)
	_ = os.remove(root)
	_, missing := watch_fingerprint(&w)
	testing.expect(t, !missing)
}

@(test)
session_rejects_missing_module_without_becoming_live :: proc(t: ^testing.T) {
	s: Session
	testing.expect(t, reload(&s, "absent.dll") == .Not_Initialized)
	testing.expect(t, init(&s, 17))
	defer _ = dispose(&s)
	testing.expect(t, !init(&s, 18), "must not overwrite a live session's ownership")
	testing.expect(t, reload(&s, "__olib_missing_module__.dll") == .File_Error)
	testing.expect(t, !is_live(&s) && s.revision == 0 && s.diagnostic != "")
	s.busy = true
	testing.expect(t, reload(&s, "absent.dll") == .Busy && !dispose(&s))
	s.busy = false
}
