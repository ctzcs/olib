// storage 包单元测试。写入真实用户目录（olib_test_app/<随机>），结束清理。
#+test
package storage

import "core:os"
import "core:strings"
import "core:testing"

import foster "ofoster:."

@(private)
TEST_APP :: "olib_storage_test_app"

@(private)
remove_tree :: proc(path: string) -> os.Error {
	if !os.is_directory(path) {
		e := os.remove(path)
		if e == nil || e == .Not_Exist do return nil
		return e
	}
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err != nil do return err
	defer os.file_info_slice_delete(infos, context.temp_allocator)
	for info in infos {
		child := strings.join({path, info.name}, "/", context.temp_allocator)
		e := remove_tree(child)
		if e != nil do return e
	}
	return os.remove(path)
}

@(test)
user_root_creates_platform_dir :: proc(t: ^testing.T) {
	root := user_root(TEST_APP)
	if !testing.expectf(t, root != "", "应得到用户根目录（APPDATA/HOME 应存在）") {
		return
	}
	defer delete(root)

	testing.expectf(t, os.is_directory(root), "user_root 应已建目录: %s", root)
	// 二次调用幂等
	again := user_root(TEST_APP)
	defer delete(again)
	testing.expect(t, again == root)
}

@(private)
Write_State :: struct {
	written: bool,
}

@(private)
write_then_check :: proc(ds: ^foster.DirectoryStorage, ud: rawptr) {
	state := (^Write_State)(ud)
	ok := foster.storage_write_all_bytes(
		foster.directory_storage_as_container(ds),
		"saves/save1.dat",
		[]u8{1, 2, 3, 4},
	)
	state.written = ok
}

@(test)
with_user_storage_roundtrip :: proc(t: ^testing.T) {
	root := user_root(TEST_APP)
	defer delete(root)
	if !testing.expectf(t, root != "", "无用户根目录") { return }
	saves_dir := strings.join({root, "saves"}, "/", context.temp_allocator)
	defer remove_tree(saves_dir)

	// 写
	state: Write_State
	ok := with_user_storage(TEST_APP, write_then_check, &state)
	testing.expectf(t, ok && state.written, "with_user_storage 写入应成功: ok=%v written=%v", ok, state.written)

	// 读回（DirectoryStorage 直读）
	full := user_file_path(TEST_APP, "saves/save1.dat")
	testing.expectf(t, os.exists(full), "文件应存在: %s", full)
	data, err := os.read_entire_file_from_path(full, context.allocator)
	testing.expectf(t, err == nil && len(data) == 4 && data[0] == 1 && data[3] == 4, "读回内容应一致")
	if err == nil do delete(data)
}

@(test)
resources_roots_resolve :: proc(t: ^testing.T) {
	dev := resources_root_dev()
	defer delete(dev)
	testing.expectf(t, dev != "", "dev 根 = cwd 应非空")

	rel := resources_root_release()
	defer delete(rel)
	testing.expectf(t, rel != "", "release 根 = exe 目录应非空")
}
