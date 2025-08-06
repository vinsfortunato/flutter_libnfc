# The Flutter tooling requires that developers have CMake 3.10 or later installed.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "flutter_libnfc")
project(${PROJECT_NAME} LANGUAGES CXX)

set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries")
set(LIBNFC_BUILD_EXAMPLES OFF CACHE BOOL "Do not build libnfc examples")
set(LIBNFC_BUILD_UTILS OFF CACHE BOOL "Do not build libnfc command-line utils")

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libnfc ${CMAKE_CURRENT_BINARY_DIR}/libnfc-build)

# --- Bundling ---
set(flutter_libnfc_bundled_libraries
  $<TARGET_FILE:nfc>
  PARENT_SCOPE
)