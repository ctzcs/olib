#+build js
package handle

import "core:mem"
import "base:runtime"

Growing_Arena :: mem.Dynamic_Arena

growing_arena_init :: proc(arena: ^Growing_Arena, block_size: int = GROWING_ARENA_DEFAULT_BLOCK_SIZE, allocator := context.allocator) -> runtime.Allocator_Error {
    mem.dynamic_arena_init(arena, block_allocator = allocator, array_allocator = allocator, block_size = block_size)
    return nil
}

growing_arena_destroy :: mem.dynamic_arena_destroy
growing_arena_free_all :: mem.dynamic_arena_free_all
growing_arena_allocator :: mem.dynamic_arena_allocator
GROWING_ARENA_DEFAULT_BLOCK_SIZE :: mem.DYNAMIC_ARENA_BLOCK_SIZE_DEFAULT

growing_arena_initialized :: proc(arena: Growing_Arena) -> bool {
    return arena.block_size != 0
}