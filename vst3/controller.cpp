// Publishes the original 44-parameter model through the VST3 controller API.
#include "port/StdAfx.h"

#include "controller.hpp"

#include "ids.hpp"
#include "state.hpp"
#include "dtblkfx/BlkFxParam.h"

#include "pluginterfaces/base/ustring.h"

#include <array>
#include <cstdio>

namespace DtBlkVst3
{
namespace
{
void ParameterName(Steinberg::Vst::ParamID id, char* output, std::size_t outputSize)
{
    static constexpr const char* globals[] = {"Mixbk", "Delay", "BlkSz", "Ovrlp"};
    static constexpr const char* effects[] = {"FrqA", "FrqB", "Amp", "Fx", "Val"};
    if(id < 4)
        std::snprintf(output, outputSize, "%s", globals[id]);
    else
        std::snprintf(output, outputSize, "%u.%s", static_cast<unsigned>((id - 4) / 5), effects[(id - 4) % 5]);
}

double DefaultValue(Steinberg::Vst::ParamID id)
{
    if(id == BlkFxParam::DELAY)
        return 16.0 / 255.0;
    if(id == BlkFxParam::FFT_LEN)
        return BlkFxParam::getFFTLenParam(16);
    if(id == BlkFxParam::OVERLAP)
        return 0.35;
    return 0.0;
}
}

Steinberg::FUnknown* Controller::createInstance(void*)
{
    return static_cast<Steinberg::Vst::IEditController*>(new Controller());
}

Steinberg::tresult PLUGIN_API Controller::initialize(Steinberg::FUnknown* context)
{
    const Steinberg::tresult result = EditController::initialize(context);
    if(result != Steinberg::kResultOk)
        return result;

    for(Steinberg::Vst::ParamID id = 0; id < LegacyParameterCount; ++id)
    {
        char asciiName[32] {};
        Steinberg::Vst::String128 title {};
        ParameterName(id, asciiName, sizeof(asciiName));
        Steinberg::UString(title, 128).fromAscii(asciiName);
        parameters.addParameter(title, nullptr, 0, DefaultValue(id),
                                Steinberg::Vst::ParameterInfo::kCanAutomate, id);
    }
    parameters.addParameter(STR16("Bypass"), nullptr, 1, 0.0,
                            Steinberg::Vst::ParameterInfo::kCanAutomate |
                                Steinberg::Vst::ParameterInfo::kIsBypass,
                            BypassParameterId);
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Controller::setComponentState(Steinberg::IBStream* stream)
{
    StateData state;
    std::array<float, 44> parameterValues {};
    if(!ReadState(stream, state) || !ExtractLegacyParameters(state.legacyChunk, parameterValues))
        return Steinberg::kResultFalse;

    for(Steinberg::Vst::ParamID id = 0; id < LegacyParameterCount; ++id)
        setParamNormalized(id, parameterValues[id]);
    setParamNormalized(BypassParameterId, state.bypass ? 1.0 : 0.0);
    return Steinberg::kResultOk;
}
}
