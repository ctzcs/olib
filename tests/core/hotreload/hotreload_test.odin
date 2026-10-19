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

// ---- Hot：命令由配置生成，初始化/释放不留下状态 ----

@(test)
hot_builds_command_and_validates_config :: proc(t: ^testing.T) {
	command := hot_command({source = "src/game", collections = {"olib=../olib", "game=src"}, args = {"-vet"}})
	testing.expect_value(t, len(command), 8)
	testing.expect_value(t, command[2], "src/game")
	testing.expect_value(t, command[4], "-collection:olib=../olib")
	testing.expect_value(t, command[6], "-vet")
	testing.expect_value(t, command[7], "-out:{output}")
	h: Hot
	testing.expect(t, !hot_init(&h, {}), "source is required")
	root, err := os.make_directory_temp("", "olib_hot_test_", context.allocator)
	testing.expect(t, err == nil)
	if err != nil do return
	defer delete(root)
	defer _ = os.remove(root)
	testing.expect(t, hot_init(&h, {source = root, quiet = true}))
	testing.expect(t, !hot_init(&h, {source = root, quiet = true}), "already initialized")
	testing.expect_value(t, h.version, 0)
	testing.expect_value(t, hot_error(&h), "")
	hot_update(&h, 0.01) // 没有模块时不做任何事
	hot_render(&h, 0.01)
	hot_dispose(&h)
	testing.expect(t, !h.session.initialized && !h.watch.initialized)
}

// ---- simple_api：State 按字节保存恢复，start / stop 成对 ----

@(private = "file")
Test_State :: struct {
	value: i32,
	position: [2]f32,
}

@(private = "file")
Test_Services :: struct {
	started, stopped, updated, rendered: int,
}

@(private = "file")
test_reset :: proc(state: ^Test_State, services: ^Test_Services) {
	state^ = {value = 7, position = {1, 2}}
}

@(private = "file")
test_start :: proc(state: ^Test_State, services: ^Test_Services) {
	services.started += 1
}

@(private = "file")
test_stop :: proc(state: ^Test_State, services: ^Test_Services) {
	services.stopped += 1
}

@(private = "file")
test_update :: proc(state: ^Test_State, services: ^Test_Services, dt: f64) {
	services.updated += 1
	state.value += 1
}

@(private = "file")
test_render :: proc(state: ^Test_State, services: ^Test_Services, dt: f64) {
	services.rendered += 1
}

@(test)
simple_api_saves_restores_and_pairs_start_stop :: proc(t: ^testing.T) {
	api: API
	testing.expect(t, !simple_api(API_VERSION + 1, size_of(API), &api, Test_State, Test_Services,
		test_reset, test_start, test_stop, test_update, test_render))
	testing.expect(t, simple_api(API_VERSION, size_of(API), &api, Test_State, Test_Services,
		test_reset, test_start, test_stop, test_update, test_render, host_version = 3, state_version = 5))
	testing.expect(t, api_valid(api) && api.host_version == 3 && api.state_version == 5)
	services: Test_Services
	ctx := context
	call := Call{host_context = &ctx, services = &services}
	// 新局：reset 初始化，start 被调用。
	testing.expect(t, api.load(&call, {}))
	api.update(&call, 0.1)
	api.render(&call, 0.1)
	testing.expect_value(t, services.started, 1)
	testing.expect_value(t, services.updated, 1)
	testing.expect_value(t, services.rendered, 1)
	testing.expect_value(t, api.snapshot_size(&call), size_of(Test_State))
	snapshot := make([]u8, api.snapshot_size(&call))
	defer delete(snapshot)
	testing.expect(t, !api.save(&call, snapshot[:1]), "wrong buffer size")
	testing.expect(t, api.save(&call, snapshot))
	api.unload(&call)
	testing.expect_value(t, services.stopped, 1)
	// 热重载：用快照恢复，不再调用 reset。
	next := Call{host_context = &ctx, services = &services}
	testing.expect(t, api.load(&next, {data = snapshot, version = 5}))
	restored := (cast(^Simple_Slot(Test_State))next.instance).state
	testing.expect_value(t, restored.value, 8) // reset 的 7 加一次 update
	testing.expect_value(t, restored.position, [2]f32{1, 2})
	api.unload(&next)
	testing.expect_value(t, services.started, 2)
	testing.expect_value(t, services.stopped, 2)
	// 大小不符的快照被拒绝；失败的加载不会调用 stop，但 unload 仍能释放。
	bad := Call{host_context = &ctx, services = &services}
	testing.expect(t, !api.load(&bad, {data = snapshot[:3], version = 5}))
	api.unload(&bad)
	testing.expect_value(t, services.started, 2)
	testing.expect_value(t, services.stopped, 2)
}

// 没有额外资源的游戏只写 reset / update / render，不需要 start / stop。
@(test)
simple_api_without_start_and_stop :: proc(t: ^testing.T) {
	api: API
	testing.expect(t, simple_api(API_VERSION, size_of(API), &api, Test_State, Test_Services,
		test_reset, test_update, test_render))
	services: Test_Services
	ctx := context
	call := Call{host_context = &ctx, services = &services}
	testing.expect(t, api.load(&call, {}))
	api.update(&call, 0.1)
	api.unload(&call)
	testing.expect_value(t, services.started + services.stopped, 0)
	testing.expect_value(t, services.updated, 1)
}
