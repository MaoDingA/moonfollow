///|
pub(all) suberror TrackError {
  BadJson(detail~ : String)
  InvalidTrack(detail~ : String)
} derive(Debug, Eq)

///|
pub impl Show for TrackError with fn output(self, logger) {
  match self {
    BadJson(detail~) => logger <+ "invalid foottrack JSON: \{detail}"
    InvalidTrack(detail~) => logger <+ "invalid foottrack data: \{detail}"
  }
}
