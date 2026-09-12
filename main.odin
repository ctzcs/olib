package main
import ha "handle/array"

main :: proc() {

    Value_Handle :: distinct ha.Handle
    values: ha.Pool(int, Value_Handle)
    defer ha.delete(&values)

    old := ha.add(&values, 42)
    assert(ha.get(values, old)^ == 42)

    ha.clear(&values)
    fresh := ha.add(&values, 7)
    assert(!ha.valid(values, old))
    assert(ha.get(values, fresh)^ == 7)
}
