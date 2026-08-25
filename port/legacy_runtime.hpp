// Initializes FFTW plans and loads the original factory presets from the plug-in bundle.
#pragma once

#include <array>
#include <cstddef>

bool InitializeLegacyRuntime();
float LegacyDefaultParameter(std::size_t index);
std::size_t LegacyPresetCount();
const char* LegacyPresetName(std::size_t index);
bool ReadLegacyPreset(std::size_t index, std::array<float, 44>& parameters);
