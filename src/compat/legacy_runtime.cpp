// Initializes FFTW plans and loads the original factory presets from the plug-in bundle.
#include <StdAfx.h>

#include "legacy_runtime.hpp"

#include "BlkFxParam.h"
#include "VstProgram.h"
#include "rfftw_float.h"

#include <dlfcn.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <vector>

std::vector<VstProgram<BlkFxParam::TOTAL_NUM>> g_blk_fx_presets;

bool GlobalInitOk() { return false; }

namespace
{
std::filesystem::path ResourceDirectory()
{
    Dl_info info {};
    if(dladdr(reinterpret_cast<const void*>(&InitializeLegacyRuntime), &info) == 0 || !info.dli_fname)
        return {};
    return std::filesystem::path(info.dli_fname).parent_path().parent_path() / "Resources";
}

bool LoadPresets()
{
    std::ifstream input(ResourceDirectory() / "stereo_presets.txt");
    if(!input)
        return false;

    std::string line;
    while(std::getline(input, line))
    {
        if(!line.empty())
            g_blk_fx_presets.emplace_back(line.c_str());
    }
    return !g_blk_fx_presets.empty();
}
}

bool InitializeLegacyRuntime()
{
    static std::once_flag once;
    static bool initialized = false;
    try
    {
        std::call_once(once,
            []
            {
                if(!LoadPresets())
                    return;
                CreateFFTWfPlans();
                initialized = true;
            });
    }
    catch(...)
    {
        return false;
    }
    return initialized;
}

float LegacyDefaultParameter(std::size_t index)
{
    if(index == BlkFxParam::DELAY)
        return 0.0f;
    if(index == BlkFxParam::FFT_LEN)
        return BlkFxParam::getFFTLenParam(16);
    if(index == BlkFxParam::OVERLAP)
        return 0.35f;
    return 0.0f;
}

std::size_t LegacyPresetCount() { return g_blk_fx_presets.size(); }

const char* LegacyPresetName(std::size_t index)
{
    if(index >= g_blk_fx_presets.size())
        return nullptr;
    return g_blk_fx_presets[index].getName();
}

bool ReadLegacyPreset(std::size_t index, std::array<float, 44>& parameters)
{
    if(index >= g_blk_fx_presets.size())
        return false;
    std::copy(g_blk_fx_presets[index].params.begin(), g_blk_fx_presets[index].params.end(), parameters.begin());
    return true;
}
