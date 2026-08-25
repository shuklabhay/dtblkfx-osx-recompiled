// Verifies the AUv2 wrapper exposes and selects every DtBlkFx factory preset.
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>

#include <cmath>
#include <iostream>

namespace
{
constexpr AudioUnitParameterID ProgramParameterId = 0x10001;
constexpr CFIndex PresetCount = 43;

bool Check(bool condition, const char* message)
{
    if(!condition)
        std::cerr << "FAIL: " << message << '\n';
    return condition;
}
}

int main()
{
    AudioComponentDescription description {};
    description.componentType = 'aufx';
    description.componentSubType = 'DtBF';
    description.componentManufacturer = 'DtFx';
    AudioComponent component = AudioComponentFindNext(nullptr, &description);
    if(!Check(component != nullptr, "DtBlkFx Audio Unit is not registered"))
        return 1;

    AudioUnit unit {};
    if(!Check(AudioComponentInstanceNew(component, &unit) == noErr,
              "Audio Unit instantiation failed") ||
       !Check(AudioUnitInitialize(unit) == noErr, "Audio Unit initialization failed"))
        return 1;

    CFArrayRef presets {};
    UInt32 presetBytes = sizeof(presets);
    if(!Check(AudioUnitGetProperty(unit, kAudioUnitProperty_FactoryPresets,
                                   kAudioUnitScope_Global, 0, &presets,
                                   &presetBytes) == noErr,
              "factory preset list unavailable") ||
       !Check(presets != nullptr && CFArrayGetCount(presets) == PresetCount,
              "factory preset list is incomplete"))
        return 1;

    for(CFIndex index = 0; index < PresetCount; ++index)
    {
        const auto* preset = static_cast<const AUPreset*>(CFArrayGetValueAtIndex(presets, index));
        if(!Check(preset != nullptr && preset->presetNumber == index && preset->presetName != nullptr,
                  "factory preset metadata is invalid") ||
           !Check(AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset,
                                       kAudioUnitScope_Global, 0, preset,
                                       sizeof(*preset)) == noErr,
                  "factory preset selection failed"))
            return 1;

        AudioUnitParameterValue selected {};
        const double expected = static_cast<double>(index) /
                                static_cast<double>(PresetCount - 1);
        if(!Check(AudioUnitGetParameter(unit, ProgramParameterId, kAudioUnitScope_Global,
                                        0, &selected) == noErr,
                  "factory program parameter unavailable") ||
           !Check(std::abs(static_cast<double>(selected) - expected) < 1e-6,
                  "factory preset selected the wrong VST3 program"))
            return 1;
    }

    CFRelease(presets);
    AudioUnitUninitialize(unit);
    AudioComponentInstanceDispose(unit);
    std::cout << "PASS: instantiated AUv2 and selected all 43 factory presets\n";
    return 0;
}
