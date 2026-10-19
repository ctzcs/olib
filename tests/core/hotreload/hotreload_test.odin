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

// ---- simple_api：State 整体交接，堆数据共用，start / stop / drop 各司其职 ----

@(private = "file")
Test_State :: struct {
	value: i32,
	values: [dynamic]int, // 堆数据：热重载时新旧版本共用，只在真正退出时 drop 释放
	resource: int, // 模拟资源（如 Batcher）：每个版本自己创建、释放
}

@(private = "file")
Test_Services :: struct {
	started, stopped, dropped, updated, rendered: int,
	next_resource: int,
	released: [4]int,
}

@(private = "file")
test_reset :: proc(state: ^Test_State, services: ^Test_Services) {
	state.value = 7
	state.values = make([dynamic]int)
	append(&state.values, 10, 20)
}

@(private = "file")
test_start :: proc(state: ^Test_State, services: ^Test_Services) {
	services.started += 1
	services.next_resource += 1
	state.resource = services.next_resource // 覆盖交接过来的旧资源
}

@(private = "file")
test_stop :: proc(state: ^Test_State, services: ^Test_Services) {
	services.released[services.stopped] = state.resource
	services.stopped += 1
}

@(private = "file")
test_drop :: proc(state: ^Test_State, services: ^Test_Services) {
	services.dropped += 1
	delete(state.values)
}

@(private = "file")
test_update :: proc(state: ^Test_State, services: ^Test_Services, dt: f64) {
	services.updated += 1
	state.value += 1
	append(&state.values, int(state.value))
}

@(private = "file")
test_render :: proc(state: ^Test_State, services: ^Test_Services, dt: f64) {
	services.rendered += 1
}

@(private = "file")
test_hooks := Game_Hooks(Test_State, Test_Services){
	reset = test_reset, update = test_update, render = test_render,
	start = test_start, stop = test_stop, drop = test_drop, host_version = 3, state_version = 5,
}

@(test)
simple_api_hands_state_over_and_drops_only_at_exit :: proc(t: ^testing.T) {
	api: API
	testing.expect(t, !simple_api(API_VERSION + 1, size_of(API), &api, &test_hooks))
	bad_hooks := Game_Hooks(Test_State, Test_Services){reset = test_reset}
	testing.expect(t, !simple_api(API_VERSION, size_of(API), &api, &bad_hooks), "update and render are required")
	testing.expect(t, simple_api(API_VERSION, size_of(API), &api, &test_hooks))
	testing.expect(t, api_valid(api) && api.host_version == 3 && api.state_version == 5)
	services: Test_Services
	ctx := context
	old := Call{host_context = &ctx, services = &services}
	// 新局：reset 初始化，start 创建资源 1。
	testing.expect(t, api.load(&old, {}))
	api.update(&old, 0.1)
	api.render(&old, 0.1)
	testing.expect_value(t, services.started, 1)
	testing.expect_value(t, api.snapshot_size(&old), size_of(Test_State))
	snapshot := make([]u8, api.snapshot_size(&old))
	defer delete(snapshot)
	testing.expect(t, !api.save(&old, snapshot[:1]), "wrong buffer size")
	// 热重载：旧版本交出 State，新版本 load（不调用 reset），start 换上资源 2，旧版本再 unload。
	testing.expect(t, api.save(&old, snapshot))
	next := Call{host_context = &ctx, services = &services}
	testing.expect(t, api.load(&next, {data = snapshot, version = 5}))
	testing.expect_value(t, services.started, 2)
	old_state := (cast(^Simple_Slot(Test_State))old.instance).state
	api.unload(&old)
	testing.expect_value(t, services.stopped, 1)
	testing.expect_value(t, services.released[0], 1) // 旧版本释放的是它自己的资源 1
	testing.expect_value(t, services.dropped, 0) // 已交接：不释放共用的堆数据
	restored := (cast(^Simple_Slot(Test_State))next.instance).state
	testing.expect_value(t, restored.value, 8) // reset 的 7 加一次 update
	testing.expect_value(t, restored.resource, 2)
	testing.expect(t, raw_data(restored.values) == raw_data(old_state.values), "heap data is shared, not copied")
	testing.expect_value(t, len(restored.values), 3)
	api.update(&next, 0.1)
	testing.expect_value(t, len(restored.values), 3) // restored 是副本；真实状态在 next 的槽里
	testing.expect_value(t, len((cast(^Simple_Slot(Test_State))next.instance).state.values), 4)
	// 真正退出：stop 和 drop 各一次。
	api.unload(&next)
	testing.expect_value(t, services.stopped, 2)
	testing.expect_value(t, services.released[1], 2)
	testing.expect_value(t, services.dropped, 1)
}

@(test)
simple_api_keeps_ownership_when_candidate_is_rejected :: proc(t: ^testing.T) {
	api: API
	testing.expect(t, simple_api(API_VERSION, size_of(API), &api, &test_hooks))
	services: Test_Services
	ctx := context
	old := Call{host_context = &ctx, services = &services}
	testing.expect(t, api.load(&old, {}))
	snapshot := make([]u8, api.snapshot_size(&old))
	defer delete(snapshot)
	testing.expect(t, api.save(&old, snapshot))
	// 新版本拒绝（大小不符）：不调用它的 stop / drop，旧版本继续运行并仍然拥有 State。
	rejected := Call{host_context = &ctx, services = &services}
	testing.expect(t, !api.load(&rejected, {data = snapshot[:3], version = 5}))
	api.unload(&rejected)
	testing.expect_value(t, services.stopped, 0)
	testing.expect_value(t, services.dropped, 0)
	api.update(&old, 0.1) // 继续运行会取消"已交接"标记
	api.unload(&old)
	testing.expect_value(t, services.dropped, 1)
}

@(private = "file")
Minimal_State :: struct {
	count: int,
}

@(private = "file")
minimal_reset :: proc(state: ^Minimal_State, services: ^Test_Services) {
	state.count = 1
}

@(private = "file")
minimal_update :: proc(state: ^Minimal_State, services: ^Test_Services, dt: f64) {
	state.count += 1
}

@(private = "file")
minimal_render :: proc(state: ^Minimal_State, services: ^Test_Services, dt: f64) {}

// 没有资源的游戏只填 reset / update / render，其余回调为 nil。
@(test)
simple_api_works_with_only_required_hooks :: proc(t: ^testing.T) {
	hooks := Game_Hooks(Minimal_State, Test_Services){reset = minimal_reset, update = minimal_update, render = minimal_render}
	api: API
	testing.expect(t, simple_api(API_VERSION, size_of(API), &api, &hooks))
	testing.expect(t, api.host_version == 1 && api.state_version == 1)
	services: Test_Services
	ctx := context
	call := Call{host_context = &ctx, services = &services}
	testing.expect(t, api.load(&call, {}))
	api.update(&call, 0.1)
	testing.expect_value(t, (cast(^Simple_Slot(Minimal_State))call.instance).state.count, 2)
	api.unload(&call)
}
