// Loads, attaches, renders, edits, and removes the DtBlkFx editor through VST3 host APIs.
#import <Cocoa/Cocoa.h>

#include "vst3/ids.hpp"

#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstunits.h"
#include "public.sdk/source/common/memorystream.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"

#include <algorithm>
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
           !Check(controller->getParameterCount() == 46,
                  "expected 44 legacy parameters, bypass, and factory programs") ||
           !Check(controller->getParamNormalized(1) == 0.0, "fresh instances must default Delay to zero"))
            return 1;

        auto unitInfo = Steinberg::U::cast<Steinberg::Vst::IUnitInfo>(controller);
        Steinberg::Vst::ProgramListInfo programListInfo {};
        Steinberg::Vst::String128 lastProgramName {};
        if(!Check(unitInfo != nullptr, "controller does not expose VST3 program lists") ||
           !Check(unitInfo->getProgramListCount() == 1, "expected one factory program list") ||
           !Check(unitInfo->getProgramListInfo(0, programListInfo) == Steinberg::kResultTrue,
                  "factory program list info unavailable") ||
           !Check(programListInfo.programCount == 43, "expected all 43 historical factory presets") ||
           !Check(unitInfo->getProgramName(programListInfo.id, 42, lastProgramName) == Steinberg::kResultTrue,
                  "factory program name unavailable") ||
           !Check(controller->setParamNormalized(DtBlkVst3::ProgramParameterId, 2.0 / 42.0) == Steinberg::kResultOk,
                  "factory program selection failed") ||
           !Check(std::abs(controller->getParamNormalized(5) - 0.635) < 1e-6,
                  "factory program did not update controller parameters"))
            return 1;

        auto view = Steinberg::owned(controller->createView(Steinberg::Vst::ViewType::kEditor));
        if(!Check(view != nullptr, "controller returned no editor") ||
           !Check(view->isPlatformTypeSupported(Steinberg::kPlatformTypeNSView) == Steinberg::kResultTrue,
                  "editor does not support NSView"))
            return 1;

        Steinberg::ViewRect size;
        if(!Check(view->getSize(&size) == Steinberg::kResultTrue, "editor size unavailable") ||
           !Check(size.getWidth() == 410 && size.getHeight() == 439, "unexpected editor dimensions"))
            return 1;

        NSView* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.getWidth(), size.getHeight())];
        if(!Check(view->attached((__bridge void*)parent, Steinberg::kPlatformTypeNSView) == Steinberg::kResultTrue,
                  "editor attach failed") ||
           !Check(parent.subviews.count == 1, "editor did not attach one native child view"))
            return 1;

        NSPopUpButton* presetPopup = nil;
        for(NSView* subview in parent.subviews.firstObject.subviews)
        {
            if([subview isKindOfClass:NSPopUpButton.class])
                presetPopup = static_cast<NSPopUpButton*>(subview);
        }
        if(!Check(presetPopup != nil, "editor has no factory-preset selector") ||
           !Check(presetPopup.numberOfItems == 43, "editor preset selector is incomplete") ||
           !Check(presetPopup.indexOfSelectedItem == 2, "editor preset selector is out of sync"))
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

               Steinberg::Vst::ParameterChanges startupChanges(2);
               Steinberg::int32 startupQueueIndex {};
               Steinberg::int32 startupPointIndex {};
               auto* delayQueue = startupChanges.addParameterData(1, startupQueueIndex);
               auto* startupProgramQueue = startupChanges.addParameterData(
                   DtBlkVst3::ProgramParameterId, startupQueueIndex);
               if(!delayQueue || !startupProgramQueue ||
                  delayQueue->addPoint(0, 0.0, startupPointIndex) != Steinberg::kResultTrue ||
                  startupProgramQueue->addPoint(0, 0.0, startupPointIndex) != Steinberg::kResultTrue)
                   return false;
               data.inputParameterChanges = &startupChanges;
               if(processor->process(data) != Steinberg::kResultOk)
                   return false;
               data.inputParameterChanges = nullptr;
               Steinberg::MemoryStream startupState;
               if(component->getState(&startupState) != Steinberg::kResultOk ||
                  startupState.seek(0, Steinberg::IBStream::kIBSeekSet, nullptr) != Steinberg::kResultOk ||
                  controller->setComponentState(&startupState) != Steinberg::kResultOk ||
                  controller->getParamNormalized(1) != 0.0 ||
                  processor->setProcessing(false) != Steinberg::kResultOk ||
                  processor->setProcessing(true) != Steinberg::kResultOk)
                   return false;

               std::uint32_t noise = 0x12345678;
               struct AudioResult
               {
                   double energy {};
                   std::int64_t firstOutput {-1};
               };
               const auto processAudio = [&] {
                   AudioResult result;
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
                       {
                           result.energy = -1.0;
                           return result;
                       }
                       for(Steinberg::int32 sample = 0; sample < setup.maxSamplesPerBlock; ++sample)
                       {
                           result.energy += std::abs(outputLeft[sample]);
                           if(result.firstOutput < 0 &&
                              (outputLeft[sample] != 0.0f || outputRight[sample] != 0.0f))
                               result.firstOutput = static_cast<std::int64_t>(block) * setup.maxSamplesPerBlock + sample;
                       }
                   }
                   return result;
               };

               const AudioResult firstAudio = processAudio();
               if(firstAudio.energy <= 1.0 || firstAudio.firstOutput != 101)
                   return false;
               [[NSRunLoop currentRunLoop]
                   runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
               NSData* firstSpectrum = Render(parent);
               if([after isEqualToData:firstSpectrum] ||
                  processor->setProcessing(false) != Steinberg::kResultOk ||
                  processor->setProcessing(true) != Steinberg::kResultOk)
                   return false;
               const AudioResult secondAudio = processAudio();
               if(secondAudio.energy <= 1.0 || secondAudio.firstOutput != 101)
                   return false;
               [[NSRunLoop currentRunLoop]
                   runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
               NSData* secondSpectrum = Render(parent);
               if([firstSpectrum isEqualToData:secondSpectrum])
                   return false;

               if(processor->setProcessing(false) != Steinberg::kResultOk ||
                  processor->setProcessing(true) != Steinberg::kResultOk)
                   return false;
               std::fill(inputLeft.begin(), inputLeft.end(), 0.0f);
               std::fill(inputRight.begin(), inputRight.end(), 0.0f);
               inputLeft[0] = 1.0f;
               Steinberg::Vst::ParameterChanges delayedImpulse(1);
               Steinberg::int32 delayedQueueIndex {};
               Steinberg::int32 delayedPointIndex {};
               auto* delayedQueue = delayedImpulse.addParameterData(1, delayedQueueIndex);
               if(!delayedQueue ||
                  delayedQueue->addPoint(0, 16.0 / 255.0, delayedPointIndex) != Steinberg::kResultTrue)
                   return false;
               data.inputParameterChanges = &delayedImpulse;
               if(processor->process(data) != Steinberg::kResultOk)
                   return false;
               std::fill(inputLeft.begin(), inputLeft.end(), 0.0f);

               Steinberg::Vst::ParameterChanges bypassOn(1);
               Steinberg::int32 bypassQueueIndex {};
               Steinberg::int32 bypassPointIndex {};
               auto* bypassOnQueue = bypassOn.addParameterData(DtBlkVst3::BypassParameterId,
                                                                bypassQueueIndex);
               if(!bypassOnQueue ||
                  bypassOnQueue->addPoint(0, 1.0, bypassPointIndex) != Steinberg::kResultTrue)
                   return false;
               data.inputParameterChanges = &bypassOn;
               for(int block = 0; block < 50; ++block)
               {
                   if(processor->process(data) != Steinberg::kResultOk ||
                      !std::equal(outputLeft.begin(), outputLeft.end(), inputLeft.begin()) ||
                      !std::equal(outputRight.begin(), outputRight.end(), inputRight.begin()))
                       return false;
                   data.inputParameterChanges = nullptr;
               }

               Steinberg::Vst::ParameterChanges bypassOff(1);
               auto* bypassOffQueue = bypassOff.addParameterData(DtBlkVst3::BypassParameterId,
                                                                  bypassQueueIndex);
               if(!bypassOffQueue ||
                  bypassOffQueue->addPoint(0, 0.0, bypassPointIndex) != Steinberg::kResultTrue)
                   return false;
               data.inputParameterChanges = &bypassOff;
               float postBypassMaximum = 0.0f;
               for(int block = 0; block < 50; ++block)
               {
                   if(processor->process(data) != Steinberg::kResultOk)
                       return false;
                   data.inputParameterChanges = nullptr;
                   for(float sample : outputLeft)
                       postBypassMaximum = std::max(postBypassMaximum, std::abs(sample));
                   for(float sample : outputRight)
                       postBypassMaximum = std::max(postBypassMaximum, std::abs(sample));
               }
               if(postBypassMaximum > 1e-5f ||
                  processor->setProcessing(false) != Steinberg::kResultOk ||
                  processor->setProcessing(true) != Steinberg::kResultOk)
                   return false;

               Steinberg::Vst::ParameterChanges programChange(1);
               Steinberg::int32 queueIndex {};
               Steinberg::int32 pointIndex {};
               auto* programQueue = programChange.addParameterData(DtBlkVst3::ProgramParameterId, queueIndex);
               if(!programQueue ||
                  programQueue->addPoint(0, 2.0 / 42.0, pointIndex) != Steinberg::kResultTrue)
                   return false;
               data.inputParameterChanges = &programChange;
               if(processor->process(data) != Steinberg::kResultOk)
                   return false;
               data.inputParameterChanges = nullptr;
               Steinberg::MemoryStream componentState;
               if(component->getState(&componentState) != Steinberg::kResultOk ||
                  componentState.seek(0, Steinberg::IBStream::kIBSeekSet, nullptr) != Steinberg::kResultOk ||
                  controller->setComponentState(&componentState) != Steinberg::kResultOk ||
                  std::abs(controller->getParamNormalized(5) - 0.635) > 1e-6 ||
                  std::abs(controller->getParamNormalized(DtBlkVst3::ProgramParameterId) - 2.0 / 42.0) > 1e-9)
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
        std::cout << "PASS: module, preset selector, ordered startup, state, audio, live FFT, bypass continuity, disable/re-enable, NSView lifecycle\n";
        return 0;
    }
}
