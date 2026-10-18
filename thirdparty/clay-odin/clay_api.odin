// Pure Odin port of Clay v0.14 (b25a31c1a152915cd7dd6796e6592273e5a10aac).
// Copyright (c) 2024 Nic Barker. Altered source; see LICENSE.md and README.md.
package clay

// clay.h:3864 — Clay_MinMemorySize
MinMemorySize :: proc "c" () -> u32 {
	fakeContext: Context = Context{maxElementCount = _defaultMaxElementCount, maxMeasureTextCacheWordCount = _defaultMaxMeasureTextWordCacheCount, internalArena = Arena{capacity = ~uint(0), memory = nil}}
	currentContext: ^Context = GetCurrentContext()
	if (currentContext != nil) {
		fakeContext.maxElementCount = currentContext.maxElementCount
		fakeContext.maxMeasureTextCacheWordCount = currentContext.maxMeasureTextCacheWordCount
	}
	// Reserve space in the arena for the context, important for calculating min memory size correctly
	_Context_Allocate_Arena(&fakeContext.internalArena)
	_InitializePersistentMemory(&fakeContext)
	_InitializeEphemeralMemory(&fakeContext)
	return (cast(u32)(fakeContext.internalArena.nextAllocation) + cast(u32)(128))
}

// clay.h:3886 — Clay_CreateArenaWithCapacityAndMemory
CreateArenaWithCapacityAndMemory :: proc "c" (capacity: uint, offset: [^]u8) -> Arena {
	arena: Arena = Arena{capacity = capacity, memory = offset}
	return arena
}

// clay.h:3895 — Clay_SetMeasureTextFunction
SetMeasureTextFunction :: proc "c" (measureTextFunction: proc "c" (StringSlice, ^TextElementConfig, rawptr) -> Dimensions, userData: rawptr) {
	ctx: ^Context = GetCurrentContext()
	_MeasureText = measureTextFunction
	ctx.measureTextUserData = userData
}

// clay.h:3900 — Clay_SetQueryScrollOffsetFunction
SetQueryScrollOffsetFunction :: proc "c" (queryScrollOffsetFunction: proc "c" (u32, rawptr) -> Vector2, userData: rawptr) {
	ctx: ^Context = GetCurrentContext()
	_QueryScrollOffset = queryScrollOffsetFunction
	ctx.queryScrollOffsetUserData = userData
}

// clay.h:3908 — Clay_SetLayoutDimensions
SetLayoutDimensions :: proc "c" (dimensions: Dimensions) {
	GetCurrentContext().layoutDimensions = dimensions
}

// clay.h:3913 — Clay_SetPointerState
SetPointerState :: proc "c" (position: Vector2, pointerDown: bool) {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return
	}
	ctx.pointerInfo.position = position
	ctx.pointerOverIds.length = 0
	dfsBuffer: _int32_tArray = ctx.layoutElementChildrenBuffer
	for rootIndex: i32 = (ctx.layoutElementTreeRoots.length - 1); (rootIndex >= 0); rootIndex -= 1 {
		dfsBuffer.length = 0
		root: ^_LayoutElementTreeRoot = _LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, rootIndex)
		_int32_tArray_Add(&dfsBuffer, root.layoutElementIndex)
		ctx.treeNodeVisited.internalArray[0] = false
		found: bool = false
		for (dfsBuffer.length > 0) {
			if ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] {
				dfsBuffer.length -= 1
				continue
			}
			ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] = true
			currentElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&dfsBuffer, (dfsBuffer.length - 1)))
			mapItem: ^LayoutElementHashMapItem = _GetHashMapItem(currentElement.id)
			clipElementId: i32 = _int32_tArray_GetValue(&ctx.layoutElementClipElementIds, cast(i32)((cast(i64)(uintptr(currentElement) - uintptr(ctx.layoutElements.internalArray)) / size_of(LayoutElement))))
			clipItem: ^LayoutElementHashMapItem = _GetHashMapItem(cast(u32)(clipElementId))
			if (mapItem != nil) {
				elementBox: BoundingBox = mapItem.boundingBox
				elementBox.x -= (root.pointerOffset)[0]
				elementBox.y -= (root.pointerOffset)[1]
				if ((cast(i32)(_BackendPointInside(currentElement.id, position, elementBox, false)) != 0) && ((clipElementId == 0) || (cast(i32)(_BackendPointInside(cast(u32)(clipElementId), position, clipItem.boundingBox, true)) != 0))) {
					if (mapItem.onHoverFunction != nil) {
						mapItem.onHoverFunction(mapItem.elementId, ctx.pointerInfo, mapItem.hoverFunctionUserData)
					}
					ElementIdArray_Add(&ctx.pointerOverIds, mapItem.elementId)
					found = true
					if (mapItem.idAlias != cast(u32)(0)) {
						ElementIdArray_Add(&ctx.pointerOverIds, ElementId{id = mapItem.idAlias})
					}
				}
				if _ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT)) {
					dfsBuffer.length -= 1
					continue
				}
				for i: i32 = (cast(i32)(currentElement.childrenOrTextContent.children.length) - 1); (i >= 0); i -= 1 {
					_int32_tArray_Add(&dfsBuffer, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
					ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] = false
				}
			} else {
				dfsBuffer.length -= 1
			}
		}
		rootElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, root.layoutElementIndex)
		if (((cast(i32)(found) != 0) && (cast(i32)(_ElementHasConfig(rootElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING))) != 0)) && (cast(i32)(_FindElementConfigWithType(rootElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING)).floatingElementConfig.pointerCaptureMode) == CLAY_POINTER_CAPTURE_MODE_CAPTURE)) {
			break
		}
	}
	if pointerDown {
		if (cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
			ctx.pointerInfo.state = cast(PointerDataInteractionState)(CLAY_POINTER_DATA_PRESSED)
		} else {
			if (cast(i32)(ctx.pointerInfo.state) != CLAY_POINTER_DATA_PRESSED) {
				ctx.pointerInfo.state = cast(PointerDataInteractionState)(CLAY_POINTER_DATA_PRESSED_THIS_FRAME)
			}
		}
	} else {
		if (cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_RELEASED_THIS_FRAME) {
			ctx.pointerInfo.state = cast(PointerDataInteractionState)(CLAY_POINTER_DATA_RELEASED)
		} else {
			if (cast(i32)(ctx.pointerInfo.state) != CLAY_POINTER_DATA_RELEASED) {
				ctx.pointerInfo.state = cast(PointerDataInteractionState)(CLAY_POINTER_DATA_RELEASED_THIS_FRAME)
			}
		}
	}
}

// clay.h:3988 — Clay_Initialize
Initialize :: proc "c" (arena: Arena, layoutDimensions: Dimensions, errorHandler: ErrorHandler) -> ^Context {
	arena_copy := arena
	ctx: ^Context = _Context_Allocate_Arena(&arena_copy)
	if (ctx == cast(^Context)(nil)) {
		return nil
	}
	// DEFAULTS
	oldContext: ^Context = GetCurrentContext()
	(ctx)^ = Context{maxElementCount = ((oldContext != nil) ? oldContext.maxElementCount : _defaultMaxElementCount), maxMeasureTextCacheWordCount = ((oldContext != nil) ? oldContext.maxMeasureTextCacheWordCount : _defaultMaxMeasureTextWordCacheCount), errorHandler = ((errorHandler.handler != nil) ? errorHandler : ErrorHandler{handler = _ErrorHandlerFunctionDefault, userData = nil}), layoutDimensions = layoutDimensions, internalArena = arena_copy}
	SetCurrentContext(ctx)
	_InitializePersistentMemory(ctx)
	_InitializeEphemeralMemory(ctx)
	for i: i32 = 0; (i < ctx.layoutElementsHashMap.capacity); i += 1 {
		ctx.layoutElementsHashMap.internalArray[i] = -(1)
	}
	for i: i32 = 0; (i < ctx.measureTextHashMap.capacity); i += 1 {
		ctx.measureTextHashMap.internalArray[i] = 0
	}
	ctx.measureTextHashMapInternal.length = 1
	ctx.layoutDimensions = layoutDimensions
	return ctx
}

// clay.h:4015 — Clay_GetCurrentContext
GetCurrentContext :: proc "c" () -> ^Context {
	return _currentContext
}

// clay.h:4020 — Clay_SetCurrentContext
SetCurrentContext :: proc "c" (ctx: ^Context) {
	_currentContext = ctx
}

// clay.h:4025 — Clay_GetScrollOffset
GetScrollOffset :: proc "c" () -> Vector2 {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return Vector2{cast(f32)(0), 0}
	}
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	// If the element has no id attached at this point, we need to generate one
	if (openLayoutElement.id == cast(u32)(0)) {
		_GenerateIdForAnonymousElement(openLayoutElement)
	}
	for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
		mapping: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
		if (mapping.layoutElement == openLayoutElement) {
			return mapping.scrollPosition
		}
	}
	return Vector2{cast(f32)(0), 0}
}

// clay.h:4045 — Clay_UpdateScrollContainers
UpdateScrollContainers :: proc "c" (enableDragScrolling: bool, scrollDelta: Vector2, deltaTime: f32) {
	ctx: ^Context = GetCurrentContext()
	isPointerActive: bool = ((cast(i32)(enableDragScrolling) != 0) && ((cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_PRESSED) || (cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_PRESSED_THIS_FRAME)))
	// Don't apply scroll events to ancestors of the inner element
	highestPriorityElementIndex: i32 = -(1)
	highestPriorityScrollData: ^_ScrollContainerDataInternal = nil
	for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
		scrollData: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
		if !(scrollData.openThisFrame) {
			_ScrollContainerDataInternalArray_RemoveSwapback(&ctx.scrollContainerDatas, i)
			continue
		}
		scrollData.openThisFrame = false
		hashMapItem: ^LayoutElementHashMapItem = _GetHashMapItem(scrollData.elementId)
		// Element isn't rendered this frame but scroll offset has been retained
		if !((hashMapItem != nil)) {
			_ScrollContainerDataInternalArray_RemoveSwapback(&ctx.scrollContainerDatas, i)
			continue
		}
		// Touch / click is released
		if (!(isPointerActive) && (cast(i32)(scrollData.pointerScrollActive) != 0)) {
			xDiff: f32 = ((scrollData.scrollPosition)[0] - (scrollData.scrollOrigin)[0])
			if ((xDiff < cast(f32)(-(10))) || (xDiff > cast(f32)(10))) {
				(scrollData.scrollMomentum)[0] = (((scrollData.scrollPosition)[0] - (scrollData.scrollOrigin)[0]) / (scrollData.momentumTime * cast(f32)(25)))
			}
			yDiff: f32 = ((scrollData.scrollPosition)[1] - (scrollData.scrollOrigin)[1])
			if ((yDiff < cast(f32)(-(10))) || (yDiff > cast(f32)(10))) {
				(scrollData.scrollMomentum)[1] = (((scrollData.scrollPosition)[1] - (scrollData.scrollOrigin)[1]) / (scrollData.momentumTime * cast(f32)(25)))
			}
			scrollData.pointerScrollActive = false
			scrollData.pointerOrigin = Vector2{cast(f32)(0), cast(f32)(0)}
			scrollData.scrollOrigin = Vector2{cast(f32)(0), cast(f32)(0)}
			scrollData.momentumTime = cast(f32)(0)
		}
		// Apply existing momentum
		(scrollData.scrollPosition)[0] += (scrollData.scrollMomentum)[0]
		(scrollData.scrollMomentum)[0] *= 0.949999988
		scrollOccurred: bool = (((scrollDelta)[0] != cast(f32)(0)) || ((scrollDelta)[1] != cast(f32)(0)))
		if ((((scrollData.scrollMomentum)[0] > -(0.100000001)) && ((scrollData.scrollMomentum)[0] < 0.100000001)) || (cast(i32)(scrollOccurred) != 0)) {
			(scrollData.scrollMomentum)[0] = cast(f32)(0)
		}
		(scrollData.scrollPosition)[0] = _min(_max((scrollData.scrollPosition)[0], -(_max((scrollData.contentSize.width - scrollData.layoutElement.dimensions.width), cast(f32)(0)))), cast(f32)(0))
		(scrollData.scrollPosition)[1] += (scrollData.scrollMomentum)[1]
		(scrollData.scrollMomentum)[1] *= 0.949999988
		if ((((scrollData.scrollMomentum)[1] > -(0.100000001)) && ((scrollData.scrollMomentum)[1] < 0.100000001)) || (cast(i32)(scrollOccurred) != 0)) {
			(scrollData.scrollMomentum)[1] = cast(f32)(0)
		}
		(scrollData.scrollPosition)[1] = _min(_max((scrollData.scrollPosition)[1], -(_max((scrollData.contentSize.height - scrollData.layoutElement.dimensions.height), cast(f32)(0)))), cast(f32)(0))
		for j: i32 = 0; (j < ctx.pointerOverIds.length); j += 1 {
			if (scrollData.layoutElement.id == ElementIdArray_Get(&ctx.pointerOverIds, j).id) {
				highestPriorityElementIndex = j
				highestPriorityScrollData = scrollData
			}
		}
	}
	if ((highestPriorityElementIndex > -(1)) && (highestPriorityScrollData != nil)) {
		scrollElement: ^LayoutElement = highestPriorityScrollData.layoutElement
		clipConfig: ^ClipElementConfig = _FindElementConfigWithType(scrollElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
		canScrollVertically: bool = ((cast(i32)(clipConfig.vertical) != 0) && (highestPriorityScrollData.contentSize.height > scrollElement.dimensions.height))
		canScrollHorizontally: bool = ((cast(i32)(clipConfig.horizontal) != 0) && (highestPriorityScrollData.contentSize.width > scrollElement.dimensions.width))
		// Handle wheel scroll
		if canScrollVertically {
			(highestPriorityScrollData.scrollPosition)[1] = ((highestPriorityScrollData.scrollPosition)[1] + ((scrollDelta)[1] * cast(f32)(10)))
		}
		if canScrollHorizontally {
			(highestPriorityScrollData.scrollPosition)[0] = ((highestPriorityScrollData.scrollPosition)[0] + ((scrollDelta)[0] * cast(f32)(10)))
		}
		// Handle click / touch scroll
		if isPointerActive {
			highestPriorityScrollData.scrollMomentum = Vector2{cast(f32)(0), 0}
			if !(highestPriorityScrollData.pointerScrollActive) {
				highestPriorityScrollData.pointerOrigin = ctx.pointerInfo.position
				highestPriorityScrollData.scrollOrigin = highestPriorityScrollData.scrollPosition
				highestPriorityScrollData.pointerScrollActive = true
			} else {
				scrollDeltaX: f32 = cast(f32)(0)
				scrollDeltaY: f32 = cast(f32)(0)
				if canScrollHorizontally {
					oldXScrollPosition: f32 = (highestPriorityScrollData.scrollPosition)[0]
					(highestPriorityScrollData.scrollPosition)[0] = ((highestPriorityScrollData.scrollOrigin)[0] + ((ctx.pointerInfo.position)[0] - (highestPriorityScrollData.pointerOrigin)[0]))
					(highestPriorityScrollData.scrollPosition)[0] = _max(_min((highestPriorityScrollData.scrollPosition)[0], cast(f32)(0)), -((highestPriorityScrollData.contentSize.width - highestPriorityScrollData.boundingBox.width)))
					scrollDeltaX = ((highestPriorityScrollData.scrollPosition)[0] - oldXScrollPosition)
				}
				if canScrollVertically {
					oldYScrollPosition: f32 = (highestPriorityScrollData.scrollPosition)[1]
					(highestPriorityScrollData.scrollPosition)[1] = ((highestPriorityScrollData.scrollOrigin)[1] + ((ctx.pointerInfo.position)[1] - (highestPriorityScrollData.pointerOrigin)[1]))
					(highestPriorityScrollData.scrollPosition)[1] = _max(_min((highestPriorityScrollData.scrollPosition)[1], cast(f32)(0)), -((highestPriorityScrollData.contentSize.height - highestPriorityScrollData.boundingBox.height)))
					scrollDeltaY = ((highestPriorityScrollData.scrollPosition)[1] - oldYScrollPosition)
				}
				if (((((scrollDeltaX > -(0.100000001)) && (scrollDeltaX < 0.100000001)) && (scrollDeltaY > -(0.100000001))) && (scrollDeltaY < 0.100000001)) && (highestPriorityScrollData.momentumTime > 0.150000006)) {
					highestPriorityScrollData.momentumTime = cast(f32)(0)
					highestPriorityScrollData.pointerOrigin = ctx.pointerInfo.position
					highestPriorityScrollData.scrollOrigin = highestPriorityScrollData.scrollPosition
				} else {
					highestPriorityScrollData.momentumTime += deltaTime
				}
			}
		}
		// Clamp any changes to scroll position to the maximum size of the contents
		if canScrollVertically {
			(highestPriorityScrollData.scrollPosition)[1] = _max(_min((highestPriorityScrollData.scrollPosition)[1], cast(f32)(0)), -((highestPriorityScrollData.contentSize.height - scrollElement.dimensions.height)))
		}
		if canScrollHorizontally {
			(highestPriorityScrollData.scrollPosition)[0] = _max(_min((highestPriorityScrollData.scrollPosition)[0], cast(f32)(0)), -((highestPriorityScrollData.contentSize.width - scrollElement.dimensions.width)))
		}
	}
}

// clay.h:4159 — Clay_BeginLayout
BeginLayout :: proc "c" () {
	ctx: ^Context = GetCurrentContext()
	_InitializeEphemeralMemory(ctx)
	ctx.generation += 1
	ctx.dynamicElementIndex = cast(u32)(0)
	// Set up the root container that covers the entire window
	rootDimensions: Dimensions = Dimensions{width = ctx.layoutDimensions.width, height = ctx.layoutDimensions.height}
	if ctx.debugModeEnabled {
		rootDimensions.width -= cast(f32)(_debugViewWidth)
	}
	ctx.booleanWarnings = BooleanWarnings{maxElementsExceeded = false}
	_OpenElement()
	_ConfigureOpenElement(ElementDeclaration{id = _HashString(_static_string("Clay__RootContainer"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = rootDimensions.width, max = rootDimensions.width}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = rootDimensions.height, max = rootDimensions.height}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}})
	_int32_tArray_Add(&ctx.openLayoutElementStack, 0)
	_LayoutElementTreeRootArray_Add(&ctx.layoutElementTreeRoots, _LayoutElementTreeRoot{layoutElementIndex = 0})
}

// clay.h:4180 — Clay_EndLayout
EndLayout :: proc "c" () -> ClayArray(RenderCommand) {
	ctx: ^Context = GetCurrentContext()
	_CloseElement()
	elementsExceededBeforeDebugView: bool = ctx.booleanWarnings.maxElementsExceeded
	if ((cast(i32)(ctx.debugModeEnabled) != 0) && !(elementsExceededBeforeDebugView)) {
		ctx.warningsEnabled = false
		_RenderDebugView()
		ctx.warningsEnabled = true
	}
	if ctx.booleanWarnings.maxElementsExceeded {
		message: String
		if !(elementsExceededBeforeDebugView) {
			message = _static_string("Clay Error: Layout elements exceeded Clay__maxElementCount after adding the debug-view to the layout.")
		} else {
			message = _static_string("Clay Error: Layout elements exceeded Clay__maxElementCount")
		}
		_AddRenderCommand(RenderCommand{boundingBox = BoundingBox{x = ((ctx.layoutDimensions.width / cast(f32)(2)) - cast(f32)((59 * 4))), y = (ctx.layoutDimensions.height / cast(f32)(2)), width = cast(f32)(0), height = cast(f32)(0)}, renderData = RenderCommandData{text = TextRenderData{stringContents = StringSlice{length = message.length, chars = message.chars, baseChars = message.chars}, textColor = Color{cast(f32)(255), cast(f32)(0), cast(f32)(0), cast(f32)(255)}, fontSize = cast(u16)(16)}}, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_TEXT)})
	} else {
		_CalculateFinalLayout()
	}
	return ctx.renderCommands
}

// clay.h:4208 — Clay_GetElementId
GetElementId :: proc "c" (id: String) -> ElementId {
	return _HashString(id, cast(u32)(0), cast(u32)(0))
}

// clay.h:4213 — Clay_GetElementIdWithIndex
GetElementIdWithIndex :: proc "c" (id: String, index: u32) -> ElementId {
	return _HashString(id, index, cast(u32)(0))
}

// clay.h:4217 — Clay_Hovered
Hovered :: proc "c" () -> bool {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return false
	}
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	// If the element has no id attached at this point, we need to generate one
	if (openLayoutElement.id == cast(u32)(0)) {
		_GenerateIdForAnonymousElement(openLayoutElement)
	}
	for i: i32 = 0; (i < ctx.pointerOverIds.length); i += 1 {
		if (ElementIdArray_Get(&ctx.pointerOverIds, i).id == openLayoutElement.id) {
			return true
		}
	}
	return false
}

// clay.h:4235 — Clay_OnHover
OnHover :: proc "c" (onHoverFunction: proc "c" (ElementId, PointerData, rawptr), userData: rawptr) {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return
	}
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	if (openLayoutElement.id == cast(u32)(0)) {
		_GenerateIdForAnonymousElement(openLayoutElement)
	}
	hashMapItem: ^LayoutElementHashMapItem = _GetHashMapItem(openLayoutElement.id)
	hashMapItem.onHoverFunction = onHoverFunction
	hashMapItem.hoverFunctionUserData = userData
}

// clay.h:4250 — Clay_PointerOver
PointerOver :: proc "c" (id: ElementId) -> bool {
	ctx: ^Context = GetCurrentContext()
	for i: i32 = 0; (i < ctx.pointerOverIds.length); i += 1 {
		if (ElementIdArray_Get(&ctx.pointerOverIds, i).id == id.id) {
			return true
		}
	}
	return false
}

// clay.h:4261 — Clay_GetScrollContainerData
GetScrollContainerData :: proc "c" (id: ElementId) -> ScrollContainerData {
	ctx: ^Context = GetCurrentContext()
	for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
		scrollContainerData: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
		if (scrollContainerData.elementId == id.id) {
			clipElementConfig: ^ClipElementConfig = _FindElementConfigWithType(scrollContainerData.layoutElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
			if !((clipElementConfig != nil)) {
				return ScrollContainerData{scrollPosition = nil}
			}
			return ScrollContainerData{scrollPosition = &scrollContainerData.scrollPosition, scrollContainerDimensions = Dimensions{width = scrollContainerData.boundingBox.width, height = scrollContainerData.boundingBox.height}, contentDimensions = scrollContainerData.contentSize, config = (clipElementConfig)^, found = true}
		}
	}
	return ScrollContainerData{scrollPosition = nil}
}

// clay.h:4283 — Clay_GetElementData
GetElementData :: proc "c" (id: ElementId) -> ElementData {
	item: ^LayoutElementHashMapItem = _GetHashMapItem(id.id)
	if (item == &LayoutElementHashMapItem_DEFAULT) {
		return ElementData{boundingBox = BoundingBox{x = cast(f32)(0)}}
	}
	return ElementData{boundingBox = item.boundingBox, found = true}
}

// clay.h:4296 — Clay_SetDebugModeEnabled
SetDebugModeEnabled :: proc "c" (enabled: bool) {
	ctx: ^Context = GetCurrentContext()
	ctx.debugModeEnabled = enabled
}

// clay.h:4302 — Clay_IsDebugModeEnabled
IsDebugModeEnabled :: proc "c" () -> bool {
	ctx: ^Context = GetCurrentContext()
	return ctx.debugModeEnabled
}

// clay.h:4308 — Clay_SetCullingEnabled
SetCullingEnabled :: proc "c" (enabled: bool) {
	ctx: ^Context = GetCurrentContext()
	ctx.disableCulling = !(enabled)
}

// clay.h:4314 — Clay_SetExternalScrollHandlingEnabled
SetExternalScrollHandlingEnabled :: proc "c" (enabled: bool) {
	ctx: ^Context = GetCurrentContext()
	ctx.externalScrollHandlingEnabled = enabled
}

// clay.h:4320 — Clay_GetMaxElementCount
GetMaxElementCount :: proc "c" () -> i32 {
	ctx: ^Context = GetCurrentContext()
	return ctx.maxElementCount
}

// clay.h:4326 — Clay_SetMaxElementCount
SetMaxElementCount :: proc "c" (maxElementCount: i32) {
	ctx: ^Context = GetCurrentContext()
	if (ctx != nil) {
		ctx.maxElementCount = maxElementCount
	} else {
		_defaultMaxElementCount = maxElementCount
		_defaultMaxMeasureTextWordCacheCount = (maxElementCount * 2)
	}
}

// clay.h:4337 — Clay_GetMaxMeasureTextCacheWordCount
GetMaxMeasureTextCacheWordCount :: proc "c" () -> i32 {
	ctx: ^Context = GetCurrentContext()
	return ctx.maxMeasureTextCacheWordCount
}

// clay.h:4343 — Clay_SetMaxMeasureTextCacheWordCount
SetMaxMeasureTextCacheWordCount :: proc "c" (maxMeasureTextCacheWordCount: i32) {
	ctx: ^Context = GetCurrentContext()
	if (ctx != nil) {
		_currentContext.maxMeasureTextCacheWordCount = maxMeasureTextCacheWordCount
	} else {
		_defaultMaxMeasureTextWordCacheCount = maxMeasureTextCacheWordCount
	}
}

// clay.h:4353 — Clay_ResetMeasureTextCache
ResetMeasureTextCache :: proc "c" () {
	ctx: ^Context = GetCurrentContext()
	ctx.measureTextHashMapInternal.length = 0
	ctx.measureTextHashMapInternalFreeList.length = 0
	ctx.measureTextHashMap.length = 0
	ctx.measuredWords.length = 0
	ctx.measuredWordsFreeList.length = 0
	for i: i32 = 0; (i < ctx.measureTextHashMap.capacity); i += 1 {
		ctx.measureTextHashMap.internalArray[i] = 0
	}
	ctx.measureTextHashMapInternal.length = 1
}
