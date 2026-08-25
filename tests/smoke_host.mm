// Loads, attaches, renders, edits, and removes the DtBlkFx editor through VST3 host APIs.
#import <Cocoa/Cocoa.h>

#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "public.sdk/source/common/memorystream.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace
{
bool Check(bool condition, const char* message)
{
    if(!condition)
        std::cerr << "FAIL: " << message << '\n';
    return condition;
}

NSData* Render(NSView* parent)
{
    [parent setNeedsDisplay:YES];
    [parent displayIfNeeded];
    NSBitmapImageRep* bitmap = [parent bitmapImageRepForCachingDisplayInRect:parent.bounds];
    [parent cacheDisplayInRect:parent.bounds toBitmapImageRep:bitmap];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
}

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc != 2)
        {
            std::cerr << "usage: dtblkfx_smoke /path/to/DtBlkFx.vst3\n";
            return 2;
        }

        [NSApplication sharedApplication];
        std::string error;
        auto module = VST3::Hosting::Module::create(argv[1], error);
        if(!Check(module != nullptr, error.c_str()))
            return 1;

        auto factory = module->getFactory();
        Steinberg::Vst::HostApplication host;
        factory.setHostContext(&host);
        Steinberg::Vst::PluginContextFactory::instance().setPluginContext(&host);

        std::unique_ptr<Steinberg::Vst::PlugProvider> provider;
        for(const auto& info : factory.classInfos())
        {
            if(info.category() == kVstAudioEffectClass)
            {
                provider = std::make_unique<Steinberg::Vst::PlugProvider>(factory, info, true);
                break;
            }
        }
        if(!Check(provider != nullptr, "audio-effect class not found") ||
           !Check(provider->initialize(), "plug-in initialization failed"))
            return 1;

        auto controller = provider->getControllerPtr();
        if(!Check(controller != nullptr, "edit controller not found") ||
           !Check(controller->getParameterCount() == 45, "expected 44 legacy parameters plus bypass"))
            return 1;

        auto view = Steinberg::owned(controller->createView(Steinberg::Vst::ViewType::kEditor));
        if(!Check(view != nullptr, "controller returned no editor") ||
           !Check(view->isPlatformTypeSupported(Steinberg::kPlatformTypeNSView) == Steinberg::kResultTrue,
                  "editor does not support NSView"))
            return 1;

        Steinberg::ViewRect size;
        if(!Check(view->getSize(&size) == Steinberg::kResultTrue, "editor size unavailable") ||
           !Check(size.getWidth() == 410 && size.getHeight() == 409, "unexpected editor dimensions"))
            return 1;

        NSView* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.getWidth(), size.getHeight())];
        if(!Check(view->attached((__bridge void*)parent, Steinberg::kPlatformTypeNSView) == Steinberg::kResultTrue,
                  "editor attach failed") ||
           !Check(parent.subviews.count == 1, "editor did not attach one native child view"))
            return 1;

        NSData* before = Render(parent);
        if(!Check(before.length > 25000, "editor render is empty or implausibly small"))
            return 1;

        const Steinberg::Vst::ParamValue changedValue = 0.25;
        if(!Check(controller->setParamNormalized(4, changedValue) == Steinberg::kResultOk,
                  "host parameter edit failed") ||
           !Check(std::abs(controller->getParamNormalized(4) - changedValue) < 1e-9,
                  "host parameter edit did not round-trip"))
            return 1;

        NSData* after = Render(parent);
        if(!Check(![before isEqualToData:after], "editor did not redraw after a host parameter edit") ||
           !Check([&] {
               Steinberg::MemoryStream state;
               if(controller->getState(&state) != Steinberg::kResultOk ||
                  state.seek(0, Steinberg::IBStream::kIBSeekSet, nullptr) != Steinberg::kResultOk ||
                  controller->setParamNormalized(4, 0.75) != Steinberg::kResultOk ||
                  controller->setState(&state) != Steinberg::kResultOk)
                   return false;
               return std::abs(controller->getParamNormalized(4) - changedValue) < 1e-9;
           }(), "controller state did not round-trip") ||
           !Check([&] {
               auto component = provider->getComponentPtr();
               auto processor = Steinberg::U::cast<Steinberg::Vst::IAudioProcessor>(component);
               if(!component || !processor)
                   return false;

               Steinberg::Vst::SpeakerArrangement inputArrangement = Steinberg::Vst::SpeakerArr::kStereo;
               Steinberg::Vst::SpeakerArrangement outputArrangement = Steinberg::Vst::SpeakerArr::kStereo;
               Steinberg::Vst::ProcessSetup setup {};
               setup.processMode = Steinberg::Vst::kRealtime;
               setup.symbolicSampleSize = Steinberg::Vst::kSample32;
               setup.maxSamplesPerBlock = 512;
               setup.sampleRate = 44100.0;
               if(processor->setBusArrangements(&inputArrangement, 1, &outputArrangement, 1) != Steinberg::kResultOk ||
                  processor->setupProcessing(setup) != Steinberg::kResultOk ||
                  component->activateBus(Steinberg::Vst::kAudio, Steinberg::Vst::kInput, 0, true) != Steinberg::kResultOk ||
                  component->activateBus(Steinberg::Vst::kAudio, Steinberg::Vst::kOutput, 0, true) != Steinberg::kResultOk ||
                  component->setActive(true) != Steinberg::kResultOk ||
                  processor->setProcessing(true) != Steinberg::kResultOk)
                   return false;

               std::vector<float> inputLeft(setup.maxSamplesPerBlock);
               std::vector<float> inputRight(setup.maxSamplesPerBlock);
               std::vector<float> outputLeft(setup.maxSamplesPerBlock);
               std::vector<float> outputRight(setup.maxSamplesPerBlock);
               float* inputChannels[] = {inputLeft.data(), inputRight.data()};
               float* outputChannels[] = {outputLeft.data(), outputRight.data()};
               Steinberg::Vst::AudioBusBuffers inputBus {};
               inputBus.numChannels = 2;
               inputBus.channelBuffers32 = inputChannels;
               Steinberg::Vst::AudioBusBuffers outputBus {};
               outputBus.numChannels = 2;
               outputBus.channelBuffers32 = outputChannels;
               Steinberg::Vst::ProcessData data {};
               data.processMode = Steinberg::Vst::kRealtime;
               data.symbolicSampleSize = Steinberg::Vst::kSample32;
               data.numSamples = setup.maxSamplesPerBlock;
               data.numInputs = 1;
               data.numOutputs = 1;
               data.inputs = &inputBus;
               data.outputs = &outputBus;

               std::uint32_t noise = 0x12345678;
               const auto processAudio = [&] {
                   double outputEnergy = 0.0;
                   for(int block = 0; block < 128; ++block)
                   {
                       for(Steinberg::int32 sample = 0; sample < setup.maxSamplesPerBlock; ++sample)
                       {
                           noise = noise * 1664525U + 1013904223U;
                           const float value = (static_cast<float>(noise >> 8U) / 8388608.0f - 1.0f) * 0.15f;
                           inputLeft[sample] = value;
                           inputRight[sample] = value * 0.7f;
                       }
                       if(processor->process(data) != Steinberg::kResultOk)
                           return -1.0;
                       for(float sample : outputLeft)
                           outputEnergy += std::abs(sample);
                   }
                   return outputEnergy;
               };

               const double firstEnergy = processAudio();
               if(firstEnergy <= 1.0)
                   return false;
               [[NSRunLoop currentRunLoop]
                   runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
               NSData* firstSpectrum = Render(parent);
               if([after isEqualToData:firstSpectrum] ||
                  processor->setProcessing(false) != Steinberg::kResultOk ||
                  processor->setProcessing(true) != Steinberg::kResultOk)
                   return false;
               const double secondEnergy = processAudio();
               if(secondEnergy <= 1.0)
                   return false;
               [[NSRunLoop currentRunLoop]
                   runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
               NSData* secondSpectrum = Render(parent);
               if([firstSpectrum isEqualToData:secondSpectrum])
                   return false;
               if(const char* screenshotPath = std::getenv("DTBLKFX_SMOKE_PNG"))
               {
                   if(![secondSpectrum writeToFile:[NSString stringWithUTF8String:screenshotPath]
                                        atomically:YES])
                       return false;
               }
               if(processor->setProcessing(false) != Steinberg::kResultOk)
                   return false;
               component->setActive(false);
               return true;
           }(), "audio, live FFT, or disable/re-enable cycle failed") ||
           !Check(view->removed() == Steinberg::kResultTrue, "editor removal failed") ||
           !Check(parent.subviews.count == 0, "native child view survived editor removal"))
            return 1;

        Steinberg::Vst::PluginContextFactory::instance().setPluginContext(nullptr);
        std::cout << "PASS: module, controller, state, audio, live FFT, disable/re-enable, NSView lifecycle\n";
        return 0;
    }
}
