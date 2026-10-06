// profiler —— 轻量作用域计时统计。
//
// 分区：
//   数据 —— 统计表与 Guard 类型（含 profile_init）
//   Scope Guard —— @(deferred_out) 作用域计时
//   输出 —— profile_dump
package profiler

import "core:fmt"
import "core:time"

// ------------------------------------------------------------------------------
// 数据 —— 统计表与 Guard 类型
// ------------------------------------------------------------------------------

Profile_Stat :: struct {
	count: i64,
	total: time.Duration,
	max:   time.Duration,
}

Profile_Guard :: struct {
	name:  string,
	start: time.Time,
}

// 全局统计表（名字 -> Profile_Stat）。使用前先调 profile_init 分配。
profile_stats: map[string]Profile_Stat

profile_init :: proc() {
	profile_stats = make(map[string]Profile_Stat)
}

// ------------------------------------------------------------------------------
// Scope Guard —— 作用域计时
// ------------------------------------------------------------------------------

// 用法：`defer profile_scope("frame")` —— 作用域结束时自动累计耗时。
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
	if d > s.max {
		s.max = d
	}
	profile_stats[g.name] = s
}

// ------------------------------------------------------------------------------
// 输出
// ------------------------------------------------------------------------------

profile_dump :: proc() {
	for name, s in profile_stats {
		avg_ms := f64(time.duration_milliseconds(s.total)) / max(1.0, f64(s.count)) // [1]
		max_ms := f64(time.duration_milliseconds(s.max))
		tot_ms := f64(time.duration_milliseconds(s.total))
		fmt.printf(
			"[PROFILE] %-20s count=%d avg=%.3fms max=%.3fms total=%.3fms\n",
			name, s.count, avg_ms, max_ms, tot_ms,
		)
	}
}
