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
Velocity :: struct {x, y: f32}
Dead :: struct {}

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

	// Helper layer, including the each/iterate iterator pair.
	helper_total := 0
	it := of.each(world, Position)
	for of.next(&it) {
		positions := of.field(&it, Position, 0)
		for i in 0..<of.count(&it) {
			positions[i].y += 1
			helper_total += 1
		}
	}
	assert(helper_total == raw_total)

	// Typed helper layer: registration and ids derive from the Odin type.
	e2 := of.new_entity(world)
	of.set(world, e2, Position{1, 2})
	assert(of.has(world, e2, Position))
	assert(of.get(world, e2, Position).x == 1)
	of.get_mut(world, e2, Position).y = 3
	assert(of.get(world, e2, Position).y == 3)

	of.add(world, e2, Velocity)
	assert(of.has(world, e2, Velocity))
	of.remove(world, e2, Velocity)
	assert(!of.has(world, e2, Velocity))
	of.modified(world, e2, Position)

	// Term-based query via Query_Terms: no expression string involved.
	of.add(world, e2, Velocity)
	movement := of.query_terms(world, {all = {Position, Velocity}})
	matches := 0
	mit := of.iterate(world, movement)
	for of.next(&mit) {
		positions := of.field(&mit, Position, 0)
		velocities := of.field(&mit, Velocity, 1)
		for i in 0..<of.count(&mit) {
			positions[i].x += 10
			velocities[i].y = 7
			matches += 1
		}
	}
	of.query_free(movement)
	assert(matches == 1)
	assert(of.get(world, e2, Position).x == 11)
	assert(of.get(world, e2, Velocity).y == 7)

	// Builder-style with/without lists, through the query group.
	e3 := of.new_entity(world)
	of.set(world, e3, Position{5, 5})
	of.set(world, e3, Velocity{1, 1})
	of.add(world, e3, Dead)

	filtered := of.query(world, of.Query_Terms{all = {Position, Velocity}, none = {Dead}, read = {Velocity}})
	total := 0
	fit := of.iterate(world, filtered)
	for of.next(&fit) {
		total += of.count(&fit)
	}
	of.query_free(filtered)
	assert(total == 1)

	fmt.printfln("oflecs %s smoke ok: %d entities, EcsChildOf=%v", of.VERSION, raw_total, u64(of.EcsChildOf))
}
