#+build !js
// 开发期编译子进程共享入口。只在后台线程使用，不要阻塞游戏帧。
package devbuild

import "core:os"
import "core:sync"

// core:os.process_start 会修改句柄继承属性，不支持并发。
// 游戏 DLL、Shader 与参数生成器共用这个锁；结果归调用方的 allocator。
@(private)
process_mutex: sync.Mutex

exec :: proc(desc: os.Process_Desc, allocator := context.allocator) -> (
	state: os.Process_State, stdout: []u8, stderr: []u8, err: os.Error,
) {
	sync.mutex_lock(&process_mutex)
	defer sync.mutex_unlock(&process_mutex)
	return os.process_exec(desc, allocator)
}
