# mybench-ni, the myDAQ driver library behind the USB backend, is a closed component under its own
# binary licence (MYBENCH's licence exception: LICENSE-EXCEPTION.md). It is not needed to build
# MYBENCH: without it the build has the simulated myDAQ only. This file provides the target
# libmybench::mydaq from the first of these that is available:
#
#   1. MYBENCH_NI_SDK         an unpacked mybench-ni binary SDK directory
#   2. MYBENCH_NI_SOURCE_DIR  the driver sources, by default mybench-ni/ (a submodule of the
#                             private repository spunwave/mybench-ni, skipped by default:
#                             git submodule update --init --checkout mybench-ni), built here as
#                             the hardened shared library
#
# If neither is there, MYBENCH_WITH_USB turns OFF with a warning, unless MYBENCH_NI_REQUIRED is ON
# (default: the MYBENCH_NI_REQUIRED environment variable, which the CI action sets when it fetched
# the driver), which makes it an error.

set(MYBENCH_NI_SDK "" CACHE PATH "Unpacked mybench-ni binary SDK (optional)")
set(MYBENCH_NI_SOURCE_DIR "${PROJECT_SOURCE_DIR}/mybench-ni" CACHE PATH
    "mybench-ni sources (default: the mybench-ni/ submodule)")
if("$ENV{MYBENCH_NI_REQUIRED}")
    set(_mybench_ni_required_default ON)
else()
    set(_mybench_ni_required_default OFF)
endif()
option(MYBENCH_NI_REQUIRED "Fail if the mybench-ni driver is not found" ${_mybench_ni_required_default})

if(MYBENCH_NI_SDK)
    # The SDK's CMake package is still called libmybench (imported target libmybench::mydaq).
    find_package(libmybench CONFIG REQUIRED PATHS "${MYBENCH_NI_SDK}" NO_DEFAULT_PATH)
    set(MYBENCH_NI_LICENSE_FILE "${MYBENCH_NI_SDK}/LICENSE.md")
    message(STATUS "mybench-ni: SDK ${libmybench_DIR}")
elseif(EXISTS "${MYBENCH_NI_SOURCE_DIR}/CMakeLists.txt")
    # The hardened shared library (exports only the public C API), shipped next to the
    # application (packaging/CMakeLists.txt). The driver's own tests and CLI are not built.
    set(LIBMYBENCH_SHARED ON CACHE BOOL "" FORCE)
    set(LIBMYBENCH_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(LIBMYBENCH_BUILD_CLI OFF CACHE BOOL "" FORCE)
    set(LIBMYBENCH_INSTALL OFF CACHE BOOL "" FORCE)
    add_subdirectory("${MYBENCH_NI_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/mybench-ni")
    set(MYBENCH_NI_LICENSE_FILE "${MYBENCH_NI_SOURCE_DIR}/LICENSE.md")
    message(STATUS "mybench-ni: source ${MYBENCH_NI_SOURCE_DIR} (shared)")
elseif(MYBENCH_NI_REQUIRED)
    message(FATAL_ERROR
        "mybench-ni (the closed myDAQ driver) not found: no MYBENCH_NI_SDK and no sources in "
        "${MYBENCH_NI_SOURCE_DIR}. With access to spunwave/mybench-ni:\n"
        "    git submodule update --init --checkout mybench-ni\n"
        "or set MYBENCH_NI_SDK to an unpacked binary SDK.")
else()
    message(WARNING
        "mybench-ni (the closed myDAQ driver) not found: building with the simulated myDAQ only. "
        "For the USB backend, set MYBENCH_NI_SDK to an unpacked mybench-ni binary SDK.")
    set(MYBENCH_WITH_USB OFF)
endif()
