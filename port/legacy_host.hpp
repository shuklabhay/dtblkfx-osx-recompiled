// Replaces the small VST2 host surface used by the preserved processing engine.
#pragma once

#include <cstdint>

using VstInt32 = std::int32_t;

constexpr VstInt32 kVstMaxParamStrLen = 8;
constexpr VstInt32 kVstMaxEffectNameLen = 32;
constexpr VstInt32 kVstMaxVendorStrLen = 64;
constexpr VstInt32 kVstTempoValid = 1 << 0;
constexpr VstInt32 kVstPpqPosValid = 1 << 1;

enum VstPlugCategory
{
    kPlugCategEffect = 1,
};

struct VstTimeInfo
{
    double samplePos {};
    double sampleRate {44100.0};
    double nanoSeconds {};
    double ppqPos {};
    double tempo {120.0};
    double barStartPos {};
    double cycleStartPos {};
    double cycleEndPos {};
    VstInt32 timeSigNumerator {4};
    VstInt32 timeSigDenominator {4};
    VstInt32 smpteOffset {};
    VstInt32 smpteFrameRate {};
    VstInt32 samplesToNextClock {};
    VstInt32 flags {};
};

class LegacyPluginBase
{
public:
    LegacyPluginBase(VstInt32 programCount, VstInt32 parameterCount)
        : numPrograms(programCount), numParams(parameterCount)
    {
    }

    virtual ~LegacyPluginBase() = default;
    virtual void setParameter(VstInt32 index, float value) = 0;
    virtual float getParameter(VstInt32 index) = 0;

    virtual void setProgram(VstInt32 program)
    {
        curProgram = program;
    }

    virtual void resume() {}
    virtual void suspend() {}

    virtual void setBlockSize(VstInt32 samples)
    {
        blockSize = samples;
    }

    void setSampleRate(float rate)
    {
        sampleRate = rate;
        timeInfo.sampleRate = rate;
    }

    float getSampleRate() const
    {
        return sampleRate;
    }

    void setTimeInfo(double tempo, double ppqPosition, bool tempoValid, bool ppqValid)
    {
        timeInfo.tempo = tempo;
        timeInfo.ppqPos = ppqPosition;
        timeInfo.flags = (tempoValid ? kVstTempoValid : 0) | (ppqValid ? kVstPpqPosValid : 0);
        hasTimeInfo = timeInfo.flags != 0;
    }

    VstTimeInfo* getTimeInfo(VstInt32)
    {
        return hasTimeInfo ? &timeInfo : nullptr;
    }

    void setParameterAutomated(VstInt32 index, float value)
    {
        setParameter(index, value);
    }

    void setNumInputs(VstInt32) {}
    void setNumOutputs(VstInt32) {}
    void canProcessReplacing(bool) {}
    void programsAreChunks(bool) {}
    void setInitialDelay(VstInt32 delay) { initialDelay = delay; }
    void setUniqueID(VstInt32 id) { uniqueId = id; }

    VstInt32 numPrograms {};
    VstInt32 numParams {};
    VstInt32 curProgram {};
    VstInt32 blockSize {};
    VstInt32 initialDelay {};
    VstInt32 uniqueId {};
    float sampleRate {44100.0f};

private:
    VstTimeInfo timeInfo {};
    bool hasTimeInfo {};
};
