# olib 面向数据开发约定

本文件是用 olib 编写 Odin 游戏时的面向数据设计（Data-Oriented Design，DOD）约定，适用于新项目和已有项目的日常开发。工程目录、包划分、UI、发布脚本和创建流程见 [新项目创建提示词](new-project.md)；本文件补充“数据怎么放、规则怎么写、缓存和配置怎么管、怎样证明行为没变”。

使用方式：让 AI 阅读本文件后再改代码，例如“阅读 olib 的 prompts/dod-guidelines.md，按其中约定为 MyGame 加一种敌人”。也可以复制“提示词开始”到“提示词结束”之间的内容放进游戏仓库的 `AGENTS.md`。下文的 `World`、`Derived`、`loc_get` 等是推荐的类型和 proc 名，不是 olib 已提供的 API；在游戏中实现时可以改名，但职责保持一致。

Odin 本身就是面向数据的语言：没有类、虚方法和 GC，有 `#soa`、enumerated array、`bit_set`、显式分配器。这些约定的重点是把这些能力用在一致的位置。

## 提示词开始

你在一个以面向数据设计为核心的 Odin 游戏项目中工作，库为 olib（`olib:foster` 运行时、`olib:kit/*` 扩展、`olib:core/*` 数据结构）。目标是：模拟可确定、可在无窗口时用 `odin test` 测试；热点循环不分配；内容由数据驱动；各包边界清楚。写代码前先判断它属于哪个包、读写哪些数据列；规则不确定时先读项目的 `src/README.md` 和相关源码。

### 1. 实体：句柄池 + SoA 属性列

- 大量同类实体放在 `olib:core/handle/array` 的 `Pool(T, H)` 中，`H` 是游戏自己的 `distinct ha.Handle`（每种实体一个，编译器阻止混用）。`T` 只保存所有实体共有的少量字段（种类、位置等）。跨帧引用一律保存句柄（槽位 + 代数），使用前 `ha.valid` 或判断 `ha.get` 返回是否为 nil；实体删除后旧句柄自动失效，不用裸指针指向实体。
- 各类实体的专有属性按结构数组（SoA）存放，例如 `hp: [dynamic]f32`、`target: [dynamic]Unit_Handle`，下标为 `handle.idx`，与池的槽位对齐。新增字段即新增一列，并同步检查分配、初始化、扩容、删除、槽位复用和重开，不能把旧值留给复用该槽位的新实体。不需要句柄的纯批量数据可直接用 Odin 的 `#soa[dynamic]T`。
- 不为每个实体创建带 update 回调的结构体或 proc 指针表。行为是对若干列做批量循环的 proc。
- 实例只存 1 字节类型编号和自身会变化的数据；价格、射程等类型数值去目录里查（见第 3 节）。
- 遍历存活实体用 `ha.begin` / `ha.next`，它跳过空槽。`ha.get` 返回的指针和列切片在 `add` / `remove` / 扩容后可能失效，需要重新解析句柄；需要稳定地址时改用 `core/handle/growing` 或 `virtual`。热点循环不用 `map` 迭代、不做堆分配、不创建临时 `[dynamic]`。

### 2. 包与依赖方向

固定采用 `def / data / logic / view / game` 五层，各层内按功能拆文件，需要独立边界或复用时再拆子包。Odin 一个目录一个包，编译器禁止循环导入；import 检查约束依赖方向，数据读写职责还要通过调用位置和测试验证。

| 包 | 回答的问题 | 可以 import |
| --- | --- | --- |
| `def` | 类型、固定映射、句柄、配置结构与默认值、命令和事件类型 | `core:*`、`olib:core/*`；不 import 其他游戏层、foster、kit |
| `data` | 模拟实例的数据：句柄池、SoA 列、对局状态、模拟缓存结构、版本号与存储生命周期 | `def`、`core:*`、`olib:core/*`；不 import logic、view、game、装载器、foster、kit |
| `logic` 及其子包 | 状态转换、玩法规则、计算、查询、配置语义校验、模拟缓存重建与更新 | `data`、`def`、`core:*`、`olib:core/*`；不 import view、game、装载器、foster、kit、vendor |
| `view` | 状态如何显示和播放；表现状态与 GPU 缓存 | `data`、`def`、`core:*`、`olib:core/*`、`olib:foster`、`olib:kit/*`；不 import logic、game、装载器，不另存权威模拟状态 |
| `game`（package main） | 输入转换、命令传递、实例创建与释放、系统组装与执行顺序 | 全部；不实现伤害、收入等玩法公式 |

- `data` 只维护存储一致性（分配、删除、扩容、版本号），不决定“是否合法”“收益多少”。
- 规则写在 `logic`，签名显式接收状态和时间，例如 `step(world: ^data.World, dt: f32)`；`odin test` 中可以直接调用。
- `logic` 可以根据规则修改传入的数据；涉及列、句柄或版本一致性时调用 `data` 的存储操作，不为每个字段机械地增加 setter。
- `view` 只读取模拟数据，操作形成 `def` 中的命令，由 `game` 交给 `logic`。需要模拟查询结果时，由 `game` 调用 `logic` 后传给 `view`，不在表现层复制规则。
- 同一功能在对应层中使用一致的名称，例如 `def/units.odin`、`data/units.odin`、`logic/units.odin`、`view/units.odin`。文件装载按需独立为 `content` 或工具入口，不强制额外创建 `authoring` 包；装载器依赖 `def`，模拟各层不反向依赖装载器。
- 不用转发 proc、包级别名或“桥接包”掩盖跨层引用。层界由 `tools/check_layers.ps1` 解析各包的 `import` 行验证（Odin 的 import 是文件顶部的字符串字面量，按行解析可靠）。

### 3. 数据驱动的内容目录

- 建筑、单位、敌人、地形等定义为“目录”：有序、以字符串 ID 作 JSON 键，第一项为默认项，运行时以其下标作为 1 字节类型编号（`u8`）。关卡只覆盖个别条目的个别字段。
- 条目行为由**能力字段**组合（攻击方式、挡路、照明、产出、可升级……），能力用 `enum` 和 `bit_set` 表达。代码按能力查询，**不按 ID 分支**；ID 常量只给测试和工具用，并由层间检查禁止 `logic` / `view` 引用。
- 热点循环使用从目录预展开的规则数组（固定长度 `[256]T` 或 enumerated array），如 `rules.attacks[type]`、`rules.walkable[kind]`。规则按目录快照缓存，目录被替换后自动重建（见第 4 节的 `Derived`）。
- 配置类型、默认值与格式约束放在 `def`，依赖模拟含义的校验放在 `logic`，JSON 解码与版本迁移放在装载入口；`def` 不依赖文件装载器。编辑器元数据用 Odin **字段标签**描述，例如 ``sight: int `name:"视野" range:"0,32"` ``，经 `core:reflect` 的 `struct_tag_lookup` 读取。编辑器表单、JSON Schema 和格式校验从这些标签生成，不手写第二份；Schema 由工具生成，检查比对是否过期。JSON 键名用 `json:"..."` 标签，与 `core/encoding` 的读写一致。
- 优先级固定为：代码默认值 → 全局 JSON → 关卡稀疏覆盖。载入时完整校验，失败则保留上一份有效配置并返回可定位的错误（文件、字段）；旧字段在载入时迁移，旧文件继续可读。

### 4. 模拟实例与权威数据所有权

- 每个模拟实例只有一份权威数据，推荐用 `data.World` 组装，由 `game` 创建、持有和释放，并显式传给 `logic` 与 `view`。允许同时存在多个世界；不要求 `data` 包中的全局单例。世界模式、地图尺寸、生效配置等跟随对应实例，不散落为独立的可变全局量。
- `data` 负责数据结构和存储生命周期，`logic` 决定规则并修改传入的数据。只读配置可以直接访问 `world.tuning.economy.cost`，不用散布转发 proc；需要维护存储一致性或变化记录的修改才收口到相应入口。
- 快照与回滚：值类型直接复制；含堆数据时提供 `world_capture` / `world_restore`，不能把浅复制当独立快照，写明复制数据的所有者和释放责任。
- 派生缓存显式记录来源与失效条件，可用版本号或 `Derived(S, T)` 按来源快照指针判断变化。按指针判断时来源必须是不可变快照，修改时整体替换；先让缓存放弃旧来源引用，再释放旧快照，避免地址复用误判。模拟缓存跟随模拟实例，显示缓存跟随表现实例，不使用共享的可变全局缓存。
- 玩家设置（例如界面语言）由明确的应用或表现实例持有，不影响模拟结果；与文本有关的缓存也把语言版本作为来源。

### 5. 变化事件与增量缓存

- 会被缓存观察的数据经统一入口修改（例如 `building_set_position`），只在值真正变化时记录变化并递增版本号。
- 变化记录用脏槽位位图（`bit_array` 或按槽位对齐的 `[dynamic]bool`）或 `olib:core/messaging` 的 `Broadcast_Channel`（延迟一帧可见）。不注册任意回调：Odin 没有闭包，回调表会把状态藏进 `rawptr`，难以追踪。
- 查询索引（空间桶、索敌树、工作分配索引）的结构、缓冲与生命周期放在 `data`，按模拟实例持有；重建、更新与查询算法放在 `logic`，在下次查询前批量处理脏槽位。缓存是可重建数据，不另存权威结果，存档不必保存它。记录变化的代码只能记录，不能重入修改模拟。
- `view` 的缓存（实例缓冲、地形块、反馈特效）只读取、不驱动；切换模拟、重开或退出时释放 GPU 资源（foster 的 `TextureDispose`、`MeshDispose` 等）。
- 每个缓存在注释或文档中写明：输入、失效条件、重建时机、所有者与释放责任。缓存只加速查询，规则仍由对应 logic 决定；可以提供关闭缓存的对照模式，用测试证明结果一致。

### 6. 确定性与并行

- 模拟以固定步长推进：foster `DefaultAppConfig` 默认固定 60 Hz 调用 `UpdateProc`，`app.Time.Delta` 即步长。暂停和倍速由 `game` 决定一帧执行几次 logic；logic 不读 foster 时钟、输入或 App。
- 需要可重放时，随机数用显式种子的生成器（`core:math/rand` 的 `rand.create(seed)` 得到状态，经参数传给 logic），不用全局默认随机源。处理和提交都按槽位顺序进行，不依赖 `map` 的遍历顺序。
- 并行只用于只读阶段（如批量索敌）：用 `core:thread.Pool` + `core:sync.Wait_Group`，工作线程读取稳定数据，只写自己的结果区间；句柄池、导航、视野和 GPU 只由主线程修改，并按原槽位顺序提交结果。每个线程的 `context.temp_allocator` 各自独立，线程结束前自行 `free_all`。
- 表现动画不保存插值中间值，只记录事件发生时刻，绘制时用缓动曲线（`olib:core/tween` 的插值原语）算出姿态。

### 7. 内存与所有权

- 每个持有堆数据的结构配 `xxx_init` / `xxx_destroy`，并在注释写明所有权。列、池、目录在一局的 init 中分配、在重开或退出时整体释放；不要在热点循环里逐实体分配。
- 一帧内的临时数据用 `context.temp_allocator`，foster 在每帧末尾（`RenderProc` 与 `end_frame` 之后）自动清空；不要跨帧持有，`StartupProc` 的临时分配也在第一帧结束时失效。返回临时分配结果的 proc 在注释中写明“本帧有效”。工作线程仍自行清理各自的临时分配器。
- 测试与开发构建用 `mem.Tracking_Allocator` 检查泄漏；重开一局后内存不应增长。

### 8. 文本与显示

- 玩家可见文字一律经本地化表读取，例如 `loc_get("hud.restart")`、`loc_format("build.need_gold", cost)`，用占位符写整句，不拼接句子片段。内容名称按目录 ID 翻译（如 `building.catapult.name`），缺少翻译时回退为配置里的原名。
- 本地化文本中出现的全部字符要传给 `ui.ui_font_bake_sdf` 的 `codepoints`，否则不在默认 ASCII 集里的字形不会显示。
- logic 可以返回拒绝原因枚举，由 view 翻译成文字；文本不参与模拟判断。

### 9. 验证

- `logic` 及实际创建的子包配 `*_test.odin`（`#+test` + `@(test)`），直接调用 logic 并断言状态，`odin test src/logic -collection:olib=<olib> -collection:game=src` 无窗口运行；有子包时也逐包运行。画面与输入用游戏 exe 的 `shot` / `smoke` 参数：注入真实点击、渲染、写 PNG 后退出，再实际查看截图。
- 测试中的期望值从配置公式计算（例如 `wild.night_base_enemies + wild.night_growth_per_day`），不写死数字，以免调参导致误报。
- 结构重构和性能优化要证明行为不变：用固定场景、`-o:speed` 构建压测，对比关键结果（如开火数、击杀数、被毁建筑数）完全一致，再比较耗时。
- 调整层界或职责后运行层间依赖检查，并更新 `src/README.md` 中的职责表和“修改入口”表。

### 10. 改代码时的默认步骤

1. 判断改动属于数据（新列、新目录字段）、规则（logic）、接线（game）还是显示（view）。
2. 新行为优先做成目录能力字段 + 按能力查询，而不是新结构体类型或 ID 分支。
3. 新的权威状态放入 `data` 的对应模拟实例；表现状态放入 `view`。派生量注明来源、失效条件和所有者，不另建共享的可变全局量。
4. 新缓存写明来源、失效条件和所有者。
5. 热点路径不引入逐实体分配、proc 指针分发、反射或 `map` 迭代。
6. 改完运行 `check.ps1` 和相关冒烟；修改默认数值时，同时更新代码默认值、JSON 和生成的 Schema。

## 提示词结束

## 示例

以下示例只说明写法，名称按项目替换；代码已在 olib 当前版本下以 `-vet` 编译验证，缓存示例已实际运行。

**句柄池 + SoA 属性列，与槽位对齐**

```odin
// 文件：src/def/units.odin
package def

import ha "olib:core/handle/array"

Unit_Handle :: distinct ha.Handle
```

```odin
// 文件：src/data/units.odin
package data

import ha "olib:core/handle/array"

import "game:def"

// 所有单位共有的少量字段；专有属性放在 Unit_Columns 的列里。
Unit :: struct {
	kind: u8,
	pos:  [2]f32,
}

// 单位专有属性列，下标即 Unit_Handle.idx（与句柄池槽位一致）。
Unit_Columns :: struct {
	hp:     [dynamic]f32,
	target: [dynamic]def.Unit_Handle, // 无目标时为零值句柄（永远无效）
}

Units :: struct {
	pool: ha.Pool(Unit, def.Unit_Handle),
	cols: Unit_Columns,
}

// 分配或复用槽位时调用：扩容并清掉上一位占用者留下的值。
unit_spawn :: proc(units: ^Units, kind: u8, pos: [2]f32, max_hp: f32) -> def.Unit_Handle {
	h := ha.add(&units.pool, Unit{kind = kind, pos = pos})
	slot := int(h.idx)
	if slot >= len(units.cols.hp) {
		resize(&units.cols.hp, slot + 1)
		resize(&units.cols.target, slot + 1)
	}
	units.cols.hp[slot] = max_hp
	units.cols.target[slot] = {}
	return h
}

units_destroy :: proc(units: ^Units) {
	ha.delete(&units.pool)
	delete(units.cols.hp)
	delete(units.cols.target)
}
```

```odin
// 文件：src/logic/combat/combat.odin
package combat

import ha "olib:core/handle/array"

import "game:data"

// 批量规则：遍历存活槽位，只读写列。
units_regen :: proc(units: ^data.Units, regen_per_second: f32, dt: f32) {
	it := ha.begin(&units.pool)
	for _, h in ha.next(&it) {
		units.cols.hp[h.idx] += regen_per_second * dt
	}
}
```

**能力字段 + 字段标签 + 预展开的规则数组**

```odin
// 文件：src/def/buildings.odin
package def

Attack_Kind :: enum u8 {
	None,
	Single,
	Splash,
}

// 目录条目：能力字段 + 编辑器元数据（字段标签，经 core:reflect 读取）。
Building_Def :: struct {
	id:     string,
	attack: Attack_Kind `name:"攻击方式"`,
	sight:  int         `name:"视野" range:"0,32"`,
}

Building_Catalog :: struct {
	entries: []Building_Def,
}
```

```odin
// 文件：src/data/buildings.odin
package data

// 从目录展开的能力数组，下标为 1 字节类型编号。
Building_Rules :: struct {
	attacks: [256]bool,
	sight:   [256]i32,
}
```

```odin
// 文件：src/logic/tuning/rules.odin
package tuning

import "game:data"
import "game:def"

building_rules_build :: proc(catalog: ^def.Building_Catalog) -> data.Building_Rules {
	assert(len(catalog.entries) <= 256) // 装载校验也须拒绝超出 u8 容量的目录。
	rules: data.Building_Rules
	for entry, i in catalog.entries {
		rules.attacks[i] = entry.attack != .None
		rules.sight[i] = i32(entry.sight)
	}
	return rules
}
```

**模拟实例与按来源重建的派生缓存**

```odin
// 文件：src/data/world.odin
package data

import "game:def"

// 按来源快照指针缓存的派生值；来源被替换时重建。
// 来源必须是不可变快照：修改时整体替换指针，不原地改。
Derived :: struct($S, $T: typeid) {
	from:  ^S,
	value: T,
	build: proc(source: ^S) -> T,
}

Tuning :: struct {
	buildings: ^def.Building_Catalog,
}

World :: struct {
	tuning:         Tuning,
	building_rules: Derived(def.Building_Catalog, Building_Rules),
}
```

```odin
// 文件：src/logic/tuning/cache.odin
package tuning

import "game:data"

// 本例的派生值是固定数组；不持有堆数据，无须释放旧 value。
derived_get :: proc(d: ^data.Derived($S, $T), source: ^S) -> ^T {
	if source == nil {
		return nil
	}
	if d.from != source {
		d.value = d.build(source)
		d.from = source
	}
	return &d.value
}

// 建筑能力数组；数值重载后自动按新目录重建。
world_building_rules :: proc(world: ^data.World) -> ^data.Building_Rules {
	return derived_get(&world.building_rules, world.tuning.buildings)
}

// 候选配置完整校验通过后才替换；本缓存先放弃旧来源引用。
// 其他观察者也放弃引用后，旧快照才能由其所有者释放。
world_load_tuning :: proc(world: ^data.World, validated: data.Tuning) {
	world.building_rules.from = nil
	world.building_rules.value = {}
	world.tuning = validated
}
```

```odin
// 文件：src/game/main.odin（独立的缓存示例，不含窗口）
package main

import "game:data"
import "game:def"
import "game:logic/tuning"

// game 持有实例，data 包没有全局单例；其他世界可以使用相同的数据类型。
world: data.World

main :: proc() {
	catalog := def.Building_Catalog{entries = []def.Building_Def{
		{id = "tower", attack = .Single, sight = 8},
	}}
	world.building_rules.build = tuning.building_rules_build
	tuning.world_load_tuning(&world, data.Tuning{buildings = &catalog})
	rules := tuning.world_building_rules(&world)
	assert(rules.attacks[0] && rules.sight[0] == 8)
}
```

示例目录借用局部数据，只在 `main` 内同步使用；长期配置须由明确的所有者保存和释放。
派生值本身持有堆数据时（例如名称表），给 `Derived` 再加一个 `destroy: proc(value: ^T)` 字段，在重建、失效和实例销毁时释放旧值。

## 反面例子

| 不要这样 | 改为 |
| --- | --- |
| `Tower :: struct { update: proc(^Tower, f32), … }`，每座塔一个带回调的结构体 | 塔的属性放在 SoA 列里，`tower_step(world, dt)` 批量处理 |
| `if def.id == "catapult" { splash(…) }` | 目录字段 `attack = .Splash`，按能力分支 |
| 多个包里各写一个 `cost :: proc() -> int { return config.cost }` | 从显式传入的 `world.tuning.…` 读取 |
| 全局 `rules_cache: Maybe(Rules)`，来源和失效条件不明 | 跟随对应实例，按来源版本或不可变快照指针重建 |
| 在 `RenderProc` 或 UI 控件分支里扣金币、改实体 | UI 产生 `def` 中的操作请求，由 `game` 交给 logic 校验并修改 |
| 测试里写 `testing.expect(t, enemies == 8)` | 用配置公式计算期望值 |
| 工作线程直接 `ha.remove(&units.pool, h)` | 工作线程写结果区间，主线程按槽位顺序提交 |
| 遍历 `map[Unit_Handle]Target` 决定结算顺序 | 按槽位顺序遍历列；`map` 只做查找 |
| 每帧 `make([dynamic]T)` 收集候选再 `delete` | 复用持久缓冲（`clear` 后重填）或用 `context.temp_allocator`；foster 每帧末尾清空，不要跨帧持有 |

## 参考入口

| 主题 | 入口 |
| --- | --- |
| 句柄与槽位容器 | [core/handle README](../core/handle/README.md)、[array 实现](../core/handle/array/) |
| 命令队列与延迟一帧广播 | [core/messaging](../core/messaging/messaging.odin) |
| 补间与插值原语 | [core/tween](../core/tween/) |
| 配置读写 | [core/encoding](../core/encoding/) |
| 编码规范与 Odin 注意事项 | [CODE_STYLE.md](../docs/CODE_STYLE.md) |
| 新项目目录、UI、发布与验证 | [新项目创建提示词](new-project.md) |
