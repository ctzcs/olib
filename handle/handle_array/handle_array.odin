///可扩容的句柄数组
package handle_array

import "base:builtin"
import "base:runtime"

Handle :: struct {
	idx: u32,
	gen: u32,
}

Slot :: struct($T: typeid, $HT: typeid) {
    value: T,
    handle: HT,
}

Pool :: struct($T: typeid, $HT: typeid) {
    slots:    [dynamic]Slot(T, HT),
    freelist: [dynamic]HT,
    num:      int,
}

Iterator :: struct($T: typeid, $HT: typeid) {
    ha:    ^Pool(T, HT),
    index: int,
}

HANDLE_NONE :: Handle {}


add :: proc(ha: ^Pool($T, $HT), v: T) -> HT {
    v := v

    if builtin.len(ha.freelist) > 0 {
        h := pop(&ha.freelist)
        h.gen += 1
        ha.slots[h.idx].value  = v
        ha.slots[h.idx].handle = h
        ha.num += 1
        return h
    }

    if builtin.len(ha.slots) == 0 {
        append_nothing(&ha.slots) // 0 索引为 dummy
    }

    idx: u32 = u32(builtin.len(ha.slots))
    h:HT
    h.idx = idx
    h.gen = 1

    append(&ha.slots, Slot(T, HT){ value = v, handle = h })
    ha.num += 1
    return h
}

remove :: proc {
	remove_without_destroy,
	remove_with_destroy,
}

@(private)
remove_without_destroy :: proc(ha: ^Pool($T, $HT), h: HT) {
	remove_with_destroy(ha, h, nil)
}

@(private)
remove_with_destroy :: proc(ha: ^Pool($T, $HT), h: HT, destroy: proc(value: ^T)) {
    if h.idx > 0 && int(h.idx) < builtin.len(ha.slots) && ha.slots[h.idx].handle == h {
        if destroy != nil {
            destroy(&ha.slots[h.idx].value)
        }
        append(&ha.freelist, h)
        ha.slots[h.idx] = {}
        ha.num -= 1
    }
}

// Resets the container for a new lifecycle while retaining allocated capacity.
// All previously returned handles must be discarded.
reset :: proc {
	reset_without_destroy,
	reset_with_destroy,
}

@(private)
reset_without_destroy :: proc(ha: ^Pool($T, $HT)) {
	reset_with_destroy(ha, nil)
}

@(private)
reset_with_destroy :: proc(ha: ^Pool($T, $HT), destroy: proc(value: ^T)) {
    if destroy != nil {
        for i := 1; i < builtin.len(ha.slots); i += 1 {
            if ha.slots[i].handle.idx > 0 {
                destroy(&ha.slots[i].value)
            }
        }
    }
    clear(&ha.slots)
    clear(&ha.freelist)
    ha.num = 0
}

//释放内存；如有资源可传 destroy 先逐项清理
delete :: proc {
	delete_without_destroy,
	delete_with_destroy,
}

@(private)
delete_without_destroy :: proc(ha: ^Pool($T, $HT)) {
	delete_with_destroy(ha, nil)
}

@(private)
delete_with_destroy :: proc(ha: ^Pool($T, $HT), destroy: proc(value: ^T)) {
    if destroy != nil {
        for i := 1; i < builtin.len(ha.slots); i += 1 {
            if ha.slots[i].handle.idx > 0 {
                destroy(&ha.slots[i].value)
            }
        }
    }
	runtime.delete(ha.slots)
	runtime.delete(ha.freelist)
    ha^ = {}
}

get_value :: proc(ha: Pool($T, $HT), h: HT) -> (val:T, ok:bool) {
    if h.idx > 0 && int(h.idx) < builtin.len(ha.slots) && ha.slots[h.idx].handle == h {
        return ha.slots[h.idx].value, true
    }
    return {}, false
}

get :: proc(ha: Pool($T, $HT), h: HT) -> ^T {
    if h.idx > 0 && int(h.idx) < builtin.len(ha.slots) && ha.slots[h.idx].handle == h {
        return &ha.slots[h.idx].value
    }
    return nil
}

valid :: proc(ha: Pool($T, $HT), h: HT) -> bool {
    return get(ha, h) != nil
}

len :: proc(ha: Pool($T, $HT)) -> int {
    return ha.num
}

// Returns the number of live items that fit without growing the slot array.
cap :: proc(ha: Pool($T, $HT)) -> int {
    return max(builtin.cap(ha.slots) - 1, 0)
}

begin :: proc(ha: ^Pool($T, $HT)) -> Iterator(T, HT) {
    return {
        ha = ha,
        index = 1,
    }
}

// Structural mutation during iteration is not allowed. Adding an item may
// relocate slots and invalidate a pointer returned by next.
next :: proc(it: ^Iterator($T, $HT)) -> (value: ^T, handle: HT, ok: bool) {
    for it.index < builtin.len(it.ha.slots) {
        index := it.index
        it.index += 1

        slot := &it.ha.slots[index]
        if slot.handle.idx != 0 {
            return &slot.value, slot.handle, true
        }
    }

    return nil, {}, false
}
