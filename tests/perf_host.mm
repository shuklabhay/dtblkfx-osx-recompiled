// Benchmarks deterministic DtBlkFx configurations through the public VST3 processing API.
#import <Cocoa/Cocoa.h>

#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"

#include <algorithm>
#include <array>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <numeric>
#include <string>
#include <vector>

namespace
{
constexpr Steinberg::int32 BlockSize = 256;
constexpr double SampleRate = 44100.0;
constexpr Steinberg::int32 RenderSamples = 131072;
constexpr Steinberg::int32 LongRenderSamples = 262144;
constexpr int GlobalParameterCount = 4;
constexpr int EffectSetCount = 8;
constexpr int EffectParameterCount = 5;
constexpr Steinberg::Vst::ParamID DelayParameter = 1;
constexpr Steinberg::Vst::ParamID FftLengthParameter = 2;
constexpr Steinberg::Vst::ParamID OverlapParameter = 3;
constexpr Steinberg::Vst::ParamID EffectFrequencyA = 0;
constexpr Steinberg::Vst::ParamID EffectFrequencyB = 1;
constexpr Steinberg::Vst::ParamID EffectAmplitude = 2;
constexpr Steinberg::Vst::ParamID EffectType = 3;
constexpr Steinberg::Vst::ParamID EffectValue = 4;
constexpr int NoEffectType = 9;

struct Scenario
{
    std::string name;
    std::array<double, 44> parameters {};
    Steinberg::int32 renderSamples {RenderSamples};
};

double EffectTypeValue(int effect)
{
    return static_cast<double>(effect * 8 + 4) / 255.0;
}

double FftPlanValue(int plan)
{
    return std::clamp(static_cast<double>(plan + 2) * 4.0 / 255.0, 0.0, 1.0);
}

double MillisecondsDelayValue(double milliseconds)
{
    return 0.5 + milliseconds / 12000.0;
}

Steinberg::Vst::ParamID EffectParameter(int set, int parameter)
{
    return GlobalParameterCount + set * EffectParameterCount + parameter;
}

Scenario BaseScenario(std::string name)
{
    Scenario scenario;
    scenario.name = std::move(name);
    scenario.parameters[0] = 0.0;
    scenario.parameters[DelayParameter] = 16.0 / 255.0;
    scenario.parameters[FftLengthParameter] = FftPlanValue(16);
    scenario.parameters[OverlapParameter] = 0.35;
    for(int set = 0; set < EffectSetCount; ++set)
    {
        scenario.parameters[EffectParameter(set, EffectFrequencyA)] = 0.18 + set * 0.035;
        scenario.parameters[EffectParameter(set, EffectFrequencyB)] = 0.82 - set * 0.025;
        scenario.parameters[EffectParameter(set, EffectAmplitude)] = 0.6;
        scenario.parameters[EffectParameter(set, EffectType)] = EffectTypeValue(NoEffectType);
        scenario.parameters[EffectParameter(set, EffectValue)] = 0.5;
    }
    return scenario;
}

void SetEffect(Scenario& scenario, int set, int effect, double value = 0.5)
{
    scenario.parameters[EffectParameter(set, EffectType)] = EffectTypeValue(effect);
    scenario.parameters[EffectParameter(set, EffectValue)] = value;
}

std::vector<Scenario> MakeScenarios()
{
    std::vector<Scenario> scenarios;
    for(int effect = 0; effect < 31; ++effect)
    {
        Scenario scenario = BaseScenario("effect-" + std::to_string(effect));
        SetEffect(scenario, 0, effect, 0.17 + 0.66 * static_cast<double>(effect % 7) / 6.0);
        scenarios.push_back(std::move(scenario));
    }

    for(int chain = 0; chain < 6; ++chain)
    {
        Scenario scenario = BaseScenario("chain-" + std::to_string(chain));
        for(int set = 0; set < EffectSetCount; ++set)
            SetEffect(scenario, set, (chain * 5 + set * 3) % 31, 0.13 + 0.1 * set);
        scenarios.push_back(std::move(scenario));
    }

    constexpr std::array<int, EffectSetCount> chainFourEffects {20, 23, 26, 29, 1, 4, 7, 10};
    for(int prefix = 1; prefix <= EffectSetCount; ++prefix)
    {
        Scenario scenario = BaseScenario("chain-4-prefix-" + std::to_string(prefix));
        for(int set = 0; set < prefix; ++set)
            SetEffect(scenario, set, chainFourEffects[set], 0.13 + 0.1 * set);
        scenarios.push_back(std::move(scenario));
    }

    for(int plan : {0, 8, 16, 24, 32})
    {
        Scenario scenario = BaseScenario("fft-plan-" + std::to_string(plan));
        scenario.parameters[FftLengthParameter] = FftPlanValue(plan);
        SetEffect(scenario, 0, 2, 0.77);
        SetEffect(scenario, 1, 7, 0.31);
        scenarios.push_back(std::move(scenario));
    }

    for(int overlapIndex = 0; overlapIndex < 5; ++overlapIndex)
    {
        constexpr std::array<double, 5> overlaps {0.05, 0.35, 0.49, 0.65, 0.85};
        Scenario scenario = BaseScenario("overlap-" + std::to_string(overlapIndex));
        scenario.parameters[OverlapParameter] = overlaps[overlapIndex];
        SetEffect(scenario, 0, 14, 0.68);
        SetEffect(scenario, 1, 20, 0.42);
        scenarios.push_back(std::move(scenario));
    }

    for(int delayIndex = 0; delayIndex < 4; ++delayIndex)
    {
        constexpr std::array<double, 4> delays {0.0, 16.0 / 255.0, 0.5 + 50.0 / 12000.0,
                                                0.5 + 500.0 / 12000.0};
        Scenario scenario = BaseScenario("delay-" + std::to_string(delayIndex));
        scenario.parameters[DelayParameter] = delays[delayIndex];
        SetEffect(scenario, 0, 15, 0.62);
        scenarios.push_back(std::move(scenario));
    }

    Scenario maximum = BaseScenario("large-fft-long-delay");
    maximum.parameters[DelayParameter] = MillisecondsDelayValue(3000.0);
    maximum.parameters[FftLengthParameter] = FftPlanValue(33);
    maximum.parameters[OverlapParameter] = 0.47;
    maximum.renderSamples = LongRenderSamples;
    SetEffect(maximum, 0, 2, 0.8);
    SetEffect(maximum, 1, 6, 0.27);
    SetEffect(maximum, 2, 18, 0.72);
    scenarios.push_back(std::move(maximum));
    return scenarios;
}

std::uint64_t HashSample(std::uint64_t hash, float sample)
{
    hash ^= std::bit_cast<std::uint32_t>(sample);
    return hash * 1099511628211ULL;
}

float InputSample(std::uint64_t position, int channel)
{
    std::uint32_t noise = static_cast<std::uint32_t>(position) * 747796405U + 2891336453U;
    noise = ((noise >> ((noise >> 28U) + 4U)) ^ noise) * 277803737U;
    noise = (noise >> 22U) ^ noise;
    const float random = static_cast<float>(noise) / 4294967295.0f - 0.5f;
    const double phase = static_cast<double>(position);
    float sample = 0.12f * std::sin(static_cast<float>(phase * 2.0 * M_PI * 83.0 / SampleRate));
    sample += 0.08f * std::sin(static_cast<float>(phase * 2.0 * M_PI * 997.0 / SampleRate));
    sample += 0.04f * random;
    if(position % 8192 == 0)
        sample += channel == 0 ? 0.8f : -0.65f;
    return channel == 0 ? sample : sample * 0.73f;
}

class BenchmarkHost
{
public:
    bool open(const char* path)
    {
        std::string error;
        module = VST3::Hosting::Module::create(path, error);
        if(!module)
        {
            std::cerr << error << '\n';
            return false;
        }
        auto factory = module->getFactory();
        factory.setHostContext(&host);
        Steinberg::Vst::PluginContextFactory::instance().setPluginContext(&host);
        for(const auto& info : factory.classInfos())
        {
            if(info.category() == kVstAudioEffectClass)
            {
                provider = std::make_unique<Steinberg::Vst::PlugProvider>(factory, info, true);
                break;
            }
        }
        if(!provider || !provider->initialize())
            return false;
        if(std::getenv("DTBLKFX_PERF_EDITOR"))
        {
            [NSApplication sharedApplication];
            auto controller = provider->getControllerPtr();
            editor = Steinberg::owned(controller->createView(Steinberg::Vst::ViewType::kEditor));
            Steinberg::ViewRect size;
            if(!editor || editor->getSize(&size) != Steinberg::kResultTrue)
                return false;
            editorParent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.getWidth(), size.getHeight())];
            if(editor->attached((__bridge void*)editorParent, Steinberg::kPlatformTypeNSView) !=
               Steinberg::kResultTrue)
                return false;
        }
        component = provider->getComponentPtr();
        processor = Steinberg::U::cast<Steinberg::Vst::IAudioProcessor>(component);
        if(!component || !processor)
            return false;

        Steinberg::Vst::SpeakerArrangement input = Steinberg::Vst::SpeakerArr::kStereo;
        Steinberg::Vst::SpeakerArrangement output = Steinberg::Vst::SpeakerArr::kStereo;
        Steinberg::Vst::ProcessSetup setup {};
        setup.processMode = Steinberg::Vst::kRealtime;
        setup.symbolicSampleSize = Steinberg::Vst::kSample32;
        setup.maxSamplesPerBlock = BlockSize;
        setup.sampleRate = SampleRate;
        return processor->setBusArrangements(&input, 1, &output, 1) == Steinberg::kResultOk &&
               processor->setupProcessing(setup) == Steinberg::kResultOk &&
               component->activateBus(Steinberg::Vst::kAudio, Steinberg::Vst::kInput, 0, true) == Steinberg::kResultOk &&
               component->activateBus(Steinberg::Vst::kAudio, Steinberg::Vst::kOutput, 0, true) == Steinberg::kResultOk;
    }

    bool render(const Scenario& scenario)
    {
        if(component->setActive(true) != Steinberg::kResultOk ||
           processor->setProcessing(true) != Steinberg::kResultOk)
            return false;

        const bool sendParameters = std::getenv("DTBLKFX_PERF_NO_PARAMETERS") == nullptr;
        Steinberg::Vst::ParameterChanges changes(44);
        for(Steinberg::Vst::ParamID parameter = 0;
            sendParameters && parameter < scenario.parameters.size(); ++parameter)
        {
            Steinberg::int32 queueIndex = 0;
            Steinberg::Vst::IParamValueQueue* queue = changes.addParameterData(parameter, queueIndex);
            Steinberg::int32 pointIndex = 0;
            queue->addPoint(0, scenario.parameters[parameter], pointIndex);
        }

        std::array<float, BlockSize> inputLeft {};
        std::array<float, BlockSize> inputRight {};
        std::array<float, BlockSize> outputLeft {};
        std::array<float, BlockSize> outputRight {};
        float* inputs[] = {inputLeft.data(), inputRight.data()};
        float* outputs[] = {outputLeft.data(), outputRight.data()};
        Steinberg::Vst::AudioBusBuffers inputBus {};
        inputBus.numChannels = 2;
        inputBus.channelBuffers32 = inputs;
        Steinberg::Vst::AudioBusBuffers outputBus {};
        outputBus.numChannels = 2;
        outputBus.channelBuffers32 = outputs;
        Steinberg::Vst::ProcessContext context {};
        context.state = Steinberg::Vst::ProcessContext::kTempoValid |
                        Steinberg::Vst::ProcessContext::kProjectTimeMusicValid;
        context.tempo = 120.0;
        context.projectTimeMusic = 0.0;
        Steinberg::Vst::ProcessData data {};
        data.processMode = Steinberg::Vst::kRealtime;
        data.symbolicSampleSize = Steinberg::Vst::kSample32;
        data.numInputs = 1;
        data.numOutputs = 1;
        data.inputs = &inputBus;
        data.outputs = &outputBus;
        data.processContext = &context;
        data.inputParameterChanges = sendParameters ? &changes : nullptr;

        std::uint64_t hash = 1469598103934665603ULL;
        std::int64_t firstOutput = -1;
        std::vector<double> blockMicroseconds;
        std::ofstream output;
        if(const char* directory = std::getenv("DTBLKFX_PERF_OUTPUT_DIR"))
        {
            std::filesystem::create_directories(directory);
            output.open(std::filesystem::path(directory) / (scenario.name + ".f32"),
                        std::ios::binary | std::ios::trunc);
            if(!output)
                return false;
        }
        std::uint64_t position = 0;
        while(position < static_cast<std::uint64_t>(scenario.renderSamples))
        {
            const Steinberg::int32 samples = static_cast<Steinberg::int32>(
                std::min<std::uint64_t>(BlockSize, scenario.renderSamples - position));
            data.numSamples = samples;
            context.projectTimeMusic = static_cast<double>(position) * context.tempo / (60.0 * SampleRate);
            for(Steinberg::int32 sample = 0; sample < samples; ++sample)
            {
                inputLeft[sample] = InputSample(position + sample, 0);
                inputRight[sample] = InputSample(position + sample, 1);
            }
            const auto started = std::chrono::steady_clock::now();
            if(processor->process(data) != Steinberg::kResultOk)
                return false;
            const auto stopped = std::chrono::steady_clock::now();
            blockMicroseconds.push_back(
                std::chrono::duration<double, std::micro>(stopped - started).count());
            changes.clearQueue();
            data.inputParameterChanges = nullptr;
            for(Steinberg::int32 sample = 0; sample < samples; ++sample)
            {
                hash = HashSample(hash, outputLeft[sample]);
                hash = HashSample(hash, outputRight[sample]);
                if(output)
                {
                    const float pair[] {outputLeft[sample], outputRight[sample]};
                    output.write(reinterpret_cast<const char*>(pair), sizeof(pair));
                }
                if(firstOutput < 0 && (outputLeft[sample] != 0.0f || outputRight[sample] != 0.0f))
                    firstOutput = static_cast<std::int64_t>(position + sample);
            }
            position += samples;
        }

        const double total = std::accumulate(blockMicroseconds.begin(), blockMicroseconds.end(), 0.0);
        std::sort(blockMicroseconds.begin(), blockMicroseconds.end());
        const auto percentile = [&](double fraction) {
            const std::size_t index = static_cast<std::size_t>(fraction * (blockMicroseconds.size() - 1));
            return blockMicroseconds[index];
        };
        std::cout << scenario.name << ',' << std::hex << std::setw(16) << std::setfill('0') << hash
                  << std::dec << std::setfill(' ') << ',' << firstOutput << ',' << processor->getLatencySamples()
                  << ',' << std::fixed << std::setprecision(3) << total << ',' << percentile(0.5) << ','
                  << percentile(0.95) << ',' << blockMicroseconds.back() << '\n';

        processor->setProcessing(false);
        component->setActive(false);
        return true;
    }

    ~BenchmarkHost()
    {
        if(editor)
            editor->removed();
        Steinberg::Vst::PluginContextFactory::instance().setPluginContext(nullptr);
    }

private:
    Steinberg::Vst::HostApplication host;
    VST3::Hosting::Module::Ptr module;
    std::unique_ptr<Steinberg::Vst::PlugProvider> provider;
    Steinberg::IPtr<Steinberg::IPlugView> editor;
    __strong NSView* editorParent {};
    Steinberg::Vst::IComponent* component {};
    Steinberg::Vst::IAudioProcessor* processor {};
};
}

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc != 2)
        {
            std::cerr << "usage: dtblkfx_perf /path/to/DtBlkFx.vst3\n";
            return 2;
        }
        BenchmarkHost benchmark;
        if(!benchmark.open(argv[1]))
            return 1;
        int repeat = 1;
        if(const char* value = std::getenv("DTBLKFX_PERF_REPEAT"))
            repeat = std::max(1, static_cast<int>(std::strtol(value, nullptr, 10)));
        std::cout << "scenario,hash,first_output_sample,reported_latency_samples,total_us,p50_us,p95_us,max_us\n";
        const std::vector<Scenario> scenarios = MakeScenarios();
        for(int iteration = 0; iteration < repeat; ++iteration)
        {
            for(const Scenario& scenario : scenarios)
            {
                if(!benchmark.render(scenario))
                    return 1;
            }
        }
        return 0;
    }
}
