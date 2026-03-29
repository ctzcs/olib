 package handle_array
/*
Handle_Array_Soa :: struct($T: typeid, $HT: typeid) {
	items: #soa [dynamic]T,
	freelist: [dynamic]HT,
	num: int,
}

ha_clear_soa :: proc(ha: ^Handle_Array_Soa($T, $HT)) {
	clear(&ha.items)
	clear(&ha.freelist)
}

ha_delete_soa :: proc(ha: Handle_Array_Soa($T, $HT)) {
	delete(ha.items)
	delete(ha.freelist)
}

ha_add_soa :: proc(ha: ^Handle_Array_Soa($T, $HT), v: T) -> HT {
	v := v

	if len(ha.freelist) > 0 {
		h := pop(&ha.freelist)
		h.gen += 1
		v.handle = h
		ha.items[h.idx] = v
		ha.num += 1
		return h
	}

	if len(ha.items) == 0 {
        append(&ha.items, T{})
		//append_nothing(&ha.items) // Item at index zero is always "dummy" used for zero comparison
	}

	idx := u32(len(ha.items))
	v.handle.idx = idx
	v.handle.gen = 1
	append(&ha.items, v)
	ha.num += 1
	return v.handle
}

//这里返回的是数组的投影，并不会赋值整块数据
ha_get_soa :: proc(ha: ^Handle_Array_Soa($T, $HT), h: HT) -> (T, bool) {
	if h.idx > 0 && int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		return ha.items[h.idx], true
	}

	return {}, false
}

//SOA无法对整体T进行取地址，因为T只是一个暂存的东西
/* ha_get_ptr_soa :: proc(ha: Handle_Array_Soa($T, $HT), h: HT) -> ^T {
	if h.idx > 0 && int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		return &ha.items[h.idx]
	}

	return nil
} */

ha_remove_soa :: proc(ha: ^Handle_Array($T, $HT), h: HT) {
	if h.idx > 0 && int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		append(&ha.freelist, h)
		ha.items[h.idx] = {}
		ha.num -= 1
	}
}

ha_valid_soa :: proc(ha: Handle_Array($T, $HT), h: HT) -> bool {
	return ha_get(ha, h) != nil
}

// Iterators for iterating over all used
// slots in the array. Used like this:
//
// ent_iter := ha_make_iter(your_handle_based_array)
// for e in ha_iter_ptr(&ent_iter) {
//
// }

Handle_Array_Iter_Soa :: struct($T: typeid, $HT: typeid) {
	ha: Handle_Array_Soa(T, HT),
	index: int,
}

ha_make_iter_soa :: proc(ha: Handle_Array($T, $HT)) -> Handle_Array_Iter_Soa(T, HT) {
	return Handle_Array_Iter_Soa(T, HT) { ha = ha }
}

ha_iter_soa :: proc(it: ^Handle_Array_Iter_Soa($T, $HT)) -> (val: T, h: HT, cond: bool) {
	in_range := it.index < len(it.ha.items)

	for in_range {
		cond = it.index > 0 && in_range && it.ha.items[it.index].handle.idx > 0

		if cond {
			val = it.ha.items[it.index]
			h = it.ha.items[it.index].handle
			it.index += 1
			return
		}

		it.index += 1
		in_range = it.index < len(it.ha.items)
	}

	return
}

*/