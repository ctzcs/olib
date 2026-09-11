package main

// Smoke test for the oflecs package: native linking, component storage,
// exported IDs, helper iteration and raw query iteration.
//
// Run from the repository root (on case-sensitive systems the repository
// folder itself must be named `oflecs`):
//
//	odin run smoke/main.odin -file -collection:libs=..

import of "libs:oflecs"
import "core:fmt"

Position :: struct {x, y: f32}

main :: proc() {
	// Raw C API.
	world := of.ecs_init()
	defer { _ = of.ecs_fini(world) }

	component_desc := of.ecs_component_desc_t{
		type = {size = size_of(Position), alignment = align_of(Position), name = "Position"},
	}
	position := of.ecs_component_init(world, &component_desc)
	assert(position != 0)

	e := of.ecs_new(world)
	value := Position{10, 20}
	of.ecs_set_id(world, e, position, size_of(Position), &value)

	query_desc := of.ecs_query_desc_t{}
	query_desc.expr = "Position"
	query := of.ecs_query_init(world, &query_desc)
	defer of.ecs_query_fini(query)

	iter := of.ecs_query_iter(world, query)
	raw_total := 0
	for of.ecs_query_next(&iter) {
		positions := cast([^]Position)of.ecs_field_w_size(&iter, size_of(Position), 0)
		for index in 0..<iter.count {
			positions[index].x += 1
			raw_total += 1
		}
	}
	assert(raw_total == 1)

	assert(of.EcsChildOf != 0 && of.EcsWildcard != 0 && of.EcsOnAdd != 0 && of.EcsComponent_ID != 0)
	of.ecs_add_id(world, of.ecs_new(world), of.ecs_make_pair(of.EcsChildOf, e))

	// Helper layer, including the each/query iterator pair.
	helper_total := 0
	it := of.each(world, position)
	for of.next(&it) {
		positions := cast([^]Position)of.field_raw(&it, size_of(Position), 0)
		for i in 0..<of.iter_count_now(&it) {
			positions[i].y += 1
			helper_total += 1
		}
	}
	assert(helper_total == raw_total)

	fmt.printfln("oflecs %s smoke ok: %d entities, EcsChildOf=%v", of.VERSION, raw_total, u64(of.child_of()))
}
