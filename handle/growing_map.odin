package handle

import "base:runtime"
import "base:builtin"

Growing_Map :: struct($T: typeid, $HT: typeid) {
    items: [dynamic]^T,
    items_arena: Growing_Arena,
    unused_items: [dynamic]u32,
}

growing_make :: proc(
    $T: typeid,
    $HT: typeid,
    min_items_per_block: int = (GROWING_ARENA_DEFAULT_BLOCK_SIZE / size_of(T)),
    allocator := context.allocator,
    loc := #caller_location,
) -> (res: Growing_Map(T, HT), err: runtime.Allocator_Error) #optional_allocator_error {
    m := Growing_Map(T, HT){
        items = runtime.make([dynamic]^T, allocator, loc),
        unused_items = runtime.make([dynamic]u32, allocator, loc),
    }

    growing_arena_init(&m.items_arena, min_items_per_block * size_of(T), allocator) or_return
    return m, nil
}

growing_delete :: proc(m: ^Growing_Map($T, $HT), loc := #caller_location) {
    growing_arena_destroy(&m.items_arena)
    runtime.delete(m.items, loc)
    runtime.delete(m.unused_items, loc)
}

growing_clear :: proc(m: ^Growing_Map($T, $HT), loc := #caller_location) {
    growing_arena_free_all(&m.items_arena)
    runtime.clear(&m.items)
    runtime.clear(&m.unused_items)
}

growing_add :: proc(m: ^Growing_Map($T, $HT), v: T, loc := #caller_location) -> (res: HT, err: runtime.Allocator_Error) #optional_allocator_error {
    if !growing_arena_initialized(m.items_arena) {
        m^ = growing_make(T, HT, loc = loc) or_return
    }

    v := v

    if builtin.len(m.unused_items) > 0 {
        reuse_idx := pop(&m.unused_items)
        reused := m.items[reuse_idx]
        gen := reused.handle.gen
        reused^ = v
        reused.handle.idx = u32(reuse_idx)
        reused.handle.gen = gen + 1
        return reused.handle, nil
    }

    items_allocator := growing_arena_allocator(&m.items_arena)

    if builtin.len(m.items) == 0 {
        zero_dummy := new(T, items_allocator) or_return
        append(&m.items, zero_dummy)
    }

    new_item := new(T, items_allocator) or_return
    new_item^ = v
    new_item.handle.idx = u32(builtin.len(m.items))
    new_item.handle.gen = 1
    append(&m.items, new_item)
    return new_item.handle, nil
}

growing_get :: proc(m: Growing_Map($T, $HT), h: HT) -> ^T {
    if h.idx <= 0 || h.idx >= u32(builtin.len(m.items)) {
        return nil
    }

    if item := m.items[h.idx]; item.handle == h {
        return item
    }

    return nil
}

growing_remove :: proc(m: ^Growing_Map($T, $HT), h: HT) {
    if h.idx <= 0 || h.idx >= u32(builtin.len(m.items)) {
        return
    }

    if item := m.items[h.idx]; item.handle == h {
        append(&m.unused_items, h.idx)
        item.handle.idx = 0
    }
}

growing_valid :: proc(m: Growing_Map($T, $HT), h: HT) -> bool {
    return growing_get(m, h) != nil
}

growing_len :: proc(m: Growing_Map($T, $HT)) -> int {
    return max(builtin.len(m.items), 1) - builtin.len(m.unused_items) - 1
}

Growing_Iter :: struct($T: typeid, $HT: typeid) {
    m: ^Growing_Map(T, HT),
    index: int,
}

growing_make_iter :: proc(m: ^Growing_Map($T, $HT)) -> Growing_Iter(T, HT) {
    return {m = m}
}

growing_iter :: proc(it: ^Growing_Iter($T, $HT)) -> (val: ^T, h: HT, cond: bool) {
    for _ in it.index..<builtin.len(it.m.items) {
        item := it.m.items[it.index]
        it.index += 1

        if item.handle.idx != 0 {
            return item, item.handle, true
        }
    }

    return nil, {}, false
}

growing_skip :: proc(e: $T) -> bool {
    return e.handle.idx == 0
}