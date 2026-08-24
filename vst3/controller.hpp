// Publishes the original 44-parameter model through the VST3 controller API.
#pragma once

#include "public.sdk/source/vst/vsteditcontroller.h"

namespace DtBlkVst3
{
class Controller final : public Steinberg::Vst::EditController
{
public:
    static Steinberg::FUnknown* createInstance(void*);

    Steinberg::tresult PLUGIN_API initialize(Steinberg::FUnknown* context) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setComponentState(Steinberg::IBStream* state) SMTG_OVERRIDE;
};
}
