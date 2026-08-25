// Draws and operates the original DtBlkFx control layout with native AppKit.
#import <Cocoa/Cocoa.h>

#include "editor.hpp"

#include "controller.hpp"
#include "upstream/dtblkfx/BlkFxParam.h"
#include "upstream/dtblkfx/FxRun1_0.h"
#include "upstream/dtblkfx/rfftw_float.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace
{
constexpr CGFloat EditorWidth = 410.0;
constexpr CGFloat GlobalHeight = 26.0;
constexpr CGFloat SpectrumHeight = 191.0;
constexpr CGFloat EffectHeight = 24.0;
constexpr CGFloat EditorHeight = GlobalHeight + SpectrumHeight + EffectHeight * BlkFxParam::NUM_FX_SETS;
constexpr NSInteger SpectrumHeights[] = { 92, 93 };

struct SpectrumColor
{
    unsigned char red;
    unsigned char green;
    unsigned char blue;
};

SpectrumColor MapSpectrumColor(float power)
{
    static constexpr SpectrumColor colors[] = {
        { 0, 0, 0 },
        { 0, 0, 255 },
        { 0, 255, 255 },
        { 0, 204, 0 },
        { 255, 255, 0 },
        { 255, 0, 0 },
    };
    constexpr float minimumPower = 1e-8f;
    constexpr float maximumPower = 0.04f;
    if(!(power > minimumPower))
        return colors[0];
    const float position = std::clamp(
        (std::log(power) - std::log(minimumPower)) / (std::log(maximumPower) - std::log(minimumPower)), 0.0f, 1.0f);
    const float scaled = position * 5.0f;
    const int segment = std::min(static_cast<int>(scaled), 4);
    const float fraction = scaled - static_cast<float>(segment);
    const auto interpolate = [fraction](unsigned char start, unsigned char end)
    {
        return static_cast<unsigned char>(
            std::lround(static_cast<float>(start) + fraction * (static_cast<float>(end) - start)));
    };
    return { interpolate(colors[segment].red, colors[segment + 1].red),
        interpolate(colors[segment].green, colors[segment + 1].green),
        interpolate(colors[segment].blue, colors[segment + 1].blue) };
}

NSString* EffectName(double value)
{
    FxRun1_0* effect = GetFxRun1_0(static_cast<int>(BlkFxParam::getEffectType(static_cast<float>(value))));
    return [NSString stringWithUTF8String:effect ? effect->name() : "Filter"];
}

NSString* ParameterText(Steinberg::Vst::ParamID id, double value)
{
    if(id == BlkFxParam::MIX_BACK)
        return [NSString stringWithFormat:@"%.0f%%", BlkFxParam::getMixBackFrac(value) * 100.0];
    if(id == BlkFxParam::DELAY)
    {
        BlkFxParam::Delay delay(static_cast<float>(value));
        if(delay.getUnits() == BlkFxParam::Delay::BEATS)
            return [NSString stringWithFormat:@"%.2f beats", delay.getAmount()];
        return [NSString stringWithFormat:@"%.0f ms", delay.getAmount()];
    }
    if(id == BlkFxParam::FFT_LEN)
        return [NSString stringWithFormat:@"%d", g_fft_sz[BlkFxParam::getPlan(value)]];
    if(id == BlkFxParam::OVERLAP)
        return [NSString stringWithFormat:@"%.0f%%", BlkFxParam::getOverlapPart(value) * 85.0];

    const int effectParameter = static_cast<int>((id - BlkFxParam::NUM_GLOBAL_PARAMS) % BlkFxParam::NUM_FX_PARAMS);
    switch(effectParameter)
    {
    case BlkFxParam::FX_FREQ_A:
    case BlkFxParam::FX_FREQ_B:
    {
        const float hz = BlkFxParam::getHz(static_cast<float>(value));
        if(hz >= 1000.0f)
            return [NSString stringWithFormat:@"%.2fkHz", hz / 1000.0f];
        return [NSString stringWithFormat:@"%.1fHz", hz];
    }
    case BlkFxParam::FX_AMP:
        return value <= 0.0 ? @"-inf dB" : [NSString stringWithFormat:@"%.1f dB", BlkFxParam::getEffectAmp(value)];
    case BlkFxParam::FX_TYPE:
        return EffectName(value);
    default:
        return [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    }
}

void DrawOutlinedText(NSString* text, NSRect rect, CGFloat size)
{
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary* shadowAttributes = @ {
        NSFontAttributeName : [NSFont boldSystemFontOfSize:size],
        NSForegroundColorAttributeName : NSColor.blackColor,
        NSParagraphStyleAttributeName : paragraph,
    };
    NSDictionary* textAttributes = @ {
        NSFontAttributeName : [NSFont boldSystemFontOfSize:size],
        NSForegroundColorAttributeName : NSColor.whiteColor,
        NSParagraphStyleAttributeName : paragraph,
    };
    for(NSValue* offsetValue in @[
            [NSValue valueWithPoint:NSMakePoint(-1, 0)], [NSValue valueWithPoint:NSMakePoint(1, 0)],
            [NSValue valueWithPoint:NSMakePoint(0, -1)], [NSValue valueWithPoint:NSMakePoint(0, 1)]
        ])
    {
        NSPoint offset = offsetValue.pointValue;
        [text drawInRect:NSOffsetRect(rect, offset.x, offset.y) withAttributes:shadowAttributes];
    }
    [text drawInRect:rect withAttributes:textAttributes];
}
}

@interface DtBlkEditorNSView : NSView
- (instancetype)initWithFrame:(NSRect)frame controller:(DtBlkVst3::Controller*)controller;
- (void)pushSpectrumFrame:(const DtBlkVst3::SpectrumFrame*)frame;
@end

@implementation DtBlkEditorNSView
{
    DtBlkVst3::Controller* _controller;
    NSImage* _globalImage;
    NSImage* _splashImage;
    NSImage* _effectImage;
    NSBitmapImageRep* _spectrumBitmap[2];
    NSImage* _spectrumImage[2];
    NSInteger _spectrumRows[2];
    Steinberg::Vst::ParamID _dragParameter;
    NSRect _dragRect;
}

- (instancetype)initWithFrame:(NSRect)frame controller:(DtBlkVst3::Controller*)controller
{
    self = [super initWithFrame:frame];
    if(self)
    {
        _controller = controller;
        _dragParameter = Steinberg::Vst::kNoParamId;
        NSBundle* bundle = [NSBundle bundleForClass:self.class];
        _globalImage = [[NSImage alloc] initWithContentsOfURL:[bundle URLForResource:@"stereo_global_ctrl"
                                                                       withExtension:@"png"]];
        _splashImage = [[NSImage alloc] initWithContentsOfURL:[bundle URLForResource:@"stereo_splash"
                                                                       withExtension:@"png"]];
        _effectImage = [[NSImage alloc] initWithContentsOfURL:[bundle URLForResource:@"stereo_fx_bg"
                                                                       withExtension:@"png"]];
        for(int index = 0; index < 2; ++index)
        {
            _spectrumBitmap[index] =
                [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                        pixelsWide:DtBlkVst3::SpectrumPixelCount
                                                        pixelsHigh:SpectrumHeights[index]
                                                     bitsPerSample:8
                                                   samplesPerPixel:4
                                                          hasAlpha:YES
                                                          isPlanar:NO
                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                      bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                                                       bytesPerRow:DtBlkVst3::SpectrumPixelCount * 4
                                                      bitsPerPixel:32];
            std::memset(_spectrumBitmap[index].bitmapData, 0,
                static_cast<std::size_t>(_spectrumBitmap[index].bytesPerRow) * SpectrumHeights[index]);
            _spectrumImage[index] =
                [[NSImage alloc] initWithSize:NSMakeSize(DtBlkVst3::SpectrumPixelCount, SpectrumHeights[index])];
            [_spectrumImage[index] addRepresentation:_spectrumBitmap[index]];
            _spectrumRows[index] = 0;
        }
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    [NSColor.blackColor setFill];
    NSRectFill(self.bounds);

    [_globalImage drawInRect:NSMakeRect(0, 0, EditorWidth, GlobalHeight)];
    [_splashImage drawInRect:NSMakeRect(0, GlobalHeight, EditorWidth, SpectrumHeight)];

    CGFloat spectrumY = GlobalHeight + 1.0;
    for(int index = 0; index < 2; ++index)
    {
        if(_spectrumRows[index] > 0)
        {
            [_spectrumImage[index]
                    drawInRect:NSMakeRect(5.0, spectrumY, DtBlkVst3::SpectrumPixelCount, SpectrumHeights[index])
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationCopy
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
        }
        DrawOutlinedText(
            index == 0 ? @"Input L+R" : @"Output L+R", NSMakeRect(285.0, spectrumY + 2.0, 115.0, 13.0), 9.0);
        spectrumY += SpectrumHeights[index] + 3.0;
    }

    const NSRect source = NSMakeRect(0, _effectImage.size.height - EffectHeight, EditorWidth, EffectHeight);
    for(int row = 0; row < BlkFxParam::NUM_FX_SETS; ++row)
    {
        NSRect destination
            = NSMakeRect(0, GlobalHeight + SpectrumHeight + row * EffectHeight, EditorWidth, EffectHeight);
        [_effectImage drawInRect:destination fromRect:source operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    const CGFloat globalColumn = EditorWidth / 6.0;
    for(int column = 0; column < 6; ++column)
    {
        NSString* text = nil;
        if(column == 0)
            text = ParameterText(BlkFxParam::MIX_BACK, _controller->getParamNormalized(BlkFxParam::MIX_BACK));
        else if(column == 1)
            text
                = BlkFxParam::getPwrMatch(_controller->getParamNormalized(BlkFxParam::MIX_BACK)) ? @"match" : @"filter";
        else if(column == 2)
            text = ParameterText(BlkFxParam::DELAY, _controller->getParamNormalized(BlkFxParam::DELAY));
        else if(column == 3)
            text = ParameterText(BlkFxParam::OVERLAP, _controller->getParamNormalized(BlkFxParam::OVERLAP));
        else if(column == 4)
            text = BlkFxParam::getBlkSync(_controller->getParamNormalized(BlkFxParam::OVERLAP)) ? @"on" : @"off";
        else
            text = ParameterText(BlkFxParam::FFT_LEN, _controller->getParamNormalized(BlkFxParam::FFT_LEN));
        DrawOutlinedText(text, NSMakeRect(column * globalColumn, 12, globalColumn, 14), 9.0);
    }

    const CGFloat effectWidths[] = { 82.0, 82.0, 49.0, 98.0, 99.0 };
    for(int row = 0; row < BlkFxParam::NUM_FX_SETS; ++row)
    {
        CGFloat x = 0.0;
        for(int column = 0; column < BlkFxParam::NUM_FX_PARAMS; ++column)
        {
            const Steinberg::Vst::ParamID id = BlkFxParam::paramOffs(row) + column;
            DrawOutlinedText(ParameterText(id, _controller->getParamNormalized(id)),
                NSMakeRect(x, GlobalHeight + SpectrumHeight + row * EffectHeight + 5, effectWidths[column], 15), 10.0);
            x += effectWidths[column];
        }
    }
}

- (void)pushSpectrumFrame:(const DtBlkVst3::SpectrumFrame*)frame
{
    if(!frame)
        return;
    const std::array<float, DtBlkVst3::SpectrumPixelCount>* powers[] = {
        &frame->inputPower,
        &frame->outputPower,
    };
    for(int index = 0; index < 2; ++index)
    {
        const NSInteger rowBytes = _spectrumBitmap[index].bytesPerRow;
        unsigned char* pixels = _spectrumBitmap[index].bitmapData;
        std::memmove(pixels, pixels + rowBytes, static_cast<std::size_t>(rowBytes) * (SpectrumHeights[index] - 1));
        unsigned char* destination = pixels + rowBytes * (SpectrumHeights[index] - 1);
        for(std::size_t pixel = 0; pixel < DtBlkVst3::SpectrumPixelCount; ++pixel)
        {
            const SpectrumColor color = MapSpectrumColor((*powers[index])[pixel]);
            destination[pixel * 4] = color.red;
            destination[pixel * 4 + 1] = color.green;
            destination[pixel * 4 + 2] = color.blue;
            destination[pixel * 4 + 3] = 255;
        }
        _spectrumRows[index] = std::min(_spectrumRows[index] + 1, SpectrumHeights[index]);
    }
    [self setNeedsDisplay:YES];
}

- (BOOL)resolveParameterAtPoint:(NSPoint)point id:(Steinberg::Vst::ParamID*)id rect:(NSRect*)rect
{
    if(point.y < GlobalHeight)
    {
        const CGFloat width = EditorWidth / 6.0;
        const int column = std::clamp(static_cast<int>(point.x / width), 0, 5);
        const Steinberg::Vst::ParamID ids[] = { BlkFxParam::MIX_BACK, BlkFxParam::MIX_BACK, BlkFxParam::DELAY,
            BlkFxParam::OVERLAP, BlkFxParam::OVERLAP, BlkFxParam::FFT_LEN };
        *id = ids[column];
        *rect = NSMakeRect(column * width, 0, width, GlobalHeight);
        return YES;
    }

    const CGFloat effectsTop = GlobalHeight + SpectrumHeight;
    if(point.y < effectsTop || point.y >= EditorHeight)
        return NO;

    const int row = std::clamp(
        static_cast<int>((point.y - effectsTop) / EffectHeight), 0, static_cast<int>(BlkFxParam::NUM_FX_SETS) - 1);
    const CGFloat widths[] = { 82.0, 82.0, 49.0, 98.0, 99.0 };
    CGFloat x = 0.0;
    for(int column = 0; column < BlkFxParam::NUM_FX_PARAMS; ++column)
    {
        if(point.x < x + widths[column] || column == BlkFxParam::NUM_FX_PARAMS - 1)
        {
            *id = BlkFxParam::paramOffs(row) + column;
            *rect = NSMakeRect(x, effectsTop + row * EffectHeight, widths[column], EffectHeight);
            return YES;
        }
        x += widths[column];
    }
    return NO;
}

- (void)showEffectMenuForParameter:(Steinberg::Vst::ParamID)id event:(NSEvent*)event
{
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Effect"];
    for(int index = 0; index < g_num_fx_1_0; ++index)
    {
        FxRun1_0* effect = GetFxRun1_0(index);
        if(!effect || std::strcmp(effect->name(), "DoNotUse") == 0)
            continue;
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:effect->name()]
                                                      action:@selector(selectEffect:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = index;
        item.representedObject = @(id);
        [menu addItem:item];
    }
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)selectEffect:(NSMenuItem*)item
{
    const auto id = static_cast<Steinberg::Vst::ParamID>([item.representedObject unsignedIntValue]);
    _controller->editParameter(id, BlkFxParam::getEffectTypeInv(item.tag));
}

- (void)applyPoint:(NSPoint)point
{
    if(_dragParameter == Steinberg::Vst::kNoParamId)
        return;
    const int effectParameter = _dragParameter >= BlkFxParam::NUM_GLOBAL_PARAMS
        ? static_cast<int>((_dragParameter - BlkFxParam::NUM_GLOBAL_PARAMS) % BlkFxParam::NUM_FX_PARAMS)
        : -1;
    double value = std::clamp((point.x - NSMinX(_dragRect)) / NSWidth(_dragRect), 0.0, 1.0);
    if(_dragParameter == BlkFxParam::MIX_BACK)
    {
        const double current = _controller->getParamNormalized(_dragParameter);
        value = BlkFxParam::getMixbackParam(value, BlkFxParam::getPwrMatch(current));
    }
    else if(_dragParameter == BlkFxParam::OVERLAP)
    {
        const double current = _controller->getParamNormalized(_dragParameter);
        value = BlkFxParam::getOverlapParam(value, BlkFxParam::getBlkSync(current));
    }
    else if(_dragParameter == BlkFxParam::FFT_LEN)
    {
        const int plan = std::clamp(static_cast<int>(value * NUM_FFT_SZ), 0, NUM_FFT_SZ - 1);
        value = BlkFxParam::getFFTLenParam(plan);
    }
    else if(effectParameter == BlkFxParam::FX_TYPE)
        return;
    _controller->editParameter(_dragParameter, value);
}

- (void)mouseDown:(NSEvent*)event
{
    const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if(![self resolveParameterAtPoint:point id:&_dragParameter rect:&_dragRect])
        return;

    if(point.y < GlobalHeight)
    {
        const int column = std::clamp(static_cast<int>(point.x / (EditorWidth / 6.0)), 0, 5);
        if(column == 1)
        {
            const double current = _controller->getParamNormalized(BlkFxParam::MIX_BACK);
            _controller->editParameter(BlkFxParam::MIX_BACK,
                BlkFxParam::getMixbackParam(BlkFxParam::getMixBackFrac(current), !BlkFxParam::getPwrMatch(current)));
            _dragParameter = Steinberg::Vst::kNoParamId;
            return;
        }
        if(column == 4)
        {
            const double current = _controller->getParamNormalized(BlkFxParam::OVERLAP);
            _controller->editParameter(BlkFxParam::OVERLAP,
                BlkFxParam::getOverlapParam(BlkFxParam::getOverlapPart(current), !BlkFxParam::getBlkSync(current)));
            _dragParameter = Steinberg::Vst::kNoParamId;
            return;
        }
    }

    const int effectParameter = _dragParameter >= BlkFxParam::NUM_GLOBAL_PARAMS
        ? static_cast<int>((_dragParameter - BlkFxParam::NUM_GLOBAL_PARAMS) % BlkFxParam::NUM_FX_PARAMS)
        : -1;
    if(effectParameter == BlkFxParam::FX_TYPE)
    {
        [self showEffectMenuForParameter:_dragParameter event:event];
        _dragParameter = Steinberg::Vst::kNoParamId;
        return;
    }
    [self applyPoint:point];
}

- (void)mouseDragged:(NSEvent*)event
{
    [self applyPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseUp:(NSEvent*)event
{
    _dragParameter = Steinberg::Vst::kNoParamId;
}
@end

namespace DtBlkVst3
{
EditorView::EditorView(Controller* controllerValue)
    : controller(controllerValue)
{
    rect = Steinberg::ViewRect(
        0, 0, static_cast<Steinberg::int32>(EditorWidth), static_cast<Steinberg::int32>(EditorHeight));
    controller->addEditor(this);
}

EditorView::~EditorView()
{
    if(nativeView)
        removed();
    controller->removeEditor(this);
}

Steinberg::tresult PLUGIN_API EditorView::isPlatformTypeSupported(Steinberg::FIDString type)
{
    return type && std::strcmp(type, Steinberg::kPlatformTypeNSView) == 0 ? Steinberg::kResultTrue
                                                                          : Steinberg::kResultFalse;
}

Steinberg::tresult PLUGIN_API EditorView::attached(void* parent, Steinberg::FIDString type)
{
    if(!parent || nativeView || isPlatformTypeSupported(type) != Steinberg::kResultTrue)
        return Steinberg::kInvalidArgument;
    systemWindow = parent;
    NSView* parentView = (__bridge NSView*)parent;
    DtBlkEditorNSView* view = [[DtBlkEditorNSView alloc] initWithFrame:NSMakeRect(0, 0, EditorWidth, EditorHeight)
                                                            controller:controller];
    [parentView addSubview:view];
    nativeView = (__bridge void*)view;
    return Steinberg::kResultTrue;
}

Steinberg::tresult PLUGIN_API EditorView::removed()
{
    if(nativeView)
    {
        DtBlkEditorNSView* view = (__bridge DtBlkEditorNSView*)nativeView;
        [view removeFromSuperview];
        nativeView = nullptr;
    }
    systemWindow = nullptr;
    return Steinberg::kResultTrue;
}

Steinberg::tresult PLUGIN_API EditorView::onSize(Steinberg::ViewRect* size)
{
    if(!size || size->getWidth() != static_cast<Steinberg::int32>(EditorWidth)
        || size->getHeight() != static_cast<Steinberg::int32>(EditorHeight))
        return Steinberg::kResultFalse;
    rect = *size;
    if(nativeView)
        [(__bridge DtBlkEditorNSView*)nativeView setFrameSize:NSMakeSize(EditorWidth, EditorHeight)];
    return Steinberg::kResultTrue;
}

void EditorView::invalidate()
{
    if(nativeView)
        [(__bridge DtBlkEditorNSView*)nativeView setNeedsDisplay:YES];
}

void EditorView::pushSpectrumFrame(const SpectrumFrame& frame)
{
    if(nativeView)
        [(__bridge DtBlkEditorNSView*)nativeView pushSpectrumFrame:&frame];
}
}
