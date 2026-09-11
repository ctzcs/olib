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

`helpers.odin` provides shorter names for common operations:

```odin
world := oflecs.init()
defer oflecs.fini(world)

position := oflecs.component(world, "Position", size_of(Position), align_of(Position))
entity := oflecs.new_entity(world)
value := Position{10, 20}
oflecs.set_raw(world, entity, position, &value, size_of(Position))
```

Iteration helpers wrap the native stack iterator, so there is no heap
allocation and no separate free step. `next` accepts iterators from both
`each` and `query_iterate`:

```odin
it := oflecs.each(world, position)
for oflecs.next(&it) {
	positions := cast([^]Position)oflecs.field_raw(&it, size_of(Position), 0)
	for i in 0..<oflecs.iter_count_now(&it) {
		positions[i].x += 1
	}
}
```

Call `iter_free` only when abandoning an iterator before it ran to
completion.

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
