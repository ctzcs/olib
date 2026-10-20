#+build !js
// 开发专用 HLSL 热重载，2D/3D 共用。后台仅编译，GPU 替换由渲染线程提交。
package dev

import "base:intrinsics"
import "base:runtime"
import "core:path/filepath"
import "core:strings"
import "core:thread"

import foster "olib:foster"

// 分区：状态与生命周期 / 检测与编译 / 帧边界提交。

Status :: enum {
	Waiting,
	Compiling,
	Ready,
	Live,
	Error,
}

// Session 必须保持地址稳定；不要复制。init 后 dispose，退出时等待编译线程结束。
// 持有 shader 和字节码；material 借用 &vertex/&fragment，须先于 Session 释放。
Session :: struct {
	vertex, fragment: foster.Shader,
	status: Status,
	diagnostic: string,
	revision: u64,
	source: string,
	root: string,
	format: string,
	parameter_layout: bool,
	source_text: string,
	contract_revision: u64,
	expected: [2]Resources,
	live: Build,
	job: Job,
	worker: ^thread.Thread,
	observed: u64,
	attempted: u64,
	has_observed, has_attempted: bool,
	poll_elapsed, stable_elapsed: f64,
}

@(private)
Job :: struct {
	source, format: string,
	source_text: string,
	fingerprint: u64,
	result: Build,
	done: bool,
}

init :: proc(s: ^Session, source: string, driver: foster.GraphicsDriver,
	vertex_resources, fragment_resources: Resources) -> bool {
	context.allocator = runtime.heap_allocator()
	s^ = {}
	for resources in ([2]Resources{vertex_resources, fragment_resources}) {
		if resources.storage_textures != 0 || resources.storage_buffers < 0 ||
			resources.samplers < 0 || resources.samplers > 16 ||
			resources.uniform_buffers < 0 || resources.uniform_buffers > 8 {
			set_error(s, "Shader binding contract exceeds Foster graphics material support")
			return false
		}
	}
	#partial switch driver {
	case .Vulkan: s.format = "spv"
	case .D3D12: s.format = "dxil"
	case .Metal: s.format = "msl"
	case:
		set_error(s, "Shader development requires Vulkan, D3D12 or Metal")
		return false
	}
	path, err := filepath.abs(source)
	if err != nil {
		set_error(s, "Cannot resolve shader source path")
		return false
	}
	s.source = path
	s.root = strings.clone(filepath.dir(path))
	s.expected[0] = vertex_resources
	s.expected[1] = fragment_resources
	s.vertex.Stage = .Vertex
	s.fragment.Stage = .Fragment
	s.vertex.Name = "live vertex"
	s.fragment.Name = "live fragment"
	return true
}

dispose :: proc(s: ^Session) {
	context.allocator = runtime.heap_allocator()
	if s.worker != nil {
		thread.join(s.worker)
		thread.destroy(s.worker)
	}
	foster.ShaderDispose(&s.vertex)
	foster.ShaderDispose(&s.fragment)
	build_dispose(&s.live)
	build_dispose(&s.job.result)
	delete(s.job.source)
	delete(s.job.source_text)
	delete(s.source_text)
	delete(s.source)
	delete(s.root)
	delete(s.diagnostic)
	s^ = {}
}

// 重新尝试当前源码（如编译器安装完成后）；不丢弃有效画面。
retry :: proc(s: ^Session) {
	s.has_attempted = false
}

// 主线程每帧调用。250ms 检测、250ms 稳定期；任务完成前不读取其结果。
update :: proc(s: ^Session, dt: f64) {
	context.allocator = runtime.heap_allocator()
	if s.source == "" do return
	s.poll_elapsed += max(dt, 0)
	s.stable_elapsed += max(dt, 0)
	if s.poll_elapsed < 0.25 do return
	s.poll_elapsed = 0
	fingerprint, ok := session_fingerprint(s)
	if !ok {
		s.has_attempted = false
		set_error(s, "Cannot read shader sources; previous shader retained")
		return
	}
	if !s.has_observed || fingerprint != s.observed {
		s.observed = fingerprint
		s.has_observed = true
		s.stable_elapsed = 0
	}
	if s.worker != nil {
		if !intrinsics.atomic_load(&s.job.done) do return
		thread.join(s.worker)
		thread.destroy(s.worker)
		s.worker = nil
		if s.job.fingerprint != fingerprint {
			build_dispose(&s.job.result)
		} else if s.job.result.error != "" {
			set_error(s, s.job.result.error)
			build_dispose(&s.job.result)
		} else {
			s.status = .Ready
		}
	}
	if s.stable_elapsed < 0.25 || (s.has_attempted && s.attempted == fingerprint) do return
	build_dispose(&s.job.result)
	delete(s.job.source)
	delete(s.job.source_text)
	s.job = {source = strings.clone(s.source), format = s.format, source_text = strings.clone(s.source_text),
		fingerprint = fingerprint}
	s.worker = thread.create(compile_worker)
	if s.worker == nil {
		set_error(s, "Cannot start shader compiler thread")
		return
	}
	s.attempted = fingerprint
	s.has_attempted = true
	s.worker.data = &s.job
	s.status = .Compiling
	thread.start(s.worker)
}

@(private)
compile_worker :: proc(t: ^thread.Thread) {
	job := cast(^Job)t.data
	job.result = compile(job.source, job.format, job.source_text)
	intrinsics.atomic_store(&job.done, true)
}

// 在所有实际绘制和 Batcher 排队之前调用，probes 覆盖该 Shader 所有绘制配置。
// 成功后 shader 地址不变，uniform、纹理、相机和预览时间不会被重置。
apply :: proc(s: ^Session, device: ^foster.GraphicsDevice, probes: []foster.DrawCommand) -> bool {
	context.allocator = runtime.heap_allocator()
	if s.status != .Ready do return false
	current, readable := session_fingerprint(s)
	if !readable || current != s.job.fingerprint {
		build_dispose(&s.job.result)
		s.has_attempted = false
		s.status = .Waiting
		return false
	}
	for expected, i in s.expected {
		actual := s.job.result.resources[i]
		if (!s.parameter_layout && actual != expected) || (s.parameter_layout &&
			(actual.samplers > expected.samplers || actual.uniform_buffers > expected.uniform_buffers ||
			actual.storage_buffers > expected.storage_buffers || actual.storage_textures != expected.storage_textures)) {
			set_error(s, "Shader resource bindings changed; update the host contract and restart")
			build_dispose(&s.job.result)
			return false
		}
	}
	infos: [2]foster.ShaderCreateInfo
	for &info, i in infos {
		r := s.job.result.resources[i]
		// 反射报告使用数量；b0 被优化掉但 b1 仍被使用时，布局仍须保留两个槽。
		// storage buffer 同理：精灵没读轴和字段时被优化掉，宿主仍按约定绑定。
		// 同理，未使用的贴图不能使后续生成的 t/s 槽发生位移。
		if s.parameter_layout do r = s.expected[i]
		info = {
			Stage = i == 0 ? .Vertex : .Fragment,
			Code = s.job.result.code[i],
			EntryPoint = i == 0 ? "vertex_main" : "fragment_main",
			SamplerCount = r.samplers,
			UniformBufferCount = r.uniform_buffers,
			StorageBufferCount = r.storage_buffers,
		}
	}
	ok, error := foster.ShaderPairTryReplace(&s.vertex, &s.fragment, device,
		infos[0], infos[1], probes)
	if !ok {
		set_error(s, error)
		build_dispose(&s.job.result)
		return false
	}
	build_dispose(&s.live)
	s.live = s.job.result
	s.job.result = {}
	s.status = .Live
	s.revision += 1
	delete(s.diagnostic)
	s.diagnostic = ""
	return true
}

@(private)
set_error :: proc(s: ^Session, message: string) {
	delete(s.diagnostic)
	s.diagnostic = strings.clone(message)
	s.status = .Error
}

// 保留生成参数布局的全部槽，包括被编译器优化掉的字段。
configure_parameters :: proc(s: ^Session, textures: int) {
	s.parameter_layout = true
	s.contract_revision += 1
	s.status = .Waiting
	s.expected[1] = {samplers = textures, uniform_buffers = 2}
	s.has_attempted = false
}

@(private)
session_fingerprint :: proc(s: ^Session) -> (hash: u64, ok: bool) {
	hash, ok = source_fingerprint(s.root)
	for b in transmute([]u8)s.source do hash = (hash ~ u64(b))*1099511628211
	for b in transmute([]u8)s.source_text do hash = (hash ~ u64(b))*1099511628211
	hash = (hash ~ s.contract_revision)*1099511628211
	return
}
