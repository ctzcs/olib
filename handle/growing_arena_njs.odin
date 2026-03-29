#+build !js
package handle

import vmem "core:mem/virtual"
import "base:runtime"

Growing_Arena :: vmem.Arena

@require_results
growing_arena_init :: proc(arena: ^Growing_Arena, block_size: int = GROWING_ARENA_DEFAULT_BLOCK_SIZE, allocator := context.allocator) -> runtime.Allocator_Error {
    return vmem.arena_init_growing(arena, uint(block_size))
}

growing_arena_destroy :: vmem.arena_destroy
growing_arena_free_all :: vmem.arena_free_all
growing_arena_allocator :: vmem.arena_allocator
GROWING_ARENA_DEFAULT_BLOCK_SIZE :: vmem.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE

growing_arena_initialized :: proc(arena: Growing_Arena) -> bool {
    return arena.curr_block != nil
}




