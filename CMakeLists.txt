cmake_minimum_required(VERSION 3.15)

project(Idris2All C CXX)

# Options
set(IDRIS2_VERSION "0.7.0" CACHE STRING "Idris2 version")
set(IDRIS2_CG "racket" CACHE STRING "Idris2 code generator (chez/racket/js/refc)")

# Build C support lib first
add_subdirectory(support/c)

# Helper to touch a stamp file
set(STAGE_DIR "${CMAKE_BINARY_DIR}")
set(STAGE1_STAMP "${STAGE_DIR}/.stage1-${CMAKE_CFG_INTDIR}.stamp")
set(STAGE2_STAMP "${STAGE_DIR}/.stage2-${CMAKE_CFG_INTDIR}.stamp")
set(STAGE2_PART1_STAMP "${STAGE_DIR}/.stage2-part1-${CMAKE_CFG_INTDIR}.stamp")

# Stage 1 (Racket) -> stamp
add_custom_command(
  OUTPUT ${STAGE1_STAMP}
  COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass
          -File "${CMAKE_SOURCE_DIR}/bootstrap-stage1-racket.ps1"
          -Idris2Version "${IDRIS2_VERSION}" -Config $<CONFIG>
  COMMAND ${CMAKE_COMMAND} -E touch ${STAGE1_STAMP}
  DEPENDS idris2_support idris2_support_static
          "${CMAKE_SOURCE_DIR}/bootstrap-stage1-racket.ps1"
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  VERBATIM
)
add_custom_target(stage1 DEPENDS ${STAGE1_STAMP})

# Stage 2 part1 -> stamp (generates idris2.ps1 and idris2 app, but skips extra libs)
add_custom_command(
  OUTPUT ${STAGE2_PART1_STAMP}
  COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass
    -File "${CMAKE_SOURCE_DIR}/bootstrap-stage2-part1.ps1"
    -Idris2Cg "${IDRIS2_CG}" -Config $<CONFIG>
  COMMAND ${CMAKE_COMMAND} -E touch ${STAGE2_PART1_STAMP}
  DEPENDS ${STAGE1_STAMP}
    idris2_support idris2_support_static
    "${CMAKE_SOURCE_DIR}/bootstrap-stage2-part1.ps1"
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  VERBATIM
)
add_custom_target(stage2-part1 DEPENDS ${STAGE2_PART1_STAMP})

# Stage 2 -> stamp (depends on stage1 stamp and support libs)
add_custom_command(
  OUTPUT ${STAGE2_STAMP}
  COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass
          -File "${CMAKE_SOURCE_DIR}/bootstrap-stage2.ps1"
          -Idris2Cg "${IDRIS2_CG}" -Config $<CONFIG>
  COMMAND ${CMAKE_COMMAND} -E touch ${STAGE2_STAMP}
  DEPENDS ${STAGE1_STAMP}
          idris2_support idris2_support_static
          "${CMAKE_SOURCE_DIR}/bootstrap-stage2.ps1"
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  VERBATIM
)
add_custom_target(stage2 DEPENDS ${STAGE2_STAMP})

# Convenience target
add_custom_target(bootstrap-racket DEPENDS stage2)
add_custom_target(bootstrap-racket-part1 DEPENDS stage2-part1)

# Custom clean helpers
add_custom_target(clean-support
  COMMAND ${CMAKE_COMMAND} -E rm -f "${STAGE1_STAMP}" "${STAGE2_STAMP}"
  COMMAND ${CMAKE_COMMAND} -E remove_directory "${CMAKE_SOURCE_DIR}/support/c/build"
  COMMAND ${CMAKE_COMMAND} -E remove_directory "${CMAKE_BINARY_DIR}/build"
  COMMAND ${CMAKE_COMMAND} -E remove_directory "${CMAKE_BINARY_DIR}/bootstrap-build"
)

# Test target: won’t retrigger stage2 unless stamps/scripts changed
if (WIN32)
  add_custom_target(test
    COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_SOURCE_DIR}/tools/run-tests.ps1" -Config $<CONFIG>
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    VERBATIM
  )
  # Run only the fundamental language feature tests (idris2/basic) using the
  # substring filter supported by the test harness' --only flag.
  add_custom_target(test-basic
    COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_SOURCE_DIR}/tools/run-tests.ps1" -Config $<CONFIG> -Only idris2/basic
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    VERBATIM
  )
  # Windows-only: example PowerShell test runner for a single test folder
  add_custom_target(test-basic001
    COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_SOURCE_DIR}/tests/idris2/basic/basic001/run.ps1"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    VERBATIM
  )
endif()

# Install script (unchanged)
configure_file(
  "${CMAKE_SOURCE_DIR}/cmake/InstallIdris2.in.cmake"
  "${CMAKE_BINARY_DIR}/InstallIdris2.cmake"
  @ONLY
)
install(SCRIPT "${CMAKE_BINARY_DIR}/InstallIdris2.cmake")
