// Translates between VST3 component state and the original DtBlkFx chunk format.
#pragma once

#include "pluginterfaces/base/ibstream.h"

#include <array>
#include <cstdint>
#include <vector>

namespace DtBlkVst3
{
struct StateData
{
    bool bypass {};
    std::vector<std::uint8_t> legacyChunk;
};

bool ReadState(Steinberg::IBStream* stream, StateData& state);
bool WriteState(Steinberg::IBStream* stream, const StateData& state);
bool ExtractLegacyParameters(const std::vector<std::uint8_t>& chunk, std::array<float, 44>& parameters);
}
