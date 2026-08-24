// Registers the DtBlkFx processor and controller with VST3 hosts.
#include "controller.hpp"
#include "ids.hpp"
#include "processor.hpp"
#include "version.hpp"

#include "public.sdk/source/main/pluginfactory_constexpr.h"

BEGIN_FACTORY_DEF(DTBLKFX_COMPANY_NAME, DTBLKFX_COMPANY_WEB, DTBLKFX_COMPANY_EMAIL, 2)

DEF_CLASS(DtBlkVst3::ProcessorUID,
          Steinberg::PClassInfo::kManyInstances,
          kVstAudioEffectClass,
          DTBLKFX_PLUGIN_NAME,
          Steinberg::Vst::kDistributable,
          "Fx|Filter",
          DTBLKFX_VERSION_STRING,
          kVstVersionString,
          DtBlkVst3::Processor::createInstance,
          nullptr)

DEF_CLASS(DtBlkVst3::ControllerUID,
          Steinberg::PClassInfo::kManyInstances,
          kVstComponentControllerClass,
          DTBLKFX_PLUGIN_NAME " Controller",
          0,
          "",
          DTBLKFX_VERSION_STRING,
          kVstVersionString,
          DtBlkVst3::Controller::createInstance,
          nullptr)

END_FACTORY
