#+test
package handle_array

import "core:testing"

@(test)
iterator_skips_free_slots_and_returns_live_values :: proc(t: ^testing.T) {
    Test_Handle :: distinct Handle

    values: Pool(i32, Test_Handle)
    defer delete(&values)

    first := add(&values, 1)
    removed := add(&values, 2)
    third := add(&values, 3)
    remove(&values, removed)

    testing.expect(t, len(values) == 2)
    testing.expect(t, cap(values) >= len(values))
    testing.expect(t, valid(values, first))
    testing.expect(t, !valid(values, removed))

    count := 0
    sum := 0
    saw_first := false
    saw_third := false

    for it := begin(&values); value, handle in next(&it) {
        count += 1
        sum += int(value^)
        saw_first = saw_first || handle == first
        saw_third = saw_third || handle == third
        value^ += 10
    }

    testing.expect(t, count == 2)
    testing.expect(t, sum == 4)
    testing.expect(t, saw_first)
    testing.expect(t, saw_third)
    testing.expect(t, get(values, removed) == nil)
    testing.expect(t, get(values, first)^ == 11)
    testing.expect(t, get(values, third)^ == 13)

    reused := add(&values, 4)
    testing.expect(t, reused.idx == removed.idx)
    testing.expect(t, reused.gen != removed.gen)

    copied, ok := get_value(values, reused)
    testing.expect(t, ok)
    testing.expect(t, copied == 4)

    reset(&values)
    testing.expect(t, len(values) == 0)
    testing.expect(t, !valid(values, first))
}
