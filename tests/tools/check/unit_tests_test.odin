#+test
package main

import "core:strings"
import "core:testing"

@(test)
isolated_test_sources_keep_original_paths_without_rewriting_literals :: proc(t: ^testing.T) {
	source := "package sample\n// #directory #load(\"fake\")\n" +
		"text :: `#directory #load(\"fake\")`\n" +
		"root :: #directory\nblob :: #load(\"data.bin\")\n" +
		"import local \"../shared\"\nimport \"core:fmt\"\n"
	path := path_join(#directory, "fixture.odin")
	result, ok := unit_source_paths(source, path)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(result, "// #directory #load(\"fake\")"))
	testing.expect(t, strings.contains(result, "text :: `#directory #load(\"fake\")`"))
	testing.expect(t, !strings.contains(result, "root :: #directory"))
	testing.expect(t, !strings.contains(result, "blob :: #load(\"data.bin\")"))
	testing.expect(t, !strings.contains(result, "import local \"../shared\""))
	testing.expect(t, strings.contains(result, "import \"core:fmt\""))
}
