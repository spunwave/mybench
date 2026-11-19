# MCP (Model Context Protocol) remote control of MYBENCH:
#   mybench_mcp_server  the in-app control server (local socket, off unless --mcp), linked into `mybench`
#   mybench-mcp         the MCP stdio server an MCP client starts; forwards to the running app
# The tool definitions (tools.json) are compiled into both.

option(MYBENCH_MCP "Build the MCP remote control (mybench --mcp, mybench-mcp)" ON)
if(NOT MYBENCH_MCP)
    return()
endif()

find_package(Qt6 QUIET COMPONENTS Network)
if(NOT TARGET Qt6::Network)
    message(WARNING "Qt6 Network not found: MCP remote control is not built")
    return()
endif()

qt_add_library(mybench_mcp_common STATIC src/mcpcommon.cpp src/mcpcommon.h)
qt_add_resources(mybench_mcp_common "mybench_mcp_tools" PREFIX /mybench/mcp FILES tools.json)
target_include_directories(mybench_mcp_common PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(mybench_mcp_common PUBLIC Qt6::Core)

qt_add_library(mybench_mcp_server STATIC
    src/controlserver.cpp src/controlserver.h
    src/remotecontrol.cpp src/remotecontrol.h
)
target_link_libraries(mybench_mcp_server
    PUBLIC mybench_mcp_common mybench_framework mybench_plot Qt6::Network Qt6::Quick)

qt_add_executable(mybench-mcp src/bridge.cpp)
set_target_properties(mybench-mcp PROPERTIES WIN32_EXECUTABLE FALSE MACOSX_BUNDLE FALSE)
target_link_libraries(mybench-mcp PRIVATE mybench_mcp_common Qt6::Network)
target_compile_definitions(mybench-mcp PRIVATE MYBENCH_VERSION="${PROJECT_VERSION}")

foreach(_t mybench_mcp_common mybench_mcp_server mybench-mcp)
    if(MSVC)
        target_compile_options(${_t} PRIVATE /W4)
    else()
        target_compile_options(${_t} PRIVATE -Wall -Wextra)
    endif()
endforeach()

# The app starts the server from its shell (app/main.cpp, MYBENCH_WITH_MCP).
if(TARGET mybench)
    target_link_libraries(mybench PRIVATE mybench_mcp_server)
    target_compile_definitions(mybench PRIVATE MYBENCH_WITH_MCP=1)
endif()

add_subdirectory(tests)
