#+build js
// growing 的平台后端（web）：Dynamic_Arena。
// wasm 无虚存 API，改用堆分配的动态 arena；native 版见 arena_default.odin。
package growing

import "base:runtime"
import "core:mem"

Arena :: mem.Dynamic_Arena

arena_init :: proc(arena: ^Arena, block_size: int = ARENA_DEFAULT_BLOCK_SIZE, allocator := context.allocator) -> runtime.Allocator_Error {
	mem.dynamic_arena_init(arena, block_allocator = allocator, array_allocator = allocator, block_size = block_size)
	return nil
}

arena_destroy           :: mem.dynamic_arena_destroy
arena_free_all          :: mem.dynamic_arena_free_all
arena_allocator         :: mem.dynamic_arena_allocator
ARENA_DEFAULT_BLOCK_SIZE :: mem.DYNAMIC_ARENA_BLOCK_SIZE_DEFAULT

arena_initialized :: proc(arena: Arena) -> bool {
	return arena.block_size != 0
}
