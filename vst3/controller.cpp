// Publishes the original 44-parameter model through the VST3 controller API.
#include "port/StdAfx.h"

#include "controller.hpp"

#include "editor.hpp"
#include "ids.hpp"
#include "state.hpp"
#include "dtblkfx/BlkFxParam.h"
#include "port/legacy_runtime.hpp"

#include "base/source/fstreamer.h"
#include "pluginterfaces/base/ustring.h"

#include <array>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace DtBlkVst3
{
namespace
{
    constexpr Steinberg::int32 ControllerStateMagic = 0x44544333;
    constexpr Steinberg::int32 ControllerStateVersion = 1;

    void ParameterName(Steinberg::Vst::ParamID id, char* output, std::size_t outputSize)
    {
        static constexpr const char* globals[] = { "Mixbk", "Delay", "BlkSz", "Ovrlp" };
        static constexpr const char* effects[] = { "FrqA", "FrqB", "Amp", "Fx", "Val" };
        if(id < 4)
            std::snprintf(output, outputSize, "%s", globals[id]);
        else
            std::snprintf(output, outputSize, "%u.%s", static_cast<unsigned>((id - 4) / 5), effects[(id - 4) % 5]);
    }

    double DefaultValue(Steinberg::Vst::ParamID id) { return LegacyDefaultParameter(id); }
}

Steinberg::FUnknown* Controller::createInstance(void*)
{
    return static_cast<Steinberg::Vst::IEditController*>(new Controller());
}

Steinberg::tresult PLUGIN_API Controller::initialize(Steinberg::FUnknown* context)
{
    const Steinberg::tresult result = EditControllerEx1::initialize(context);
    if(result != Steinberg::kResultOk)
        return result;
    if(!InitializeLegacyRuntime())
        return Steinberg::kResultFalse;

    for(Steinberg::Vst::ParamID id = 0; id < LegacyParameterCount; ++id)
    {
        char asciiName[32] {};
        Steinberg::Vst::String128 title {};
        ParameterName(id, asciiName, sizeof(asciiName));
        Steinberg::UString(title, 128).fromAscii(asciiName);
        parameters.addParameter(title, nullptr, 0, DefaultValue(id), Steinberg::Vst::ParameterInfo::kCanAutomate, id);
    }
    parameters.addParameter(STR16("Bypass"), nullptr, 1, 0.0,
        Steinberg::Vst::ParameterInfo::kCanAutomate | Steinberg::Vst::ParameterInfo::kIsBypass, BypassParameterId);

    addUnit(new Steinberg::Vst::Unit(
        STR16("Root"), Steinberg::Vst::kRootUnitId, Steinberg::Vst::kNoParentUnitId, FactoryProgramListId));
    auto* programList
        = new Steinberg::Vst::ProgramList(STR16("Factory Presets"), FactoryProgramListId, Steinberg::Vst::kRootUnitId);
    addProgramList(programList);
    for(std::size_t index = 0; index < LegacyPresetCount(); ++index)
    {
        Steinberg::Vst::String128 name {};
        Steinberg::UString(name, 128).fromAscii(LegacyPresetName(index));
        programList->addProgram(name);
    }
    Steinberg::Vst::Parameter* programParameter = programList->getParameter();
    programParameter->getInfo().id = ProgramParameterId;
    programParameter->getInfo().flags &= ~Steinberg::Vst::ParameterInfo::kCanAutomate;
    parameters.addParameter(programParameter);
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Controller::setComponentState(Steinberg::IBStream* stream)
{
    StateData state;
    std::array<float, 44> parameterValues {};
    Steinberg::int32 program {};
    if(!ReadState(stream, state) || !ExtractLegacyParameters(state.legacyChunk, parameterValues))
        return Steinberg::kResultFalse;

    for(Steinberg::Vst::ParamID id = 0; id < LegacyParameterCount; ++id)
        setParamNormalized(id, parameterValues[id]);
    setParamNormalized(BypassParameterId, state.bypass ? 1.0 : 0.0);
    if(ExtractLegacyProgram(state.legacyChunk, program) && LegacyPresetCount() > 1)
        EditControllerEx1::setParamNormalized(ProgramParameterId,
            static_cast<double>(
                std::clamp<Steinberg::int32>(program, 0, static_cast<Steinberg::int32>(LegacyPresetCount() - 1)))
                / static_cast<double>(LegacyPresetCount() - 1));
    for(EditorView* editor : editors)
        editor->invalidate();
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Controller::setState(Steinberg::IBStream* stream)
{
    if(!stream)
        return Steinberg::kInvalidArgument;

    Steinberg::IBStreamer reader(stream, kLittleEndian);
    Steinberg::int32 magic {};
    Steinberg::int32 version {};
    Steinberg::int32 count {};
    if(!reader.readInt32(magic) || magic != ControllerStateMagic || !reader.readInt32(version)
        || version != ControllerStateVersion || !reader.readInt32(count) || count != getParameterCount())
        return Steinberg::kResultFalse;

    for(Steinberg::int32 index = 0; index < count; ++index)
    {
        Steinberg::Vst::ParamValue value {};
        if(!reader.readDouble(value))
            return Steinberg::kResultFalse;
        const Steinberg::Vst::ParameterInfo info = parameters.getParameterByIndex(index)->getInfo();
        if(EditControllerEx1::setParamNormalized(info.id, value) != Steinberg::kResultOk)
            return Steinberg::kResultFalse;
    }
    for(EditorView* editor : editors)
        editor->invalidate();
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Controller::getState(Steinberg::IBStream* stream)
{
    if(!stream)
        return Steinberg::kInvalidArgument;

    Steinberg::IBStreamer writer(stream, kLittleEndian);
    const Steinberg::int32 count = getParameterCount();
    if(!writer.writeInt32(ControllerStateMagic) || !writer.writeInt32(ControllerStateVersion)
        || !writer.writeInt32(count))
        return Steinberg::kResultFalse;

    for(Steinberg::int32 index = 0; index < count; ++index)
    {
        const Steinberg::Vst::ParameterInfo info = parameters.getParameterByIndex(index)->getInfo();
        if(!writer.writeDouble(getParamNormalized(info.id)))
            return Steinberg::kResultFalse;
    }
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Controller::notify(Steinberg::Vst::IMessage* message)
{
    if(spectrumReceiver.onMessage(message))
        return Steinberg::kResultTrue;
    return EditControllerEx1::notify(message);
}

void PLUGIN_API Controller::queueOpened(
    Steinberg::Vst::DataExchangeUserContextID, Steinberg::uint32, Steinberg::TBool& dispatchOnBackgroundThread)
{
    dispatchOnBackgroundThread = false;
}

void PLUGIN_API Controller::queueClosed(Steinberg::Vst::DataExchangeUserContextID) { }

void PLUGIN_API Controller::onDataExchangeBlocksReceived(Steinberg::Vst::DataExchangeUserContextID userContextID,
    Steinberg::uint32 numBlocks, Steinberg::Vst::DataExchangeBlock* blocks, Steinberg::TBool)
{
    if(userContextID != SpectrumExchangeContext || !blocks)
        return;
    for(Steinberg::uint32 index = 0; index < numBlocks; ++index)
    {
        if(blocks[index].size < sizeof(SpectrumFrame) || !blocks[index].data)
            continue;
        const auto& frame = *static_cast<const SpectrumFrame*>(blocks[index].data);
        for(EditorView* editor : editors)
            editor->pushSpectrumFrame(frame);
    }
}

Steinberg::tresult PLUGIN_API Controller::setParamNormalized(
    Steinberg::Vst::ParamID id, Steinberg::Vst::ParamValue value)
{
    const Steinberg::tresult result = EditControllerEx1::setParamNormalized(id, value);
    if(result == Steinberg::kResultOk)
    {
        if(id == ProgramParameterId && LegacyPresetCount() > 0)
        {
            const std::size_t index = static_cast<std::size_t>(
                std::lround(std::clamp(value, 0.0, 1.0) * static_cast<double>(LegacyPresetCount() - 1)));
            std::array<float, 44> preset {};
            if(ReadLegacyPreset(index, preset))
            {
                for(Steinberg::Vst::ParamID parameter = 0; parameter < LegacyParameterCount; ++parameter)
                    EditControllerEx1::setParamNormalized(parameter, preset[parameter]);
                if(componentHandler)
                    componentHandler->restartComponent(Steinberg::Vst::kParamValuesChanged);
            }
        }
        for(EditorView* editor : editors)
            editor->invalidate();
    }
    return result;
}

Steinberg::IPlugView* PLUGIN_API Controller::createView(Steinberg::FIDString name)
{
    if(!name || std::strcmp(name, Steinberg::Vst::ViewType::kEditor) != 0)
        return nullptr;
    return new EditorView(this);
}

void Controller::addEditor(EditorView* editor)
{
    const bool enableSpectrum = editors.empty();
    editors.push_back(editor);
    if(enableSpectrum)
        sendMessageID(SpectrumEnableMessage);
}

void Controller::removeEditor(EditorView* editor)
{
    editors.erase(std::remove(editors.begin(), editors.end(), editor), editors.end());
    if(editors.empty())
        sendMessageID(SpectrumDisableMessage);
}

void Controller::editParameter(Steinberg::Vst::ParamID id, Steinberg::Vst::ParamValue value)
{
    value = std::clamp(value, 0.0, 1.0);
    beginEdit(id);
    setParamNormalized(id, value);
    performEdit(id, value);
    endEdit(id);
}
}
