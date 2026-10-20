#+test
package rendering2d

import "core:fmt"
import "core:strings"
import "core:testing"

// 标准 include olib/sprite.hlsli 的块大小必须等于 Render2D 写入的大小；宿主改块时这里失败，提醒同步 include。
@(test)
sprite_include_matches_host_blocks :: proc(t: ^testing.T) {
	text := string(#load("../../../../kit/rendering/shader/lang/include/olib/sprite.hlsli"))
	testing.expect_value(t, include_block_size(text, "OlibVertex"), SPRITE_VERTEX_BLOCK_SIZE)
	testing.expect_value(t, include_block_size(text, "OlibFrame"), SPRITE_FRAME_BLOCK_SIZE)
}

// 计算标准 include 里某个 cbuffer 的字节数；引擎块只用 float4x4 与 float4，遇到其他成员返回 -1。
@(private)
include_block_size :: proc(text, name: string) -> int {
	start := strings.index(text, fmt.tprintf("cbuffer %s ", name))
	if start < 0 do return -1
	open := strings.index_byte(text[start:], '{')
	close := strings.index_byte(text[start:], '}')
	if open < 0 || close < open do return -1
	size := 0
	for line in strings.split_lines(text[start+open+1:start+close], context.temp_allocator) {
		member := line
		if comment := strings.index(member, "//"); comment >= 0 do member = member[:comment]
		member = strings.trim_space(member)
		switch {
		case member == "":
		case strings.has_prefix(member, "float4x4 "):
			size += 64
		case strings.has_prefix(member, "float4 "):
			size += 16
		case:
			return -1
		}
	}
	return size
}
