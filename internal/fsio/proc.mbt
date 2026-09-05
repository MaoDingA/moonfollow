///|
/// NUL-separated UTF-8 argument blob for mf_spawn (the runtime appends the
/// final terminating NUL).

///|
fn encode_argv(args : Array[String]) -> Bytes {
  let buf = Buffer::Buffer()
  for i, arg in args {
    if i > 0 {
      buf.write_byte(b'\x00')
    }
    buf.write_bytes(@utf8.encode(arg))
  }
  buf.to_bytes()
}

///|
#borrow(argv_blob)
extern "c" fn proc_spawn(argv_blob : Bytes) -> Int = "mf_spawn"

///|
extern "c" fn proc_read_chunk(handle : Int) -> Bytes = "mf_proc_read"

///|
extern "c" fn proc_close(handle : Int) -> Int = "mf_proc_close"

///|
/// A child process with its stdout piped back to us.
///
/// Errors of the child itself are surfaced by `finish`, which returns the
/// child's exit status once its output is exhausted.

///|
pub struct Proc {
  handle : Int
  program : String
}

///|
/// Spawn `args` (argv[0] is the program, resolved through PATH) and pipe its
/// stdout. Read with `read_chunk` until it returns an empty chunk, then call
/// `finish`.

///|
pub fn spawn(args : Array[String]) -> Proc raise FsError {
  let handle = proc_spawn(encode_argv(args))
  if handle < 0 {
    raise FsError::SpawnFailed(program=args[0], errno=0 - handle)
  }
  { handle, program: args[0], }
}

///|
/// Read the next chunk of stdout; empty bytes mean EOF.

///|
pub fn Proc::read_chunk(self : Proc) -> Bytes {
  proc_read_chunk(self.handle)
}

///|
/// Close the pipe and return the child's exit status (0 = success).

///|
pub fn Proc::finish(self : Proc) -> Int {
  proc_close(self.handle)
}
