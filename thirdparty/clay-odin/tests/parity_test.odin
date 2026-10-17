package clay_tests

import "core:fmt"
import "core:strings"
import "core:testing"
import clay ".."

// Keep a single test: Clay's current context and callbacks are process globals,
// as in v0.14. Splitting this into parallel tests would race those globals.
@(test)
c_v014_parity :: proc(t: ^testing.T) {
	// Preserve the original function-pointer types, not just call-site coercions.
	create: proc "c" (uint, [^]u8) -> clay.Arena = clay.CreateArenaWithCapacityAndMemory
	end_layout: proc "c" () -> clay.ClayArray(clay.RenderCommand) = clay.EndLayout
	measure_setter: proc "c" (proc "c" (clay.StringSlice, ^clay.TextElementConfig, rawptr) -> clay.Dimensions, rawptr) = clay.SetMeasureTextFunction
	_ = create
	_ = end_layout
	_ = measure_setter
	output := Run()
	defer delete(output)
	summary := Summarize(output)
	defer delete(summary)
	expected := #load("testdata/c-v0.14.txt", string)
	// Git checkouts may use CRLF; the actual frame data is always LF.
	normalized, allocated := strings.replace_all(expected, "\r", "")
	defer if allocated {
		delete(normalized)
	}
	if !testing.expect(t, summary == normalized, "Clay differs from the v0.14 C oracle") {
		fmt.println("Actual frame digests:\n", summary)
		fmt.println("Actual commands and queries:\n", output)
	}
}
