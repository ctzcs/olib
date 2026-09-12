# oflecs

Complete Odin bindings for the public C API of [Flecs](https://github.com/SanderMertens/flecs) v4.1.6.

The repository vendors the matching official amalgamated `flecs.c` and `flecs.h`. No Flecs download is required at build time.

## Coverage

- All public C structs, unions, enums, callback types and descriptors
- 708 linkable C procedures from the default v4.1.6 distribution
- 299 exported globals, including built-in entities, relationships, events, units and component IDs
- Core, pipeline, systems, timers, modules, REST, HTTP, JSON, Meta, Script, Metrics, Alerts, Stats, Units and Doc APIs
- A small optional helper layer for common world, entity, component and query operations

C++-only helper symbols and features disabled in the official default build (`FLECS_JOURNAL`, `FLECS_SCRIPT_MATH`, allocation tracking) are intentionally excluded.

## Build

### Windows

The convenience script prefers Zig because it produces an MSVC ABI static library compatible with Odin's default Windows linker:

```powershell
./build.ps1 -Configuration Release
```

Output: `windows/oflecs.lib`

Alternatively, use CMake with an installed MSVC toolchain:

```powershell
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

### Linux and macOS

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

The platform libraries are kept beside the package, matching Odin's vendor layout:

```text
oflecs.odin
windows/oflecs.lib
linux/liboflecs.a
linux-arm64/liboflecs.a
macos/liboflecs.a
macos-arm64/liboflecs.a
```

When the package is placed in your project's own `vendor` collection, no extra linker path is needed. The `foreign import lib` block selects the correct platform file automatically.

For example, keep this repository under your project as `project/vendor/oflecs` and import it as:

```odin
import "vendor:oflecs"
```

You do not need to modify or copy anything into the official Odin installation. You can also keep the repository elsewhere and register its parent directory as an Odin collection, then import the package by its collection name.

## Raw API

The raw API keeps Flecs' original C names:

```odin
package main

import flecs "oflecs"

Position :: struct {x, y: f32}

main :: proc() {
	world := flecs.ecs_init()
	defer flecs.ecs_fini(world)

	component_desc := flecs.ecs_component_desc_t{
		type = {size = size_of(Position), alignment = align_of(Position), name = "Position"},
	}
	position := flecs.ecs_component_init(world, &component_desc)
	e := flecs.ecs_new(world)
	value := Position{10, 20}
	flecs.ecs_set_id(world, e, position, size_of(Position), &value)

	desc := flecs.ecs_query_desc_t{}
	desc.expr = "Position"
	query := flecs.ecs_query_init(world, &desc)
	defer flecs.ecs_query_fini(query)

	iter := flecs.ecs_query_iter(world, query)
	for flecs.ecs_query_next(&iter) {
		positions := cast([^]Position)flecs.ecs_field_w_size(&iter, size_of(Position), 0)
		for index in 0..<iter.count {
			positions[index].x += 1
		}
	}
}
```

Global IDs use their C names, such as `EcsChildOf`, `EcsOnAdd` and `EcsWildcard`. C macro-style component IDs use a `_ID` suffix, such as `EcsComponent_ID` and `ecs_bool_t_ID`.

## Helper API

`helpers.odin` provides shorter names for common operations. The typed procs
derive the component from the Odin type: the first call for a type registers it
in that world under the Odin type name and caches the id.

```odin
world := oflecs.init()
defer oflecs.fini(world)

entity := oflecs.new_entity(world)
oflecs.set(world, entity, Position{10, 20})
oflecs.get(world, entity, Position).x += 1
```

`new_entity` also takes an initial id or a name; `add`, `remove`, `has` and
`modified` accept either a component ID or an Odin type:

```odin
e2 := oflecs.new_entity(world, oflecs.pair(oflecs.EcsChildOf, parent))
e3 := oflecs.new_entity(world, "Player")

oflecs.add(world, entity, Velocity)   // by type
oflecs.add(world, entity, tag_id)     // by id (pairs, builtin ids)
```

Queries are created either from a DSL expression or from a `Query_Terms` spec
with with/without/optional lists — the latter involves no string parsing:

```odin
q := oflecs.query(world, "Position, [in] Velocity") // DSL expression
defer oflecs.query_free(q)

// C++ builder style, as typed component lists:
q2 := oflecs.query_terms(world, {
	all      = {Position, Velocity},
	none     = {Dead},
	optional = {Mass},
	read     = {Velocity}, // matched read-only ([in])
})
```

**`query` or `each`?** Use `query` for anything iterated every frame: it is a
cached, reusable object, table matching happens once at creation. Use `each`
only for one-off, ad-hoc single-component loops (debug dumps, initialization
sweeps) where managing a query object is overkill — `each` re-evaluates the
match on every call and caches nothing.

Iteration helpers wrap the native stack iterator, so there is no heap
allocation and no separate free step. Two entry points produce an `Iter`:
`each(world, T)` for ad-hoc loops and `iterate(world, q)` for a cached query;
`next` accepts both:

```odin
it := oflecs.each(world, Position)      // or: oflecs.iterate(world, q)
for oflecs.next(&it) {
	positions := oflecs.field(&it, Position, 0)
	for i in 0..<oflecs.count(&it) {
		positions[i].x += 1
	}
}
```

`field` returns the term's component array as a typed multi-pointer — no
`size_of` and no cast at the call site. Use `field_raw` for untyped ids such
as pairs. `count` and `entities` describe the current batch and are only
valid until the next call to `next`.

Call `iter_free` only when abandoning an iterator before it ran to
completion.

Builtin ids are the exported globals themselves, with their C names:
`oflecs.EcsChildOf`, `oflecs.EcsOnAdd`, `oflecs.EcsWildcard`, ...

The raw API is preferred when porting Flecs examples or using advanced features. Component pointers belong to Flecs and must not be retained across structural changes.

## Regeneration and verification

After replacing `flecs.h`, regenerate exported globals with:

```powershell
./scripts/generate_globals.ps1
```

The smoke test in `smoke/main.odin` exercises native linking, component storage, exported IDs, helper iteration and raw query iteration:

```sh
odin run smoke/main.odin -file -collection:libs=..
```

Run it from the repository root; on case-sensitive systems the repository folder itself must be named `oflecs`. `oflecs.odin` was generated with [odin-c-bindgen](https://github.com/karl-zylinski/odin-c-bindgen) and checked against the symbols in the v4.1.6 static library. `build.ps1` rebuilds the platform library in its vendor directory; `CMakeLists.txt` remains available for maintainers who want a conventional external build tree.

See `THIRD_PARTY_NOTICES.md` for Flecs and generated-binding attribution.
