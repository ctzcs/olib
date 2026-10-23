#+build !js
package hotreload

import "base:intrinsics"
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"
import "core:time"

import "olib:core/devbuild"

// 分区：监听配置与状态 / 生命周期 / 每帧状态机（Auto、Manual）/ 后台编译 / 主线程提交。
// 文件扫描在 scan.odin 的后台线程里进行，主线程每帧只读取结果。

Build_Status :: enum {
	Waiting,
	Compiling,
	Ready,
	Live,
	Error,
}

Watch_Mode :: enum {
	Auto, // 后台线程增量扫描 roots，保存后自动编译
	Manual, // 不扫描源码：启动时编译一次，之后由 watch_retry 或 trigger_file 触发
}

Watch_Config :: struct {
	// 参数数组，不经过 shell；至少一个参数含 {output}，如 -out:{output}。
	command: []string,
	working_directory: string,
	// 显式列出游戏代码/共享定义/#load 资产所在目录或文件；不自动解析 import。Manual 可以为空。
	roots: []string,
	extensions: []string, // 空时只监听 .odin；显式文件不受扩展名过滤。
	cache_parent: string, // 空时使用系统临时目录；目录内依赖须由宿主/系统解决。
	poll_seconds: f64, // 后台扫描与触发文件的检查间隔；<=0 使用 0.25 秒。
	debounce_seconds: f64, // <=0 使用 0.25 秒。
	mode: Watch_Mode,
	// Manual：修改时间变化即触发编译，供编辑器任务或脚本使用；按 working_directory 解析，空为不用。
	trigger_file: string,
}

// 必须在常驻宿主中创建，地址稳定。只允许一个线程调用公开接口。
// 后台线程只扫描文件和编译，不调用模块/UI/GPU。持久内存固定使用宿主 heap_allocator。
Watch :: struct {
	status: Build_Status,
	diagnostic: string,
	initialized: bool,
	mode: Watch_Mode,
	command, roots, extensions: []string,
	working_directory, cache, trigger_file: string,
	poll_seconds, debounce_seconds: f64,
	poll, stable: f64,
	observed, attempted: u64,
	has_observed, has_attempted: bool,
	build_invalidated: bool,
	verifying: bool, // 编译已结束，等待一次在其后开始的完整扫描确认源码未变
	verify_ticket: u64,
	pending: bool, // Manual：已请求编译
	trigger_modified: i64,
	generation: u64,
	worker: ^thread.Thread,
	job: Build_Job,
	scanner: Scanner,
}

@(private)
Build_Job :: struct {
	command: []string,
	working_directory, output: string,
	fingerprint: u64,
	diagnostic: string,
	succeeded, done: bool,
}

@(private)
WATCH_UNREADABLE :: "Cannot read watched sources; live module retained"

watch_init :: proc(w: ^Watch, config: Watch_Config) -> bool {
	if w.initialized do return false
	context.allocator = runtime.heap_allocator()
	w^ = {}
	if len(config.command) == 0 || (config.mode == .Auto && len(config.roots) == 0) do return false
	has_output := false
	for arg in config.command do has_output = has_output || strings.contains(arg, "{output}")
	if !has_output do return false
	w.initialized = true
	success := false
	defer if !success do watch_dispose(w)
	w.mode = config.mode
	w.command = clone_strings(config.command)
	w.extensions = clone_strings(len(config.extensions) == 0 ? []string{".odin"} : config.extensions)
	work := config.working_directory == "" ? "." : config.working_directory
	wd, wd_err := filepath.abs(work)
	if wd_err != nil do return false
	w.working_directory = wd
	w.roots = make([]string, len(config.roots))
	for root, i in config.roots {
		w.roots[i] = watch_path(wd, root) or_return
	}
	if config.trigger_file != "" {
		w.trigger_file = watch_path(wd, config.trigger_file) or_return
		// 已有的触发文件不算请求，只有之后的修改才触发。
		if entry, ok := scan_stat(w.trigger_file); ok do w.trigger_modified = entry.modified
	}
	cache, cache_err := os.make_directory_temp(config.cache_parent, "olib_hotreload_", context.allocator)
	if cache_err != nil do return false
	w.cache = cache
	w.poll_seconds = config.poll_seconds > 0 ? config.poll_seconds : 0.25
	w.debounce_seconds = config.debounce_seconds > 0 ? config.debounce_seconds : 0.25
	scan_init(&w.scanner, w.roots, w.extensions, time.Duration(w.poll_seconds * f64(time.Second)))
	if w.mode == .Auto && !scan_start(&w.scanner) do return false
	w.pending = w.mode == .Manual // 启动时还没有可运行的版本
	success = true
	return true
}

// 退出时停止扫描线程并等待正在运行的编译器完成；先 dispose Session，再 dispose Watch。
watch_dispose :: proc(w: ^Watch) {
	if !w.initialized do return
	context.allocator = runtime.heap_allocator()
	scan_destroy(&w.scanner)
	if w.worker != nil {
		thread.join(w.worker)
		thread.destroy(w.worker)
	}
	job_dispose(&w.job)
	delete_strings(w.command)
	delete_strings(w.roots)
	delete_strings(w.extensions)
	delete(w.working_directory)
	delete(w.trigger_file)
	delete(w.diagnostic)
	if w.cache != "" {
		// 只删除本会话创建的独占目录内的文件；不跟随链接或递归删除外部路径。
		entries, err := os.read_all_directory_by_path(w.cache, context.allocator)
		if err == nil {
			for e in entries {
				if e.type != .Directory do _ = os.remove(e.fullpath)
			}
			os.file_info_slice_delete(entries, context.allocator)
		}
		_ = os.remove(w.cache)
		delete(w.cache)
	}
	w^ = {}
}

// 编译当前源码：Auto 用于修好环境后重试，Manual 就是手动触发。
// 编译中调用时丢弃这次结果，结束后按最新源码再编。
watch_retry :: proc(w: ^Watch) {
	if !w.initialized do return
	w.has_attempted = false
	if w.mode == .Manual do w.pending = true
	if w.worker != nil do w.build_invalidated = true
}

// 同步得到一次完整扫描的指纹，供测试和工具使用；帧循环不要调用。
// Auto 请求后台扫描并阻塞到完成；Manual 没有扫描线程，在调用线程上扫描。
watch_fingerprint :: proc(w: ^Watch) -> (hash: u64, ok: bool) {
	context.allocator = runtime.heap_allocator()
	if w.scanner.thread != nil {
		ticket := scan_request(&w.scanner)
		for {
			latest := scan_result(&w.scanner)
			if latest.served >= ticket {
				if !latest.readable do return 0, false
				return latest.fingerprint, true
			}
			time.sleep(time.Millisecond)
		}
	}
	scan_sweep(&w.scanner)
	if !w.scanner.readable do return 0, false
	return scan_fingerprint(&w.scanner), true
}

// 每帧调用；只读取后台扫描结果和编译状态，不在调用线程上读文件。编译期间游戏继续运行。
// 失败版本只尝试一次，修改源码或 retry 后重试。
watch_update :: proc(w: ^Watch, dt: f64) {
	if !w.initialized do return
	context.allocator = runtime.heap_allocator()
	w.stable += max(dt, 0)
	if w.mode == .Manual {
		watch_update_manual(w, dt)
		return
	}
	latest := scan_result(&w.scanner)
	if latest.sweeps == 0 do return
	hash := latest.fingerprint
	readable := latest.readable
	if readable && (!w.has_observed || hash != w.observed) {
		w.observed = hash
		w.has_observed = true
		w.stable = 0
		if w.worker == nil && !w.verifying {
			w.status = .Waiting
			w.has_attempted = false
		}
	}
	if w.worker != nil {
		if !readable || hash != w.job.fingerprint do w.build_invalidated = true
		if !watch_join(w) do return
		// 编译结束后等一次在此之后开始的完整扫描，拒绝用过期源码编出的产物。
		w.verify_ticket = scan_request(&w.scanner)
		w.verifying = true
		return
	}
	if w.verifying {
		if latest.served < w.verify_ticket do return
		w.verifying = false
		if readable && hash == w.job.fingerprint && !w.build_invalidated {
			watch_diagnostic(w, w.job.diagnostic)
			w.status = w.job.succeeded ? .Ready : .Error
		} else {
			w.status = .Waiting
			w.has_attempted = false
		}
	}
	if w.status == .Ready && (!readable || hash != w.job.fingerprint) {
		w.status = .Waiting
		w.has_attempted = false
	}
	if !readable {
		w.has_observed = false
		w.has_attempted = false
		if w.status != .Error || w.diagnostic != WATCH_UNREADABLE {
			w.status = .Error
			watch_diagnostic(w, WATCH_UNREADABLE)
		}
		return
	}
	if w.stable < w.debounce_seconds || (w.has_attempted && w.attempted == hash) do return
	watch_start(w, hash)
}

// 与 reload 相同的帧边界要求。Auto 再核对最新扫描结果，拒绝编译期间或 Ready 之后过期的产物。
watch_apply :: proc(w: ^Watch, s: ^Session, policy: State_Policy = .Compatible) -> Result {
	if w.status != .Ready do return .Not_Initialized
	if w.mode == .Auto {
		latest := scan_result(&w.scanner)
		if !latest.readable || latest.fingerprint != w.job.fingerprint {
			w.status = .Waiting
			w.has_attempted = false
			return .Busy
		}
	}
	result := reload(s, w.job.output, policy)
	if result == .Busy do return result
	w.status = result == .Success ? .Live : .Error
	watch_diagnostic(w, s.diagnostic)
	return result
}

// Manual：只在请求时编译。触发文件按 poll_seconds 查询一次修改时间，不扫描源码。
@(private)
watch_update_manual :: proc(w: ^Watch, dt: f64) {
	w.poll += max(dt, 0)
	if w.trigger_file != "" && w.poll >= w.poll_seconds {
		w.poll = 0
		if entry, ok := scan_stat(w.trigger_file); ok && entry.modified != w.trigger_modified {
			w.trigger_modified = entry.modified
			watch_retry(w)
		}
	}
	if w.worker != nil {
		if !watch_join(w) do return
		if w.build_invalidated {
			w.status = .Waiting
		} else {
			watch_diagnostic(w, w.job.diagnostic)
			w.status = w.job.succeeded ? .Ready : .Error
		}
	}
	if !w.pending do return
	w.pending = false
	watch_start(w, 0)
}

// 编译线程结束时回收；返回是否已结束。
@(private)
watch_join :: proc(w: ^Watch) -> bool {
	if !intrinsics.atomic_load(&w.job.done) do return false
	thread.join(w.worker)
	thread.destroy(w.worker)
	w.worker = nil
	return true
}

// 按当前源码启动后台编译；fingerprint 是启动时的源码指纹（Manual 为 0）。
@(private)
watch_start :: proc(w: ^Watch, fingerprint: u64) {
	job_dispose(&w.job)
	w.generation += 1
	output := fmt.aprintf("%s/game_%d.%s", w.cache, w.generation, dynlib.LIBRARY_FILE_EXTENSION)
	w.job = {working_directory = w.working_directory, output = output, fingerprint = fingerprint}
	w.build_invalidated = false
	w.job.command = make([]string, len(w.command))
	for arg, i in w.command {
		expanded, allocated := strings.replace_all(arg, "{output}", output, context.allocator)
		w.job.command[i] = allocated ? expanded : strings.clone(expanded)
	}
	w.attempted = fingerprint
	w.has_attempted = true
	w.worker = thread.create(build_worker)
	if w.worker == nil {
		w.status = .Error
		watch_diagnostic(w, "Cannot create compiler worker")
		return
	}
	w.worker.data = &w.job
	w.status = .Compiling
	watch_diagnostic(w, "")
	thread.start(w.worker)
}

@(private)
build_worker :: proc(t: ^thread.Thread) {
	context.allocator = runtime.heap_allocator()
	j := cast(^Build_Job)t.data
	state, stdout, stderr, err := devbuild.exec(
		{command = j.command, working_dir = j.working_directory}, context.allocator)
	defer delete(stdout)
	defer delete(stderr)
	j.succeeded = err == nil && state.exited && state.exit_code == 0 && os.is_file(j.output)
	if !j.succeeded {
		j.diagnostic = fmt.aprintf("Game build failed (%v, exit %d)\n%s%s",
			err, state.exit_code, string(stdout), string(stderr))
	}
	intrinsics.atomic_store(&j.done, true)
}

@(private)
watch_path :: proc(working_directory, path: string) -> (absolute: string, ok: bool) {
	joined := path
	if !filepath.is_abs(joined) do joined = fmt.tprintf("%s/%s", working_directory, path)
	result, err := filepath.abs(joined)
	return result, err == nil
}

@(private)
clone_strings :: proc(values: []string) -> []string {
	result := make([]string, len(values))
	for value, i in values do result[i] = strings.clone(value)
	return result
}

@(private)
delete_strings :: proc(values: []string) {
	for value in values do delete(value)
	delete(values)
}

@(private)
job_dispose :: proc(j: ^Build_Job) {
	if j.output != "" {
		_ = os.remove(j.output)
		for extension in ([]string{".pdb", ".lib", ".exp"}) {
			sidecar := fmt.tprintf("%s/%s%s", filepath.dir(j.output), filepath.stem(j.output), extension)
			_ = os.remove(sidecar)
		}
	}
	delete(j.output)
	delete(j.diagnostic)
	delete_strings(j.command)
	j^ = {}
}

@(private)
watch_diagnostic :: proc(w: ^Watch, value: string) {
	delete(w.diagnostic, runtime.heap_allocator())
	w.diagnostic = strings.clone(value, runtime.heap_allocator())
}
