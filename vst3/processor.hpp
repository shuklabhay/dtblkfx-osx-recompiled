// Connects the preserved DtBlkFx processing engine to the VST3 audio API.
#pragma once

#include "public.sdk/source/vst/vstaudioeffect.h"
#include "public.sdk/source/vst/utility/dataexchange.h"
#include "spectrum.hpp"

#include <array>
#include <memory>

class DtBlkFx;

namespace DtBlkVst3
{
class Processor final : public Steinberg::Vst::AudioEffect
{
public:
    Processor();
    ~Processor() SMTG_OVERRIDE;

    static Steinberg::FUnknown* createInstance(void*);

    Steinberg::tresult PLUGIN_API initialize(Steinberg::FUnknown* context) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API connect(Steinberg::Vst::IConnectionPoint* other) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API disconnect(Steinberg::Vst::IConnectionPoint* other) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setBusArrangements(Steinberg::Vst::SpeakerArrangement* inputs,
                                                     Steinberg::int32 inputCount,
                                                     Steinberg::Vst::SpeakerArrangement* outputs,
                                                     Steinberg::int32 outputCount) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API canProcessSampleSize(Steinberg::int32 symbolicSampleSize) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setupProcessing(Steinberg::Vst::ProcessSetup& setup) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setActive(Steinberg::TBool state) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setProcessing(Steinberg::TBool state) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API process(Steinberg::Vst::ProcessData& data) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API setState(Steinberg::IBStream* state) SMTG_OVERRIDE;
    Steinberg::tresult PLUGIN_API getState(Steinberg::IBStream* state) SMTG_OVERRIDE;

private:
    void updateTiming(const Steinberg::Vst::ProcessContext* context, Steinberg::int32 sampleOffset);
    void processSegment(Steinberg::Vst::ProcessData& data, Steinberg::int32 offset, Steinberg::int32 sampleCount);
    void captureSpectrum(int stage);
    void resetSpectrumLine();

    std::unique_ptr<DtBlkFx> engine;
    std::unique_ptr<Steinberg::Vst::DataExchangeHandler> spectrumExchange;
    SpectrumFrame spectrumFrame;
    bool spectrumLineEmpty {true};
    std::int64_t previousSpectrumSamplePosition {};
    bool bypass {};
};
}
