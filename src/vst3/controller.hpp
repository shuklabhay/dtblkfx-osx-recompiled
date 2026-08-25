// Publishes the original 44-parameter model through the VST3 controller API.
#pragma once

#include "public.sdk/source/vst/vsteditcontroller.h"
#include "public.sdk/source/vst/utility/dataexchange.h"
#include "spectrum.hpp"

#include <vector>

namespace DtBlkVst3
{
class EditorView;

class Controller final : public Steinberg::Vst::EditControllerEx1, public Steinberg::Vst::IDataExchangeReceiver
{
public:
    OBJ_METHODS(Controller, Steinberg::Vst::EditControllerEx1)
    DEFINE_INTERFACES
    DEF_INTERFACE(Steinberg::Vst::IDataExchangeReceiver)
    END_DEFINE_INTERFACES(Steinberg::Vst::EditControllerEx1)
    REFCOUNT_METHODS(Steinberg::Vst::EditControllerEx1)

    static Steinberg::FUnknown* createInstance(void*);

    Steinberg::tresult PLUGIN_API initialize(Steinberg::FUnknown* context) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setComponentState(Steinberg::IBStream* state) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setState(Steinberg::IBStream* state) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API getState(Steinberg::IBStream* state) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API notify(Steinberg::Vst::IMessage* message) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setParamNormalized(
        Steinberg::Vst::ParamID id, Steinberg::Vst::ParamValue value) SMTG_OVERRIDE;
    Steinberg::IPlugView* PLUGIN_API createView(Steinberg::FIDString name) SMTG_OVERRIDE;

    void PLUGIN_API queueOpened(Steinberg::Vst::DataExchangeUserContextID userContextID, Steinberg::uint32 blockSize,
        Steinberg::TBool& dispatchOnBackgroundThread) SMTG_OVERRIDE;
    void PLUGIN_API queueClosed(Steinberg::Vst::DataExchangeUserContextID userContextID) SMTG_OVERRIDE;
    void PLUGIN_API onDataExchangeBlocksReceived(Steinberg::Vst::DataExchangeUserContextID userContextID,
        Steinberg::uint32 numBlocks, Steinberg::Vst::DataExchangeBlock* blocks,
        Steinberg::TBool onBackgroundThread) SMTG_OVERRIDE;

    void addEditor(EditorView* editor);
    void removeEditor(EditorView* editor);
    void editParameter(Steinberg::Vst::ParamID id, Steinberg::Vst::ParamValue value);

private:
    Steinberg::Vst::DataExchangeReceiverHandler spectrumReceiver { this };
    std::vector<EditorView*> editors;
};
}
