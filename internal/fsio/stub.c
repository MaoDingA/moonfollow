#include <errno.h>
#include <moonbit.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

// Read a whole file. Returns 0 on success (content in *out), errno on failure.
MOONBIT_FFI_EXPORT
int32_t mf_read_file(const void *path, moonbit_bytes_t *out) {
  FILE *f = fopen((const char *)path, "rb");
  if (f == NULL) {
    return errno;
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    int32_t e = errno;
    fclose(f);
    return e;
  }
  long size = ftell(f);
  if (size < 0) {
    int32_t e = errno;
    fclose(f);
    return e;
  }
  rewind(f);
  moonbit_bytes_t buf = moonbit_make_bytes((int32_t)size, 0);
  if (size > 0 && fread(buf, 1, (size_t)size, f) != (size_t)size) {
    int32_t e = errno != 0 ? errno : EIO;
    fclose(f);
    return e;
  }
  fclose(f);
  *out = buf;
  return 0;
}

// Write a whole file. Returns 0 on success, errno on failure.
MOONBIT_FFI_EXPORT
int32_t mf_write_file(const void *path, moonbit_bytes_t data) {
  FILE *f = fopen((const char *)path, "wb");
  if (f == NULL) {
    return errno;
  }
  int32_t len = Moonbit_array_length(data);
  if (len > 0 && fwrite(data, 1, (size_t)len, f) != (size_t)len) {
    int32_t e = errno != 0 ? errno : EIO;
    fclose(f);
    return e;
  }
  fclose(f);
  return 0;
}

// ---- child process pipes ------------------------------------------------

#define MF_MAX_PROCS 16
static struct {
  pid_t pid;
  int fd;
} mf_procs[MF_MAX_PROCS];

// Spawn a program with stdout piped to us. `argv_blob` is a sequence of
// NUL-separated UTF-8 arguments (the runtime terminates Bytes with NUL).
// Returns a handle >= 0, or -errno.
MOONBIT_FFI_EXPORT
int32_t mf_spawn(const void *argv_blob) {
  char *argv[256];
  int argc = 0;
  const uint8_t *p = (const uint8_t *)argv_blob;
  const uint8_t *end = p + Moonbit_array_length(argv_blob);
  while (p < end && argc < 255) {
    argv[argc++] = (char *)p;
    while (p < end && *p != 0) {
      p++;
    }
    p++; // skip the NUL
  }
  argv[argc] = NULL;
  if (argc == 0) {
    return -EINVAL;
  }
  int fds[2];
  if (pipe(fds) != 0) {
    return -errno;
  }
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
  posix_spawn_file_actions_addclose(&actions, fds[0]);
  pid_t pid;
  if (posix_spawnp(&pid, argv[0], &actions, NULL, argv, environ) != 0) {
    int32_t e = errno;
    close(fds[0]);
    close(fds[1]);
    posix_spawn_file_actions_destroy(&actions);
    return -e;
  }
  posix_spawn_file_actions_destroy(&actions);
  close(fds[1]);
  for (int i = 0; i < MF_MAX_PROCS; i++) {
    if (mf_procs[i].pid == 0) {
      mf_procs[i].pid = pid;
      mf_procs[i].fd = fds[0];
      return i;
    }
  }
  close(fds[0]);
  kill(pid, SIGKILL);
  waitpid(pid, NULL, 0);
  return -EMFILE;
}

// Read one chunk (<= 1 MiB) from a spawned process into a fresh Bytes.
// Empty bytes = EOF. Read errors are surfaced as EOF; check mf_proc_close.
MOONBIT_FFI_EXPORT
moonbit_bytes_t mf_proc_read(int32_t handle) {
  static uint8_t chunk[1024 * 1024];
  if (handle < 0 || handle >= MF_MAX_PROCS || mf_procs[handle].pid == 0) {
    return moonbit_make_bytes(0, 0);
  }
  ssize_t n = read(mf_procs[handle].fd, chunk, sizeof(chunk));
  if (n <= 0) {
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  memcpy(out, chunk, (size_t)n);
  return out;
}

// Close the pipe and reap the child. Returns the exit status, or -1.
MOONBIT_FFI_EXPORT
int32_t mf_proc_close(int32_t handle) {
  if (handle < 0 || handle >= MF_MAX_PROCS || mf_procs[handle].pid == 0) {
    return -1;
  }
  close(mf_procs[handle].fd);
  int status = 0;
  waitpid(mf_procs[handle].pid, &status, 0);
  mf_procs[handle].pid = 0;
  mf_procs[handle].fd = -1;
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  return -1;
}
