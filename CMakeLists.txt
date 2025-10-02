cmake_minimum_required(VERSION 3.15)

project(Idris2All C CXX)

# Options
set(IDRIS2_VERSION "0.7.0" CACHE STRING "Idris2 version")
set(IDRIS2_CG "racket" CACHE STRING "Idris2 code generator (chez/racket/js/refc)")

# Build C support lib first
add_subdirectory(support/c)

# Helper: PowerShell invocation wrapper
function(add_ps_script_target tgt script)
  if (WIN32)
    add_custom_target(${tgt}
      COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "${script}" ${ARGN}
      WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
      VERBATIM)
  else()
    add_custom_target(${tgt}
      COMMAND ${CMAKE_COMMAND} -E echo "PowerShell required for this target"
      VERBATIM)
  endif()
endfunction()

# Stage 1 (Racket only per Windows-centric flow)
add_ps_script_target(stage1 "${CMAKE_SOURCE_DIR}/bootstrap-stage1-racket.ps1" -Idris2Version "${IDRIS2_VERSION}" -Config "$<CONFIG>")
# Ensure the C support DLL is built before stage1 so Racket FFI can load it
add_dependencies(stage1 idris2_support idris2_support_static)

# Stage 2 (depends on stage1 and C support)
add_ps_script_target(stage2 "${CMAKE_SOURCE_DIR}/bootstrap-stage2.ps1" -Idris2Cg "${IDRIS2_CG}" -Config "$<CONFIG>")
add_dependencies(stage2 stage1 idris2_support idris2_support_static)

# Mirror old Makefile target names for convenience
add_custom_target(bootstrap-racket DEPENDS stage2)

# Aggregate 'all' build
# add_custom_target(all_build DEPENDS stage2)  # Removed to avoid duplicate project names in VS solution

# Custom clean for support/c build directory
add_custom_target(clean-support
  COMMAND ${CMAKE_COMMAND} -E remove_directory "${CMAKE_SOURCE_DIR}/support/c/build"
  COMMAND ${CMAKE_COMMAND} -E remove_directory "${CMAKE_BINARY_DIR}/build"
  COMMAND ${CMAKE_COMMAND} -E remove_directory "${CMAKE_BINARY_DIR}/bootstrap-build"
)

# Install: call Windows helper to place launcher, runtime app, and TTC libs
configure_file(
  "${CMAKE_SOURCE_DIR}/cmake/InstallIdris2.in.cmake"
  "${CMAKE_BINARY_DIR}/InstallIdris2.cmake"
  @ONLY
)
install(SCRIPT "${CMAKE_BINARY_DIR}/InstallIdris2.cmake")
