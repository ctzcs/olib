package tween

import math "core:math"

//region tween
Repeat_Mode :: enum u8 {
    Once,
    Loop,
    PingPong,
}

Tween :: struct($T: typeid) {
    using value: Interpolated(T),
    delay: f32,
    repeat_mode: Repeat_Mode,
}

Tween_Config :: struct {
    duration:    f32,
    delay:       f32,
    repeat_mode: Repeat_Mode,
    transition:  Transition,
}

TWEEN_CONFIG_DEFAULT :: Tween_Config{
    duration = 1.0,
    delay = 0,
    repeat_mode = .Once,
    transition = .Linear,
}

make :: proc(
    start, finish: $T,
    current_time: f32,
    transition: Transition,
    lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> Tween(T) {
    return Tween(T){
        value = Interpolated(T){
            start = start,
            finish = finish,
            start_time = current_time,
            speed = 1.0,
            transition = transition,
            lerp = lerp,
        },
        delay = 0,
        repeat_mode = .Once,
    }
}

make_ex :: proc(
    start, finish: $T,
    current_time: f32,
    config: Tween_Config,
    lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> Tween(T) {
    cfg := TWEEN_CONFIG_DEFAULT

    if config.duration > 0 {
        cfg.duration = config.duration
    }
    cfg.delay = math.max(config.delay, 0)
    cfg.repeat_mode = config.repeat_mode
    if config.transition != .None {
        cfg.transition = config.transition
    }

    tween := make(start, finish, current_time, cfg.transition, lerp)
    tween_set_duration(&tween, cfg.duration)
    tween_set_delay(&tween, cfg.delay)
    tween_set_repeat_mode(&tween, cfg.repeat_mode)
    return tween
}

tween_set_duration :: proc(tween: ^Tween($T), duration: f32) {
    interp_set_duration(&tween.value, duration)
}

tween_set_delay :: proc(tween: ^Tween($T), delay: f32) {
    tween.delay = math.max(delay, 0)
}

tween_set_repeat_mode :: proc(tween: ^Tween($T), repeat_mode: Repeat_Mode) {
    tween.repeat_mode = repeat_mode
}

tween_get_elapsed_seconds :: proc(tween: ^Tween($T), current_time: f32) -> f32 {
    return current_time - tween.start_time
}

tween_is_finished :: proc(tween: ^Tween($T), current_time: f32) -> bool {
    if tween.repeat_mode != .Once {
        return false
    }

    elapsed := tween_get_elapsed_seconds(tween, current_time) - tween.delay
    if elapsed <= 0 {
        return false
    }

    if tween.value.speed >= 1.0e20 {
        return true
    }

    return elapsed * tween.value.speed >= 1
}

tween_get_value :: proc(tween: ^Tween($T), current_time: f32) -> T {
    elapsed := tween_get_elapsed_seconds(tween, current_time) - tween.delay
    if elapsed <= 0 {
        return tween.value.start
    }

    if tween.value.speed >= 1.0e20 {
        return tween.value.finish
    }

    normalized_t := elapsed * tween.value.speed

    switch tween.repeat_mode {
    case .Once:
        if normalized_t >= 1 {
            return tween.value.finish
        }
        ratio := interp_get_ratio_internal(&tween.value, normalized_t)
        return tween.value.lerp(tween.value.start, tween.value.finish, ratio)

    case .Loop:
        local_t := normalized_t - math.floor(normalized_t)
        ratio := interp_get_ratio_internal(&tween.value, local_t)
        return tween.value.lerp(tween.value.start, tween.value.finish, ratio)

    case .PingPong:
        cycle := int(math.floor(normalized_t))
        local_t := normalized_t - f32(cycle)
        ratio := interp_get_ratio_internal(&tween.value, local_t)

        if cycle % 2 == 0 {
            return tween.value.lerp(tween.value.start, tween.value.finish, ratio)
        }
        return tween.value.lerp(tween.value.finish, tween.value.start, ratio)
    }

    return tween.value.finish
}

tween_set_value :: proc(tween: ^Tween($T), new_value: T, current_time: f32) {
    tween.start = interp_get_value(tween.value, current_time)
    tween.finish = new_value
    tween.start_time = current_time 
}

tween_set_transition_proc :: proc(tween: ^Tween($T), transition_proc: proc "contextless" (t: f32) -> f32) {
    interp_set_transition_proc(&tween.value, transition_proc)
}

tween_set_value_full :: proc(
    tween: ^Tween($T),
    now_value, new_value: T,
    current_time: f32,
    transition: Transition,
    lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) {
    tween.start = now_value
    tween.finish = new_value
    tween.start_time = current_time
    tween.transition = transition
    tween.transition_proc = nil
    tween.lerp = lerp
}
//endregion tween
