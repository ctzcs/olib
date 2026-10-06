// messaging —— 单线程更新循环的两种消息原语（对位 DragonLib Engine.Messaging）。
//
//   Command_Queue(T)：单消费者 FIFO。生产者入队，唯一消费者 Drain；
//     Drain 只处理调用开始时已入队的命令，handler 里再入队的留到下一次
//     （消费者不会在同一帧里被自己派生的命令递归轰炸）。
//
//   Broadcast_Channel(T)：多消费者、延迟一帧。本帧 Publish 的消息在下一帧
//     开始时（AdvanceFrame）对所有消费者可见，读到的是同一批数据；
//     每帧开始调用一次 AdvanceFrame（生产者/消费者运行之前）。
//
// 两者都为单线程更新循环设计（无锁、无等待）。零值即可用（走
// context.allocator），dispose 释放内部缓冲。
//
// 用法：
//   import msg "olib:engine/messaging"
//
//   Cmd :: union { Spawn, Play_Sound }
//   queue:  msg.Command_Queue(Cmd)   defer msg.queue_dispose(&queue)
//   channel: msg.Broadcast_Channel(Hit) defer msg.channel_dispose(&channel)
package messaging

// ---------------------------------------------------------------------------
// Command_Queue —— 单消费者
// ---------------------------------------------------------------------------

Command_Queue :: struct($T: typeid) {
	items: [dynamic]T,
	head:  int, // 下一个待消费下标
}

// 入队（生产者任意方调用）。
queue_enqueue :: proc(q: ^Command_Queue($T), item: T) {
	append(&q.items, item)
}

// 待消费数量。
queue_count :: proc(q: ^Command_Queue($T)) -> int {
	return len(q.items) - q.head
}

// 消费一批：只处理调用开始时已入队的命令，返回处理数量。
// handler 内 enqueue 的命令留给下一次 drain。
// 注意 Odin 的 proc 字面量无闭包：需要状态的 handler 用 userdata 传入。
queue_drain :: proc(q: ^Command_Queue($T), handler: proc(item: T, userdata: rawptr), userdata: rawptr = nil) -> int {
	n := len(q.items) - q.head
	for i in 0..<n {
		handler(q.items[q.head], userdata)
		q.head += 1
	}
	if q.head == len(q.items) {
		clear(&q.items) // 保留容量，头部归零
		q.head = 0
	}
	return n
}

// 丢弃全部未消费命令。
queue_clear :: proc(q: ^Command_Queue($T)) {
	clear(&q.items)
	q.head = 0
}

queue_dispose :: proc(q: ^Command_Queue($T)) {
	delete(q.items)
	q.items = {}
	q.head = 0
}

// ---------------------------------------------------------------------------
// Broadcast_Channel —— 多消费者，延迟一帧
// ---------------------------------------------------------------------------

Broadcast_Channel :: struct($T: typeid) {
	current: [dynamic]T, // 本帧可见批（只读约定）
	pending: [dynamic]T, // 等待下一帧
}

// 发布：下一帧开始时可见。
channel_publish :: proc(ch: ^Broadcast_Channel($T), message: T) {
	append(&ch.pending, message)
}

// 本帧可见的消息批（所有消费者读到同一份切片）。
channel_messages :: proc(ch: ^Broadcast_Channel($T)) -> []T {
	return ch.current[:]
}

channel_count :: proc(ch: ^Broadcast_Channel($T)) -> int {
	return len(ch.current)
}

channel_pending_count :: proc(ch: ^Broadcast_Channel($T)) -> int {
	return len(ch.pending)
}

// 每帧开始调用一次（生产者/消费者运行之前）：
// pending 变为本帧可见批，上一帧的可见批作废。
channel_advance_frame :: proc(ch: ^Broadcast_Channel($T)) {
	ch.current, ch.pending = ch.pending, ch.current
	clear(&ch.pending)
}

// 清空可见批与待发批。
channel_clear :: proc(ch: ^Broadcast_Channel($T)) {
	clear(&ch.current)
	clear(&ch.pending)
}

channel_dispose :: proc(ch: ^Broadcast_Channel($T)) {
	delete(ch.current)
	delete(ch.pending)
	ch.current = {}
	ch.pending = {}
}
