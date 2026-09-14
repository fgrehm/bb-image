/* Log the fontconfig bookkeeping writes a sandbox would block, without strace.
 *
 * Usage: FCLOG=/tmp/fc.log LD_PRELOAD=/tmp/fcrun/fcshim.so <program>
 *
 * Interposes chmod, unlink, unlinkat and openat, and records the path of every
 * call that is not under XDG_CACHE_HOME. openat is the noisy one (every file
 * open in every process lands there), so it is filtered to paths that look like
 * fontconfig cache or uuid bookkeeping.
 *
 * The log is written with raw syscalls so that note() can never re-enter the
 * interposed functions.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static int logfd = -2;

static void note(const char *kind, const char *path) {
  if (logfd == -2) {
    const char *p = getenv("FCLOG");
    logfd = p ? syscall(SYS_openat, AT_FDCWD, p, O_WRONLY | O_APPEND | O_CREAT, 0644) : -1;
  }
  if (logfd < 0 || !path) return;
  char line[4096];
  int n = 0;
  for (const char *k = kind; *k && n < 4000; k++) line[n++] = *k;
  line[n++] = ' ';
  for (const char *p = path; *p && n < 4080; p++) line[n++] = *p;
  line[n++] = '\n';
  syscall(SYS_write, logfd, line, n);
}

/* Only the paths this exercise is about, so the log stays readable. */
static int interested(const char *path) {
  if (!path) return 0;
  if (strstr(path, ".uuid")) return 1;
  if (strstr(path, "fontconfig")) return 1;
  return 0;
}

typedef int (*chmod_t)(const char *, mode_t);
typedef int (*unlink_t)(const char *);
typedef int (*unlinkat_t)(int, const char *, int);
typedef int (*openat_t)(int, const char *, int, ...);

int chmod(const char *path, mode_t mode) {
  static chmod_t real;
  if (!real) real = (chmod_t)dlsym(RTLD_NEXT, "chmod");
  if (interested(path)) note("chmod", path);
  return real(path, mode);
}

int unlink(const char *path) {
  static unlink_t real;
  if (!real) real = (unlink_t)dlsym(RTLD_NEXT, "unlink");
  if (interested(path)) note("unlink", path);
  return real(path);
}

int unlinkat(int dirfd, const char *path, int flags) {
  static unlinkat_t real;
  if (!real) real = (unlinkat_t)dlsym(RTLD_NEXT, "unlinkat");
  if (interested(path)) note("unlinkat", path);
  return real(dirfd, path, flags);
}

int openat(int dirfd, const char *path, int flags, ...) {
  static openat_t real;
  if (!real) real = (openat_t)dlsym(RTLD_NEXT, "openat");
  mode_t mode = 0;
  if (flags & O_CREAT) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, mode_t);
    va_end(ap);
  }
  if ((flags & O_CREAT) && interested(path)) note("openat(O_CREAT)", path);
  return real(dirfd, path, flags, mode);
}
