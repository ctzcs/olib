package structure
Simple_Array :: struct($T: typeid, $N: int){
    data: [N]T,
    alive: int,
}
//a := Simple_Array(int,16){}

add_element::proc(sa: ^Simple_Array($T, $N), elem: T) -> ^T{
    if sa.alive >= $N {
        return nil
    }
    sa.data[sa.alive] = elem
    sa.alive += 1
    return &sa.data[sa.alive - 1]
}
