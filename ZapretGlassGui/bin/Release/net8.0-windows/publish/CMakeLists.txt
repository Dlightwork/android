cmake_minimum_required(VERSION 3.16)
project(dPI-Bypass VERSION 1.0.0 LANGUAGES CXX)

# C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Detect compiler and set flags accordingly
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    # MinGW/GCC
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -Wall -Wextra -D_WIN32_WINNT=0x0600")
    set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
    set(CMAKE_CXX_FLAGS_RELEASE "-O2 -s")
elseif(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    # Visual Studio
    add_definitions(-DWIN32_LEAN_AND_MEAN -D_CRT_SECURE_NO_WARNINGS)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4 /O2 /EHsc")
    set(CMAKE_CXX_FLAGS_DEBUG "/Zi /Od")
    set(CMAKE_CXX_FLAGS_RELEASE "/O2")
else()
    # Generic
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2")
endif()

# Include directories - WinDivert is in project root
include_directories(${CMAKE_SOURCE_DIR})
link_directories(${CMAKE_SOURCE_DIR})

# Check WinDivert exists in project folder
if(NOT EXISTS "${CMAKE_SOURCE_DIR}/windivert.h")
    message(FATAL_ERROR "WinDivert not found in project folder. Please copy windivert.h, WinDivert.lib, WinDivert.dll, WinDivert64.sys to ${CMAKE_SOURCE_DIR}")
endif()

message(STATUS "WinDivert found in project folder")

# Source files
set(SOURCES
    main.cpp
    packet_engine.cpp
    desync_strategies.cpp
    utils.cpp
    roblox_optimizer.cpp
)

# Header files (for IDE)
set(HEADERS
    config.h
    packet_engine.h
    desync_strategies.h
    utils.h
    roblox_optimizer.h
)

# Executable
add_executable(dpi-bypass ${SOURCES} ${HEADERS})

# Link libraries
target_link_libraries(dpi-bypass
    WinDivert
    ws2_32
    iphlpapi
)

# Set output directory
set_target_properties(dpi-bypass PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Copy WinDivert DLL and SYS to output directory
add_custom_command(TARGET dpi-bypass POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_SOURCE_DIR}/WinDivert.dll"
    $<TARGET_FILE_DIR:dpi-bypass>
    COMMENT "Copying WinDivert.dll to output directory"
)

add_custom_command(TARGET dpi-bypass POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_SOURCE_DIR}/WinDivert64.sys"
    $<TARGET_FILE_DIR:dpi-bypass>
    COMMENT "Copying WinDivert64.sys to output directory"
)

# Installation
install(TARGETS dpi-bypass
    RUNTIME DESTINATION bin
)

install(FILES
    "${CMAKE_SOURCE_DIR}/WinDivert.dll"
    "${CMAKE_SOURCE_DIR}/WinDivert64.sys"
    DESTINATION bin
)

# Print configuration
message(STATUS "")
message(STATUS "dPI-Bypass Configuration:")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "  WinDivert: ${CMAKE_SOURCE_DIR} (local)")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "")

