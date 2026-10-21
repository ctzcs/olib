#+build !js
package dev

// .oshader 候选包的所有权与后台监听；GPU 验证成功后由调用方整体提交。
import "base:intrinsics"
import "base:runtime"
import "core:path/filepath"
import "core:strings"
import "core:thread"

import sh "olib:kit/rendering/shader"

Parameter_Build :: struct {
	schemas: []sh.Schema,
	effects: []sh.Shader_Desc,
	programs: []Parameter_Program,
	error: string,
}

parameter_build_dispose :: proc(b: ^Parameter_Build) {
	context.allocator = runtime.heap_allocator()
	for &s in b.schemas do sh.schema_dispose(&s)
	delete(b.schemas)
	for &e in b.effects do sh.shader_dispose(&e)
	delete(b.effects)
	for program in b.programs {
		delete(program.group)
		delete(program.source)
		delete(program.text)
	}
	delete(b.programs)
	delete(b.error)
	b^ = {}
}

// ==============================================================================
// 后台监听：结果由主线程 take，始终只有一个包生成任务
// ==============================================================================

Parameter_Watch :: struct {
	source_directory: string,
	status: Status,
	diagnostic: string,
	worker: ^thread.Thread,
	job: Parameter_Job,
	observed, attempted: u64,
	has_observed, has_attempted: bool,
	poll, stable: f64,
}

@(private)
Parameter_Job :: struct {
	source_directory: string,
	fingerprint: u64,
	result: Parameter_Build,
	done: bool,
}

parameters_init :: proc(w: ^Parameter_Watch, source_directory: string) {
	context.allocator = runtime.heap_allocator()
	w^ = {}
	w.source_directory, _ = filepath.abs(source_directory)
}

parameters_dispose :: proc(w: ^Parameter_Watch) {
	context.allocator = runtime.heap_allocator()
	if w.worker != nil {
		thread.join(w.worker)
		thread.destroy(w.worker)
	}
	parameter_build_dispose(&w.job.result)
	delete(w.source_directory)
	delete(w.diagnostic)
	w^ = {}
}

@(private)
parameter_worker :: proc(t: ^thread.Thread) {
	j := cast(^Parameter_Job)t.data
	j.result = parameters_compile(j.source_directory)
	intrinsics.atomic_store(&j.done, true)
}

parameters_update :: proc(w: ^Parameter_Watch, dt: f64) {
	context.allocator = runtime.heap_allocator()
	w.poll += dt
	w.stable += dt
	if w.poll < 0.25 do return
	w.poll = 0
	hash, ok := parameters_fingerprint(w.source_directory)
	if !ok {
		w.has_attempted = false
		w.status = .Error
		delete(w.diagnostic)
		w.diagnostic = strings.clone("Cannot read shader declaration directories")
		return
	}
	if !w.has_observed || hash != w.observed {
		w.observed = hash
		w.has_observed = true
		w.stable = 0
	}
	if w.worker != nil {
		if !intrinsics.atomic_load(&w.job.done) do return
		thread.join(w.worker)
		thread.destroy(w.worker)
		w.worker = nil
		if w.job.fingerprint != hash {
			parameter_build_dispose(&w.job.result)
		} else {
			delete(w.diagnostic)
			w.diagnostic = strings.clone(w.job.result.error)
			w.status = w.diagnostic == "" ? .Ready : .Error
		}
	}
	if w.stable < 0.25 || (w.has_attempted && w.attempted == hash) do return
	parameter_build_dispose(&w.job.result)
	w.job = {source_directory = w.source_directory, fingerprint = hash}
	w.worker = thread.create(parameter_worker)
	if w.worker == nil do return
	w.worker.data = &w.job
	w.attempted = hash
	w.has_attempted = true
	w.status = .Compiling
	thread.start(w.worker)
}

parameters_take :: proc(w: ^Parameter_Watch) -> Parameter_Build {
	if w.status != .Ready do return {}
	current, ok := parameters_fingerprint(w.source_directory)
	if !ok || current != w.job.fingerprint do return {}
	result := w.job.result
	w.job.result = {}
	w.status = .Live
	return result
}
