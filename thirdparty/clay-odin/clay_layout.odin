// Pure Odin port of Clay v0.14 (b25a31c1a152915cd7dd6796e6592273e5a10aac).
// Copyright (c) 2024 Nic Barker. Altered source; see LICENSE.md and README.md.
package clay

// clay.h:1791 — Clay__CloseElement
_CloseElement :: proc "c" () {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return
	}
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	layoutConfig: ^LayoutConfig = openLayoutElement.layoutConfig
	elementHasScrollHorizontal: bool = false
	elementHasScrollVertical: bool = false
	for i: i32 = 0; (i < openLayoutElement.elementConfigs.length); i += 1 {
		config: ^ElementConfig = _ElementConfigArraySlice_Get(&openLayoutElement.elementConfigs, i)
		if (cast(i32)(config.type) == CLAY__ELEMENT_CONFIG_TYPE_CLIP) {
			elementHasScrollHorizontal = config.config.clipElementConfig.horizontal
			elementHasScrollVertical = config.config.clipElementConfig.vertical
			ctx.openClipElementStack.length -= 1
			break
		} else {
			if (cast(i32)(config.type) == CLAY__ELEMENT_CONFIG_TYPE_FLOATING) {
				ctx.openClipElementStack.length -= 1
			}
		}
	}
	leftRightPadding: f32 = cast(f32)((cast(i32)(layoutConfig.padding.left) + cast(i32)(layoutConfig.padding.right)))
	topBottomPadding: f32 = cast(f32)((cast(i32)(layoutConfig.padding.top) + cast(i32)(layoutConfig.padding.bottom)))
	// Attach children to the current open element
	openLayoutElement.childrenOrTextContent.children.elements = &ctx.layoutElementChildren.internalArray[ctx.layoutElementChildren.length]
	if (cast(i32)(layoutConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT) {
		openLayoutElement.dimensions.width = leftRightPadding
		openLayoutElement.minDimensions.width = leftRightPadding
		for i: i32 = 0; (i < cast(i32)(openLayoutElement.childrenOrTextContent.children.length)); i += 1 {
			childIndex: i32 = _int32_tArray_GetValue(&ctx.layoutElementChildrenBuffer, ((ctx.layoutElementChildrenBuffer.length - cast(i32)(openLayoutElement.childrenOrTextContent.children.length)) + i))
			child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, childIndex)
			openLayoutElement.dimensions.width += child.dimensions.width
			openLayoutElement.dimensions.height = _max(openLayoutElement.dimensions.height, (child.dimensions.height + topBottomPadding))
			// Minimum size of child elements doesn't matter to scroll containers as they can shrink and hide their contents
			if !(elementHasScrollHorizontal) {
				openLayoutElement.minDimensions.width += child.minDimensions.width
			}
			if !(elementHasScrollVertical) {
				openLayoutElement.minDimensions.height = _max(openLayoutElement.minDimensions.height, (child.minDimensions.height + topBottomPadding))
			}
			_int32_tArray_Add(&ctx.layoutElementChildren, childIndex)
		}
		childGap: f32 = cast(f32)((_max((cast(i32)(openLayoutElement.childrenOrTextContent.children.length) - 1), 0) * cast(i32)(layoutConfig.childGap)))
		openLayoutElement.dimensions.width += childGap
		openLayoutElement.minDimensions.width += childGap
	} else {
		if (cast(i32)(layoutConfig.layoutDirection) == CLAY_TOP_TO_BOTTOM) {
			openLayoutElement.dimensions.height = topBottomPadding
			openLayoutElement.minDimensions.height = topBottomPadding
			for i: i32 = 0; (i < cast(i32)(openLayoutElement.childrenOrTextContent.children.length)); i += 1 {
				childIndex: i32 = _int32_tArray_GetValue(&ctx.layoutElementChildrenBuffer, ((ctx.layoutElementChildrenBuffer.length - cast(i32)(openLayoutElement.childrenOrTextContent.children.length)) + i))
				child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, childIndex)
				openLayoutElement.dimensions.height += child.dimensions.height
				openLayoutElement.dimensions.width = _max(openLayoutElement.dimensions.width, (child.dimensions.width + leftRightPadding))
				// Minimum size of child elements doesn't matter to scroll containers as they can shrink and hide their contents
				if !(elementHasScrollVertical) {
					openLayoutElement.minDimensions.height += child.minDimensions.height
				}
				if !(elementHasScrollHorizontal) {
					openLayoutElement.minDimensions.width = _max(openLayoutElement.minDimensions.width, (child.minDimensions.width + leftRightPadding))
				}
				_int32_tArray_Add(&ctx.layoutElementChildren, childIndex)
			}
			childGap: f32 = cast(f32)((_max((cast(i32)(openLayoutElement.childrenOrTextContent.children.length) - 1), 0) * cast(i32)(layoutConfig.childGap)))
			openLayoutElement.dimensions.height += childGap
			openLayoutElement.minDimensions.height += childGap
		}
	}
	ctx.layoutElementChildrenBuffer.length -= cast(i32)(openLayoutElement.childrenOrTextContent.children.length)
	// Clamp element min and max width to the values configured in the layout
	if (cast(i32)(layoutConfig.sizing.width.type) != CLAY__SIZING_TYPE_PERCENT) {
		if (layoutConfig.sizing.width.constraints.sizeMinMax.max <= cast(f32)(0)) {
			layoutConfig.sizing.width.constraints.sizeMinMax.max = 3.40282347E+38
		}
		openLayoutElement.dimensions.width = _min(_max(openLayoutElement.dimensions.width, layoutConfig.sizing.width.constraints.sizeMinMax.min), layoutConfig.sizing.width.constraints.sizeMinMax.max)
		openLayoutElement.minDimensions.width = _min(_max(openLayoutElement.minDimensions.width, layoutConfig.sizing.width.constraints.sizeMinMax.min), layoutConfig.sizing.width.constraints.sizeMinMax.max)
	} else {
		openLayoutElement.dimensions.width = cast(f32)(0)
	}
	// Clamp element min and max height to the values configured in the layout
	if (cast(i32)(layoutConfig.sizing.height.type) != CLAY__SIZING_TYPE_PERCENT) {
		if (layoutConfig.sizing.height.constraints.sizeMinMax.max <= cast(f32)(0)) {
			layoutConfig.sizing.height.constraints.sizeMinMax.max = 3.40282347E+38
		}
		openLayoutElement.dimensions.height = _min(_max(openLayoutElement.dimensions.height, layoutConfig.sizing.height.constraints.sizeMinMax.min), layoutConfig.sizing.height.constraints.sizeMinMax.max)
		openLayoutElement.minDimensions.height = _min(_max(openLayoutElement.minDimensions.height, layoutConfig.sizing.height.constraints.sizeMinMax.min), layoutConfig.sizing.height.constraints.sizeMinMax.max)
	} else {
		openLayoutElement.dimensions.height = cast(f32)(0)
	}
	_UpdateAspectRatioBox(openLayoutElement)
	elementIsFloating: bool = _ElementHasConfig(openLayoutElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING))
	// Close the currently open element
	closingElementIndex: i32 = _int32_tArray_RemoveSwapback(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 1))
	openLayoutElement = _GetOpenLayoutElement()
	if (!(elementIsFloating) && (ctx.openLayoutElementStack.length > 1)) {
		openLayoutElement.childrenOrTextContent.children.length += 1
		_int32_tArray_Add(&ctx.layoutElementChildrenBuffer, closingElementIndex)
	}
}

// clay.h:1953 — Clay__MemCmp
@(private)
_MemCmp :: proc "c" (s1: [^]u8, s2: [^]u8, length: i32) -> bool {
	for i: i32 = 0; (i < length); i += 1 {
		if (cast(i32)(s1[i]) != cast(i32)(s2[i])) {
			return false
		}
	}
	return true
}

// clay.h:1963 — Clay__OpenElement
_OpenElement :: proc "c" () {
	ctx: ^Context = GetCurrentContext()
	if ((ctx.layoutElements.length == (ctx.layoutElements.capacity - 1)) || (cast(i32)(ctx.booleanWarnings.maxElementsExceeded) != 0)) {
		ctx.booleanWarnings.maxElementsExceeded = true
		return
	}
	layoutElement: LayoutElement = LayoutElement{childrenOrTextContent = LayoutElement_childrenOrTextContent{children = _LayoutElementChildren{elements = nil}}}
	LayoutElementArray_Add(&ctx.layoutElements, layoutElement)
	_int32_tArray_Add(&ctx.openLayoutElementStack, (ctx.layoutElements.length - 1))
	if (ctx.openClipElementStack.length > 0) {
		_int32_tArray_Set(&ctx.layoutElementClipElementIds, (ctx.layoutElements.length - 1), _int32_tArray_GetValue(&ctx.openClipElementStack, (ctx.openClipElementStack.length - 1)))
	} else {
		_int32_tArray_Set(&ctx.layoutElementClipElementIds, (ctx.layoutElements.length - 1), 0)
	}
}

// clay.h:1979 — Clay__OpenTextElement
_OpenTextElement :: proc "c" (text_arg: String, textConfig: ^TextElementConfig) {
	text := text_arg
	ctx: ^Context = GetCurrentContext()
	if ((ctx.layoutElements.length == (ctx.layoutElements.capacity - 1)) || (cast(i32)(ctx.booleanWarnings.maxElementsExceeded) != 0)) {
		ctx.booleanWarnings.maxElementsExceeded = true
		return
	}
	parentElement: ^LayoutElement = _GetOpenLayoutElement()
	layoutElement: LayoutElement = LayoutElement{childrenOrTextContent = LayoutElement_childrenOrTextContent{children = _LayoutElementChildren{elements = nil}}}
	textElement: ^LayoutElement = LayoutElementArray_Add(&ctx.layoutElements, layoutElement)
	if (ctx.openClipElementStack.length > 0) {
		_int32_tArray_Set(&ctx.layoutElementClipElementIds, (ctx.layoutElements.length - 1), _int32_tArray_GetValue(&ctx.openClipElementStack, (ctx.openClipElementStack.length - 1)))
	} else {
		_int32_tArray_Set(&ctx.layoutElementClipElementIds, (ctx.layoutElements.length - 1), 0)
	}
	_int32_tArray_Add(&ctx.layoutElementChildrenBuffer, (ctx.layoutElements.length - 1))
	textMeasured: ^_MeasureTextCacheItem = _MeasureTextCached(&text, textConfig)
	elementId: ElementId = _HashNumber(cast(u32)(parentElement.childrenOrTextContent.children.length), parentElement.id)
	textElement.id = elementId.id
	_AddHashMapItem(elementId, textElement, cast(u32)(0))
	_StringArray_Add(&ctx.layoutElementIdStrings, elementId.stringId)
	textDimensions: Dimensions = Dimensions{width = textMeasured.unwrappedDimensions.width, height = ((cast(i32)(textConfig.lineHeight) > 0) ? cast(f32)(textConfig.lineHeight) : textMeasured.unwrappedDimensions.height)}
	textElement.dimensions = textDimensions
	textElement.minDimensions = Dimensions{width = textMeasured.minWidth, height = textDimensions.height}
	textElement.childrenOrTextContent.textElementData = _TextElementDataArray_Add(&ctx.textElementData, _TextElementData{text = text, preferredDimensions = textMeasured.unwrappedDimensions, elementIndex = (ctx.layoutElements.length - 1)})
	textElement.elementConfigs = _ElementConfigArraySlice{length = 1, internalArray = cast([^]ElementConfig)(_ElementConfigArray_Add(&ctx.elementConfigs, ElementConfig{type = cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT), config = ElementConfigUnion{textElementConfig = textConfig}}))}
	textElement.layoutConfig = &CLAY_LAYOUT_DEFAULT
	parentElement.childrenOrTextContent.children.length += 1
}

// clay.h:2013 — Clay__AttachId
@(private)
_AttachId :: proc "c" (elementId: ElementId) -> ElementId {
	ctx: ^Context = GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return ElementId_DEFAULT
	}
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	idAlias: u32 = openLayoutElement.id
	openLayoutElement.id = elementId.id
	_AddHashMapItem(elementId, openLayoutElement, idAlias)
	_StringArray_Set(&ctx.layoutElementIdStrings, (ctx.layoutElements.length - 1), elementId.stringId)
	return elementId
}

// clay.h:2026 — Clay__ConfigureOpenElementPtr
@(private)
_ConfigureOpenElementPtr :: proc "c" (declaration: ^ElementDeclaration) {
	ctx: ^Context = GetCurrentContext()
	openLayoutElement: ^LayoutElement = _GetOpenLayoutElement()
	openLayoutElement.layoutConfig = _StoreLayoutConfig(declaration.layout)
	if (((cast(i32)(declaration.layout.sizing.width.type) == CLAY__SIZING_TYPE_PERCENT) && (declaration.layout.sizing.width.constraints.sizePercent > cast(f32)(1))) || ((cast(i32)(declaration.layout.sizing.height.type) == CLAY__SIZING_TYPE_PERCENT) && (declaration.layout.sizing.height.constraints.sizePercent > cast(f32)(1)))) {
		ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_PERCENTAGE_OVER_1), errorText = _static_string("An element was configured with CLAY_SIZING_PERCENT, but the provided percentage value was over 1.0. Clay expects a value between 0 and 1, i.e. 20% is 0.2."), userData = ctx.errorHandler.userData})
	}
	openLayoutElementId: ElementId = declaration.id
	openLayoutElement.elementConfigs.internalArray = cast([^]ElementConfig)(&ctx.elementConfigs.internalArray[ctx.elementConfigs.length])
	sharedConfig: ^SharedElementConfig = nil
	if ((declaration.backgroundColor)[3] > cast(f32)(0)) {
		sharedConfig = _StoreSharedElementConfig(SharedElementConfig{backgroundColor = declaration.backgroundColor})
		_AttachElementConfig(ElementConfigUnion{sharedElementConfig = sharedConfig}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_SHARED))
	}
	if !(_MemCmp(cast([^]u8)(&declaration.cornerRadius), cast([^]u8)(&_CornerRadius_DEFAULT), cast(i32)(size_of(CornerRadius)))) {
		if (sharedConfig != nil) {
			sharedConfig.cornerRadius = declaration.cornerRadius
		} else {
			sharedConfig = _StoreSharedElementConfig(SharedElementConfig{cornerRadius = declaration.cornerRadius})
			_AttachElementConfig(ElementConfigUnion{sharedElementConfig = sharedConfig}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_SHARED))
		}
	}
	if (declaration.userData != nil) {
		if (sharedConfig != nil) {
			sharedConfig.userData = declaration.userData
		} else {
			sharedConfig = _StoreSharedElementConfig(SharedElementConfig{userData = declaration.userData})
			_AttachElementConfig(ElementConfigUnion{sharedElementConfig = sharedConfig}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_SHARED))
		}
	}
	if (declaration.image.imageData != nil) {
		_AttachElementConfig(ElementConfigUnion{imageElementConfig = _StoreImageElementConfig(declaration.image)}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_IMAGE))
	}
	if (declaration.aspectRatio.aspectRatio > cast(f32)(0)) {
		_AttachElementConfig(ElementConfigUnion{aspectRatioElementConfig = _StoreAspectRatioElementConfig(declaration.aspectRatio)}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_ASPECT))
		_int32_tArray_Add(&ctx.aspectRatioElementIndexes, (ctx.layoutElements.length - 1))
	}
	if (cast(i32)(declaration.floating.attachTo) != CLAY_ATTACH_TO_NONE) {
		floatingConfig: FloatingElementConfig = declaration.floating
		// This looks dodgy but because of the auto generated root element the depth of the tree will always be at least 2 here
		hierarchicalParent: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 2)))
		if (hierarchicalParent != nil) {
			clipElementId: u32 = cast(u32)(0)
			if (cast(i32)(declaration.floating.attachTo) == CLAY_ATTACH_TO_PARENT) {
				// Attach to the element's direct hierarchical parent
				floatingConfig.parentId = hierarchicalParent.id
				if (ctx.openClipElementStack.length > 0) {
					clipElementId = cast(u32)(_int32_tArray_GetValue(&ctx.openClipElementStack, (ctx.openClipElementStack.length - 1)))
				}
			} else {
				if (cast(i32)(declaration.floating.attachTo) == CLAY_ATTACH_TO_ELEMENT_WITH_ID) {
					parentItem: ^LayoutElementHashMapItem = _GetHashMapItem(floatingConfig.parentId)
					if (parentItem == &LayoutElementHashMapItem_DEFAULT) {
						ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_FLOATING_CONTAINER_PARENT_NOT_FOUND), errorText = _static_string("A floating element was declared with a parentId, but no element with that ID was found."), userData = ctx.errorHandler.userData})
					} else {
						clipElementId = cast(u32)(_int32_tArray_GetValue(&ctx.layoutElementClipElementIds, cast(i32)((cast(i64)(uintptr(parentItem.layoutElement) - uintptr(ctx.layoutElements.internalArray)) / size_of(LayoutElement)))))
					}
				} else {
					if (cast(i32)(declaration.floating.attachTo) == CLAY_ATTACH_TO_ROOT) {
						floatingConfig.parentId = _HashString(_static_string("Clay__RootContainer"), cast(u32)(0), cast(u32)(0)).id
					}
				}
			}
			if !((openLayoutElementId.id != 0)) {
				openLayoutElementId = _HashString(_static_string("Clay__FloatingContainer"), cast(u32)(ctx.layoutElementTreeRoots.length), cast(u32)(0))
			}
			if (cast(i32)(declaration.floating.clipTo) == CLAY_CLIP_TO_NONE) {
				clipElementId = cast(u32)(0)
			}
			currentElementIndex: i32 = _int32_tArray_GetValue(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 1))
			_int32_tArray_Set(&ctx.layoutElementClipElementIds, currentElementIndex, cast(i32)(clipElementId))
			_int32_tArray_Add(&ctx.openClipElementStack, cast(i32)(clipElementId))
			_LayoutElementTreeRootArray_Add(&ctx.layoutElementTreeRoots, _LayoutElementTreeRoot{layoutElementIndex = _int32_tArray_GetValue(&ctx.openLayoutElementStack, (ctx.openLayoutElementStack.length - 1)), parentId = floatingConfig.parentId, clipElementId = clipElementId, zIndex = floatingConfig.zIndex})
			_AttachElementConfig(ElementConfigUnion{floatingElementConfig = _StoreFloatingElementConfig(floatingConfig)}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING))
		}
	}
	if (declaration.custom.customData != nil) {
		_AttachElementConfig(ElementConfigUnion{customElementConfig = _StoreCustomElementConfig(declaration.custom)}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CUSTOM))
	}
	if (openLayoutElementId.id != cast(u32)(0)) {
		_AttachId(openLayoutElementId)
	} else {
		if (openLayoutElement.id == cast(u32)(0)) {
			openLayoutElementId = _GenerateIdForAnonymousElement(openLayoutElement)
		}
	}
	if ((cast(i32)(declaration.clip.horizontal) | cast(i32)(declaration.clip.vertical)) != 0) {
		_AttachElementConfig(ElementConfigUnion{clipElementConfig = _StoreClipElementConfig(declaration.clip)}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP))
		_int32_tArray_Add(&ctx.openClipElementStack, cast(i32)(openLayoutElement.id))
		// Retrieve or create cached data to track scroll position across frames
		scrollOffset: ^_ScrollContainerDataInternal = nil
		for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
			mapping: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
			if (openLayoutElement.id == mapping.elementId) {
				scrollOffset = mapping
				scrollOffset.layoutElement = openLayoutElement
				scrollOffset.openThisFrame = true
			}
		}
		if !((scrollOffset != nil)) {
			scrollOffset = _ScrollContainerDataInternalArray_Add(&ctx.scrollContainerDatas, _ScrollContainerDataInternal{layoutElement = openLayoutElement, scrollOrigin = Vector2{cast(f32)(-(1)), cast(f32)(-(1))}, elementId = openLayoutElement.id, openThisFrame = true})
		}
		if ctx.externalScrollHandlingEnabled {
			scrollOffset.scrollPosition = _QueryScrollOffset(scrollOffset.elementId, ctx.queryScrollOffsetUserData)
		}
	}
	if !(_MemCmp(cast([^]u8)(&declaration.border.width), cast([^]u8)(&_BorderWidth_DEFAULT), cast(i32)(size_of(BorderWidth)))) {
		_AttachElementConfig(ElementConfigUnion{borderElementConfig = _StoreBorderElementConfig(declaration.border)}, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_BORDER))
	}
}

// clay.h:2146 — Clay__ConfigureOpenElement
_ConfigureOpenElement :: proc "c" (declaration_arg: ElementDeclaration) {
	declaration := declaration_arg
	_ConfigureOpenElementPtr(&declaration)
}

// clay.h:2150 — Clay__InitializeEphemeralMemory
@(private)
_InitializeEphemeralMemory :: proc "c" (ctx: ^Context) {
	maxElementCount: i32 = ctx.maxElementCount
	// Ephemeral Memory - reset every frame
	arena: ^Arena = &ctx.internalArena
	arena.nextAllocation = ctx.arenaResetOffset
	ctx.layoutElementChildrenBuffer = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElements = LayoutElementArray_Allocate_Arena(maxElementCount, arena)
	ctx.warnings = _WarningArray_Allocate_Arena(100, arena)
	ctx.layoutConfigs = _LayoutConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.elementConfigs = _ElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.textElementConfigs = _TextElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.aspectRatioElementConfigs = _AspectRatioElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.imageElementConfigs = _ImageElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.floatingElementConfigs = _FloatingElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.clipElementConfigs = _ClipElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.customElementConfigs = _CustomElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.borderElementConfigs = _BorderElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.sharedElementConfigs = _SharedElementConfigArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElementIdStrings = _StringArray_Allocate_Arena(maxElementCount, arena)
	ctx.wrappedTextLines = _WrappedTextLineArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElementTreeNodeArray1 = _LayoutElementTreeNodeArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElementTreeRoots = _LayoutElementTreeRootArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElementChildren = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.openLayoutElementStack = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.textElementData = _TextElementDataArray_Allocate_Arena(maxElementCount, arena)
	ctx.aspectRatioElementIndexes = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.renderCommands = RenderCommandArray_Allocate_Arena(maxElementCount, arena)
	ctx.treeNodeVisited = _boolArray_Allocate_Arena(maxElementCount, arena)
	ctx.treeNodeVisited.length = ctx.treeNodeVisited.capacity
	ctx.openClipElementStack = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.reusableElementIndexBuffer = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElementClipElementIds = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.dynamicStringData = _charArray_Allocate_Arena(maxElementCount, arena)
}

// clay.h:2188 — Clay__InitializePersistentMemory
@(private)
_InitializePersistentMemory :: proc "c" (ctx: ^Context) {
	// Persistent memory - initialized once and not reset
	maxElementCount: i32 = ctx.maxElementCount
	maxMeasureTextCacheWordCount: i32 = ctx.maxMeasureTextCacheWordCount
	arena: ^Arena = &ctx.internalArena
	ctx.scrollContainerDatas = _ScrollContainerDataInternalArray_Allocate_Arena(10, arena)
	ctx.layoutElementsHashMapInternal = _LayoutElementHashMapItemArray_Allocate_Arena(maxElementCount, arena)
	ctx.layoutElementsHashMap = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.measureTextHashMapInternal = _MeasureTextCacheItemArray_Allocate_Arena(maxElementCount, arena)
	ctx.measureTextHashMapInternalFreeList = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.measuredWordsFreeList = _int32_tArray_Allocate_Arena(maxMeasureTextCacheWordCount, arena)
	ctx.measureTextHashMap = _int32_tArray_Allocate_Arena(maxElementCount, arena)
	ctx.measuredWords = _MeasuredWordArray_Allocate_Arena(maxMeasureTextCacheWordCount, arena)
	ctx.pointerOverIds = ElementIdArray_Allocate_Arena(maxElementCount, arena)
	ctx.debugElementData = _DebugElementDataArray_Allocate_Arena(maxElementCount, arena)
	ctx.arenaResetOffset = arena.nextAllocation
}

// clay.h:2209 — Clay__FloatEqual
@(private)
_FloatEqual :: proc "c" (left: f32, right: f32) -> bool {
	subtracted: f32 = (left - right)
	return ((subtracted < CLAY__EPSILON) && (subtracted > -(CLAY__EPSILON)))
}

// clay.h:2214 — Clay__SizeContainersAlongAxis
@(private)
_SizeContainersAlongAxis :: proc "c" (xAxis: bool) {
	ctx: ^Context = GetCurrentContext()
	bfsBuffer: _int32_tArray = ctx.layoutElementChildrenBuffer
	resizableContainerBuffer: _int32_tArray = ctx.openLayoutElementStack
	for rootIndex: i32 = 0; (rootIndex < ctx.layoutElementTreeRoots.length); rootIndex += 1 {
		bfsBuffer.length = 0
		root: ^_LayoutElementTreeRoot = _LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, rootIndex)
		rootElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, root.layoutElementIndex)
		_int32_tArray_Add(&bfsBuffer, root.layoutElementIndex)
		// Size floating containers to their parents
		if _ElementHasConfig(rootElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING)) {
			floatingElementConfig: ^FloatingElementConfig = _FindElementConfigWithType(rootElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING)).floatingElementConfig
			parentItem: ^LayoutElementHashMapItem = _GetHashMapItem(floatingElementConfig.parentId)
			if ((parentItem != nil) && (parentItem != &LayoutElementHashMapItem_DEFAULT)) {
				parentLayoutElement: ^LayoutElement = parentItem.layoutElement
				if (cast(i32)(rootElement.layoutConfig.sizing.width.type) == CLAY__SIZING_TYPE_GROW) {
					rootElement.dimensions.width = parentLayoutElement.dimensions.width
				}
				if (cast(i32)(rootElement.layoutConfig.sizing.height.type) == CLAY__SIZING_TYPE_GROW) {
					rootElement.dimensions.height = parentLayoutElement.dimensions.height
				}
			}
		}
		rootElement.dimensions.width = _min(_max(rootElement.dimensions.width, rootElement.layoutConfig.sizing.width.constraints.sizeMinMax.min), rootElement.layoutConfig.sizing.width.constraints.sizeMinMax.max)
		rootElement.dimensions.height = _min(_max(rootElement.dimensions.height, rootElement.layoutConfig.sizing.height.constraints.sizeMinMax.min), rootElement.layoutConfig.sizing.height.constraints.sizeMinMax.max)
		for i: i32 = 0; (i < bfsBuffer.length); i += 1 {
			parentIndex: i32 = _int32_tArray_GetValue(&bfsBuffer, i)
			parent: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, parentIndex)
			parentStyleConfig: ^LayoutConfig = parent.layoutConfig
			growContainerCount: i32 = 0
			parentSize: f32 = ((cast(i32)(xAxis) != 0) ? parent.dimensions.width : parent.dimensions.height)
			parentPadding: f32 = cast(f32)(((cast(i32)(xAxis) != 0) ? (cast(i32)(parent.layoutConfig.padding.left) + cast(i32)(parent.layoutConfig.padding.right)) : (cast(i32)(parent.layoutConfig.padding.top) + cast(i32)(parent.layoutConfig.padding.bottom))))
			innerContentSize: f32 = cast(f32)(0)
			totalPaddingAndChildGaps: f32 = parentPadding
			sizingAlongAxis: bool = (((cast(i32)(xAxis) != 0) && (cast(i32)(parentStyleConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT)) || (!(xAxis) && (cast(i32)(parentStyleConfig.layoutDirection) == CLAY_TOP_TO_BOTTOM)))
			resizableContainerBuffer.length = 0
			parentChildGap: f32 = cast(f32)(parentStyleConfig.childGap)
			for childOffset: i32 = 0; (childOffset < cast(i32)(parent.childrenOrTextContent.children.length)); childOffset += 1 {
				childElementIndex: i32 = (cast([^]i32)(parent.childrenOrTextContent.children.elements))[childOffset]
				childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, childElementIndex)
				childSizing: SizingAxis = ((cast(i32)(xAxis) != 0) ? childElement.layoutConfig.sizing.width : childElement.layoutConfig.sizing.height)
				childSize: f32 = ((cast(i32)(xAxis) != 0) ? childElement.dimensions.width : childElement.dimensions.height)
				if (!(_ElementHasConfig(childElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) && (cast(i32)(childElement.childrenOrTextContent.children.length) > 0)) {
					_int32_tArray_Add(&bfsBuffer, childElementIndex)
				}
				if (((cast(i32)(childSizing.type) != CLAY__SIZING_TYPE_PERCENT) && (cast(i32)(childSizing.type) != CLAY__SIZING_TYPE_FIXED)) && (!(_ElementHasConfig(childElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) || (cast(i32)(_FindElementConfigWithType(childElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT)).textElementConfig.wrapMode) == CLAY_TEXT_WRAP_WORDS))) {
					_int32_tArray_Add(&resizableContainerBuffer, childElementIndex)
				}
				if sizingAlongAxis {
					innerContentSize += ((cast(i32)(childSizing.type) == CLAY__SIZING_TYPE_PERCENT) ? cast(f32)(0) : childSize)
					if (cast(i32)(childSizing.type) == CLAY__SIZING_TYPE_GROW) {
						growContainerCount += 1
					}
					if (childOffset > 0) {
						innerContentSize += parentChildGap
						totalPaddingAndChildGaps += parentChildGap
					}
				} else {
					innerContentSize = _max(childSize, innerContentSize)
				}
			}
			// Expand percentage containers to size
			for childOffset: i32 = 0; (childOffset < cast(i32)(parent.childrenOrTextContent.children.length)); childOffset += 1 {
				childElementIndex: i32 = (cast([^]i32)(parent.childrenOrTextContent.children.elements))[childOffset]
				childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, childElementIndex)
				childSizing: SizingAxis = ((cast(i32)(xAxis) != 0) ? childElement.layoutConfig.sizing.width : childElement.layoutConfig.sizing.height)
				childSize: ^f32 = ((cast(i32)(xAxis) != 0) ? &childElement.dimensions.width : &childElement.dimensions.height)
				if (cast(i32)(childSizing.type) == CLAY__SIZING_TYPE_PERCENT) {
					(childSize)^ = ((parentSize - totalPaddingAndChildGaps) * childSizing.constraints.sizePercent)
					if sizingAlongAxis {
						innerContentSize += (childSize)^
					}
					_UpdateAspectRatioBox(childElement)
				}
			}
			if sizingAlongAxis {
				sizeToDistribute: f32 = ((parentSize - parentPadding) - innerContentSize)
				// The content is too large, compress the children as much as possible
				if (sizeToDistribute < cast(f32)(0)) {
					// If the parent clips content in this axis direction, don't compress children, just leave them alone
					clipElementConfig: ^ClipElementConfig = _FindElementConfigWithType(parent, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
					if (clipElementConfig != nil) {
						if (((cast(i32)(xAxis) != 0) && (cast(i32)(clipElementConfig.horizontal) != 0)) || (!(xAxis) && (cast(i32)(clipElementConfig.vertical) != 0))) {
							continue
						}
					}
					// Scrolling containers preferentially compress before others
					for ((sizeToDistribute < -(CLAY__EPSILON)) && (resizableContainerBuffer.length > 0)) {
						largest: f32 = cast(f32)(0)
						secondLargest: f32 = cast(f32)(0)
						widthToAdd: f32 = sizeToDistribute
						for childIndex: i32 = 0; (childIndex < resizableContainerBuffer.length); childIndex += 1 {
							child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&resizableContainerBuffer, childIndex))
							childSize: f32 = ((cast(i32)(xAxis) != 0) ? child.dimensions.width : child.dimensions.height)
							if _FloatEqual(childSize, largest) {
								continue
							}
							if (childSize > largest) {
								secondLargest = largest
								largest = childSize
							}
							if (childSize < largest) {
								secondLargest = _max(secondLargest, childSize)
								widthToAdd = (secondLargest - largest)
							}
						}
						widthToAdd = _max(widthToAdd, (sizeToDistribute / cast(f32)(resizableContainerBuffer.length)))
						for childIndex: i32 = 0; (childIndex < resizableContainerBuffer.length); childIndex += 1 {
							child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&resizableContainerBuffer, childIndex))
							childSize: ^f32 = ((cast(i32)(xAxis) != 0) ? &child.dimensions.width : &child.dimensions.height)
							minSize: f32 = ((cast(i32)(xAxis) != 0) ? child.minDimensions.width : child.minDimensions.height)
							previousWidth: f32 = (childSize)^
							if _FloatEqual((childSize)^, largest) {
								(childSize)^ += widthToAdd
								if ((childSize)^ <= minSize) {
									(childSize)^ = minSize
									_int32_tArray_RemoveSwapback(&resizableContainerBuffer, _post_inc(&(childIndex), -1))
								}
								sizeToDistribute -= ((childSize)^ - previousWidth)
							}
						}
					}
				} else {
					if ((sizeToDistribute > cast(f32)(0)) && (growContainerCount > 0)) {
						for childIndex: i32 = 0; (childIndex < resizableContainerBuffer.length); childIndex += 1 {
							child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&resizableContainerBuffer, childIndex))
							childSizing: SizingType = cast(SizingType)(((cast(i32)(xAxis) != 0) ? cast(i32)(child.layoutConfig.sizing.width.type) : cast(i32)(child.layoutConfig.sizing.height.type)))
							if (cast(i32)(childSizing) != CLAY__SIZING_TYPE_GROW) {
								_int32_tArray_RemoveSwapback(&resizableContainerBuffer, _post_inc(&(childIndex), -1))
							}
						}
						for ((sizeToDistribute > CLAY__EPSILON) && (resizableContainerBuffer.length > 0)) {
							smallest: f32 = 3.40282347E+38
							secondSmallest: f32 = 3.40282347E+38
							widthToAdd: f32 = sizeToDistribute
							for childIndex: i32 = 0; (childIndex < resizableContainerBuffer.length); childIndex += 1 {
								child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&resizableContainerBuffer, childIndex))
								childSize: f32 = ((cast(i32)(xAxis) != 0) ? child.dimensions.width : child.dimensions.height)
								if _FloatEqual(childSize, smallest) {
									continue
								}
								if (childSize < smallest) {
									secondSmallest = smallest
									smallest = childSize
								}
								if (childSize > smallest) {
									secondSmallest = _min(secondSmallest, childSize)
									widthToAdd = (secondSmallest - smallest)
								}
							}
							widthToAdd = _min(widthToAdd, (sizeToDistribute / cast(f32)(resizableContainerBuffer.length)))
							for childIndex: i32 = 0; (childIndex < resizableContainerBuffer.length); childIndex += 1 {
								child: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&resizableContainerBuffer, childIndex))
								childSize: ^f32 = ((cast(i32)(xAxis) != 0) ? &child.dimensions.width : &child.dimensions.height)
								maxSize: f32 = ((cast(i32)(xAxis) != 0) ? child.layoutConfig.sizing.width.constraints.sizeMinMax.max : child.layoutConfig.sizing.height.constraints.sizeMinMax.max)
								previousWidth: f32 = (childSize)^
								if _FloatEqual((childSize)^, smallest) {
									(childSize)^ += widthToAdd
									if ((childSize)^ >= maxSize) {
										(childSize)^ = maxSize
										_int32_tArray_RemoveSwapback(&resizableContainerBuffer, _post_inc(&(childIndex), -1))
									}
									sizeToDistribute -= ((childSize)^ - previousWidth)
								}
							}
						}
					}
				}
			} else {
				for childOffset: i32 = 0; (childOffset < resizableContainerBuffer.length); childOffset += 1 {
					childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&resizableContainerBuffer, childOffset))
					childSizing: SizingAxis = ((cast(i32)(xAxis) != 0) ? childElement.layoutConfig.sizing.width : childElement.layoutConfig.sizing.height)
					minSize: f32 = ((cast(i32)(xAxis) != 0) ? childElement.minDimensions.width : childElement.minDimensions.height)
					childSize: ^f32 = ((cast(i32)(xAxis) != 0) ? &childElement.dimensions.width : &childElement.dimensions.height)
					maxSize: f32 = (parentSize - parentPadding)
					// If we're laying out the children of a scroll panel, grow containers expand to the size of the inner content, not the outer container
					if _ElementHasConfig(parent, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)) {
						clipElementConfig: ^ClipElementConfig = _FindElementConfigWithType(parent, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
						if (((cast(i32)(xAxis) != 0) && (cast(i32)(clipElementConfig.horizontal) != 0)) || (!(xAxis) && (cast(i32)(clipElementConfig.vertical) != 0))) {
							maxSize = _max(maxSize, innerContentSize)
						}
					}
					if (cast(i32)(childSizing.type) == CLAY__SIZING_TYPE_GROW) {
						(childSize)^ = _min(maxSize, childSizing.constraints.sizeMinMax.max)
					}
					(childSize)^ = _max(minSize, _min((childSize)^, maxSize))
				}
			}
		}
	}
}

// clay.h:2419 — Clay__IntToString
@(private)
_IntToString :: proc "c" (integer_arg: i32) -> String {
	integer := integer_arg
	if (integer == 0) {
		return String{length = 1, chars = raw_data(string("0"))}
	}
	ctx: ^Context = GetCurrentContext()
	chars: [^]u8 = _offset(ctx.dynamicStringData.internalArray, int(ctx.dynamicStringData.length))
	length: i32 = 0
	sign: i32 = integer
	if (integer < 0) {
		integer = -(integer)
	}
	for (integer > 0) {
		chars[_post_inc(&(length), 1)] = cast(u8)(((integer % 10) + 48))
		integer /= 10
	}
	if (sign < 0) {
		chars[_post_inc(&(length), 1)] = cast(u8)(45)
	}
	// Reverse the string to get the correct order
	{
		j: i32 = 0
		k: i32 = (length - 1)
		for ; (j < k); j, k = j + 1, k - 1 {
			temp: u8 = chars[j]
			chars[j] = chars[k]
			chars[k] = temp
		}
	}
	ctx.dynamicStringData.length += length
	return String{length = length, chars = chars}
}

// clay.h:2450 — Clay__AddRenderCommand
@(private)
_AddRenderCommand :: proc "c" (renderCommand: RenderCommand) {
	ctx: ^Context = GetCurrentContext()
	if (ctx.renderCommands.length < (ctx.renderCommands.capacity - 1)) {
		RenderCommandArray_Add(&ctx.renderCommands, renderCommand)
	} else {
		if !(ctx.booleanWarnings.maxRenderCommandsExceeded) {
			ctx.booleanWarnings.maxRenderCommandsExceeded = true
			ctx.errorHandler.handler(ErrorData{errorType = cast(ErrorType)(CLAY_ERROR_TYPE_ELEMENTS_CAPACITY_EXCEEDED), errorText = _static_string("Clay ran out of capacity while attempting to create render commands. This is usually caused by a large amount of wrapping text elements while close to the max element capacity. Try using Clay_SetMaxElementCount() with a higher value."), userData = ctx.errorHandler.userData})
		}
	}
}

// clay.h:2465 — Clay__ElementIsOffscreen
@(private)
_ElementIsOffscreen :: proc "c" (boundingBox: ^BoundingBox) -> bool {
	ctx: ^Context = GetCurrentContext()
	if ctx.disableCulling {
		return false
	}
	return ((((boundingBox.x > ctx.layoutDimensions.width) || (boundingBox.y > ctx.layoutDimensions.height)) || ((boundingBox.x + boundingBox.width) < cast(f32)(0))) || ((boundingBox.y + boundingBox.height) < cast(f32)(0)))
}

// clay.h:2477 — Clay__CalculateFinalLayout
@(private)
_CalculateFinalLayout :: proc "c" () {
	ctx: ^Context = GetCurrentContext()
	// Calculate sizing along the X axis
	_SizeContainersAlongAxis(true)
	// Wrap text
	for textElementIndex: i32 = 0; (textElementIndex < ctx.textElementData.length); textElementIndex += 1 {
		textElementData: ^_TextElementData = _TextElementDataArray_Get(&ctx.textElementData, textElementIndex)
		textElementData.wrappedLines = _WrappedTextLineArraySlice{length = 0, internalArray = cast([^]_WrappedTextLine)(&ctx.wrappedTextLines.internalArray[ctx.wrappedTextLines.length])}
		containerElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, textElementData.elementIndex)
		textConfig: ^TextElementConfig = _FindElementConfigWithType(containerElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT)).textElementConfig
		measureTextCacheItem: ^_MeasureTextCacheItem = _MeasureTextCached(&textElementData.text, textConfig)
		lineWidth: f32 = cast(f32)(0)
		lineHeight: f32 = ((cast(i32)(textConfig.lineHeight) > 0) ? cast(f32)(textConfig.lineHeight) : textElementData.preferredDimensions.height)
		lineLengthChars: i32 = 0
		lineStartOffset: i32 = 0
		if (!(measureTextCacheItem.containsNewlines) && (textElementData.preferredDimensions.width <= containerElement.dimensions.width)) {
			_WrappedTextLineArray_Add(&ctx.wrappedTextLines, _WrappedTextLine{dimensions = containerElement.dimensions, line = textElementData.text})
			textElementData.wrappedLines.length += 1
			continue
		}
		spaceWidth: f32 = _MeasureText(StringSlice{length = 1, chars = CLAY__SPACECHAR.chars, baseChars = CLAY__SPACECHAR.chars}, textConfig, ctx.measureTextUserData).width
		wordIndex: i32 = measureTextCacheItem.measuredWordsStartIndex
		for (wordIndex != -(1)) {
			if (ctx.wrappedTextLines.length > (ctx.wrappedTextLines.capacity - 1)) {
				break
			}
			measuredWord: ^_MeasuredWord = _MeasuredWordArray_Get(&ctx.measuredWords, wordIndex)
			// Only word on the line is too large, just render it anyway
			if ((lineLengthChars == 0) && ((lineWidth + measuredWord.width) > containerElement.dimensions.width)) {
				_WrappedTextLineArray_Add(&ctx.wrappedTextLines, _WrappedTextLine{dimensions = Dimensions{width = measuredWord.width, height = lineHeight}, line = String{length = measuredWord.length, chars = &textElementData.text.chars[measuredWord.startOffset]}})
				textElementData.wrappedLines.length += 1
				wordIndex = measuredWord.next
				lineStartOffset = (measuredWord.startOffset + measuredWord.length)
			} else {
				if ((measuredWord.length == 0) || ((lineWidth + measuredWord.width) > containerElement.dimensions.width)) {
					finalCharIsSpace: bool = (cast(i32)(textElementData.text.chars[((lineStartOffset + lineLengthChars) - 1)]) == 32)
					_WrappedTextLineArray_Add(&ctx.wrappedTextLines, _WrappedTextLine{dimensions = Dimensions{width = (lineWidth + ((cast(i32)(finalCharIsSpace) != 0) ? -(spaceWidth) : cast(f32)(0))), height = lineHeight}, line = String{length = (lineLengthChars + ((cast(i32)(finalCharIsSpace) != 0) ? -(1) : 0)), chars = &textElementData.text.chars[lineStartOffset]}})
					textElementData.wrappedLines.length += 1
					if ((lineLengthChars == 0) || (measuredWord.length == 0)) {
						wordIndex = measuredWord.next
					}
					lineWidth = cast(f32)(0)
					lineLengthChars = 0
					lineStartOffset = measuredWord.startOffset
				} else {
					lineWidth += (measuredWord.width + cast(f32)(cast(i32)(textConfig.letterSpacing)))
					lineLengthChars += measuredWord.length
					wordIndex = measuredWord.next
				}
			}
		}
		if (lineLengthChars > 0) {
			_WrappedTextLineArray_Add(&ctx.wrappedTextLines, _WrappedTextLine{dimensions = Dimensions{width = (lineWidth - cast(f32)(cast(i32)(textConfig.letterSpacing))), height = lineHeight}, line = String{length = lineLengthChars, chars = &textElementData.text.chars[lineStartOffset]}})
			textElementData.wrappedLines.length += 1
		}
		containerElement.dimensions.height = (lineHeight * cast(f32)(textElementData.wrappedLines.length))
	}
	// Scale vertical heights according to aspect ratio
	for i: i32 = 0; (i < ctx.aspectRatioElementIndexes.length); i += 1 {
		aspectElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&ctx.aspectRatioElementIndexes, i))
		config: ^AspectRatioElementConfig = _FindElementConfigWithType(aspectElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_ASPECT)).aspectRatioElementConfig
		aspectElement.dimensions.height = ((cast(f32)(1) / config.aspectRatio) * aspectElement.dimensions.width)
		aspectElement.layoutConfig.sizing.height.constraints.sizeMinMax.max = aspectElement.dimensions.height
	}
	// Propagate effect of text wrapping, aspect scaling etc. on height of parents
	dfsBuffer: _LayoutElementTreeNodeArray = ctx.layoutElementTreeNodeArray1
	dfsBuffer.length = 0
	for i: i32 = 0; (i < ctx.layoutElementTreeRoots.length); i += 1 {
		root: ^_LayoutElementTreeRoot = _LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, i)
		ctx.treeNodeVisited.internalArray[dfsBuffer.length] = false
		_LayoutElementTreeNodeArray_Add(&dfsBuffer, _LayoutElementTreeNode{layoutElement = LayoutElementArray_Get(&ctx.layoutElements, root.layoutElementIndex)})
	}
	for (dfsBuffer.length > 0) {
		currentElementTreeNode: ^_LayoutElementTreeNode = _LayoutElementTreeNodeArray_Get(&dfsBuffer, (dfsBuffer.length - 1))
		currentElement: ^LayoutElement = currentElementTreeNode.layoutElement
		if !(ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)]) {
			ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] = true
			// If the element has no children or is the container for a text element, don't bother inspecting it
			if ((cast(i32)(_ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) != 0) || (cast(i32)(currentElement.childrenOrTextContent.children.length) == 0)) {
				dfsBuffer.length -= 1
				continue
			}
			// Add the children to the DFS buffer (needs to be pushed in reverse so that stack traversal is in correct layout order)
			for i: i32 = 0; (i < cast(i32)(currentElement.childrenOrTextContent.children.length)); i += 1 {
				ctx.treeNodeVisited.internalArray[dfsBuffer.length] = false
				_LayoutElementTreeNodeArray_Add(&dfsBuffer, _LayoutElementTreeNode{layoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])})
			}
			continue
		}
		dfsBuffer.length -= 1
		// DFS node has been visited, this is on the way back up to the root
		layoutConfig: ^LayoutConfig = currentElement.layoutConfig
		if (cast(i32)(layoutConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT) {
			// Resize any parent containers that have grown in height along their non layout axis
			for j: i32 = 0; (j < cast(i32)(currentElement.childrenOrTextContent.children.length)); j += 1 {
				childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[j])
				childHeightWithPadding: f32 = _max(((childElement.dimensions.height + cast(f32)(cast(i32)(layoutConfig.padding.top))) + cast(f32)(cast(i32)(layoutConfig.padding.bottom))), currentElement.dimensions.height)
				currentElement.dimensions.height = _min(_max(childHeightWithPadding, layoutConfig.sizing.height.constraints.sizeMinMax.min), layoutConfig.sizing.height.constraints.sizeMinMax.max)
			}
		} else {
			if (cast(i32)(layoutConfig.layoutDirection) == CLAY_TOP_TO_BOTTOM) {
				// Resizing along the layout axis
				contentHeight: f32 = cast(f32)((cast(i32)(layoutConfig.padding.top) + cast(i32)(layoutConfig.padding.bottom)))
				for j: i32 = 0; (j < cast(i32)(currentElement.childrenOrTextContent.children.length)); j += 1 {
					childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[j])
					contentHeight += childElement.dimensions.height
				}
				contentHeight += cast(f32)((_max((cast(i32)(currentElement.childrenOrTextContent.children.length) - 1), 0) * cast(i32)(layoutConfig.childGap)))
				currentElement.dimensions.height = _min(_max(contentHeight, layoutConfig.sizing.height.constraints.sizeMinMax.min), layoutConfig.sizing.height.constraints.sizeMinMax.max)
			}
		}
	}
	// Calculate sizing along the Y axis
	_SizeContainersAlongAxis(false)
	// Scale horizontal widths according to aspect ratio
	for i: i32 = 0; (i < ctx.aspectRatioElementIndexes.length); i += 1 {
		aspectElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, _int32_tArray_GetValue(&ctx.aspectRatioElementIndexes, i))
		config: ^AspectRatioElementConfig = _FindElementConfigWithType(aspectElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_ASPECT)).aspectRatioElementConfig
		aspectElement.dimensions.width = (config.aspectRatio * aspectElement.dimensions.height)
	}
	// Sort tree roots by z-index
	sortMax: i32 = (ctx.layoutElementTreeRoots.length - 1)
	for (sortMax > 0) {
		for i: i32 = 0; (i < sortMax); i += 1 {
			current: _LayoutElementTreeRoot = (_LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, i))^
			next: _LayoutElementTreeRoot = (_LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, (i + 1)))^
			if (cast(i32)(next.zIndex) < cast(i32)(current.zIndex)) {
				_LayoutElementTreeRootArray_Set(&ctx.layoutElementTreeRoots, i, next)
				_LayoutElementTreeRootArray_Set(&ctx.layoutElementTreeRoots, (i + 1), current)
			}
		}
		sortMax -= 1
	}
	// Calculate final positions and generate render commands
	ctx.renderCommands.length = 0
	dfsBuffer.length = 0
	for rootIndex: i32 = 0; (rootIndex < ctx.layoutElementTreeRoots.length); rootIndex += 1 {
		dfsBuffer.length = 0
		root: ^_LayoutElementTreeRoot = _LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, rootIndex)
		rootElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, root.layoutElementIndex)
		rootPosition: Vector2 = Vector2{cast(f32)(0), 0}
		parentHashMapItem: ^LayoutElementHashMapItem = _GetHashMapItem(root.parentId)
		// Position root floating containers
		if ((cast(i32)(_ElementHasConfig(rootElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING))) != 0) && (parentHashMapItem != nil)) {
			config: ^FloatingElementConfig = _FindElementConfigWithType(rootElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING)).floatingElementConfig
			rootDimensions: Dimensions = rootElement.dimensions
			parentBoundingBox: BoundingBox = parentHashMapItem.boundingBox
			// Set X position
			targetAttachPosition: Vector2 = Vector2{cast(f32)(0), 0}
			switch cast(i32)(config.attachment.parent) {
			case CLAY_ATTACH_POINT_LEFT_TOP, CLAY_ATTACH_POINT_LEFT_CENTER, CLAY_ATTACH_POINT_LEFT_BOTTOM:
				(targetAttachPosition)[0] = parentBoundingBox.x
				break
			case CLAY_ATTACH_POINT_CENTER_TOP, CLAY_ATTACH_POINT_CENTER_CENTER, CLAY_ATTACH_POINT_CENTER_BOTTOM:
				(targetAttachPosition)[0] = (parentBoundingBox.x + (parentBoundingBox.width / cast(f32)(2)))
				break
			case CLAY_ATTACH_POINT_RIGHT_TOP, CLAY_ATTACH_POINT_RIGHT_CENTER, CLAY_ATTACH_POINT_RIGHT_BOTTOM:
				(targetAttachPosition)[0] = (parentBoundingBox.x + parentBoundingBox.width)
				break
			}
			switch cast(i32)(config.attachment.element) {
			case CLAY_ATTACH_POINT_LEFT_TOP, CLAY_ATTACH_POINT_LEFT_CENTER, CLAY_ATTACH_POINT_LEFT_BOTTOM:
				break
			case CLAY_ATTACH_POINT_CENTER_TOP, CLAY_ATTACH_POINT_CENTER_CENTER, CLAY_ATTACH_POINT_CENTER_BOTTOM:
				(targetAttachPosition)[0] -= (rootDimensions.width / cast(f32)(2))
				break
			case CLAY_ATTACH_POINT_RIGHT_TOP, CLAY_ATTACH_POINT_RIGHT_CENTER, CLAY_ATTACH_POINT_RIGHT_BOTTOM:
				(targetAttachPosition)[0] -= rootDimensions.width
				break
			}
			switch cast(i32)(config.attachment.parent) {
			case CLAY_ATTACH_POINT_LEFT_TOP, CLAY_ATTACH_POINT_RIGHT_TOP, CLAY_ATTACH_POINT_CENTER_TOP:
				(targetAttachPosition)[1] = parentBoundingBox.y
				break
			case CLAY_ATTACH_POINT_LEFT_CENTER, CLAY_ATTACH_POINT_CENTER_CENTER, CLAY_ATTACH_POINT_RIGHT_CENTER:
				(targetAttachPosition)[1] = (parentBoundingBox.y + (parentBoundingBox.height / cast(f32)(2)))
				break
			case CLAY_ATTACH_POINT_LEFT_BOTTOM, CLAY_ATTACH_POINT_CENTER_BOTTOM, CLAY_ATTACH_POINT_RIGHT_BOTTOM:
				(targetAttachPosition)[1] = (parentBoundingBox.y + parentBoundingBox.height)
				break
			}
			switch cast(i32)(config.attachment.element) {
			case CLAY_ATTACH_POINT_LEFT_TOP, CLAY_ATTACH_POINT_RIGHT_TOP, CLAY_ATTACH_POINT_CENTER_TOP:
				break
			case CLAY_ATTACH_POINT_LEFT_CENTER, CLAY_ATTACH_POINT_CENTER_CENTER, CLAY_ATTACH_POINT_RIGHT_CENTER:
				(targetAttachPosition)[1] -= (rootDimensions.height / cast(f32)(2))
				break
			case CLAY_ATTACH_POINT_LEFT_BOTTOM, CLAY_ATTACH_POINT_CENTER_BOTTOM, CLAY_ATTACH_POINT_RIGHT_BOTTOM:
				(targetAttachPosition)[1] -= rootDimensions.height
				break
			}
			(targetAttachPosition)[0] += (config.offset)[0]
			(targetAttachPosition)[1] += (config.offset)[1]
			rootPosition = targetAttachPosition
		}
		if (root.clipElementId != 0) {
			clipHashMapItem: ^LayoutElementHashMapItem = _GetHashMapItem(root.clipElementId)
			if (clipHashMapItem != nil) {
				// Floating elements that are attached to scrolling contents won't be correctly positioned if external scroll handling is enabled, fix here
				if ctx.externalScrollHandlingEnabled {
					clipConfig: ^ClipElementConfig = _FindElementConfigWithType(clipHashMapItem.layoutElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
					if clipConfig.horizontal {
						(rootPosition)[0] += (clipConfig.childOffset)[0]
					}
					if clipConfig.vertical {
						(rootPosition)[1] += (clipConfig.childOffset)[1]
					}
					break
				}
				_AddRenderCommand(RenderCommand{boundingBox = clipHashMapItem.boundingBox, userData = nil, id = _HashNumber(rootElement.id, cast(u32)((cast(i32)(rootElement.childrenOrTextContent.children.length) + 10))).id, zIndex = root.zIndex, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_SCISSOR_START)})
			}
		}
		_LayoutElementTreeNodeArray_Add(&dfsBuffer, _LayoutElementTreeNode{layoutElement = rootElement, position = rootPosition, nextChildOffset = Vector2{cast(f32)(rootElement.layoutConfig.padding.left), cast(f32)(rootElement.layoutConfig.padding.top)}})
		ctx.treeNodeVisited.internalArray[0] = false
		for (dfsBuffer.length > 0) {
			currentElementTreeNode: ^_LayoutElementTreeNode = _LayoutElementTreeNodeArray_Get(&dfsBuffer, (dfsBuffer.length - 1))
			currentElement: ^LayoutElement = currentElementTreeNode.layoutElement
			layoutConfig: ^LayoutConfig = currentElement.layoutConfig
			scrollOffset: Vector2 = Vector2{cast(f32)(0), 0}
			// This will only be run a single time for each element in downwards DFS order
			if !(ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)]) {
				ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] = true
				currentElementBoundingBox: BoundingBox = BoundingBox{x = (currentElementTreeNode.position)[0], y = (currentElementTreeNode.position)[1], width = currentElement.dimensions.width, height = currentElement.dimensions.height}
				if _ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING)) {
					floatingElementConfig: ^FloatingElementConfig = _FindElementConfigWithType(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_FLOATING)).floatingElementConfig
					expand: Dimensions = floatingElementConfig.expand
					currentElementBoundingBox.x -= expand.width
					currentElementBoundingBox.width += (expand.width * cast(f32)(2))
					currentElementBoundingBox.y -= expand.height
					currentElementBoundingBox.height += (expand.height * cast(f32)(2))
				}
				scrollContainerData: ^_ScrollContainerDataInternal = nil
				// Apply scroll offsets to container
				if _ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)) {
					clipConfig: ^ClipElementConfig = _FindElementConfigWithType(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
					// This linear scan could theoretically be slow under very strange conditions, but I can't imagine a real UI with more than a few 10's of scroll containers
					for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
						mapping: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
						if (mapping.layoutElement == currentElement) {
							scrollContainerData = mapping
							mapping.boundingBox = currentElementBoundingBox
							scrollOffset = clipConfig.childOffset
							if ctx.externalScrollHandlingEnabled {
								scrollOffset = Vector2{cast(f32)(0), 0}
							}
							break
						}
					}
				}
				hashMapItem: ^LayoutElementHashMapItem = _GetHashMapItem(currentElement.id)
				if (hashMapItem != nil) {
					hashMapItem.boundingBox = currentElementBoundingBox
					if (hashMapItem.idAlias != 0) {
						hashMapItemAlias: ^LayoutElementHashMapItem = _GetHashMapItem(hashMapItem.idAlias)
						if (hashMapItemAlias != nil) {
							hashMapItemAlias.boundingBox = currentElementBoundingBox
						}
					}
				}
				sortedConfigIndexes: [20]i32
				for elementConfigIndex: i32 = 0; (elementConfigIndex < currentElement.elementConfigs.length); elementConfigIndex += 1 {
					(cast([^]i32)(&(sortedConfigIndexes)[0]))[elementConfigIndex] = elementConfigIndex
				}
				sortMax = (currentElement.elementConfigs.length - 1)
				for (sortMax > 0) {
					for i: i32 = 0; (i < sortMax); i += 1 {
						current: i32 = (cast([^]i32)(&(sortedConfigIndexes)[0]))[i]
						next: i32 = (cast([^]i32)(&(sortedConfigIndexes)[0]))[(i + 1)]
						currentType: _ElementConfigType = _ElementConfigArraySlice_Get(&currentElement.elementConfigs, current).type
						nextType: _ElementConfigType = _ElementConfigArraySlice_Get(&currentElement.elementConfigs, next).type
						if ((cast(i32)(nextType) == CLAY__ELEMENT_CONFIG_TYPE_CLIP) || (cast(i32)(currentType) == CLAY__ELEMENT_CONFIG_TYPE_BORDER)) {
							(cast([^]i32)(&(sortedConfigIndexes)[0]))[i] = next
							(cast([^]i32)(&(sortedConfigIndexes)[0]))[(i + 1)] = current
						}
					}
					sortMax -= 1
				}
				emitRectangle: bool = false
				// Create the render commands for this element
				sharedConfig: ^SharedElementConfig = _FindElementConfigWithType(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_SHARED)).sharedElementConfig
				if ((sharedConfig != nil) && ((sharedConfig.backgroundColor)[3] > cast(f32)(0))) {
					emitRectangle = true
				} else {
					if !((sharedConfig != nil)) {
						emitRectangle = false
						sharedConfig = &SharedElementConfig_DEFAULT
					}
				}
				for elementConfigIndex: i32 = 0; (elementConfigIndex < currentElement.elementConfigs.length); elementConfigIndex += 1 {
					elementConfig: ^ElementConfig = _ElementConfigArraySlice_Get(&currentElement.elementConfigs, (cast([^]i32)(&(sortedConfigIndexes)[0]))[elementConfigIndex])
					renderCommand: RenderCommand = RenderCommand{boundingBox = currentElementBoundingBox, userData = sharedConfig.userData, id = currentElement.id}
					offscreen: bool = _ElementIsOffscreen(&currentElementBoundingBox)
					shouldRender: bool = !(offscreen)
					switch cast(i32)(elementConfig.type) {
					case CLAY__ELEMENT_CONFIG_TYPE_ASPECT, CLAY__ELEMENT_CONFIG_TYPE_FLOATING, CLAY__ELEMENT_CONFIG_TYPE_SHARED, CLAY__ELEMENT_CONFIG_TYPE_BORDER:
						shouldRender = false
						break
					case CLAY__ELEMENT_CONFIG_TYPE_CLIP:
						renderCommand.commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_SCISSOR_START)
						renderCommand.renderData = RenderCommandData{clip = ClipRenderData{horizontal = elementConfig.config.clipElementConfig.horizontal, vertical = elementConfig.config.clipElementConfig.vertical}}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_IMAGE:
						renderCommand.commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_IMAGE)
						renderCommand.renderData = RenderCommandData{image = ImageRenderData{backgroundColor = sharedConfig.backgroundColor, cornerRadius = sharedConfig.cornerRadius, imageData = elementConfig.config.imageElementConfig.imageData}}
						emitRectangle = false
						break
					case CLAY__ELEMENT_CONFIG_TYPE_TEXT:
						if !(shouldRender) {
							break
						}
						shouldRender = false
						configUnion: ElementConfigUnion = elementConfig.config
						textElementConfig: ^TextElementConfig = configUnion.textElementConfig
						naturalLineHeight: f32 = currentElement.childrenOrTextContent.textElementData.preferredDimensions.height
						finalLineHeight: f32 = ((cast(i32)(textElementConfig.lineHeight) > 0) ? cast(f32)(textElementConfig.lineHeight) : naturalLineHeight)
						lineHeightOffset: f32 = ((finalLineHeight - naturalLineHeight) / cast(f32)(2))
						yPosition: f32 = lineHeightOffset
						for lineIndex: i32 = 0; (lineIndex < currentElement.childrenOrTextContent.textElementData.wrappedLines.length); lineIndex += 1 {
							wrappedLine: ^_WrappedTextLine = _WrappedTextLineArraySlice_Get(&currentElement.childrenOrTextContent.textElementData.wrappedLines, lineIndex)
							if (wrappedLine.line.length == 0) {
								yPosition += finalLineHeight
								continue
							}
							offset: f32 = (currentElementBoundingBox.width - wrappedLine.dimensions.width)
							if (cast(i32)(textElementConfig.textAlignment) == CLAY_TEXT_ALIGN_LEFT) {
								offset = cast(f32)(0)
							}
							if (cast(i32)(textElementConfig.textAlignment) == CLAY_TEXT_ALIGN_CENTER) {
								offset /= cast(f32)(2)
							}
							_AddRenderCommand(RenderCommand{boundingBox = BoundingBox{x = (currentElementBoundingBox.x + offset), y = (currentElementBoundingBox.y + yPosition), width = wrappedLine.dimensions.width, height = wrappedLine.dimensions.height}, renderData = RenderCommandData{text = TextRenderData{stringContents = StringSlice{length = wrappedLine.line.length, chars = wrappedLine.line.chars, baseChars = currentElement.childrenOrTextContent.textElementData.text.chars}, textColor = textElementConfig.textColor, fontId = textElementConfig.fontId, fontSize = textElementConfig.fontSize, letterSpacing = textElementConfig.letterSpacing, lineHeight = textElementConfig.lineHeight}}, userData = textElementConfig.userData, id = _HashNumber(cast(u32)(lineIndex), currentElement.id).id, zIndex = root.zIndex, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_TEXT)})
							yPosition += finalLineHeight
							if (!(ctx.disableCulling) && ((currentElementBoundingBox.y + yPosition) > ctx.layoutDimensions.height)) {
								break
							}
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_CUSTOM:
						renderCommand.commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_CUSTOM)
						renderCommand.renderData = RenderCommandData{custom = CustomRenderData{backgroundColor = sharedConfig.backgroundColor, cornerRadius = sharedConfig.cornerRadius, customData = elementConfig.config.customElementConfig.customData}}
						emitRectangle = false
						break
					case:
						break
					}
					if shouldRender {
						_AddRenderCommand(renderCommand)
					}
					if offscreen {
					}
				}
				if emitRectangle {
					_AddRenderCommand(RenderCommand{boundingBox = currentElementBoundingBox, renderData = RenderCommandData{rectangle = RectangleRenderData{backgroundColor = sharedConfig.backgroundColor, cornerRadius = sharedConfig.cornerRadius}}, userData = sharedConfig.userData, id = currentElement.id, zIndex = root.zIndex, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_RECTANGLE)})
				}
				// Setup initial on-axis alignment
				if !(_ElementHasConfig(currentElementTreeNode.layoutElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) {
					contentSize: Dimensions = Dimensions{width = cast(f32)(0), height = cast(f32)(0)}
					if (cast(i32)(layoutConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT) {
						for i: i32 = 0; (i < cast(i32)(currentElement.childrenOrTextContent.children.length)); i += 1 {
							childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
							contentSize.width += childElement.dimensions.width
							contentSize.height = _max(contentSize.height, childElement.dimensions.height)
						}
						contentSize.width += cast(f32)((_max((cast(i32)(currentElement.childrenOrTextContent.children.length) - 1), 0) * cast(i32)(layoutConfig.childGap)))
						extraSpace: f32 = ((currentElement.dimensions.width - cast(f32)((cast(i32)(layoutConfig.padding.left) + cast(i32)(layoutConfig.padding.right)))) - contentSize.width)
						switch cast(i32)(layoutConfig.childAlignment.x) {
						case CLAY_ALIGN_X_LEFT:
							extraSpace = cast(f32)(0)
							break
						case CLAY_ALIGN_X_CENTER:
							extraSpace /= cast(f32)(2)
							break
						case:
							break
						}
						(currentElementTreeNode.nextChildOffset)[0] += extraSpace
					} else {
						for i: i32 = 0; (i < cast(i32)(currentElement.childrenOrTextContent.children.length)); i += 1 {
							childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
							contentSize.width = _max(contentSize.width, childElement.dimensions.width)
							contentSize.height += childElement.dimensions.height
						}
						contentSize.height += cast(f32)((_max((cast(i32)(currentElement.childrenOrTextContent.children.length) - 1), 0) * cast(i32)(layoutConfig.childGap)))
						extraSpace: f32 = ((currentElement.dimensions.height - cast(f32)((cast(i32)(layoutConfig.padding.top) + cast(i32)(layoutConfig.padding.bottom)))) - contentSize.height)
						switch cast(i32)(layoutConfig.childAlignment.y) {
						case CLAY_ALIGN_Y_TOP:
							extraSpace = cast(f32)(0)
							break
						case CLAY_ALIGN_Y_CENTER:
							extraSpace /= cast(f32)(2)
							break
						case:
							break
						}
						(currentElementTreeNode.nextChildOffset)[1] += extraSpace
					}
					if (scrollContainerData != nil) {
						scrollContainerData.contentSize = Dimensions{width = (contentSize.width + cast(f32)((cast(i32)(layoutConfig.padding.left) + cast(i32)(layoutConfig.padding.right)))), height = (contentSize.height + cast(f32)((cast(i32)(layoutConfig.padding.top) + cast(i32)(layoutConfig.padding.bottom))))}
					}
				}
			} else {
				closeClipElement: bool = false
				clipConfig: ^ClipElementConfig = _FindElementConfigWithType(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_CLIP)).clipElementConfig
				if (clipConfig != nil) {
					closeClipElement = true
					for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
						mapping: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
						if (mapping.layoutElement == currentElement) {
							scrollOffset = clipConfig.childOffset
							if ctx.externalScrollHandlingEnabled {
								scrollOffset = Vector2{cast(f32)(0), 0}
							}
							break
						}
					}
				}
				if _ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_BORDER)) {
					currentElementData: ^LayoutElementHashMapItem = _GetHashMapItem(currentElement.id)
					currentElementBoundingBox: BoundingBox = currentElementData.boundingBox
					// Culling - Don't bother to generate render commands for rectangles entirely outside the screen - this won't stop their children from being rendered if they overflow
					if !(_ElementIsOffscreen(&currentElementBoundingBox)) {
						sharedConfig: ^SharedElementConfig = ((cast(i32)(_ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_SHARED))) != 0) ? _FindElementConfigWithType(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_SHARED)).sharedElementConfig : &SharedElementConfig_DEFAULT)
						borderConfig: ^BorderElementConfig = _FindElementConfigWithType(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_BORDER)).borderElementConfig
						renderCommand: RenderCommand = RenderCommand{boundingBox = currentElementBoundingBox, renderData = RenderCommandData{border = BorderRenderData{color = borderConfig.color, cornerRadius = sharedConfig.cornerRadius, width = borderConfig.width}}, userData = sharedConfig.userData, id = _HashNumber(currentElement.id, cast(u32)(currentElement.childrenOrTextContent.children.length)).id, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_BORDER)}
						_AddRenderCommand(renderCommand)
						if ((cast(i32)(borderConfig.width.betweenChildren) > 0) && ((borderConfig.color)[3] > cast(f32)(0))) {
							halfGap: f32 = cast(f32)((cast(i32)(layoutConfig.childGap) / 2))
							borderOffset: Vector2 = Vector2{(cast(f32)(layoutConfig.padding.left) - halfGap), (cast(f32)(layoutConfig.padding.top) - halfGap)}
							if (cast(i32)(layoutConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT) {
								for i: i32 = 0; (i < cast(i32)(currentElement.childrenOrTextContent.children.length)); i += 1 {
									childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
									if (i > 0) {
										_AddRenderCommand(RenderCommand{boundingBox = BoundingBox{x = ((currentElementBoundingBox.x + (borderOffset)[0]) + (scrollOffset)[0]), y = (currentElementBoundingBox.y + (scrollOffset)[1]), width = cast(f32)(borderConfig.width.betweenChildren), height = currentElement.dimensions.height}, renderData = RenderCommandData{rectangle = RectangleRenderData{backgroundColor = borderConfig.color}}, userData = sharedConfig.userData, id = _HashNumber(currentElement.id, cast(u32)(((cast(i32)(currentElement.childrenOrTextContent.children.length) + 1) + i))).id, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_RECTANGLE)})
									}
									(borderOffset)[0] += (childElement.dimensions.width + cast(f32)(layoutConfig.childGap))
								}
							} else {
								for i: i32 = 0; (i < cast(i32)(currentElement.childrenOrTextContent.children.length)); i += 1 {
									childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
									if (i > 0) {
										_AddRenderCommand(RenderCommand{boundingBox = BoundingBox{x = (currentElementBoundingBox.x + (scrollOffset)[0]), y = ((currentElementBoundingBox.y + (borderOffset)[1]) + (scrollOffset)[1]), width = currentElement.dimensions.width, height = cast(f32)(borderConfig.width.betweenChildren)}, renderData = RenderCommandData{rectangle = RectangleRenderData{backgroundColor = borderConfig.color}}, userData = sharedConfig.userData, id = _HashNumber(currentElement.id, cast(u32)(((cast(i32)(currentElement.childrenOrTextContent.children.length) + 1) + i))).id, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_RECTANGLE)})
									}
									(borderOffset)[1] += (childElement.dimensions.height + cast(f32)(layoutConfig.childGap))
								}
							}
						}
					}
				}
				// This exists because the scissor needs to end _after_ borders between elements
				if closeClipElement {
					_AddRenderCommand(RenderCommand{id = _HashNumber(currentElement.id, cast(u32)((cast(i32)(rootElement.childrenOrTextContent.children.length) + 11))).id, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_SCISSOR_END)})
				}
				dfsBuffer.length -= 1
				continue
			}
			// Add children to the DFS buffer
			if !(_ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) {
				dfsBuffer.length += cast(i32)(currentElement.childrenOrTextContent.children.length)
				for i: i32 = 0; (i < cast(i32)(currentElement.childrenOrTextContent.children.length)); i += 1 {
					childElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
					// Alignment along non layout axis
					if (cast(i32)(layoutConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT) {
						(currentElementTreeNode.nextChildOffset)[1] = cast(f32)(currentElement.layoutConfig.padding.top)
						whiteSpaceAroundChild: f32 = ((currentElement.dimensions.height - cast(f32)((cast(i32)(layoutConfig.padding.top) + cast(i32)(layoutConfig.padding.bottom)))) - childElement.dimensions.height)
						switch cast(i32)(layoutConfig.childAlignment.y) {
						case CLAY_ALIGN_Y_TOP:
							break
						case CLAY_ALIGN_Y_CENTER:
							(currentElementTreeNode.nextChildOffset)[1] += (whiteSpaceAroundChild / cast(f32)(2))
							break
						case CLAY_ALIGN_Y_BOTTOM:
							(currentElementTreeNode.nextChildOffset)[1] += whiteSpaceAroundChild
							break
						}
					} else {
						(currentElementTreeNode.nextChildOffset)[0] = cast(f32)(currentElement.layoutConfig.padding.left)
						whiteSpaceAroundChild: f32 = ((currentElement.dimensions.width - cast(f32)((cast(i32)(layoutConfig.padding.left) + cast(i32)(layoutConfig.padding.right)))) - childElement.dimensions.width)
						switch cast(i32)(layoutConfig.childAlignment.x) {
						case CLAY_ALIGN_X_LEFT:
							break
						case CLAY_ALIGN_X_CENTER:
							(currentElementTreeNode.nextChildOffset)[0] += (whiteSpaceAroundChild / cast(f32)(2))
							break
						case CLAY_ALIGN_X_RIGHT:
							(currentElementTreeNode.nextChildOffset)[0] += whiteSpaceAroundChild
							break
						}
					}
					childPosition: Vector2 = Vector2{(((currentElementTreeNode.position)[0] + (currentElementTreeNode.nextChildOffset)[0]) + (scrollOffset)[0]), (((currentElementTreeNode.position)[1] + (currentElementTreeNode.nextChildOffset)[1]) + (scrollOffset)[1])}
					// DFS buffer elements need to be added in reverse because stack traversal happens backwards
					newNodeIndex: u32 = cast(u32)(((dfsBuffer.length - 1) - i))
					dfsBuffer.internalArray[newNodeIndex] = _LayoutElementTreeNode{layoutElement = childElement, position = Vector2{(childPosition)[0], (childPosition)[1]}, nextChildOffset = Vector2{cast(f32)(childElement.layoutConfig.padding.left), cast(f32)(childElement.layoutConfig.padding.top)}}
					ctx.treeNodeVisited.internalArray[newNodeIndex] = false
					// Update parent offsets
					if (cast(i32)(layoutConfig.layoutDirection) == CLAY_LEFT_TO_RIGHT) {
						(currentElementTreeNode.nextChildOffset)[0] += (childElement.dimensions.width + cast(f32)(layoutConfig.childGap))
					} else {
						(currentElementTreeNode.nextChildOffset)[1] += (childElement.dimensions.height + cast(f32)(layoutConfig.childGap))
					}
				}
			}
		}
		if (root.clipElementId != 0) {
			_AddRenderCommand(RenderCommand{id = _HashNumber(rootElement.id, cast(u32)((cast(i32)(rootElement.childrenOrTextContent.children.length) + 11))).id, commandType = cast(RenderCommandType)(CLAY_RENDER_COMMAND_TYPE_SCISSOR_END)})
		}
	}
}

// clay.h:3095 — Clay_GetPointerOverIds
GetPointerOverIds :: proc "c" () -> ElementIdArray {
	return GetCurrentContext().pointerOverIds
}
