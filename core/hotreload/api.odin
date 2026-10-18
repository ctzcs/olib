// 开发期游戏模块协议。宿主与模块必须使用相同 Odin、架构和本协议源码。
// 不提供跨编译器 ABI；宿主接口变化必须升级 host_version 并重启。
package hotreload

import "base:runtime"

// 分区：协议版本 / 调用上下文与快照 / 模块入口。

API_VERSION :: u32(1)
ENTRY_SYMBOL :: "olib_game_api"

// 只在当前回调内借用；模块不得保存 host_context 或 frame。
// instance 是模块私有世界/UI，可含动态数组；宿主不解释也不跨版本复制它。
// services 由宿主持有，允许指向含 ^foster.App 的游戏自定义结构。
Call :: struct {
	host_context: ^runtime.Context,
	services: rawptr,
	instance: rawptr,
	frame: rawptr,
}

// data 仅在 load 调用期间有效。version=0 表示首次启动或明确要求重置。
// 快照必须自包含，不得包含指针、proc、any、typeid、分配器或 GPU 资源。
Snapshot :: struct {
	data: []u8,
	version: u64,
}

// load 只创建私有候选状态；失败也会调用 unload，须支持部分初始化。
// activate 在提交后调用，才可注册宿主回调/启动任务；它不得失败。
// unload 必须注销回调、停止并 join 任务、释放所有私有资源。
// snapshot_size/save 必须只读；save 恰好写入所声明长度，不得保留输出地址。
// 所有 "c" 回调先执行 context = call.host_context^。
API :: struct {
	host_version: u64,
	state_version: u64,
	load: proc "c" (call: ^Call, snapshot: Snapshot) -> bool,
	unload: proc "c" (call: ^Call),
	activate: proc "c" (call: ^Call),
	snapshot_size: proc "c" (call: ^Call) -> int,
	save: proc "c" (call: ^Call, destination: []u8) -> bool,
	update: proc "c" (call: ^Call, dt: f64),
	render: proc "c" (call: ^Call, dt: f64),
}

// 导出名必须为 ENTRY_SYMBOL。先校验 version/size，再写出 API；不能产生副作用。
Get_API :: proc "c" (version: u32, size: int, api: ^API) -> bool
