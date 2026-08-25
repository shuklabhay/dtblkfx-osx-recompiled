# Builds the preserved DtBlkFx engine as a native macOS VST3 plug-in.
cmake_minimum_required(VERSION 3.25)

if(APPLE AND NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
endif()
if(APPLE AND NOT DEFINED CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "macOS architectures")
endif()

project(dtblk_osx_recompiled VERSION 1.1.1 LANGUAGES C CXX)

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
target_compile_options(dtblkfx_engine PRIVATE $<$<CONFIG:Release>:-ffast-math>)
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
    )
    target_compile_features(dtblkfx_smoke PRIVATE cxx_std_17)
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
endif()
