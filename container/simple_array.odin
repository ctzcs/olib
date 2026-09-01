package container
Simple_Array::struct($T:typeid,$N: int){
    data: [N]T,
    alive: int,
    max_size: int,
}


new_simple_array::proc($T:typeid,max_size: int)->Simple_Array(T){
    return Simple_Array(T){
        data = [max_size]T,
        alive = 0,
        max_size = max_size,
    }
}

add_element::proc(sa: ^Simple_Array(T), elem: T) -> ^T{
    if sa.alive >= sa.max_size {
        return nil
    }
    sa.data[sa.alive] = elem
    sa.alive += 1
    return &sa.data[sa.alive - 1]
}
