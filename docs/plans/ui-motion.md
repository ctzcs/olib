# kit/ui 状态驱动动效

## 背景

kit/ui 已有 `ui_set_visual`（子树位移/缩放/旋转/透明度）和 `core/tween`，但常见 UI 动效写起来样板多：
调用方要保存地址稳定的 `UI_Visual`、Tween 管理器与句柄，打断时先 `manager_kill` 再接续，
退场时自己保持声明并隔离输入，参数散落在事件代码里。这与控件每帧声明的即时模式写法不一致。

本计划在 `ui_set_visual` 之上加一层按 ID 保存状态、每帧声明目标的动效原语，覆盖悬停/按下/选中、
一次性冲击和进出场。它只是便利层：自己计算 `UI_Visual`、Tween/Sequence 编排、非变换类数值动画
（颜色、打字机、进度、数字滚动）与自绘照旧可用，并能和原语在同一元素树里叠加。

## 已定决策

1. **参数** `UI_Motion :: struct { time: f32, bounce: f32 }`：`time` 约为到位所需秒数，`bounce`
   0 为临界阻尼不过冲，0..1 越大越弹（阻尼比 = 1 - bounce）。零值 `time` 表示立即到位，零值结构可用。
   游戏把参数写成具名常量集中放置，配合 core DLL 热重载调手感；库不提供预设表和资源格式。
2. **弹簧** 在 `core/tween/damp.odin` 新增 `spring(current, velocity, target, time, bounce, dt)`，
   解析解阻尼弹簧，任意 dt 稳定，泛型同 `smooth_damp`（f32 或 [N]f32）。`bounce = 0` 时结果与临界阻尼一致。
   依赖目前未提交的 `damp.odin`，执行前它须已提交。
3. **追随** `ui_motion(ctx, id, target: UI_Visual, motion: UI_Motion) -> UI_Visual`：
   按 `ui_begin` 的 dt 把该 ID 的当前值和速度推向 target，调用 `ui_set_visual` 注册并返回当前值。
   首次出现的 ID 直接取 target（入场交给 presence）。打断时保留速度，无需 kill。
4. **冲击** `ui_motion_kick(ctx, id, velocity: UI_Visual)`：给已存在的状态叠加速度（零值字段无冲击），
   下一次推进生效；ID 尚无状态时忽略。由弹簧自行回到 target。
5. **读取** `ui_motion_state(ctx, id) -> (value, velocity: UI_Visual, ok: bool)`，供定制动画在原语结果上加工。
6. **进出场** `ui_presence(ctx, id, open: bool, enter, exit: UI_Motion) -> (alive: bool, t: f32)`：
   `t` 为 0..1 进度（弹性时可过冲），映射成画面由调用方决定；`alive` 为 false 时调用方不再声明。
   正在退场（`!open && alive`）的 ID 标记为 inert：其子树在命中测试中不接受指针（在 `UI_Visual_Element`
   上按父子继承 inert，`ui_visual_hit` 拒绝），键盘导航跳过上一帧位于 inert 子树中的控件。
7. **生命周期** 动效状态存在 `UI_Context` 按 clay ID 的表里；`ui_end` 删除本帧未声明的 ID，
   调用方不持有指针、不负责释放。`ui_dispose` 释放表。
8. 原语不独占 ID：同一 ID 本帧后续的 `ui_set_visual` 仍按“最后一次注册生效”覆盖；嵌套元素的变换照常合成。
9. 文档写清四层：原语 → 自算 `UI_Visual` → Tween/Sequence → 非变换数值与自绘，并给出嵌套叠加示例。

## 执行步骤

1. `core/tween`：`spring` 与单元测试（收敛、bounce=0 不过冲、大 dt 稳定、[2]f32）。
   提交 `tween: 阻尼弹簧 spring`。
2. `kit/ui/ui_motion.odin`：决策 3–8，配 CPU 单元测试（追随收敛、打断保留速度、kick 回弹、
   未声明 ID 回收、presence 的 alive/t 时序、退场子树不命中、导航跳过）。提交 `ui: 状态驱动动效原语`。
3. olib_sample `ui_motion` 示例改用新原语（按压回弹用 kick、悬停用追随、REWARD 弹窗用 presence），
   保留一处嵌套的自定义程序化动画作对照，`shot` 截图。kit/ui README 动画一节改写为四层说明，
   core/tween 文档补 `spring`。提交 `samples: ui_motion 改用动效原语` 与 `docs: kit/ui 动效原语`。
4. 按 docs/plans/README.md 归档本计划。

## 验收

- `odin run tools/check` 全部通过（含 tween、kit/ui 单元测试与示例编译）。
- ui_motion 示例行为与改写前一致或更顺：连续快速悬停进出无跳变，退场中的弹窗点不到。
  截图放 olib_sample 的 library/screenshots；手感由用户运行示例验收。

## 禁止事项

- 不改 `ui_set_visual` / `UI_Visual` 现有语义，不改 foster。
- 不做关键帧编辑器、动画资源格式或预设表；不把 Tween 管理器塞进 `UI_Context`。
- 不提交与本计划无关的已有改动（hotreload、shader_lab 等）。

## 汇报内容

- 每步 commit、测试与 check 结果、截图路径、与计划不一致之处。
