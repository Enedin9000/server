add_subdirectory(detour)
# add_subdirectory(lua) # Handled globally 
# add_subdirectory(mysql) # Handled globally
add_subdirectory(recast)
add_subdirectory(sol)
add_subdirectory(spdlog)
# add_subdirectory(zmq) # Handled globally

# CPM Modules

CPMAddPackage(
    NAME efsw
    GITHUB_REPOSITORY LandSandBoat/efsw
    GIT_TAG b477e1c8f00bf483b1be256321d5e32784d6df96
) # defines: efsw

CPMAddPackage(
    NAME argparse
    GITHUB_REPOSITORY p-ranav/argparse
    GIT_TAG 4cacdc4b30da8e9bdc8aefb6dea575b345da8b2b
) # defines: argparse

# Enable Tracy on command-line with 'cmake -DTRACY_ENABLE=ON ..'
option(TRACY_ENABLE "Enable Tracy profiling." OFF)
message(STATUS "TRACY_ENABLE: ${TRACY_ENABLE}")

if(TRACY_ENABLE)
    CPMAddPackage(
        NAME tracy
        GITHUB_REPOSITORY wolfpld/tracy
        VERSION 0.7.8
    )

    if (tracy_ADDED)
        add_library(tracy_client STATIC ${tracy_SOURCE_DIR}/TracyClient.cpp)
        target_include_directories(tracy_client
            PUBLIC
                $<BUILD_INTERFACE:${tracy_SOURCE_DIR}>
            )
        target_compile_definitions(tracy_client PUBLIC TRACY_ENABLE TRACY_ON_DEMAND TRACY_NO_EXIT TRACY_NO_BROADCAST)
        target_link_libraries(tracy_client PRIVATE no_warnings)

        if(MSVC AND CMAKE_SIZEOF_VOID_P EQUAL 4)
            set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /LARGEADDRESSAWARE")
        endif()
    endif()
endif(TRACY_ENABLE)
