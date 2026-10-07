// asset 包单元测试（native）。
//
// 覆盖：guid 往返/唯一、blob 往返、.meta 身份（ensure/移动不坏/重复 GUID 报错）、
// import_all（导入/新鲜度跳过/删 Library 重建/孤儿警告/importer 版本失效）、
// 运行时加载（directory 与 map 后端、三种 kind、缓存、卸载）、
// manifest（打包形态：只带 Library、assets_root 为空时 load_path 仍可用）。
#+test
package asset

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"

import foster "olib:foster"

// 测试工作区根：优先系统临时目录。
@(private)
test_root :: proc() -> string {
	base := os.get_env_alloc("TEMP", context.temp_allocator)
	if base == "" {
		base = os.get_env_alloc("TMP", context.temp_allocator)
	}
	if base == "" {
		base = ".test_tmp"
	}
	return strings.join({base, "olib_asset_test"}, "/", context.temp_allocator)
}

// 递归删除。不用 os.remove_all：此 Odin nightly 在 Windows 上走 SHFileOperationW
// 且路径缺双 NUL 终止，会直接崩溃（core bug），自实现绕开。
// 目录不存在视为成功（fresh_dir 首次运行时就是这种形态）。
@(private)
remove_tree :: proc(path: string) -> os.Error {
	if !os.is_directory(path) {
		e := os.remove(path)
		if e == nil || e == .Not_Exist {
			return nil
		}
		return e
	}
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err != nil {
		return err
	}
	defer os.file_info_slice_delete(infos, context.temp_allocator)
	for info in infos {
		child := strings.join({path, info.name}, "/", context.temp_allocator)
		e := remove_tree(child)
		if e != nil {
			return e
		}
	}
	return os.remove(path)
}

// 清空并重建 <root>/<name>，返回其路径（temp 分配）。
@(private)
fresh_dir :: proc(t: ^testing.T, name: string) -> string {
	dir := strings.join({test_root(), name}, "/", context.temp_allocator)
	e := remove_tree(dir)
	if !testing.expectf(t, e == nil, "remove_all(%s): %v", dir, e) { return "" }
	e = os.make_directory_all(dir)
	if !testing.expectf(t, e == nil, "make_directory_all(%s): %v", dir, e) { return "" }
	return dir
}

@(private)
join_path :: proc(a, b: string) -> string {
	return strings.join({a, b}, "/", context.temp_allocator)
}

@(private)
write_file :: proc(t: ^testing.T, path: string, data: []u8) -> bool {
	e := os.write_entire_file(path, data)
	return testing.expectf(t, e == nil, "write_entire_file(%s): %v", path, e)
}

// 生成一张 >=2x2 的四象限纯色 QOI（返回四个象限颜色）。
@(private)
make_test_qoi :: proc(t: ^testing.T, path: string, w, h: int) -> (c00, c10, c01, c11: foster.Color) {
	c00 = foster.Color{255, 0, 0, 255}
	c10 = foster.Color{0, 255, 0, 255}
	c01 = foster.Color{0, 0, 255, 255}
	c11 = foster.Color{255, 255, 0, 255}
	testing.expect(t, w >= 2 && h >= 2)

	image := foster.ImageMake(w, h, foster.Color{0, 0, 0, 255})
	for y in 0..<h {
		for x in 0..<w {
			upper := y < h / 2 + 1
			left := x < w / 2 + 1
			image.Pixels[x + y * w] = left ? (upper ? c00 : c01) : (upper ? c10 : c11)
		}
	}
	wok := foster.ImageWriteQoi(&image, path)
	testing.expectf(t, wok, "ImageWriteQoi(%s) 失败", path)
	delete(image.Pixels)
	return
}

@(private)
meta_read_by_path :: proc(t: ^testing.T, assets_root, rel: string) -> Guid {
	ds: foster.DirectoryStorage
	foster.directory_storage_init(&ds, assets_root, false)
	g, e := meta_read(foster.directory_storage_as_container(&ds), rel)
	testing.expectf(t, e == .None, "meta_read(%s): %v", rel, e)
	return g
}

// ---------------------------------------------------------------------------
// Guid
// ---------------------------------------------------------------------------

@(test)
guid_roundtrip_and_uniqueness :: proc(t: ^testing.T) {
	g := guid_generate()
	s := guid_to_string(g, context.temp_allocator)
	testing.expectf(t, len(s) == 32, "guid_to_string 长度应为 32，实际 %d", len(s))

	back, ok := guid_from_string(s)
	testing.expectf(t, ok && back == g, "hex 往返失败: %s", s)

	upper, _ := strings.to_upper(s, context.temp_allocator)
	back2, ok2 := guid_from_string(upper)
	testing.expectf(t, ok2 && back2 == g, "大写 hex 解析不一致")

	_, ok3 := guid_from_string("zzzz")
	testing.expect(t, !ok3)

	seen := make(map[Guid]bool)
	defer delete(seen)
	dup := false
	for _ in 0..<1000 {
		gg := guid_generate()
		if gg in seen {
			dup = true
			break
		}
		seen[gg] = true
	}
	testing.expectf(t, !dup, "1000 次内出现重复 guid")
}

// ---------------------------------------------------------------------------
// blob
// ---------------------------------------------------------------------------

@(test)
blob_roundtrip :: proc(t: ^testing.T) {
	g := guid_generate()
	payload := []u8{1, 2, 3, 4, 5}

	blob, ok := blob_build(g, .Raw, 7, 12345, 99, payload, context.temp_allocator)
	testing.expect(t, ok)

	header, parsed, pok := blob_parse(blob)
	testing.expect(t, pok)
	testing.expect(t, header.guid == cast([16]u8)g)
	testing.expect(t, header.importer_version == 7)
	testing.expect(t, header.src_mtime == 12345 && header.src_size == 99)
	testing.expect(t, header.kind == u8(Asset_Kind.Raw) && header.payload_len == 5)
	testing.expect(t, string(parsed) == string(payload))

	_, _, ok_trunc := blob_parse(blob[:10])
	testing.expect(t, !ok_trunc)
	blob[0] = 'X'
	_, _, ok_magic := blob_parse(blob)
	testing.expect(t, !ok_magic)
}

// ---------------------------------------------------------------------------
// .meta 身份
// ---------------------------------------------------------------------------

@(test)
meta_identity :: proc(t: ^testing.T) {
	root := fresh_dir(t, "meta")
	if root == "" { return }

	ds: foster.DirectoryStorage
	foster.directory_storage_init(&ds, root, true)
	assets := foster.directory_storage_as_container(&ds)

	make_test_qoi(t, join_path(root, "a.qoi"), 4, 4)

	// 缺 .meta 时 ensure 生成；已存在时读回同一个
	g1, e1 := meta_ensure(assets, "a.qoi")
	testing.expectf(t, e1 == .None, "meta_ensure: %v", e1)
	g1b, e2 := meta_read(assets, "a.qoi")
	testing.expectf(t, e2 == .None && g1b == g1, "meta_read 与 ensure 不一致: %v", e2)
	g1c, e3 := meta_ensure(assets, "a.qoi")
	testing.expectf(t, e3 == .None && g1c == g1, "二次 ensure 不应改 GUID")

	// 移动文件 + .meta 到子目录：GUID 不变（身份随 .meta 走）
	e4 := os.make_directory_all(join_path(root, "sub"))
	testing.expectf(t, e4 == nil, "mkdir sub: %v", e4)
	e5 := os.rename(join_path(root, "a.qoi"), join_path(root, "sub/a.qoi"))
	testing.expectf(t, e5 == nil, "rename a.qoi: %v", e5)
	e6 := os.rename(join_path(root, "a.qoi.meta"), join_path(root, "sub/a.qoi.meta"))
	testing.expectf(t, e6 == nil, "rename a.qoi.meta: %v", e6)
	g2, e7 := meta_read(assets, "sub/a.qoi")
	testing.expectf(t, e7 == .None && g2 == g1, "移动文件+.meta 后 GUID 应不变: %v", e7)

	// 人为制造重复 GUID：import_all 必须报 Duplicate_Guid（绝不静默换）
	write_file(t, join_path(root, "b.qoi"), []u8{1})
	e8 := meta_write(assets, "b.qoi", g1)
	testing.expectf(t, e8 == .None, "meta_write b: %v", e8)
	_, derr := import_all(root, join_path(root, "Library"))
	testing.expectf(t, derr == .Duplicate_Guid, "重复 GUID 应报 Duplicate_Guid，实际 %v", derr)
}

// ---------------------------------------------------------------------------
// import_all + 运行时加载（directory 后端）
// ---------------------------------------------------------------------------

@(test)
import_and_load :: proc(t: ^testing.T) {
	root := fresh_dir(t, "pipeline")
	if root == "" { return }
	assets_root := join_path(root, "Assets")
	library_root := join_path(root, "Library")
	e0 := os.make_directory_all(assets_root)
	testing.expectf(t, e0 == nil, "mkdir Assets: %v", e0)

	c00, c10, c01, c11 := make_test_qoi(t, join_path(assets_root, "tex.qoi"), 4, 4)
	json_text := "{\"hp\": 10, \"name\": \"slime\"}"
	write_file(t, join_path(assets_root, "conf.json"), transmute([]u8)(json_text))
	write_file(t, join_path(assets_root, "data.bin"), []u8{9, 8, 7, 6})

	s1, e1 := import_all(assets_root, library_root)
	testing.expectf(t, e1 == .None, "import_all #1: %v", e1)
	testing.expect(t, s1.scanned == 3 && s1.imported == 3 && s1.skipped == 0 && s1.guid_generated == 3)

	s2, e2 := import_all(assets_root, library_root)
	testing.expectf(t, e2 == .None, "import_all #2: %v", e2)
	testing.expect(t, s2.skipped == 3 && s2.imported == 0 && s2.guid_generated == 0)

	// 不变量：删除整个 Library 可完全重建，GUID 不变
	g_tex := meta_read_by_path(t, assets_root, "tex.qoi")
	e3 := remove_tree(library_root)
	testing.expectf(t, e3 == nil, "删除 Library: %v", e3)
	s3, e3b := import_all(assets_root, library_root)
	testing.expectf(t, e3b == .None && s3.imported == 3, "删 Library 重建: %v", e3b)
	testing.expect(t, meta_read_by_path(t, assets_root, "tex.qoi") == g_tex)

	// 运行时加载（无 GPU：Texture 保留 CPU Image）
	m: Asset_Manager
	e4 := assets_init(&m, Asset_Manager_Config{
		assets_root  = assets_root,
		library_root = library_root,
	})
	testing.expectf(t, e4 == .None, "assets_init: %v", e4)
	defer assets_dispose(&m)

	htex, e5 := assets_load_path(&m, "tex.qoi")
	testing.expectf(t, e5 == .None, "load_path tex.qoi: %v", e5)
	image := assets_get_image(&m, htex)
	testing.expectf(t, image != nil, "无 device 时应拿到 CPU Image")
	if image != nil {
		testing.expect(t, image.Width == 4 && image.Height == 4)
		expect := [4]foster.Color{c00, c10, c01, c11}
		for i in 0..<4 {
			want := expect[i]
			x := i % 2 == 0 ? 0 : 3
			y := i / 2 == 0 ? 0 : 3
			testing.expectf(t, image.Pixels[x + y * 4] == want, "象限 %d 像素不符: got %v want %v", i, image.Pixels[x + y * 4], want)
		}
	}

	hjson, e6 := assets_load_path(&m, "conf.json")
	testing.expectf(t, e6 == .None, "load_path conf.json: %v", e6)
	value := assets_get_json(&m, hjson)
	if testing.expectf(t, value != nil, "json getter 应返回非 nil") {
		obj, o_ok := value.(json.Object)
		testing.expect(t, o_ok)
		hp, hp_ok := obj["hp"].(json.Integer)
		testing.expect(t, hp_ok && hp == 10)
	}

	hraw, e7 := assets_load_path(&m, "data.bin")
	testing.expectf(t, e7 == .None, "load_path data.bin: %v", e7)
	raw := assets_get_bytes(&m, hraw)
	testing.expect(t, len(raw) == 4 && raw[0] == 9 && raw[3] == 6)

	// kind 不匹配防御
	testing.expect(t, assets_get_texture(&m, hjson) == nil)
	testing.expect(t, assets_get_bytes(&m, htex) == nil)

	// guid 直查 + 缓存：同 guid 重复加载返回同句柄
	hagain, e8 := assets_load(&m, g_tex)
	testing.expectf(t, e8 == .None && hagain == htex, "重复加载应命中缓存: %v", e8)
	testing.expect(t, assets_len(&m) == 3)

	// 卸载：句柄失效，缓存清空，重载可用
	g_raw := assets_guid(&m, hraw)
	assets_unload(&m, hraw)
	testing.expect(t, !assets_valid(&m, hraw))
	hraw2, e9 := assets_load(&m, g_raw)
	testing.expectf(t, e9 == .None && hraw2 != ASSET_HANDLE_NONE, "卸载后应可重载: %v", e9)
	testing.expect(t, len(assets_get_bytes(&m, hraw2)) == 4)
}

// ---------------------------------------------------------------------------
// importer 版本失效
// ---------------------------------------------------------------------------

@(private)
test_import_upper :: proc(source: []u8, ext: string, out: ^Payload_Builder, allocator := context.allocator) -> Asset_Error {
	data, aerr := make([]u8, len(source), allocator)
	if aerr != .None {
		return .Import_Failed
	}
	for i in 0..<len(source) {
		c := source[i]
		data[i] = u8((c >= 'a' && c <= 'z') ? c - 32 : c)
	}
	out.data = data
	return .None
}

@(test)
importer_version_invalidates :: proc(t: ^testing.T) {
	root := fresh_dir(t, "version")
	if root == "" { return }
	assets_root := join_path(root, "Assets")
	library_root := join_path(root, "Library")
	e0 := os.make_directory_all(assets_root)
	testing.expectf(t, e0 == nil, "mkdir: %v", e0)
	test_text := "hello"
	write_file(t, join_path(assets_root, "a.tst"), transmute([]u8)(test_text))

	importer_register(".tst", Importer{ kind = .Raw, version = 1, run = test_import_upper })

	s1, e1 := import_all(assets_root, library_root)
	testing.expectf(t, e1 == .None && s1.imported == 1, "v1 首次导入: %v", e1)
	s2, e2 := import_all(assets_root, library_root)
	testing.expectf(t, e2 == .None && s2.skipped == 1, "v1 二次应跳过: %v", e2)

	// 版本号 +1：源没变也要重导（导入逻辑升级即缓存失效）
	importer_register(".tst", Importer{ kind = .Raw, version = 2, run = test_import_upper })
	s3, e3 := import_all(assets_root, library_root)
	testing.expectf(t, e3 == .None && s3.imported == 1 && s3.skipped == 0, "版本升级应触发重导: %v", e3)
}

// ---------------------------------------------------------------------------
// map 后端
// ---------------------------------------------------------------------------

@(test)
map_storage_load :: proc(t: ^testing.T) {
	g := guid_generate()
	blob, ok := blob_build(g, .Raw, 1, 0, 0, []u8{1, 2, 3}, context.temp_allocator)
	testing.expect(t, ok)

	state: Map_State
	storage_map_init(&state)
	defer storage_map_dispose(&state)
	state.blobs[g] = blob

	m: Asset_Manager
	defer assets_dispose(&m)
	e := assets_init(&m, Asset_Manager_Config{ storage = storage_map(&state) })
	testing.expectf(t, e == .None, "assets_init: %v", e)

	handle, lerr := assets_load(&m, g)
	testing.expectf(t, lerr == .None, "assets_load: %v", lerr)
	raw := assets_get_bytes(&m, handle)
	testing.expect(t, len(raw) == 3 && raw[0] == 1 && raw[2] == 3)

	// 不存在的 guid
	_, nferr := assets_load(&m, guid_generate())
	testing.expectf(t, nferr == .File_Not_Found, "未知 guid 应报 File_Not_Found: %v", nferr)
}

// ---------------------------------------------------------------------------
// 孤儿 .meta
// ---------------------------------------------------------------------------

@(test)
orphan_meta_warns :: proc(t: ^testing.T) {
	root := fresh_dir(t, "orphan")
	if root == "" { return }
	assets_root := join_path(root, "Assets")
	library_root := join_path(root, "Library")
	e0 := os.make_directory_all(assets_root)
	testing.expectf(t, e0 == nil, "mkdir: %v", e0)

	ds: foster.DirectoryStorage
	foster.directory_storage_init(&ds, assets_root, true)
	assets := foster.directory_storage_as_container(&ds)
	e1 := meta_write(assets, "ghost.png", guid_generate())
	testing.expectf(t, e1 == .None, "meta_write: %v", e1)

	stats, e2 := import_all(assets_root, library_root)
	testing.expectf(t, e2 == .None, "孤儿 .meta 不应报错: %v", e2)
	testing.expect(t, stats.scanned == 0 && stats.orphaned_meta == 1)
	testing.expect(t, foster.storage_file_exists(assets, "ghost.png.meta"))
}

// ---------------------------------------------------------------------------
// manifest —— 打包形态（只带 Library，没有 Assets）
// ---------------------------------------------------------------------------

@(test)
manifest_packaged_load :: proc(t: ^testing.T) {
	root := fresh_dir(t, "manifest")
	if root == "" { return }
	assets_root := join_path(root, "Assets")
	library_root := join_path(root, "Library")
	e0 := os.make_directory_all(assets_root)
	testing.expectf(t, e0 == nil, "mkdir: %v", e0)

	c00, c10, c01, c11 := make_test_qoi(t, join_path(assets_root, "demo.qoi"), 4, 4)

	s1, e1 := import_all(assets_root, library_root)
	testing.expectf(t, e1 == .None && s1.imported == 1, "导入: %v", e1)

	// manifest blob 应作为保留 GUID 的 Raw blob 落在 Library 里
	name_buf: [37]u8
	mname, _ := guid_filename(GUID_MANIFEST, name_buf[:])
	testing.expectf(t, os.exists(join_path(library_root, mname)), "manifest blob 应存在于 Library")

	// ---- 模拟打包：删掉源 Assets 目录，运行时只有 Library ----
	// （"包"就是原 Library；源目录从配置中拿掉，assets_root 留空）
	e4 := remove_tree(assets_root)
	testing.expectf(t, e4 == nil, "删 Assets: %v", e4)

	// 打包形态加载：assets_root 为空，.meta 回退不可用，只能靠 manifest
	m: Asset_Manager
	e5 := assets_init(&m, Asset_Manager_Config{
		assets_root  = "",
		library_root = library_root,
	})
	testing.expectf(t, e5 == .None, "assets_init: %v", e5)
	defer assets_dispose(&m)

	h, e6 := assets_load_path(&m, "demo.qoi")
	testing.expectf(t, e6 == .None, "打包形态 load_path 应走 manifest: %v", e6)
	image := assets_get_image(&m, h)
	if testing.expectf(t, image != nil, "打包形态应拿到 CPU Image") {
		testing.expect(t, image.Width == 4 && image.Height == 4)
		testing.expect(t, image.Pixels[0] == c00)
		testing.expect(t, image.Pixels[3] == c10)
		testing.expect(t, image.Pixels[12] == c01)
		testing.expect(t, image.Pixels[15] == c11)
	}

	// manifest 里不存在的路径：没有 .meta 回退时应报错而非崩溃
	_, e7 := assets_load_path(&m, "nope.qoi")
	testing.expectf(t, e7 != .None, "未知路径应报错: %v", e7)
}
