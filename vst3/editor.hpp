// Hosts the native macOS editor for the VST3 controller.
#pragma once

#include "public.sdk/source/common/pluginview.h"
#include "spectrum.hpp"

namespace DtBlkVst3
{
class Controller;

class EditorView final : public Steinberg::CPluginView
{
public:
    explicit EditorView(Controller* controller);
    ~EditorView() override;

    Steinberg::tresult PLUGIN_API isPlatformTypeSupported(Steinberg::FIDString type) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API attached(void* parent, Steinberg::FIDString type) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API removed() SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API onSize(Steinberg::ViewRect* size) SMTG_OVERRIDE;

    void invalidate();
    void pushSpectrumFrame(const SpectrumFrame& frame);

private:
    Controller* controller {};
    void* nativeView {};
};
}
