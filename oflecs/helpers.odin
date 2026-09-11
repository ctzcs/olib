package oflecs

import "core:c"

// Idiomatic aliases used by the helper layer. The ecs_* declarations in
// oflecs.odin expose the complete C ABI and remain the canonical low-level API.
World :: ecs_world_t
Query :: ecs_query_t
Entity :: ecs_entity_t
ID :: ecs_id_t

// Iter is the native Flecs iterator. Helpers hand it out by value: keep it on
// the stack, advance it with next, and there is nothing to free once a loop
// has run to completion.
Iter :: ecs_iter_t

NULL_ENTITY :: Entity(0)
NULL_ID :: ID(0)
VERSION :: "4.1.6"

// Init creates a Flecs world with the default modules.
init :: proc() -> ^World { return ecs_init() }

// Mini creates a smaller world without optional modules.
mini :: proc() -> ^World { return ecs_mini() }

// Fini releases a world and all entities/components owned by it.
fini :: proc(world: ^World) -> i32 { return ecs_fini(world) }

progress :: proc(world: ^World, delta_time: f32 = 0) -> bool {
	return ecs_progress(world, delta_time)
}

should_quit :: proc(world: ^World) -> bool { return ecs_should_quit(world) }

new_entity :: proc(world: ^World) -> Entity { return ecs_new(world) }

new_entity_with :: proc(world: ^World, id: ID) -> Entity {
	return ecs_new_w_id(world, id)
}

entity :: proc(world: ^World, name: cstring) -> Entity {
	desc := ecs_entity_desc_t{name = name}
	return ecs_entity_init(world, &desc)
}

component :: proc(world: ^World, name: cstring, size: uintptr, alignment: uintptr = 1) -> Entity {
	desc := ecs_component_desc_t{}
	desc.type.size = cast(ecs_size_t)size
	desc.type.alignment = cast(ecs_size_t)alignment
	desc.type.name = name
	return ecs_component_init(world, &desc)
}

add :: proc(world: ^World, e: Entity, id: ID) { ecs_add_id(world, e, id) }
remove :: proc(world: ^World, e: Entity, id: ID) { ecs_remove_id(world, e, id) }
clear :: proc(world: ^World, e: Entity) { ecs_clear(world, e) }
delete :: proc(world: ^World, e: Entity) { ecs_delete(world, e) }

has :: proc(world: ^World, e: Entity, id: ID) -> bool { return ecs_has_id(world, e, id) }
is_alive :: proc(world: ^World, e: Entity) -> bool { return ecs_is_alive(world, e) }
lookup :: proc(world: ^World, path: cstring) -> Entity { return ecs_lookup(world, path) }
name :: proc(world: ^World, e: Entity) -> cstring { return ecs_get_name(world, e) }

set_raw :: proc(world: ^World, e: Entity, id: ID, value: rawptr, size: uintptr) {
	ecs_set_id(world, e, id, c.size_t(size), value)
}

get_raw :: proc(world: ^World, e: Entity, id: ID) -> rawptr {
	return ecs_get_id(world, e, id)
}

get_mut_raw :: proc(world: ^World, e: Entity, id: ID) -> rawptr {
	return ecs_get_mut_id(world, e, id)
}

modified :: proc(world: ^World, e: Entity, id: ID) { ecs_modified_id(world, e, id) }

pair :: proc(relation: Entity, target: Entity) -> ID {
	return ecs_make_pair(relation, target)
}

query :: proc(world: ^World, expression: cstring) -> ^Query {
	desc := ecs_query_desc_t{}
	desc.expr = expression
	return ecs_query_init(world, &desc)
}

query_free :: proc(q: ^Query) { ecs_query_fini(q) }

// Each returns an iterator over all entities matching id.
each :: proc(world: ^World, id: ID) -> Iter { return ecs_each_id(world, id) }

query_iterate :: proc(world: ^World, q: ^Query) -> Iter { return ecs_query_iter(world, q) }

// Next advances an iterator returned by each or query_iterate. The dispatch
// follows the Flecs C API: term iterators advance with ecs_each_next, query
// iterators with ecs_query_next.
next :: proc(it: ^Iter) -> bool {
	if it.query != nil {
		return ecs_query_next(it)
	}
	return ecs_each_next(it)
}

// Iter_free releases an iterator abandoned before next returned false. Calling
// it on a drained iterator is allowed but not required.
iter_free :: proc(it: ^Iter) { ecs_iter_fini(it) }

// Iter_count_now and iter_entities_now are only valid until the next call to
// next. The multi-pointer returned by iter_entities_now has no length; index
// it with iter_count_now.
iter_count_now :: proc(it: ^Iter) -> int { return int(it.count) }

iter_entities_now :: proc(it: ^Iter) -> [^]Entity { return cast([^]Entity)it.entities }

field_raw :: proc(it: ^Iter, size: uintptr, index: int) -> rawptr {
	return ecs_field_w_size(it, c.size_t(size), i8(index))
}

field_id :: proc(it: ^Iter, index: int) -> ID { return ecs_field_id(it, i8(index)) }

field_is_set :: proc(it: ^Iter, index: int) -> bool { return ecs_field_is_set(it, i8(index)) }

child_of :: proc() -> Entity { return EcsChildOf }
is_a :: proc() -> Entity { return EcsIsA }
on_add :: proc() -> Entity { return EcsOnAdd }
on_remove :: proc() -> Entity { return EcsOnRemove }
on_set :: proc() -> Entity { return EcsOnSet }
wildcard :: proc() -> Entity { return EcsWildcard }
any_id :: proc() -> Entity { return EcsAny }
