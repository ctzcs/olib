#+test
package fixed

import "core:testing"

Test_Handle :: distinct Handle

Test_Item :: struct {
	handle: Test_Handle,
	value:  i32,
}

@(test)
pool_lifecycle_and_iteration :: proc(t: ^testing.T) {
	pool: Pool(Test_Item, Test_Handle, 4)
	defer delete(&pool)

	testing.expect(t, len(pool) == 0)
	testing.expect(t, cap(pool) == 3)

	first := add(&pool, Test_Item{value = 1})
	removed := add(&pool, Test_Item{value = 2})
	third := add(&pool, Test_Item{value = 3})
	_, added := add(&pool, Test_Item{value = 99})
	testing.expect(t, !added)

	remove(&pool, removed)
	testing.expect(t, len(pool) == 2)
	testing.expect(t, valid(pool, first))
	testing.expect(t, !valid(pool, removed))
	testing.expect(t, get(&pool, removed) == nil)

	reused := add(&pool, Test_Item{value = 4})
	testing.expect(t, reused.idx == removed.idx)
	testing.expect(t, reused.gen != removed.gen)

	count := 0
	sum: i32 = 0
	for it := begin(&pool); item, handle in next(&it) {
		count += 1
		sum += item.value
		testing.expect(t, handle == item.handle)
	}
	testing.expect(t, count == 3)
	testing.expect(t, sum == 8)
	testing.expect(t, valid(pool, third))

	reset(&pool)
	testing.expect(t, len(pool) == 0)
	testing.expect(t, !valid(pool, first))
}

@(test)
callbacks_clear_and_delete_preserve_lifecycle :: proc(t: ^testing.T) {
	H :: distinct Handle
	Item :: struct { handle: H, count: ^int, value: int }
	destroy := proc(item: ^Item) { item.count^ += 1; item^ = {} }
	pool: Pool(Item, H, 4)
	defer delete(&pool)
	counts: [3]int
	clear(&pool)
	reset(&pool)
	delete(&pool)
	old := [3]H{add(&pool, Item{count = &counts[0], value = 7}), add(&pool, Item{count = &counts[1]}), add(&pool, Item{count = &counts[2]})}
	copied, ok := get_value(&pool, old[0])
	testing.expect(t, ok && copied.value == 7)
	remove(&pool, old[1], destroy)
	remove(&pool, old[1], destroy)
	old[1] = add(&pool, Item{count = &counts[1]})
	remove(&pool, old[1], destroy)
	clear(&pool, destroy)
	clear(&pool, destroy)
	testing.expect(t, counts == [3]int{1, 2, 1})
	testing.expect(t, len(pool) == 0)
	it := begin(&pool)
	_, _, more := next(&it)
	testing.expect(t, !more)
	_, missing := get_value(&pool, old[0])
	testing.expect(t, !missing)
	fresh: [3]H
	for i in 0..<3 {
		fresh[i] = add(&pool, Item{count = &counts[i]})
		for h in old { testing.expect(t, !valid(pool, h)) }
		for j in 0..<i { testing.expect(t, fresh[i].idx != fresh[j].idx) }
	}
	testing.expect(t, len(pool) == 3)
	reset(&pool, destroy)
	testing.expect(t, counts == [3]int{2, 3, 2})
	_ = add(&pool, Item{count = &counts[0]})
	delete(&pool, destroy)
	delete(&pool, destroy)
	testing.expect(t, counts == [3]int{3, 3, 2})
	testing.expect(t, len(pool) == 0)
	it = begin(&pool)
	_, _, more = next(&it)
	testing.expect(t, !more)
	h := add(&pool, Item{count = &counts[0]})
	testing.expect(t, valid(pool, h))
	clear(&pool, destroy)
	testing.expect(t, counts[0] == 4)
}
