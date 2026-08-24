// Defines stable VST3 class and parameter identifiers for DtBlkFx.
#pragma once

#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"

namespace DtBlkVst3
{
constexpr Steinberg::Vst::ParamID LegacyParameterCount = 44;
constexpr Steinberg::Vst::ParamID BypassParameterId = 0x10000;

static DECLARE_UID(ProcessorUID, 0xE1DF6409, 0xE6A53951, 0x24C3CDC5, 0x20B60CD0);
static DECLARE_UID(ControllerUID, 0x9EDF743B, 0xF948D258, 0x4C517545, 0xD62AF358);
}
