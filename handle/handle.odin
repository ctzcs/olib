package handle

Handle :: struct {
	idx: u32,
	gen: u32,
}

Array_Handle :: distinct Handle
Fixed_Handle :: distinct Handle
Growing_Handle :: distinct Handle
Virtual_Handle :: distinct Handle

Array_None :: Array_Handle{}
Fixed_None :: Fixed_Handle{}
Growing_None :: Growing_Handle{}
Virtual_None :: Virtual_Handle{}