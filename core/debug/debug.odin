// debug —— 内存调试工具。
//
// 分区：
//   Tracking Allocator —— ODIN_DEBUG 下追踪泄漏与非法释放
package debug

import "base:runtime"
import "core:fmt"
import "core:mem"

// ------------------------------------------------------------------------------
// Tracking Allocator —— 泄漏/非法释放追踪
// ------------------------------------------------------------------------------

// 用法：`defer track_create(backing)` —— @(deferred_out=track_destroy) 使 defer 语句
// 立即执行本 proc，并在作用域结束时自动对返回值调用 track_destroy
// （打印泄漏与非法释放后销毁追踪器）。
track_create :: proc(backing_allocator := context.allocator) -> runtime.Allocator {
	when ODIN_DEBUG {
		track := new(mem.Tracking_Allocator)
		mem.tracking_allocator_init(track, backing_allocator)
		// 默认在 bad free 时 panic；想要"记录而不崩溃"就打开下面这行。
		// track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
		return mem.tracking_allocator(track)
	} else {
		return backing_allocator
	}
}

// 显式接受 allocator 参数，让调用点清楚自己传的是哪一个。
track_destroy :: proc(tracking_allocator: runtime.Allocator) {
	when ODIN_DEBUG {
		track := (^mem.Tracking_Allocator)(tracking_allocator.data)
		if len(track.allocation_map) > 0 {
			for _, entry in track.allocation_map {
				fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
			}
		}
		if len(track.bad_free_array) > 0 {
			for entry in track.bad_free_array {
				fmt.eprintf("%v bad free @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(track)
		free(track, track.backing)
	}
}
