# Handle 容器

通过索引与代数（`idx`、`gen`）定位元素，识别已删除、已复用的槽位。
直接导入下面的子包；根目录不再提供另一套带前缀的 API。

## 选型

| 子包 | 适用场景 | 存储与限制 |
| --- | --- | --- |
| `array` | 默认选择；asset、tween 使用此包 | 动态槽位数组，扩容可能使元素指针失效；`T` 无需包含句柄 |
| `fixed` | 已知容量，需要避免容器分配堆内存 | 内嵌数组，`Pool(T, HT, N)` 可存 `N - 1` 个元素；容器移动会改变元素地址 |
| `growing` | 需要扩容并保持元素地址稳定 | 指针数组加 arena；JS 使用 Dynamic Arena，其他平台使用 Growing Virtual Arena |
| `virtual` | 需要连续存储和稳定元素地址 | 预留虚拟内存并原地扩容，依赖平台虚拟内存支持；实际容量受页对齐影响 |

三个专用包（`fixed`、`growing`、`virtual`）要求 `T` 包含 `handle: HT`，该字段由容器维护，不应由调用方修改。
四个包提供相同的公共操作：`add/get/get_value/valid/remove/clear/reset/delete/len/cap/begin/next`。

## 默认用法

从仓库根目录导入 `"handle/array"`；使用 Odin collection 时导入
`"olib:handle/array"`，并传入 `-collection:olib=<仓库路径>`。

```odin
import ha "olib:handle/array"

Value_Handle :: distinct ha.Handle

example :: proc() {
    values: ha.Pool(int, Value_Handle)
    defer ha.delete(&values)

    old := ha.add(&values, 42)
    if value := ha.get(values, old); value != nil {
        value^ += 1
    }

    ha.clear(&values)
    fresh := ha.add(&values, 7)
    assert(!ha.valid(values, old))
    assert(ha.valid(values, fresh))
}
```

用业务类型定义 `distinct` 句柄，避免混用资产、动画等不同类型的引用。
句柄只属于创建它的容器实例；相同句柄类型的两个容器之间也不能互用。
零句柄始终无效。槽位复用会递增 `u32` 代数；代数回绕后不保证历史句柄仍然无效。

## 公共生命周期

| 操作 | 内容和内存 | 句柄语义 |
| --- | --- | --- |
| `remove(&pool, h)` | 移除一个元素，槽位可复用 | 该元素旧句柄失效 |
| `clear(&pool)` | 清空活跃元素，保留槽位、代数和容量 | 后续复用槽位时，旧句柄仍失效，直到代数回绕 |
| `reset(&pool)` | 清空槽位历史；具体内存保留方式见下文 | 开始新生命周期，调用方必须丢弃全部旧句柄 |
| `delete(&pool)` | 释放容器内存并将容器清零 | 结束生命周期，调用方必须丢弃全部旧句柄 |

`clear` 扫描历史槽位，将活跃槽位加入已有空闲列表，不重复加入已空闲槽位。
`clear/remove` 不分配内存：动态容器在 `add` 时提前准备空闲列表容量，后续新增优先复用空闲槽位。
这会增加空闲列表的预留内存，但把可失败的分配集中在 `add`。

上述四个操作都可追加 `destroy: proc(value: ^T)` 回调，对需要移除的活跃元素逐项清理。
容器不会自动释放 `T` 内部持有的资源；未提供回调时由调用方处理。
回调不得增删、清空或销毁同一个 Pool。

`get` 返回临时指针，`get_value` 返回值副本和成功标记。
使用 `begin` / `next` 遍历时，不要结构性修改容器。
Array 的 `add` 可能搬移槽位；即使其他子包地址稳定，删除、复用槽位后也不能继续把旧指针视作原元素。

## 保留的差异

- `array/growing/virtual` 的 `add` 返回 `(handle, Allocator_Error)`，使用 `#optional_allocator_error`；失败返回零句柄，已有元素保持有效，容器容量可能已经增加。
- `fixed` 的 `add` 返回 `(handle, bool)`，使用 `#optional_ok`；容量满时返回零句柄与 `false`。
- 单返回值写法仍然可用；需要处理分配失败时，应显式接收错误。新增失败时容器不接管传入值的资源。
- Fixed 的 `get/get_value` 接收 `&pool`，避免返回内嵌数组副本的地址；其他包接收 `pool`。
- `make` 的配置参数保留：Growing 配置 arena 块大小，Virtual 配置预留容量，Array 支持零值初始化，Fixed 容量由类型参数确定。
- `cap`：Array 为当前槽位容量；Growing 为当前指针数组容量（新增元素仍可能分配 arena 内存）；Fixed 为硬上限；Virtual 为预留容量。
- `reset`：Array 保留数组容量；Fixed 清零内嵌存储；Growing 保留索引数组容量并回收 arena 的后续块；Virtual 保留预留存储。
- `delete`：四个包都清零容器，可重复删除；Fixed 无容器堆内存需要释放。重用容器时不能再使用上一生命周期的句柄。

```odin
h, err := ha.add(&values, 42)
if err != nil {
    // 由调用方处理失败；原有元素仍有效。
}
```

## 验证

在仓库根目录运行，每个子包单独测试：

```text
odin test handle/array
odin test handle/fixed
odin test handle/growing
odin test handle/virtual
odin test tween -collection:olib=.
odin run .
```
