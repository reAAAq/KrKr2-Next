cmake_minimum_required(VERSION 3.16)

project(engine_api LANGUAGES C CXX)

add_library(engine_api SHARED
    src/engine_api.cpp
)

target_compile_features(engine_api PRIVATE cxx_std_17)
target_compile_definitions(engine_api PRIVATE ENGINE_API_BUILD_SHARED)
target_include_directories(engine_api
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set_target_properties(engine_api PROPERTIES
    OUTPUT_NAME "engine_api"
)
