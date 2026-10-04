cmake_minimum_required(VERSION 3.14)
project(crudoc_j2k_library VERSION 0.0.1 LANGUAGES C)

# CMake 3.30+ deprecates FetchContent_Populate(<name>); we need it to pass
# EXCLUDE_FROM_ALL on older CMake (Android's is 3.22).
if(POLICY CMP0169)
  cmake_policy(SET CMP0169 OLD)
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_CODEC OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_DOC OFF CACHE BOOL "" FORCE)

include(FetchContent)
FetchContent_Declare(openjpeg
  GIT_REPOSITORY https://github.com/uclouvain/openjpeg.git
  GIT_TAG v2.5.3)
FetchContent_GetProperties(openjpeg)
if(NOT openjpeg_POPULATED)
  FetchContent_Populate(openjpeg)
  # EXCLUDE_FROM_ALL keeps OpenJPEG's install rules out of Flutter's install step.
  add_subdirectory(${openjpeg_SOURCE_DIR} ${openjpeg_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()

# OpenJPEG caches one output folder for every library; keep ours out of it.
unset(LIBRARY_OUTPUT_PATH CACHE)
unset(EXECUTABLE_OUTPUT_PATH CACHE)

add_library(crudoc_j2k SHARED crudoc_j2k.c)
target_include_directories(crudoc_j2k PRIVATE
  ${openjpeg_SOURCE_DIR}/src/lib/openjp2
  ${openjpeg_BINARY_DIR}/src/lib/openjp2)
target_link_libraries(crudoc_j2k PRIVATE openjp2)
target_compile_definitions(crudoc_j2k PRIVATE OPJ_STATIC DART_SHARED_LIB)
set_target_properties(crudoc_j2k PROPERTIES OUTPUT_NAME "crudoc_j2k")
