// Renders the deterministic oracle corpus through a Windows VST2 binary.
#include <windows.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using VstInt32 = std::int32_t;
using VstIntPtr = std::intptr_t;

struct AEffect;
using AudioMasterCallback = VstIntPtr(__cdecl*)(AEffect*, VstInt32, VstInt32, VstIntPtr, void*, float);
using Dispatcher = VstIntPtr(__cdecl*)(AEffect*, VstInt32, VstInt32, VstIntPtr, void*, float);
using Process = void(__cdecl*)(AEffect*, float**, float**, VstInt32);
using SetParameter = void(__cdecl*)(AEffect*, VstInt32, float);
using GetParameter = float(__cdecl*)(AEffect*, VstInt32);

struct AEffect
{
    VstInt32 magic;
    Dispatcher dispatcher;
    Process process;
    SetParameter setParameter;
    GetParameter getParameter;
    VstInt32 numPrograms;
    VstInt32 numParams;
    VstInt32 numInputs;
    VstInt32 numOutputs;
    VstInt32 flags;
    VstIntPtr reserved1;
    VstIntPtr reserved2;
    VstInt32 initialDelay;
    VstInt32 realQualities;
    VstInt32 offQualities;
    float ioRatio;
    void* object;
    void* user;
    VstInt32 uniqueID;
    VstInt32 version;
    Process processReplacing;
    Process processDoubleReplacing;
    char future[56];
};

struct VstTimeInfo
{
    double samplePos;
    double sampleRate;
    double nanoSeconds;
    double ppqPos;
    double tempo;
    double barStartPos;
    double cycleStartPos;
    double cycleEndPos;
    VstInt32 timeSigNumerator;
    VstInt32 timeSigDenominator;
    VstInt32 smpteOffset;
    VstInt32 smpteFrameRate;
    VstInt32 samplesToNextClock;
    VstInt32 flags;
};

enum
{
    audioMasterVersion = 1,
    audioMasterGetTime = 7,
    audioMasterGetSampleRate = 16,
    audioMasterGetBlockSize = 17,
    effOpen = 0,
    effClose = 1,
    effSetSampleRate = 10,
    effSetBlockSize = 11,
    effMainsChanged = 12,
    effGetEffectName = 45,
    effGetVendorString = 47,
    effGetProductString = 48,
    effGetVendorVersion = 49,
    effGetVstVersion = 58,
    kVstPpqPosValid = 1 << 9,
    kVstTempoValid = 1 << 10,
};

constexpr VstInt32 BlockSize = 256;
constexpr double SampleRate = 44100.0;
constexpr VstInt32 RenderSamples = 131072;
constexpr int GlobalParameterCount = 4;
constexpr int EffectSetCount = 8;
constexpr int EffectParameterCount = 5;
constexpr int NoEffectType = 9;

struct Scenario
{
    std::string name;
    std::array<double, 44> parameters{};
    VstInt32 renderSamples{RenderSamples};
};

VstTimeInfo timeInfo{};

VstIntPtr __cdecl Host(AEffect*, VstInt32 opcode, VstInt32, VstIntPtr, void*, float)
{
    if(opcode == audioMasterVersion)
        return 2400;
    if(opcode == audioMasterGetTime)
        return reinterpret_cast<VstIntPtr>(&timeInfo);
    if(opcode == audioMasterGetSampleRate)
        return static_cast<VstIntPtr>(SampleRate);
    if(opcode == audioMasterGetBlockSize)
        return BlockSize;
    return 0;
}

float InputSample(std::uint64_t position, int channel)
{
    std::uint32_t noise = static_cast<std::uint32_t>(position) * 747796405U + 2891336453U;
    noise = ((noise >> ((noise >> 28U) + 4U)) ^ noise) * 277803737U;
    noise = (noise >> 22U) ^ noise;
    const float random = static_cast<float>(noise) / 4294967295.0f - 0.5f;
    const double phase = static_cast<double>(position);
    float sample = 0.12f * std::sin(static_cast<float>(phase * 2.0 * 3.14159265358979323846 * 83.0 / SampleRate));
    sample += 0.08f * std::sin(static_cast<float>(phase * 2.0 * 3.14159265358979323846 * 997.0 / SampleRate));
    sample += 0.04f * random;
    if(position % 8192 == 0)
        sample += channel == 0 ? 0.8f : -0.65f;
    return channel == 0 ? sample : sample * 0.73f;
}

double EffectTypeValue(int effect)
{
    return static_cast<double>(effect * 8 + 4) / 255.0;
}

double FftPlanValue(int plan)
{
    return std::clamp(static_cast<double>(plan + 2) * 4.0 / 255.0, 0.0, 1.0);
}

int EffectParameter(int set, int parameter)
{
    return GlobalParameterCount + set * EffectParameterCount + parameter;
}

Scenario BaseScenario(std::string name)
{
    Scenario scenario;
    scenario.name = std::move(name);
    scenario.parameters[0] = 0.0;
    scenario.parameters[1] = 16.0 / 255.0;
    scenario.parameters[2] = FftPlanValue(16);
    scenario.parameters[3] = 0.35;
    for(int set = 0; set < EffectSetCount; ++set)
    {
        scenario.parameters[EffectParameter(set, 0)] = 0.18 + set * 0.035;
        scenario.parameters[EffectParameter(set, 1)] = 0.82 - set * 0.025;
        scenario.parameters[EffectParameter(set, 2)] = 0.6;
        scenario.parameters[EffectParameter(set, 3)] = EffectTypeValue(NoEffectType);
        scenario.parameters[EffectParameter(set, 4)] = 0.5;
    }
    return scenario;
}

void SetEffect(Scenario& scenario, int set, int effect, double value = 0.5)
{
    scenario.parameters[EffectParameter(set, 3)] = EffectTypeValue(effect);
    scenario.parameters[EffectParameter(set, 4)] = value;
}

double MillisecondsDelayValue(double milliseconds)
{
    return 0.5 + milliseconds / 12000.0;
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
    constexpr std::array<int, EffectSetCount> chainFourEffects{20, 23, 26, 29, 1, 4, 7, 10};
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
        scenario.parameters[2] = FftPlanValue(plan);
        SetEffect(scenario, 0, 2, 0.77);
        SetEffect(scenario, 1, 7, 0.31);
        scenarios.push_back(std::move(scenario));
    }
    constexpr std::array<double, 5> overlaps{0.05, 0.35, 0.49, 0.65, 0.85};
    for(int overlapIndex = 0; overlapIndex < 5; ++overlapIndex)
    {
        Scenario scenario = BaseScenario("overlap-" + std::to_string(overlapIndex));
        scenario.parameters[3] = overlaps[overlapIndex];
        SetEffect(scenario, 0, 14, 0.68);
        SetEffect(scenario, 1, 20, 0.42);
        scenarios.push_back(std::move(scenario));
    }
    constexpr std::array<double, 4> delays{0.0, 16.0 / 255.0, 0.5 + 50.0 / 12000.0,
                                           0.5 + 500.0 / 12000.0};
    for(int delayIndex = 0; delayIndex < 4; ++delayIndex)
    {
        Scenario scenario = BaseScenario("delay-" + std::to_string(delayIndex));
        scenario.parameters[1] = delays[delayIndex];
        SetEffect(scenario, 0, 15, 0.62);
        scenarios.push_back(std::move(scenario));
    }
    Scenario maximum = BaseScenario("large-fft-long-delay");
    maximum.parameters[1] = MillisecondsDelayValue(3000.0);
    maximum.parameters[2] = FftPlanValue(33);
    maximum.parameters[3] = 0.47;
    maximum.renderSamples = 262144;
    SetEffect(maximum, 0, 2, 0.8);
    SetEffect(maximum, 1, 6, 0.27);
    SetEffect(maximum, 2, 18, 0.72);
    scenarios.push_back(std::move(maximum));
    return scenarios;
}

int main(int argc, char** argv)
{
    if(argc != 3)
    {
        std::fprintf(stderr, "usage: legacy_vst2_probe plugin.dll output-directory\n");
        return 2;
    }
    const std::vector<Scenario> scenarios = MakeScenarios();
    HMODULE library = LoadLibraryA(argv[1]);
    if(!library)
    {
        std::fprintf(stderr, "LoadLibrary failed: %lu\n", GetLastError());
        return 1;
    }
    auto entry = reinterpret_cast<AEffect*(__cdecl*)(AudioMasterCallback)>(GetProcAddress(library, "VSTPluginMain"));
    if(!entry)
        return 1;
    AEffect* effect = entry(Host);
    if(!effect || effect->magic != 0x56737450)
        return 1;
    effect->dispatcher(effect, effOpen, 0, 0, nullptr, 0.0f);
    effect->dispatcher(effect, effSetSampleRate, 0, 0, nullptr, static_cast<float>(SampleRate));
    effect->dispatcher(effect, effSetBlockSize, 0, BlockSize, nullptr, 0.0f);

    char effectName[64]{};
    char vendor[64]{};
    char product[64]{};
    effect->dispatcher(effect, effGetEffectName, 0, 0, effectName, 0.0f);
    effect->dispatcher(effect, effGetVendorString, 0, 0, vendor, 0.0f);
    effect->dispatcher(effect, effGetProductString, 0, 0, product, 0.0f);
    std::printf("name=%s vendor=%s product=%s programs=%d params=%d inputs=%d outputs=%d initialDelay=%d version=%d vst=%lld vendorVersion=%lld\n",
                effectName, vendor, product, effect->numPrograms, effect->numParams, effect->numInputs,
                effect->numOutputs, effect->initialDelay, effect->version,
                static_cast<long long>(effect->dispatcher(effect, effGetVstVersion, 0, 0, nullptr, 0.0f)),
                static_cast<long long>(effect->dispatcher(effect, effGetVendorVersion, 0, 0, nullptr, 0.0f)));

    std::array<float, BlockSize> inLeft{};
    std::array<float, BlockSize> inRight{};
    std::array<float, BlockSize> outLeft{};
    std::array<float, BlockSize> outRight{};
    float* inputs[] = {inLeft.data(), inRight.data()};
    float* outputs[] = {outLeft.data(), outRight.data()};
    for(const Scenario& scenario : scenarios)
    {
        for(int index = 0; index < effect->numParams; ++index)
            effect->setParameter(effect, index, static_cast<float>(scenario.parameters[index]));
        const std::string outputPath = std::string(argv[2]) + "/" + scenario.name + ".f32";
        FILE* output = std::fopen(outputPath.c_str(), "wb");
        if(!output)
            return 1;
        effect->dispatcher(effect, effMainsChanged, 0, 1, nullptr, 0.0f);
        std::int64_t firstOutput = -1;
        for(VstInt32 position = 0; position < scenario.renderSamples; position += BlockSize)
        {
            timeInfo.samplePos = position;
            timeInfo.sampleRate = SampleRate;
            timeInfo.ppqPos = position * 120.0 / (60.0 * SampleRate);
            timeInfo.tempo = 120.0;
            timeInfo.flags = kVstPpqPosValid | kVstTempoValid;
            for(VstInt32 sample = 0; sample < BlockSize; ++sample)
            {
                inLeft[sample] = InputSample(static_cast<std::uint64_t>(position + sample), 0);
                inRight[sample] = InputSample(static_cast<std::uint64_t>(position + sample), 1);
            }
            effect->processReplacing(effect, inputs, outputs, BlockSize);
            for(VstInt32 sample = 0; sample < BlockSize; ++sample)
            {
                float pair[] = {outLeft[sample], outRight[sample]};
                std::fwrite(pair, sizeof(float), 2, output);
                if(firstOutput < 0 && (pair[0] != 0.0f || pair[1] != 0.0f))
                    firstOutput = position + sample;
            }
        }
        std::fclose(output);
        std::printf("scenario=%s firstOutput=%lld\n", scenario.name.c_str(), static_cast<long long>(firstOutput));
        effect->dispatcher(effect, effMainsChanged, 0, 0, nullptr, 0.0f);
    }
    effect->dispatcher(effect, effClose, 0, 0, nullptr, 0.0f);
    FreeLibrary(library);
    return 0;
}
