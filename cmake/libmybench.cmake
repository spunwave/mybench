# The myDAQ driver library behind the USB backend is a closed component in a private git
# submodule (MYBENCH's own licence exception: LICENSE-EXCEPTION.md). This file provides the
# target libmybench::mydaq from the first of these that is available:
#
#   1. MYBENCH_LIBMYBENCH_SDK         an unpacked binary SDK directory (optional)
#   2. MYBENCH_LIBMYBENCH_SOURCE_DIR  the driver sources, by default the submodule;
#                                   built here as the hardened shared library
#
# Without access to the driver, configure with -DMYBENCH_WITH_USB=OFF (simulated myDAQ only).

set(MYBENCH_LIBMYBENCH_SDK "" CACHE PATH "Unpacked libmybench binary SDK (optional)")
set(MYBENCH_LIBMYBENCH_SOURCE_DIR "${PROJECT_SOURCE_DIR}/libmybench" CACHE PATH
    "libmybench sources (default: the libmybench/ submodule)")

if(MYBENCH_LIBMYBENCH_SDK)
    find_package(libmybench CONFIG REQUIRED PATHS "${MYBENCH_LIBMYBENCH_SDK}" NO_DEFAULT_PATH)
    message(STATUS "libmybench: SDK ${libmybench_DIR}")
    return()
endif()

if(NOT EXISTS "${MYBENCH_LIBMYBENCH_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "libmybench sources not found in ${MYBENCH_LIBMYBENCH_SOURCE_DIR}.\n"
        "The USB backend needs the private repository spunwave/libmybench (ask for access), "
        "checked out as the libmybench/ submodule:\n"
        "    git submodule update --init\n"
        "(or clone with git clone --recursive). Without it, configure with "
        "-DMYBENCH_WITH_USB=OFF to build with the simulated myDAQ only.")
endif()

# The hardened shared library (exports only the public C API), shipped next to the application
# (packaging/CMakeLists.txt). The driver's own tests and CLI are not part of the MYBENCH build.
set(LIBMYBENCH_SHARED ON CACHE BOOL "" FORCE)
set(LIBMYBENCH_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LIBMYBENCH_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LIBMYBENCH_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${MYBENCH_LIBMYBENCH_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/libmybench")
set(libmybench_LICENSE_FILE "${MYBENCH_LIBMYBENCH_SOURCE_DIR}/LICENSE.md")
message(STATUS "libmybench: source ${MYBENCH_LIBMYBENCH_SOURCE_DIR} (shared)")
