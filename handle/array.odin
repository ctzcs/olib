package handle

Array_Slot :: struct($T: typeid, $HT: typeid) {
    value: T,
    handle: HT,
}

Array :: struct($T: typeid, $HT: typeid) {
    slots:    [dynamic]Array_Slot(T, HT),
    freelist: [dynamic]HT,
    num:      int,
}

array_clear :: proc(ha: ^Array($T, $HT)) {
    clear(&ha.slots)
    clear(&ha.freelist)
}

array_delete :: proc(ha: Array($T, $HT)) {
    delete(ha.slots)
    delete(ha.freelist)
}

array_add :: proc(ha: ^Array($T, $HT), v: T) -> HT {
    v := v

    if len(ha.freelist) > 0 {
        h := pop(&ha.freelist)
        h.gen += 1
        ha.slots[h.idx].value = v
        ha.slots[h.idx].handle = h
        ha.num += 1
        return h
    }

    if len(ha.slots) == 0 {
        append_nothing(&ha.slots)
    }

    idx: u32 = u32(len(ha.slots))
    h: HT
    h.idx = idx
    h.gen = 1

    append(&ha.slots, Array_Slot(T, HT){value = v, handle = h})
    ha.num += 1
    return h
}

array_get :: proc(ha: Array($T, $HT), h: HT) -> (val: T, ok: bool) {
    if h.idx > 0 && int(h.idx) < len(ha.slots) && ha.slots[h.idx].handle == h {
        return ha.slots[h.idx].value, true
    }
    return {}, false
}

array_get_ptr :: proc(ha: Array($T, $HT), h: HT) -> ^T {
    if h.idx > 0 && int(h.idx) < len(ha.slots) && ha.slots[h.idx].handle == h {
        return &ha.slots[h.idx].value
    }
    return nil
}

array_remove :: proc(ha: ^Array($T, $HT), h: HT) {
    if h.idx > 0 && int(h.idx) < len(ha.slots) && ha.slots[h.idx].handle == h {
        append(&ha.freelist, h)
        ha.slots[h.idx] = {}
        ha.num -= 1
    }
}

Array_Iter :: struct($T: typeid, $HT: typeid) {
    ha:    Array(T, HT),
    index: int,
}

array_make_iter :: proc(ha: Array($T, $HT)) -> (iter: Array_Iter(T, HT)) {
    return Array_Iter(T, HT){ha = ha}
}

array_iter :: proc(it: ^Array_Iter($T, $HT)) -> (val: T, h: HT, cond: bool) {
    in_range := it.index < len(it.ha.slots)
    for in_range {
        cond = it.index > 0 && in_range && it.ha.slots[it.index].handle.idx > 0
        if cond {
            val = it.ha.slots[it.index].value
            h = it.ha.slots[it.index].handle
            it.index += 1
            return
        }
        it.index += 1
        in_range = it.index < len(it.ha.slots)
    }
    return
}

array_iter_ptr :: proc(it: ^Array_Iter($T, $HT)) -> (val: ^T, h: HT, cond: bool) {
    in_range := it.index < len(it.ha.slots)
    for in_range {
        cond = it.index > 0 && in_range && it.ha.slots[it.index].handle.idx > 0
        if cond {
            val = &it.ha.slots[it.index].value
            h = it.ha.slots[it.index].handle
            it.index += 1
            return
        }
        it.index += 1
        in_range = it.index < len(it.ha.slots)
    }
    return
}