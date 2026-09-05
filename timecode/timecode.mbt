///|
/// A SMPTE timecode: a real frame index at a given frame rate.
///
/// `frames` counts actual frames since 00:00:00:00 (for drop-frame rates this
/// is *not* the number shown on the clock; use `display` / `Show` for the
/// SMPTE string and `frame_index` for the true position).

///|
pub struct Timecode {
  frames : Int
  rate : FrameRate
} derive(Debug, Eq)

///|
/// Build a timecode from a real frame index (must be non-negative).

///|
pub fn Timecode::make(frame_index : Int, rate~ : FrameRate) -> Timecode {
  { frames: frame_index, rate, }
}

///|
/// Convert a timestamp in seconds to the nearest frame.

///|
pub fn Timecode::from_seconds(
  seconds : Double,
  rate~ : FrameRate,
) -> Timecode raise TimecodeError {
  if seconds < 0.0 {
    raise TimecodeError::NegativeTime(seconds~)
  }
  let frames = (seconds * rate.frames_per_second()).round().to_int()
  Timecode::make(frames, rate~)
}

///|
/// Real frame index since 00:00:00:00.

///|
pub fn Timecode::frame_index(self : Timecode) -> Int {
  self.frames
}

///|
/// The frame rate this timecode is expressed at.

///|
pub fn Timecode::rate(self : Timecode) -> FrameRate {
  self.rate
}

///|
/// Exact timestamp in seconds.

///|
pub fn Timecode::seconds(self : Timecode) -> Double {
  self.frames.to_double() *
  self.rate.den.to_double() /
  self.rate.num.to_double()
}

///|
/// Number of frame numbers skipped per non-tenth minute at this rate
/// (2 for nominal 30, 4 for nominal 60, 0 for non-drop).

///|
fn FrameRate::drop_count(self : FrameRate) -> Int {
  if self.drop {
    self.nominal / 15
  } else {
    0
  }
}

///|
/// Real frame index -> nominal-clock display number for drop-frame rates.
/// Non-drop rates use the frame index directly.

///|
fn display_number(real : Int, rate : FrameRate) -> Int {
  if !rate.drop {
    return real
  }
  let drop = rate.drop_count()
  let nominal = rate.nominal
  let frames_per_10min = nominal * 600 - 9 * drop
  let tens = real / frames_per_10min
  let rest = real % frames_per_10min
  if rest > drop {
    real + drop * 9 * tens + drop * ((rest - drop) / (nominal * 60 - drop))
  } else {
    real + drop * 9 * tens
  }
}

///|
/// Nominal-clock display number -> real frame index for drop-frame rates.

///|
fn real_index(display : Int, rate : FrameRate) -> Int {
  if !rate.drop {
    return display
  }
  let drop = rate.drop_count()
  let nominal = rate.nominal
  let tens = display / (nominal * 600)
  let rest = display % (nominal * 600)
  // Each minute boundary inside a 10-minute block (except the block start)
  // has dropped `drop` numbers before any valid shown value in that minute.
  let minutes_passed = rest / (nominal * 60)
  display - drop * (9 * tens + minutes_passed)
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// SMPTE display string, e.g. "01:02:03:24" (non-drop) or "00:01:00;02"
/// (drop-frame uses a semicolon before the frame number).

///|
pub fn Timecode::display(self : Timecode) -> String {
  let n = self.rate.nominal
  let d = display_number(self.frames, self.rate)
  let ff = d % n
  let total_seconds = d / n
  let ss = total_seconds % 60
  let mm = total_seconds / 60 % 60
  let hh = total_seconds / 3600
  let sep = if self.rate.drop { ";" } else { ":" }
  "\{pad2(hh)}:\{pad2(mm)}:\{pad2(ss)}\{sep}\{pad2(ff)}"
}

///|
pub impl Show for Timecode with fn output(self, logger) {
  logger.write_string(self.display())
}

///|
fn parse_part(part : StringView, input~ : String) -> Int raise TimecodeError {
  let value : Int = @strconv.from_str(part) catch {
    _ =>
      raise TimecodeError::InvalidTimecode(
        input~,
        reason="non-numeric field \{part}",
      )
  }
  if value < 0 {
    raise TimecodeError::InvalidTimecode(
      input~,
      reason="negative field \{part}",
    )
  }
  value
}

///|
/// Parse "HH:MM:SS:FF" (non-drop) or "HH:MM:SS;FF" (drop-frame).

///|
pub fn Timecode::parse(
  text : String,
  rate~ : FrameRate,
) -> Timecode raise TimecodeError {
  fn invalid(reason : String) -> Unit raise TimecodeError {
    raise TimecodeError::InvalidTimecode(input=text, reason~)
  }
  let fields : (Int, Int, Int, Int) = match text.split_once(";") {
    Some((head, ff_view)) => {
      if !rate.drop {
        invalid("drop-frame separator ';' used with non-drop rate \{rate}")
      }
      let parts = head.split(":").to_array()
      if parts.length() != 3 {
        invalid("expected HH:MM:SS;FF")
      }
      (
        parse_part(parts[0], input=text),
        parse_part(parts[1], input=text),
        parse_part(parts[2], input=text),
        parse_part(ff_view, input=text),
      )
    }
    None => {
      if rate.drop {
        invalid("drop-frame rate \{rate} requires ';' before the frame number")
      }
      let parts = text.split(":").to_array()
      if parts.length() != 4 {
        invalid("expected HH:MM:SS:FF")
      }
      (
        parse_part(parts[0], input=text),
        parse_part(parts[1], input=text),
        parse_part(parts[2], input=text),
        parse_part(parts[3], input=text),
      )
    }
  }
  let (hh, mm, ss, ff) = fields
  if ff >= rate.nominal {
    invalid("frame number \{ff} out of range for \{rate}")
  }
  if ss >= 60 {
    invalid("seconds \{ss} out of range")
  }
  if mm >= 60 {
    invalid("minutes \{mm} out of range")
  }
  let drop = rate.drop_count()
  if rate.drop && ss == 0 && mm % 10 != 0 && ff < drop {
    invalid(
      "frame numbers 00-0\{drop - 1} are dropped at the start of minute \{mm}",
    )
  }
  let display = (hh * 3600 + mm * 60 + ss) * rate.nominal + ff
  Timecode::make(real_index(display, rate), rate~)
}
