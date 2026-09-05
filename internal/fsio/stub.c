#include <errno.h>
#include <moonbit.h>
#include <stdio.h>

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
