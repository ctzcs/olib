#+test
package tween

import "core:testing"

@(test)
manager_reset_keeps_previous_handles_invalid :: proc(t: ^testing.T) {
    manager := manager_make()
    defer manager_delete(&manager)
    old := manager_add_sequence(&manager)
    testing.expect(t, manager_is_handle_valid(manager, old))
    manager_reset(&manager)
    fresh := manager_add_sequence(&manager)
    testing.expect(t, fresh.idx == old.idx)
    testing.expect(t, fresh.gen != old.gen)
    testing.expect(t, !manager_is_handle_valid(manager, old))
    testing.expect(t, manager_is_handle_valid(manager, fresh))
}
