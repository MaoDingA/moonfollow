///|
pub(all) suberror TimecodeError {
  UnsupportedRate(fps~ : Double)
  InvalidTimecode(input~ : String, reason~ : String)
  NegativeTime(seconds~ : Double)
} derive(Debug, Eq)

///|
pub impl Show for TimecodeError with fn output(self, logger) {
  match self {
    UnsupportedRate(fps~) =>
      logger <+
        "unsupported frame rate \{fps} (supported: 23.976, 24, 25, 29.97, 30, 50, 59.94, 60)"
    InvalidTimecode(input~, reason~) => logger <+ "\{input}: \{reason}"
    NegativeTime(seconds~) =>
      logger <+ "negative time \{seconds} has no SMPTE timecode"
  }
}
