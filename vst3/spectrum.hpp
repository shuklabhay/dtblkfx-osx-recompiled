// Defines the real-time-safe spectrum frame exchanged between processor and editor.
#pragma once

#include <array>
#include <cstdint>

namespace DtBlkVst3
{
constexpr std::size_t SpectrumPixelCount = 400;
constexpr std::uint32_t SpectrumExchangeContext = 0x44544253;
constexpr const char* SpectrumEnableMessage = "DtBlkFx.Spectrum.Enable";
constexpr const char* SpectrumDisableMessage = "DtBlkFx.Spectrum.Disable";

struct alignas(32) SpectrumFrame
{
    std::int64_t samplePosition {};
    std::int32_t timeFftSize {};
    std::array<float, SpectrumPixelCount> inputPower {};
    std::array<float, SpectrumPixelCount> outputPower {};
};
}
