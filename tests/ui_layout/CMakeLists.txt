# Layout lint: every built instrument's real panel in panes of
# 440..1320 x 560/700/824 px, stopped and running, against the simulator. One ctest case per
# instrument (they run in parallel), all labelled "layout": `ctest -L layout` or `ctest -R layout_sweep`.
if(NOT MYBENCH_BUILT_INSTRUMENTS)
    return()
endif()

# The same generated registration list as the app (app/instruments.cpp.in).
set(MYBENCH_REGISTER_DECLS "")
set(MYBENCH_REGISTER_CALLS "")
foreach(id IN LISTS MYBENCH_BUILT_INSTRUMENTS)
    string(SUBSTRING ${id} 0 1 initial)
    string(TOUPPER ${initial} initial)
    string(SUBSTRING ${id} 1 -1 rest)
    string(APPEND MYBENCH_REGISTER_DECLS "void register${initial}${rest}(mybench::InstrumentRegistry& registry);\n")
    string(APPEND MYBENCH_REGISTER_CALLS "    mybench::instruments::register${initial}${rest}(registry);\n")
endforeach()
configure_file(${PROJECT_SOURCE_DIR}/app/instruments.cpp.in ${CMAKE_CURRENT_BINARY_DIR}/layout_instruments.cpp @ONLY)

add_executable(tst_layout_sweep tst_layout_sweep.cpp ${CMAKE_CURRENT_BINARY_DIR}/layout_instruments.cpp)
foreach(id IN LISTS MYBENCH_BUILT_INSTRUMENTS)
    target_link_libraries(tst_layout_sweep PRIVATE mybench_instrument_${id} mybench_instrument_${id}plugin)
endforeach()
target_link_libraries(tst_layout_sweep PRIVATE mybench_ui mybench_offscreen Qt6::Test Qt6::Quick Qt6::QuickControls2)
target_compile_definitions(tst_layout_sweep PRIVATE MYBENCH_QML_DIR="${CMAKE_BINARY_DIR}/qml")
if(MSVC)
    target_compile_options(tst_layout_sweep PRIVATE /W4)
else()
    target_compile_options(tst_layout_sweep PRIVATE -Wall -Wextra)
endif()
target_link_options(tst_layout_sweep PRIVATE $<$<CXX_COMPILER_ID:AppleClang>:LINKER:-no_warn_duplicate_libraries>)

# "gen/editor" is the generator's second view (its own pane).
set(_layout_ids ${MYBENCH_BUILT_INSTRUMENTS})
if("gen" IN_LIST MYBENCH_BUILT_INSTRUMENTS)
    list(APPEND _layout_ids gen/editor)
endif()
foreach(id IN LISTS _layout_ids)
    string(REPLACE "/" "_" _name ${id})
    add_test(NAME layout_sweep_${_name} COMMAND tst_layout_sweep)
    set_tests_properties(layout_sweep_${_name} PROPERTIES
        LABELS "layout" TIMEOUT 600
        ENVIRONMENT "MYBENCH_NO_USB=1;QT_QPA_PLATFORM=offscreen;LAYOUT_SWEEP=${id}")
endforeach()

# The lint finds a known defect of every check (a synthetic scene).
add_test(NAME layout_sweep_selftest COMMAND tst_layout_sweep)
set_tests_properties(layout_sweep_selftest PROPERTIES LABELS "layout" TIMEOUT 120
    ENVIRONMENT "MYBENCH_NO_USB=1;QT_QPA_PLATFORM=offscreen;LAYOUT_SWEEP=selftest")
