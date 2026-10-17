package clay

@(private)
_static_string :: proc "contextless" (text: string) -> String {
	return {isStaticallyAllocated = true, length = i32(len(text)), chars = raw_data(text)}
}

// Keep the C comparison semantics (including the second operand on equality).
@(private)
_min :: proc "contextless" (a, b: $T) -> T {
	return a < b ? a : b
}

@(private)
_max :: proc "contextless" (a, b: $T) -> T {
	return a > b ? a : b
}

@(private)
_post_inc :: proc "contextless" (value: ^$T, delta: int) -> T {
	old := value^
	value^ += T(delta)
	return old
}

@(private)
_pre_inc :: proc "contextless" (value: ^$T, delta: int) -> T {
	value^ += T(delta)
	return value^
}

@(private)
_offset_ptr :: proc "contextless" (value: ^$T, offset: int) -> ^T {
	return cast(^T)(uintptr(value) + uintptr(offset * size_of(T)))
}

@(private)
_offset_multi :: proc "contextless" (value: [^]$T, offset: int) -> [^]T {
	return cast([^]T)(uintptr(value) + uintptr(offset * size_of(T)))
}

@(private)
_offset :: proc {_offset_ptr, _offset_multi}
