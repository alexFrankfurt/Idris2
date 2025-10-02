# Install Idris2 app and libraries via PowerShell helper
message(STATUS "Installing Idris2 app and libraries via PowerShell helper...")

if(WIN32)
  # Compose install prefix with DESTDIR support
  set(_prefix "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}")
  set(_script "${CMAKE_SOURCE_DIR}/tools/install-windows.ps1")

  if(NOT EXISTS "${_script}")
    message(FATAL_ERROR "Install script not found: ${_script}")
  endif()

  execute_process(
    COMMAND pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "${_script}" -Prefix "${_prefix}" -Version "${IDRIS2_VERSION}"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    RESULT_VARIABLE _res
  )

  if(NOT _res EQUAL 0)
    message(FATAL_ERROR "Idris2 install script failed with code ${_res}")
  endif()
else()
  message(STATUS "Skipping Idris2 PowerShell install on non-Windows host")
endif()
