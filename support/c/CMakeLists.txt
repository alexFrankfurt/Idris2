cmake_minimum_required(VERSION 3.15)

# Build the Idris2 C support library (static and shared)
project(idris2_support C)

# Require C11 for portability (MSVC needs this for C atomics and noreturn)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Option to match Makefile's OLD_WIN=1
option(OLD_WIN "Enable _OLD_WIN define (matches Makefile OLD_WIN=1)" OFF)

# Version used in install layout (idris2-<version>/...).
# Respect a value set by the parent project; only provide a default if undefined.
if(NOT DEFINED IDRIS2_VERSION)
  set(IDRIS2_VERSION "0.0.0" CACHE STRING "Idris2 version for install layout")
endif()

# Collect sources
file(GLOB SRC_C "*.c")
set(SRCS ${SRC_C})

if(WIN32)
  list(APPEND SRCS
    windows/win_utils.c
    windows/win_hack.c
  )
endif()

# Base logical target name without 'lib' prefix
set(TARGET_BASE idris2_support)

# Shared library
add_library(${TARGET_BASE} SHARED ${SRCS})
# Static library
add_library(${TARGET_BASE}_static STATIC ${SRCS})

# Keep 'lib' prefix to match Makefile outputs
# Avoid MSVC import-vs-static .lib name clash by suffixing the static lib on MSVC
if(MSVC)
  set_target_properties(${TARGET_BASE} PROPERTIES OUTPUT_NAME "idris2_support" PREFIX "lib")
  set_target_properties(${TARGET_BASE}_static PROPERTIES OUTPUT_NAME "idris2_support_static" PREFIX "lib")
else()
  set_target_properties(${TARGET_BASE} PROPERTIES OUTPUT_NAME "idris2_support" PREFIX "lib")
  set_target_properties(${TARGET_BASE}_static PROPERTIES OUTPUT_NAME "idris2_support" PREFIX "lib")
endif()

# Optimize: -O2 (or /O2 on MSVC)
if(MSVC)
  target_compile_options(${TARGET_BASE} PRIVATE /O2)
  target_compile_options(${TARGET_BASE}_static PRIVATE /O2)
  # Enable C11 atomics usage on MSVC where available
  target_compile_definitions(${TARGET_BASE} PRIVATE _CRT_SECURE_NO_WARNINGS)
  target_compile_definitions(${TARGET_BASE}_static PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_options(${TARGET_BASE} PRIVATE -O2)
  target_compile_options(${TARGET_BASE}_static PRIVATE -O2)
endif()

# Preprocessor definitions
if(WIN32)
  target_compile_definitions(${TARGET_BASE} PRIVATE WIN32_LEAN_AND_MEAN)
  target_compile_definitions(${TARGET_BASE}_static PRIVATE WIN32_LEAN_AND_MEAN)
  # Ensure target architecture is defined for Windows headers (avoids "No Target Architecture")
  target_compile_definitions(${TARGET_BASE} PRIVATE _AMD64_)
  target_compile_definitions(${TARGET_BASE}_static PRIVATE _AMD64_)
  if(OLD_WIN)
    target_compile_definitions(${TARGET_BASE} PRIVATE _OLD_WIN)
    target_compile_definitions(${TARGET_BASE}_static PRIVATE _OLD_WIN)
  endif()
endif()

# Link libraries
if(WIN32)
  # Match Makefile LDFLAGS += -lws2_32
  target_link_libraries(${TARGET_BASE} PRIVATE ws2_32)
  if(MSVC)
    # Export all symbols so FFI consumers can resolve functions without __declspec(dllexport)
    set_target_properties(${TARGET_BASE} PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
  endif()
endif()

# Install rules mirror Makefile
include(GNUInstallDirs)
set(INSTALL_LIB_SUBDIR "idris2-${IDRIS2_VERSION}/lib")
set(INSTALL_SUPPORT_C_SUBDIR "idris2-${IDRIS2_VERSION}/support/c")

install(TARGETS ${TARGET_BASE}
  RUNTIME DESTINATION "${INSTALL_LIB_SUBDIR}"
  LIBRARY DESTINATION "${INSTALL_LIB_SUBDIR}"
  ARCHIVE DESTINATION "${INSTALL_LIB_SUBDIR}"
)
install(TARGETS ${TARGET_BASE}_static
  ARCHIVE DESTINATION "${INSTALL_LIB_SUBDIR}"
)

file(GLOB HDRS "*.h")
install(FILES ${HDRS} DESTINATION "${INSTALL_SUPPORT_C_SUBDIR}")

# Group files in IDEs
source_group(TREE ${CMAKE_CURRENT_SOURCE_DIR} FILES ${SRCS} ${HDRS})

# Usage example (PowerShell):
#   cmake -S . -B build -DIDRIS2_VERSION=0.7.0
#   cmake --build build --config Release
#   cmake --install build --config Release --prefix "C:/path/to/prefix"
