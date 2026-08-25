// Connects the preserved DtBlkFx processing engine to the VST3 audio API.
#include "processor.hpp"

#include "ids.hpp"
#include "state.hpp"
#include "upstream/dtblkfx/DtBlkFx.hpp"
#include "src/compat/legacy_runtime.hpp"

#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>

namespace DtBlkVst3
{
namespace
{
    constexpr std::int64_t MinimumSpectrumSamplesPerLine = 600;

    void UpdateSilenceFlags(Steinberg::Vst::ProcessData& data)
    {
        if(data.numOutputs < 1 || data.numSamples <= 0 || !data.outputs[0].channelBuffers32)
            return;

        Steinberg::uint64 silenceFlags = 0;
        for(Steinberg::int32 channel = 0; channel < data.outputs[0].numChannels; ++channel)
        {
            const float* samples = data.outputs[0].channelBuffers32[channel];
            bool silent = samples != nullptr;
            for(Steinberg::int32 sample = 0; silent && sample < data.numSamples; ++sample)
                silent = samples[sample] == 0.0f;
            if(silent)
                silenceFlags |= Steinberg::uint64 { 1 } << channel;
        }
        data.outputs[0].silenceFlags = silenceFlags;
    }
}

Processor::Processor()
{
    setControllerClass(Steinberg::FUID::fromTUID(ControllerUID));
    processContextRequirements.needTempo().needProjectTimeMusic();
    spectrumExchange = std::make_unique<Steinberg::Vst::DataExchangeHandler>(this,
        [](Steinberg::Vst::DataExchangeHandler::Config& config, const Steinberg::Vst::ProcessSetup&)
        {
            config.blockSize = sizeof(SpectrumFrame);
            config.numBlocks = 32;
            config.alignment = 32;
            config.userContextID = SpectrumExchangeContext;
            return true;
        });
    parameterEvents.reserve(64);
}

Processor::~Processor() = default;

Steinberg::FUnknown* Processor::createInstance(void*)
{
    return static_cast<Steinberg::Vst::IAudioProcessor*>(new Processor());
}

Steinberg::tresult PLUGIN_API Processor::initialize(Steinberg::FUnknown* context)
{
    const Steinberg::tresult result = AudioEffect::initialize(context);
    if(result != Steinberg::kResultOk || !InitializeLegacyRuntime())
        return Steinberg::kResultFalse;

    try
    {
        engine = std::make_unique<DtBlkFx>();
        for(std::size_t index = 0; index < LegacyParameterCount; ++index)
            engine->setParameter(static_cast<VstInt32>(index), LegacyDefaultParameter(index));
        engine->setSpectrumCallback(
            this, [](void* context, DtBlkFx&, int stage) { static_cast<Processor*>(context)->captureSpectrum(stage); });
    }
    catch(...)
    {
        return Steinberg::kResultFalse;
    }

    addAudioInput(STR16("Stereo Input"), Steinberg::Vst::SpeakerArr::kStereo);
    addAudioOutput(STR16("Stereo Output"), Steinberg::Vst::SpeakerArr::kStereo);
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Processor::connect(Steinberg::Vst::IConnectionPoint* other)
{
    const Steinberg::tresult result = AudioEffect::connect(other);
    if(spectrumExchange)
        spectrumExchange->onConnect(other, getHostContext());
    return result;
}

Steinberg::tresult PLUGIN_API Processor::disconnect(Steinberg::Vst::IConnectionPoint* other)
{
    if(spectrumExchange)
        spectrumExchange->onDisconnect(other);
    return AudioEffect::disconnect(other);
}

Steinberg::tresult PLUGIN_API Processor::notify(Steinberg::Vst::IMessage* message)
{
    if(message && message->getMessageID())
    {
        if(std::strcmp(message->getMessageID(), SpectrumEnableMessage) == 0)
        {
            spectrumResetRequested.store(true, std::memory_order_relaxed);
            spectrumEnabled.store(true, std::memory_order_relaxed);
            return Steinberg::kResultTrue;
        }
        if(std::strcmp(message->getMessageID(), SpectrumDisableMessage) == 0)
        {
            spectrumEnabled.store(false, std::memory_order_relaxed);
            return Steinberg::kResultTrue;
        }
    }
    return AudioEffect::notify(message);
}

Steinberg::tresult PLUGIN_API Processor::setBusArrangements(Steinberg::Vst::SpeakerArrangement* inputs,
    Steinberg::int32 inputCount, Steinberg::Vst::SpeakerArrangement* outputs, Steinberg::int32 outputCount)
{
    if(inputCount != 1 || outputCount != 1 || inputs[0] != Steinberg::Vst::SpeakerArr::kStereo
        || outputs[0] != Steinberg::Vst::SpeakerArr::kStereo)
        return Steinberg::kResultFalse;
    return AudioEffect::setBusArrangements(inputs, inputCount, outputs, outputCount);
}

Steinberg::tresult PLUGIN_API Processor::canProcessSampleSize(Steinberg::int32 symbolicSampleSize)
{
    return symbolicSampleSize == Steinberg::Vst::kSample32 ? Steinberg::kResultTrue : Steinberg::kResultFalse;
}

Steinberg::tresult PLUGIN_API Processor::setupProcessing(Steinberg::Vst::ProcessSetup& setup)
{
    if(!engine || setup.sampleRate <= 0.0 || setup.maxSamplesPerBlock <= 0
        || setup.symbolicSampleSize != Steinberg::Vst::kSample32)
        return Steinberg::kResultFalse;

    const Steinberg::tresult result = AudioEffect::setupProcessing(setup);
    if(result == Steinberg::kResultOk)
    {
        engine->setSampleRate(static_cast<float>(setup.sampleRate));
        engine->setBlockSize(setup.maxSamplesPerBlock);
        for(auto& channel : bypassDry)
            channel.resize(static_cast<std::size_t>(setup.maxSamplesPerBlock));
    }
    return result;
}

Steinberg::tresult PLUGIN_API Processor::setActive(Steinberg::TBool state)
{
    if(!engine)
        return Steinberg::kResultFalse;
    if(state)
    {
        engine->resume();
        resetSpectrumLine();
        previousSpectrumSamplePosition = 0;
        if(spectrumExchange)
            spectrumExchange->onActivate(processSetup);
    }
    else
    {
        if(spectrumExchange)
            spectrumExchange->onDeactivate();
        engine->suspend();
    }
    return AudioEffect::setActive(state);
}

Steinberg::tresult PLUGIN_API Processor::setProcessing(Steinberg::TBool state)
{
    if(!engine)
        return Steinberg::kResultFalse;
    if(state)
    {
        engine->resume();
        resetSpectrumLine();
        previousSpectrumSamplePosition = 0;
    }
    else
    {
        engine->suspend();
        spectrumLineEmpty = true;
        previousSpectrumSamplePosition = 0;
    }
    return Steinberg::kResultOk;
}

void Processor::updateTiming(const Steinberg::Vst::ProcessContext* context, Steinberg::int32 sampleOffset)
{
    if(!engine)
        return;

    const bool tempoValid = context && (context->state & Steinberg::Vst::ProcessContext::kTempoValid) != 0;
    const bool ppqValid = context && (context->state & Steinberg::Vst::ProcessContext::kProjectTimeMusicValid) != 0;
    const double tempo = tempoValid ? context->tempo : 120.0;
    double ppq = ppqValid ? context->projectTimeMusic : 0.0;
    if(ppqValid && tempoValid && processSetup.sampleRate > 0.0)
        ppq += static_cast<double>(sampleOffset) * tempo / (60.0 * processSetup.sampleRate);
    engine->setTimeInfo(tempo, ppq, tempoValid, ppqValid);
}

void Processor::processSegment(Steinberg::Vst::ProcessData& data, Steinberg::int32 offset, Steinberg::int32 sampleCount)
{
    if(sampleCount <= 0 || data.numInputs < 1 || data.numOutputs < 1 || data.inputs[0].numChannels < 2
        || data.outputs[0].numChannels < 2)
        return;

    std::array<float*, 2> inputs {
        data.inputs[0].channelBuffers32[0] + offset,
        data.inputs[0].channelBuffers32[1] + offset,
    };
    std::array<float*, 2> outputs {
        data.outputs[0].channelBuffers32[0] + offset,
        data.outputs[0].channelBuffers32[1] + offset,
    };

    if(bypass)
    {
        std::array<float*, 2> dryInputs {
            bypassDry[0].data(),
            bypassDry[1].data(),
        };
        for(std::size_t channel = 0; channel < outputs.size(); ++channel)
            std::memcpy(dryInputs[channel], inputs[channel], static_cast<std::size_t>(sampleCount) * sizeof(float));
        engine->processReplacing(inputs.data(), outputs.data(), sampleCount);
        for(std::size_t channel = 0; channel < outputs.size(); ++channel)
            std::memcpy(outputs[channel], dryInputs[channel], static_cast<std::size_t>(sampleCount) * sizeof(float));
        return;
    }

    engine->processReplacing(inputs.data(), outputs.data(), sampleCount);
}

void Processor::resetSpectrumLine()
{
    spectrumFrame.inputPower.fill(0.0f);
    spectrumFrame.outputPower.fill(0.0f);
    spectrumLineEmpty = false;
}

void Processor::captureSpectrum(int stage)
{
    if(!spectrumEnabled.load(std::memory_order_relaxed) || !engine || stage < 0 || stage > 1 || engine->_plan < 0
        || engine->_plan >= NUM_FFT_SZ || engine->getSampleRate() <= 0.0f)
        return;
    if(spectrumResetRequested.exchange(false, std::memory_order_relaxed))
    {
        resetSpectrumLine();
        previousSpectrumSamplePosition = 0;
    }
    if(stage == 0 && spectrumLineEmpty)
        resetSpectrumLine();

    auto& destination = stage == 0 ? spectrumFrame.inputPower : spectrumFrame.outputPower;
    const int fftLength = g_fft_sz[engine->_plan];
    const int maximumBin = fftLength / 2;
    if(spectrumPlan != engine->_plan || spectrumSampleRate != engine->getSampleRate())
    {
        const float halfPixel
            = std::pow(2.0f, -0.5f * BlkFxParam::octaveSpan() / static_cast<float>(SpectrumPixelCount));
        const float hzToBin = halfPixel * static_cast<float>(fftLength) / engine->getSampleRate();
        int cachedStartBin = 0;
        for(std::size_t pixel = 0; pixel < SpectrumPixelCount; ++pixel)
        {
            int endBin = maximumBin + 1;
            if(pixel + 1 < SpectrumPixelCount)
            {
                const float parameter = static_cast<float>(pixel + 1) / static_cast<float>(SpectrumPixelCount);
                endBin = std::clamp(RndToInt(BlkFxParam::getHz(parameter) * hzToBin), cachedStartBin, maximumBin);
            }
            spectrumEndBins[pixel] = endBin;
            cachedStartBin = endBin;
        }
        spectrumPlan = engine->_plan;
        spectrumSampleRate = engine->getSampleRate();
    }
    for(int channel = 0; channel < DtBlkFx::AUDIO_CHANNELS; ++channel)
    {
        const cplxf* bins = engine->FFTdata(channel);
        const float scale = stage == 1 ? engine->_chan[channel].out_pwr_scale : 1.0f;
        int startBin = 0;
        for(std::size_t pixel = 0; pixel < SpectrumPixelCount; ++pixel)
        {
            const int endBin = spectrumEndBins[pixel];
            float maximumPower = norm(bins[startBin]) * scale;
            for(int bin = startBin + 1; bin < endBin; ++bin)
                maximumPower = std::max(maximumPower, norm(bins[bin]) * scale);
            destination[pixel] = std::max(destination[pixel], maximumPower);
            startBin = endBin;
        }
    }

    if(stage != 1)
        return;
    const std::int64_t lineEnd = static_cast<std::int64_t>(engine->_blk_samp_abs) + engine->_time_fft_n;
    if(lineEnd - previousSpectrumSamplePosition < MinimumSpectrumSamplesPerLine)
        return;

    spectrumFrame.samplePosition = engine->_blk_samp_abs;
    spectrumFrame.timeFftSize = static_cast<std::int32_t>(engine->_time_fft_n);
    if(spectrumExchange)
    {
        Steinberg::Vst::DataExchangeBlock block = spectrumExchange->getCurrentOrNewBlock();
        if(block.blockID != Steinberg::Vst::InvalidDataExchangeBlockID && block.size >= sizeof(SpectrumFrame))
        {
            std::memcpy(block.data, &spectrumFrame, sizeof(SpectrumFrame));
            spectrumExchange->sendCurrentBlock();
        }
    }
    previousSpectrumSamplePosition = lineEnd;
    spectrumLineEmpty = true;
}

Steinberg::tresult PLUGIN_API Processor::process(Steinberg::Vst::ProcessData& data)
{
    if(!engine || data.symbolicSampleSize != Steinberg::Vst::kSample32)
        return Steinberg::kResultFalse;

    parameterEvents.clear();
    if(data.inputParameterChanges)
    {
        const Steinberg::int32 queueCount = data.inputParameterChanges->getParameterCount();
        for(Steinberg::int32 queueIndex = 0; queueIndex < queueCount; ++queueIndex)
        {
            Steinberg::Vst::IParamValueQueue* queue = data.inputParameterChanges->getParameterData(queueIndex);
            if(!queue)
                continue;
            const Steinberg::Vst::ParamID id = queue->getParameterId();
            if(id >= LegacyParameterCount && id != BypassParameterId && id != ProgramParameterId)
                continue;
            for(Steinberg::int32 pointIndex = 0; pointIndex < queue->getPointCount(); ++pointIndex)
            {
                ParameterEvent event;
                event.id = id;
                if(queue->getPoint(pointIndex, event.offset, event.value) == Steinberg::kResultTrue)
                {
                    event.offset = std::clamp(event.offset, 0, data.numSamples);
                    event.value = std::clamp(event.value, 0.0, 1.0);
                    parameterEvents.push_back(event);
                }
            }
        }
    }

    std::stable_sort(parameterEvents.begin(), parameterEvents.end(),
        [](const ParameterEvent& left, const ParameterEvent& right)
        {
            if(left.offset != right.offset)
                return left.offset < right.offset;
            return left.id == ProgramParameterId && right.id != ProgramParameterId;
        });

    updateTiming(data.processContext, 0);
    Steinberg::int32 cursor = 0;
    std::size_t eventIndex = 0;
    while(eventIndex < parameterEvents.size())
    {
        const Steinberg::int32 eventOffset = parameterEvents[eventIndex].offset;
        processSegment(data, cursor, eventOffset - cursor);
        updateTiming(data.processContext, eventOffset);
        while(eventIndex < parameterEvents.size() && parameterEvents[eventIndex].offset == eventOffset)
        {
            const ParameterEvent& event = parameterEvents[eventIndex++];
            if(event.id == BypassParameterId)
                bypass = event.value > 0.5;
            else if(event.id == ProgramParameterId && LegacyPresetCount() > 0)
                engine->setProgram(
                    static_cast<VstInt32>(std::lround(event.value * static_cast<double>(LegacyPresetCount() - 1))));
            else
                engine->setParameter(static_cast<VstInt32>(event.id), static_cast<float>(event.value));
        }
        cursor = eventOffset;
    }
    processSegment(data, cursor, data.numSamples - cursor);

    UpdateSilenceFlags(data);
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Processor::setState(Steinberg::IBStream* stream)
{
    if(!engine)
        return Steinberg::kResultFalse;
    StateData state;
    if(!ReadState(stream, state) || state.legacyChunk.empty()
        || engine->setChunk(state.legacyChunk.data(), static_cast<VstInt32>(state.legacyChunk.size()), false) == 0)
        return Steinberg::kResultFalse;
    bypass = state.bypass;
    return Steinberg::kResultOk;
}

Steinberg::tresult PLUGIN_API Processor::getState(Steinberg::IBStream* stream)
{
    if(!engine)
        return Steinberg::kResultFalse;
    void* chunkData = nullptr;
    const VstInt32 chunkSize = engine->getChunk(&chunkData, false);
    if(chunkSize <= 0 || !chunkData)
        return Steinberg::kResultFalse;

    StateData state;
    state.bypass = bypass;
    const auto* bytes = static_cast<const std::uint8_t*>(chunkData);
    state.legacyChunk.assign(bytes, bytes + chunkSize);
    return WriteState(stream, state) ? Steinberg::kResultOk : Steinberg::kResultFalse;
}
}
