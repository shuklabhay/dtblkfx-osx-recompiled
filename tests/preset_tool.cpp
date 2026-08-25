// Generates and reload-validates factory presets through the VST3 host API.
#include "src/vst3/ids.hpp"

#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstunits.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/vstpresetfile.h"

#include <array>
#include <cmath>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

namespace
{
constexpr Steinberg::int32 PresetCount = 43;

bool Check(bool condition, const std::string& message)
{
    if(!condition)
        std::cerr << "FAIL: " << message << '\n';
    return condition;
}

std::string ToAscii(const Steinberg::Vst::TChar* text)
{
    std::string result;
    for(std::size_t index = 0; index < 128; ++index)
    {
        const Steinberg::Vst::TChar character = text[index];
        if(character == 0)
            break;
        result.push_back(character < 128 ? static_cast<char>(character) : '_');
    }
    return result;
}

std::string FileName(Steinberg::int32 index, const std::string& name)
{
    std::string safe = name;
    for(char& character : safe)
    {
        if(character == '/' || character == ':' || character == '\\')
            character = '-';
    }
    std::ostringstream output;
    output << std::setfill('0') << std::setw(2) << index + 1 << ' ' << safe << ".vstpreset";
    return output.str();
}

bool SelectProgram(
    Steinberg::Vst::IEditController* controller, Steinberg::Vst::IAudioProcessor* processor, Steinberg::int32 index)
{
    const double normalized = static_cast<double>(index) / static_cast<double>(PresetCount - 1);
    if(controller->setParamNormalized(DtBlkVst3::ProgramParameterId, normalized) != Steinberg::kResultOk)
        return false;

    Steinberg::Vst::ParameterChanges changes(1);
    Steinberg::int32 queueIndex {};
    Steinberg::int32 pointIndex {};
    auto* queue = changes.addParameterData(DtBlkVst3::ProgramParameterId, queueIndex);
    if(!queue || queue->addPoint(0, normalized, pointIndex) != Steinberg::kResultTrue)
        return false;

    Steinberg::Vst::ProcessData data {};
    data.processMode = Steinberg::Vst::kRealtime;
    data.symbolicSampleSize = Steinberg::Vst::kSample32;
    data.numSamples = 0;
    data.inputParameterChanges = &changes;
    return processor->process(data) == Steinberg::kResultOk;
}
}

int main(int argc, const char* argv[])
{
    if(argc != 3)
    {
        std::cerr << "usage: dtblkfx_presets /path/to/DtBlkFx.vst3 output-directory\n";
        return 2;
    }

    const std::filesystem::path outputDirectory = argv[2];
    std::filesystem::create_directories(outputDirectory);

    std::string error;
    auto module = VST3::Hosting::Module::create(argv[1], error);
    if(!Check(module != nullptr, error))
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
    if(!Check(provider != nullptr, "audio-effect class not found")
        || !Check(provider->initialize(), "plug-in initialization failed"))
        return 1;

    auto component = provider->getComponentPtr();
    auto controller = provider->getControllerPtr();
    auto processor = Steinberg::U::cast<Steinberg::Vst::IAudioProcessor>(component);
    auto unitInfo = Steinberg::U::cast<Steinberg::Vst::IUnitInfo>(controller);
    Steinberg::FUID componentUid;
    Steinberg::Vst::ProgramListInfo listInfo {};
    if(!Check(component != nullptr && controller != nullptr && processor != nullptr && unitInfo != nullptr,
           "required plug-in interfaces unavailable")
        || !Check(provider->getComponentUID(componentUid) == Steinberg::kResultTrue, "component identifier unavailable")
        || !Check(
            unitInfo->getProgramListInfo(0, listInfo) == Steinberg::kResultTrue && listInfo.programCount == PresetCount,
            "factory program list is incomplete"))
        return 1;

    Steinberg::Vst::SpeakerArrangement inputArrangement = Steinberg::Vst::SpeakerArr::kStereo;
    Steinberg::Vst::SpeakerArrangement outputArrangement = Steinberg::Vst::SpeakerArr::kStereo;
    Steinberg::Vst::ProcessSetup setup {};
    setup.processMode = Steinberg::Vst::kRealtime;
    setup.symbolicSampleSize = Steinberg::Vst::kSample32;
    setup.maxSamplesPerBlock = 512;
    setup.sampleRate = 44100.0;
    if(!Check(processor->setBusArrangements(&inputArrangement, 1, &outputArrangement, 1) == Steinberg::kResultOk,
           "stereo bus configuration failed")
        || !Check(processor->setupProcessing(setup) == Steinberg::kResultOk, "processing setup failed")
        || !Check(component->setActive(true) == Steinberg::kResultOk, "component activation failed")
        || !Check(processor->setProcessing(true) == Steinberg::kResultOk, "processing activation failed"))
        return 1;

    for(Steinberg::int32 index = 0; index < PresetCount; ++index)
    {
        Steinberg::Vst::String128 programName {};
        if(!Check(unitInfo->getProgramName(listInfo.id, index, programName) == Steinberg::kResultTrue,
               "factory program name unavailable")
            || !Check(SelectProgram(controller, processor, index), "factory program selection failed"))
            return 1;

        std::array<double, DtBlkVst3::LegacyParameterCount> expected {};
        for(Steinberg::Vst::ParamID parameter = 0; parameter < DtBlkVst3::LegacyParameterCount; ++parameter)
            expected[parameter] = controller->getParamNormalized(parameter);
        const double expectedProgram = controller->getParamNormalized(DtBlkVst3::ProgramParameterId);

        if(!Check(processor->setProcessing(false) == Steinberg::kResultOk, "processing deactivation failed")
            || !Check(component->setActive(false) == Steinberg::kResultOk, "component deactivation failed"))
            return 1;

        const std::filesystem::path path = outputDirectory / FileName(index, ToAscii(programName));
        Steinberg::IPtr<Steinberg::IBStream> output
            = Steinberg::owned(Steinberg::Vst::FileStream::open(path.string().c_str(), "wb"));
        if(!Check(output != nullptr, "could not create " + path.string())
            || !Check(Steinberg::Vst::PresetFile::savePreset(output, componentUid, component, controller, nullptr, 0),
                "could not write " + path.string()))
            return 1;
        output = nullptr;

        controller->setParamNormalized(DtBlkVst3::ProgramParameterId, index == 0 ? 1.0 : 0.0);
        Steinberg::IPtr<Steinberg::IBStream> input
            = Steinberg::owned(Steinberg::Vst::FileStream::open(path.string().c_str(), "rb"));
        if(!Check(input != nullptr, "could not reopen " + path.string())
            || !Check(Steinberg::Vst::PresetFile::loadPreset(input, componentUid, component, controller),
                "could not reload " + path.string()))
            return 1;

        for(Steinberg::Vst::ParamID parameter = 0; parameter < DtBlkVst3::LegacyParameterCount; ++parameter)
        {
            if(!Check(std::abs(controller->getParamNormalized(parameter) - expected[parameter]) < 1e-7,
                   "reloaded parameter mismatch in " + path.string()))
                return 1;
        }
        if(!Check(std::abs(controller->getParamNormalized(DtBlkVst3::ProgramParameterId) - expectedProgram) < 1e-7,
               "reloaded program mismatch in " + path.string()))
            return 1;

        if(index + 1 < PresetCount
            && (!Check(component->setActive(true) == Steinberg::kResultOk, "component reactivation failed")
                || !Check(processor->setProcessing(true) == Steinberg::kResultOk, "processing reactivation failed")))
            return 1;
    }

    Steinberg::Vst::PluginContextFactory::instance().setPluginContext(nullptr);
    std::cout << "PASS: generated and reloaded 43 VST3 factory presets\n";
    return 0;
}
