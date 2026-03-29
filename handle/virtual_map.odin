package handle

import "base:runtime"
import "base:builtin"
import vmem "core:mem/virtual"

Virtual_Map :: struct($T: typeid, $HT: typeid, $Max: int) {
    items: [dynamic]T,
    items_arena: ^vmem.Arena,
    unused_items: [dynamic]u32,
}

virtual_make :: proc($T: typeid, $HT: typeid, $Max: int, allocator := context.allocator, loc := #caller_location) -> (Virtual_Map(T, HT, Max), vmem.Allocator_Error) #optional_allocator_error {
    arena_bootstrap: vmem.Arena
    err := vmem.arena_init_static(&arena_bootstrap, uint(Max * size_of(T) + size_of(vmem.Arena)))

    if err != nil {
        return {}, err
    }

    arena := new(vmem.Arena, vmem.arena_allocator(&arena_bootstrap), loc)
    arena^ = arena_bootstrap

    return {
        unused_items = runtime.make([dynamic]u32, allocator, loc),
        items_arena = arena,
        items = runtime.make([dynamic]T, vmem.arena_allocator(arena), loc),
    }, nil
}

virtual_delete :: proc(m: ^Virtual_Map($T, $HT, $Max), loc := #caller_location) {
    if m.items_arena != nil {
        arena := m.items_arena^
        vmem.arena_destroy(&arena)
    }

    runtime.delete(m.unused_items, loc)
}

virtual_clear :: proc(m: ^Virtual_Map($T, $HT, $Max), loc := #caller_location) {
    runtime.clear(&m.items)
    runtime.clear(&m.unused_items)
}

virtual_add :: proc(m: ^Virtual_Map($T, $HT, $Max), v: T, loc := #caller_location) -> (res: HT, err: vmem.Allocator_Error) #optional_allocator_error {
    if m.items_arena == nil {
        m^ = virtual_make(T, HT, Max, loc = loc) or_return
    }

    v := v

    if builtin.len(m.unused_items) > 0 {
        reuse_idx := pop(&m.unused_items)
        reused := &m.items[reuse_idx]
        gen := reused.handle.gen
        reused^ = v
        reused.handle.idx = u32(reuse_idx)
        reused.handle.gen = gen + 1
        return reused.handle, nil
    }

    if builtin.len(m.items) == 0 {
        append(&m.items, T{})
    }

    new_item := v
    new_item.handle.idx = u32(builtin.len(m.items))
    new_item.handle.gen = 1
    _, append_err := append(&m.items, new_item)

    if append_err != nil {
        if append_err == .Out_Of_Memory {
            reserve(&m.items, virtual_cap(m^)) or_return
            append(&m.items, new_item) or_return
        } else {
            return {}, append_err
        }
    }

    return new_item.handle, nil
}

virtual_get :: proc(m: Virtual_Map($T, $HT, $Max), h: HT) -> ^T {
    if h.idx <= 0 || h.idx >= u32(builtin.len(m.items)) {
        return nil
    }

    if item := &m.items[h.idx]; item.handle == h {
        return item
    }

    return nil
}

virtual_remove :: proc(m: ^Virtual_Map($T, $HT, $Max), h: HT) {
    if h.idx <= 0 || h.idx >= u32(builtin.len(m.items)) {
        return
    }

    if item := &m.items[h.idx]; item.handle == h {
        append(&m.unused_items, h.idx)
        item.handle.idx = 0
    }
}

virtual_valid :: proc(m: Virtual_Map($T, $HT, $Max), h: HT) -> bool {
    return virtual_get(m, h) != nil
}

virtual_len :: proc(m: Virtual_Map($T, $HT, $Max)) -> int {
    return builtin.len(m.items) - builtin.len(m.unused_items)
}

virtual_cap :: proc(m: Virtual_Map($T, $HT, $Max)) -> int {
    if m.items_arena == nil {
        return 0
    }

    return int((m.items_arena.total_reserved - size_of(vmem.Arena)) / size_of(T))
}

Virtual_Iter :: struct($T: typeid, $HT: typeid, $Max: int) {
    m: ^Virtual_Map(T, HT, Max),
    index: int,
}

virtual_make_iter :: proc(m: ^Virtual_Map($T, $HT, $Max)) -> Virtual_Iter(T, HT, Max) {
    return {m = m}
}

virtual_iter :: proc(it: ^Virtual_Iter($T, $HT, $Max)) -> (val: ^T, h: HT, cond: bool) {
    for _ in it.index..<builtin.len(it.m.items) {
        item := &it.m.items[it.index]
        it.index += 1

        if item.handle.idx != 0 {
            return item, item.handle, true
        }
    }

    return nil, {}, false
}

virtual_skip :: proc(e: $T) -> bool {
    return e.handle.idx == 0
}