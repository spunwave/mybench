# The myDAQ driver library behind the USB backend is a closed component in a private git
# submodule (MYBENCH's own licence exception: LICENSE-EXCEPTION.md). This file provides the
# target libmydaq::mydaq from the first of these that is available:
#
#   1. MYBENCH_LIBMYDAQ_SDK         an unpacked binary SDK directory (optional)
#   2. MYBENCH_LIBMYDAQ_SOURCE_DIR  the driver sources, by default the submodule;
#                                   built here as the hardened shared library
#
# Without access to the driver, configure with -DMYBENCH_WITH_USB=OFF (simulated myDAQ only).

set(MYBENCH_LIBMYDAQ_SDK "" CACHE PATH "Unpacked libmybench binary SDK (optional)")
set(MYBENCH_LIBMYDAQ_SOURCE_DIR "${PROJECT_SOURCE_DIR}/libmydaq" CACHE PATH
    "libmybench sources (default: the libmydaq/ submodule)")

if(MYBENCH_LIBMYDAQ_SDK)
    find_package(libmydaq CONFIG REQUIRED PATHS "${MYBENCH_LIBMYDAQ_SDK}" NO_DEFAULT_PATH)
    message(STATUS "libmybench: SDK ${libmydaq_DIR}")
    return()
endif()

if(NOT EXISTS "${MYBENCH_LIBMYDAQ_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "libmybench sources not found in ${MYBENCH_LIBMYDAQ_SOURCE_DIR}.\n"
        "The USB backend needs the private repository spunwave/libmybench (ask for access), "
        "checked out as the libmydaq/ submodule:\n"
        "    git submodule update --init\n"
        "(or clone with git clone --recursive). Without it, configure with "
        "-DMYBENCH_WITH_USB=OFF to build with the simulated myDAQ only.")
endif()

# The hardened shared library (exports only the public C API), shipped next to the application
# (packaging/CMakeLists.txt). The driver's own tests and CLI are not part of the MYBENCH build.
set(LIBMYDAQ_SHARED ON CACHE BOOL "" FORCE)
set(LIBMYDAQ_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LIBMYDAQ_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LIBMYDAQ_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${MYBENCH_LIBMYDAQ_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/libmydaq")
set(libmydaq_LICENSE_FILE "${MYBENCH_LIBMYDAQ_SOURCE_DIR}/LICENSE.md")
message(STATUS "libmybench: source ${MYBENCH_LIBMYDAQ_SOURCE_DIR} (shared)")
