#****************************************************************************
#* HarmonyOS port: builds Mayo core (MayoCore + MayoIO sources) as one static
#* library "mayo_core", without Qt.
#*
#* The root CMakeLists.txt requires Qt (find_package(QT ... REQUIRED)), so it
#* is left untouched; the source lists below mirror its "MayoCore+MayoIO source
#* files" section. Intended to be pulled in via add_subdirectory() by the
#* HarmonyOS app (OHOS toolchain, arm64-v8a).
#*
#* Inputs (cache variables):
#*   MAYO_OCCT_INCLUDE_DIR  OCCT headers (.../include/opencascade)
#*   MAYO_OCCT_LIB_DIR      directory holding the OCCT shared libraries (libTK*.so)
#* OCCT libraries are linked through targets named after them (TKernel, ...);
#* targets already defined by the parent project are reused, missing ones are
#* created here as IMPORTED from MAYO_OCCT_LIB_DIR.
#****************************************************************************

cmake_minimum_required(VERSION 3.16)
project(mayo_core LANGUAGES CXX)

get_filename_component(MAYO_ROOT_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(MAYO_SRC_DIR "${MAYO_ROOT_DIR}/src")

set(MAYO_OCCT_INCLUDE_DIR "" CACHE PATH "OCCT include directory (.../include/opencascade)")
set(MAYO_OCCT_LIB_DIR     "" CACHE PATH "Directory of OCCT shared libraries")
if(NOT EXISTS "${MAYO_OCCT_INCLUDE_DIR}/Standard_Version.hxx")
    message(FATAL_ERROR "MAYO_OCCT_INCLUDE_DIR is not an OCCT include directory: '${MAYO_OCCT_INCLUDE_DIR}'")
endif()

# OCCT version (Mayo requires >= 7.8 here: only the TKDE* toolkit layout is handled)
file(STRINGS "${MAYO_OCCT_INCLUDE_DIR}/Standard_Version.hxx" _occt_ver_lines
     REGEX "^#define OCC_VERSION_(MAJOR|MINOR|MAINTENANCE) ")
foreach(_line ${_occt_ver_lines})
    if(_line MATCHES "OCC_VERSION_(MAJOR|MINOR|MAINTENANCE) +([0-9]+)")
        set(_occt_${CMAKE_MATCH_1} ${CMAKE_MATCH_2})
    endif()
endforeach()
set(MAYO_OCCT_VERSION "${_occt_MAJOR}.${_occt_MINOR}.${_occt_MAINTENANCE}")
message(STATUS "mayo_core: OpenCascade ${MAYO_OCCT_VERSION} from ${MAYO_OCCT_INCLUDE_DIR}")
if(MAYO_OCCT_VERSION VERSION_LESS 7.8.0)
    message(FATAL_ERROR "mayo_core: OpenCascade >= 7.8.0 is required")
endif()

##########
# Generated headers: common/mayo_config.h, common/mayo_version.h
##########

# Version numbers are taken from the root CMakeLists.txt
file(STRINGS "${MAYO_ROOT_DIR}/CMakeLists.txt" _mayo_ver_lines
     REGEX "^set\\(Mayo_Version(Major|Minor|Patch) ")
foreach(_line ${_mayo_ver_lines})
    if(_line MATCHES "^set\\((Mayo_Version[A-Za-z]+) +([0-9]+)\\)")
        set(${CMAKE_MATCH_1} ${CMAKE_MATCH_2})
    endif()
endforeach()
set(Mayo_Version ${Mayo_VersionMajor}.${Mayo_VersionMinor}.${Mayo_VersionPatch})

set(Mayo_VersionCommit 0)
set(Mayo_VersionRevNum 0)
find_package(Git QUIET)
if(Git_FOUND)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
                    WORKING_DIRECTORY ${MAYO_ROOT_DIR}
                    OUTPUT_VARIABLE _commit OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-list --count HEAD
                    WORKING_DIRECTORY ${MAYO_ROOT_DIR}
                    OUTPUT_VARIABLE _revnum OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(_commit)
        set(Mayo_VersionCommit ${_commit})
    endif()
    if(_revnum)
        set(Mayo_VersionRevNum ${_revnum})
    endif()
endif()

# Assimp plugin is not built: MAYO_HAVE_ASSIMP* stay undefined
configure_file(${MAYO_ROOT_DIR}/cmake/mayo_config.h.in  ${CMAKE_CURRENT_BINARY_DIR}/common/mayo_config.h  @ONLY)
configure_file(${MAYO_ROOT_DIR}/cmake/mayo_version.h.in ${CMAKE_CURRENT_BINARY_DIR}/common/mayo_version.h @ONLY)

##########
# Source files (same as root CMakeLists.txt "MayoCore+MayoIO source files")
##########

file(
    GLOB MayoCore_SourceFiles
    ${MAYO_SRC_DIR}/base/*.cpp
    ${MAYO_SRC_DIR}/graphics/*.cpp
    ${MAYO_SRC_DIR}/gui/*.cpp
    ${MAYO_SRC_DIR}/3rdparty/fmt/src/format.cc
)

file(
    GLOB MayoIO_SourceFiles
    ${MAYO_SRC_DIR}/io_dxf/*.cpp
    ${MAYO_SRC_DIR}/io_image/*.cpp
    ${MAYO_SRC_DIR}/io_occ/*.cpp
    ${MAYO_SRC_DIR}/io_off/*.cpp
    ${MAYO_SRC_DIR}/io_ply/*.cpp
    ${MAYO_SRC_DIR}/3rdparty/miniply/miniply.cpp
)

# Qt-free helpers from src/app, also compiled into mayo-conv by the root CMakeLists.txt.
# brep_meshing: BRep shapes must be meshed after import, as GraphicsShapeObjectDriver
# disables auto-triangulation
set(MayoApp_QtFreeSourceFiles
    ${MAYO_SRC_DIR}/app/brep_meshing.cpp
)

add_library(mayo_core STATIC ${MayoCore_SourceFiles} ${MayoIO_SourceFiles} ${MayoApp_QtFreeSourceFiles})

set_target_properties(mayo_core PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON  # linked into the app's shared library
)

# Consumers include Mayo headers as "base/application.h", "io_occ/io_occ.h", ...
target_include_directories(mayo_core
    PUBLIC
        ${MAYO_SRC_DIR}
        ${MAYO_SRC_DIR}/3rdparty
        ${CMAKE_CURRENT_BINARY_DIR}
        ${MAYO_OCCT_INCLUDE_DIR}
)

# Same as root CMakeLists.txt, minus the QT_* definitions
target_compile_definitions(mayo_core PUBLIC OCCT_HANDLE_NOCAST)
if(UNIX AND NOT APPLE)
    target_compile_definitions(mayo_core PRIVATE OCC_CONVERT_SIGNALS)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(mayo_core PRIVATE
        -Wno-undefined-var-template
        -Wno-deprecated-declarations
        -Wno-macro-redefined
    )
endif()

##########
# OpenCascade libraries
##########

# Root CMakeLists.txt lists, for OCCT >= 7.8. HarmonyOS only has OpenGL ES, so
# TKOpenGl is replaced by TKOpenGles (same OpenGl_* classes).
set(MAYO_OCCT_LIBS
    # FoundationClasses
    TKernel TKMath
    # ModelingData
    TKG2d TKG3d TKGeomBase TKBRep
    # ModelingAlgorithms
    TKBO TKBool TKGeomAlgo TKHLR TKMesh TKPrim TKShHealing TKTopAlgo
    # Visualization
    TKMeshVS TKOpenGles TKService TKV3d
    # ApplicationFramework
    TKBin TKBinL TKBinXCAF TKCAF TKCDF TKLCAF TKVCAF TKXml TKXmlL
    # DataExchange
    TKXCAF TKXmlXCAF TKXSBase
    TKDE TKDEIGES TKDESTEP TKDESTL TKDEVRML
    # OBJ/glTF
    TKRWMesh TKDEOBJ TKDEGLTF
)

foreach(lib ${MAYO_OCCT_LIBS})
    if(TARGET ${lib})
        continue()
    endif()
    set(_so "${MAYO_OCCT_LIB_DIR}/lib${lib}.so")
    if(NOT EXISTS "${_so}")
        message(FATAL_ERROR "mayo_core: ${_so} not found (MAYO_OCCT_LIB_DIR='${MAYO_OCCT_LIB_DIR}')")
    endif()
    add_library(${lib} SHARED IMPORTED)
    set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION "${_so}")
endforeach()

find_package(Threads REQUIRED)
target_link_libraries(mayo_core PUBLIC ${MAYO_OCCT_LIBS} Threads::Threads)
