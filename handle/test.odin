package handle

import "core:testing"

@(test)
handle_array_test :: proc(t: ^testing.T) {
    testing.expect(t, true, "test info: handle_array_test fail")
}