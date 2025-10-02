#include "idris_directory.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#ifdef _WIN32
#include <direct.h>
#include <windows.h>
#else
#include <dirent.h>
#include <unistd.h>
#endif

#include "idris_util.h"

char *idris2_currentDirectory() {
  char *cwd = malloc(1024); // probably ought to deal with the unlikely event of
                            // this being too small
  IDRIS2_VERIFY(cwd, "malloc failed");
#ifdef _WIN32
  return _getcwd(cwd, 1024);
#else
  return getcwd(cwd, 1024); // Freed by RTS
#endif
}

int idris2_changeDir(char *dir) {
#ifdef _WIN32
  return _chdir(dir);
#else
  return chdir(dir);
#endif
}

static int idris2_ensure_dir_posix(const char *path) {
#ifndef _WIN32
  if (!path || !*path) return -1;

  char *tmp = strdup(path);
  if (!tmp) return -1;

  // Normalize backslashes to forward slashes
  for (char *p = tmp; *p; ++p) if (*p == '\\') *p = '/';

  size_t len = strlen(tmp);
  // Create progressively: a, a/b, a/b/c
  for (size_t i = 1; i <= len; ++i) {
    if (tmp[i] == '/' || tmp[i] == '\0') {
      char saved = tmp[i];
      tmp[i] = '\0';
      if (strlen(tmp) > 0) {
        if (mkdir(tmp, S_IRWXU | S_IRWXG | S_IRWXO) != 0) {
          if (errno != EEXIST) { tmp[i] = saved; free(tmp); return -1; }
        }
      }
      tmp[i] = saved;
    }
  }

  free(tmp);
  return 0;
#else
  // Not used on Windows; see idris2_ensure_dir_win below.
  (void)path;
  return -1;
#endif
}

#ifdef _WIN32
static int utf8_to_wstr(const char *in, wchar_t **out) {
  *out = NULL;
  int n = MultiByteToWideChar(CP_UTF8, 0, in, -1, NULL, 0);
  if (n <= 0) return -1;
  *out = (wchar_t *)malloc(n * sizeof(wchar_t));
  if (!*out) return -1;
  if (MultiByteToWideChar(CP_UTF8, 0, in, -1, *out, n) <= 0) {
    free(*out); *out = NULL; return -1;
  }
  return 0;
}

static void normalize_slashes_w(wchar_t *s) {
  for (wchar_t *p = s; *p; ++p) if (*p == L'/') *p = L'\\';
}

static int make_one_dir_w(const wchar_t *p) {
  if (CreateDirectoryW(p, NULL)) return 0;
  DWORD e = GetLastError();
  if (e == ERROR_ALREADY_EXISTS) return 0;
  return -1;
}

static int idris2_ensure_dir_win(const char *path_utf8) {
  if (!path_utf8 || !*path_utf8) return -1;
  wchar_t *wfull = NULL;
  if (utf8_to_wstr(path_utf8, &wfull) != 0) return -1;
  normalize_slashes_w(wfull);

  size_t i = 0;
  // Handle prefixes: UNC or Drive
  if (wfull[0] == L'\\' && wfull[1] == L'\\') {
    // Skip UNC prefix: \\\\server\\share
    int backslashes = 0;
    for (i = 2; wfull[i]; ++i) {
      if (wfull[i] == L'\\' && ++backslashes == 2) { ++i; break; }
    }
  } else if (wfull[1] == L':' && (wfull[2] == L'\\' || wfull[2] == L'/')) {
    i = 3;
  }

  for (; wfull[i]; ++i) {
    if (wfull[i] == L'\\') {
      wchar_t saved = wfull[i];
      wfull[i] = L'\0';
      if (make_one_dir_w(wfull) != 0) { wfull[i] = saved; free(wfull); return -1; }
      wfull[i] = saved;
      while (wfull[i+1] == L'\\') ++i; // skip repeats
    }
  }
  int rc = make_one_dir_w(wfull);
  free(wfull);
  return rc;
}
#endif

int idris2_createDir(char *dir) {
#ifdef _WIN32
  return idris2_ensure_dir_win(dir);
#else
  return idris2_ensure_dir_posix(dir);
#endif
}

typedef struct {
#ifdef _WIN32
  HANDLE hFind;
  WIN32_FIND_DATAA ffd;
  int first;
  char pattern[MAX_PATH];
#else
  DIR *dirptr;
#endif
} DirInfo;

void *idris2_openDir(char *dir) {
#ifdef _WIN32
  DirInfo *di = malloc(sizeof(DirInfo));
  IDRIS2_VERIFY(di, "malloc failed");
  snprintf(di->pattern, MAX_PATH, "%s\\*", dir);
  // Probe existence: try opening once; if it fails, directory does not exist.
  HANDLE h = FindFirstFileA(di->pattern, &di->ffd);
  if (h == INVALID_HANDLE_VALUE) {
    free(di);
    return NULL;
  }
  // Close the probe handle; nextDirEntry will reopen to enumerate from the start.
  FindClose(h);
  di->hFind = INVALID_HANDLE_VALUE;
  di->first = 1;
  return (void *)di;
#else
  DIR *d = opendir(dir);
  if (d == NULL) {
    return NULL;
  } else {
    DirInfo *di = malloc(sizeof(DirInfo));
    IDRIS2_VERIFY(di, "malloc failed");
    di->dirptr = d;

    return (void *)di;
  }
#endif
}

void idris2_closeDir(void *d) {
  DirInfo *di = (DirInfo *)d;
#ifdef _WIN32
  if (di->hFind != INVALID_HANDLE_VALUE) {
    FindClose(di->hFind);
  }
  free(di);
#else
  IDRIS2_VERIFY(closedir(di->dirptr) == 0, "closedir failed: %s",
                strerror(errno));
  free(di);
#endif
}

int idris2_removeDir(char *path) {
#ifdef _WIN32
  return _rmdir(path);
#else
  return rmdir(path);
#endif
}

char *idris2_nextDirEntry(void *d) {
  DirInfo *di = (DirInfo *)d;
#ifdef _WIN32
  if (di->first) {
    di->first = 0;
    di->hFind = FindFirstFileA(di->pattern, &di->ffd);
    if (di->hFind == INVALID_HANDLE_VALUE) return NULL;
    return di->ffd.cFileName;
  } else {
    if (FindNextFileA(di->hFind, &di->ffd)) {
      return di->ffd.cFileName;
    } else {
      return NULL;
    }
  }
#else
  // `readdir` keeps `errno` unchanged on end of stream
  // so we need to reset `errno` to distinguish between
  // end of stream and failure.
  errno = 0;
  struct dirent *de = readdir(di->dirptr);

  if (de == NULL) {
    return NULL;
  } else {
    return de->d_name;
  }
#endif
}
