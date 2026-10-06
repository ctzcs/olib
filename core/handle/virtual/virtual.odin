/* Handle-based map using static virtual arena. By Karl Zylinski (karl@zylinski.se)

The Pool maps a handle to an item. A handle consists of an index and a
generation. The item can be any type. Such a handle can be stored as a permanent
reference, where you'd usually store a pointer. The benefit of storing handles
instead of pointers is that you know if a slot has been reused, thanks to the
generation number. This makes it much easier to several systems to work with,
and store references to the items in the handle map.

This implementation uses a dynamic array and static virtual arena. The dynamic
array allocates its data (its items) into the arena. This means that virtual
memory is reserved up-front when the handle map is created. You can use a very
big up-front reservation since it is just a reservation: Reserving virtual
memory does not make the memory usage go up. It goes up when the dynamic array
actually grows into that reserved space.

Odin's virtual arena lets the dynamic array grow in-place as long as no other
allocation into the arena has happened in-between, which is always the case here.
So no pointers will ever move!

Example (assumes this package is imported under the alias `hm`):

	Entity_Handle :: hm.Handle

	Entity :: struct {
		// All items must contain a handle
		handle: Entity_Handle,
		pos: [2]f32,
	}

	// The number 10000 results in a virtual reserve of 10000*size_of(Entity)
	// bytes. It's just a reserve. The physical memory usage will go up when
	// that memory is committed as part of the dynamic array inside the
	// Pool grows.
	entities: hm.Pool(Entity, Entity_Handle, 10000)

	h1 := hm.add(&entities, Entity { pos = { 5, 7 } })
	h2 := hm.add(&entities, Entity { pos = { 10, 5 } })

	// Resolve handle -> pointer
	if h2e := hm.get(entities, h2); h2e != nil {
		h2e.pos.y = 123
	}

	// Will remove this entity, leaving an unused slot
	hm.remove(&entities, h1)

	// Will reuse the slot h1 used
	h3 := hm.add(&entities, Entity { pos = { 1, 2 } })

	// Iterate. You can also use `for e in hm.items {}` and skip any item where
	// `e.handle.idx == 0`. The iterator does that automatically. There's also
	// `skip` procedure in this package that check `e.handle.idx == 0` for you.
	ent_iter := hm.begin(&entities)
	for e, h in hm.next(&ent_iter) {
		e.pos += { 5, 1 }
	}

	hm.delete(&entities)
*/
package virtual

import "base:runtime"
import "base:builtin"
import vmem "core:mem/virtual"

// Returned from the `add` proc. Store these as permanent references to items in
// the handle map. You can resolve the handle to a pointer using the `get` proc.
Handle :: struct {
	// index into `items` array of the `Pool` struct.
	idx: u32,

	// When using the `get` proc, this will be matched to the `gen` on the item
	// in the handle map. The handle is only valid if they match. If they don't
	// match, then it means that the slot in the handle map has been reused.
	gen: u32,
}

// `T` is the type to store in the Pool.
//
// `HT` is the handle type. Usually `My_Handle_Type :: distinct hm.Handle`.
//
// `Max` is the maximum number of items the Pool can store. Since the
// Pool uses virtual memory, you can choose a very big value for `Max`:
// It will only be used to reserve virtual memory. Actual physical memory is
// only allocated as the `items` array grows into that reserved memory.
Pool :: struct($T: typeid, $HT: typeid, $Max: int) {
	// Each item much have a field `handle` of type `HT`.
	//
	// There's always a "dummy element" at index 0. This way, a Handle with
	// `idx == 0` means "no Handle".
	items: [dynamic]T,

	// Arena that stores the data for each of the items. It will have room for
	// `Max` number of elements.
	items_arena: ^vmem.Arena,

	// The indices of unused slots. `remove` will add things to it and `add`
	// will remove things from it.
	unused_items: [dynamic]u32,
}

// Usually you can just declare the Pool using
// `hm: Pool(Item_Type, Handle_Type, 10000)`, but if you want to override
// the allocator used for `unused_items`, then you can instead do:
// `hm := hm.make(Item_Type, Handle_Type, 10000, some_allocator)`
make :: proc($T: typeid, $HT: typeid, $Max: int, allocator := context.allocator, loc := #caller_location) -> (Pool(T, HT, Max), vmem.Allocator_Error) #optional_allocator_error {
	arena_bootstrap: vmem.Arena
	err := vmem.arena_init_static(&arena_bootstrap, uint((Max + 1) * size_of(T) + size_of(vmem.Arena)))

	if err != nil {
		return {}, err
	}

	// We allocate the arena struct into the arena itself, the reference to the
	// arena inside the allocator that is sent into the dynamic array stays fixed.
	arena, alloc_err := new(vmem.Arena, vmem.arena_allocator(&arena_bootstrap), loc)
    if alloc_err != nil {
        vmem.arena_destroy(&arena_bootstrap)
        return {}, alloc_err
    }
	arena^ = arena_bootstrap

	return {
		unused_items = runtime.make([dynamic]u32, allocator, loc),
		items_arena = arena,
		items = runtime.make([dynamic]T, vmem.arena_allocator(arena), loc),
	}, nil
}

// Destroys live values if requested, frees container memory, and zeroes the Pool.
delete :: proc(m: ^Pool($T, $HT, $Max), destroy: proc(value: ^T) = nil, loc := #caller_location) {
    clear(m, destroy)
    if m.items_arena != nil {
        arena := m.items_arena^
        vmem.arena_destroy(&arena)
    }
    runtime.delete(m.unused_items, loc)
    m^ = {}
}

// Empties the handle map without deallocating any memory.
// Starts a new lifecycle; all previously returned handles must be discarded.
reset :: proc(m: ^Pool($T, $HT, $Max), destroy: proc(value: ^T) = nil, loc := #caller_location) {
    clear(m, destroy)
    runtime.clear(&m.items)
    runtime.clear(&m.unused_items)
}

// Add a value of type `T` to the handle map. Returns a handle you can use as a
// permanent reference.
//
// This may cause the `items` array to grow. Since the backing memory of `items`
// is always the most recent allocation into `items_arena`, then arena is able
// to reallocate the dynamic array `items` in-place: No pointers will move.
//
// Will reuse slots from `unused_items` array if there are any.
add :: proc(m: ^Pool($T, $HT, $Max), v: T, loc := #caller_location) -> (res: HT, err: vmem.Allocator_Error) #optional_allocator_error {
	if m.items_arena == nil {
		m^ = make(T, HT, Max, loc = loc) or_return
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

    needed := max(builtin.len(m.items), 1) + 1
    if builtin.cap(m.unused_items) < needed - 1 {
        reserve(&m.unused_items, max(needed - 1, 2 * builtin.cap(m.unused_items), 8)) or_return
    }

	if builtin.len(m.items) == 0 {
		append(&m.items, T{}) or_return
	}

	new_item := v
	new_item.handle.idx = u32(builtin.len(m.items))
	new_item.handle.gen = 1
	_, append_err := append(&m.items, new_item)

	if append_err != nil {
		// If the append couldn't grow the dynamic array due to out of memory,
		// then it is probably because it tried to make it bigger than what has
		// been reserved for it. In that case we try to grow it again, but to
		// the exact maximum that should fit in the arena.
		if append_err == .Out_Of_Memory {
			reserve(&m.items, slot_cap(m^)) or_return
			append(&m.items, new_item) or_return
		} else {
			return {}, append_err
		}
	}

	return new_item.handle, nil
}

// Resolve a handle to a pointer of type `^T`. The pointer is stable due to the
// usage of the virtual static arena. But you should _not_ store the pointer
// permanently. The item may get reused if any part of your program destroys and
// reuses that slot. Only store handles permanently and temporarily resolve them
// into pointers as needed.
get :: proc(m: Pool($T, $HT, $Max), h: HT) -> ^T {
	if h.idx <= 0 || h.idx >= u32(builtin.len(m.items)) {
		return nil
	}

	if item := &m.items[h.idx]; item.handle == h {
		return item
	}

	return nil
}

// Removes a live value, optionally destroying its resources, and retains its
// generation for reuse. The callback must not structurally mutate this pool.
remove :: proc(m: ^Pool($T, $HT, $Max), h: HT, destroy: proc(value: ^T) = nil) {
    item := get(m^, h)
    if item == nil { return }
    // Save generation before the callback, which may zero the entire value.
    gen := h.gen
    if destroy != nil { destroy(item) }
    // add reserves free-list space before publishing a new slot.
    append(&m.unused_items, h.idx)
    item^ = {}
    item.handle.gen = gen
}

// Tells you if a handle maps to a valid item.
valid :: proc(m: Pool($T, $HT, $Max), h: HT) -> bool {
	return get(m, h) != nil
}

// Tells you how many valid items there are in the handle map.
len :: proc(m: Pool($T, $HT, $Max)) -> int {
	return max(builtin.len(m.items), 1) - builtin.len(m.unused_items) - 1
}

@(private)
slot_cap :: proc(m: Pool($T, $HT, $Max)) -> int {
	if m.items_arena == nil {
		return 0
	}

	return int((m.items_arena.total_reserved - size_of(vmem.Arena)) / size_of(T))
}

// Calculates how many items you could, in theory, fit into the Pool. In
// many cases the Pool will be reserved with a very very large number, so
// this capacity may have an absurd value.
//
// Note: This does not just return `Max`. That's because the amount of memory
// may have been rounded upwards to nearest page size.
cap :: proc(m: Pool($T, $HT, $Max)) -> int {
	return max(slot_cap(m) - 1, 0)
}

// For iterating a handle map. Create using `begin`.
Iterator :: struct($T: typeid, $HT: typeid, $Max: int) {
	m: ^Pool(T, HT, Max),
	index: int,
}

// Create an iterator. Use with `next` to do the actual iteration.
begin :: proc(m: ^Pool($T, $HT, $Max)) -> Iterator(T, HT, Max) {
	return { m = m }
}

// Iterate over the handle map. Skips unused slots, meaning that it skips slots
// with handle.idx == 0.
//
// Usage:
//     my_iter := hm.begin(&my_handle_map)
//     for e in hm.next(&my_iter) {}
// 
// Instead of using an iterator you can also loop over `items` and check if
// `item.handle.idx == 0` and in that case skip that item.
next :: proc(it: ^Iterator($T, $HT, $Max)) -> (val: ^T, h: HT, cond: bool) {
	for _ in it.index..<builtin.len(it.m.items) {
		item := &it.m.items[it.index]
		it.index += 1

		if item.handle.idx != 0 {
			return item, item.handle, true
		}
	}

	return nil, {}, false
}

// If you don't want to use iterator, you can instead do:
// for &item in my_map.items {
//     if hm.skip(item) {
//         continue
//     }
//     // do stuff
// }
skip :: proc(e: $T) -> bool {
	return e.handle.idx == 0
}

// Returns a value copy and whether the handle was valid.
get_value :: proc(m: Pool($T, $HT, $Max), h: HT) -> (value: T, ok: bool) {
    if item := get(m, h); item != nil { return item^, true }
    return {}, false
}

// Retains slots and generations without allocation. Old handles stay invalid until generation
// wraparound. Callbacks must not structurally mutate this pool.
clear :: proc(m: ^Pool($T, $HT, $Max), destroy: proc(value: ^T) = nil) {
    for i := 1; i < builtin.len(m.items); i += 1 {
        item := &m.items[i]
        if item.handle.idx != 0 { remove(m, item.handle, destroy) }
    }
}
