package oflecs

import "base:runtime"
import "core:c"
import "core:strings"

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

new_entity_plain :: proc(world: ^World) -> Entity { return ecs_new(world) }

new_entity_with :: proc(world: ^World, id: ID) -> Entity {
	return ecs_new_w_id(world, id)
}

new_entity_named :: proc(world: ^World, name: cstring) -> Entity {
	desc := ecs_entity_desc_t{name = name}
	return ecs_entity_init(world, &desc)
}

// new_entity creates an entity: empty, with an initial id (e.g. a pair), or
// with a name:
//
//	e1 := of.new_entity(world)
//	e2 := of.new_entity(world, of.pair(of.EcsChildOf, parent))
//	e3 := of.new_entity(world, "Player")
new_entity :: proc{new_entity_plain, new_entity_with, new_entity_named}

add_id :: proc(world: ^World, e: Entity, id: ID) { ecs_add_id(world, e, id) }
remove_id :: proc(world: ^World, e: Entity, id: ID) { ecs_remove_id(world, e, id) }
clear :: proc(world: ^World, e: Entity) { ecs_clear(world, e) }
delete :: proc(world: ^World, e: Entity) { ecs_delete(world, e) }

has_id :: proc(world: ^World, e: Entity, id: ID) -> bool { return ecs_has_id(world, e, id) }
is_alive :: proc(world: ^World, e: Entity) -> bool { return ecs_is_alive(world, e) }
lookup :: proc(world: ^World, path: cstring) -> Entity { return ecs_lookup(world, path) }
name :: proc(world: ^World, e: Entity) -> cstring { return ecs_get_name(world, e) }

modified_id :: proc(world: ^World, e: Entity, id: ID) { ecs_modified_id(world, e, id) }

pair :: proc(relation: Entity, target: Entity) -> ID {
	return ecs_make_pair(relation, target)
}

query_expr :: proc(world: ^World, expression: cstring) -> ^Query {
	desc := ecs_query_desc_t{}
	desc.expr = expression
	return ecs_query_init(world, &desc)
}

query_free :: proc(q: ^Query) { ecs_query_fini(q) }

// Each returns an iterator over all entities matching id. It creates no
// query object: nothing to cache, nothing to free, and the match is
// re-evaluated on every call. Use it for one-off, ad-hoc single-id loops
// (debug dumps, initialization sweeps). For anything iterated every frame,
// prefer a cached query.
each_id :: proc(world: ^World, id: ID) -> Iter { return ecs_each_id(world, id) }

// Iterate returns an iterator over the entities matched by a query. It pairs
// with each: each is the ad-hoc form, iterate the cached-query form.
iterate :: proc(world: ^World, q: ^Query) -> Iter { return ecs_query_iter(world, q) }

// Next advances an iterator returned by each or iterate. The dispatch
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

// count and entities describe the batch produced by the last call to next and
// are only valid until the following one. The multi-pointer returned by
// entities has no length; index it with count.
count :: proc(it: ^Iter) -> int { return int(it.count) }

entities :: proc(it: ^Iter) -> [^]Entity { return cast([^]Entity)it.entities }

field_raw :: proc(it: ^Iter, size: uintptr, index: int) -> rawptr {
	return ecs_field_w_size(it, c.size_t(size), i8(index))
}

// Field returns the term's component array as a typed multi-pointer, hiding
// the size and the cast. The result has no length; index it with count, and
// only until the next call to next.
//
//	positions := of.field(&it, Position, 0)
field :: proc(it: ^Iter, $T: typeid, index: int) -> [^]T {
	return cast([^]T)ecs_field_w_size(it, c.size_t(size_of(T)), i8(index))
}

field_id :: proc(it: ^Iter, index: int) -> ID { return ecs_field_id(it, i8(index)) }

field_is_set :: proc(it: ^Iter, index: int) -> bool { return ecs_field_is_set(it, i8(index)) }

////////////////////////////////////////////////////////////////////////////////
// Typed API
//
// The procs below take an Odin type instead of a component ID, mirroring the
// ergonomics of the Flecs C++ API. The first call for a type registers the
// component in that world under the Odin type name and caches the id; later
// calls reuse the cache. The cache is process-global, keyed per world, and
// not thread-safe.

@(private)
Component_Key :: struct {
	world: ^World,
	type:  typeid,
}

// Keyed by (world, type) so the same Odin type gets a distinct component id
// per world. A single flat map: map-of-maps values read back corrupted on the
// current toolchain.
@(private)
component_ids: map[Component_Key]Entity

// component_id returns the id of component T in world, registering the
// component under the Odin type name on first use.
component_id :: proc(world: ^World, $T: typeid) -> Entity {
	return component_id_of(world, T)
}

// component_id_of is the runtime-typeid variant of component_id, used
// internally by query_terms for dynamically built component lists.
@(private)
component_id_of :: proc(world: ^World, t: typeid) -> Entity {
	key := Component_Key{world, t}
	if id, found := component_ids[key]; found {
		return id
	}
	if component_ids == nil {
		component_ids = make(map[Component_Key]Entity)
	}
	name := strings.clone_to_cstring(type_name_of(t))
	// Reuse a component already registered under this name (e.g. via the raw
	// ecs_component_init) instead of creating a duplicate-named entity.
	if existing := ecs_lookup(world, name); existing != 0 {
		component_ids[key] = existing
		return existing
	}
	info := type_info_of(t)
	desc := ecs_component_desc_t{}
	desc.type.size = cast(ecs_size_t)info.size
	desc.type.alignment = cast(ecs_size_t)info.align
	// Flecs copies the name into the world; the permanent allocation keeps the
	// cstring valid regardless of that and leaks once per component type.
	desc.type.name = name
	id := ecs_component_init(world, &desc)
	component_ids[key] = id
	return id
}

@(private)
type_name_of :: proc(t: typeid) -> string {
	#partial switch v in type_info_of(t).variant {
	case runtime.Type_Info_Named:
		return v.name
	}
	return "Component"
}

// set adds component T to e when missing and copies value into it.
set :: proc(world: ^World, e: Entity, value: $T) {
	v := value
	ecs_set_id(world, e, component_id(world, T), c.size_t(size_of(T)), &v)
}

// get returns a read-only pointer to e's component T, or nil when absent.
get :: proc(world: ^World, e: Entity, $T: typeid) -> ^T {
	return cast(^T)ecs_get_id(world, e, component_id(world, T))
}

// get_mut returns a writable pointer to e's component T and marks it modified.
get_mut :: proc(world: ^World, e: Entity, $T: typeid) -> ^T {
	return cast(^T)ecs_get_mut_id(world, e, component_id(world, T))
}

add_t :: proc(world: ^World, e: Entity, $T: typeid) { ecs_add_id(world, e, component_id(world, T)) }

remove_t :: proc(world: ^World, e: Entity, $T: typeid) {
	ecs_remove_id(world, e, component_id(world, T))
}

has_t :: proc(world: ^World, e: Entity, $T: typeid) -> bool {
	return ecs_has_id(world, e, component_id(world, T))
}

modified_t :: proc(world: ^World, e: Entity, $T: typeid) {
	ecs_modified_id(world, e, component_id(world, T))
}

// add, remove, has and modified accept either a component ID or an Odin type:
//
//	of.add(world, e, position_id)
//	of.add(world, e, Position)
add :: proc{add_id, add_t}
remove :: proc{remove_id, remove_t}
has :: proc{has_id, has_t}
modified :: proc{modified_id, modified_t}

each_t :: proc(world: ^World, $T: typeid) -> Iter {
	return ecs_each_id(world, component_id(world, T))
}

// Query_Terms describes a query as typed component lists, the Flecs C++
// builder style (with/without/optional) without an expression string.
//
//	q := of.query_terms(world, {
//		all      = {Position, Velocity},  // entities must have both
//		none     = {Dead},                // and must not have Dead
//		optional = {Mass},                // Mass may match; check field_is_set
//		read     = {Velocity},            // Velocity matched read-only ([in])
//	})
Query_Terms :: struct {
	all:      []typeid,
	none:     []typeid,
	optional: []typeid,
	read:     []typeid,
}

// query_terms builds a query from a Query_Terms spec. Call it directly (rather
// than through the query group) when using an untyped compound literal:
//
//	q := of.query_terms(world, {all = {Position}, none = {Dead}})
query_terms :: proc(world: ^World, spec: Query_Terms) -> ^Query {
	desc := ecs_query_desc_t{}
	i := 0
	add_term :: proc(desc: ^ecs_query_desc_t, i: ^int, world: ^World, t: typeid) {
		assert(i^ < FLECS_TERM_COUNT_MAX, "query has too many terms")
		desc.terms[i^].id = component_id_of(world, t)
		i^ += 1
	}
	for t in spec.all {
		add_term(&desc, &i, world, t)
	}
	for t in spec.none {
		add_term(&desc, &i, world, t)
		desc.terms[i - 1].oper = i16(ecs_oper_kind_t.Not)
	}
	for t in spec.optional {
		add_term(&desc, &i, world, t)
		desc.terms[i - 1].oper = i16(ecs_oper_kind_t.Optional)
	}
	// read marks already-added terms as [in]; it does not add terms itself.
	for t in spec.read {
		id := component_id_of(world, t)
		for j in 0..<i {
			if desc.terms[j].id == id {
				desc.terms[j].inout = i16(ecs_inout_kind_t.In)
			}
		}
	}
	return ecs_query_init(world, &desc)
}

// query creates a cached, reusable query from a DSL expression or a
// Query_Terms spec:
//
//	q := of.query(world, "Position, [in] Velocity")
//	q := of.query(world, of.Query_Terms{all = {Position, Velocity}})
//
// (call query_terms directly to use an untyped literal). Table matching
// happens once at creation — a query is the default choice for anything
// iterated every frame. Create once, iterate with iterate, release with
// query_free. For one-off single-component loops, see each.
query :: proc{query_expr, query_terms}

// each accepts either a component ID or an Odin type. Unlike query it builds
// no cached object — prefer it only for one-off, ad-hoc loops.
each :: proc{each_id, each_t}
