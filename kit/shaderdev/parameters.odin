#+build !js
package shaderdev

// 分区：包发现与单程序生成 / 后台监听。
// Odin 包只用于生成描述，不载入 DLL；调用方在 shader.apply 成功后提交对应描述。
import "base:intrinsics"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"

import mat "olib:kit/material"

Parameter_Build :: struct {
	schemas: []mat.Schema,
	effects: []mat.Effect_Desc,
	error: string,
}

parameter_build_dispose :: proc(b: ^Parameter_Build) {
	context.allocator = runtime.heap_allocator()
	for &s in b.schemas do mat.schema_dispose(&s)
	delete(b.schemas)
	for &e in b.effects do mat.effect_dispose(&e)
	delete(b.effects)
	delete(b.error)
	b^ = {}
}

// 保留 IDE 可读取的生成头文件。每组独立目录，内容不变不写盘；失败保留旧文件。
// root 由宿主指定，通常是项目的 library/shader_dev。返回错误使用调用方 allocator。
parameters_write_headers :: proc(schemas: []mat.Schema, root: string) -> string {
	for schema in schemas {
		if schema.name == "" || schema.name == "." || schema.name == ".." ||
			strings.contains_any(schema.name, "/\\:") {
			return fmt.aprintf("Invalid generated header group: %s", schema.name)
		}
		directory := fmt.tprintf("%s/%s", root, schema.name)
		path := fmt.tprintf("%s/params.generated.hlsli", directory)
		header := mat.hlsl(schema)
		defer delete(header)
		previous, read_err := os.read_entire_file(path, context.temp_allocator)
		if read_err == nil && string(previous) == header do continue
		if err := os.make_directory_all(directory); err != nil {
			return fmt.aprintf("Cannot create generated header directory %s: %v", directory, err)
		}
		staging, create_err := os.make_directory_temp(directory, ".params_*", context.temp_allocator)
		if create_err != nil do return fmt.aprintf("Cannot stage generated header: %v", create_err)
		temporary := fmt.tprintf("%s/header.hlsli", staging)
		defer {
			_ = os.remove(temporary)
			_ = os.remove(staging)
		}
		if err := os.write_entire_file(temporary, header); err != nil {
			return fmt.aprintf("Cannot write generated header %s: %v", path, err)
		}
		if err := os.rename(temporary, path); err != nil {
			return fmt.aprintf("Cannot replace generated header %s: %v", path, err)
		}
	}
	return ""
}

// AST 只找顶层 *_Params 名字；类型、标签、默认值表达式均交给 Odin 编译器。
parameter_names :: proc(directory: string) -> (names: []string, declarations: map[string]bool, error: string) {
	diagnostic: strings.Builder
	strings.builder_init(&diagnostic)
	context.user_ptr = &diagnostic
	p := parser.default_parser()
	p.err = proc(pos: tokenizer.Pos, message: string, args: ..any) {
		b := cast(^strings.Builder)context.user_ptr
		fmt.sbprintf(b, "%s:%d:%d: ", pos.file, pos.line, pos.column)
		fmt.sbprintf(b, message, ..args)
		strings.write_string(b, "\n")
	}
	pkg, ok := parser.parse_package_from_path(directory, &p)
	if !ok || p.error_count != 0 {
		if strings.to_string(diagnostic) == "" do strings.write_string(&diagnostic, "Cannot parse Odin parameter package")
		return nil, nil, strings.to_string(diagnostic)
	}
	result: [dynamic]string
	declarations = make(map[string]bool)
	for _, file in pkg.files {
		for stmt in file.decls {
			decl, is_decl := stmt.derived_stmt.(^ast.Value_Decl)
			if !is_decl do continue
			for expr in decl.names {
				ident, is_ident := expr.derived_expr.(^ast.Ident)
				if is_ident do declarations[ident.name] = true
				if is_ident && strings.has_suffix(ident.name, "_Params") {
					append(&result, strings.trim_suffix(ident.name, "_Params"))
				}
			}
		}
	}
	slice.sort(result[:])
	if len(result) == 0 do return nil, nil, "No top-level *_Params declarations found"
	return result[:], declarations, ""
}

// 整个参数包只编译一次；独占临时工作目录，退出清理，用户源码不会被生成器覆盖。
parameters_compile :: proc(directory: string) -> (result: Parameter_Build) {
	context.allocator = runtime.heap_allocator()
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)
	context.temp_allocator = context.allocator
	workspace, err := os.make_directory_temp("", "olib_params_*", context.allocator)
	if err != nil {
		result.error = strings.clone("Cannot create parameter generation workspace", runtime.heap_allocator())
		return
	}
	defer remove_workspace(workspace)
	input := fmt.tprintf("%s/params", workspace)
	_ = os.make_directory(input)
	entries, read_err := os.read_all_directory_by_path(directory, context.allocator)
	if read_err != nil {
		result.error = strings.clone("Cannot read parameter package", runtime.heap_allocator())
		return
	}
	for entry in entries {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") || strings.has_suffix(entry.name, "_test.odin") do continue
		data, file_err := os.read_entire_file(entry.fullpath, context.allocator)
		if file_err != nil || os.write_entire_file(fmt.tprintf("%s/%s", input, entry.name), data) != nil {
			result.error = strings.clone("Cannot snapshot parameter package", runtime.heap_allocator())
			return
		}
	}
	names, declarations, error := parameter_names(input)
	if error != "" {
		result.error = strings.clone(error, runtime.heap_allocator())
		return
	}
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "package main\nimport p \"params\"\nimport gen \"olib:kit/shaderdev/paramgen\"\nimport mat \"olib:kit/material\"\nmain :: proc() {\n schemas: [dynamic]mat.Schema\n")
	for name in names {
		strings.write_string(&b, " {\n preview := \"2d\"\n")
		if declarations[fmt.tprintf("%s_Preview", name)] {
			fmt.sbprintf(&b, " preview = gen.preview_name(p.%s_Preview)\n", name)
		}
		fmt.sbprintf(&b, " defaults: p.%s_Params\n", name)
		lower := strings.to_lower(name)
		if declarations[fmt.tprintf("%s_defaults", lower)] {
			fmt.sbprintf(&b, " defaults = p.%s_defaults()\n", lower)
		}
		label := declarations[fmt.tprintf("%s_Label", name)] ? fmt.tprintf("p.%s_Label", name) : "\"\""
		folder := declarations[fmt.tprintf("%s_Folder", name)] ? fmt.tprintf("p.%s_Folder", name) : "\"\""
		fmt.sbprintf(&b, " gen.add(&schemas, \"%s\", p.%s_Shader, preview, defaults, %s, %s)\n", name, name, label, folder)
		strings.write_string(&b, " }\n")
	}
	strings.write_string(&b, " effects: [dynamic]mat.Effect_Desc\n")
	effect_names: [dynamic]string
	for name in declarations {
		if strings.has_suffix(name, "_Passes") do append(&effect_names, strings.trim_suffix(name, "_Passes"))
	}
	slice.sort(effect_names[:])
	for name in effect_names {
		label := declarations[fmt.tprintf("%s_Label", name)] ? fmt.tprintf("p.%s_Label", name) : "\"\""
		preview := declarations[fmt.tprintf("%s_Preview", name)] ? fmt.tprintf("gen.preview_name(p.%s_Preview)", name) : "\"\""
		fmt.sbprintf(&b, " gen.add_effect(&effects, \"%s\", p.%s_Passes[:], p.%s_Output, schemas[:], %s, %s)\n", name, name, name, label, preview)
	}
	strings.write_string(&b, " gen.write(schemas[:], effects[:])\n}\n")
	if os.write_entire_file(fmt.tprintf("%s/main.odin", workspace), strings.to_string(b)) != nil {
		result.error = strings.clone("Cannot write parameter generator", runtime.heap_allocator())
		return
	}
	root, _ := filepath.abs(#directory + "/../..")
	exe := fmt.tprintf("%s/shader_params%s", workspace, ODIN_OS == .Windows ? ".exe" : "")
	output := fmt.tprintf("%s/parameters.json", workspace)
	commands := [2][]string{
		{"odin", "build", workspace, fmt.tprintf("-collection:olib=%s", root), fmt.tprintf("-out:%s", exe)},
		{exe, output},
	}
	for command in commands {
		sync.mutex_lock(&compiler_mutex)
		state, stdout, stderr, exec_err := os.process_exec({command = command}, context.allocator)
		sync.mutex_unlock(&compiler_mutex)
		if exec_err != nil || !state.exited || state.exit_code != 0 {
			context.allocator = runtime.heap_allocator()
			result.error = fmt.aprintf("Parameter generator failed (%v, exit %d)\n%s%s", exec_err,
				state.exit_code, string(stdout), string(stderr))
			return
		}
	}
	data, data_err := os.read_entire_file(output, context.allocator)
	decoded: struct {schemas: []mat.Schema, effects: []mat.Effect_Desc}
	if data_err != nil || json.unmarshal(data, &decoded) != nil {
		result.error = strings.clone("Cannot decode generated parameters", runtime.heap_allocator())
		return
	}
	context.allocator = runtime.heap_allocator()
	result.schemas = make([]mat.Schema, len(decoded.schemas))
	for s, i in decoded.schemas do result.schemas[i] = mat.schema_clone(s)
	result.effects = make([]mat.Effect_Desc, len(decoded.effects))
	for e, i in decoded.effects do result.effects[i] = mat.effect_clone(e)
	return
}

// ==============================================================================
// 后台监听：结果由主线程 take，始终只有一个包生成任务
// ==============================================================================

Parameter_Watch :: struct {
	directory: string,
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
	directory: string,
	fingerprint: u64,
	result: Parameter_Build,
	done: bool,
}

parameters_init :: proc(w: ^Parameter_Watch, directory: string) {
	context.allocator = runtime.heap_allocator()
	w^ = {}
	w.directory, _ = filepath.abs(directory)
}

parameters_dispose :: proc(w: ^Parameter_Watch) {
	context.allocator = runtime.heap_allocator()
	if w.worker != nil {
		thread.join(w.worker)
		thread.destroy(w.worker)
	}
	parameter_build_dispose(&w.job.result)
	delete(w.directory)
	delete(w.diagnostic)
	w^ = {}
}

parameters_fingerprint :: proc(directory: string) -> (hash: u64, ok: bool) {
	entries, err := os.read_all_directory_by_path(directory, context.temp_allocator)
	if err != nil do return 0, false
	paths := make([dynamic]string, 0, len(entries), context.temp_allocator)
	for e in entries {
		if e.type == .Regular && strings.has_suffix(e.name, ".odin") && !strings.has_suffix(e.name, "_test.odin") {
			append(&paths, e.fullpath)
		}
	}
	slice.sort(paths[:])
	hash = 1469598103934665603
	for path in paths {
		data, file_err := os.read_entire_file(path, context.temp_allocator)
		if file_err != nil do return 0, false
		for b in transmute([]u8)path do hash = (hash ~ u64(b))*1099511628211
		for b in data do hash = (hash ~ u64(b))*1099511628211
		hash = (hash ~ u64(len(data)))*1099511628211
	}
	return hash, true
}

@(private)
parameter_worker :: proc(t: ^thread.Thread) {
	j := cast(^Parameter_Job)t.data
	j.result = parameters_compile(j.directory)
	intrinsics.atomic_store(&j.done, true)
}

parameters_update :: proc(w: ^Parameter_Watch, dt: f64) {
	context.allocator = runtime.heap_allocator()
	w.poll += dt
	w.stable += dt
	if w.poll < 0.25 do return
	w.poll = 0
	hash, ok := parameters_fingerprint(w.directory)
	if !ok {
		w.has_attempted = false
		w.status = .Error
		delete(w.diagnostic)
		w.diagnostic = strings.clone("Cannot read Odin parameter directory")
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
	w.job = {directory = w.directory, fingerprint = hash}
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
	current, ok := parameters_fingerprint(w.directory)
	if !ok || current != w.job.fingerprint do return {}
	result := w.job.result
	w.job.result = {}
	w.status = .Live
	return result
}
