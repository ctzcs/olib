package debug
import "core:fmt"
import "base:runtime"
import "core:mem"

// At the end of the callie's scope `track_destroy` will be run with the output of `track_create`
@(deferred_out=track_destroy)
track_create :: proc( backing_allocator := context.allocator ) -> runtime.Allocator {
    when ODIN_DEBUG{
        track := new(mem.Tracking_Allocator)
        mem.tracking_allocator_init(track, backing_allocator)
        // By default it'll panic on bad free. Setting this will have it not do so.
        // track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
        return mem.tracking_allocator(track)
    } else {
        return backing_allocator
    }
}

// Take an explict allocator to make it easier to see you're passing the right one.
track_destroy :: proc( tracking_allocator: runtime.Allocator ) {
    when ODIN_DEBUG {
        track := (^mem.Tracking_Allocator)(tracking_allocator.data)
        if len(track.allocation_map) > 0 {
            for _, entry in track.allocation_map {
                fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
            }
        }
        if len(track.bad_free_array) > 0 {
            for entry in track.bad_free_array {
                fmt.eprintf("%v bad free @ %v \n", entry.memory, entry.location)
            }
        }
        mem.tracking_allocator_destroy(track)
        free(track, track.backing)
    }
}