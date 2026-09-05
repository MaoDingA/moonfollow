///|
#borrow(path, out)
extern "c" fn read_file_raw(path : Bytes, out : Ref[Bytes]) -> Int = "mf_read_file"

///|
#borrow(path, data)
extern "c" fn write_file_raw(path : Bytes, data : Bytes) -> Int = "mf_write_file"

///|
fn check(path : String, errno : Int) -> Unit raise FsError {
  if errno != 0 {
    raise FsError::IoFailed(path~, errno~)
  }
}

///|
pub fn read_bytes(path : String) -> Bytes raise FsError {
  let out : Ref[Bytes] = Ref::{ val: b"", }
  check(path, read_file_raw(@utf8.encode(path), out))
  out.val
}

///|
pub fn write_bytes(path : String, data : Bytes) -> Unit raise FsError {
  check(path, write_file_raw(@utf8.encode(path), data))
}

///|
pub fn read_string(path : String) -> String raise FsError {
  @utf8.decode_lossy(read_bytes(path))
}

///|
pub fn write_string(path : String, text : String) -> Unit raise FsError {
  write_bytes(path, @utf8.encode(text))
}
