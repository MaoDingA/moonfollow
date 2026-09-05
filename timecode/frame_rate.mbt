///|
/// Rational frame rate with SMPTE drop-frame bookkeeping.
///
/// `num`/`den` describe the true rate (e.g. 30000/1001 for NTSC video);
/// `nominal` is the integer rate the timecode clock counts (30, 60, ...);
/// `drop` marks drop-frame numbering, where frame numbers 00 and 01 are
/// skipped at the start of every minute except every tenth minute.
pub(all) struct FrameRate {
  num : Int
  den : Int
  nominal : Int
  drop : Bool
  label : String
} derive(Debug, Eq)

///|
/// True frames per second as a floating point value.

///|
pub fn FrameRate::frames_per_second(self : FrameRate) -> Double {
  self.num.to_double() / self.den.to_double()
}

///|
pub fn FrameRate::fps23976() -> FrameRate {
  { num: 24000, den: 1001, nominal: 24, drop: false, label: "23.976", }
}

///|
pub fn FrameRate::fps24() -> FrameRate {
  { num: 24, den: 1, nominal: 24, drop: false, label: "24", }
}

///|
pub fn FrameRate::fps25() -> FrameRate {
  { num: 25, den: 1, nominal: 25, drop: false, label: "25", }
}

///|
pub fn FrameRate::fps2997() -> FrameRate {
  { num: 30000, den: 1001, nominal: 30, drop: true, label: "29.97", }
}

///|
pub fn FrameRate::fps30() -> FrameRate {
  { num: 30, den: 1, nominal: 30, drop: false, label: "30", }
}

///|
pub fn FrameRate::fps50() -> FrameRate {
  { num: 50, den: 1, nominal: 50, drop: false, label: "50", }
}

///|
pub fn FrameRate::fps5994() -> FrameRate {
  { num: 60000, den: 1001, nominal: 60, drop: true, label: "59.94", }
}

///|
pub fn FrameRate::fps60() -> FrameRate {
  { num: 60, den: 1, nominal: 60, drop: false, label: "60", }
}

///|
/// Match a reported fps value (as found in container metadata) against the
/// rates SMPTE timecode supports. Values within 0.012 fps of a known rate are
/// snapped to it; anything else is rejected.

///|
pub fn FrameRate::of_double(fps : Double) -> FrameRate raise TimecodeError {
  let candidates : Array[FrameRate] = [
    FrameRate::fps23976(),
    FrameRate::fps24(),
    FrameRate::fps25(),
    FrameRate::fps2997(),
    FrameRate::fps30(),
    FrameRate::fps50(),
    FrameRate::fps5994(),
    FrameRate::fps60(),
  ]
  for rate in candidates {
    if (fps - rate.frames_per_second()).abs() < 0.012 {
      return rate
    }
  }
  raise TimecodeError::UnsupportedRate(fps~)
}

///|
pub impl Show for FrameRate with fn output(self, logger) {
  logger.write_string("\{self.label} fps")
  if self.drop {
    logger.write_string(" (drop-frame)")
  }
}
