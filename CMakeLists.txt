# Builds the preserved DtBlkFx engine as a native macOS VST3 plug-in.
cmake_minimum_required(VERSION 3.25)

if(APPLE AND NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
endif()
if(APPLE AND NOT DEFINED CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "macOS architectures")
endif()

project(dtblk_osx_recompiled VERSION 1.1.1 LANGUAGES C CXX)

option(DTBLKFX_BUILD_AUV2 "Build the macOS Audio Unit v2 wrapper" OFF)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)

if(APPLE AND NOT XCODE AND NOT DEFINED ENV{XCODE_VERSION})
    set(XCODE_VERSION "26.0")
    set(ENV{XCODE_VERSION} "${XCODE_VERSION}")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(DISABLE_FORTRAN ON CACHE BOOL "" FORCE)
set(ENABLE_FLOAT ON CACHE BOOL "" FORCE)
set(ENABLE_LONG_DOUBLE OFF CACHE BOOL "" FORCE)
set(ENABLE_QUAD_PRECISION OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENMP OFF CACHE BOOL "" FORCE)
set(ENABLE_THREADS OFF CACHE BOOL "" FORCE)

set(SMTG_CREATE_PLUGIN_LINK OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VST3_HOSTING_EXAMPLES ON CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VSTGUI_SUPPORT OFF CACHE BOOL "" FORCE)
set(SMTG_RUN_VST_VALIDATOR OFF CACHE BOOL "" FORCE)

FetchContent_Declare(fftw
    URL "https://fftw.org/fftw-3.3.10.tar.gz"
    URL_HASH "SHA256=56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467"
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
FetchContent_MakeAvailable(fftw)

if(APPLE AND DTBLKFX_BUILD_AUV2)
    FetchContent_Declare(audiounitsdk
        GIT_REPOSITORY "https://github.com/apple/AudioUnitSDK.git"
        GIT_TAG "53a9a2008aae7fb1b0a9f093dd523b9b12f6c0d9"
        GIT_SHALLOW FALSE
    )
    FetchContent_MakeAvailable(audiounitsdk)
endif()

add_subdirectory(third_party/vst3sdk EXCLUDE_FROM_ALL)
set(public_sdk_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/vst3sdk/public.sdk")

set(DTBLKFX_ENGINE_SOURCES
    dtblkfx/DtBlkFx.cpp
    dtblkfx/FxRun1_0.cpp
    dtblkfx/FxState1_0.cpp
    dtblkfx/NoteFreq.cpp
    dtblkfx/fft_frac_shift.cpp
    dtblkfx/fftw_support.cpp
    dtblkfx/misc_stuff.cpp
    dtblkfx/rfftw_float.cpp
    dtblkfx/sweep1_coeff.cpp
    dtblkfx/sweep2_coeff.cpp
    dtblkfx/sweep3_coeff.cpp
    dtblkfx/sweep4_coeff.cpp
    dtblkfx/sweep5_coeff.cpp
    port/legacy_runtime.cpp
)

add_library(dtblkfx_engine STATIC ${DTBLKFX_ENGINE_SOURCES})
target_compile_features(dtblkfx_engine PUBLIC cxx_std_17)
target_compile_definitions(dtblkfx_engine PUBLIC DTBLKFX_HEADLESS=1 STEREO=1)
target_include_directories(dtblkfx_engine
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/dtblkfx
        ${CMAKE_CURRENT_SOURCE_DIR}/port
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/projects
        ${fftw_SOURCE_DIR}/api
)
target_link_libraries(dtblkfx_engine PRIVATE fftw3f)

set(DTBLKFX_VST3_SOURCES
    vst3/controller.cpp
    vst3/controller.hpp
    vst3/editor.hpp
    vst3/factory.cpp
    vst3/ids.hpp
    vst3/processor.cpp
    vst3/processor.hpp
    vst3/state.cpp
    vst3/state.hpp
    vst3/spectrum.hpp
    vst3/version.hpp
)

if(APPLE)
    list(APPEND DTBLKFX_VST3_SOURCES vst3/editor.mm)
endif()

smtg_add_vst3plugin(DtBlkFx
    PACKAGE_NAME "DtBlkFx"
    SOURCES_LIST ${DTBLKFX_VST3_SOURCES}
)
target_compile_features(DtBlkFx PRIVATE cxx_std_17)
target_include_directories(DtBlkFx PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(DtBlkFx PRIVATE dtblkfx_engine fftw3f sdk)
if(APPLE)
    target_link_libraries(DtBlkFx PRIVATE "-framework Cocoa")
    set_source_files_properties(vst3/editor.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
endif()

file(GLOB DTBLKFX_RESOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/resources/*")
smtg_target_add_plugin_resources(DtBlkFx
    RESOURCES
        ${DTBLKFX_RESOURCES}
        ${CMAKE_CURRENT_SOURCE_DIR}/vst3/DtBlkFx.icns
)
smtg_target_set_bundle(DtBlkFx
    BUNDLE_IDENTIFIER "org.darrelltam.dtblkfx.vst3"
    COMPANY_NAME "Darrell Tam"
)
configure_file(vst3/Info.plist.in DtBlkFx.Info.plist @ONLY)
set_target_properties(DtBlkFx PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/DtBlkFx.Info.plist"
)

if(APPLE AND NOT XCODE)
    get_target_property(DTBLKFX_BUNDLE_PATH DtBlkFx SMTG_PLUGIN_PACKAGE_PATH)
    add_custom_command(TARGET DtBlkFx POST_BUILD
        COMMAND /usr/bin/codesign --force --sign - "${DTBLKFX_BUNDLE_PATH}"
        VERBATIM
    )
endif()

if(APPLE)
    add_executable(dtblkfx_smoke
        tests/smoke_host.mm
        ${public_sdk_SOURCE_DIR}/source/common/memorystream.cpp
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/plugprovider.cpp
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/module_mac.mm
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/parameterchanges.cpp
    )
    target_compile_features(dtblkfx_smoke PRIVATE cxx_std_17)
    target_include_directories(dtblkfx_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(dtblkfx_smoke PRIVATE sdk_hosting "-framework Cocoa")
    set_target_properties(dtblkfx_smoke PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/Release"
    )
    set_source_files_properties(
        tests/smoke_host.mm
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/module_mac.mm
        PROPERTIES COMPILE_FLAGS "-fobjc-arc"
    )
    smtg_target_setup_universal_binary(dtblkfx_smoke)

    add_executable(dtblkfx_perf
        tests/perf_host.mm
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/module_mac.mm
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/parameterchanges.cpp
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/plugprovider.cpp
    )
    target_compile_features(dtblkfx_perf PRIVATE cxx_std_20)
    target_link_libraries(dtblkfx_perf PRIVATE sdk_hosting "-framework Cocoa")
    set_target_properties(dtblkfx_perf PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/Release"
    )
    set_source_files_properties(
        tests/perf_host.mm
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/module_mac.mm
        PROPERTIES COMPILE_FLAGS "-fobjc-arc"
    )
    smtg_target_setup_universal_binary(dtblkfx_perf)

    add_executable(dtblkfx_presets
        tests/preset_tool.cpp
        ${public_sdk_SOURCE_DIR}/source/common/memorystream.cpp
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/plugprovider.cpp
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/module_mac.mm
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/parameterchanges.cpp
        ${public_sdk_SOURCE_DIR}/source/vst/vstpresetfile.cpp
    )
    target_compile_features(dtblkfx_presets PRIVATE cxx_std_17)
    target_include_directories(dtblkfx_presets PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(dtblkfx_presets PRIVATE sdk_hosting "-framework Cocoa")
    set_target_properties(dtblkfx_presets PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/Release"
    )
    set_source_files_properties(
        ${public_sdk_SOURCE_DIR}/source/vst/hosting/module_mac.mm
        PROPERTIES COMPILE_FLAGS "-fobjc-arc"
    )
    smtg_target_setup_universal_binary(dtblkfx_presets)
endif()

if(APPLE AND DTBLKFX_BUILD_AUV2)
    file(READ
        "${public_sdk_SOURCE_DIR}/source/vst/auwrapper/auwrapper.mm"
        DTBLKFX_AUWRAPPER_ORIGINAL
    )
    string(REPLACE
        "(float)numPresets;"
        "(float)(numPresets - 1);"
        DTBLKFX_AUWRAPPER_SOURCE
        "${DTBLKFX_AUWRAPPER_ORIGINAL}"
    )
    if(DTBLKFX_AUWRAPPER_SOURCE STREQUAL DTBLKFX_AUWRAPPER_ORIGINAL)
        message(FATAL_ERROR "The pinned AU wrapper program-list patch no longer applies")
    endif()
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/generated")
    file(WRITE
        "${CMAKE_BINARY_DIR}/generated/dtblkfx_auwrapper.mm"
        "${DTBLKFX_AUWRAPPER_SOURCE}"
    )

    file(GLOB AUDIOUNIT_SDK_SOURCES CONFIGURE_DEPENDS
        "${audiounitsdk_SOURCE_DIR}/src/AudioUnitSDK/*.cpp"
    )
    add_library(dtblkfx_audiounitsdk STATIC ${AUDIOUNIT_SDK_SOURCES})
    target_compile_features(dtblkfx_audiounitsdk PUBLIC cxx_std_17)
    target_include_directories(dtblkfx_audiounitsdk PUBLIC
        "${audiounitsdk_SOURCE_DIR}/include"
    )
    target_link_libraries(dtblkfx_audiounitsdk PUBLIC
        "-framework AudioToolbox"
        "-framework CoreAudio"
        "-framework CoreFoundation"
    )

    add_library(DtBlkFxAU MODULE
        ${public_sdk_SOURCE_DIR}/source/vst/auwrapper/aucocoaview.mm
        ${CMAKE_BINARY_DIR}/generated/dtblkfx_auwrapper.mm
        ${public_sdk_SOURCE_DIR}/source/vst/auwrapper/NSDataIBStream.mm
    )
    target_compile_features(DtBlkFxAU PRIVATE cxx_std_17)
    target_compile_definitions(DtBlkFxAU PRIVATE
        SMTG_AUWRAPPER_USES_AUSDK
        SMTG_AUCocoaUIBase_CLASS_NAME=DtBlkFxAUCocoaUIBase
        CA_USE_AUDIO_PLUGIN_ONLY=0
    )
    target_include_directories(DtBlkFxAU PRIVATE
        "${audiounitsdk_SOURCE_DIR}/include"
        "${public_sdk_SOURCE_DIR}/source/vst/auwrapper"
    )
    target_link_libraries(DtBlkFxAU PRIVATE
        sdk_hosting
        dtblkfx_audiounitsdk
        "-framework AudioUnit"
        "-framework CoreMIDI"
        "-framework AudioToolbox"
        "-framework CoreFoundation"
        "-framework Carbon"
        "-framework Cocoa"
        "-framework CoreAudio"
    )
    add_dependencies(DtBlkFxAU DtBlkFx)
    set_target_properties(DtBlkFxAU PROPERTIES
        BUNDLE TRUE
        BUNDLE_EXTENSION component
        OUTPUT_NAME DtBlkFx
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/AU/Release"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/au/Info.plist.in"
    )
    smtg_target_setup_universal_binary(DtBlkFxAU)
    add_custom_command(TARGET DtBlkFxAU POST_BUILD
        COMMAND /usr/bin/ditto --norsrc
            "$<TARGET_BUNDLE_DIR:DtBlkFx>"
            "$<TARGET_BUNDLE_DIR:DtBlkFxAU>/Contents/Resources/plugin.vst3"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_CURRENT_SOURCE_DIR}/vst3/DtBlkFx.icns"
            "$<TARGET_BUNDLE_DIR:DtBlkFxAU>/Contents/Resources/DtBlkFx.icns"
        COMMAND /usr/bin/codesign --force --sign - --deep "$<TARGET_BUNDLE_DIR:DtBlkFxAU>"
        VERBATIM
    )

    add_executable(dtblkfx_au_presets tests/au_preset_tool.mm)
    target_compile_features(dtblkfx_au_presets PRIVATE cxx_std_17)
    target_link_libraries(dtblkfx_au_presets PRIVATE
        "-framework AudioToolbox"
        "-framework CoreFoundation"
    )
    set_target_properties(dtblkfx_au_presets PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/Release"
    )
endif()
