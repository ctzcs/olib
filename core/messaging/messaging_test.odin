// messaging 包单元测试。
//
// 注意 Odin 的 proc 字面量无闭包：handler 需要的状态一律经 userdata 传入。
#+test
package messaging

import "core:testing"

@(private)
Spawn_Effect :: struct { x, y: f32 }
@(private)
Play_Sound  :: struct { id: int }
@(private)
Test_Cmd :: union {
	Spawn_Effect,
	Play_Sound,
}

// drain handler 的状态：记录 + 反向引用队列（演示 handler 内再入队）。
@(private)
Drain_State :: struct {
	queue: ^Command_Queue(Test_Cmd),
	log:   [dynamic]int,
}

@(private)
drain_handler :: proc(c: Test_Cmd, ud: rawptr) {
	s := (^Drain_State)(ud)
	switch v in c {
	case Play_Sound:
		append(&s.log, v.id)
		if v.id == 1 do queue_enqueue(s.queue, Play_Sound{99}) // 派生命令，留到下次
	case Spawn_Effect:
		append(&s.log, -1)
	}
}

@(test)
command_queue_drain_semantics :: proc(t: ^testing.T) {
	q: Command_Queue(Test_Cmd)
	defer queue_dispose(&q)

	testing.expect(t, queue_count(&q) == 0)

	queue_enqueue(&q, Play_Sound{1})
	queue_enqueue(&q, Spawn_Effect{0, 0})
	queue_enqueue(&q, Play_Sound{2})
	testing.expect(t, queue_count(&q) == 3)

	state: Drain_State
	defer delete(state.log)
	state.queue = &q

	// drain 开始时已入队的 3 条全部处理；handler 里再入队的 1 条留下次
	n := queue_drain(&q, drain_handler, &state)
	testing.expectf(t, n == 3, "drain 应处理 3 条, 实际 %d", n)
	testing.expect(t, len(state.log) == 3)
	testing.expectf(t, queue_count(&q) == 1, "派生命令应留到下次: %d", queue_count(&q))

	// 第二次 drain 处理派生命令
	clear(&state.log)
	n2 := queue_drain(&q, drain_handler, &state)
	testing.expectf(t, n2 == 1 && len(state.log) == 1 && state.log[0] == 99, "第二次 drain 应处理派生命令")
	testing.expect(t, queue_count(&q) == 0)
}

@(private)
count_handler :: proc(v: int, ud: rawptr) {
	p := (^int)(ud)
	p^ += 1
}

@(test)
command_queue_clear :: proc(t: ^testing.T) {
	q: Command_Queue(int)
	defer queue_dispose(&q)

	for i in 0..<5 do queue_enqueue(&q, i)
	total := 0
	n := queue_drain(&q, count_handler, &total)
	testing.expect(t, n == 5 && total == 5)

	for i in 0..<3 do queue_enqueue(&q, i)
	queue_clear(&q)
	testing.expect(t, queue_count(&q) == 0)
	n2 := queue_drain(&q, count_handler, &total)
	testing.expect(t, n2 == 0 && total == 5)
}

@(private)
Hit :: struct { target: int, damage: f32 }

@(test)
broadcast_channel_frame_semantics :: proc(t: ^testing.T) {
	ch: Broadcast_Channel(Hit)
	defer channel_dispose(&ch)

	// 第 0 帧：发布 a/b，尚未可见
	channel_publish(&ch, Hit{1, 10})
	channel_publish(&ch, Hit{2, 20})
	testing.expect(t, channel_count(&ch) == 0)
	testing.expect(t, channel_pending_count(&ch) == 2)

	// 第 1 帧开始：advance 后可见
	channel_advance_frame(&ch)
	testing.expect(t, channel_count(&ch) == 2)
	testing.expect(t, channel_pending_count(&ch) == 0)

	// 两个消费者读到同一批、同一份数据
	consumer_a := channel_messages(&ch)
	consumer_b := channel_messages(&ch)
	testing.expect(t, len(consumer_a) == 2 && consumer_a[0].target == 1 && consumer_a[1].damage == 20)
	testing.expect(t, &consumer_a[0] == &consumer_b[0]) // 同一片内存

	// 第 1 帧中再发布 c
	channel_publish(&ch, Hit{3, 30})
	testing.expect(t, channel_count(&ch) == 2) // 可见批不变

	// 第 2 帧：可见批换成 [c]，旧批作废
	channel_advance_frame(&ch)
	testing.expect(t, channel_count(&ch) == 1)
	testing.expect(t, channel_messages(&ch)[0].target == 3)

	// 无发布的帧：advance 后可见批为空
	channel_advance_frame(&ch)
	testing.expect(t, channel_count(&ch) == 0 && channel_pending_count(&ch) == 0)
}
