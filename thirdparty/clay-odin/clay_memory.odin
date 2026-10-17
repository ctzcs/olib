// Pure Odin port of Clay v0.14 (b25a31c1a152915cd7dd6796e6592273e5a10aac).
// Copyright (c) 2024 Nic Barker. Altered source; see LICENSE.md and README.md.
package clay

@(private)
CLAY__ELEMENT_DEFINITION_LATCH: u8

// clay.h:107 — Clay__SuppressUnusedLatchDefinitionVariableWarning
@(private)
_SuppressUnusedLatchDefinitionVariableWarning :: proc "c" () {
	_ = CLAY__ELEMENT_DEFINITION_LATCH
}

@(private)
CLAY_LAYOUT_DEFAULT: LayoutConfig = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}}}}

@(private)
_Color_DEFAULT: Color = Color{cast(f32)(0), 0, 0, 0}

@(private)
_CornerRadius_DEFAULT: CornerRadius = CornerRadius{topLeft = cast(f32)(0)}

@(private)
_BorderWidth_DEFAULT: BorderWidth = BorderWidth{left = cast(u16)(0)}

@(private)
_currentContext: ^Context

@(private)
_defaultMaxElementCount: i32 = 8192

@(private)
_defaultMaxMeasureTextWordCacheCount: i32 = 16384

// clay.h:1022 — Clay__ErrorHandlerFunctionDefault
@(private)
_ErrorHandlerFunctionDefault :: proc "c" (errorText: ErrorData) {
	_ = errorText
}

@(private)
CLAY__SPACECHAR: String = String{length = 1, chars = raw_data(string(" "))}

@(private)
CLAY__STRING_DEFAULT: String = String{length = 0, chars = nil}

@(private)
CLAY__WARNING_DEFAULT: _Warning = _Warning{baseMessage = String{isStaticallyAllocated = false}}

@(private)
_Bool_DEFAULT: bool = false

// clay.h:1063 — Clay__boolArray_Allocate_Arena
@(private)
_boolArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _boolArray {
	return _boolArray{capacity = capacity, length = 0, internalArray = cast([^]bool)(cast(^bool)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(bool)), arena)))}
}

// clay.h:1063 — Clay__boolArray_Get
@(private)
_boolArray_Get :: proc "c" (array: ^_boolArray, index: i32) -> ^bool {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_Bool_DEFAULT)
}

// clay.h:1063 — Clay__boolArray_GetValue
@(private)
_boolArray_GetValue :: proc "c" (array: ^_boolArray, index: i32) -> bool {
	return (((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? cast(i32)(array.internalArray[index]) : cast(i32)(_Bool_DEFAULT)) != 0)
}

// clay.h:1063 — Clay__boolArray_Add
@(private)
_boolArray_Add :: proc "c" (array: ^_boolArray, item: bool) -> ^bool {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_Bool_DEFAULT
}

// clay.h:1063 — Clay__boolArraySlice_Get
@(private)
_boolArraySlice_Get :: proc "c" (slice: ^_boolArraySlice, index: i32) -> ^bool {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_Bool_DEFAULT)
}

// clay.h:1063 — Clay__boolArray_RemoveSwapback
@(private)
_boolArray_RemoveSwapback :: proc "c" (array: ^_boolArray, index: i32) -> bool {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: bool = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _Bool_DEFAULT
}

// clay.h:1063 — Clay__boolArray_Set
@(private)
_boolArray_Set :: proc "c" (array: ^_boolArray, index: i32, value: bool) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
int32_t_DEFAULT: i32 = 0

// clay.h:1064 — Clay__int32_tArray_Allocate_Arena
@(private)
_int32_tArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _int32_tArray {
	return _int32_tArray{capacity = capacity, length = 0, internalArray = cast([^]i32)(cast(^i32)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(i32)), arena)))}
}

// clay.h:1064 — Clay__int32_tArray_Get
@(private)
_int32_tArray_Get :: proc "c" (array: ^_int32_tArray, index: i32) -> ^i32 {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &int32_t_DEFAULT)
}

// clay.h:1064 — Clay__int32_tArray_GetValue
@(private)
_int32_tArray_GetValue :: proc "c" (array: ^_int32_tArray, index: i32) -> i32 {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : int32_t_DEFAULT)
}

// clay.h:1064 — Clay__int32_tArray_Add
@(private)
_int32_tArray_Add :: proc "c" (array: ^_int32_tArray, item: i32) -> ^i32 {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &int32_t_DEFAULT
}

// clay.h:1064 — Clay__int32_tArraySlice_Get
@(private)
_int32_tArraySlice_Get :: proc "c" (slice: ^_int32_tArraySlice, index: i32) -> ^i32 {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &int32_t_DEFAULT)
}

// clay.h:1064 — Clay__int32_tArray_RemoveSwapback
@(private)
_int32_tArray_RemoveSwapback :: proc "c" (array: ^_int32_tArray, index: i32) -> i32 {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: i32 = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return int32_t_DEFAULT
}

// clay.h:1064 — Clay__int32_tArray_Set
@(private)
_int32_tArray_Set :: proc "c" (array: ^_int32_tArray, index: i32, value: i32) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
char_DEFAULT: u8 = cast(u8)(0)

// clay.h:1065 — Clay__charArray_Allocate_Arena
@(private)
_charArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _charArray {
	return _charArray{capacity = capacity, length = 0, internalArray = cast([^]u8)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(u8)), arena))}
}

// clay.h:1065 — Clay__charArray_Get
@(private)
_charArray_Get :: proc "c" (array: ^_charArray, index: i32) -> [^]u8 {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &char_DEFAULT)
}

// clay.h:1065 — Clay__charArray_GetValue
@(private)
_charArray_GetValue :: proc "c" (array: ^_charArray, index: i32) -> u8 {
	return cast(u8)(((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? cast(i32)(array.internalArray[index]) : cast(i32)(char_DEFAULT)))
}

// clay.h:1065 — Clay__charArray_Add
@(private)
_charArray_Add :: proc "c" (array: ^_charArray, item: u8) -> [^]u8 {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &char_DEFAULT
}

// clay.h:1065 — Clay__charArraySlice_Get
@(private)
_charArraySlice_Get :: proc "c" (slice: ^_charArraySlice, index: i32) -> [^]u8 {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &char_DEFAULT)
}

// clay.h:1065 — Clay__charArray_RemoveSwapback
@(private)
_charArray_RemoveSwapback :: proc "c" (array: ^_charArray, index: i32) -> u8 {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: u8 = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return char_DEFAULT
}

// clay.h:1065 — Clay__charArray_Set
@(private)
_charArray_Set :: proc "c" (array: ^_charArray, index: i32, value: u8) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
ElementId_DEFAULT: ElementId = ElementId{id = cast(u32)(0)}

// clay.h:1066 — Clay_ElementIdArray_Allocate_Arena
ElementIdArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> ElementIdArray {
	return ElementIdArray{capacity = capacity, length = 0, internalArray = cast([^]ElementId)(cast(^ElementId)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(ElementId)), arena)))}
}

// clay.h:1066 — Clay_ElementIdArray_Get
ElementIdArray_Get :: proc "c" (array: ^ElementIdArray, index: i32) -> ^ElementId {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &ElementId_DEFAULT)
}

// clay.h:1066 — Clay_ElementIdArray_GetValue
ElementIdArray_GetValue :: proc "c" (array: ^ElementIdArray, index: i32) -> ElementId {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : ElementId_DEFAULT)
}

// clay.h:1066 — Clay_ElementIdArray_Add
ElementIdArray_Add :: proc "c" (array: ^ElementIdArray, item: ElementId) -> ^ElementId {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &ElementId_DEFAULT
}

// clay.h:1066 — Clay_ElementIdArraySlice_Get
ElementIdArraySlice_Get :: proc "c" (slice: ^ElementIdArraySlice, index: i32) -> ^ElementId {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &ElementId_DEFAULT)
}

// clay.h:1066 — Clay_ElementIdArray_RemoveSwapback
ElementIdArray_RemoveSwapback :: proc "c" (array: ^ElementIdArray, index: i32) -> ElementId {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: ElementId = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return ElementId_DEFAULT
}

// clay.h:1066 — Clay_ElementIdArray_Set
ElementIdArray_Set :: proc "c" (array: ^ElementIdArray, index: i32, value: ElementId) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
LayoutConfig_DEFAULT: LayoutConfig = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}}}}

// clay.h:1067 — Clay__LayoutConfigArray_Allocate_Arena
@(private)
_LayoutConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _LayoutConfigArray {
	return _LayoutConfigArray{capacity = capacity, length = 0, internalArray = cast([^]LayoutConfig)(cast(^LayoutConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(LayoutConfig)), arena)))}
}

// clay.h:1067 — Clay__LayoutConfigArray_Get
@(private)
_LayoutConfigArray_Get :: proc "c" (array: ^_LayoutConfigArray, index: i32) -> ^LayoutConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &LayoutConfig_DEFAULT)
}

// clay.h:1067 — Clay__LayoutConfigArray_GetValue
@(private)
_LayoutConfigArray_GetValue :: proc "c" (array: ^_LayoutConfigArray, index: i32) -> LayoutConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : LayoutConfig_DEFAULT)
}

// clay.h:1067 — Clay__LayoutConfigArray_Add
@(private)
_LayoutConfigArray_Add :: proc "c" (array: ^_LayoutConfigArray, item: LayoutConfig) -> ^LayoutConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &LayoutConfig_DEFAULT
}

// clay.h:1067 — Clay__LayoutConfigArraySlice_Get
@(private)
_LayoutConfigArraySlice_Get :: proc "c" (slice: ^_LayoutConfigArraySlice, index: i32) -> ^LayoutConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &LayoutConfig_DEFAULT)
}

// clay.h:1067 — Clay__LayoutConfigArray_RemoveSwapback
@(private)
_LayoutConfigArray_RemoveSwapback :: proc "c" (array: ^_LayoutConfigArray, index: i32) -> LayoutConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: LayoutConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return LayoutConfig_DEFAULT
}

// clay.h:1067 — Clay__LayoutConfigArray_Set
@(private)
_LayoutConfigArray_Set :: proc "c" (array: ^_LayoutConfigArray, index: i32, value: LayoutConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
TextElementConfig_DEFAULT: TextElementConfig = TextElementConfig{userData = nil}

// clay.h:1068 — Clay__TextElementConfigArray_Allocate_Arena
@(private)
_TextElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _TextElementConfigArray {
	return _TextElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]TextElementConfig)(cast(^TextElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(TextElementConfig)), arena)))}
}

// clay.h:1068 — Clay__TextElementConfigArray_Get
@(private)
_TextElementConfigArray_Get :: proc "c" (array: ^_TextElementConfigArray, index: i32) -> ^TextElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &TextElementConfig_DEFAULT)
}

// clay.h:1068 — Clay__TextElementConfigArray_GetValue
@(private)
_TextElementConfigArray_GetValue :: proc "c" (array: ^_TextElementConfigArray, index: i32) -> TextElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : TextElementConfig_DEFAULT)
}

// clay.h:1068 — Clay__TextElementConfigArray_Add
@(private)
_TextElementConfigArray_Add :: proc "c" (array: ^_TextElementConfigArray, item: TextElementConfig) -> ^TextElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &TextElementConfig_DEFAULT
}

// clay.h:1068 — Clay__TextElementConfigArraySlice_Get
@(private)
_TextElementConfigArraySlice_Get :: proc "c" (slice: ^_TextElementConfigArraySlice, index: i32) -> ^TextElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &TextElementConfig_DEFAULT)
}

// clay.h:1068 — Clay__TextElementConfigArray_RemoveSwapback
@(private)
_TextElementConfigArray_RemoveSwapback :: proc "c" (array: ^_TextElementConfigArray, index: i32) -> TextElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: TextElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return TextElementConfig_DEFAULT
}

// clay.h:1068 — Clay__TextElementConfigArray_Set
@(private)
_TextElementConfigArray_Set :: proc "c" (array: ^_TextElementConfigArray, index: i32, value: TextElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
AspectRatioElementConfig_DEFAULT: AspectRatioElementConfig = AspectRatioElementConfig{aspectRatio = cast(f32)(0)}

// clay.h:1069 — Clay__AspectRatioElementConfigArray_Allocate_Arena
@(private)
_AspectRatioElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _AspectRatioElementConfigArray {
	return _AspectRatioElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]AspectRatioElementConfig)(cast(^AspectRatioElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(AspectRatioElementConfig)), arena)))}
}

// clay.h:1069 — Clay__AspectRatioElementConfigArray_Get
@(private)
_AspectRatioElementConfigArray_Get :: proc "c" (array: ^_AspectRatioElementConfigArray, index: i32) -> ^AspectRatioElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &AspectRatioElementConfig_DEFAULT)
}

// clay.h:1069 — Clay__AspectRatioElementConfigArray_GetValue
@(private)
_AspectRatioElementConfigArray_GetValue :: proc "c" (array: ^_AspectRatioElementConfigArray, index: i32) -> AspectRatioElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : AspectRatioElementConfig_DEFAULT)
}

// clay.h:1069 — Clay__AspectRatioElementConfigArray_Add
@(private)
_AspectRatioElementConfigArray_Add :: proc "c" (array: ^_AspectRatioElementConfigArray, item: AspectRatioElementConfig) -> ^AspectRatioElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &AspectRatioElementConfig_DEFAULT
}

// clay.h:1069 — Clay__AspectRatioElementConfigArraySlice_Get
@(private)
_AspectRatioElementConfigArraySlice_Get :: proc "c" (slice: ^_AspectRatioElementConfigArraySlice, index: i32) -> ^AspectRatioElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &AspectRatioElementConfig_DEFAULT)
}

// clay.h:1069 — Clay__AspectRatioElementConfigArray_RemoveSwapback
@(private)
_AspectRatioElementConfigArray_RemoveSwapback :: proc "c" (array: ^_AspectRatioElementConfigArray, index: i32) -> AspectRatioElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: AspectRatioElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return AspectRatioElementConfig_DEFAULT
}

// clay.h:1069 — Clay__AspectRatioElementConfigArray_Set
@(private)
_AspectRatioElementConfigArray_Set :: proc "c" (array: ^_AspectRatioElementConfigArray, index: i32, value: AspectRatioElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
ImageElementConfig_DEFAULT: ImageElementConfig = ImageElementConfig{imageData = nil}

// clay.h:1070 — Clay__ImageElementConfigArray_Allocate_Arena
@(private)
_ImageElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _ImageElementConfigArray {
	return _ImageElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]ImageElementConfig)(cast(^ImageElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(ImageElementConfig)), arena)))}
}

// clay.h:1070 — Clay__ImageElementConfigArray_Get
@(private)
_ImageElementConfigArray_Get :: proc "c" (array: ^_ImageElementConfigArray, index: i32) -> ^ImageElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &ImageElementConfig_DEFAULT)
}

// clay.h:1070 — Clay__ImageElementConfigArray_GetValue
@(private)
_ImageElementConfigArray_GetValue :: proc "c" (array: ^_ImageElementConfigArray, index: i32) -> ImageElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : ImageElementConfig_DEFAULT)
}

// clay.h:1070 — Clay__ImageElementConfigArray_Add
@(private)
_ImageElementConfigArray_Add :: proc "c" (array: ^_ImageElementConfigArray, item: ImageElementConfig) -> ^ImageElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &ImageElementConfig_DEFAULT
}

// clay.h:1070 — Clay__ImageElementConfigArraySlice_Get
@(private)
_ImageElementConfigArraySlice_Get :: proc "c" (slice: ^_ImageElementConfigArraySlice, index: i32) -> ^ImageElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &ImageElementConfig_DEFAULT)
}

// clay.h:1070 — Clay__ImageElementConfigArray_RemoveSwapback
@(private)
_ImageElementConfigArray_RemoveSwapback :: proc "c" (array: ^_ImageElementConfigArray, index: i32) -> ImageElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: ImageElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return ImageElementConfig_DEFAULT
}

// clay.h:1070 — Clay__ImageElementConfigArray_Set
@(private)
_ImageElementConfigArray_Set :: proc "c" (array: ^_ImageElementConfigArray, index: i32, value: ImageElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
FloatingElementConfig_DEFAULT: FloatingElementConfig = FloatingElementConfig{offset = Vector2{cast(f32)(0), 0}}

// clay.h:1071 — Clay__FloatingElementConfigArray_Allocate_Arena
@(private)
_FloatingElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _FloatingElementConfigArray {
	return _FloatingElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]FloatingElementConfig)(cast(^FloatingElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(FloatingElementConfig)), arena)))}
}

// clay.h:1071 — Clay__FloatingElementConfigArray_Get
@(private)
_FloatingElementConfigArray_Get :: proc "c" (array: ^_FloatingElementConfigArray, index: i32) -> ^FloatingElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &FloatingElementConfig_DEFAULT)
}

// clay.h:1071 — Clay__FloatingElementConfigArray_GetValue
@(private)
_FloatingElementConfigArray_GetValue :: proc "c" (array: ^_FloatingElementConfigArray, index: i32) -> FloatingElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : FloatingElementConfig_DEFAULT)
}

// clay.h:1071 — Clay__FloatingElementConfigArray_Add
@(private)
_FloatingElementConfigArray_Add :: proc "c" (array: ^_FloatingElementConfigArray, item: FloatingElementConfig) -> ^FloatingElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &FloatingElementConfig_DEFAULT
}

// clay.h:1071 — Clay__FloatingElementConfigArraySlice_Get
@(private)
_FloatingElementConfigArraySlice_Get :: proc "c" (slice: ^_FloatingElementConfigArraySlice, index: i32) -> ^FloatingElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &FloatingElementConfig_DEFAULT)
}

// clay.h:1071 — Clay__FloatingElementConfigArray_RemoveSwapback
@(private)
_FloatingElementConfigArray_RemoveSwapback :: proc "c" (array: ^_FloatingElementConfigArray, index: i32) -> FloatingElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: FloatingElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return FloatingElementConfig_DEFAULT
}

// clay.h:1071 — Clay__FloatingElementConfigArray_Set
@(private)
_FloatingElementConfigArray_Set :: proc "c" (array: ^_FloatingElementConfigArray, index: i32, value: FloatingElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
CustomElementConfig_DEFAULT: CustomElementConfig = CustomElementConfig{customData = nil}

// clay.h:1072 — Clay__CustomElementConfigArray_Allocate_Arena
@(private)
_CustomElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _CustomElementConfigArray {
	return _CustomElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]CustomElementConfig)(cast(^CustomElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(CustomElementConfig)), arena)))}
}

// clay.h:1072 — Clay__CustomElementConfigArray_Get
@(private)
_CustomElementConfigArray_Get :: proc "c" (array: ^_CustomElementConfigArray, index: i32) -> ^CustomElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &CustomElementConfig_DEFAULT)
}

// clay.h:1072 — Clay__CustomElementConfigArray_GetValue
@(private)
_CustomElementConfigArray_GetValue :: proc "c" (array: ^_CustomElementConfigArray, index: i32) -> CustomElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : CustomElementConfig_DEFAULT)
}

// clay.h:1072 — Clay__CustomElementConfigArray_Add
@(private)
_CustomElementConfigArray_Add :: proc "c" (array: ^_CustomElementConfigArray, item: CustomElementConfig) -> ^CustomElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &CustomElementConfig_DEFAULT
}

// clay.h:1072 — Clay__CustomElementConfigArraySlice_Get
@(private)
_CustomElementConfigArraySlice_Get :: proc "c" (slice: ^_CustomElementConfigArraySlice, index: i32) -> ^CustomElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &CustomElementConfig_DEFAULT)
}

// clay.h:1072 — Clay__CustomElementConfigArray_RemoveSwapback
@(private)
_CustomElementConfigArray_RemoveSwapback :: proc "c" (array: ^_CustomElementConfigArray, index: i32) -> CustomElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: CustomElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return CustomElementConfig_DEFAULT
}

// clay.h:1072 — Clay__CustomElementConfigArray_Set
@(private)
_CustomElementConfigArray_Set :: proc "c" (array: ^_CustomElementConfigArray, index: i32, value: CustomElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
ClipElementConfig_DEFAULT: ClipElementConfig = ClipElementConfig{horizontal = false}

// clay.h:1073 — Clay__ClipElementConfigArray_Allocate_Arena
@(private)
_ClipElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _ClipElementConfigArray {
	return _ClipElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]ClipElementConfig)(cast(^ClipElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(ClipElementConfig)), arena)))}
}

// clay.h:1073 — Clay__ClipElementConfigArray_Get
@(private)
_ClipElementConfigArray_Get :: proc "c" (array: ^_ClipElementConfigArray, index: i32) -> ^ClipElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &ClipElementConfig_DEFAULT)
}

// clay.h:1073 — Clay__ClipElementConfigArray_GetValue
@(private)
_ClipElementConfigArray_GetValue :: proc "c" (array: ^_ClipElementConfigArray, index: i32) -> ClipElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : ClipElementConfig_DEFAULT)
}

// clay.h:1073 — Clay__ClipElementConfigArray_Add
@(private)
_ClipElementConfigArray_Add :: proc "c" (array: ^_ClipElementConfigArray, item: ClipElementConfig) -> ^ClipElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &ClipElementConfig_DEFAULT
}

// clay.h:1073 — Clay__ClipElementConfigArraySlice_Get
@(private)
_ClipElementConfigArraySlice_Get :: proc "c" (slice: ^_ClipElementConfigArraySlice, index: i32) -> ^ClipElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &ClipElementConfig_DEFAULT)
}

// clay.h:1073 — Clay__ClipElementConfigArray_RemoveSwapback
@(private)
_ClipElementConfigArray_RemoveSwapback :: proc "c" (array: ^_ClipElementConfigArray, index: i32) -> ClipElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: ClipElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return ClipElementConfig_DEFAULT
}

// clay.h:1073 — Clay__ClipElementConfigArray_Set
@(private)
_ClipElementConfigArray_Set :: proc "c" (array: ^_ClipElementConfigArray, index: i32, value: ClipElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
BorderElementConfig_DEFAULT: BorderElementConfig = BorderElementConfig{color = Color{cast(f32)(0), 0, 0, 0}}

// clay.h:1074 — Clay__BorderElementConfigArray_Allocate_Arena
@(private)
_BorderElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _BorderElementConfigArray {
	return _BorderElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]BorderElementConfig)(cast(^BorderElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(BorderElementConfig)), arena)))}
}

// clay.h:1074 — Clay__BorderElementConfigArray_Get
@(private)
_BorderElementConfigArray_Get :: proc "c" (array: ^_BorderElementConfigArray, index: i32) -> ^BorderElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &BorderElementConfig_DEFAULT)
}

// clay.h:1074 — Clay__BorderElementConfigArray_GetValue
@(private)
_BorderElementConfigArray_GetValue :: proc "c" (array: ^_BorderElementConfigArray, index: i32) -> BorderElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : BorderElementConfig_DEFAULT)
}

// clay.h:1074 — Clay__BorderElementConfigArray_Add
@(private)
_BorderElementConfigArray_Add :: proc "c" (array: ^_BorderElementConfigArray, item: BorderElementConfig) -> ^BorderElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &BorderElementConfig_DEFAULT
}

// clay.h:1074 — Clay__BorderElementConfigArraySlice_Get
@(private)
_BorderElementConfigArraySlice_Get :: proc "c" (slice: ^_BorderElementConfigArraySlice, index: i32) -> ^BorderElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &BorderElementConfig_DEFAULT)
}

// clay.h:1074 — Clay__BorderElementConfigArray_RemoveSwapback
@(private)
_BorderElementConfigArray_RemoveSwapback :: proc "c" (array: ^_BorderElementConfigArray, index: i32) -> BorderElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: BorderElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return BorderElementConfig_DEFAULT
}

// clay.h:1074 — Clay__BorderElementConfigArray_Set
@(private)
_BorderElementConfigArray_Set :: proc "c" (array: ^_BorderElementConfigArray, index: i32, value: BorderElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
String_DEFAULT: String = String{isStaticallyAllocated = false}

// clay.h:1075 — Clay__StringArray_Allocate_Arena
@(private)
_StringArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _StringArray {
	return _StringArray{capacity = capacity, length = 0, internalArray = cast([^]String)(cast(^String)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(String)), arena)))}
}

// clay.h:1075 — Clay__StringArray_Get
@(private)
_StringArray_Get :: proc "c" (array: ^_StringArray, index: i32) -> ^String {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &String_DEFAULT)
}

// clay.h:1075 — Clay__StringArray_GetValue
@(private)
_StringArray_GetValue :: proc "c" (array: ^_StringArray, index: i32) -> String {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : String_DEFAULT)
}

// clay.h:1075 — Clay__StringArray_Add
@(private)
_StringArray_Add :: proc "c" (array: ^_StringArray, item: String) -> ^String {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &String_DEFAULT
}

// clay.h:1075 — Clay__StringArraySlice_Get
@(private)
_StringArraySlice_Get :: proc "c" (slice: ^_StringArraySlice, index: i32) -> ^String {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &String_DEFAULT)
}

// clay.h:1075 — Clay__StringArray_RemoveSwapback
@(private)
_StringArray_RemoveSwapback :: proc "c" (array: ^_StringArray, index: i32) -> String {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: String = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return String_DEFAULT
}

// clay.h:1075 — Clay__StringArray_Set
@(private)
_StringArray_Set :: proc "c" (array: ^_StringArray, index: i32, value: String) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
SharedElementConfig_DEFAULT: SharedElementConfig = SharedElementConfig{backgroundColor = Color{cast(f32)(0), 0, 0, 0}}

// clay.h:1076 — Clay__SharedElementConfigArray_Allocate_Arena
@(private)
_SharedElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _SharedElementConfigArray {
	return _SharedElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]SharedElementConfig)(cast(^SharedElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(SharedElementConfig)), arena)))}
}

// clay.h:1076 — Clay__SharedElementConfigArray_Get
@(private)
_SharedElementConfigArray_Get :: proc "c" (array: ^_SharedElementConfigArray, index: i32) -> ^SharedElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &SharedElementConfig_DEFAULT)
}

// clay.h:1076 — Clay__SharedElementConfigArray_GetValue
@(private)
_SharedElementConfigArray_GetValue :: proc "c" (array: ^_SharedElementConfigArray, index: i32) -> SharedElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : SharedElementConfig_DEFAULT)
}

// clay.h:1076 — Clay__SharedElementConfigArray_Add
@(private)
_SharedElementConfigArray_Add :: proc "c" (array: ^_SharedElementConfigArray, item: SharedElementConfig) -> ^SharedElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &SharedElementConfig_DEFAULT
}

// clay.h:1076 — Clay__SharedElementConfigArraySlice_Get
@(private)
_SharedElementConfigArraySlice_Get :: proc "c" (slice: ^_SharedElementConfigArraySlice, index: i32) -> ^SharedElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &SharedElementConfig_DEFAULT)
}

// clay.h:1076 — Clay__SharedElementConfigArray_RemoveSwapback
@(private)
_SharedElementConfigArray_RemoveSwapback :: proc "c" (array: ^_SharedElementConfigArray, index: i32) -> SharedElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: SharedElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return SharedElementConfig_DEFAULT
}

// clay.h:1076 — Clay__SharedElementConfigArray_Set
@(private)
_SharedElementConfigArray_Set :: proc "c" (array: ^_SharedElementConfigArray, index: i32, value: SharedElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
RenderCommand_DEFAULT: RenderCommand = RenderCommand{boundingBox = BoundingBox{x = cast(f32)(0)}}

// clay.h:1077 — Clay_RenderCommandArray_Allocate_Arena
RenderCommandArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> ClayArray(RenderCommand) {
	return ClayArray(RenderCommand){capacity = capacity, length = 0, internalArray = cast([^]RenderCommand)(cast(^RenderCommand)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(RenderCommand)), arena)))}
}

// clay.h:1077 — Clay_RenderCommandArray_Get
RenderCommandArray_Get :: proc "c" (array: ^ClayArray(RenderCommand), index: i32) -> ^RenderCommand {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &RenderCommand_DEFAULT)
}

// clay.h:1077 — Clay_RenderCommandArray_GetValue
RenderCommandArray_GetValue :: proc "c" (array: ^ClayArray(RenderCommand), index: i32) -> RenderCommand {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : RenderCommand_DEFAULT)
}

// clay.h:1077 — Clay_RenderCommandArray_Add
RenderCommandArray_Add :: proc "c" (array: ^ClayArray(RenderCommand), item: RenderCommand) -> ^RenderCommand {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &RenderCommand_DEFAULT
}

// clay.h:1077 — Clay_RenderCommandArraySlice_Get
RenderCommandArraySlice_Get :: proc "c" (slice: ^RenderCommandArraySlice, index: i32) -> ^RenderCommand {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &RenderCommand_DEFAULT)
}

// clay.h:1077 — Clay_RenderCommandArray_RemoveSwapback
RenderCommandArray_RemoveSwapback :: proc "c" (array: ^ClayArray(RenderCommand), index: i32) -> RenderCommand {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: RenderCommand = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return RenderCommand_DEFAULT
}

// clay.h:1077 — Clay_RenderCommandArray_Set
RenderCommandArray_Set :: proc "c" (array: ^ClayArray(RenderCommand), index: i32, value: RenderCommand) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
ElementConfig_DEFAULT: ElementConfig = ElementConfig{type = cast(_ElementConfigType)(0)}

// clay.h:1107 — Clay__ElementConfigArray_Allocate_Arena
@(private)
_ElementConfigArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _ElementConfigArray {
	return _ElementConfigArray{capacity = capacity, length = 0, internalArray = cast([^]ElementConfig)(cast(^ElementConfig)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(ElementConfig)), arena)))}
}

// clay.h:1107 — Clay__ElementConfigArray_Get
@(private)
_ElementConfigArray_Get :: proc "c" (array: ^_ElementConfigArray, index: i32) -> ^ElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &ElementConfig_DEFAULT)
}

// clay.h:1107 — Clay__ElementConfigArray_GetValue
@(private)
_ElementConfigArray_GetValue :: proc "c" (array: ^_ElementConfigArray, index: i32) -> ElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : ElementConfig_DEFAULT)
}

// clay.h:1107 — Clay__ElementConfigArray_Add
@(private)
_ElementConfigArray_Add :: proc "c" (array: ^_ElementConfigArray, item: ElementConfig) -> ^ElementConfig {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &ElementConfig_DEFAULT
}

// clay.h:1107 — Clay__ElementConfigArraySlice_Get
@(private)
_ElementConfigArraySlice_Get :: proc "c" (slice: ^_ElementConfigArraySlice, index: i32) -> ^ElementConfig {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &ElementConfig_DEFAULT)
}

// clay.h:1107 — Clay__ElementConfigArray_RemoveSwapback
@(private)
_ElementConfigArray_RemoveSwapback :: proc "c" (array: ^_ElementConfigArray, index: i32) -> ElementConfig {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: ElementConfig = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return ElementConfig_DEFAULT
}

// clay.h:1107 — Clay__ElementConfigArray_Set
@(private)
_ElementConfigArray_Set :: proc "c" (array: ^_ElementConfigArray, index: i32, value: ElementConfig) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_WrappedTextLine_DEFAULT: _WrappedTextLine = _WrappedTextLine{dimensions = Dimensions{width = cast(f32)(0)}}

// clay.h:1114 — Clay__WrappedTextLineArray_Allocate_Arena
@(private)
_WrappedTextLineArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _WrappedTextLineArray {
	return _WrappedTextLineArray{capacity = capacity, length = 0, internalArray = cast([^]_WrappedTextLine)(cast(^_WrappedTextLine)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_WrappedTextLine)), arena)))}
}

// clay.h:1114 — Clay__WrappedTextLineArray_Get
@(private)
_WrappedTextLineArray_Get :: proc "c" (array: ^_WrappedTextLineArray, index: i32) -> ^_WrappedTextLine {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_WrappedTextLine_DEFAULT)
}

// clay.h:1114 — Clay__WrappedTextLineArray_GetValue
@(private)
_WrappedTextLineArray_GetValue :: proc "c" (array: ^_WrappedTextLineArray, index: i32) -> _WrappedTextLine {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _WrappedTextLine_DEFAULT)
}

// clay.h:1114 — Clay__WrappedTextLineArray_Add
@(private)
_WrappedTextLineArray_Add :: proc "c" (array: ^_WrappedTextLineArray, item: _WrappedTextLine) -> ^_WrappedTextLine {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_WrappedTextLine_DEFAULT
}

// clay.h:1114 — Clay__WrappedTextLineArraySlice_Get
@(private)
_WrappedTextLineArraySlice_Get :: proc "c" (slice: ^_WrappedTextLineArraySlice, index: i32) -> ^_WrappedTextLine {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_WrappedTextLine_DEFAULT)
}

// clay.h:1114 — Clay__WrappedTextLineArray_RemoveSwapback
@(private)
_WrappedTextLineArray_RemoveSwapback :: proc "c" (array: ^_WrappedTextLineArray, index: i32) -> _WrappedTextLine {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _WrappedTextLine = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _WrappedTextLine_DEFAULT
}

// clay.h:1114 — Clay__WrappedTextLineArray_Set
@(private)
_WrappedTextLineArray_Set :: proc "c" (array: ^_WrappedTextLineArray, index: i32, value: _WrappedTextLine) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_TextElementData_DEFAULT: _TextElementData = _TextElementData{text = String{isStaticallyAllocated = false}}

// clay.h:1123 — Clay__TextElementDataArray_Allocate_Arena
@(private)
_TextElementDataArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _TextElementDataArray {
	return _TextElementDataArray{capacity = capacity, length = 0, internalArray = cast([^]_TextElementData)(cast(^_TextElementData)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_TextElementData)), arena)))}
}

// clay.h:1123 — Clay__TextElementDataArray_Get
@(private)
_TextElementDataArray_Get :: proc "c" (array: ^_TextElementDataArray, index: i32) -> ^_TextElementData {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_TextElementData_DEFAULT)
}

// clay.h:1123 — Clay__TextElementDataArray_GetValue
@(private)
_TextElementDataArray_GetValue :: proc "c" (array: ^_TextElementDataArray, index: i32) -> _TextElementData {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _TextElementData_DEFAULT)
}

// clay.h:1123 — Clay__TextElementDataArray_Add
@(private)
_TextElementDataArray_Add :: proc "c" (array: ^_TextElementDataArray, item: _TextElementData) -> ^_TextElementData {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_TextElementData_DEFAULT
}

// clay.h:1123 — Clay__TextElementDataArraySlice_Get
@(private)
_TextElementDataArraySlice_Get :: proc "c" (slice: ^_TextElementDataArraySlice, index: i32) -> ^_TextElementData {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_TextElementData_DEFAULT)
}

// clay.h:1123 — Clay__TextElementDataArray_RemoveSwapback
@(private)
_TextElementDataArray_RemoveSwapback :: proc "c" (array: ^_TextElementDataArray, index: i32) -> _TextElementData {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _TextElementData = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _TextElementData_DEFAULT
}

// clay.h:1123 — Clay__TextElementDataArray_Set
@(private)
_TextElementDataArray_Set :: proc "c" (array: ^_TextElementDataArray, index: i32, value: _TextElementData) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
LayoutElement_DEFAULT: LayoutElement = LayoutElement{childrenOrTextContent = LayoutElement_childrenOrTextContent{children = _LayoutElementChildren{elements = nil}}}

// clay.h:1142 — Clay_LayoutElementArray_Allocate_Arena
LayoutElementArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> LayoutElementArray {
	return LayoutElementArray{capacity = capacity, length = 0, internalArray = cast([^]LayoutElement)(cast(^LayoutElement)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(LayoutElement)), arena)))}
}

// clay.h:1142 — Clay_LayoutElementArray_Get
LayoutElementArray_Get :: proc "c" (array: ^LayoutElementArray, index: i32) -> ^LayoutElement {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &LayoutElement_DEFAULT)
}

// clay.h:1142 — Clay_LayoutElementArray_GetValue
LayoutElementArray_GetValue :: proc "c" (array: ^LayoutElementArray, index: i32) -> LayoutElement {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : LayoutElement_DEFAULT)
}

// clay.h:1142 — Clay_LayoutElementArray_Add
LayoutElementArray_Add :: proc "c" (array: ^LayoutElementArray, item: LayoutElement) -> ^LayoutElement {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &LayoutElement_DEFAULT
}

// clay.h:1142 — Clay_LayoutElementArraySlice_Get
LayoutElementArraySlice_Get :: proc "c" (slice: ^LayoutElementArraySlice, index: i32) -> ^LayoutElement {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &LayoutElement_DEFAULT)
}

// clay.h:1142 — Clay_LayoutElementArray_RemoveSwapback
LayoutElementArray_RemoveSwapback :: proc "c" (array: ^LayoutElementArray, index: i32) -> LayoutElement {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: LayoutElement = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return LayoutElement_DEFAULT
}

// clay.h:1142 — Clay_LayoutElementArray_Set
LayoutElementArray_Set :: proc "c" (array: ^LayoutElementArray, index: i32, value: LayoutElement) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_ScrollContainerDataInternal_DEFAULT: _ScrollContainerDataInternal = _ScrollContainerDataInternal{layoutElement = nil}

// clay.h:1159 — Clay__ScrollContainerDataInternalArray_Allocate_Arena
@(private)
_ScrollContainerDataInternalArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _ScrollContainerDataInternalArray {
	return _ScrollContainerDataInternalArray{capacity = capacity, length = 0, internalArray = cast([^]_ScrollContainerDataInternal)(cast(^_ScrollContainerDataInternal)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_ScrollContainerDataInternal)), arena)))}
}

// clay.h:1159 — Clay__ScrollContainerDataInternalArray_Get
@(private)
_ScrollContainerDataInternalArray_Get :: proc "c" (array: ^_ScrollContainerDataInternalArray, index: i32) -> ^_ScrollContainerDataInternal {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_ScrollContainerDataInternal_DEFAULT)
}

// clay.h:1159 — Clay__ScrollContainerDataInternalArray_GetValue
@(private)
_ScrollContainerDataInternalArray_GetValue :: proc "c" (array: ^_ScrollContainerDataInternalArray, index: i32) -> _ScrollContainerDataInternal {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _ScrollContainerDataInternal_DEFAULT)
}

// clay.h:1159 — Clay__ScrollContainerDataInternalArray_Add
@(private)
_ScrollContainerDataInternalArray_Add :: proc "c" (array: ^_ScrollContainerDataInternalArray, item: _ScrollContainerDataInternal) -> ^_ScrollContainerDataInternal {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_ScrollContainerDataInternal_DEFAULT
}

// clay.h:1159 — Clay__ScrollContainerDataInternalArraySlice_Get
@(private)
_ScrollContainerDataInternalArraySlice_Get :: proc "c" (slice: ^_ScrollContainerDataInternalArraySlice, index: i32) -> ^_ScrollContainerDataInternal {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_ScrollContainerDataInternal_DEFAULT)
}

// clay.h:1159 — Clay__ScrollContainerDataInternalArray_RemoveSwapback
@(private)
_ScrollContainerDataInternalArray_RemoveSwapback :: proc "c" (array: ^_ScrollContainerDataInternalArray, index: i32) -> _ScrollContainerDataInternal {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _ScrollContainerDataInternal = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _ScrollContainerDataInternal_DEFAULT
}

// clay.h:1159 — Clay__ScrollContainerDataInternalArray_Set
@(private)
_ScrollContainerDataInternalArray_Set :: proc "c" (array: ^_ScrollContainerDataInternalArray, index: i32, value: _ScrollContainerDataInternal) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_DebugElementData_DEFAULT: _DebugElementData = _DebugElementData{collision = false}

// clay.h:1166 — Clay__DebugElementDataArray_Allocate_Arena
@(private)
_DebugElementDataArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _DebugElementDataArray {
	return _DebugElementDataArray{capacity = capacity, length = 0, internalArray = cast([^]_DebugElementData)(cast(^_DebugElementData)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_DebugElementData)), arena)))}
}

// clay.h:1166 — Clay__DebugElementDataArray_Get
@(private)
_DebugElementDataArray_Get :: proc "c" (array: ^_DebugElementDataArray, index: i32) -> ^_DebugElementData {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_DebugElementData_DEFAULT)
}

// clay.h:1166 — Clay__DebugElementDataArray_GetValue
@(private)
_DebugElementDataArray_GetValue :: proc "c" (array: ^_DebugElementDataArray, index: i32) -> _DebugElementData {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _DebugElementData_DEFAULT)
}

// clay.h:1166 — Clay__DebugElementDataArray_Add
@(private)
_DebugElementDataArray_Add :: proc "c" (array: ^_DebugElementDataArray, item: _DebugElementData) -> ^_DebugElementData {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_DebugElementData_DEFAULT
}

// clay.h:1166 — Clay__DebugElementDataArraySlice_Get
@(private)
_DebugElementDataArraySlice_Get :: proc "c" (slice: ^_DebugElementDataArraySlice, index: i32) -> ^_DebugElementData {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_DebugElementData_DEFAULT)
}

// clay.h:1166 — Clay__DebugElementDataArray_RemoveSwapback
@(private)
_DebugElementDataArray_RemoveSwapback :: proc "c" (array: ^_DebugElementDataArray, index: i32) -> _DebugElementData {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _DebugElementData = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _DebugElementData_DEFAULT
}

// clay.h:1166 — Clay__DebugElementDataArray_Set
@(private)
_DebugElementDataArray_Set :: proc "c" (array: ^_DebugElementDataArray, index: i32, value: _DebugElementData) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
LayoutElementHashMapItem_DEFAULT: LayoutElementHashMapItem = LayoutElementHashMapItem{boundingBox = BoundingBox{x = cast(f32)(0)}}

// clay.h:1180 — Clay__LayoutElementHashMapItemArray_Allocate_Arena
@(private)
_LayoutElementHashMapItemArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _LayoutElementHashMapItemArray {
	return _LayoutElementHashMapItemArray{capacity = capacity, length = 0, internalArray = cast([^]LayoutElementHashMapItem)(cast(^LayoutElementHashMapItem)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(LayoutElementHashMapItem)), arena)))}
}

// clay.h:1180 — Clay__LayoutElementHashMapItemArray_Get
@(private)
_LayoutElementHashMapItemArray_Get :: proc "c" (array: ^_LayoutElementHashMapItemArray, index: i32) -> ^LayoutElementHashMapItem {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &LayoutElementHashMapItem_DEFAULT)
}

// clay.h:1180 — Clay__LayoutElementHashMapItemArray_GetValue
@(private)
_LayoutElementHashMapItemArray_GetValue :: proc "c" (array: ^_LayoutElementHashMapItemArray, index: i32) -> LayoutElementHashMapItem {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : LayoutElementHashMapItem_DEFAULT)
}

// clay.h:1180 — Clay__LayoutElementHashMapItemArray_Add
@(private)
_LayoutElementHashMapItemArray_Add :: proc "c" (array: ^_LayoutElementHashMapItemArray, item: LayoutElementHashMapItem) -> ^LayoutElementHashMapItem {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &LayoutElementHashMapItem_DEFAULT
}

// clay.h:1180 — Clay__LayoutElementHashMapItemArraySlice_Get
@(private)
_LayoutElementHashMapItemArraySlice_Get :: proc "c" (slice: ^_LayoutElementHashMapItemArraySlice, index: i32) -> ^LayoutElementHashMapItem {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &LayoutElementHashMapItem_DEFAULT)
}

// clay.h:1180 — Clay__LayoutElementHashMapItemArray_RemoveSwapback
@(private)
_LayoutElementHashMapItemArray_RemoveSwapback :: proc "c" (array: ^_LayoutElementHashMapItemArray, index: i32) -> LayoutElementHashMapItem {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: LayoutElementHashMapItem = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return LayoutElementHashMapItem_DEFAULT
}

// clay.h:1180 — Clay__LayoutElementHashMapItemArray_Set
@(private)
_LayoutElementHashMapItemArray_Set :: proc "c" (array: ^_LayoutElementHashMapItemArray, index: i32, value: LayoutElementHashMapItem) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_MeasuredWord_DEFAULT: _MeasuredWord = _MeasuredWord{startOffset = 0}

// clay.h:1189 — Clay__MeasuredWordArray_Allocate_Arena
@(private)
_MeasuredWordArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _MeasuredWordArray {
	return _MeasuredWordArray{capacity = capacity, length = 0, internalArray = cast([^]_MeasuredWord)(cast(^_MeasuredWord)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_MeasuredWord)), arena)))}
}

// clay.h:1189 — Clay__MeasuredWordArray_Get
@(private)
_MeasuredWordArray_Get :: proc "c" (array: ^_MeasuredWordArray, index: i32) -> ^_MeasuredWord {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_MeasuredWord_DEFAULT)
}

// clay.h:1189 — Clay__MeasuredWordArray_GetValue
@(private)
_MeasuredWordArray_GetValue :: proc "c" (array: ^_MeasuredWordArray, index: i32) -> _MeasuredWord {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _MeasuredWord_DEFAULT)
}

// clay.h:1189 — Clay__MeasuredWordArray_Add
@(private)
_MeasuredWordArray_Add :: proc "c" (array: ^_MeasuredWordArray, item: _MeasuredWord) -> ^_MeasuredWord {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_MeasuredWord_DEFAULT
}

// clay.h:1189 — Clay__MeasuredWordArraySlice_Get
@(private)
_MeasuredWordArraySlice_Get :: proc "c" (slice: ^_MeasuredWordArraySlice, index: i32) -> ^_MeasuredWord {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_MeasuredWord_DEFAULT)
}

// clay.h:1189 — Clay__MeasuredWordArray_RemoveSwapback
@(private)
_MeasuredWordArray_RemoveSwapback :: proc "c" (array: ^_MeasuredWordArray, index: i32) -> _MeasuredWord {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _MeasuredWord = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _MeasuredWord_DEFAULT
}

// clay.h:1189 — Clay__MeasuredWordArray_Set
@(private)
_MeasuredWordArray_Set :: proc "c" (array: ^_MeasuredWordArray, index: i32, value: _MeasuredWord) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_MeasureTextCacheItem_DEFAULT: _MeasureTextCacheItem = _MeasureTextCacheItem{unwrappedDimensions = Dimensions{width = cast(f32)(0)}}

// clay.h:1202 — Clay__MeasureTextCacheItemArray_Allocate_Arena
@(private)
_MeasureTextCacheItemArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _MeasureTextCacheItemArray {
	return _MeasureTextCacheItemArray{capacity = capacity, length = 0, internalArray = cast([^]_MeasureTextCacheItem)(cast(^_MeasureTextCacheItem)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_MeasureTextCacheItem)), arena)))}
}

// clay.h:1202 — Clay__MeasureTextCacheItemArray_Get
@(private)
_MeasureTextCacheItemArray_Get :: proc "c" (array: ^_MeasureTextCacheItemArray, index: i32) -> ^_MeasureTextCacheItem {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_MeasureTextCacheItem_DEFAULT)
}

// clay.h:1202 — Clay__MeasureTextCacheItemArray_GetValue
@(private)
_MeasureTextCacheItemArray_GetValue :: proc "c" (array: ^_MeasureTextCacheItemArray, index: i32) -> _MeasureTextCacheItem {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _MeasureTextCacheItem_DEFAULT)
}

// clay.h:1202 — Clay__MeasureTextCacheItemArray_Add
@(private)
_MeasureTextCacheItemArray_Add :: proc "c" (array: ^_MeasureTextCacheItemArray, item: _MeasureTextCacheItem) -> ^_MeasureTextCacheItem {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_MeasureTextCacheItem_DEFAULT
}

// clay.h:1202 — Clay__MeasureTextCacheItemArraySlice_Get
@(private)
_MeasureTextCacheItemArraySlice_Get :: proc "c" (slice: ^_MeasureTextCacheItemArraySlice, index: i32) -> ^_MeasureTextCacheItem {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_MeasureTextCacheItem_DEFAULT)
}

// clay.h:1202 — Clay__MeasureTextCacheItemArray_RemoveSwapback
@(private)
_MeasureTextCacheItemArray_RemoveSwapback :: proc "c" (array: ^_MeasureTextCacheItemArray, index: i32) -> _MeasureTextCacheItem {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _MeasureTextCacheItem = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _MeasureTextCacheItem_DEFAULT
}

// clay.h:1202 — Clay__MeasureTextCacheItemArray_Set
@(private)
_MeasureTextCacheItemArray_Set :: proc "c" (array: ^_MeasureTextCacheItemArray, index: i32, value: _MeasureTextCacheItem) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_LayoutElementTreeNode_DEFAULT: _LayoutElementTreeNode = _LayoutElementTreeNode{layoutElement = nil}

// clay.h:1210 — Clay__LayoutElementTreeNodeArray_Allocate_Arena
@(private)
_LayoutElementTreeNodeArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _LayoutElementTreeNodeArray {
	return _LayoutElementTreeNodeArray{capacity = capacity, length = 0, internalArray = cast([^]_LayoutElementTreeNode)(cast(^_LayoutElementTreeNode)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_LayoutElementTreeNode)), arena)))}
}

// clay.h:1210 — Clay__LayoutElementTreeNodeArray_Get
@(private)
_LayoutElementTreeNodeArray_Get :: proc "c" (array: ^_LayoutElementTreeNodeArray, index: i32) -> ^_LayoutElementTreeNode {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_LayoutElementTreeNode_DEFAULT)
}

// clay.h:1210 — Clay__LayoutElementTreeNodeArray_GetValue
@(private)
_LayoutElementTreeNodeArray_GetValue :: proc "c" (array: ^_LayoutElementTreeNodeArray, index: i32) -> _LayoutElementTreeNode {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _LayoutElementTreeNode_DEFAULT)
}

// clay.h:1210 — Clay__LayoutElementTreeNodeArray_Add
@(private)
_LayoutElementTreeNodeArray_Add :: proc "c" (array: ^_LayoutElementTreeNodeArray, item: _LayoutElementTreeNode) -> ^_LayoutElementTreeNode {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_LayoutElementTreeNode_DEFAULT
}

// clay.h:1210 — Clay__LayoutElementTreeNodeArraySlice_Get
@(private)
_LayoutElementTreeNodeArraySlice_Get :: proc "c" (slice: ^_LayoutElementTreeNodeArraySlice, index: i32) -> ^_LayoutElementTreeNode {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_LayoutElementTreeNode_DEFAULT)
}

// clay.h:1210 — Clay__LayoutElementTreeNodeArray_RemoveSwapback
@(private)
_LayoutElementTreeNodeArray_RemoveSwapback :: proc "c" (array: ^_LayoutElementTreeNodeArray, index: i32) -> _LayoutElementTreeNode {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _LayoutElementTreeNode = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _LayoutElementTreeNode_DEFAULT
}

// clay.h:1210 — Clay__LayoutElementTreeNodeArray_Set
@(private)
_LayoutElementTreeNodeArray_Set :: proc "c" (array: ^_LayoutElementTreeNodeArray, index: i32, value: _LayoutElementTreeNode) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

@(private)
_LayoutElementTreeRoot_DEFAULT: _LayoutElementTreeRoot = _LayoutElementTreeRoot{layoutElementIndex = 0}

// clay.h:1220 — Clay__LayoutElementTreeRootArray_Allocate_Arena
@(private)
_LayoutElementTreeRootArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _LayoutElementTreeRootArray {
	return _LayoutElementTreeRootArray{capacity = capacity, length = 0, internalArray = cast([^]_LayoutElementTreeRoot)(cast(^_LayoutElementTreeRoot)(_Array_Allocate_Arena(capacity, cast(u32)(size_of(_LayoutElementTreeRoot)), arena)))}
}

// clay.h:1220 — Clay__LayoutElementTreeRootArray_Get
@(private)
_LayoutElementTreeRootArray_Get :: proc "c" (array: ^_LayoutElementTreeRootArray, index: i32) -> ^_LayoutElementTreeRoot {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? &array.internalArray[index] : &_LayoutElementTreeRoot_DEFAULT)
}

// clay.h:1220 — Clay__LayoutElementTreeRootArray_GetValue
@(private)
_LayoutElementTreeRootArray_GetValue :: proc "c" (array: ^_LayoutElementTreeRootArray, index: i32) -> _LayoutElementTreeRoot {
	return ((cast(i32)(_Array_RangeCheck(index, array.length)) != 0) ? array.internalArray[index] : _LayoutElementTreeRoot_DEFAULT)
}

// clay.h:1220 — Clay__LayoutElementTreeRootArray_Add
@(private)
_LayoutElementTreeRootArray_Add :: proc "c" (array: ^_LayoutElementTreeRootArray, item: _LayoutElementTreeRoot) -> ^_LayoutElementTreeRoot {
	if _Array_AddCapacityCheck(array.length, array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &_LayoutElementTreeRoot_DEFAULT
}

// clay.h:1220 — Clay__LayoutElementTreeRootArraySlice_Get
@(private)
_LayoutElementTreeRootArraySlice_Get :: proc "c" (slice: ^_LayoutElementTreeRootArraySlice, index: i32) -> ^_LayoutElementTreeRoot {
	return ((cast(i32)(_Array_RangeCheck(index, slice.length)) != 0) ? &slice.internalArray[index] : &_LayoutElementTreeRoot_DEFAULT)
}

// clay.h:1220 — Clay__LayoutElementTreeRootArray_RemoveSwapback
@(private)
_LayoutElementTreeRootArray_RemoveSwapback :: proc "c" (array: ^_LayoutElementTreeRootArray, index: i32) -> _LayoutElementTreeRoot {
	if _Array_RangeCheck(index, array.length) {
		array.length -= 1
		removed: _LayoutElementTreeRoot = array.internalArray[index]
		array.internalArray[index] = array.internalArray[array.length]
		return removed
	}
	return _LayoutElementTreeRoot_DEFAULT
}

// clay.h:1220 — Clay__LayoutElementTreeRootArray_Set
@(private)
_LayoutElementTreeRootArray_Set :: proc "c" (array: ^_LayoutElementTreeRootArray, index: i32, value: _LayoutElementTreeRoot) {
	if _Array_RangeCheck(index, array.capacity) {
		array.internalArray[index] = value
		array.length = ((index < array.length) ? array.length : (index + 1))
	}
}

// clay.h:1284 — Clay__Context_Allocate_Arena
@(private)
_Context_Allocate_Arena :: proc "c" (arena: ^Arena) -> ^Context {
	totalSizeBytes: uint = cast(uint)(size_of(Context))
	memoryAddress: uintptr = uintptr(arena.memory)
	// Make sure the memory address passed in for clay to use is cache line aligned
	nextAllocOffset: uintptr = (memoryAddress % cast(uintptr)(64))
	if ((nextAllocOffset + cast(uintptr)(totalSizeBytes)) > cast(uintptr)(arena.capacity)) {
		return nil
	}
	arena.nextAllocation = (nextAllocOffset + cast(uintptr)(totalSizeBytes))
	return cast(^Context)(uintptr((memoryAddress + nextAllocOffset)))
}

// clay.h:1297 — Clay__WriteStringToCharBuffer
@(private)
_WriteStringToCharBuffer :: proc "c" (buffer: ^_charArray, str: String) -> String {
	for i: i32 = 0; (i < str.length); i += 1 {
		buffer.internalArray[(buffer.length + i)] = str.chars[i]
	}
	buffer.length += str.length
	return String{length = str.length, chars = _offset(_offset(buffer.internalArray, int(buffer.length)), -int(str.length))}
}

@(private)
_MeasureText: proc "c" (StringSlice, ^TextElementConfig, rawptr) -> Dimensions

@(private)
_QueryScrollOffset: proc "c" (u32, rawptr) -> Vector2

// clay.h:1313 — Clay__GetOpenLayoutElement
@(private)
_GetOpenLayoutElement :: proc "c" () -> ^LayoutElement {
	ctx: ^Context = GetCurrentContext()
	return LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 1)))
}

// clay.h:1318 — Clay__GetParentElementId
_GetParentElementId :: proc "c" () -> u32 {
	ctx: ^Context = GetCurrentContext()
	return LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 2))).id
}

// clay.h:1323 — Clay__StoreLayoutConfig
@(private)
_StoreLayoutConfig :: proc "c" (config: LayoutConfig) -> ^LayoutConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &CLAY_LAYOUT_DEFAULT : _LayoutConfigArray_Add(&GetCurrentContext().layoutConfigs, config))
}

// clay.h:1324 — Clay__StoreTextElementConfig
_StoreTextElementConfig :: proc "c" (config: TextElementConfig) -> ^TextElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &TextElementConfig_DEFAULT : _TextElementConfigArray_Add(&GetCurrentContext().textElementConfigs, config))
}

// clay.h:1325 — Clay__StoreAspectRatioElementConfig
@(private)
_StoreAspectRatioElementConfig :: proc "c" (config: AspectRatioElementConfig) -> ^AspectRatioElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &AspectRatioElementConfig_DEFAULT : _AspectRatioElementConfigArray_Add(&GetCurrentContext().aspectRatioElementConfigs, config))
}

// clay.h:1326 — Clay__StoreImageElementConfig
@(private)
_StoreImageElementConfig :: proc "c" (config: ImageElementConfig) -> ^ImageElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &ImageElementConfig_DEFAULT : _ImageElementConfigArray_Add(&GetCurrentContext().imageElementConfigs, config))
}

// clay.h:1327 — Clay__StoreFloatingElementConfig
@(private)
_StoreFloatingElementConfig :: proc "c" (config: FloatingElementConfig) -> ^FloatingElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &FloatingElementConfig_DEFAULT : _FloatingElementConfigArray_Add(&GetCurrentContext().floatingElementConfigs, config))
}

// clay.h:1328 — Clay__StoreCustomElementConfig
@(private)
_StoreCustomElementConfig :: proc "c" (config: CustomElementConfig) -> ^CustomElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &CustomElementConfig_DEFAULT : _CustomElementConfigArray_Add(&GetCurrentContext().customElementConfigs, config))
}

// clay.h:1329 — Clay__StoreClipElementConfig
@(private)
_StoreClipElementConfig :: proc "c" (config: ClipElementConfig) -> ^ClipElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &ClipElementConfig_DEFAULT : _ClipElementConfigArray_Add(&GetCurrentContext().clipElementConfigs, config))
}

// clay.h:1330 — Clay__StoreBorderElementConfig
@(private)
_StoreBorderElementConfig :: proc "c" (config: BorderElementConfig) -> ^BorderElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &BorderElementConfig_DEFAULT : _BorderElementConfigArray_Add(&GetCurrentContext().borderElementConfigs, config))
}

// clay.h:1331 — Clay__StoreSharedElementConfig
@(private)
_StoreSharedElementConfig :: proc "c" (config: SharedElementConfig) -> ^SharedElementConfig {
	return ((cast(i32)(GetCurrentContext().booleanWarnings.maxElementsExceeded) != 0) ? &SharedElementConfig_DEFAULT : _SharedElementConfigArray_Add(&GetCurrentContext().sharedElementConfigs, config))
}

// clay.h:1333 — Clay__AttachElementConfig
@(private)
_AttachElementConfig :: proc "c" (config: ElementConfigUnion, kind: _ElementConfigType) -> ElementConfig {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return ElementConfig{type = cast(_ElementConfigType)(0)}
	}
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	openLayoutElement.elementConfigs.length += 1
	return (_ElementConfigArray_Add(&ctx.elementConfigs, ElementConfig{type = kind, config = config}))^
}

// clay.h:1343 — Clay__FindElementConfigWithType
@(private)
_FindElementConfigWithType :: proc "c" (element: ^LayoutElement, kind: _ElementConfigType) -> ElementConfigUnion {
	for i: i32 = 0; (i < element.elementConfigs.length); i += 1 {
		config: ^ElementConfig = _ElementConfigArraySlice_Get(&element.elementConfigs, i)
		if (cast(i32)(config.type) == cast(i32)(kind)) {
			return config.config
		}
	}
	return ElementConfigUnion{textElementConfig = nil}
}

// clay.h:1353 — Clay__HashNumber
@(private)
_HashNumber :: proc "c" (offset: u32, seed: u32) -> ElementId {
	hash: u32 = seed
	hash += (offset + cast(u32)(48))
	hash += (hash << 10)
	hash ~= (hash >> 6)
	hash += (hash << 3)
	hash ~= (hash >> 11)
	hash += (hash << 15)
	return ElementId{id = (hash + cast(u32)(1)), offset = offset, baseId = seed, stringId = CLAY__STRING_DEFAULT}
}

// clay.h:1365 — Clay__HashString
_HashString :: proc "c" (key: String, offset: u32, seed: u32) -> ElementId {
	hash: u32 = cast(u32)(0)
	base: u32 = seed
	for i: i32 = 0; (i < key.length); i += 1 {
		base += u32(i8(key.chars[i]))
		base += (base << 10)
		base ~= (base >> 6)
	}
	hash = base
	hash += offset
	hash += (hash << 10)
	hash ~= (hash >> 6)
	hash += (hash << 3)
	base += (base << 3)
	hash ~= (hash >> 11)
	base ~= (base >> 11)
	hash += (hash << 15)
	base += (base << 15)
	return ElementId{id = (hash + cast(u32)(1)), offset = offset, baseId = (base + cast(u32)(1)), stringId = key}
}

// clay.h:1496 — Clay__HashData
@(private)
_HashData :: proc "c" (data: [^]u8, length: uint) -> u64 {
	hash: u64 = cast(u64)(0)
	for i: uint = cast(uint)(0); (i < length); i += 1 {
		hash += cast(u64)(data[i])
		hash += (hash << 10)
		hash ~= (hash >> 6)
	}
	return hash
}

// clay.h:1508 — Clay__HashStringContentsWithConfig
@(private)
_HashStringContentsWithConfig :: proc "c" (text: ^String, config: ^TextElementConfig) -> u32 {
	hash: u32 = cast(u32)(0)
	if text.isStaticallyAllocated {
		hash += cast(u32)(uintptr(text.chars))
		hash += (hash << 10)
		hash ~= (hash >> 6)
		hash += cast(u32)(text.length)
		hash += (hash << 10)
		hash ~= (hash >> 6)
	} else {
		hash = cast(u32)((_HashData(text.chars, cast(uint)(text.length)) % cast(u64)(4294967295)))
	}
	hash += cast(u32)(config.fontId)
	hash += (hash << 10)
	hash ~= (hash >> 6)
	hash += cast(u32)(config.fontSize)
	hash += (hash << 10)
	hash ~= (hash >> 6)
	hash += cast(u32)(config.letterSpacing)
	hash += (hash << 10)
	hash ~= (hash >> 6)
	hash += (hash << 3)
	hash ~= (hash >> 11)
	hash += (hash << 15)
	return (hash + cast(u32)(1))
}

// clay.h:1539 — Clay__AddMeasuredWord
@(private)
_AddMeasuredWord :: proc "c" (word: _MeasuredWord, previousWord: ^_MeasuredWord) -> ^_MeasuredWord {
	ctx: ^Context = GetCurrentContext()
	if (ctx.measuredWordsFreeList.length > 0) {
		newItemIndex: u32 = cast(u32)(_int32_tArray_GetValue(&ctx.measuredWordsFreeList, (ctx.measuredWordsFreeList.length - 1)))
		ctx.measuredWordsFreeList.length -= 1
		_MeasuredWordArray_Set(&ctx.measuredWords, cast(i32)(newItemIndex), word)
		previousWord.next = cast(i32)(newItemIndex)
		return _MeasuredWordArray_Get(&ctx.measuredWords, cast(i32)(newItemIndex))
	} else {
		previousWord.next = ctx.measuredWords.length
		return _MeasuredWordArray_Add(&ctx.measuredWords, word)
	}
}

// clay.h:1553 — Clay__MeasureTextCached
@(private)
_MeasureTextCached :: proc "c" (text: ^String, config: ^TextElementConfig) -> ^_MeasureTextCacheItem {
	ctx: ^Context = GetCurrentContext()
	if !((_MeasureText != nil)) {
		if !(ctx.booleanWarnings.textMeasurementFunctionNotSet) {
			ctx.booleanWarnings.textMeasurementFunctionNotSet = true
			ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_TEXT_MEASUREMENT_FUNCTION_NOT_PROVIDED), errorText = _static_string("Clay's internal MeasureText function is null. You may have forgotten to call Clay_SetMeasureTextFunction(), or passed a NULL function pointer by mistake."), userData = ctx.errorHandler.userData})
		}
		return &_MeasureTextCacheItem_DEFAULT
	}
	id: u32 = _HashStringContentsWithConfig(text, config)
	hashBucket: u32 = (id % cast(u32)((ctx.maxMeasureTextCacheWordCount / 32)))
	elementIndexPrevious: i32 = 0
	elementIndex: i32 = ctx.measureTextHashMap.internalArray[hashBucket]
	for (elementIndex != 0) {
		hashEntry: ^_MeasureTextCacheItem = _MeasureTextCacheItemArray_Get(&ctx.measureTextHashMapInternal, elementIndex)
		if (hashEntry.id == id) {
			hashEntry.generation = ctx.generation
			return hashEntry
		}
		// This element hasn't been seen in a few frames, delete the hash map item
		if ((ctx.generation - hashEntry.generation) > cast(u32)(2)) {
			// Add all the measured words that were included in this measurement to the freelist
			nextWordIndex: i32 = hashEntry.measuredWordsStartIndex
			for (nextWordIndex != -(1)) {
				measuredWord: ^_MeasuredWord = _MeasuredWordArray_Get(&ctx.measuredWords, nextWordIndex)
				_int32_tArray_Add(&ctx.measuredWordsFreeList, nextWordIndex)
				nextWordIndex = measuredWord.next
			}
			nextIndex: i32 = hashEntry.nextIndex
			_MeasureTextCacheItemArray_Set(&ctx.measureTextHashMapInternal, elementIndex, _MeasureTextCacheItem{measuredWordsStartIndex = -(1)})
			_int32_tArray_Add(&ctx.measureTextHashMapInternalFreeList, elementIndex)
			if (elementIndexPrevious == 0) {
				ctx.measureTextHashMap.internalArray[hashBucket] = nextIndex
			} else {
				previousHashEntry: ^_MeasureTextCacheItem = _MeasureTextCacheItemArray_Get(&ctx.measureTextHashMapInternal, elementIndexPrevious)
				previousHashEntry.nextIndex = nextIndex
			}
			elementIndex = nextIndex
		} else {
			elementIndexPrevious = elementIndex
			elementIndex = hashEntry.nextIndex
		}
	}
	newItemIndex: i32 = 0
	newCacheItem: _MeasureTextCacheItem = _MeasureTextCacheItem{measuredWordsStartIndex = -(1), id = id, generation = ctx.generation}
	measured: ^_MeasureTextCacheItem = nil
	if (ctx.measureTextHashMapInternalFreeList.length > 0) {
		newItemIndex = _int32_tArray_GetValue(&ctx.measureTextHashMapInternalFreeList, (ctx.measureTextHashMapInternalFreeList.length - 1))
		ctx.measureTextHashMapInternalFreeList.length -= 1
		_MeasureTextCacheItemArray_Set(&ctx.measureTextHashMapInternal, newItemIndex, newCacheItem)
		measured = _MeasureTextCacheItemArray_Get(&ctx.measureTextHashMapInternal, newItemIndex)
	} else {
		if (ctx.measureTextHashMapInternal.length == (ctx.measureTextHashMapInternal.capacity - 1)) {
			if !(ctx.booleanWarnings.maxTextMeasureCacheExceeded) {
				ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_ELEMENTS_CAPACITY_EXCEEDED), errorText = _static_string("Clay ran out of capacity while attempting to measure text elements. Try using Clay_SetMaxElementCount() with a higher value."), userData = ctx.errorHandler.userData})
				ctx.booleanWarnings.maxTextMeasureCacheExceeded = true
			}
			return &_MeasureTextCacheItem_DEFAULT
		}
		measured = _MeasureTextCacheItemArray_Add(&ctx.measureTextHashMapInternal, newCacheItem)
		newItemIndex = (ctx.measureTextHashMapInternal.length - 1)
	}
	start: i32 = 0
	end: i32 = 0
	lineWidth: f32 = cast(f32)(0)
	measuredWidth: f32 = cast(f32)(0)
	measuredHeight: f32 = cast(f32)(0)
	spaceWidth: f32 = _MeasureText(StringSlice{length = 1, chars = CLAY__SPACECHAR.chars, baseChars = CLAY__SPACECHAR.chars}, config, ctx.measureTextUserData).width
	tempWord: _MeasuredWord = _MeasuredWord{next = -(1)}
	previousWord: ^_MeasuredWord = &tempWord
	for (end < text.length) {
		if (ctx.measuredWords.length == (ctx.measuredWords.capacity - 1)) {
			if !(ctx.booleanWarnings.maxTextMeasureCacheExceeded) {
				ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_TEXT_MEASUREMENT_CAPACITY_EXCEEDED), errorText = _static_string("Clay has run out of space in it's internal text measurement cache. Try using Clay_SetMaxMeasureTextCacheWordCount() (default 16384, with 1 unit storing 1 measured word)."), userData = ctx.errorHandler.userData})
				ctx.booleanWarnings.maxTextMeasureCacheExceeded = true
			}
			return &_MeasureTextCacheItem_DEFAULT
		}
		current: u8 = text.chars[end]
		if ((cast(i32)(current) == 32) || (cast(i32)(current) == 10)) {
			length: i32 = (end - start)
			dimensions: Dimensions = _MeasureText(StringSlice{length = length, chars = &text.chars[start], baseChars = text.chars}, config, ctx.measureTextUserData)
			measured.minWidth = _max(dimensions.width, measured.minWidth)
			measuredHeight = _max(measuredHeight, dimensions.height)
			if (cast(i32)(current) == 32) {
				dimensions.width += spaceWidth
				previousWord = _AddMeasuredWord(_MeasuredWord{startOffset = start, length = (length + 1), width = dimensions.width, next = -(1)}, previousWord)
				lineWidth += dimensions.width
			}
			if (cast(i32)(current) == 10) {
				if (length > 0) {
					previousWord = _AddMeasuredWord(_MeasuredWord{startOffset = start, length = length, width = dimensions.width, next = -(1)}, previousWord)
				}
				previousWord = _AddMeasuredWord(_MeasuredWord{startOffset = (end + 1), length = 0, width = cast(f32)(0), next = -(1)}, previousWord)
				lineWidth += dimensions.width
				measuredWidth = _max(lineWidth, measuredWidth)
				measured.containsNewlines = true
				lineWidth = cast(f32)(0)
			}
			start = (end + 1)
		}
		end += 1
	}
	if ((end - start) > 0) {
		dimensions: Dimensions = _MeasureText(StringSlice{length = (end - start), chars = &text.chars[start], baseChars = text.chars}, config, ctx.measureTextUserData)
		_AddMeasuredWord(_MeasuredWord{startOffset = start, length = (end - start), width = dimensions.width, next = -(1)}, previousWord)
		lineWidth += dimensions.width
		measuredHeight = _max(measuredHeight, dimensions.height)
		measured.minWidth = _max(dimensions.width, measured.minWidth)
	}
	measuredWidth = (_max(lineWidth, measuredWidth) - cast(f32)(cast(i32)(config.letterSpacing)))
	measured.measuredWordsStartIndex = tempWord.next
	measured.unwrappedDimensions.width = measuredWidth
	measured.unwrappedDimensions.height = measuredHeight
	if (elementIndexPrevious != 0) {
		_MeasureTextCacheItemArray_Get(&ctx.measureTextHashMapInternal, elementIndexPrevious).nextIndex = newItemIndex
	} else {
		ctx.measureTextHashMap.internalArray[hashBucket] = newItemIndex
	}
	return measured
}

// clay.h:1691 — Clay__PointIsInsideRect
@(private)
_PointIsInsideRect :: proc "c" (point: Vector2, rect: BoundingBox) -> bool {
	return (((((point)[0] >= rect.x) && ((point)[0] <= (rect.x + rect.width))) && ((point)[1] >= rect.y)) && ((point)[1] <= (rect.y + rect.height)))
}

// clay.h:1695 — Clay__AddHashMapItem
@(private)
_AddHashMapItem :: proc "c" (elementId: ElementId, layoutElement: ^LayoutElement, idAlias: u32) -> ^LayoutElementHashMapItem {
	ctx: ^Context = GetCurrentContext()
	if (ctx.layoutElementsHashMapInternal.length == (ctx.layoutElementsHashMapInternal.capacity - 1)) {
		return nil
	}
	item: LayoutElementHashMapItem = LayoutElementHashMapItem{elementId = elementId, layoutElement = layoutElement, nextIndex = -(1), generation = (ctx.generation + cast(u32)(1)), idAlias = idAlias}
	hashBucket: u32 = (elementId.id % cast(u32)(ctx.layoutElementsHashMap.capacity))
	hashItemPrevious: i32 = -(1)
	hashItemIndex: i32 = ctx.layoutElementsHashMap.internalArray[hashBucket]
	for (hashItemIndex != -(1)) {
		hashItem: ^LayoutElementHashMapItem = _LayoutElementHashMapItemArray_Get(&ctx.layoutElementsHashMapInternal, hashItemIndex)
		if (hashItem.elementId.id == elementId.id) {
			item.nextIndex = hashItem.nextIndex
			if (hashItem.generation <= ctx.generation) {
				hashItem.elementId = elementId
				hashItem.idAlias = idAlias
				hashItem.generation = (ctx.generation + cast(u32)(1))
				hashItem.layoutElement = layoutElement
				hashItem.debugData.collision = false
				hashItem.onHoverFunction = nil
				hashItem.hoverFunctionUserData = nil
			} else {
				ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_DUPLICATE_ID), errorText = _static_string("An element with this ID was already previously declared during this layout."), userData = ctx.errorHandler.userData})
				if ctx.debugModeEnabled {
					hashItem.debugData.collision = true
				}
			}
			return hashItem
		}
		hashItemPrevious = hashItemIndex
		hashItemIndex = hashItem.nextIndex
	}
	hashItem: ^LayoutElementHashMapItem = _LayoutElementHashMapItemArray_Add(&ctx.layoutElementsHashMapInternal, item)
	hashItem.debugData = _DebugElementDataArray_Add(&ctx.debugElementData, _DebugElementData{collision = false})
	if (hashItemPrevious != -(1)) {
		_LayoutElementHashMapItemArray_Get(&ctx.layoutElementsHashMapInternal, hashItemPrevious).nextIndex = (ctx.layoutElementsHashMapInternal.length - 1)
	} else {
		ctx.layoutElementsHashMap.internalArray[hashBucket] = (ctx.layoutElementsHashMapInternal.length - 1)
	}
	return hashItem
}

// clay.h:1740 — Clay__GetHashMapItem
@(private)
_GetHashMapItem :: proc "c" (id: u32) -> ^LayoutElementHashMapItem {
	ctx: ^Context = GetCurrentContext()
	hashBucket: u32 = (id % cast(u32)(ctx.layoutElementsHashMap.capacity))
	elementIndex: i32 = ctx.layoutElementsHashMap.internalArray[hashBucket]
	for (elementIndex != -(1)) {
		hashEntry: ^LayoutElementHashMapItem = _LayoutElementHashMapItemArray_Get(&ctx.layoutElementsHashMapInternal, elementIndex)
		if (hashEntry.elementId.id == id) {
			return hashEntry
		}
		elementIndex = hashEntry.nextIndex
	}
	return &LayoutElementHashMapItem_DEFAULT
}

// clay.h:1754 — Clay__GenerateIdForAnonymousElement
@(private)
_GenerateIdForAnonymousElement :: proc "c" (openLayoutElement: ^LayoutElement) -> ElementId {
	ctx: ^Context = GetCurrentContext()
	parentElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 2)))
	elementId: ElementId = _HashNumber(cast(u32)(parentElement.childrenOrTextContent.children.length), parentElement.id)
	openLayoutElement.id = elementId.id
	_AddHashMapItem(elementId, openLayoutElement, cast(u32)(0))
	_StringArray_Add(&ctx.layoutElementIdStrings, elementId.stringId)
	return elementId
}

// clay.h:1764 — Clay__ElementHasConfig
@(private)
_ElementHasConfig :: proc "c" (layoutElement: ^LayoutElement, kind: _ElementConfigType) -> bool {
	for i: i32 = 0; (i < layoutElement.elementConfigs.length); i += 1 {
		if (cast(i32)(_ElementConfigArraySlice_Get(&layoutElement.elementConfigs, i).type) == cast(i32)(kind)) {
			return true
		}
	}
	return false
}

// clay.h:1773 — Clay__UpdateAspectRatioBox
@(private)
_UpdateAspectRatioBox :: proc "c" (layoutElement: ^LayoutElement) {
	for j: i32 = 0; (j < layoutElement.elementConfigs.length); j += 1 {
		config: ^ElementConfig = _ElementConfigArraySlice_Get(&layoutElement.elementConfigs, j)
		if (cast(i32)(config.type) == CLAY__ELEMENT_CONFIG_TYPE_ASPECT) {
			aspectConfig: ^AspectRatioElementConfig = config.config.aspectRatioElementConfig
			if (aspectConfig.aspectRatio == cast(f32)(0)) {
				break
			}
			if ((layoutElement.dimensions.width == cast(f32)(0)) && (layoutElement.dimensions.height != cast(f32)(0))) {
				layoutElement.dimensions.width = (layoutElement.dimensions.height * aspectConfig.aspectRatio)
			} else {
				if ((layoutElement.dimensions.width != cast(f32)(0)) && (layoutElement.dimensions.height == cast(f32)(0))) {
					layoutElement.dimensions.height = (layoutElement.dimensions.width * (cast(f32)(1) / aspectConfig.aspectRatio))
				}
			}
			break
		}
	}
}

@(private)
CLAY__EPSILON: f32 = cast(f32)(0.01)

@(private)
CLAY__DEBUGVIEW_COLOR_1: Color = Color{cast(f32)(58), cast(f32)(56), cast(f32)(52), cast(f32)(255)}

@(private)
CLAY__DEBUGVIEW_COLOR_2: Color = Color{cast(f32)(62), cast(f32)(60), cast(f32)(58), cast(f32)(255)}

@(private)
CLAY__DEBUGVIEW_COLOR_3: Color = Color{cast(f32)(141), cast(f32)(133), cast(f32)(135), cast(f32)(255)}

@(private)
CLAY__DEBUGVIEW_COLOR_4: Color = Color{cast(f32)(238), cast(f32)(226), cast(f32)(231), cast(f32)(255)}

@(private)
CLAY__DEBUGVIEW_COLOR_SELECTED_ROW: Color = Color{cast(f32)(102), cast(f32)(80), cast(f32)(78), cast(f32)(255)}

@(private)
CLAY__DEBUGVIEW_ROW_HEIGHT: i32 = 30

@(private)
CLAY__DEBUGVIEW_OUTER_PADDING: i32 = 10

@(private)
CLAY__DEBUGVIEW_INDENT_WIDTH: i32 = 16

@(private)
_DebugView_TextNameConfig: TextElementConfig = TextElementConfig{textColor = Color{cast(f32)(238), cast(f32)(226), cast(f32)(231), cast(f32)(255)}, fontSize = cast(u16)(16), wrapMode = cast(TextWrapMode)(CLAY_TEXT_WRAP_NONE)}

@(private)
_DebugView_ScrollViewItemLayoutConfig: LayoutConfig = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}}}}

@(private)
_debugViewWidth: u32 = cast(u32)(400)

@(private)
_debugViewHighlightColor: Color = Color{cast(f32)(168), cast(f32)(66), cast(f32)(28), cast(f32)(100)}

// clay.h:3792 — Clay__WarningArray_Allocate_Arena
@(private)
_WarningArray_Allocate_Arena :: proc "c" (capacity: i32, arena: ^Arena) -> _WarningArray {
	totalSizeBytes: uint = cast(uint)((cast(u64)(capacity) * size_of(String)))
	array: _WarningArray = _WarningArray{capacity = capacity, length = 0}
	nextAllocOffset: uintptr = (arena.nextAllocation + (cast(uintptr)(64) - (arena.nextAllocation % cast(uintptr)(64))))
	if ((nextAllocOffset + cast(uintptr)(totalSizeBytes)) <= cast(uintptr)(arena.capacity)) {
		array.internalArray = cast([^]_Warning)(cast(^_Warning)(uintptr((uintptr(arena.memory) + nextAllocOffset))))
		arena.nextAllocation = (nextAllocOffset + cast(uintptr)(totalSizeBytes))
	} else {
		_currentContext.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_ARENA_CAPACITY_EXCEEDED), errorText = _static_string("Clay attempted to allocate memory in its arena, but ran out of capacity. Try increasing the capacity of the arena passed to Clay_Initialize()"), userData = _currentContext.errorHandler.userData})
	}
	return array
}

// clay.h:3809 — Clay__WarningArray_Add
@(private)
_WarningArray_Add :: proc "c" (array: ^_WarningArray, item: _Warning) -> ^_Warning {
	if (array.length < array.capacity) {
		array.internalArray[_post_inc(&(array.length), 1)] = item
		return &array.internalArray[(array.length - 1)]
	}
	return &CLAY__WARNING_DEFAULT
}

// clay.h:3818 — Clay__Array_Allocate_Arena
@(private)
_Array_Allocate_Arena :: proc "c" (capacity: i32, itemSize: u32, arena: ^Arena) -> rawptr {
	totalSizeBytes: uint = cast(uint)((cast(u32)(capacity) * itemSize))
	nextAllocOffset: uintptr = (arena.nextAllocation + (cast(uintptr)(64) - (arena.nextAllocation % cast(uintptr)(64))))
	if ((nextAllocOffset + cast(uintptr)(totalSizeBytes)) <= cast(uintptr)(arena.capacity)) {
		arena.nextAllocation = (nextAllocOffset + cast(uintptr)(totalSizeBytes))
		return cast(rawptr)(uintptr((uintptr(arena.memory) + nextAllocOffset)))
	} else {
		_currentContext.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_ARENA_CAPACITY_EXCEEDED), errorText = _static_string("Clay attempted to allocate memory in its arena, but ran out of capacity. Try increasing the capacity of the arena passed to Clay_Initialize()"), userData = _currentContext.errorHandler.userData})
	}
	return nil
}

// clay.h:3835 — Clay__Array_RangeCheck
@(private)
_Array_RangeCheck :: proc "c" (index: i32, length: i32) -> bool {
	if ((index < length) && (index >= 0)) {
		return true
	}
	ctx: ^Context = GetCurrentContext()
	ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_INTERNAL_ERROR), errorText = _static_string("Clay attempted to make an out of bounds array access. This is an internal error and is likely a bug."), userData = ctx.errorHandler.userData})
	return false
}

// clay.h:3848 — Clay__Array_AddCapacityCheck
@(private)
_Array_AddCapacityCheck :: proc "c" (length: i32, capacity: i32) -> bool {
	if (length < capacity) {
		return true
	}
	ctx: ^Context = GetCurrentContext()
	ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_INTERNAL_ERROR), errorText = _static_string("Clay attempted to make an out of bounds array access. This is an internal error and is likely a bug."), userData = ctx.errorHandler.userData})
	return false
}
