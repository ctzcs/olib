#+test
package array

import "core:testing"
import "base:runtime"
import "base:builtin"

@(test)
clear_preserves_generations_and_reuses_all_slots :: proc(t: ^testing.T) {
    Test_Handle :: distinct Handle
    values: Pool(i32, Test_Handle)
    defer delete(&values)

    clear(&values)
    testing.expect(t, cap(values) == 0)
    old := [3]Test_Handle{add(&values, 1), add(&values, 2), add(&values, 3)}
    remove(&values, old[1])
    // Include a slot whose generation has already advanced.
    old[1] = add(&values, 4)
    remove(&values, old[1])
    capacity := cap(values)
    slot_count := builtin.len(values.slots)

    for cycle in 0..<3 {
        clear(&values)
        clear(&values)
        testing.expect(t, len(values) == 0)
        testing.expect(t, builtin.len(values.freelist) == 3)
        it := begin(&values)
        _, _, ok := next(&it)
        testing.expect(t, !ok)

        fresh: [3]Test_Handle
        for i in 0..<3 {
            fresh[i] = add(&values, i32(i))
            testing.expect(t, valid(values, fresh[i]))
            for h in old {
                testing.expect(t, !valid(values, h))
            }
            for j in 0..<i {
                testing.expect(t, fresh[i].idx != fresh[j].idx)
            }
        }
        testing.expect(t, len(values) == 3)
        testing.expect(t, cap(values) == capacity)
        testing.expect(t, builtin.len(values.slots) == slot_count)
        old = fresh
    }
}

@(test)
clear_destroys_only_live_values_once :: proc(t: ^testing.T) {
    Test_Handle :: distinct Handle
    Value :: struct { destroyed: ^int }
    destroy := proc(v: ^Value) {
        v.destroyed^ += 1
        v^ = {}
    }
    values: Pool(Value, Test_Handle)
    defer delete(&values)
    counts: [3]int
    first := add(&values, Value{&counts[0]})
    removed := add(&values, Value{&counts[1]})
    third := add(&values, Value{&counts[2]})
    remove(&values, removed, destroy)
    clear(&values, destroy)
    clear(&values, destroy)
    testing.expect(t, counts == [3]int{1, 1, 1})
    testing.expect(t, !valid(values, first))
    testing.expect(t, !valid(values, third))
    testing.expect(t, len(values) == 0)
    // Reset still discards slot history and supports the same callback form.
    _ = add(&values, Value{&counts[0]})
    reset(&values, destroy)
    testing.expect(t, counts == [3]int{2, 1, 1})
    testing.expect(t, builtin.len(values.slots) == 0)
}

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

Failure_State :: struct { backing: runtime.Allocator, remaining: int }
failing_allocator :: proc(data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
    state := cast(^Failure_State)data
    if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
        if state.remaining == 0 { return nil, .Out_Of_Memory }
        state.remaining -= 1
    }
    return state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

@(test)
allocation_failure_leaves_pool_usable :: proc(t: ^testing.T) {
    H :: distinct Handle
    Item :: struct { handle: H, value: int }
    // Fail at each of the first two backing-array allocations, then recover.
    for budget in 0..<2 {
        state := Failure_State{context.allocator, budget}
        allocator := runtime.Allocator{procedure = failing_allocator, data = &state}
        pool: Pool(Item, H)
        pool.slots = runtime.make([dynamic]Slot(Item, H), allocator)
        pool.freelist = runtime.make([dynamic]H, allocator)
        defer delete(&pool)
        h, err := add(&pool, Item{value = 42})
        testing.expect(t, err == .Out_Of_Memory && h == H{})
        testing.expect(t, len(pool) == 0)
        state.remaining = 100
        first := add(&pool, Item{value = 42})
        first_ptr := get(pool, first)
        state.remaining = 0
        // Existing spare capacity may admit more items before growth fails.
        for i in 0..<100 {
            _, add_err := add(&pool, Item{value = i})
            if add_err != nil { break }
        }
        testing.expect(t, valid(pool, first))
        testing.expect(t, get(pool, first).value == 42)
        live := len(pool)
        testing.expect(t, live < 101)
        clear(&pool)
        testing.expect(t, len(pool) == 0)
        for i in 0..<live {
            fresh, add_err := add(&pool, Item{value = i})
            testing.expect(t, add_err == nil && valid(pool, fresh))
            testing.expect(t, !valid(pool, first))
        }
        clear(&pool)
        state.remaining = 10000
        first = add(&pool, Item{value = 42})
        first_ptr = get(pool, first)
        for i in 0..<1000 { _ = add(&pool, Item{value = i}) }
        testing.expect(t, get(pool, first).value == 42)
    }
}
