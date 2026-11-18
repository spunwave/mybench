cmake_minimum_required(VERSION 3.21)
project(MYBENCH VERSION 0.1.0 LANGUAGES C CXX)

# The name people see (window title, About, menus, macOS bundle, desktop entry, installers, MCP
# replies): the brand is lowercase. MYBENCH_APP_NAME stays the internal identity: QSettings
# organization/application name (settings file and data folders), the app id below, the MCP
# socket, so renaming the display name never moves anyone's settings.
set(MYBENCH_DISPLAY_NAME "mybench" CACHE STRING "Application display name")
set(MYBENCH_APP_NAME "MYBENCH" CACHE STRING "Internal application name (settings location, ids); not shown")
# Reverse-DNS id: macOS bundle identifier, Linux desktop-file / AppStream id (packaging/).
set(MYBENCH_APP_ID "org.mybench.${MYBENCH_APP_NAME}" CACHE STRING "Application id (reverse DNS)")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# Sources are UTF-8 (Ω, µ, —, ± in literals): MSVC otherwise reads them in the ANSI code page.
add_compile_options("$<$<C_COMPILER_ID:MSVC>:/utf-8>" "$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")

find_package(Qt6 6.9 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Svg Test QuickTest)
qt_standard_project_setup(REQUIRES 6.9)   # AUTOMOC, AUTORCC, QML module defaults
# Optional (DMM continuity tone); found here so the app target, which links it through the DMM
# module, sees Qt6::Multimedia at finalization and deployment.
find_package(Qt6 QUIET COMPONENTS Multimedia)

option(MYBENCH_WITH_USB "Build the native libusb backend" ON)
if(MYBENCH_WITH_USB)
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(LIBUSB IMPORTED_TARGET libusb-1.0)
    endif()
    if(NOT LIBUSB_FOUND)
        # No pkg-config (typical on Windows, e.g. libusb from vcpkg or the libusb binary release):
        # look for the header and library directly (CMAKE_PREFIX_PATH / LIBUSB_ROOT) and provide
        # the same PkgConfig::LIBUSB target that core/ and the driver link.
        find_path(LIBUSB_INCLUDE_DIR libusb.h PATH_SUFFIXES libusb-1.0 include/libusb-1.0 include)
        find_library(LIBUSB_LIBRARY NAMES usb-1.0 libusb-1.0 PATH_SUFFIXES lib VS2022/MS64/dll MS64/dll)
        if(LIBUSB_INCLUDE_DIR AND LIBUSB_LIBRARY)
            add_library(PkgConfig::LIBUSB INTERFACE IMPORTED)
            set_target_properties(PkgConfig::LIBUSB PROPERTIES
                INTERFACE_INCLUDE_DIRECTORIES "${LIBUSB_INCLUDE_DIR}"
                INTERFACE_LINK_LIBRARIES "${LIBUSB_LIBRARY}")
            set(LIBUSB_FOUND TRUE)
            message(STATUS "libusb-1.0: ${LIBUSB_LIBRARY}")
        endif()
    endif()
    if(NOT LIBUSB_FOUND)
        message(WARNING "libusb-1.0 not found: building with the simulated device only")
        set(MYBENCH_WITH_USB OFF)
    endif()
endif()

enable_testing()

# CI diagnostics: -DMYBENCH_TEST_LOG_DIR=<dir> makes every QtTest/QuickTest executable (tst_*) also write
# its plain-text log to <dir>/<test name>.txt (-o file,txt next to -o -,txt). The Windows CI runner shows
# no test output otherwise. Must come before the add_subdirectory calls: it wraps add_test().
set(MYBENCH_TEST_LOG_DIR "" CACHE PATH "Directory receiving one QtTest log per tst_* test (CI diagnostics)")
if(MYBENCH_TEST_LOG_DIR)
    file(MAKE_DIRECTORY "${MYBENCH_TEST_LOG_DIR}")
    function(add_test)
        set(_args ${ARGV})
        list(LENGTH _args _n)
        if(_n GREATER 3 AND ARGV0 STREQUAL "NAME" AND ARGV2 STREQUAL "COMMAND" AND ARGV3 MATCHES "^tst_")
            list(INSERT _args 4 -o "-,txt" -o "${MYBENCH_TEST_LOG_DIR}/${ARGV1}.txt,txt")
        endif()
        _add_test(${_args})
    endfunction()
endif()

# The driver library behind the USB backend: a closed component in a private submodule
# (cmake/libmydaq.cmake). MYBENCH_WITH_USB=OFF builds the simulator only.
if(MYBENCH_WITH_USB)
    include(cmake/libmydaq.cmake)
endif()
add_subdirectory(core)
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/ui/CMakeLists.txt)
    add_subdirectory(ui)
endif()
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/instruments/CMakeLists.txt)
    add_subdirectory(instruments)
endif()
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/app/CMakeLists.txt)
    add_subdirectory(app)
endif()
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt)
    add_subdirectory(tests)
endif()
# Layout lint of the instrument panes (tests/ui_layout).
if(TARGET mybench_ui AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/ui_layout/CMakeLists.txt)
    add_subdirectory(tests/ui_layout)
endif()
# Other tools using the myDAQ: the ngscopeclient bridge.
option(MYBENCH_INTEGRATIONS "Build the ngscopeclient bridge" ON)
if(MYBENCH_INTEGRATIONS AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/integrations/CMakeLists.txt)
    add_subdirectory(integrations)
endif()

# Test executables are console applications on Windows (Qt's qt_add_executable makes GUI-subsystem
# ones), so QTest output reaches ctest and the CI log.
function(mybench_console_tests dir)
    get_property(_targets DIRECTORY ${dir} PROPERTY BUILDSYSTEM_TARGETS)
    foreach(_t IN LISTS _targets)
        get_target_property(_type ${_t} TYPE)
        if(_type STREQUAL "EXECUTABLE" AND (_t MATCHES "^tst_" OR _t STREQUAL "mybench-offscreen-test"))
            set_target_properties(${_t} PROPERTIES WIN32_EXECUTABLE FALSE)
        endif()
    endforeach()
    get_property(_subdirs DIRECTORY ${dir} PROPERTY SUBDIRECTORIES)
    foreach(_d IN LISTS _subdirs)
        mybench_console_tests(${_d})
    endforeach()
endfunction()
mybench_console_tests(${CMAKE_CURRENT_SOURCE_DIR})

# App icon, install rules, Qt runtime deployment and installers (CPack).
option(MYBENCH_PACKAGING "App icon, install rules and CPack packaging" ON)
if(MYBENCH_PACKAGING AND TARGET mybench AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/packaging/CMakeLists.txt)
    add_subdirectory(packaging)
endif()
