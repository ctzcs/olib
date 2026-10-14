# olib 面向数据开发约定

本文件是用 olib 编写 Odin 游戏时的面向数据设计（Data-Oriented Design，DOD）约定，适用于新项目和已有项目的日常开发。工程目录、包划分、UI、发布脚本和创建流程见 [新项目创建提示词](new-project.md)；本文件补充“数据怎么放、规则怎么写、缓存和配置怎么管、怎样证明行为没变”。

使用方式：让 AI 阅读本文件后再改代码，例如“阅读 olib 的 prompts/dod-guidelines.md，按其中约定为 MyGame 加一种敌人”。也可以复制“提示词开始”到“提示词结束”之间的内容放进游戏仓库的 `AGENTS.md`。下文的 `World`、`world_install_tuning`、`place_check`、`loc_get` 等是推荐的类型和 proc 名，不是 olib 已提供的 API；在游戏中实现时可以改名，但职责保持一致。

Odin 本身就是面向数据的语言：没有类、虚方法和 GC，有 `#soa`、enumerated array、`bit_set`、显式分配器。这些约定的重点是把这些能力用在一致的位置。

## 提示词开始

你在一个以面向数据设计为核心的 Odin 游戏项目中工作，库为 olib（`olib:foster` 运行时、`olib:kit/*` 扩展、`olib:core/*` 数据结构）。目标是：模拟可确定、可在无窗口时用 `odin test` 测试；热点循环不分配；内容由数据驱动；各包边界清楚。写代码前先判断它属于哪个包、读写哪些数据列；规则不确定时先读项目的 `src/README.md` 和相关源码。代码风格与注释块（文件头、分区导航、线框）遵循 olib 的 `docs/CODE_STYLE.md` 第 2～5 节。

### 1. 按数据形状选容器

先问“这份数据长什么样、谁会跨帧引用它”，再选容器。游戏里多数数据是普通数组；句柄池只用于会被其他数据跨帧引用的实体。

| 数据形状 | 例子 | 容器 |
| --- | --- | --- |
| 单个值 | 金币、天数、波次 | 模拟实例中的普通字段 |
| 网格 | 地形、占用、迷雾、流场 | 扁平数组，长度 `w*h`，下标 `y*w + x` |
| 按类型查的表 | 价格、射程、能否通行 | `[256]T` 或 enumerated array（见第 3 节） |
| 没人跨帧引用的批量数据 | 弹道、粒子、伤害事件、待生成队列 | `#soa[dynamic]T`，交换删除，不需要句柄 |
| 会被跨帧引用的实体 | 单位（被当作目标）、建筑（被选中） | 句柄 + SoA 行，见下文两种布局 |

- 网格用一维数组，大小在实例 init 时确定；不用 `[][]T`、`map[[2]i32]T` 或每格一个结构体指针。多个图层各自一个数组，按需读取。
- 批量数据用 `#soa[dynamic]T`：`append_soa` 追加，`unordered_remove_soa` 交换删除，按 `0..<len` 顺序遍历。边遍历边删除时倒序遍历，被搬来的行已处理过，不会跳过。交换删除后的顺序仍只由数据决定，可以重放；需要保持顺序时用写下标原地压缩。
- 实体的跨帧引用一律保存句柄：`olib:core/handle/array` 的 `Pool(T, H)`，`H` 是游戏自己的 `distinct ha.Handle`（每种实体一个，编译器阻止混用）。使用前检查有效；实体删除后旧句柄自动失效。不用裸指针或行号跨帧引用实体。实体属性按两种布局之一存放：
  - **槽位对齐（起步）**：`Pool` 只管理句柄与代数（`T` 为空结构），全部属性放在一个 `#soa[dynamic]` 中，下标为 `handle.idx`。删除不搬数据，遍历用 `ha.begin` / `ha.next` 跳过空槽；0 号与已删除槽位是空洞。
  - **紧凑（数量大、遍历是热点时）**：属性行紧凑存放在 `#soa[dynamic]` 中，`0..<len` 全部存活，遍历就是对列切片的普通循环。`Pool` 的值是行号，每行另存 `owner` 句柄；删除时把最后一行搬到被删位置，并按 `owner` 修正它的行号。行号在任何删除后都可能变化，只在当前操作内使用。
  - 两种布局对外提供同样的存储操作（生成、删除、按句柄取行），从槽位对齐换成紧凑时，规则代码只改遍历和取行的写法。
- 新增属性就是在行结构中加一个字段；`#soa` 让所有列随追加、删除、扩容一起变化，不会漏列。生成实体时整行赋值，复用槽位不会留下上一位占用者的值。
- `#soa` 是为了让各列同步变化、减少遗漏，不是 DOD 的要求。数量少，或者每次循环都读写大部分字段时，用普通的 `[dynamic]T` 也可以。只有部分行才有的数据，或者生命周期不同的数据，单独存放，不要塞进同一个 `#soa`。
- 不为每个实体创建带 update 回调的结构体或 proc 指针表。行为是对若干列做批量循环的 proc。
- 实例只存 1 字节类型编号和自身会变化的数据；价格、射程等类型数值去目录里查（见第 3 节）。
- `ha.get` 返回的指针和 `#soa` 的列指针在追加、扩容后失效，紧凑布局的行在删除后也会移动；遍历中不追加。热点循环不用 `map` 迭代、不做堆分配、不创建临时 `[dynamic]`。
- 热点循环先把要用的列取成局部切片（`hp := rows.hp[:len(rows)]`），再对切片循环，不在循环体内反复写 `rows[i].hp`；后者每轮可能经指针重新读取列地址，妨碍编译器优化。边界检查确认是热点时，再对该 proc 加 `#no_bounds_check`。

### 2. 包与依赖方向

固定采用 `def / data / logic / view / game` 五层，各层内按功能拆文件，需要独立边界或复用时再拆子包。Odin 一个目录一个包，编译器禁止循环导入；import 检查约束依赖方向，数据读写职责还要通过调用位置和测试验证。本表是层界规则的唯一来源，[新项目创建提示词](new-project.md) 引用此表，不另写一份。

| 包 | 回答的问题 | 可以 import |
| --- | --- | --- |
| `def` | 类型、固定映射、句柄、配置结构与默认值、命令和事件类型 | `core:*`、`olib:core/*`；不 import 其他游戏层、foster、kit |
| `data` | 模拟实例的数据：标量、网格、批量数组、实体的句柄与 SoA 行、模拟缓存结构、版本号与存储生命周期 | `def`、`core:*`、`olib:core/*`；不 import logic、view、game、装载器、foster、kit |
| `logic` 及其子包 | 状态转换、玩法规则、计算、查询、配置语义校验、模拟缓存重建与更新 | `data`、`def`、`core:*`、`olib:core/*`；不 import view、game、装载器、foster、kit、vendor |
| `view` | 状态如何显示和播放；表现状态与 GPU 缓存 | `data`、`def`、`core:*`、`olib:core/*`、`olib:foster`、`olib:kit/*`；不 import logic（拆出的 `logic/query` 除外，见下）、game、装载器，不另存权威模拟状态 |
| `game`（package main） | 输入转换、命令传递、实例创建与释放、系统组装与执行顺序 | 全部；不实现伤害、收入等玩法公式 |
| `ids`（可选） | 内容 ID 常量（如 `CATAPULT :: "catapult"`），只给测试、工具、装载器和 `game` 的诊断命令 | `core:*`；`def`、`data`、`logic`、`view` 的非测试文件不得 import 它 |

- `data` 只维护存储一致性（分配、删除、扩容、版本号），不决定“是否合法”“收益多少”。
- 规则写在 `logic`，签名显式接收状态和时间，例如 `step(world: ^data.World, dt: f32)`；`odin test` 中可以直接调用。
- `logic` 可以根据规则修改传入的数据；涉及列、句柄或版本一致性时调用 `data` 的存储操作，不为每个字段机械地增加 setter。
- `view` 直接读取 `data` 绘制（位置、血量、类型、已重建的规则数组），不修改它；操作形成 `def` 中的命令，由 `game` 交给 `logic`。
- 依赖当前输入、又需要规则判断的预览（光标处能否放置、路径预览、升级后的数值）由 `game` 在 `RenderProc` 中调用 `logic` 的只读查询，填入 `view` 定义的输入结构（如 `view.Place_Preview`）后传给 `view`。执行命令的 logic proc 复用同一个检查（`place_building` 先调用 `place_check`），预览和结果不会分歧；`view` 只按结果显示、翻译拒绝原因，不自行判断合法性。开销大的查询（如寻路）由 `game` 缓存上次结果，输入变化时才重算。
- 只读查询多到 `game` 难以维护时，可拆出 `logic/query` 子包并允许 `view` import；执行命令的 logic 也 import 它复用检查。Odin 没有只读指针，“查询不修改数据”靠约定与测试保证。查询只有少数几个时不拆。
- 同一功能在对应层中使用一致的名称，例如 `def/units.odin`、`data/units.odin`、`logic/units.odin`、`view/units.odin`。文件装载按需独立为 `content` 或工具入口，不强制额外创建 `authoring` 包；装载器依赖 `def`，模拟各层不反向依赖装载器。
- 不用转发 proc、包级别名或“桥接包”掩盖跨层引用。层界由 `tools/check_layers.ps1` 解析各包的 `import` 行验证（Odin 的 import 是文件顶部的字符串字面量，按行解析可靠）。检查只能看到 import，看不到引用了哪个符号，所以要禁止的符号必须放在单独的包里（如 `ids`）。`*_test.odin` 文件按测试规则单独检查，允许 import `ids`。

### 3. 数据驱动的内容目录

- 建筑、单位、敌人、地形等定义为“目录”：有序、以字符串 ID 作 JSON 键，第一项为默认项，运行时以其下标作为 1 字节类型编号（`u8`）。关卡只覆盖个别条目的个别字段。
- 条目行为由**能力字段**组合（攻击方式、挡路、照明、产出、可升级……），能力用 `enum` 和 `bit_set` 表达。代码按能力查询，**不按 ID 分支**；ID 常量放在单独的 `ids` 包，只给测试、工具、装载器和诊断命令用，层间检查禁止 `def`、`data`、`logic`、`view` 的非测试文件 import 它。不要把 ID 常量放进 `def`：`logic` 本来就能 import `def`，import 检查拦不住。
- 热点循环使用从目录预展开的规则数组（固定长度 `[256]T` 或 enumerated array），如 `rules.attacks[type]`、`rules.walkable[kind]`。规则数组存放在模拟实例中，安装配置时由 logic 立即重建（见第 4 节），热点循环和 `view` 直接读取。
- 配置类型、默认值与格式约束放在 `def`，依赖模拟含义的校验放在 `logic`，JSON 解码与版本迁移放在装载入口；`def` 不依赖文件装载器。编辑器元数据用 Odin **字段标签**描述，例如 ``sight: int `name:"视野" range:"0,32"` ``，经 `core:reflect` 的 `struct_tag_lookup` 读取。编辑器表单、JSON Schema 和格式校验从这些标签生成，不手写第二份；Schema 由工具生成，检查比对是否过期。JSON 键名用 `json:"..."` 标签，与 `core/encoding` 的读写一致。
- 优先级固定为：代码默认值 → 全局 JSON → 关卡稀疏覆盖。载入时完整校验，失败则保留上一份有效配置并返回可定位的错误（文件、字段）；旧字段在载入时迁移，旧文件继续可读。

### 4. 模拟实例与权威数据所有权

- 每个模拟实例只有一份权威数据，推荐用 `data.World` 组装，由 `game` 创建、持有和释放，并显式传给 `logic` 与 `view`。允许同时存在多个世界；不要求 `data` 包中的全局单例。世界模式、地图尺寸、生效配置等跟随对应实例，不散落为独立的可变全局量。
- `data` 负责数据结构和存储生命周期，`logic` 决定规则并修改传入的数据。只读配置可以直接访问 `world.tuning.economy.cost`，不用散布转发 proc；需要维护存储一致性或变化记录的修改才收口到相应入口。
- 快照与回滚：值类型直接复制；含堆数据时提供 `world_capture` / `world_restore`，不能把浅复制当独立快照，写明复制数据的所有者和释放责任。
- 由配置派生的数据（规则数组、名称表、布局）在来源变化时**立即**重建，不惰性求值：安装配置的 logic 入口（如 `world_install_tuning`）在配置校验通过后替换配置、重建全部派生数据并递增 `tuning_version`。任何读取者（包括直接读 `data` 的 `view`）看到的都与当前配置一致，也不需要逐个手动失效；新增派生数据时只在这一个入口加一行重建。
- 其他需要判断过期的缓存记录来源的版本号，与 `tuning_version` 等比较；不用来源指针相等判断（旧快照释放后地址可能被复用）。不在 `data` 中保存指向 logic 的 proc 指针。模拟缓存跟随模拟实例，显示缓存跟随表现实例，不使用共享的可变全局缓存。
- 玩家设置（例如界面语言）由明确的应用或表现实例持有，不影响模拟结果；与文本有关的缓存也把语言版本作为来源。

### 5. 变化事件与增量缓存

- 会被缓存观察的数据经 `data` 中的统一入口修改（例如 `data.building_set_position`）：`logic` 按规则决定新值后调用它，入口只在值真正变化时记录变化并递增版本号，不判断合法性。其余字段仍由 `logic` 直接写，不为每个字段增加 setter。
- 变化记录用脏标记位图（槽位对齐布局用 `bit_array` 或按槽位对齐的 `[dynamic]bool`；紧凑布局把脏标记作为行字段，随交换删除一起移动）或 `olib:core/messaging` 的 `Broadcast_Channel`（延迟一帧可见）。不注册任意回调：Odin 没有闭包，回调表会把状态藏进 `rawptr`，难以追踪。
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
- 一帧内的临时数据用 `context.temp_allocator`，foster 在每帧末尾（`RenderProc` 与 `GraphicsDeviceEndFrame` 之后）自动清空；不要跨帧持有，`StartupProc` 的临时分配也在第一帧结束时失效。返回临时分配结果的 proc 在注释中写明“本帧有效”。工作线程仍自行清理各自的临时分配器。
- 测试与开发构建用 `mem.Tracking_Allocator` 检查泄漏；重开一局后内存不应增长。
- `data` 文件的文件头写明：布局（槽位对齐、紧凑、网格下标）、不变式（如“`0..<len` 全部存活”）、所有权，以及不负责什么。
- 批量规则 proc 在声明上方写明读哪些列、写哪些列，以及对执行顺序的要求；并行化和调整调用顺序时以此为依据。

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

1. 判断改动属于数据（新字段、新目录字段）、规则（logic）、接线（game）还是显示（view）。新数据先按第 1 节的形状选容器，不默认放进句柄池。
2. 新行为优先做成目录能力字段 + 按能力查询，而不是新结构体类型或 ID 分支。
3. 新的权威状态放入 `data` 的对应模拟实例；表现状态放入 `view`。派生量注明来源、失效条件和所有者，不另建共享的可变全局量。
4. 新缓存写明来源、失效条件和所有者。
5. 热点路径不引入逐实体分配、proc 指针分发、反射或 `map` 迭代。
6. 改完运行 `check.ps1` 和相关冒烟；修改默认数值时，同时更新代码默认值、JSON 和生成的 Schema。

## 提示词结束

## 示例

以下示例只说明写法，名称按项目替换；代码已在 olib 当前版本下以 `-vet -strict-style` 编译验证；槽位对齐与紧凑两种实体布局分别编译，`main` 示例与两种布局的生成、删除、句柄失效均已实际运行并检查无泄漏。

**网格：扁平数组**

```odin
// 文件：src/data/grid.odin
package data

// 占用网格：一维数组，下标 y*w + x；0 为空，否则为建筑类型编号 + 1。
// 所有权：grid_init 分配，grid_destroy 释放。
Grid :: struct {
	size:     [2]i32,
	occupied: []u8,
}

grid_init :: proc(grid: ^Grid, size: [2]i32, allocator := context.allocator) {
	grid.size = size
	grid.occupied = make([]u8, int(size.x * size.y), allocator)
}

grid_destroy :: proc(grid: ^Grid) {
	delete(grid.occupied)
	grid^ = {}
}

grid_contains :: proc(grid: Grid, cell: [2]i32) -> bool {
	return cell.x >= 0 && cell.y >= 0 && cell.x < grid.size.x && cell.y < grid.size.y
}

// 调用方先用 grid_contains 检查越界。
grid_index :: proc(grid: Grid, cell: [2]i32) -> int {
	return int(cell.y * grid.size.x + cell.x)
}
```

**没人跨帧引用的批量数据：`#soa` + 交换删除**

```odin
// 文件：src/data/projectiles.odin
package data

// 弹道不被其他数据跨帧引用，不需要句柄；0..<len 全部存活。
Projectile :: struct {
	pos:    [2]f32,
	vel:    [2]f32,
	life:   f32,
	damage: f32,
}

Projectiles :: #soa[dynamic]Projectile
```

```odin
// 文件：src/logic/projectiles.odin
package logic

import "game:data"

// 先对整列做批量计算，再倒序删除到期弹道；被搬来的末行已处理过，不会跳过。
projectiles_step :: proc(list: ^data.Projectiles, dt: f32) {
	n := len(list)
	pos := list.pos[:n]
	vel := list.vel[:n]
	life := list.life[:n]
	for i in 0 ..< n {
		pos[i] += vel[i] * dt
		life[i] -= dt
	}
	for i := n - 1; i >= 0; i -= 1 {
		if life[i] <= 0 {
			unordered_remove_soa(list, i)
		}
	}
}
```

**实体（槽位对齐，起步布局）**

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

// 一个单位的全部属性；#soa 按字段拆成列。
Unit :: struct {
	kind:   u8,
	pos:    [2]f32,
	hp:     f32,
	target: def.Unit_Handle, // 无目标时为零值句柄（永远无效）
}

// Pool 只管理句柄与代数，不存属性。
Unit_Slot :: struct {}

// 槽位对齐：rows 的下标即 Unit_Handle.idx；0 号与已删除槽位是空洞。
// 所有权：units_destroy 释放 pool 与 rows。
Units :: struct {
	pool: ha.Pool(Unit_Slot, def.Unit_Handle),
	rows: #soa[dynamic]Unit,
}

// 整行赋值，复用槽位不会留下上一位占用者的值。
unit_spawn :: proc(units: ^Units, kind: u8, pos: [2]f32, max_hp: f32) -> def.Unit_Handle {
	h := ha.add(&units.pool, Unit_Slot{})
	slot := int(h.idx)
	if slot >= len(units.rows) {
		resize_soa(&units.rows, slot + 1)
	}
	units.rows[slot] = Unit{kind = kind, pos = pos, hp = max_hp}
	return h
}

// 返回句柄对应的行；句柄无效时 ok 为 false。
unit_row :: proc(units: ^Units, h: def.Unit_Handle) -> (row: int, ok: bool) {
	if !ha.valid(units.pool, h) {
		return -1, false
	}
	return int(h.idx), true
}

// 删除不搬数据，旧句柄失效。
unit_remove :: proc(units: ^Units, h: def.Unit_Handle) {
	ha.remove(&units.pool, h)
}

units_destroy :: proc(units: ^Units) {
	ha.delete(&units.pool)
	delete_soa(units.rows)
	units^ = {}
}
```

```odin
// 文件：src/logic/units.odin
package logic

import ha "olib:core/handle/array"

import "game:data"

// 批量规则：遍历存活槽位，只读写列。
units_regen :: proc(units: ^data.Units, regen_per_second: f32, dt: f32) {
	hp := units.rows.hp[:len(units.rows)]
	it := ha.begin(&units.pool)
	for _, h in ha.next(&it) {
		hp[h.idx] += regen_per_second * dt
	}
}
```

**实体（紧凑布局，数量大、遍历是热点时替换上面的版本）**

```odin
// 文件：src/data/units.odin（紧凑版，替换槽位对齐版）
package data

// 单位存储（紧凑布局）：所有单位行连续存放，句柄经 index 映射到行号。
// 不变式：rows 的 0..<len 全部存活；对每一行 i，index 中 rows[i].owner 的值等于 i。
// 所有权：由 World 持有，units_destroy 释放 index 与 rows。
// 不负责：生命值变化、索敌等规则（见 logic/units.odin）。
//
// 分区：
//   类型 —— Unit / Units
//   生命周期 —— unit_spawn / unit_remove / units_destroy
//   查询 —— unit_row

import ha "olib:core/handle/array"

import "game:def"

// ------------------------------------------------------------------------------
// 单位 / 类型 — 行结构与句柄映射
// ------------------------------------------------------------------------------

// 一个单位的全部属性；#soa 按字段拆成列。
Unit :: struct {
	owner:  def.Unit_Handle, // 本行属于哪个句柄，交换删除时用来修正映射
	kind:   u8,
	pos:    [2]f32,
	hp:     f32,
	target: def.Unit_Handle, // 无目标时为零值句柄（永远无效）
}

// index 只做“句柄 → 行号”的映射；行号在任何删除后都可能变化，不跨帧保存。
Units :: struct {
	index: ha.Pool(u32, def.Unit_Handle),
	rows:  #soa[dynamic]Unit,
}

// ------------------------------------------------------------------------------
// 单位 / 生命周期 — 生成、交换删除、释放
// ------------------------------------------------------------------------------

unit_spawn :: proc(units: ^Units, kind: u8, pos: [2]f32, max_hp: f32) -> def.Unit_Handle {
	h := ha.add(&units.index, u32(len(units.rows)))
	append_soa(&units.rows, Unit{owner = h, kind = kind, pos = pos, hp = max_hp})
	return h
}

// 交换删除：末行搬到被删位置，并修正被搬行的映射；旧句柄失效。
unit_remove :: proc(units: ^Units, h: def.Unit_Handle) {
	row, ok := unit_row(units, h)
	if !ok {
		return
	}
	last := len(units.rows) - 1
	if row != last {
		ha.get(units.index, units.rows[last].owner)^ = u32(row)
	}
	unordered_remove_soa(&units.rows, row)
	ha.remove(&units.index, h)
}

units_destroy :: proc(units: ^Units) {
	ha.delete(&units.index)
	delete_soa(units.rows)
	units^ = {}
}

// ------------------------------------------------------------------------------
// 单位 / 查询 — 句柄到行号
// ------------------------------------------------------------------------------

// 返回句柄对应的行号；句柄无效时 ok 为 false。行号只在当前操作内有效。
unit_row :: proc(units: ^Units, h: def.Unit_Handle) -> (row: int, ok: bool) {
	r := ha.get(units.index, h)
	if r == nil {
		return -1, false
	}
	return int(r^), true
}
```

```odin
// 文件：src/logic/units.odin（紧凑版）
package logic

import "game:data"

// 批量规则：对紧凑列做普通循环。
// 读：hp；写：hp。各行独立，顺序无关，可以分段并行。
units_regen :: proc(units: ^data.Units, regen_per_second: f32, dt: f32) {
	for &hp in units.rows.hp[:len(units.rows)] {
		hp += regen_per_second * dt
	}
}

// 跨实体引用：经句柄取目标所在行；目标已删除时清掉引用。
// 读：target、hp；写：target、hp（目标行）。按行顺序结算，多个攻击者的伤害叠加到同一目标，不能直接并行。
units_attack :: proc(units: ^data.Units, dps: f32, dt: f32) {
	n := len(units.rows)
	target := units.rows.target[:n]
	hp := units.rows.hp[:n]
	for i in 0 ..< n {
		row, ok := data.unit_row(units, target[i])
		if !ok {
			target[i] = {}
			continue
		}
		hp[row] -= dps * dt
	}
}

// 倒序删除阵亡单位：被搬来的末行已检查过，不会跳过。
// 读：hp、owner；结构性修改 rows 与 index：只在主线程调用，不在其他遍历 rows 的循环中途调用。
units_remove_dead :: proc(units: ^data.Units) {
	for i := len(units.rows) - 1; i >= 0; i -= 1 {
		if units.rows[i].hp <= 0 {
			data.unit_remove(units, units.rows[i].owner)
		}
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
	cost:   int         `name:"价格" range:"0,9999"`,
}

Building_Catalog :: struct {
	entries: []Building_Def,
}

// 放置被拒绝的原因；logic 返回，view 翻译成文字。
Place_Error :: enum u8 {
	None,
	Out_Of_Bounds,
	Occupied,
	Not_Enough_Gold,
}
```

```odin
// 文件：src/data/buildings.odin
package data

// 从目录展开的能力数组，下标为 1 字节类型编号。
Building_Rules :: struct {
	attacks: [256]bool,
	sight:   [256]i32,
	cost:    [256]i32,
}
```

**模拟实例与安装配置时立即重建的派生数据**

```odin
// 文件：src/data/world.odin
package data

import "game:def"

// 当前生效的配置；目录由配置的所有者分配和释放，World 只引用。
Tuning :: struct {
	buildings: ^def.Building_Catalog,
}

// 一个模拟实例的全部权威数据；按形状分别存放。
// 所有权：world_init 分配，world_destroy 释放（不含 tuning 引用的配置）。
World :: struct {
	tuning:         Tuning,
	tuning_version: u64,            // 每次安装配置递增；其他缓存以此判断过期
	building_rules: Building_Rules, // 由 tuning.buildings 派生，安装配置时重建
	gold:           i32,            // 单个值
	grid:           Grid,           // 网格
	projectiles:    Projectiles,    // 没人跨帧引用的批量数据
	units:          Units,          // 会被跨帧引用的实体
}

world_init :: proc(world: ^World, map_size: [2]i32) {
	grid_init(&world.grid, map_size)
}

world_destroy :: proc(world: ^World) {
	grid_destroy(&world.grid)
	delete_soa(world.projectiles)
	units_destroy(&world.units)
	world^ = {}
}
```

```odin
// 文件：src/logic/tuning.odin
package logic

import "game:data"
import "game:def"

building_rules_build :: proc(catalog: ^def.Building_Catalog) -> data.Building_Rules {
	assert(len(catalog.entries) <= 256) // 装载校验也须拒绝超出 u8 容量的目录。
	rules: data.Building_Rules
	for entry, i in catalog.entries {
		rules.attacks[i] = entry.attack != .None
		rules.sight[i] = i32(entry.sight)
		rules.cost[i] = i32(entry.cost)
	}
	return rules
}

// 安装已完整校验的配置：替换配置并立即重建全部派生数据。
// 返回后 World 不再引用旧配置，旧配置可由其所有者释放。
// 新增派生数据时只在这里加一行重建。
world_install_tuning :: proc(world: ^data.World, validated: data.Tuning) {
	world.tuning = validated
	world.building_rules = building_rules_build(validated.buildings)
	world.tuning_version += 1
}
```

**依赖输入的预览：game 查询，view 显示**

```odin
// 文件：src/logic/place.odin
package logic

import "game:data"
import "game:def"

// 只读查询：预览和执行命令共用这一份规则。
place_check :: proc(world: ^data.World, kind: u8, cell: [2]i32) -> def.Place_Error {
	if !data.grid_contains(world.grid, cell) {
		return .Out_Of_Bounds
	}
	if world.grid.occupied[data.grid_index(world.grid, cell)] != 0 {
		return .Occupied
	}
	if world.gold < world.building_rules.cost[kind] {
		return .Not_Enough_Gold
	}
	return .None
}

place_building :: proc(world: ^data.World, kind: u8, cell: [2]i32) -> def.Place_Error {
	if err := place_check(world, kind, cell); err != .None {
		return err
	}
	world.gold -= world.building_rules.cost[kind]
	world.grid.occupied[data.grid_index(world.grid, cell)] = kind + 1
	// 生成建筑实体……
	return .None
}
```

```odin
// 文件：src/view/place.odin
package view

import "game:def"

// view 需要的输入由 view 定义，game 填写后传入。
Place_Preview :: struct {
	active: bool,
	kind:   u8,
	cell:   [2]i32,
	error:  def.Place_Error,
}

// 只按查询结果选择虚影颜色，不自行判断合法性。
place_preview_color :: proc(preview: Place_Preview) -> [4]u8 {
	return preview.error == .None ? {80, 200, 120, 160} : {220, 70, 70, 160}
}
```

```odin
// 文件：src/game/main.odin（独立示例，不含窗口）
package main

import "game:data"
import "game:def"
import "game:logic"
import "game:view"

// game 持有实例，data 包没有全局单例；其他世界可以使用相同的数据类型。
world: data.World

main :: proc() {
	catalog := def.Building_Catalog{entries = []def.Building_Def{
		{id = "tower", attack = .Single, sight = 8, cost = 50},
	}}
	data.world_init(&world, {16, 16})
	defer data.world_destroy(&world)
	world.gold = 30
	logic.world_install_tuning(&world, data.Tuning{buildings = &catalog})
	// 安装后派生数据已就绪，view 可以直接读。
	assert(world.building_rules.attacks[0] && world.building_rules.sight[0] == 8)

	// 实际游戏中这一段在 RenderProc：按光标查询，结果交给 view。
	cell := [2]i32{3, 4}
	preview := view.Place_Preview{active = true, kind = 0, cell = cell, error = logic.place_check(&world, 0, cell)}
	_ = view.place_preview_color(preview)
	assert(preview.error == .Not_Enough_Gold)

	// 执行命令走同一个检查，结果与预览一致。
	assert(logic.place_building(&world, 0, cell) == preview.error)
	world.gold = 100
	assert(logic.place_building(&world, 0, cell) == .None)
	assert(logic.place_check(&world, 0, cell) == .Occupied)

	// 批量数据：到期的弹道被交换删除。
	append_soa(&world.projectiles, data.Projectile{vel = {1, 0}, life = 0.5})
	append_soa(&world.projectiles, data.Projectile{vel = {0, 1}, life = 2})
	logic.projectiles_step(&world.projectiles, 1)
	assert(len(world.projectiles) == 1 && world.projectiles[0].life == 1)
}
```

示例目录借用局部数据，只在 `main` 内同步使用；长期配置须由明确的所有者保存和释放。
派生数据本身持有堆数据时（例如名称表），`world_install_tuning` 在重建前释放旧值，World 销毁时一并释放。

## 反面例子

| 不要这样 | 改为 |
| --- | --- |
| `Tower :: struct { update: proc(^Tower, f32), … }`，每座塔一个带回调的结构体 | 塔的属性放在 SoA 列里，`tower_step(world, dt)` 批量处理 |
| `if def.id == "catapult" { splash(…) }` | 目录字段 `attack = .Splash`，按能力分支 |
| 多个包里各写一个 `cost :: proc() -> int { return config.cost }` | 从显式传入的 `world.tuning.…` 读取 |
| 全局 `rules_cache: Maybe(Rules)`，来源和失效条件不明 | 放进对应模拟实例，安装配置时立即重建 |
| `data` 里存 `build: proc(...)`，首次读取时惰性重建 | `world_install_tuning` 中直接重建；`data` 不保存指向 logic 的 proc 指针 |
| `view` 里写 `gold >= cost && tile_free(…)` 决定能否放置 | `game` 调用 `logic.place_check`，结果经 `view.Place_Preview` 传入 |
| 在 `RenderProc` 或 UI 控件分支里扣金币、改实体 | UI 产生 `def` 中的操作请求，由 `game` 交给 logic 校验并修改 |
| 测试里写 `testing.expect(t, enemies == 8)` | 用配置公式计算期望值 |
| 工作线程直接 `ha.remove(&units.pool, h)` | 工作线程写结果区间，主线程按槽位顺序提交 |
| 弹道、粒子、伤害事件也放进句柄池 | 没人跨帧引用就用 `#soa[dynamic]` + 交换删除，不要句柄 |
| 用 `map[[2]i32]Tile` 或 `[][]Tile` 存地图 | 扁平数组，下标 `y*w + x` |
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
