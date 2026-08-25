// Translates between VST3 component state and the original DtBlkFx chunk format.
#include "state.hpp"

#include "base/source/fstreamer.h"

#include <cstring>

namespace DtBlkVst3
{
namespace
{
    constexpr Steinberg::int32 StateMagic = 0x44544233;
    constexpr Steinberg::int32 StateVersion = 1;
    constexpr Steinberg::int32 MaximumChunkBytes = 16 * 1024 * 1024;
    constexpr std::uint32_t LegacyChunkMagic = 0x99887766U;
    constexpr std::size_t LegacyHeaderBytes = 16;
    constexpr std::size_t ProgramNameBytes = 32;

    std::uint32_t ReadLittleEndian32(const std::uint8_t* source)
    {
        return static_cast<std::uint32_t>(source[0]) | (static_cast<std::uint32_t>(source[1]) << 8U)
            | (static_cast<std::uint32_t>(source[2]) << 16U) | (static_cast<std::uint32_t>(source[3]) << 24U);
    }
}

bool ReadState(Steinberg::IBStream* stream, StateData& state)
{
    if(!stream)
        return false;

    Steinberg::IBStreamer reader(stream, kLittleEndian);
    Steinberg::int32 magic {};
    Steinberg::int32 version {};
    Steinberg::int32 bypass {};
    Steinberg::int32 chunkSize {};
    if(!reader.readInt32(magic) || magic != StateMagic || !reader.readInt32(version) || version != StateVersion
        || !reader.readInt32(bypass) || !reader.readInt32(chunkSize) || chunkSize < 0 || chunkSize > MaximumChunkBytes)
        return false;

    state.bypass = bypass != 0;
    state.legacyChunk.resize(static_cast<std::size_t>(chunkSize));
    return chunkSize == 0 || reader.readRaw(state.legacyChunk.data(), chunkSize) == chunkSize;
}

bool WriteState(Steinberg::IBStream* stream, const StateData& state)
{
    if(!stream || state.legacyChunk.size() > static_cast<std::size_t>(MaximumChunkBytes))
        return false;

    Steinberg::IBStreamer writer(stream, kLittleEndian);
    const auto chunkSize = static_cast<Steinberg::int32>(state.legacyChunk.size());
    return writer.writeInt32(StateMagic) && writer.writeInt32(StateVersion) && writer.writeInt32(state.bypass ? 1 : 0)
        && writer.writeInt32(chunkSize)
        && (chunkSize == 0 || writer.writeRaw(state.legacyChunk.data(), chunkSize) == chunkSize);
}

bool ExtractLegacyParameters(const std::vector<std::uint8_t>& chunk, std::array<float, 44>& parameters)
{
    constexpr std::size_t parameterOffset = LegacyHeaderBytes + ProgramNameBytes;
    const std::size_t requiredBytes = parameterOffset + parameters.size() * sizeof(float);
    if(chunk.size() < requiredBytes || ReadLittleEndian32(chunk.data()) != LegacyChunkMagic
        || ReadLittleEndian32(chunk.data() + 4) != 101U)
        return false;

    for(std::size_t index = 0; index < parameters.size(); ++index)
    {
        const std::uint32_t bits = ReadLittleEndian32(chunk.data() + parameterOffset + index * sizeof(float));
        std::memcpy(&parameters[index], &bits, sizeof(float));
    }
    return true;
}

bool ExtractLegacyProgram(const std::vector<std::uint8_t>& chunk, Steinberg::int32& program)
{
    if(chunk.size() < LegacyHeaderBytes || ReadLittleEndian32(chunk.data()) != LegacyChunkMagic
        || ReadLittleEndian32(chunk.data() + 4) != 101U)
        return false;
    program = static_cast<Steinberg::int32>(ReadLittleEndian32(chunk.data() + 12));
    return true;
}
}
