///|
pub(all) suberror FsError {
  IoFailed(path~ : String, errno~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for FsError with fn output(self, logger) {
  match self {
    IoFailed(path~, errno~) =>
      logger <+ "cannot access \{path} (errno \{errno})"
  }
}
