package profiler

import "core:fmt"
import "core:time"

Profile_Stat :: struct {
    count: i64,
    total: time.Duration,
    max:   time.Duration,
}

profile_stats : map[string]Profile_Stat

Profile_Guard :: struct {
    name:  string,
    start: time.Time,
}

profile_init::proc(){
    profile_stats = make(map[string]Profile_Stat)
}


@(deferred_out=profile_scope_end)
profile_scope :: proc(name: string) -> Profile_Guard {
    return Profile_Guard{
        name  = name,
        start = time.now(), // [1]
    }
}

profile_scope_end :: proc(g: Profile_Guard) {
    d := time.since(g.start) // [1]
    s := profile_stats[g.name]
    s.count += 1
    s.total += d
    if d > s.max { s.max = d }
    profile_stats[g.name] = s
}

profile_dump :: proc() {
    for name, s in profile_stats {
        avg_ms := f64(time.duration_milliseconds(s.total)) / max(1.0, f64(s.count)) // [1]
        max_ms := f64(time.duration_milliseconds(s.max))
        tot_ms := f64(time.duration_milliseconds(s.total))
        fmt.printf("[PROFILE] %-20s count=%d avg=%.3fms max=%.3fms total=%.3fms\n",
                   name, s.count, avg_ms, max_ms, tot_ms)
    }
}