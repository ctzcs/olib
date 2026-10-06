// handle:array —— 可扩容的代数句柄池。
//
// Pool 按 slot 存储 value，外部只持有轻量 Handle（idx + gen 代数）：
// 句柄过期（remove 后代数 +1）不会被误认成新条目。0 号 slot 是 dummy，
// 令零值 Handle 永远无效。
//
// 分区：
//   类型 —— Handle / Slot / Pool / Iterator
//   增删 —— add 与 remove
//   清理 —— clear / reset / delete（各带 destroy 回调重载）
//   查询 —— get / get_value / valid / len / cap
//   迭代 —— begin / next
package array

import "base:builtin"
import "base:runtime"

// ------------------------------------------------------------------------------
// 类型 —— Handle / Slot / Pool / Iterator
// ------------------------------------------------------------------------------

// 代数句柄。零值（idx=0）永远无效；remove 后同 idx 的旧句柄因 gen 过期失效。
Handle :: struct {
	idx: u32,
	gen: u32,
}

// 槽位：value 与其当前有效句柄一起存放，校验即比对 handle。
Slot :: struct($T: typeid, $HT: typeid) {
	value:  T,
	handle: HT,
}

// 可扩容句柄池。slots[0] 为 dummy（见 add）；freelist 回收已删槽位。
Pool :: struct($T: typeid, $HT: typeid) {
	slots:    [dynamic]Slot(T, HT),
	freelist: [dynamic]HT,
	num:      int,
}

Iterator :: struct($T: typeid, $HT: typeid) {
	ha:    ^Pool(T, HT),
	index: int,
}

HANDLE_NONE :: Handle{}

// ------------------------------------------------------------------------------
// 增删 —— add 与 remove
// ------------------------------------------------------------------------------

// 插入一个值并返回其句柄；优先复用 freelist 里的槽位（gen 递增）。
add :: proc(ha: ^Pool($T, $HT), v: T) -> (res: HT, err: runtime.Allocator_Error) #optional_allocator_error {
	v := v

	if builtin.len(ha.freelist) > 0 {
		h := pop(&ha.freelist)
		h.gen += 1
		ha.slots[h.idx].value  = v
		ha.slots[h.idx].handle = h
		ha.num += 1
		return h, nil
	}

	needed := max(builtin.len(ha.slots), 1) + 1
	// Reserve before publishing a slot, so remove and clear never allocate.
	if builtin.cap(ha.freelist) < needed - 1 {
		reserve(&ha.freelist, max(needed - 1, 2 * builtin.cap(ha.freelist), 8)) or_return
	}
	if builtin.cap(ha.slots) < needed {
		reserve(&ha.slots, max(needed, 2 * builtin.cap(ha.slots), 8)) or_return
	}
	if builtin.len(ha.slots) == 0 {
		append_nothing(&ha.slots) or_return // 0 索引为 dummy
	}

	idx: u32 = u32(builtin.len(ha.slots))
	h: HT
	h.idx = idx
	h.gen = 1

	append(&ha.slots, Slot(T, HT){ value = v, handle = h }) or_return
	ha.num += 1
	return h, nil
}

remove :: proc {
	remove_without_destroy,
	remove_with_destroy,
}

@(private)
remove_without_destroy :: proc(ha: ^Pool($T, $HT), h: HT) {
	remove_with_destroy(ha, h, nil)
}

// 按句柄移除（代数不符的旧句柄是安全无操作）。destroy 先于回收被调用。
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

// ------------------------------------------------------------------------------
// 清理 —— clear / reset / delete
// ------------------------------------------------------------------------------

// Removes all live values while retaining slots and generation history.
// Subsequent adds reuse free slots; old handles stay invalid until generation
// wraparound. Neither the freelist nor the slot array allocates during clear.
// The destroy callback must not structurally mutate this pool.
clear :: proc {
	clear_without_destroy,
	clear_with_destroy,
}

@(private)
clear_without_destroy :: proc(ha: ^Pool($T, $HT)) {
	clear_with_destroy(ha, nil)
}

@(private)
clear_with_destroy :: proc(ha: ^Pool($T, $HT), destroy: proc(value: ^T)) {
	// Existing free slots already carry their generation in the freelist.
	// Only append live slots, so repeated clears cannot duplicate entries.
	for i := 1; i < builtin.len(ha.slots); i += 1 {
		h := ha.slots[i].handle
		if h.idx != 0 {
			remove_with_destroy(ha, h, destroy)
		}
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
	runtime.clear(&ha.slots)
	runtime.clear(&ha.freelist)
	ha.num = 0
}

// 释放全部内存（池不可再用）；持有资源时传 destroy 先逐项清理。
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

// ------------------------------------------------------------------------------
// 查询 —— get / get_value / valid / len / cap
// ------------------------------------------------------------------------------

// 按值取出（无效句柄返回零值 + false）。
get_value :: proc(ha: Pool($T, $HT), h: HT) -> (val: T, ok: bool) {
	if h.idx > 0 && int(h.idx) < builtin.len(ha.slots) && ha.slots[h.idx].handle == h {
		return ha.slots[h.idx].value, true
	}
	return {}, false
}

// 取值指针（无效句柄返回 nil）。指针在 add/remove 后可能失效。
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

// ------------------------------------------------------------------------------
// 迭代 —— begin / next
// ------------------------------------------------------------------------------

begin :: proc(ha: ^Pool($T, $HT)) -> Iterator(T, HT) {
	return {
		ha    = ha,
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
