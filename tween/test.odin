package tween

import fmt "core:fmt"
import time "core:time"

RUN_STRESS_TEST :: false

managed_value: f32
managed_value_b: f32
managed_value_c: f32
managed_step_count: i32
managed_sequence_callback_count: i32
managed_start_count: i32
managed_complete_count: i32
managed_kill_count: i32

lerp_f32 :: proc "contextless" (a, b: f32, ratio: f32) -> f32 {
    return a + (b - a) * ratio
}

Stress_Result :: struct {
    tween_count:      int,
    frames:           int,
    create_ms:        f64,
    total_update_ms:  f64,
    avg_update_ms:    f64,
    max_update_ms:    f64,
    remaining_nodes:  int,
    sample_checksum:  f64,
}

run_manager_stress_case :: proc(
    tween_count: int,
    frames: int = 240,
    dt: f32 = 1.0 / 60.0,
    duration: f32 = 10.0,
) -> Stress_Result {
    mgr := manager_make()
    values: [dynamic]f32
    resize(&values, tween_count)

    create_start := time.now()
    for i := 0; i < tween_count; i += 1 {
        tw := make_ex(f32(0), f32((i % 100) + 1), 0, Tween_Config{
            duration = duration,
            transition = .Linear,
        }, lerp_f32)
        _ = manager_add_tween_to(&mgr, tw, &values[i])
    }
    create_elapsed := time.since(create_start)

    total_update: time.Duration
    max_update: time.Duration

    for frame := 0; frame < frames; frame += 1 {
        frame_start := time.now()
        manager_update(&mgr, dt)
        frame_elapsed := time.since(frame_start)
        total_update += frame_elapsed
        if frame_elapsed > max_update {
            max_update = frame_elapsed
        }
    }

    sample_count := tween_count
    if sample_count > 16 {
        sample_count = 16
    }

    sample_checksum: f64
    for i := 0; i < sample_count; i += 1 {
        sample_checksum += f64(values[i])
    }

    result := Stress_Result{
        tween_count = tween_count,
        frames = frames,
        create_ms = time.duration_milliseconds(create_elapsed),
        total_update_ms = time.duration_milliseconds(total_update),
        avg_update_ms = time.duration_milliseconds(total_update) / f64(max(1, frames)),
        max_update_ms = time.duration_milliseconds(max_update),
        remaining_nodes = mgr.stats.total_nodes,
        sample_checksum = sample_checksum,
    }

    delete(values)
    manager_delete(&mgr)
    return result
}

print_stress_result :: proc(result: Stress_Result, frame_budget_ms: f64) {
    within_budget := result.avg_update_ms <= frame_budget_ms
    fmt.printf(
        "count=%7d create=%8.3fms update_total=%8.3fms avg_frame=%7.3fms max_frame=%7.3fms remain=%7d checksum=%8.3f budget_ok=%v\n",
        result.tween_count,
        result.create_ms,
        result.total_update_ms,
        result.avg_update_ms,
        result.max_update_ms,
        result.remaining_nodes,
        result.sample_checksum,
        within_budget,
    )
}

run_stress_step :: proc(best_sustainable: ^int, tween_count: int, frame_budget_ms: f64) -> bool {
    result := run_manager_stress_case(tween_count)
    print_stress_result(result, frame_budget_ms)

    if result.avg_update_ms <= frame_budget_ms {
        best_sustainable^ = tween_count
    }

    // 超过 3 倍 60 FPS 帧预算后提前停止，避免本地压测时间过长。
    return result.avg_update_ms <= frame_budget_ms * 3.0
}

print_manager_stress_test :: proc() {
    fmt.println("== manager stress ==")

    frame_budget_ms: f64 = 1000.0 / 60.0
    best_sustainable := 0

    should_continue := run_stress_step(&best_sustainable, 1000, frame_budget_ms)
    if should_continue do should_continue = run_stress_step(&best_sustainable, 5000, frame_budget_ms)
    if should_continue do should_continue = run_stress_step(&best_sustainable, 10000, frame_budget_ms)
    if should_continue do should_continue = run_stress_step(&best_sustainable, 20000, frame_budget_ms)
    if should_continue do should_continue = run_stress_step(&best_sustainable, 50000, frame_budget_ms)
    if should_continue do should_continue = run_stress_step(&best_sustainable, 100000, frame_budget_ms)
    if should_continue do _ = run_stress_step(&best_sustainable, 200000, frame_budget_ms)

    fmt.printf("estimated_capacity_60fps=%d tweens avg_frame_budget=%.3fms\n", best_sustainable, frame_budget_ms)
}

print_once_test :: proc() {
    fmt.println("== once ==")

    tw := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .EaseOut,
    }, lerp_f32)

    for t: f32 = 0; t <= 1.25; t += 0.25 {
        fmt.println(
            "t=", t,
            " value=", tween_get_value(&tw, t),
            " finished=", tween_is_finished(&tw, t),
        )
    }
}

print_loop_test :: proc() {
    fmt.println("== delay + loop ==")

    tw := make_ex(f32(0), f32(1), 0, Tween_Config{
        duration = 0.5,
        delay = 0.25,
        repeat_mode = .Loop,
        transition = .Linear,
    }, lerp_f32)

    for t: f32 = 0; t <= 1.75; t += 0.05 {
        fmt.println(
            "t=", t,
            " value=", tween_get_value(&tw, t),
            " finished=", tween_is_finished(&tw, t),
        )
    }
}

print_pingpong_test :: proc() {
    fmt.println("== pingpong ==")

    tw := make_ex(f32(0), f32(100), 0, Tween_Config{
        duration = 1.0,
        repeat_mode = .PingPong,
        transition = .Linear,
    }, lerp_f32)

    for t: f32 = 0; t <= 3.0; t += 0.5 {
        fmt.println(
            "t=", t,
            " value=", tween_get_value(&tw, t),
            " finished=", tween_is_finished(&tw, t),
        )
    }
}

set_managed_value :: proc "contextless" (value: f32) {
    managed_value = value
}

set_managed_value_b :: proc "contextless" (value: f32) {
    managed_value_b = value
}

set_managed_value_c :: proc "contextless" (value: f32) {
    managed_value_c = value
}

get_managed_value :: proc "contextless" () -> f32 {
    return managed_value
}

get_managed_value_b :: proc "contextless" () -> f32 {
    return managed_value_b
}

on_managed_step_complete :: proc "contextless" (_: Tween_Handle) {
    managed_step_count += 1
}

on_managed_start :: proc "contextless" (_: Tween_Handle) {
    managed_start_count += 1
}

on_managed_complete :: proc "contextless" (_: Tween_Handle) {
    managed_complete_count += 1
}

on_managed_kill :: proc "contextless" (_: Tween_Handle) {
    managed_kill_count += 1
}

on_sequence_callback :: proc "contextless" () {
    managed_sequence_callback_count += 1
}

reset_managed_test_state :: proc() {
    managed_value = -1
    managed_value_b = -1
    managed_value_c = -1
    managed_step_count = 0
    managed_sequence_callback_count = 0
    managed_start_count = 0
    managed_complete_count = 0
    managed_kill_count = 0
}

get_loops_done_or_default :: proc(mgr: Tween_Manager, h: Tween_Handle, fallback: i32 = -1) -> i32 {
    if node := manager_get_node_ptr(mgr, h); node != nil {
        return node.control.loops_done
    }
    return fallback
}

print_manager_loop_step :: proc(mgr: Tween_Manager, h: Tween_Handle, step: int) {
    fmt.println(
        "step=", step,
        " now=", mgr.now,
        " value=", managed_value,
        " loops_done=", get_loops_done_or_default(mgr, h),
        " step_callbacks=", managed_step_count,
        " valid=", manager_is_handle_valid(mgr, h),
    )
}

setup_manager_loop_test :: proc(mgr: ^Tween_Manager, loop_count: i32 = -1) -> Tween_Handle {
    tw := make_ex(f32(0), f32(1), 0, Tween_Config{
        duration = 0.5,
        repeat_mode = .Loop,
        transition = .Linear,
    }, lerp_f32)

    reset_managed_test_state()
    h := manager_add_tween(mgr, tw, set_managed_value)
    if loop_count > 0 {
        _ = manager_set_loops(mgr, h, loop_count, .Loop)
    }
    _ = manager_on_step_complete(mgr, h, on_managed_step_complete)
    return h
}

print_manager_test :: proc() {
    fmt.println("== manager ==")

    mgr := manager_make()
    tw := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        delay = 0.25,
        transition = .Linear,
    }, lerp_f32)

    managed_value = -1
    h := manager_add_tween(&mgr, tw, set_managed_value)
    fmt.println("registered value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))

    for i := 0; i < 6; i += 1 {
        manager_update(&mgr, 0.25)
        fmt.println(
            "step=", i,
            " now=", mgr.now,
            " value=", managed_value,
            " valid=", manager_is_handle_valid(mgr, h),
        )
    }

    h = manager_add_tween(&mgr, tw, set_managed_value)
    manager_update(&mgr, 0.5)
    fmt.println("before rewind value=", managed_value)
    _ = manager_rewind(&mgr, h)
    fmt.println("after rewind value=", managed_value)
    _ = manager_restart(&mgr, h)
    manager_update(&mgr, 0.5)
    fmt.println("after restart value=", managed_value)

    manager_delete(&mgr)
}

print_manager_loop_test :: proc() {
    fmt.println("== manager loop ==")

    mgr := manager_make()
    h := setup_manager_loop_test(&mgr)

    for i := 0; i < 6; i += 1 {
        manager_update(&mgr, 0.25)
        print_manager_loop_step(mgr, h, i)
    }

    manager_delete(&mgr)
}

print_manager_finite_loop_test :: proc() {
    fmt.println("== manager finite loop ==")

    mgr := manager_make()
    h := setup_manager_loop_test(&mgr, 3)

    for i := 0; i < 7; i += 1 {
        manager_update(&mgr, 0.25)
        print_manager_loop_step(mgr, h, i)
    }

    manager_delete(&mgr)
}

print_manager_sequence_append_test :: proc() {
    fmt.println("== manager sequence append ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween(&mgr, seq, tw_a, set_managed_value)
    _, _ = sequence_append_tween(&mgr, seq, tw_b, set_managed_value_b)

    for i := 0; i < 5; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println("step=", i, " now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " seq_valid=", manager_is_handle_valid(mgr, seq))
    }

    manager_delete(&mgr)
}

print_manager_sequence_join_callback_test :: proc() {
    fmt.println("== manager sequence join + callback ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween(&mgr, seq, tw_a, set_managed_value)
    _, _ = sequence_join_tween(&mgr, seq, tw_b, set_managed_value_b)
    _ = sequence_append_callback(&mgr, seq, on_sequence_callback)

    for i := 0; i < 4; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println("step=", i, " now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " callbacks=", managed_sequence_callback_count, " seq_valid=", manager_is_handle_valid(mgr, seq))
    }

    manager_delete(&mgr)
}

print_manager_sequence_restart_test :: proc() {
    fmt.println("== manager sequence rewind + restart ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween(&mgr, seq, tw_a, set_managed_value)
    _, _ = sequence_join_tween(&mgr, seq, tw_b, set_managed_value_b)
    _ = sequence_append_callback(&mgr, seq, on_sequence_callback)
    _ = manager_set_auto_kill(&mgr, seq, false)

    manager_update(&mgr, 0.5)
    fmt.println("before rewind now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " callbacks=", managed_sequence_callback_count, " seq_valid=", manager_is_handle_valid(mgr, seq))

    _ = manager_rewind(&mgr, seq)
    fmt.println("after rewind now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " callbacks=", managed_sequence_callback_count, " seq_valid=", manager_is_handle_valid(mgr, seq))

    managed_sequence_callback_count = 0
    _ = manager_restart(&mgr, seq)
    manager_update(&mgr, 1.0)
    fmt.println("after restart now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " callbacks=", managed_sequence_callback_count, " seq_valid=", manager_is_handle_valid(mgr, seq))

    manager_delete(&mgr)
}

print_manager_sequence_insert_test :: proc() {
    fmt.println("== manager sequence insert ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween(&mgr, seq, tw_a, set_managed_value)
    _, _ = sequence_insert_tween(&mgr, seq, 0.5, tw_b, set_managed_value_b)

    for i := 0; i < 4; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println("step=", i, " now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " seq_valid=", manager_is_handle_valid(mgr, seq))
    }

    manager_delete(&mgr)
}

print_manager_sequence_prepend_test :: proc() {
    fmt.println("== manager sequence prepend ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween(&mgr, seq, tw_a, set_managed_value)
    _, _ = sequence_prepend_tween(&mgr, seq, tw_b, set_managed_value_b)

    for i := 0; i < 5; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println("step=", i, " now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " seq_valid=", manager_is_handle_valid(mgr, seq))
    }

    manager_delete(&mgr)
}

print_manager_callback_api_test :: proc() {
    fmt.println("== manager callback api ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    h := manager_add_tween(&mgr, tw, set_managed_value)
    _ = manager_on_start(&mgr, h, on_managed_start)
    _ = manager_on_complete(&mgr, h, on_managed_complete)
    _ = manager_on_kill(&mgr, h, on_managed_kill)

    manager_update(&mgr, 0.5)
    fmt.println("after half start=", managed_start_count, " complete=", managed_complete_count, " kill=", managed_kill_count)

    _ = manager_clear_callbacks(&mgr, h)
    _ = manager_on_kill(&mgr, h, on_managed_kill)
    _ = manager_kill(&mgr, h)
    fmt.println("after kill start=", managed_start_count, " complete=", managed_complete_count, " kill=", managed_kill_count)

    h = manager_add_tween(&mgr, tw, set_managed_value)
    _ = manager_set_callbacks(&mgr, h, Tween_Callbacks{
        on_start = on_managed_start,
        on_complete = on_managed_complete,
    })
    manager_update(&mgr, 1.0)
    fmt.println("after set_callbacks start=", managed_start_count, " complete=", managed_complete_count, " kill=", managed_kill_count)

    manager_delete(&mgr)
}

print_manager_property_binding_test :: proc() {
    fmt.println("== manager property binding ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    h := manager_add_tween_to(&mgr, tw, &managed_value)
    fmt.println("registered value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))

    manager_update(&mgr, 0.5)
    fmt.println("after half value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))

    manager_update(&mgr, 0.5)
    fmt.println("after full value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))

    manager_delete(&mgr)
}

print_manager_sequence_property_binding_test :: proc() {
    fmt.println("== manager sequence property binding ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween_to(&mgr, seq, tw_a, &managed_value)
    _, _ = sequence_join_tween_to(&mgr, seq, tw_b, &managed_value_b)

    for i := 0; i < 3; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println("step=", i, " now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " seq_valid=", manager_is_handle_valid(mgr, seq))
    }

    manager_delete(&mgr)
}

print_manager_property_api_test :: proc() {
    fmt.println("== manager property api ==")

    mgr := manager_make()
    reset_managed_test_state()
    managed_value = 3

    h := manager_add_property_tween(&mgr, get_managed_value, set_managed_value, f32(13), Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    fmt.println("registered value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))
    manager_update(&mgr, 0.5)
    fmt.println("after half value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))
    manager_update(&mgr, 0.5)
    fmt.println("after full value=", managed_value, " valid=", manager_is_handle_valid(mgr, h))

    manager_delete(&mgr)
}

print_manager_sequence_property_api_test :: proc() {
    fmt.println("== manager sequence property api ==")

    mgr := manager_make()
    reset_managed_test_state()
    managed_value = 3
    managed_value_b = 40

    seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_property_tween(&mgr, seq, get_managed_value, set_managed_value, f32(13), Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    _, _ = sequence_join_property_tween(&mgr, seq, get_managed_value_b, set_managed_value_b, f32(140), Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    for i := 0; i < 3; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println("step=", i, " now=", mgr.now, " a=", managed_value, " b=", managed_value_b, " seq_valid=", manager_is_handle_valid(mgr, seq))
    }

    manager_delete(&mgr)
}

print_manager_nested_sequence_test :: proc() {
    fmt.println("== manager nested sequence ==")

    mgr := manager_make()
    reset_managed_test_state()

    tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)
    tw_c := make_ex(f32(1000), f32(2000), 0, Tween_Config{
        duration = 1.0,
        transition = .Linear,
    }, lerp_f32)

    child_seq := manager_add_sequence(&mgr)
    _, _ = sequence_append_tween(&mgr, child_seq, tw_a, set_managed_value)

    parent_seq := manager_add_sequence(&mgr)
    _ = sequence_append(&mgr, parent_seq, child_seq)

    _, _ = sequence_append_tween(&mgr, child_seq, tw_b, set_managed_value_b)
    _, _ = sequence_append_tween(&mgr, parent_seq, tw_c, set_managed_value_c)

    for i := 0; i < 7; i += 1 {
        manager_update(&mgr, 0.5)
        fmt.println(
            "step=", i,
            " now=", mgr.now,
            " a=", managed_value,
            " b=", managed_value_b,
            " c=", managed_value_c,
            " parent_valid=", manager_is_handle_valid(mgr, parent_seq),
            " child_valid=", manager_is_handle_valid(mgr, child_seq),
        )
    }

    manager_delete(&mgr)
}

main :: proc() {
    print_once_test()
    fmt.println()
    print_loop_test()
    fmt.println()
    print_pingpong_test()
    fmt.println()
    print_manager_test()
    fmt.println()
    print_manager_loop_test()
    fmt.println()
    print_manager_finite_loop_test()
    fmt.println()
    print_manager_sequence_append_test()
    fmt.println()
    print_manager_sequence_join_callback_test()
    fmt.println()
    print_manager_sequence_restart_test()
    fmt.println()
    print_manager_sequence_insert_test()
    fmt.println()
    print_manager_sequence_prepend_test()
    fmt.println()
    print_manager_callback_api_test()
    fmt.println()
    print_manager_property_binding_test()
    fmt.println()
    print_manager_sequence_property_binding_test()
    fmt.println()
    print_manager_property_api_test()
    fmt.println()
    print_manager_sequence_property_api_test()
    fmt.println()
    print_manager_nested_sequence_test()

    if RUN_STRESS_TEST {
        fmt.println()
        print_manager_stress_test()
    }
}
