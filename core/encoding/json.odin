// encoding:json —— JSON 序列化工具（编辑器可用）。
//
// 双向加载/保存，支持 Value 树和 struct 两种形态。
//
// 典型编辑器工作流（地图/存档，Value 树 + arena）：
//
//	arena_buf := make([]byte, N); defer delete(arena_buf)
//	arena: mem.Arena; mem.arena_init(&arena, arena_buf)
//	root, err := encoding.json_load("maps/level1.json", mem.arena_allocator(&arena))
//	// ... 编辑 root（json.Object / json.Array 等 union 分支，字面量键/值都安全）...
//	encoding.json_save("maps/level1.json", root)   // 写回，pretty 默认开
//	// arena 随 arena_buf 释放而整体回收，无需逐个 destroy
//
// 类型化配置/存档工作流：
//
//	cfg: Game_Save
//	encoding.json_load_struct("save/save1.json", &cfg)
//	// ... 游戏运行，修改 cfg ...
//	encoding.json_save_struct("save/save1.json", &cfg)
//
// 分区：
//   Value 树 API —— 编辑器场景（结构可能动态/含任意字段）
//   Struct API —— 类型化配置/存档场景
package encoding

import "core:encoding/json"
import "core:os"
import "core:strings"

Json_Error :: enum {
	None,
	File_Not_Found,
	Parse_Error,
	Write_Error,
}

// 默认序列化选项：标准 JSON、pretty、4 空格缩进（编辑器人工可读/diff 友好）。
DEFAULT_MARSHAL_OPT :: json.Marshal_Options{
	spec       = .JSON,
	pretty     = true,
	use_spaces = true,
	spaces     = 4,
}

// ------------------------------------------------------------------------------
// Value 树 API —— 编辑器场景
// ------------------------------------------------------------------------------

// 把 JSON 文件解析为 Value 树。
// allocator 推荐传 arena（编辑器场景），释放时 arena_destroy 即可。
json_load :: proc(path: string, allocator := context.allocator) -> (json.Value, Json_Error) {
	data, os_err := os.read_entire_file_from_path(path, allocator)
	if os_err != nil do return json.Value{}, .File_Not_Found
	defer delete(data)

	value, jerr := json.parse(data, parse_integers = true, allocator = allocator)
	if jerr != .None do return json.Value{}, .Parse_Error
	return value, .None
}

// 把 Value 树写回文件。pretty 默认开启。
json_save :: proc(path: string, root: json.Value, opt := DEFAULT_MARSHAL_OPT) -> Json_Error {
	data, merr := json.marshal(root, opt)
	if merr != nil do return .Write_Error
	defer delete(data)

	if os.write_entire_file_from_string(path, string(data)) != nil do return .Write_Error
	return .None
}

// 释放 Value 树（递归释放内部 Object/Array/String 的分配）。
//
// 所有权：只适用于"全树都由 json_load 在堆上解析、未混入字面量"的纯场景。
// 编辑器场景建议用 arena 装载（字面量键/值都安全），整体 arena_destroy 回收，
// 不要调本 proc。
json_destroy_value :: proc(v: json.Value) {
	json.destroy_value(v)
}

// 构造辅助（编辑器往树里塞值时用）。
// 直接用字符串字面量构造 json.String 会在 destroy_value 时崩溃
// （字面量是静态内存，不能 free）；用本 proc 克隆到堆。
json_string :: proc(s: string) -> json.String {
	return json.String(strings.clone(s, context.allocator))
}

// ------------------------------------------------------------------------------
// Struct API —— 类型化配置/存档场景
// ------------------------------------------------------------------------------

// JSON 文件 -> struct。struct 自身持有数据；其内部动态分配由调用方管理。
json_load_struct :: proc(path: string, ptr: ^$T) -> Json_Error {
	data, os_err := os.read_entire_file_from_path(path, context.allocator)
	if os_err != nil do return .File_Not_Found
	defer delete(data)

	if json.unmarshal(data, ptr) != nil do return .Parse_Error
	return .None
}

// struct -> JSON 文件。pretty 默认开启。
json_save_struct :: proc(path: string, ptr: ^$T, opt := DEFAULT_MARSHAL_OPT) -> Json_Error {
	data, merr := json.marshal(ptr^, opt)
	if merr != nil do return .Write_Error
	defer delete(data)

	if os.write_entire_file_from_string(path, string(data)) != nil do return .Write_Error
	return .None
}
