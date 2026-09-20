///|
#borrow(text)
extern "c" fn eprint_raw(text : Bytes) -> Unit = "mf_eprint"

///|
extern "c" fn exit_raw(code : Int) -> Unit = "mf_exit"

///|
/// Write `text` (UTF-8) to standard error, unbuffered. Unlike `println`
/// this reaches the console even when stdout is piped.

///|
pub fn eprint(text : String) -> Unit {
  eprint_raw(@utf8.encode(text))
}

///|
/// Terminate the process immediately with exit status `code` (0 = success).

///|
pub fn exit(code : Int) -> Unit {
  exit_raw(code)
}
