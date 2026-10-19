#+test
package dev

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import foster "olib:foster"

@(test)
source_changes_include_same_length_and_deletion :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "olib_shaderdev_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	sub := fmt.tprintf("%s/include", root)
	file := fmt.tprintf("%s/math.hlsli", sub)
	ignored := fmt.tprintf("%s/notes.txt", root)
	defer {
		_ = os.remove(file)
		_ = os.remove(ignored)
		_ = os.remove(sub)
		_ = os.remove(root)
	}
	testing.expect(t, os.make_directory(sub) == nil)
	testing.expect(t, os.write_entire_file(file, string("AAA")) == nil)
	a, ok := source_fingerprint(root)
	testing.expect(t, ok)
	testing.expect(t, os.write_entire_file(file, string("BBB")) == nil)
	b, _ := source_fingerprint(root)
	testing.expect(t, a != b)
	testing.expect(t, os.write_entire_file(ignored, string("ignored")) == nil)
	c, _ := source_fingerprint(root)
	testing.expect(t, b == c)
	testing.expect(t, os.remove(file) == nil)
	d, _ := source_fingerprint(root)
	testing.expect(t, c != d)
}

@(test)
reject_stale_candidate_without_touching_live_state :: proc(t: ^testing.T) {
	s: Session
	testing.expect(t, init(&s, "missing/shader.hlsl", .Vulkan, {}, {}))
	defer dispose(&s)
	s.status = .Ready
	s.revision = 7
	s.has_attempted = true
	testing.expect(t, !apply(&s, nil, nil))
	testing.expect(t, s.status == .Waiting && s.revision == 7 && !s.has_attempted)
}

@(test)
safe_creation_reports_errors_without_gpu :: proc(t: ^testing.T) {
	shader: foster.Shader
	ok, error := foster.ShaderTryInit(&shader, nil, {})
	testing.expect(t, !ok && error != "" && shader.Resource == nil)
	s: Session
	testing.expect(t, !init(&s, "shader.hlsl", .None, {}, {}))
	defer dispose(&s)
	testing.expect(t, strings.contains(s.diagnostic, "requires"))
}
