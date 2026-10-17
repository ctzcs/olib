// Pure Odin port of Clay v0.14 (b25a31c1a152915cd7dd6796e6592273e5a10aac).
// Copyright (c) 2024 Nic Barker. Altered source; see LICENSE.md and README.md.
package clay

Context :: struct {
	maxElementCount: i32,
	maxMeasureTextCacheWordCount: i32,
	warningsEnabled: bool,
	errorHandler: ErrorHandler,
	booleanWarnings: BooleanWarnings,
	warnings: _WarningArray,
	pointerInfo: PointerData,
	layoutDimensions: Dimensions,
	dynamicElementIndexBaseHash: ElementId,
	dynamicElementIndex: u32,
	debugModeEnabled: bool,
	disableCulling: bool,
	externalScrollHandlingEnabled: bool,
	debugSelectedElementId: u32,
	generation: u32,
	arenaResetOffset: uintptr,
	measureTextUserData: rawptr,
	queryScrollOffsetUserData: rawptr,
	internalArena: Arena,
	layoutElements: LayoutElementArray,
	renderCommands: ClayArray(RenderCommand),
	openLayoutElementStack: _int32_tArray,
	layoutElementChildren: _int32_tArray,
	layoutElementChildrenBuffer: _int32_tArray,
	textElementData: _TextElementDataArray,
	aspectRatioElementIndexes: _int32_tArray,
	reusableElementIndexBuffer: _int32_tArray,
	layoutElementClipElementIds: _int32_tArray,
	layoutConfigs: _LayoutConfigArray,
	elementConfigs: _ElementConfigArray,
	textElementConfigs: _TextElementConfigArray,
	aspectRatioElementConfigs: _AspectRatioElementConfigArray,
	imageElementConfigs: _ImageElementConfigArray,
	floatingElementConfigs: _FloatingElementConfigArray,
	clipElementConfigs: _ClipElementConfigArray,
	customElementConfigs: _CustomElementConfigArray,
	borderElementConfigs: _BorderElementConfigArray,
	sharedElementConfigs: _SharedElementConfigArray,
	layoutElementIdStrings: _StringArray,
	wrappedTextLines: _WrappedTextLineArray,
	layoutElementTreeNodeArray1: _LayoutElementTreeNodeArray,
	layoutElementTreeRoots: _LayoutElementTreeRootArray,
	layoutElementsHashMapInternal: _LayoutElementHashMapItemArray,
	layoutElementsHashMap: _int32_tArray,
	measureTextHashMapInternal: _MeasureTextCacheItemArray,
	measureTextHashMapInternalFreeList: _int32_tArray,
	measureTextHashMap: _int32_tArray,
	measuredWords: _MeasuredWordArray,
	measuredWordsFreeList: _int32_tArray,
	openClipElementStack: _int32_tArray,
	pointerOverIds: ElementIdArray,
	scrollContainerDatas: _ScrollContainerDataInternalArray,
	treeNodeVisited: _boolArray,
	dynamicStringData: _charArray,
	debugElementData: _DebugElementDataArray,
}

@(private)
ElementIdArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]ElementId,
}

@(private)
_Clay_PaddingWrapper :: struct {
	wrapped: Padding,
}

@(private)
_Clay_LayoutConfigWrapper :: struct {
	wrapped: LayoutConfig,
}

@(private)
_Clay_TextElementConfigWrapper :: struct {
	wrapped: TextElementConfig,
}

@(private)
_Clay_AspectRatioElementConfigWrapper :: struct {
	wrapped: AspectRatioElementConfig,
}

@(private)
_Clay_ImageElementConfigWrapper :: struct {
	wrapped: ImageElementConfig,
}

@(private)
_Clay_FloatingElementConfigWrapper :: struct {
	wrapped: FloatingElementConfig,
}

@(private)
_Clay_CustomElementConfigWrapper :: struct {
	wrapped: CustomElementConfig,
}

@(private)
_Clay_ClipElementConfigWrapper :: struct {
	wrapped: ClipElementConfig,
}

@(private)
_Clay_BorderElementConfigWrapper :: struct {
	wrapped: BorderElementConfig,
}

ClipRenderData :: struct {
	horizontal: bool,
	vertical: bool,
}

@(private)
_Clay_ElementDeclarationWrapper :: struct {
	wrapped: ElementDeclaration,
}

@(private)
BooleanWarnings :: struct {
	maxElementsExceeded: bool,
	maxRenderCommandsExceeded: bool,
	maxTextMeasureCacheExceeded: bool,
	textMeasurementFunctionNotSet: bool,
}

@(private)
_Warning :: struct {
	baseMessage: String,
	dynamicMessage: String,
}

@(private)
_WarningArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_Warning,
}

@(private)
SharedElementConfig :: struct {
	backgroundColor: Color,
	cornerRadius: CornerRadius,
	userData: rawptr,
}

@(private)
_Clay_SharedElementConfigWrapper :: struct {
	wrapped: SharedElementConfig,
}

@(private)
_boolArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]bool,
}

@(private)
_boolArraySlice :: struct {
	length: i32,
	internalArray: [^]bool,
}

@(private)
_int32_tArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]i32,
}

@(private)
_int32_tArraySlice :: struct {
	length: i32,
	internalArray: [^]i32,
}

@(private)
_charArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]u8,
}

@(private)
_charArraySlice :: struct {
	length: i32,
	internalArray: [^]u8,
}

@(private)
ElementIdArraySlice :: struct {
	length: i32,
	internalArray: [^]ElementId,
}

@(private)
_LayoutConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]LayoutConfig,
}

@(private)
_LayoutConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]LayoutConfig,
}

@(private)
_TextElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]TextElementConfig,
}

@(private)
_TextElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]TextElementConfig,
}

@(private)
_AspectRatioElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]AspectRatioElementConfig,
}

@(private)
_AspectRatioElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]AspectRatioElementConfig,
}

@(private)
_ImageElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]ImageElementConfig,
}

@(private)
_ImageElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]ImageElementConfig,
}

@(private)
_FloatingElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]FloatingElementConfig,
}

@(private)
_FloatingElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]FloatingElementConfig,
}

@(private)
_CustomElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]CustomElementConfig,
}

@(private)
_CustomElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]CustomElementConfig,
}

@(private)
_ClipElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]ClipElementConfig,
}

@(private)
_ClipElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]ClipElementConfig,
}

@(private)
_BorderElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]BorderElementConfig,
}

@(private)
_BorderElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]BorderElementConfig,
}

@(private)
_StringArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]String,
}

@(private)
_StringArraySlice :: struct {
	length: i32,
	internalArray: [^]String,
}

@(private)
_SharedElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]SharedElementConfig,
}

@(private)
_SharedElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]SharedElementConfig,
}

@(private)
RenderCommandArraySlice :: struct {
	length: i32,
	internalArray: [^]RenderCommand,
}

@(private)
ElementConfigUnion :: struct #raw_union {
	textElementConfig: ^TextElementConfig,
	aspectRatioElementConfig: ^AspectRatioElementConfig,
	imageElementConfig: ^ImageElementConfig,
	floatingElementConfig: ^FloatingElementConfig,
	customElementConfig: ^CustomElementConfig,
	clipElementConfig: ^ClipElementConfig,
	borderElementConfig: ^BorderElementConfig,
	sharedElementConfig: ^SharedElementConfig,
}

@(private)
ElementConfig :: struct {
	type: _ElementConfigType,
	config: ElementConfigUnion,
}

@(private)
_ElementConfigArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]ElementConfig,
}

@(private)
_ElementConfigArraySlice :: struct {
	length: i32,
	internalArray: [^]ElementConfig,
}

@(private)
_WrappedTextLine :: struct {
	dimensions: Dimensions,
	line: String,
}

@(private)
_WrappedTextLineArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_WrappedTextLine,
}

@(private)
_WrappedTextLineArraySlice :: struct {
	length: i32,
	internalArray: [^]_WrappedTextLine,
}

@(private)
_TextElementData :: struct {
	text: String,
	preferredDimensions: Dimensions,
	elementIndex: i32,
	wrappedLines: _WrappedTextLineArraySlice,
}

@(private)
_TextElementDataArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_TextElementData,
}

@(private)
_TextElementDataArraySlice :: struct {
	length: i32,
	internalArray: [^]_TextElementData,
}

@(private)
_LayoutElementChildren :: struct {
	elements: ^i32,
	length: u16,
}

@(private)
LayoutElement :: struct {
	childrenOrTextContent: LayoutElement_childrenOrTextContent,
	dimensions: Dimensions,
	minDimensions: Dimensions,
	layoutConfig: ^LayoutConfig,
	elementConfigs: _ElementConfigArraySlice,
	id: u32,
}

@(private)
LayoutElementArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]LayoutElement,
}

@(private)
LayoutElementArraySlice :: struct {
	length: i32,
	internalArray: [^]LayoutElement,
}

@(private)
_ScrollContainerDataInternal :: struct {
	layoutElement: ^LayoutElement,
	boundingBox: BoundingBox,
	contentSize: Dimensions,
	scrollOrigin: Vector2,
	pointerOrigin: Vector2,
	scrollMomentum: Vector2,
	scrollPosition: Vector2,
	previousDelta: Vector2,
	momentumTime: f32,
	elementId: u32,
	openThisFrame: bool,
	pointerScrollActive: bool,
}

@(private)
_ScrollContainerDataInternalArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_ScrollContainerDataInternal,
}

@(private)
_ScrollContainerDataInternalArraySlice :: struct {
	length: i32,
	internalArray: [^]_ScrollContainerDataInternal,
}

@(private)
_DebugElementData :: struct {
	collision: bool,
	collapsed: bool,
}

@(private)
_DebugElementDataArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_DebugElementData,
}

@(private)
_DebugElementDataArraySlice :: struct {
	length: i32,
	internalArray: [^]_DebugElementData,
}

@(private)
LayoutElementHashMapItem :: struct {
	boundingBox: BoundingBox,
	elementId: ElementId,
	layoutElement: ^LayoutElement,
	onHoverFunction: proc "c" (ElementId, PointerData, rawptr),
	hoverFunctionUserData: rawptr,
	nextIndex: i32,
	generation: u32,
	idAlias: u32,
	debugData: ^_DebugElementData,
}

@(private)
_LayoutElementHashMapItemArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]LayoutElementHashMapItem,
}

@(private)
_LayoutElementHashMapItemArraySlice :: struct {
	length: i32,
	internalArray: [^]LayoutElementHashMapItem,
}

@(private)
_MeasuredWord :: struct {
	startOffset: i32,
	length: i32,
	width: f32,
	next: i32,
}

@(private)
_MeasuredWordArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_MeasuredWord,
}

@(private)
_MeasuredWordArraySlice :: struct {
	length: i32,
	internalArray: [^]_MeasuredWord,
}

@(private)
_MeasureTextCacheItem :: struct {
	unwrappedDimensions: Dimensions,
	measuredWordsStartIndex: i32,
	minWidth: f32,
	containsNewlines: bool,
	id: u32,
	nextIndex: i32,
	generation: u32,
}

@(private)
_MeasureTextCacheItemArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_MeasureTextCacheItem,
}

@(private)
_MeasureTextCacheItemArraySlice :: struct {
	length: i32,
	internalArray: [^]_MeasureTextCacheItem,
}

@(private)
_LayoutElementTreeNode :: struct {
	layoutElement: ^LayoutElement,
	position: Vector2,
	nextChildOffset: Vector2,
}

@(private)
_LayoutElementTreeNodeArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_LayoutElementTreeNode,
}

@(private)
_LayoutElementTreeNodeArraySlice :: struct {
	length: i32,
	internalArray: [^]_LayoutElementTreeNode,
}

@(private)
_LayoutElementTreeRoot :: struct {
	layoutElementIndex: i32,
	parentId: u32,
	clipElementId: u32,
	zIndex: i16,
	pointerOffset: Vector2,
}

@(private)
_LayoutElementTreeRootArray :: struct {
	capacity: i32,
	length: i32,
	internalArray: [^]_LayoutElementTreeRoot,
}

@(private)
_LayoutElementTreeRootArraySlice :: struct {
	length: i32,
	internalArray: [^]_LayoutElementTreeRoot,
}

@(private)
_DebugElementConfigTypeLabelConfig :: struct {
	label: String,
	color: Color,
}

@(private)
_RenderDebugLayoutData :: struct {
	rowCount: i32,
	selectedElementRowIndex: i32,
}

@(private)
ScrollRenderData :: struct {
	horizontal: bool,
	vertical: bool,
}

@(private)
LayoutElement_childrenOrTextContent :: struct #raw_union {
	children: _LayoutElementChildren,
	textElementData: ^_TextElementData,
}

@(private)
CLAY_LEFT_TO_RIGHT :: 0

@(private)
CLAY_TOP_TO_BOTTOM :: 1

@(private)
CLAY_ALIGN_X_LEFT :: 0

@(private)
CLAY_ALIGN_X_RIGHT :: 1

@(private)
CLAY_ALIGN_X_CENTER :: 2

@(private)
CLAY_ALIGN_Y_TOP :: 0

@(private)
CLAY_ALIGN_Y_BOTTOM :: 1

@(private)
CLAY_ALIGN_Y_CENTER :: 2

@(private)
CLAY__SIZING_TYPE_FIT :: 0

@(private)
CLAY__SIZING_TYPE_GROW :: 1

@(private)
CLAY__SIZING_TYPE_PERCENT :: 2

@(private)
CLAY__SIZING_TYPE_FIXED :: 3

@(private)
CLAY_TEXT_WRAP_WORDS :: 0

@(private)
CLAY_TEXT_WRAP_NEWLINES :: 1

@(private)
CLAY_TEXT_WRAP_NONE :: 2

@(private)
CLAY_TEXT_ALIGN_LEFT :: 0

@(private)
CLAY_TEXT_ALIGN_CENTER :: 1

@(private)
CLAY_TEXT_ALIGN_RIGHT :: 2

@(private)
CLAY_ATTACH_POINT_LEFT_TOP :: 0

@(private)
CLAY_ATTACH_POINT_LEFT_CENTER :: 1

@(private)
CLAY_ATTACH_POINT_LEFT_BOTTOM :: 2

@(private)
CLAY_ATTACH_POINT_CENTER_TOP :: 3

@(private)
CLAY_ATTACH_POINT_CENTER_CENTER :: 4

@(private)
CLAY_ATTACH_POINT_CENTER_BOTTOM :: 5

@(private)
CLAY_ATTACH_POINT_RIGHT_TOP :: 6

@(private)
CLAY_ATTACH_POINT_RIGHT_CENTER :: 7

@(private)
CLAY_ATTACH_POINT_RIGHT_BOTTOM :: 8

@(private)
CLAY_POINTER_CAPTURE_MODE_CAPTURE :: 0

@(private)
CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH :: 1

@(private)
CLAY_ATTACH_TO_NONE :: 0

@(private)
CLAY_ATTACH_TO_PARENT :: 1

@(private)
CLAY_ATTACH_TO_ELEMENT_WITH_ID :: 2

@(private)
CLAY_ATTACH_TO_ROOT :: 3

@(private)
CLAY_CLIP_TO_NONE :: 0

@(private)
CLAY_CLIP_TO_ATTACHED_PARENT :: 1

@(private)
CLAY_RENDER_COMMAND_TYPE_NONE :: 0

@(private)
CLAY_RENDER_COMMAND_TYPE_RECTANGLE :: 1

@(private)
CLAY_RENDER_COMMAND_TYPE_BORDER :: 2

@(private)
CLAY_RENDER_COMMAND_TYPE_TEXT :: 3

@(private)
CLAY_RENDER_COMMAND_TYPE_IMAGE :: 4

@(private)
CLAY_RENDER_COMMAND_TYPE_SCISSOR_START :: 5

@(private)
CLAY_RENDER_COMMAND_TYPE_SCISSOR_END :: 6

@(private)
CLAY_RENDER_COMMAND_TYPE_CUSTOM :: 7

@(private)
CLAY_POINTER_DATA_PRESSED_THIS_FRAME :: 0

@(private)
CLAY_POINTER_DATA_PRESSED :: 1

@(private)
CLAY_POINTER_DATA_RELEASED_THIS_FRAME :: 2

@(private)
CLAY_POINTER_DATA_RELEASED :: 3

@(private)
CLAY_ERROR_TYPE_TEXT_MEASUREMENT_FUNCTION_NOT_PROVIDED :: 0

@(private)
CLAY_ERROR_TYPE_ARENA_CAPACITY_EXCEEDED :: 1

@(private)
CLAY_ERROR_TYPE_ELEMENTS_CAPACITY_EXCEEDED :: 2

@(private)
CLAY_ERROR_TYPE_TEXT_MEASUREMENT_CAPACITY_EXCEEDED :: 3

@(private)
CLAY_ERROR_TYPE_DUPLICATE_ID :: 4

@(private)
CLAY_ERROR_TYPE_FLOATING_CONTAINER_PARENT_NOT_FOUND :: 5

@(private)
CLAY_ERROR_TYPE_PERCENTAGE_OVER_1 :: 6

@(private)
CLAY_ERROR_TYPE_INTERNAL_ERROR :: 7

@(private)
_ElementConfigType :: u8

@(private)
CLAY__ELEMENT_CONFIG_TYPE_NONE :: 0

@(private)
CLAY__ELEMENT_CONFIG_TYPE_BORDER :: 1

@(private)
CLAY__ELEMENT_CONFIG_TYPE_FLOATING :: 2

@(private)
CLAY__ELEMENT_CONFIG_TYPE_CLIP :: 3

@(private)
CLAY__ELEMENT_CONFIG_TYPE_ASPECT :: 4

@(private)
CLAY__ELEMENT_CONFIG_TYPE_IMAGE :: 5

@(private)
CLAY__ELEMENT_CONFIG_TYPE_TEXT :: 6

@(private)
CLAY__ELEMENT_CONFIG_TYPE_CUSTOM :: 7

@(private)
CLAY__ELEMENT_CONFIG_TYPE_SHARED :: 8
