// Clay v0.14 native Odin port; existing olib API retained.
// Altered source derived from nicbarker/clay; see README.md and LICENSE.md.
package clay

// Native Odin implementation; no foreign objects or C runtime.

String :: struct {
	isStaticallyAllocated: bool,
	length: i32,
	chars:  [^]u8,
}

StringSlice :: struct {
	length: i32,
	chars:  [^]u8,
	baseChars:  [^]u8,
}

Vector2 :: [2]f32

Dimensions :: struct {
	width:  f32,
	height: f32,
}

Arena :: struct {
	nextAllocation: uintptr,
	capacity:       uint,
	memory:         [^]u8,
}

BoundingBox :: struct {
	x:      f32,
	y:      f32,
	width:  f32,
	height: f32,
}

Color :: [4]f32

CornerRadius :: struct {
	topLeft:     f32,
	topRight:    f32,
	bottomLeft:  f32,
	bottomRight: f32,
}

BorderData :: struct {
	width: u32,
	color: Color,
}

ElementId :: struct {
	id:       u32,
	offset:   u32,
	baseId:   u32,
	stringId: String,
}

when ODIN_OS == .Windows {
	EnumBackingType :: u32
} else {
	EnumBackingType :: u8
}

RenderCommandType :: enum EnumBackingType {
	None,
	Rectangle,
	Border,
	Text,
	Image,
	ScissorStart,
	ScissorEnd,
	Custom,
}

RectangleElementConfig :: struct {
	color:        Color,
}

TextWrapMode :: enum EnumBackingType {
	Words,
	Newlines,
	None,
}

TextAlignment :: enum EnumBackingType {
	Left,
	Center,
	Right,
}

TextElementConfig :: struct {
	userData:           rawptr,
	textColor:          Color,
	fontId:             u16,
	fontSize:           u16,
	letterSpacing:      u16,
	lineHeight:         u16,
	wrapMode:           TextWrapMode,
	textAlignment:      TextAlignment,
}

AspectRatioElementConfig :: struct {
	aspectRatio:        f32,
}

ImageElementConfig :: struct {
	imageData:        rawptr,
}

CustomElementConfig :: struct {
	customData: rawptr,
}

BorderWidth :: struct {
	left: u16,
	right: u16,
	top: u16,
	bottom: u16,
	betweenChildren: u16,
}

BorderElementConfig :: struct {
	color: Color,
	width: BorderWidth,
}

ClipElementConfig :: struct {
	horizontal:  bool, // clip overflowing elements on the "X" axis
	vertical:    bool, // clip overflowing elements on the "Y" axis
	childOffset: Vector2, // offsets the [X,Y] positions of all child elements, primarily for scrolling containers
}

FloatingAttachPointType :: enum EnumBackingType {
	LeftTop,
	LeftCenter,
	LeftBottom,
	CenterTop,
	CenterCenter,
	CenterBottom,
	RightTop,
	RightCenter,
	RightBottom,
}

FloatingAttachPoints :: struct {
	element: FloatingAttachPointType,
	parent:  FloatingAttachPointType,
}

PointerCaptureMode :: enum EnumBackingType {
	Capture,
	Passthrough,
}

FloatingAttachToElement :: enum EnumBackingType {
	None,
	Parent,
	ElementWithId,
	Root,
}

FloatingClipToElement :: enum EnumBackingType {
	None,
	AttachedParent,
}

FloatingElementConfig :: struct {
	offset:             Vector2,
	expand:             Dimensions,
	parentId:           u32,
	zIndex:             i16,
	attachment:         FloatingAttachPoints,
	pointerCaptureMode: PointerCaptureMode,
	attachTo:           FloatingAttachToElement,
	clipTo: 			FloatingClipToElement,
}

TextRenderData :: struct {
	stringContents: StringSlice,
	textColor: Color,
	fontId: u16,
	fontSize: u16,
	letterSpacing: u16,
	lineHeight: u16,
}

RectangleRenderData :: struct {
	backgroundColor: Color,
	cornerRadius: CornerRadius,
}

ImageRenderData :: struct {
	backgroundColor: Color,
	cornerRadius: CornerRadius,
	imageData: rawptr,
}

CustomRenderData :: struct {
	backgroundColor: Color,
	cornerRadius: CornerRadius,
	customData: rawptr,
}

BorderRenderData :: struct {
	color: Color,
	cornerRadius: CornerRadius,
	width: BorderWidth,
}

RenderCommandData :: struct #raw_union {
	clip: ClipRenderData,
	rectangle: RectangleRenderData,
	text: TextRenderData,
	image: ImageRenderData,
	custom: CustomRenderData,
	border: BorderRenderData,
}

RenderCommand :: struct {
	boundingBox:        BoundingBox,
	renderData:         RenderCommandData,
	userData:           rawptr,
	id:                 u32,
	zIndex:             i16,
	commandType:        RenderCommandType,
}

ScrollContainerData :: struct {
	// Note: This is a pointer to the real internal scroll position, mutating it may cause a change in final layout.
	// Intended for use with external functionality that modifies scroll position, such as scroll bars or auto scrolling.
	scrollPosition:            ^Vector2,
	scrollContainerDimensions: Dimensions,
	contentDimensions:         Dimensions,
	config:                    ClipElementConfig,
	// Indicates whether an actual scroll container matched the provided ID or if the default struct was returned.
	found:                     bool,
}

ElementData :: struct {
	boundingBox: BoundingBox,
	found:       bool,
}

PointerDataInteractionState :: enum EnumBackingType {
	PressedThisFrame,
	Pressed,
	ReleasedThisFrame,
	Released,
}

PointerData :: struct {
	position: Vector2,
	state:    PointerDataInteractionState,
}

SizingType :: enum EnumBackingType {
	Fit,
	Grow,
	Percent,
	Fixed,
}

SizingConstraintsMinMax :: struct {
	min: f32,
	max: f32,
}

SizingConstraints :: struct #raw_union {
	sizeMinMax:  SizingConstraintsMinMax,
	sizePercent: f32,
}

SizingAxis :: struct {
	// Note: `min` is used for CLAY_SIZING_PERCENT, slightly different to clay.h due to lack of C anonymous unions
	constraints: SizingConstraints,
	type:        SizingType,
}

Sizing :: struct {
	width:  SizingAxis,
	height: SizingAxis,
}

Padding :: struct {
	left: u16,
	right: u16,
	top: u16,
	bottom: u16,
}

LayoutDirection :: enum EnumBackingType {
	LeftToRight,
	TopToBottom,
}

LayoutAlignmentX :: enum EnumBackingType {
	Left,
	Right,
	Center,
}

LayoutAlignmentY :: enum EnumBackingType {
	Top,
	Bottom,
	Center,
}

ChildAlignment :: struct {
	x: LayoutAlignmentX,
	y: LayoutAlignmentY,
}

LayoutConfig :: struct {
	sizing:          Sizing,
	padding:         Padding,
	childGap:        u16,
	childAlignment:  ChildAlignment,
	layoutDirection: LayoutDirection,
}

ClayArray :: struct($type: typeid) {
	capacity:      i32,
	length:        i32,
	internalArray: [^]type,
}

ElementDeclaration :: struct {
	id:              ElementId,
	layout:          LayoutConfig,
	backgroundColor: Color,
	cornerRadius:    CornerRadius,
	aspectRatio: 	 AspectRatioElementConfig,
	image:           ImageElementConfig,
	floating:        FloatingElementConfig,
	custom:          CustomElementConfig,
	clip:            ClipElementConfig,
	border:          BorderElementConfig,
	userData:        rawptr,
}

ErrorType :: enum EnumBackingType {
	TextMeasurementFunctionNotProvided,
	ArenaCapacityExceeded,
	ElementsCapacityExceeded,
	TextMeasurementCapacityExceeded,
	DuplicateId,
	FloatingContainerParentNotFound,
	PercentageOver1,
	InternalError,
}

ErrorData :: struct {
	errorType: ErrorType,
	errorText: String,
	userData: rawptr,
}

ErrorHandler :: struct {
	handler: proc "c" (errorData: ErrorData),
	userData: rawptr,
}

ConfigureOpenElement :: proc(config: ElementDeclaration) -> bool {
	_ConfigureOpenElement(config)
	return true
}

@(deferred_none = _CloseElement)
UI :: proc() -> proc (config: ElementDeclaration) -> bool {
	_OpenElement()
	return ConfigureOpenElement
}

Text :: proc($text: string, config: ^TextElementConfig) {
	wrapped := MakeString(text)
	wrapped.isStaticallyAllocated = true
	_OpenTextElement(wrapped, config)
}

TextDynamic :: proc(text: string, config: ^TextElementConfig) {
	_OpenTextElement(MakeString(text), config)
}

TextConfig :: proc(config: TextElementConfig) -> ^TextElementConfig {
	return _StoreTextElementConfig(config)
}

PaddingAll :: proc(allPadding: u16) -> Padding {
	return { left = allPadding, right = allPadding, top = allPadding, bottom = allPadding }
}

BorderOutside :: proc(width: u16) -> BorderWidth {
	return {width, width, width, width, 0}
}

BorderAll :: proc(width: u16) -> BorderWidth {
	return {width, width, width, width, width}
}

CornerRadiusAll :: proc(radius: f32) -> CornerRadius {
	return CornerRadius{radius, radius, radius, radius}
}

SizingFit :: proc(sizeMinMax: SizingConstraintsMinMax) -> SizingAxis {
	return SizingAxis{type = SizingType.Fit, constraints = {sizeMinMax = sizeMinMax}}
}

SizingGrow :: proc(sizeMinMax: SizingConstraintsMinMax) -> SizingAxis {
	return SizingAxis{type = SizingType.Grow, constraints = {sizeMinMax = sizeMinMax}}
}

SizingFixed :: proc(size: f32) -> SizingAxis {
	return SizingAxis{type = SizingType.Fixed, constraints = {sizeMinMax = {size, size}}}
}

SizingPercent :: proc(sizePercent: f32) -> SizingAxis {
	return SizingAxis{type = SizingType.Percent, constraints = {sizePercent = sizePercent}}
}

MakeString :: proc(label: string) -> String {
	return String{chars = raw_data(label), length = cast(i32)len(label)}
}

ID :: proc(label: string, index: u32 = 0) -> ElementId {
	return _HashString(MakeString(label), index, 0)
}

ID_LOCAL :: proc(label: string, index: u32 = 0) -> ElementId {
	return _HashString(MakeString(label), index, _GetParentElementId())
}
