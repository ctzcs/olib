#+build !js
package hotreload

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// 分区：会话 / 生命周期 / 候选提交 / 帧分发 / 内部资源管理。

State_Policy :: enum {
	Compatible, // state_version 不同则拒绝；默认不会静默丢失当前局面。
	Migrate,    // 把旧快照交给新模块，由 load 明确接受或拒绝。
	Reset,      // 不保存旧状态，明确启动新局。
}

Result :: enum {
	Success,
	Not_Initialized,
	Busy,
	File_Error,
	Library_Error,
	Invalid_API,
	Host_Mismatch,
	State_Mismatch,
	Snapshot_Error,
	Load_Rejected,
}

// 单一宿主线程操作；地址稳定，不复制。没有自动安装 Foster 回调。
// 每帧在上一帧绘制/任务结束、下一帧 update 之前 reload；回调内不得重入。
Session :: struct {
	host_version: u64,
	services: rawptr,
	allocator: runtime.Allocator,
	max_snapshot_bytes: int,
	revision: u64,
	diagnostic: string,
	initialized: bool,
	busy: bool,
	live: Module,
}

@(private)
Module :: struct {
	library: dynlib.Library,
	path: string,
	api: API,
	instance: rawptr,
	load_called: bool,
}

init :: proc(s: ^Session, host_version: u64, services: rawptr = nil,
	max_snapshot_bytes: int = 64 * 1024 * 1024, allocator := context.allocator) -> bool {
	if s.initialized || host_version == 0 || max_snapshot_bytes < 0 do return false
	s^ = {host_version = host_version, services = services, allocator = allocator,
		max_snapshot_bytes = max_snapshot_bytes, initialized = true}
	return true
}

// 返回 false 表示正在回调中，调用方应在帧外重试。
dispose :: proc(s: ^Session) -> bool {
	if s.busy do return false
	if !s.initialized do return true
	s.busy = true
	module_dispose(s, &s.live)
	delete(s.diagnostic, s.allocator)
	s^ = {}
	return true
}

is_live :: proc(s: ^Session) -> bool {
	return s.live.library != nil
}

// source 必须是已完整编译、不会继续写入的产物。复制到同目录独立文件，
// 避免 Windows 锁住编译输出；原文件与同目录依赖均不归会话所有。
// 候选 API/快照/load 失败均保留旧模块；不隔离崩溃或模块擅自修改宿主的副作用。
reload :: proc(s: ^Session, source: string, policy: State_Policy = .Compatible) -> Result {
	if !s.initialized do return .Not_Initialized
	if s.busy do return .Busy
	s.busy = true
	defer s.busy = false
	context.allocator = s.allocator
	candidate: Module
	defer module_dispose(s, &candidate)
	absolute, path_err := filepath.abs(source)
	if path_err != nil do return fail(s, .File_Error, "Cannot resolve module path")
	defer delete(absolute)
	f, create_err := os.create_temp_file(filepath.dir(absolute),
		fmt.tprintf(".olib-reload-*.%s", dynlib.LIBRARY_FILE_EXTENSION))
	if create_err != nil do return fail(s, .File_Error, "Cannot create module shadow copy")
	candidate.path = strings.clone(os.name(f))
	os.close(f)
	if err := os.copy_file(candidate.path, absolute); err != nil {
		return fail(s, .File_Error, fmt.tprintf("Cannot copy module: %v", err))
	}
	library, loaded := dynlib.load_library(candidate.path)
	if !loaded do return fail(s, .Library_Error, dynlib.last_error())
	candidate.library = library
	address, found := dynlib.symbol_address(library, ENTRY_SYMBOL)
	if !found do return fail(s, .Invalid_API, "Missing olib_game_api export")
	get_api := cast(Get_API)address
	if !get_api(API_VERSION, size_of(API), &candidate.api) || !api_valid(candidate.api) {
		return fail(s, .Invalid_API, "Module protocol or required callbacks are invalid")
	}
	if candidate.api.host_version != s.host_version {
		return fail(s, .Host_Mismatch, "Host ABI changed; rebuild and restart host")
	}
	if is_live(s) && policy == .Compatible &&
		candidate.api.state_version != s.live.api.state_version {
		return fail(s, .State_Mismatch, "State format changed; explicitly migrate or reset")
	}
	callback_context := context
	old_call := Call{host_context = &callback_context, services = s.services,
		instance = s.live.instance}
	snapshot: Snapshot
	defer delete(snapshot.data, s.allocator)
	if is_live(s) && policy != .Reset {
		n := s.live.api.snapshot_size(&old_call)
		if n < 0 || n > s.max_snapshot_bytes {
			return fail(s, .Snapshot_Error, "Snapshot size is invalid or exceeds configured limit")
		}
		data, err := make([]u8, n, s.allocator)
		if err != .None do return fail(s, .Snapshot_Error, "Cannot allocate snapshot")
		snapshot.data = data
		snapshot.version = s.live.api.state_version
		if !s.live.api.save(&old_call, snapshot.data) {
			return fail(s, .Snapshot_Error, "Old module could not serialize state")
		}
	}
	new_call := Call{host_context = &callback_context, services = s.services}
	candidate.load_called = true
	accepted := candidate.api.load(&new_call, snapshot)
	candidate.instance = new_call.instance
	if !accepted do return fail(s, .Load_Rejected, "Candidate rejected state or initialization failed")
	// 旧状态一直保留到新状态完整建立；旧模块清理仍在旧代码有效时执行。
	module_dispose(s, &s.live)
	s.live = candidate
	candidate = {}
	s.revision += 1
	if s.live.api.activate != nil do s.live.api.activate(&new_call)
	delete(s.diagnostic, s.allocator)
	s.diagnostic = ""
	return .Success
}

update :: proc(s: ^Session, dt: f64, frame: rawptr = nil) {
	dispatch(s, false, dt, frame)
}

render :: proc(s: ^Session, dt: f64, frame: rawptr = nil) {
	dispatch(s, true, dt, frame)
}

@(private)
dispatch :: proc(s: ^Session, rendering: bool, dt: f64, frame: rawptr) {
	if !is_live(s) || s.busy do return
	s.busy = true
	defer s.busy = false
	callback_context := context
	callback_context.allocator = s.allocator
	call := Call{host_context = &callback_context, services = s.services,
		instance = s.live.instance, frame = frame}
	callback := rendering ? s.live.api.render : s.live.api.update
	if callback != nil do callback(&call, dt)
}

@(private)
api_valid :: proc(api: API) -> bool {
	return api.state_version != 0 && api.load != nil && api.unload != nil &&
		api.snapshot_size != nil && api.save != nil && api.update != nil && api.render != nil
}

@(private)
module_dispose :: proc(s: ^Session, m: ^Module) {
	callback_context := context
	callback_context.allocator = s.allocator
	if m.load_called {
		call := Call{host_context = &callback_context, services = s.services, instance = m.instance}
		m.api.unload(&call)
	}
	if m.library != nil do dynlib.unload_library(m.library)
	if m.path != "" {
		// 卸载失败时 Windows 会保留锁定文件，不强删用户目录或依赖。
		_ = os.remove(m.path)
		delete(m.path, s.allocator)
	}
	m^ = {}
}

@(private)
fail :: proc(s: ^Session, result: Result, message: string) -> Result {
	delete(s.diagnostic, s.allocator)
	s.diagnostic = strings.clone(message, s.allocator)
	return result
}
