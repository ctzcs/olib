package handle

import "base:intrinsics"

Fixed_Map :: struct($T: typeid, $HT: typeid, $N: int) {
    items: [N]T,
    num_items: u32,
    next_unused: u32,
    unused_items: [N]u32,
    num_unused: u32,
}

fixed_clear :: proc(m: ^Fixed_Map($T, $HT, $N)) {
    intrinsics.mem_zero(m, size_of(m^))
}

fixed_add :: proc(m: ^Fixed_Map($T, $HT, $N), v: T) -> (HT, bool) #optional_ok {
    v := v

    if m.next_unused != 0 {
        idx := m.next_unused
        item := &m.items[idx]
        m.next_unused = m.unused_items[idx]
        m.unused_items[idx] = 0
        gen := item.handle.gen
        item^ = v
        item.handle.idx = u32(idx)
        item.handle.gen = gen + 1
        m.num_unused -= 1
        return item.handle, true
    }

    if m.num_items == 0 {
        m.items[0] = {}
        m.num_items += 1
    }

    if m.num_items == len(m.items) {
        return {}, false
    }

    item := &m.items[m.num_items]
    item^ = v
    item.handle.idx = u32(m.num_items)
    item.handle.gen = 1
    m.num_items += 1
    return item.handle, true
}

fixed_get :: proc(m: ^Fixed_Map($T, $HT, $N), h: HT) -> ^T {
    if h.idx <= 0 || h.idx >= m.num_items {
        return nil
    }

    if item := &m.items[h.idx]; item.handle == h {
        return item
    }

    return nil
}

fixed_remove :: proc(m: ^Fixed_Map($T, $HT, $N), h: HT) {
    if h.idx <= 0 || h.idx >= m.num_items {
        return
    }

    if item := &m.items[h.idx]; item.handle == h {
        m.unused_items[h.idx] = m.next_unused
        m.next_unused = h.idx
        m.num_unused += 1
        item.handle.idx = 0
    }
}

fixed_valid :: proc(m: Fixed_Map($T, $HT, $N), h: HT) -> bool {
    return h.idx > 0 && h.idx < m.num_items && m.items[h.idx].handle == h
}

fixed_num_used :: proc(m: Fixed_Map($T, $HT, $N)) -> int {
    return int(m.num_items - m.num_unused)
}

fixed_cap :: proc(m: Fixed_Map($T, $HT, $N)) -> int {
    return N
}

Fixed_Iter :: struct($T: typeid, $HT: typeid, $N: int) {
    m: ^Fixed_Map(T, HT, N),
    index: u32,
}

fixed_make_iter :: proc(m: ^Fixed_Map($T, $HT, $N)) -> Fixed_Iter(T, HT, N) {
    return {m = m, index = 1}
}

fixed_iter :: proc(it: ^Fixed_Iter($T, $HT, $N)) -> (val: ^T, h: HT, cond: bool) {
    for _ in it.index..<it.m.num_items {
        item := &it.m.items[it.index]
        it.index += 1

        if item.handle.idx != 0 {
            return item, item.handle, true
        }
    }

    return nil, {}, false
}

fixed_skip :: proc(e: $T) -> bool {
    return e.handle.idx == 0
}