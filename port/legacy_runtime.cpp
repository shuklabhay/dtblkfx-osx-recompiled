// Initializes FFTW plans and loads the original factory presets from the plug-in bundle.
#include <StdAfx.h>

#include "legacy_runtime.hpp"

#include "BlkFxParam.h"
#include "VstProgram.h"
#include "rfftw_float.h"

#include <dlfcn.h>

#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <vector>

std::vector<VstProgram<BlkFxParam::TOTAL_NUM>> g_blk_fx_presets;

bool GlobalInitOk()
{
    return false;
}

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
        std::call_once(once, [] {
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
