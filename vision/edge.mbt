///|
/// Profile-view leading-edge tracker.
///
/// In profile walking the feet overlap horizontally and the ground line is
/// flat, so the y-oscillation signal does not exist. The landing signature
/// is instead the person's *leading x edge* in the bottom region: it
/// advances while the leading foot swings, then dwells while that foot is
/// planted -- a landing is the start of a dwell, exactly the plateau-start
/// rule the steps engine already applies to y series.
///
/// The walking direction locks after the first second from the edge drift,
/// so left-to-right and right-to-left walks both track the leading (not
/// trailing) edge.

///|
pub(all) struct EdgeDetector {
  width : Int
  height : Int
  dark : Bool
  bg : FixedArray[Double]
  mut frames_seen : Int
  mut direction : Int // 0 unknown yet, +1 moving right, -1 moving left
  mut early_sum : Double // leading-edge x accumulator over the first second
  mut early_n : Int
  mut late_sum : Double
  mut late_n : Int
}

///|
pub fn EdgeDetector::new(
  width : Int,
  height : Int,
  dark? : Bool = false,
) -> EdgeDetector {
  {
    width,
    height,
    dark,
    bg: FixedArray::make(width * height, if dark { 0.0 } else { 255.0 }),
    frames_seen: 0,
    direction: 0,
    early_sum: 0.0,
    early_n: 0,
    late_sum: 0.0,
    late_n: 0,
  }
}

///|
fn EdgeDetector::fg_diff(
  self : EdgeDetector,
  v : Double,
  bg : Double,
) -> Double {
  if self.dark {
    bg - v
  } else {
    v - bg
  }
}

///|
fn EdgeDetector::bg_step(
  self : EdgeDetector,
  v : Double,
  bg : Double,
) -> Double {
  let lift = 0.15
  if self.dark {
    if bg - lift > v {
      bg - lift
    } else {
      v
    }
  } else if bg + lift < v {
    bg + lift
  } else {
    v
  }
}

///|
/// Process one gray frame; returns the normalized leading-edge x with
/// presence 1.0, or a missing sample (v 0.0) when no person is found.
/// `Some(x)` samples drive the direction lock; absences do not.

///|
pub fn EdgeDetector::process_frame(
  self : EdgeDetector,
  frame : Bytes,
) -> Double? {
  let w = self.width
  let h = self.height
  let threshold = 18.0
  let warmup = 8
  if self.frames_seen < warmup {
    for i in 0..<(w * h) {
      let v = frame[i].to_int().to_double()
      let update = if self.dark { v > self.bg[i] } else { v < self.bg[i] }
      if update {
        self.bg[i] = v
      }
    }
    self.frames_seen = self.frames_seen + 1
    return None
  }
  let row_counts = FixedArray::make(h, 0)
  let col_counts = FixedArray::make(w, 0)
  let mut total_fg = 0
  for y in 0..<h {
    for x in 0..<w {
      let i = y * w + x
      let v = frame[i].to_int().to_double()
      let bg = self.bg_step(v, self.bg[i])
      self.bg[i] = bg
      if self.fg_diff(v, bg) > threshold {
        row_counts[y] = row_counts[y] + 1
        col_counts[x] = col_counts[x] + 1
        total_fg = total_fg + 1
      }
    }
  }
  let min_person_pixels = if w * h / 400 > 20 { w * h / 400 } else { 20 }
  if total_fg < min_person_pixels {
    return None
  }
  let min_row_pixels = if w / 25 > 2 { w / 25 } else { 2 }
  let mut ymin = -1
  let mut ymax = -1
  for y in 0..<h {
    if row_counts[y] >= min_row_pixels {
      if ymin < 0 {
        ymin = y
      }
      ymax = y
    }
  }
  if ymin < 0 {
    return None
  }
  let person_h = ymax - ymin + 1
  // leading edge: the extreme foreground column in the bottom 35% of the
  // person box (the planted/swinging foot region), extremity in the locked
  // walking direction; unknown direction tracks the rightmost edge
  let region_top = if ymax - person_h * 7 / 20 > ymin {
    ymax - person_h * 7 / 20
  } else {
    ymin
  }
  let min_col_pixels = if h / 40 > 2 { h / 40 } else { 2 }
  let mut edge = -1
  if self.direction >= 0 {
    // rightmost: scan columns right to left, first with enough pixels wins
    let mut x = w - 1
    while x >= 0 {
      let mut count = 0
      for y in region_top..<=ymax {
        let i = y * w + x
        let v = frame[i].to_int().to_double()
        if self.fg_diff(v, self.bg[i]) > threshold {
          count = count + 1
        }
      }
      if count >= min_col_pixels {
        edge = x
        break
      }
      x = x - 1
    }
  } else {
    let mut x = 0
    while x < w {
      let mut count = 0
      for y in region_top..<=ymax {
        let i = y * w + x
        let v = frame[i].to_int().to_double()
        if self.fg_diff(v, self.bg[i]) > threshold {
          count = count + 1
        }
      }
      if count >= min_col_pixels {
        edge = x
        break
      }
      x = x + 1
    }
  }
  if edge < 0 {
    return None
  }
  let x_norm = edge.to_double() / w.to_double()
  // direction lock from the drift between the first second and everything
  // after it
  if self.early_n < 10 {
    self.early_sum = self.early_sum + x_norm
    self.early_n = self.early_n + 1
  } else {
    self.late_sum = self.late_sum + x_norm
    self.late_n = self.late_n + 1
    // lock fast: before the lock the detector follows the trailing edge in
    // right-to-left walks, and a mixed series ruins the first landings
    if self.direction == 0 && self.late_n >= 10 {
      let drift = self.late_sum / self.late_n.to_double() -
        self.early_sum / self.early_n.to_double()
      if drift > 0.02 {
        self.direction = 1
      } else if drift < -0.02 {
        self.direction = -1
      }
    }
  }
  Some(x_norm)
}
