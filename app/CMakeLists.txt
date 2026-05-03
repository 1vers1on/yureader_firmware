cmake_minimum_required(VERSION 3.20)

list(APPEND BOARD_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(yureader)

target_sources(app PRIVATE src/main.c)

target_include_directories(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)

file(GLOB_RECURSE ZIG_FILES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/zig/*")

add_custom_command(
    OUTPUT ${CMAKE_SOURCE_DIR}/build/libapp.a
    COMMAND zig build
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/src
    DEPENDS ${ZIG_FILES} ${CMAKE_CURRENT_SOURCE_DIR}/src/build.zig
    VERBATIM
)

add_custom_target(app_zig_build
    DEPENDS ${CMAKE_SOURCE_DIR}/build/libapp.a
)

add_dependencies(app app_zig_build)

add_subdirectory(drivers)
