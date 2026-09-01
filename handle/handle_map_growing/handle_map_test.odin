#+test
package handle_map_growing

import "core:testing"

Test_Handle :: distinct Handle

Test_Item :: struct {
	handle: Test_Handle,
	value:  i32,
}

@(test)
pool_lifecycle_and_iteration :: proc(t: ^testing.T) {
	pool: Pool(Test_Item, Test_Handle)
	defer delete(&pool)

	first := add(&pool, Test_Item{value = 1})
	removed := add(&pool, Test_Item{value = 2})
	third := add(&pool, Test_Item{value = 3})
	testing.expect(t, len(pool) == 3)
	testing.expect(t, cap(pool) >= len(pool))

	remove(&pool, removed)
	testing.expect(t, len(pool) == 2)
	testing.expect(t, valid(pool, first))
	testing.expect(t, !valid(pool, removed))
	testing.expect(t, get(pool, removed) == nil)

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
