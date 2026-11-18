# Integrations with other tools:
#   scopehal/  mybench-scopehal-bridge: the myDAQ as an oscilloscope in ngscopeclient
#   mcp/       mybench-mcp + the in-app control server: MCP clients drive the running app
foreach(_dir scopehal mcp)
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/CMakeLists.txt)
        add_subdirectory(${_dir})
    endif()
endforeach()
