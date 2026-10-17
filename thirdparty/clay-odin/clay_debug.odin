// Pure Odin port of Clay v0.14 (b25a31c1a152915cd7dd6796e6592273e5a10aac).
// Copyright (c) 2024 Nic Barker. Altered source; see LICENSE.md and README.md.
package clay

// clay.h:3116 — Clay__DebugGetElementConfigTypeLabel
@(private)
_DebugGetElementConfigTypeLabel :: proc "c" (kind: _ElementConfigType) -> _DebugElementConfigTypeLabelConfig {
	switch cast(i32)(kind) {
	case CLAY__ELEMENT_CONFIG_TYPE_SHARED:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Shared"), color = Color{cast(f32)(243), cast(f32)(134), cast(f32)(48), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_TEXT:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Text"), color = Color{cast(f32)(105), cast(f32)(210), cast(f32)(231), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_ASPECT:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Aspect"), color = Color{cast(f32)(101), cast(f32)(149), cast(f32)(194), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_IMAGE:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Image"), color = Color{cast(f32)(121), cast(f32)(189), cast(f32)(154), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_FLOATING:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Floating"), color = Color{cast(f32)(250), cast(f32)(105), cast(f32)(0), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_CLIP:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Scroll"), color = Color{cast(f32)(242), cast(f32)(196), cast(f32)(90), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_BORDER:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Border"), color = Color{cast(f32)(108), cast(f32)(91), cast(f32)(123), cast(f32)(255)}}
	case CLAY__ELEMENT_CONFIG_TYPE_CUSTOM:
		return _DebugElementConfigTypeLabelConfig{label = _static_string("Custom"), color = Color{cast(f32)(11), cast(f32)(72), cast(f32)(107), cast(f32)(255)}}
	case:
		break
	}
	return _DebugElementConfigTypeLabelConfig{label = _static_string("Error"), color = Color{cast(f32)(0), cast(f32)(0), cast(f32)(0), cast(f32)(255)}}
}

// clay.h:3137 — Clay__RenderDebugLayoutElementsList
@(private)
_RenderDebugLayoutElementsList :: proc "c" (initialRootsLength: i32, highlightedRowIndex: i32) -> _RenderDebugLayoutData {
	ctx: ^Context = GetCurrentContext()
	dfsBuffer: _int32_tArray = ctx.reusableElementIndexBuffer
	_DebugView_ScrollViewItemLayoutConfig = LayoutConfig{sizing = Sizing{height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, childGap = cast(u16)(6), childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}
	layoutData: _RenderDebugLayoutData = _RenderDebugLayoutData{rowCount = 0}
	highlightedElementId: u32 = cast(u32)(0)
	for rootIndex: i32 = 0; (rootIndex < initialRootsLength); rootIndex += 1 {
		dfsBuffer.length = 0
		root: ^_LayoutElementTreeRoot = _LayoutElementTreeRootArray_Get(&ctx.layoutElementTreeRoots, rootIndex)
		_int32_tArray_Add(&dfsBuffer, root.layoutElementIndex)
		ctx.treeNodeVisited.internalArray[0] = false
		if (rootIndex > 0) {
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView_EmptyRowOuter"), cast(u32)(rootIndex), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}, padding = Padding{left = cast(u16)((CLAY__DEBUGVIEW_INDENT_WIDTH / 2)), right = cast(u16)(0), top = cast(u16)(0), bottom = cast(u16)(0)}}}}.wrapped)
				defer _CloseElement()
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView_EmptyRow"), cast(u32)(rootIndex), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_3, width = BorderWidth{top = cast(u16)(1)}}}}.wrapped)
					defer _CloseElement()
				}
			}
			layoutData.rowCount += 1
		}
		for (dfsBuffer.length > 0) {
			currentElementIndex: i32 = _int32_tArray_GetValue(&dfsBuffer, (dfsBuffer.length - 1))
			currentElement: ^LayoutElement = LayoutElementArray_Get(&ctx.layoutElements, currentElementIndex)
			if ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] {
				if (!(_ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) && (cast(i32)(currentElement.childrenOrTextContent.children.length) > 0)) {
					_CloseElement()
					_CloseElement()
					_CloseElement()
				}
				dfsBuffer.length -= 1
				continue
			}
			if (highlightedRowIndex == layoutData.rowCount) {
				if (cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
					ctx.debugSelectedElementId = currentElement.id
				}
				highlightedElementId = currentElement.id
			}
			ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] = true
			currentElementData: ^LayoutElementHashMapItem = _GetHashMapItem(currentElement.id)
			offscreen: bool = _ElementIsOffscreen(&currentElementData.boundingBox)
			if (ctx.debugSelectedElementId == currentElement.id) {
				layoutData.selectedElementRowIndex = layoutData.rowCount
			}
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView_ElementOuter"), currentElement.id, cast(u32)(0)), layout = _DebugView_ScrollViewItemLayoutConfig}}.wrapped)
				defer _CloseElement()
				// Collapse icon / button
				if !(((cast(i32)(_ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) != 0) || (cast(i32)(currentElement.childrenOrTextContent.children.length) == 0))) {
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView_CollapseElement"), currentElement.id, cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(16), max = cast(f32)(16)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(16), max = cast(f32)(16)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, childAlignment = ChildAlignment{x = cast(LayoutAlignmentX)(CLAY_ALIGN_X_CENTER), y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_3, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement((((currentElementData != nil) && (cast(i32)(currentElementData.debugData.collapsed) != 0)) ? _static_string("+") : _static_string("-")), _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_4, fontSize = cast(u16)(16)}}.wrapped))
					}
				} else {
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(16), max = cast(f32)(16)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(16), max = cast(f32)(16)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, childAlignment = ChildAlignment{x = cast(LayoutAlignmentX)(CLAY_ALIGN_X_CENTER), y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
						defer _CloseElement()
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(8), max = cast(f32)(8)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(8), max = cast(f32)(8)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}, backgroundColor = CLAY__DEBUGVIEW_COLOR_3, cornerRadius = CornerRadius{topLeft = cast(f32)(2), topRight = cast(f32)(2), bottomLeft = cast(f32)(2), bottomRight = cast(f32)(2)}}}.wrapped)
							defer _CloseElement()
						}
					}
				}
				// Collisions and offscreen info
				if (currentElementData != nil) {
					if currentElementData.debugData.collision {
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8), right = cast(u16)(8), top = cast(u16)(2), bottom = cast(u16)(2)}}, border = BorderElementConfig{color = Color{cast(f32)(177), cast(f32)(147), cast(f32)(8), cast(f32)(255)}, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Duplicate ID"), _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_3, fontSize = cast(u16)(16)}}.wrapped))
						}
					}
					if offscreen {
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8), right = cast(u16)(8), top = cast(u16)(2), bottom = cast(u16)(2)}}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_3, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Offscreen"), _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_3, fontSize = cast(u16)(16)}}.wrapped))
						}
					}
				}
				idString: String = ctx.layoutElementIdStrings.internalArray[currentElementIndex]
				if (idString.length > 0) {
					_OpenTextElement(idString, ((cast(i32)(offscreen) != 0) ? _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_3, fontSize = cast(u16)(16)}}.wrapped) : &_DebugView_TextNameConfig))
				}
				for elementConfigIndex: i32 = 0; (elementConfigIndex < currentElement.elementConfigs.length); elementConfigIndex += 1 {
					elementConfig: ^ElementConfig = _ElementConfigArraySlice_Get(&currentElement.elementConfigs, elementConfigIndex)
					if (cast(i32)(elementConfig.type) == CLAY__ELEMENT_CONFIG_TYPE_SHARED) {
						labelColor: Color = Color{cast(f32)(243), cast(f32)(134), cast(f32)(48), cast(f32)(90)}
						(labelColor)[3] = cast(f32)(90)
						backgroundColor: Color = elementConfig.config.sharedElementConfig.backgroundColor
						radius: CornerRadius = elementConfig.config.sharedElementConfig.cornerRadius
						if ((backgroundColor)[3] > cast(f32)(0)) {
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8), right = cast(u16)(8), top = cast(u16)(2), bottom = cast(u16)(2)}}, backgroundColor = labelColor, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = labelColor, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
								defer _CloseElement()
								_OpenTextElement(_static_string("Color"), _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = ((cast(i32)(offscreen) != 0) ? CLAY__DEBUGVIEW_COLOR_3 : CLAY__DEBUGVIEW_COLOR_4), fontSize = cast(u16)(16)}}.wrapped))
							}
						}
						if (radius.bottomLeft > cast(f32)(0)) {
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8), right = cast(u16)(8), top = cast(u16)(2), bottom = cast(u16)(2)}}, backgroundColor = labelColor, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = labelColor, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
								defer _CloseElement()
								_OpenTextElement(_static_string("Radius"), _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = ((cast(i32)(offscreen) != 0) ? CLAY__DEBUGVIEW_COLOR_3 : CLAY__DEBUGVIEW_COLOR_4), fontSize = cast(u16)(16)}}.wrapped))
							}
						}
						continue
					}
					config: _DebugElementConfigTypeLabelConfig = _DebugGetElementConfigTypeLabel(elementConfig.type)
					backgroundColor: Color = config.color
					(backgroundColor)[3] = cast(f32)(90)
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8), right = cast(u16)(8), top = cast(u16)(2), bottom = cast(u16)(2)}}, backgroundColor = backgroundColor, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = config.color, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(config.label, _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = ((cast(i32)(offscreen) != 0) ? CLAY__DEBUGVIEW_COLOR_3 : CLAY__DEBUGVIEW_COLOR_4), fontSize = cast(u16)(16)}}.wrapped))
					}
				}
			}
			// Render the text contents below the element as a non-interactive row
			if _ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT)) {
				layoutData.rowCount += 1
				textElementData: ^_TextElementData = currentElement.childrenOrTextContent.textElementData
				rawTextConfig: ^TextElementConfig = ((cast(i32)(offscreen) != 0) ? _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_3, fontSize = cast(u16)(16)}}.wrapped) : &_DebugView_TextNameConfig)
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
					defer _CloseElement()
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)((CLAY__DEBUGVIEW_INDENT_WIDTH + 16)), max = cast(f32)((CLAY__DEBUGVIEW_INDENT_WIDTH + 16))}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}}}.wrapped)
						defer _CloseElement()
					}
					_OpenTextElement(_static_string("\""), rawTextConfig)
					_OpenTextElement(((textElementData.text.length > 40) ? String{length = 40, chars = textElementData.text.chars} : textElementData.text), rawTextConfig)
					if (textElementData.text.length > 40) {
						_OpenTextElement(_static_string("..."), rawTextConfig)
					}
					_OpenTextElement(_static_string("\""), rawTextConfig)
				}
			} else {
				if (cast(i32)(currentElement.childrenOrTextContent.children.length) > 0) {
					_OpenElement()
					_ConfigureOpenElement(ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8)}}})
					_OpenElement()
					_ConfigureOpenElement(ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_INDENT_WIDTH)}}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_3, width = BorderWidth{left = cast(u16)(1)}}})
					_OpenElement()
					_ConfigureOpenElement(ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}})
				}
			}
			layoutData.rowCount += 1
			if !(((cast(i32)(_ElementHasConfig(currentElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_TEXT))) != 0) || ((currentElementData != nil) && (cast(i32)(currentElementData.debugData.collapsed) != 0)))) {
				for i: i32 = (cast(i32)(currentElement.childrenOrTextContent.children.length) - 1); (i >= 0); i -= 1 {
					_int32_tArray_Add(&dfsBuffer, (cast([^]i32)(currentElement.childrenOrTextContent.children.elements))[i])
					ctx.treeNodeVisited.internalArray[(dfsBuffer.length - 1)] = false
				}
			}
		}
	}
	if (cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
		collapseButtonId: ElementId = _HashString(_static_string("Clay__DebugView_CollapseElement"), cast(u32)(0), cast(u32)(0))
		for i: i32 = (ctx.pointerOverIds.length - 1); (i >= 0); i -= 1 {
			elementId: ^ElementId = ElementIdArray_Get(&ctx.pointerOverIds, i)
			if (elementId.baseId == collapseButtonId.baseId) {
				highlightedItem: ^LayoutElementHashMapItem = _GetHashMapItem(elementId.offset)
				highlightedItem.debugData.collapsed = !(highlightedItem.debugData.collapsed)
				break
			}
		}
	}
	if (highlightedElementId != 0) {
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView_ElementHighlight"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}, floating = FloatingElementConfig{parentId = highlightedElementId, zIndex = cast(i16)(32767), pointerCaptureMode = cast(PointerCaptureMode)(CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH), attachTo = cast(FloatingAttachToElement)(CLAY_ATTACH_TO_ELEMENT_WITH_ID)}}}.wrapped)
			defer _CloseElement()
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView_ElementHighlightRectangle"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}, backgroundColor = _debugViewHighlightColor}}.wrapped)
				defer _CloseElement()
			}
		}
	}
	return layoutData
}

// clay.h:3296 — Clay__RenderDebugLayoutSizing
@(private)
_RenderDebugLayoutSizing :: proc "c" (sizing: SizingAxis, infoTextConfig: ^TextElementConfig) {
	sizingLabel: String = _static_string("GROW")
	if (cast(i32)(sizing.type) == CLAY__SIZING_TYPE_FIT) {
		sizingLabel = _static_string("FIT")
	} else {
		if (cast(i32)(sizing.type) == CLAY__SIZING_TYPE_PERCENT) {
			sizingLabel = _static_string("PERCENT")
		} else {
			if (cast(i32)(sizing.type) == CLAY__SIZING_TYPE_FIXED) {
				sizingLabel = _static_string("FIXED")
			}
		}
	}
	_OpenTextElement(sizingLabel, infoTextConfig)
	if (((cast(i32)(sizing.type) == CLAY__SIZING_TYPE_GROW) || (cast(i32)(sizing.type) == CLAY__SIZING_TYPE_FIT)) || (cast(i32)(sizing.type) == CLAY__SIZING_TYPE_FIXED)) {
		_OpenTextElement(_static_string("("), infoTextConfig)
		if (sizing.constraints.sizeMinMax.min != cast(f32)(0)) {
			_OpenTextElement(_static_string("min: "), infoTextConfig)
			_OpenTextElement(_IntToString(cast(i32)(sizing.constraints.sizeMinMax.min)), infoTextConfig)
			if (sizing.constraints.sizeMinMax.max != 3.40282347E+38) {
				_OpenTextElement(_static_string(", "), infoTextConfig)
			}
		}
		if (sizing.constraints.sizeMinMax.max != 3.40282347E+38) {
			_OpenTextElement(_static_string("max: "), infoTextConfig)
			_OpenTextElement(_IntToString(cast(i32)(sizing.constraints.sizeMinMax.max)), infoTextConfig)
		}
		_OpenTextElement(_static_string(")"), infoTextConfig)
	} else {
		if (cast(i32)(sizing.type) == CLAY__SIZING_TYPE_PERCENT) {
			_OpenTextElement(_static_string("("), infoTextConfig)
			_OpenTextElement(_IntToString(cast(i32)((sizing.constraints.sizePercent * cast(f32)(100)))), infoTextConfig)
			_OpenTextElement(_static_string("%)"), infoTextConfig)
		}
	}
}

// clay.h:3327 — Clay__RenderDebugViewElementConfigHeader
@(private)
_RenderDebugViewElementConfigHeader :: proc "c" (elementId: String, kind: _ElementConfigType) {
	config: _DebugElementConfigTypeLabelConfig = _DebugGetElementConfigTypeLabel(kind)
	backgroundColor: Color = config.color
	(backgroundColor)[3] = cast(f32)(90)
	{
		_OpenElement()
		_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}, padding = _Clay_PaddingWrapper{wrapped = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), bottom = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING)}}.wrapped, childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
		defer _CloseElement()
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = Padding{left = cast(u16)(8), right = cast(u16)(8), top = cast(u16)(2), bottom = cast(u16)(2)}}, backgroundColor = backgroundColor, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = config.color, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
			defer _CloseElement()
			_OpenTextElement(config.label, _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_4, fontSize = cast(u16)(16)}}.wrapped))
		}
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}}}.wrapped)
			defer _CloseElement()
		}
		_OpenTextElement(elementId, _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_3, fontSize = cast(u16)(16), wrapMode = cast(TextWrapMode)(CLAY_TEXT_WRAP_NONE)}}.wrapped))
	}
}

// clay.h:3340 — Clay__RenderDebugViewColor
@(private)
_RenderDebugViewColor :: proc "c" (color: Color, textConfig: ^TextElementConfig) {
	{
		_OpenElement()
		_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
		defer _CloseElement()
		_OpenTextElement(_static_string("{ r: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)((color)[0])), textConfig)
		_OpenTextElement(_static_string(", g: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)((color)[1])), textConfig)
		_OpenTextElement(_static_string(", b: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)((color)[2])), textConfig)
		_OpenTextElement(_static_string(", a: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)((color)[3])), textConfig)
		_OpenTextElement(_static_string(" }"), textConfig)
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(10), max = cast(f32)(10)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}}}.wrapped)
			defer _CloseElement()
		}
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 8)), max = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 8))}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 8)), max = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 8))}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}, backgroundColor = color, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_4, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
			defer _CloseElement()
		}
	}
}

// clay.h:3356 — Clay__RenderDebugViewCornerRadius
@(private)
_RenderDebugViewCornerRadius :: proc "c" (cornerRadius: CornerRadius, textConfig: ^TextElementConfig) {
	{
		_OpenElement()
		_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
		defer _CloseElement()
		_OpenTextElement(_static_string("{ topLeft: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)(cornerRadius.topLeft)), textConfig)
		_OpenTextElement(_static_string(", topRight: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)(cornerRadius.topRight)), textConfig)
		_OpenTextElement(_static_string(", bottomLeft: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)(cornerRadius.bottomLeft)), textConfig)
		_OpenTextElement(_static_string(", bottomRight: "), textConfig)
		_OpenTextElement(_IntToString(cast(i32)(cornerRadius.bottomRight)), textConfig)
		_OpenTextElement(_static_string(" }"), textConfig)
	}
}

// clay.h:3370 — HandleDebugViewCloseButtonInteraction
HandleDebugViewCloseButtonInteraction :: proc "c" (elementId: ElementId, pointerInfo: PointerData, userData: rawptr) {
	ctx: ^Context = GetCurrentContext()
	_ = elementId
	_ = pointerInfo
	_ = userData
	if (cast(i32)(pointerInfo.state) == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
		ctx.debugModeEnabled = false
	}
}

// clay.h:3378 — Clay__RenderDebugView
@(private)
_RenderDebugView :: proc "c" () {
	ctx: ^Context = GetCurrentContext()
	closeButtonId: ElementId = _HashString(_static_string("Clay__DebugViewTopHeaderCloseButtonOuter"), cast(u32)(0), cast(u32)(0))
	if (cast(i32)(ctx.pointerInfo.state) == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
		for i: i32 = 0; (i < ctx.pointerOverIds.length); i += 1 {
			elementId: ^ElementId = ElementIdArray_Get(&ctx.pointerOverIds, i)
			if (elementId.id == closeButtonId.id) {
				ctx.debugModeEnabled = false
				return
			}
		}
	}
	initialRootsLength: u32 = cast(u32)(ctx.layoutElementTreeRoots.length)
	initialElementsLength: u32 = cast(u32)(ctx.layoutElements.length)
	infoTextConfig: ^TextElementConfig = _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_4, fontSize = cast(u16)(16), wrapMode = cast(TextWrapMode)(CLAY_TEXT_WRAP_NONE)}}.wrapped)
	infoTitleConfig: ^TextElementConfig = _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_3, fontSize = cast(u16)(16), wrapMode = cast(TextWrapMode)(CLAY_TEXT_WRAP_NONE)}}.wrapped)
	scrollId: ElementId = _HashString(_static_string("Clay__DebugViewOuterScrollPane"), cast(u32)(0), cast(u32)(0))
	scrollYOffset: f32 = cast(f32)(0)
	pointerInDebugView: bool = ((ctx.pointerInfo.position)[1] < (ctx.layoutDimensions.height - cast(f32)(300)))
	for i: i32 = 0; (i < ctx.scrollContainerDatas.length); i += 1 {
		scrollContainerData: ^_ScrollContainerDataInternal = _ScrollContainerDataInternalArray_Get(&ctx.scrollContainerDatas, i)
		if (scrollContainerData.elementId == scrollId.id) {
			if !(ctx.externalScrollHandlingEnabled) {
				scrollYOffset = (scrollContainerData.scrollPosition)[1]
			} else {
				pointerInDebugView = (((ctx.pointerInfo.position)[1] + (scrollContainerData.scrollPosition)[1]) < (ctx.layoutDimensions.height - cast(f32)(300)))
			}
			break
		}
	}
	highlightedRow: i32 = ((cast(i32)(pointerInDebugView) != 0) ? (cast(i32)((((ctx.pointerInfo.position)[1] - scrollYOffset) / cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT))) - 1) : -(1))
	if ((ctx.pointerInfo.position)[0] < (ctx.layoutDimensions.width - cast(f32)(_debugViewWidth))) {
		highlightedRow = -(1)
	}
	layoutData: _RenderDebugLayoutData = _RenderDebugLayoutData{rowCount = 0}
	{
		_OpenElement()
		_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugView"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(_debugViewWidth), max = cast(f32)(_debugViewWidth)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = ctx.layoutDimensions.height, max = ctx.layoutDimensions.height}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}, floating = FloatingElementConfig{zIndex = cast(i16)(32765), attachment = FloatingAttachPoints{element = cast(FloatingAttachPointType)(CLAY_ATTACH_POINT_LEFT_CENTER), parent = cast(FloatingAttachPointType)(CLAY_ATTACH_POINT_RIGHT_CENTER)}, attachTo = cast(FloatingAttachToElement)(CLAY_ATTACH_TO_ROOT), clipTo = cast(FloatingClipToElement)(CLAY_CLIP_TO_ATTACHED_PARENT)}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_3, width = BorderWidth{bottom = cast(u16)(1)}}}}.wrapped)
		defer _CloseElement()
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(0), bottom = cast(u16)(0)}, childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}, backgroundColor = CLAY__DEBUGVIEW_COLOR_2}}.wrapped)
			defer _CloseElement()
			_OpenTextElement(_static_string("Clay Debug Tools"), infoTextConfig)
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}}}.wrapped)
				defer _CloseElement()
			}
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 10)), max = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 10))}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 10)), max = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT - 10))}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, childAlignment = ChildAlignment{x = cast(LayoutAlignmentX)(CLAY_ALIGN_X_CENTER), y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}, backgroundColor = Color{cast(f32)(217), cast(f32)(91), cast(f32)(67), cast(f32)(80)}, cornerRadius = CornerRadius{topLeft = cast(f32)(4), topRight = cast(f32)(4), bottomLeft = cast(f32)(4), bottomRight = cast(f32)(4)}, border = BorderElementConfig{color = Color{cast(f32)(217), cast(f32)(91), cast(f32)(67), cast(f32)(255)}, width = BorderWidth{left = cast(u16)(1), right = cast(u16)(1), top = cast(u16)(1), bottom = cast(u16)(1), betweenChildren = cast(u16)(0)}}}}.wrapped)
				defer _CloseElement()
				OnHover(HandleDebugViewCloseButtonInteraction, nil)
				_OpenTextElement(_static_string("x"), _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_4, fontSize = cast(u16)(16)}}.wrapped))
			}
		}
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(1), max = cast(f32)(1)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}, backgroundColor = CLAY__DEBUGVIEW_COLOR_3}}.wrapped)
			defer _CloseElement()
		}
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = scrollId, layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}, clip = ClipElementConfig{horizontal = true, vertical = true, childOffset = GetScrollOffset()}}}.wrapped)
			defer _CloseElement()
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}, layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}, backgroundColor = ((((initialElementsLength + initialRootsLength) & cast(u32)(1)) == cast(u32)(0)) ? CLAY__DEBUGVIEW_COLOR_2 : CLAY__DEBUGVIEW_COLOR_1)}}.wrapped)
				defer _CloseElement()
				panelContentsId: ElementId = _HashString(_static_string("Clay__DebugViewPaneOuter"), cast(u32)(0), cast(u32)(0))
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = panelContentsId, layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}, floating = FloatingElementConfig{zIndex = cast(i16)(32766), pointerCaptureMode = cast(PointerCaptureMode)(CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH), attachTo = cast(FloatingAttachToElement)(CLAY_ATTACH_TO_PARENT), clipTo = cast(FloatingClipToElement)(CLAY_CLIP_TO_ATTACHED_PARENT)}}}.wrapped)
					defer _CloseElement()
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}, padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(0), bottom = cast(u16)(0)}, layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
						defer _CloseElement()
						layoutData = _RenderDebugLayoutElementsList(cast(i32)(initialRootsLength), highlightedRow)
					}
				}
				contentWidth: f32 = _GetHashMapItem(panelContentsId.id).layoutElement.dimensions.width
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = contentWidth, max = contentWidth}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
					defer _CloseElement()
				}
				for i: i32 = 0; (i < layoutData.rowCount); i += 1 {
					rowColor: Color = (((i & 1) == 0) ? CLAY__DEBUGVIEW_COLOR_2 : CLAY__DEBUGVIEW_COLOR_1)
					if (i == layoutData.selectedElementRowIndex) {
						rowColor = CLAY__DEBUGVIEW_COLOR_SELECTED_ROW
					}
					if (i == highlightedRow) {
						(rowColor)[0] *= 1.25
						(rowColor)[1] *= 1.25
						(rowColor)[2] *= 1.25
					}
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}, backgroundColor = rowColor}}.wrapped)
						defer _CloseElement()
					}
				}
			}
		}
		{
			_OpenElement()
			_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(1), max = cast(f32)(1)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}, backgroundColor = CLAY__DEBUGVIEW_COLOR_3}}.wrapped)
			defer _CloseElement()
		}
		if (ctx.debugSelectedElementId != cast(u32)(0)) {
			selectedItem: ^LayoutElementHashMapItem = _GetHashMapItem(ctx.debugSelectedElementId)
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(300), max = cast(f32)(300)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}, backgroundColor = CLAY__DEBUGVIEW_COLOR_2, clip = ClipElementConfig{vertical = true, childOffset = GetScrollOffset()}, border = BorderElementConfig{color = CLAY__DEBUGVIEW_COLOR_3, width = BorderWidth{betweenChildren = cast(u16)(1)}}}}.wrapped)
				defer _CloseElement()
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT + 8)), max = cast(f32)((CLAY__DEBUGVIEW_ROW_HEIGHT + 8))}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(0), bottom = cast(u16)(0)}, childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
					defer _CloseElement()
					_OpenTextElement(_static_string("Layout Config"), infoTextConfig)
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}}}.wrapped)
						defer _CloseElement()
					}
					if (selectedItem.elementId.stringId.length != 0) {
						_OpenTextElement(selectedItem.elementId.stringId, infoTitleConfig)
						if (selectedItem.elementId.offset != cast(u32)(0)) {
							_OpenTextElement(_static_string(" ("), infoTitleConfig)
							_OpenTextElement(_IntToString(cast(i32)(selectedItem.elementId.offset)), infoTitleConfig)
							_OpenTextElement(_static_string(")"), infoTitleConfig)
						}
					}
				}
				attributeConfigPadding: Padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(8), bottom = cast(u16)(8)}
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
					defer _CloseElement()
					_OpenTextElement(_static_string("Bounding Box"), infoTitleConfig)
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(_static_string("{ x: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(selectedItem.boundingBox.x)), infoTextConfig)
						_OpenTextElement(_static_string(", y: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(selectedItem.boundingBox.y)), infoTextConfig)
						_OpenTextElement(_static_string(", width: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(selectedItem.boundingBox.width)), infoTextConfig)
						_OpenTextElement(_static_string(", height: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(selectedItem.boundingBox.height)), infoTextConfig)
						_OpenTextElement(_static_string(" }"), infoTextConfig)
					}
					_OpenTextElement(_static_string("Layout Direction"), infoTitleConfig)
					layoutConfig: ^LayoutConfig = selectedItem.layoutElement.layoutConfig
					_OpenTextElement(((cast(i32)(layoutConfig.layoutDirection) == CLAY_TOP_TO_BOTTOM) ? _static_string("TOP_TO_BOTTOM") : _static_string("LEFT_TO_RIGHT")), infoTextConfig)
					_OpenTextElement(_static_string("Sizing"), infoTitleConfig)
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(_static_string("width: "), infoTextConfig)
						_RenderDebugLayoutSizing(layoutConfig.sizing.width, infoTextConfig)
					}
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(_static_string("height: "), infoTextConfig)
						_RenderDebugLayoutSizing(layoutConfig.sizing.height, infoTextConfig)
					}
					_OpenTextElement(_static_string("Padding"), infoTitleConfig)
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewElementInfoPadding"), cast(u32)(0), cast(u32)(0))}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(_static_string("{ left: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(layoutConfig.padding.left)), infoTextConfig)
						_OpenTextElement(_static_string(", right: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(layoutConfig.padding.right)), infoTextConfig)
						_OpenTextElement(_static_string(", top: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(layoutConfig.padding.top)), infoTextConfig)
						_OpenTextElement(_static_string(", bottom: "), infoTextConfig)
						_OpenTextElement(_IntToString(cast(i32)(layoutConfig.padding.bottom)), infoTextConfig)
						_OpenTextElement(_static_string(" }"), infoTextConfig)
					}
					_OpenTextElement(_static_string("Child Gap"), infoTitleConfig)
					_OpenTextElement(_IntToString(cast(i32)(layoutConfig.childGap)), infoTextConfig)
					_OpenTextElement(_static_string("Child Alignment"), infoTitleConfig)
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(_static_string("{ x: "), infoTextConfig)
						alignX: String = _static_string("LEFT")
						if (cast(i32)(layoutConfig.childAlignment.x) == CLAY_ALIGN_X_CENTER) {
							alignX = _static_string("CENTER")
						} else {
							if (cast(i32)(layoutConfig.childAlignment.x) == CLAY_ALIGN_X_RIGHT) {
								alignX = _static_string("RIGHT")
							}
						}
						_OpenTextElement(alignX, infoTextConfig)
						_OpenTextElement(_static_string(", y: "), infoTextConfig)
						alignY: String = _static_string("TOP")
						if (cast(i32)(layoutConfig.childAlignment.y) == CLAY_ALIGN_Y_CENTER) {
							alignY = _static_string("CENTER")
						} else {
							if (cast(i32)(layoutConfig.childAlignment.y) == CLAY_ALIGN_Y_BOTTOM) {
								alignY = _static_string("BOTTOM")
							}
						}
						_OpenTextElement(alignY, infoTextConfig)
						_OpenTextElement(_static_string(" }"), infoTextConfig)
					}
				}
				for elementConfigIndex: i32 = 0; (elementConfigIndex < selectedItem.layoutElement.elementConfigs.length); elementConfigIndex += 1 {
					elementConfig: ^ElementConfig = _ElementConfigArraySlice_Get(&selectedItem.layoutElement.elementConfigs, elementConfigIndex)
					_RenderDebugViewElementConfigHeader(selectedItem.elementId.stringId, elementConfig.type)
					switch cast(i32)(elementConfig.type) {
					case CLAY__ELEMENT_CONFIG_TYPE_SHARED:
						sharedConfig: ^SharedElementConfig = elementConfig.config.sharedElementConfig
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Background Color"), infoTitleConfig)
							_RenderDebugViewColor(sharedConfig.backgroundColor, infoTextConfig)
							_OpenTextElement(_static_string("Corner Radius"), infoTitleConfig)
							_RenderDebugViewCornerRadius(sharedConfig.cornerRadius, infoTextConfig)
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_TEXT:
						textConfig: ^TextElementConfig = elementConfig.config.textElementConfig
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Font Size"), infoTitleConfig)
							_OpenTextElement(_IntToString(cast(i32)(textConfig.fontSize)), infoTextConfig)
							_OpenTextElement(_static_string("Font ID"), infoTitleConfig)
							_OpenTextElement(_IntToString(cast(i32)(textConfig.fontId)), infoTextConfig)
							_OpenTextElement(_static_string("Line Height"), infoTitleConfig)
							_OpenTextElement(((cast(i32)(textConfig.lineHeight) == 0) ? _static_string("auto") : _IntToString(cast(i32)(textConfig.lineHeight))), infoTextConfig)
							_OpenTextElement(_static_string("Letter Spacing"), infoTitleConfig)
							_OpenTextElement(_IntToString(cast(i32)(textConfig.letterSpacing)), infoTextConfig)
							_OpenTextElement(_static_string("Wrap Mode"), infoTitleConfig)
							wrapMode: String = _static_string("WORDS")
							if (cast(i32)(textConfig.wrapMode) == CLAY_TEXT_WRAP_NONE) {
								wrapMode = _static_string("NONE")
							} else {
								if (cast(i32)(textConfig.wrapMode) == CLAY_TEXT_WRAP_NEWLINES) {
									wrapMode = _static_string("NEWLINES")
								}
							}
							_OpenTextElement(wrapMode, infoTextConfig)
							_OpenTextElement(_static_string("Text Alignment"), infoTitleConfig)
							textAlignment: String = _static_string("LEFT")
							if (cast(i32)(textConfig.textAlignment) == CLAY_TEXT_ALIGN_CENTER) {
								textAlignment = _static_string("CENTER")
							} else {
								if (cast(i32)(textConfig.textAlignment) == CLAY_TEXT_ALIGN_RIGHT) {
									textAlignment = _static_string("RIGHT")
								}
							}
							_OpenTextElement(textAlignment, infoTextConfig)
							_OpenTextElement(_static_string("Text Color"), infoTitleConfig)
							_RenderDebugViewColor(textConfig.textColor, infoTextConfig)
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_ASPECT:
						aspectRatioConfig: ^AspectRatioElementConfig = elementConfig.config.aspectRatioElementConfig
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewElementInfoAspectRatioBody"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Aspect Ratio"), infoTitleConfig)
							_OpenTextElement(_IntToString(cast(i32)(aspectRatioConfig.aspectRatio)), infoTextConfig)
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_IMAGE:
						imageConfig: ^ImageElementConfig = elementConfig.config.imageElementConfig
						aspectConfig: AspectRatioElementConfig = AspectRatioElementConfig{aspectRatio = cast(f32)(1)}
						if _ElementHasConfig(selectedItem.layoutElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_ASPECT)) {
							aspectConfig = (_FindElementConfigWithType(selectedItem.layoutElement, cast(_ElementConfigType)(CLAY__ELEMENT_CONFIG_TYPE_ASPECT)).aspectRatioElementConfig)^
						}
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewElementInfoImageBody"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Preview"), infoTitleConfig)
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(64), max = cast(f32)(128)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(64), max = cast(f32)(128)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}}}, aspectRatio = aspectConfig, image = (imageConfig)^}}.wrapped)
								defer _CloseElement()
							}
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_CLIP:
						clipConfig: ^ClipElementConfig = elementConfig.config.clipElementConfig
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Vertical"), infoTitleConfig)
							_OpenTextElement(((cast(i32)(clipConfig.vertical) != 0) ? _static_string("true") : _static_string("false")), infoTextConfig)
							_OpenTextElement(_static_string("Horizontal"), infoTitleConfig)
							_OpenTextElement(((cast(i32)(clipConfig.horizontal) != 0) ? _static_string("true") : _static_string("false")), infoTextConfig)
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_FLOATING:
						floatingConfig: ^FloatingElementConfig = elementConfig.config.floatingElementConfig
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Offset"), infoTitleConfig)
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
								defer _CloseElement()
								_OpenTextElement(_static_string("{ x: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)((floatingConfig.offset)[0])), infoTextConfig)
								_OpenTextElement(_static_string(", y: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)((floatingConfig.offset)[1])), infoTextConfig)
								_OpenTextElement(_static_string(" }"), infoTextConfig)
							}
							_OpenTextElement(_static_string("Expand"), infoTitleConfig)
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
								defer _CloseElement()
								_OpenTextElement(_static_string("{ width: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)(floatingConfig.expand.width)), infoTextConfig)
								_OpenTextElement(_static_string(", height: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)(floatingConfig.expand.height)), infoTextConfig)
								_OpenTextElement(_static_string(" }"), infoTextConfig)
							}
							_OpenTextElement(_static_string("z-index"), infoTitleConfig)
							_OpenTextElement(_IntToString(cast(i32)(floatingConfig.zIndex)), infoTextConfig)
							_OpenTextElement(_static_string("Parent"), infoTitleConfig)
							hashItem: ^LayoutElementHashMapItem = _GetHashMapItem(floatingConfig.parentId)
							_OpenTextElement(hashItem.elementId.stringId, infoTextConfig)
							_OpenTextElement(_static_string("Attach Points"), infoTitleConfig)
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
								defer _CloseElement()
								_OpenTextElement(_static_string("{ element: "), infoTextConfig)
								attachPointElement: String = _static_string("LEFT_TOP")
								if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_LEFT_CENTER) {
									attachPointElement = _static_string("LEFT_CENTER")
								} else {
									if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_LEFT_BOTTOM) {
										attachPointElement = _static_string("LEFT_BOTTOM")
									} else {
										if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_CENTER_TOP) {
											attachPointElement = _static_string("CENTER_TOP")
										} else {
											if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_CENTER_CENTER) {
												attachPointElement = _static_string("CENTER_CENTER")
											} else {
												if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_CENTER_BOTTOM) {
													attachPointElement = _static_string("CENTER_BOTTOM")
												} else {
													if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_RIGHT_TOP) {
														attachPointElement = _static_string("RIGHT_TOP")
													} else {
														if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_RIGHT_CENTER) {
															attachPointElement = _static_string("RIGHT_CENTER")
														} else {
															if (cast(i32)(floatingConfig.attachment.element) == CLAY_ATTACH_POINT_RIGHT_BOTTOM) {
																attachPointElement = _static_string("RIGHT_BOTTOM")
															}
														}
													}
												}
											}
										}
									}
								}
								_OpenTextElement(attachPointElement, infoTextConfig)
								attachPointParent: String = _static_string("LEFT_TOP")
								if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_LEFT_CENTER) {
									attachPointParent = _static_string("LEFT_CENTER")
								} else {
									if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_LEFT_BOTTOM) {
										attachPointParent = _static_string("LEFT_BOTTOM")
									} else {
										if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_CENTER_TOP) {
											attachPointParent = _static_string("CENTER_TOP")
										} else {
											if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_CENTER_CENTER) {
												attachPointParent = _static_string("CENTER_CENTER")
											} else {
												if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_CENTER_BOTTOM) {
													attachPointParent = _static_string("CENTER_BOTTOM")
												} else {
													if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_RIGHT_TOP) {
														attachPointParent = _static_string("RIGHT_TOP")
													} else {
														if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_RIGHT_CENTER) {
															attachPointParent = _static_string("RIGHT_CENTER")
														} else {
															if (cast(i32)(floatingConfig.attachment.parent) == CLAY_ATTACH_POINT_RIGHT_BOTTOM) {
																attachPointParent = _static_string("RIGHT_BOTTOM")
															}
														}
													}
												}
											}
										}
									}
								}
								_OpenTextElement(_static_string(", parent: "), infoTextConfig)
								_OpenTextElement(attachPointParent, infoTextConfig)
								_OpenTextElement(_static_string(" }"), infoTextConfig)
							}
							_OpenTextElement(_static_string("Pointer Capture Mode"), infoTitleConfig)
							pointerCaptureMode: String = _static_string("NONE")
							if (cast(i32)(floatingConfig.pointerCaptureMode) == CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH) {
								pointerCaptureMode = _static_string("PASSTHROUGH")
							}
							_OpenTextElement(pointerCaptureMode, infoTextConfig)
							_OpenTextElement(_static_string("Attach To"), infoTitleConfig)
							attachTo: String = _static_string("NONE")
							if (cast(i32)(floatingConfig.attachTo) == CLAY_ATTACH_TO_PARENT) {
								attachTo = _static_string("PARENT")
							} else {
								if (cast(i32)(floatingConfig.attachTo) == CLAY_ATTACH_TO_ELEMENT_WITH_ID) {
									attachTo = _static_string("ELEMENT_WITH_ID")
								} else {
									if (cast(i32)(floatingConfig.attachTo) == CLAY_ATTACH_TO_ROOT) {
										attachTo = _static_string("ROOT")
									}
								}
							}
							_OpenTextElement(attachTo, infoTextConfig)
							_OpenTextElement(_static_string("Clip To"), infoTitleConfig)
							clipTo: String = _static_string("ATTACHED_PARENT")
							if (cast(i32)(floatingConfig.clipTo) == CLAY_CLIP_TO_NONE) {
								clipTo = _static_string("NONE")
							}
							_OpenTextElement(clipTo, infoTextConfig)
						}
						break
					case CLAY__ELEMENT_CONFIG_TYPE_BORDER:
						borderConfig: ^BorderElementConfig = elementConfig.config.borderElementConfig
						{
							_OpenElement()
							_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewElementInfoBorderBody"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{padding = attributeConfigPadding, childGap = cast(u16)(8), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}}}.wrapped)
							defer _CloseElement()
							_OpenTextElement(_static_string("Border Widths"), infoTitleConfig)
							{
								_OpenElement()
								_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{layout = LayoutConfig{layoutDirection = cast(LayoutDirection)(CLAY_LEFT_TO_RIGHT)}}}.wrapped)
								defer _CloseElement()
								_OpenTextElement(_static_string("{ left: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)(borderConfig.width.left)), infoTextConfig)
								_OpenTextElement(_static_string(", right: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)(borderConfig.width.right)), infoTextConfig)
								_OpenTextElement(_static_string(", top: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)(borderConfig.width.top)), infoTextConfig)
								_OpenTextElement(_static_string(", bottom: "), infoTextConfig)
								_OpenTextElement(_IntToString(cast(i32)(borderConfig.width.bottom)), infoTextConfig)
								_OpenTextElement(_static_string(" }"), infoTextConfig)
							}
							_OpenTextElement(_static_string("Border Color"), infoTitleConfig)
							_RenderDebugViewColor(borderConfig.color, infoTextConfig)
						}
						break
					case:
						break
					}
				}
			}
		} else {
			{
				_OpenElement()
				_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewWarningsScrollPane"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(300), max = cast(f32)(300)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, childGap = cast(u16)(6), layoutDirection = cast(LayoutDirection)(CLAY_TOP_TO_BOTTOM)}, backgroundColor = CLAY__DEBUGVIEW_COLOR_2, clip = ClipElementConfig{horizontal = true, vertical = true, childOffset = GetScrollOffset()}}}.wrapped)
				defer _CloseElement()
				warningConfig: ^TextElementConfig = _StoreTextElementConfig(_Clay_TextElementConfigWrapper{wrapped = TextElementConfig{textColor = CLAY__DEBUGVIEW_COLOR_4, fontSize = cast(u16)(16), wrapMode = cast(TextWrapMode)(CLAY_TEXT_WRAP_NONE)}}.wrapped)
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewWarningItemHeader"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(0), bottom = cast(u16)(0)}, childGap = cast(u16)(8), childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
					defer _CloseElement()
					_OpenTextElement(_static_string("Warnings"), warningConfig)
				}
				{
					_OpenElement()
					_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewWarningsTopBorder"), cast(u32)(0), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{width = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(0)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_GROW)}, height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(1), max = cast(f32)(1)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}}, backgroundColor = Color{cast(f32)(200), cast(f32)(200), cast(f32)(200), cast(f32)(255)}}}.wrapped)
					defer _CloseElement()
				}
				previousWarningsLength: i32 = ctx.warnings.length
				for i: i32 = 0; (i < previousWarningsLength); i += 1 {
					warning: _Warning = ctx.warnings.internalArray[i]
					{
						_OpenElement()
						_ConfigureOpenElement(_Clay_ElementDeclarationWrapper{wrapped = ElementDeclaration{id = _HashString(_static_string("Clay__DebugViewWarningItem"), cast(u32)(i), cast(u32)(0)), layout = LayoutConfig{sizing = Sizing{height = SizingAxis{constraints = SizingConstraints{sizeMinMax = SizingConstraintsMinMax{min = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT), max = cast(f32)(CLAY__DEBUGVIEW_ROW_HEIGHT)}}, type = cast(SizingType)(CLAY__SIZING_TYPE_FIXED)}}, padding = Padding{left = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), right = cast(u16)(CLAY__DEBUGVIEW_OUTER_PADDING), top = cast(u16)(0), bottom = cast(u16)(0)}, childGap = cast(u16)(8), childAlignment = ChildAlignment{y = cast(LayoutAlignmentY)(CLAY_ALIGN_Y_CENTER)}}}}.wrapped)
						defer _CloseElement()
						_OpenTextElement(warning.baseMessage, warningConfig)
						if (warning.dynamicMessage.length > 0) {
							_OpenTextElement(warning.dynamicMessage, warningConfig)
						}
					}
				}
			}
		}
	}
}
