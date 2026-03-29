package handle_array

Handle :: struct {
	idx: u32,
	gen: u32,
}

HANDLE_NONE :: Handle {}


Slot :: struct($T: typeid, $HT: typeid) {
    value: T,
    handle: HT,
}

Handle_Array :: struct($T: typeid, $HT: typeid) {
    slots:    [dynamic]Slot(T, HT),
    freelist: [dynamic]HT,
    num:      int,
}

clear :: proc(ha: ^Handle_Array($T, $HT)) {
    clear(&ha.slots)
    clear(&ha.freelist)
}

delete :: proc(ha: Handle_Array($T, $HT)) {
    delete(ha.slots)
    delete(ha.freelist)
}

add :: proc(ha: ^Handle_Array($T, $HT), v: T) -> HT {       
    v := v

    if len(ha.freelist) > 0 {
        h := pop(&ha.freelist)
        h.gen += 1
        ha.slots[h.idx].value  = v
        ha.slots[h.idx].handle = h
        ha.num += 1
        return h
    }

    if len(ha.slots) == 0 {
        append_nothing(&ha.slots) // 0 索引为 dummy
    }

    idx: u32 = u32(len(ha.slots))
    h:HT
    h.idx = idx
    h.gen = 1

    append(&ha.slots, Slot(T, HT){ value = v, handle = h })
    ha.num += 1
    return h
}

get :: proc(ha: Handle_Array($T, $HT), h: HT) -> (val:T, ok:bool) {
    if h.idx > 0 && int(h.idx) < len(ha.slots) && ha.slots[h.idx].handle == h {
        return ha.slots[h.idx].value, true
    }
    return {}, false
}

get_ptr :: proc(ha: Handle_Array($T, $HT), h: HT) -> ^T {
    if h.idx > 0 && int(h.idx) < len(ha.slots) && ha.slots[h.idx].handle == h {
        return &ha.slots[h.idx].value
    }
    return nil
}

remove :: proc(ha: ^Handle_Array($T, $HT), h: HT) {
    if h.idx > 0 && int(h.idx) < len(ha.slots) && ha.slots[h.idx].handle == h {
        append(&ha.freelist, h)
        ha.slots[h.idx] = {}
        ha.num -= 1
    }
}

Handle_Array_Iter :: struct($T: typeid, $HT: typeid) {
    ha:    Handle_Array(T, HT),
    index: int,
}

make_iter :: proc(ha: Handle_Array($T, $HT)) -> (iter:Handle_Array_Iter(T, HT)) {
    return Handle_Array_Iter(T, HT){ ha = ha }
}

//复制迭代
iter :: proc(it: ^Handle_Array_Iter($T, $HT)) -> (val: T, h: HT, cond: bool) {
    in_range := it.index < len(it.ha.slots)
    for in_range {
        cond = it.index > 0 && in_range && it.ha.slots[it.index].handle.idx > 0
        if cond {
            val = it.ha.slots[it.index].value
            h   = it.ha.slots[it.index].handle
            it.index += 1
            return
        }
        it.index += 1
        in_range = it.index < len(it.ha.slots)
    }
    return
}

//指针迭代
iter_ptr :: proc(it: ^Handle_Array_Iter($T, $HT)) -> (val: ^T, h: HT, cond: bool) { 
    in_range := it.index < len(it.ha.slots)
    for in_range {
        cond = it.index > 0 && in_range && it.ha.slots[it.index].handle.idx > 0
        if cond {
            val = &it.ha.slots[it.index].value
            h   = it.ha.slots[it.index].handle
            it.index += 1
            return
        }
        it.index += 1
        in_range = it.index < len(it.ha.slots)
    }
    return
}


