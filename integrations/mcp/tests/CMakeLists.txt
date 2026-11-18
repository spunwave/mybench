# MCP remote control against the simulated myDAQ: the tools in process, then the mybench-mcp
# bridge as a separate process speaking MCP on stdio to an in-process control server.
find_package(Qt6 REQUIRED COMPONENTS Test)

qt_add_executable(tst_mcp tst_mcp.cpp)
set_target_properties(tst_mcp PROPERTIES WIN32_EXECUTABLE FALSE MACOSX_BUNDLE FALSE)
target_link_libraries(tst_mcp PRIVATE
    mybench_mcp_server
    mybench_instrument_scope mybench_instrument_gen mybench_instrument_bode mybench_instrument_dsa
    mybench_instrument_dmm mybench_instrument_log
    Qt6::Test Qt6::Quick)
target_compile_definitions(tst_mcp PRIVATE MYBENCH_MCP_BRIDGE="$<TARGET_FILE:mybench-mcp>")
add_dependencies(tst_mcp mybench-mcp)
if(MSVC)
    target_compile_options(tst_mcp PRIVATE /W4)
else()
    target_compile_options(tst_mcp PRIVATE -Wall -Wextra)
endif()
add_test(NAME mcp COMMAND tst_mcp)
set_tests_properties(mcp PROPERTIES TIMEOUT 180 LABELS mcp
                     ENVIRONMENT "QT_QPA_PLATFORM=offscreen;MYBENCH_NO_USB=1")
