#pragma once

#include <stdnoreturn.h>

// Attribute macro for printf-like format checking where supported
#if defined(__clang__) || defined(__GNUC__)
#define IDRIS2_PRINTF_ATTR __attribute__((format(printf, 4, 5)))
#else
#define IDRIS2_PRINTF_ATTR
#endif

// Utilities used by FFI code.

// Crash is the condition is false.
#define IDRIS2_VERIFY(cond, ...)                                               \
  do {                                                                         \
    if (!(cond)) {                                                             \
      idris2_verify_failed(__FILE__, __LINE__, #cond, __VA_ARGS__);            \
    }                                                                          \
  } while (0)

// Used by `IDRIS2_VERIFY`, do not use directly.
noreturn void idris2_verify_failed(const char *file, int line, const char *cond,
                   const char *fmt, ...) IDRIS2_PRINTF_ATTR;
