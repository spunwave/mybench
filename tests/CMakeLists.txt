# Qt Test unit tests for mydaq_core, one executable per area. Run: ctest --test-dir <build> --output-on-failure

set(MYDAQ_CORE_TESTS
    decimate
    device
    devicemanager
    digitaltimeline
    fft
    measure
    simcounter
    simdevice
    spectrum
    trigger
    units
    utf8
    waveform
    window
)

foreach(name IN LISTS MYDAQ_CORE_TESTS)
    add_executable(tst_${name} tst_${name}.cpp)
    target_link_libraries(tst_${name} PRIVATE mydaq_core Qt6::Test)
    if(MSVC)
        target_compile_options(tst_${name} PRIVATE /W4)
    else()
        target_compile_options(tst_${name} PRIVATE -Wall -Wextra)
    endif()
    add_test(NAME ${name} COMMAND tst_${name})
    # MYBENCH_NO_USB: unit tests never open the shared hardware (the USB provider stays idle).
    set_tests_properties(${name} PROPERTIES TIMEOUT 120 ENVIRONMENT MYBENCH_NO_USB=1)
endforeach()

# The native backend's error messages (no hardware, no mock: any build with the USB backend).
if(MYBENCH_WITH_USB AND TARGET libmydaq::mydaq)
    add_executable(tst_usberrors tst_usberrors.cpp)
    target_link_libraries(tst_usberrors PRIVATE mydaq_core libmydaq::mydaq Qt6::Test)
    target_include_directories(tst_usberrors PRIVATE ${PROJECT_SOURCE_DIR}/core/src)
    if(NOT MSVC)
        target_compile_options(tst_usberrors PRIVATE -Wall -Wextra)
    endif()
    add_test(NAME usberrors COMMAND tst_usberrors)
    set_tests_properties(usberrors PROPERTIES TIMEOUT 60 ENVIRONMENT MYBENCH_NO_USB=1)
endif()

# Native USB backend against the driver's mock transport (no hardware). Only when the driver's
# tests are built (a static driver library): the shared library does not export what the mock needs.
if(MYBENCH_WITH_USB AND TARGET mydaq_mock)
    add_executable(tst_usbdevice tst_usbdevice.cpp)
    target_link_libraries(tst_usbdevice PRIVATE mydaq_core mydaq_mock Qt6::Test)
    target_include_directories(tst_usbdevice PRIVATE ${PROJECT_SOURCE_DIR}/core/src)
    if(NOT MSVC)
        target_compile_options(tst_usbdevice PRIVATE -Wall -Wextra)
    endif()
    add_test(NAME usbdevice COMMAND tst_usbdevice)
    set_tests_properties(usbdevice PROPERTIES TIMEOUT 120)

    # Real-hardware check through DeviceManager: opt-in (MYDAQ_HW_TESTS=1 ctest -L hw).
    add_executable(usb_hw_check usb_hw_check.cpp)
    target_link_libraries(usb_hw_check PRIVATE mydaq_core)
    if(UNIX)
        add_test(NAME usb_hw
            COMMAND sh -c "if [ \"$MYDAQ_HW_TESTS\" = 1 ]; then exec \"$0\"; else echo 'hardware test skipped (set MYDAQ_HW_TESTS=1)'; exit 77; fi"
                    $<TARGET_FILE:usb_hw_check>)
        set_tests_properties(usb_hw PROPERTIES LABELS "hw" SKIP_RETURN_CODE 77 TIMEOUT 300)
    endif()
endif()

# White-box test of a simulator internal.
target_include_directories(tst_digitaltimeline PRIVATE ${PROJECT_SOURCE_DIR}/core/src)

# App-level hardware tests (label "hw", opt-in; tests/hw/CMakeLists.txt).
add_subdirectory(hw)

# Cross-instrument AI/AO/audio exclusivity through the ResourceArbiter (tests/exclusivity).
add_subdirectory(exclusivity)
