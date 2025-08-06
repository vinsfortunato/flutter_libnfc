# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(flutter_libnfc_library VERSION 0.0.1 LANGUAGES C)

add_library(flutter_libnfc SHARED
  "flutter_libnfc.c"
)

set_target_properties(flutter_libnfc PROPERTIES
  PUBLIC_HEADER flutter_libnfc.h
  OUTPUT_NAME "flutter_libnfc"
)

target_compile_definitions(flutter_libnfc PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(flutter_libnfc PRIVATE "-Wl,-z,max-page-size=16384")
endif()
