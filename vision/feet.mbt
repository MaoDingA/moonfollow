///|
/// Classical two-foot tracker over downscaled grayscale frames.
///
/// Method (per frame):
/// 1. the background is a per-pixel temporal *minimum* that creeps slowly
///    upward (`bg = min(pixel, bg + lift)`), so a foot dwelling on the
///    ground at landing never pollutes the background model (the classic
///    failure of running-average backgrounds, which absorb whatever moves
///    slowly);
/// 2. the foreground is "brighter than the background by `threshold`"
///    (a bright subject on a darker scene);
/// 3. the person is the bounding box of foreground row/column histograms;
/// 4. the box is split at its horizontal midpoint, and each side's foot is
///    its lowest foreground row (the lowest point of that foot in the
///    picture);
/// 5. visibility is the foreground support around the foot, so occluded or
///    merged feet report low confidence and get gated downstream.

///|
pub(all) struct FeetDetector {
  width : Int
  height : Int
  bg : FixedArray[Double]
  mut frames_seen : Int
  mut mid_x : Int // smoothed person center column, -1 until first seen
}

///|
pub fn FeetDetector::new(width : Int, height : Int) -> FeetDetector {
  {
    width,
    height,
    bg: FixedArray::make(width * height, 255.0),
    frames_seen: 0,
    mid_x: -1,
  }
}

///|
fn clamp01(x : Double) -> Double {
  if x < 0.0 {
    0.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}

///|
let invisible : @track.KeyPoint = { x: 0.5, y: 1.0, v: 0.0, }

///|
/// Process one gray frame; returns (left foot, right foot).
/// The first `warmup` frames only accumulate the background minimum
/// (a moving subject vacates most pixels during that time).

///|
pub fn FeetDetector::process_frame(
  self : FeetDetector,
  frame : Bytes,
) -> (@track.KeyPoint, @track.KeyPoint) {
  let w = self.width
  let h = self.height
  let threshold = 25.0
  let lift = 0.15 // per-frame upward creep of the background minimum
  let warmup = 8
  if self.frames_seen < warmup {
    for i in 0..<(w * h) {
      let v = frame[i].to_int().to_double()
      if v < self.bg[i] {
        self.bg[i] = v
      }
    }
    self.frames_seen = self.frames_seen + 1
    return (invisible, invisible)
  }
  // pass 1: background minimum + row/column histograms of the foreground
  let row_counts = FixedArray::make(h, 0)
  let col_counts = FixedArray::make(w, 0)
  let mut total_fg = 0
  for y in 0..<h {
    for x in 0..<w {
      let i = y * w + x
      let v = frame[i].to_int().to_double()
      let bg = if self.bg[i] + lift < v { self.bg[i] + lift } else { v }
      self.bg[i] = bg
      if v - bg > threshold {
        row_counts[y] = row_counts[y] + 1
        col_counts[x] = col_counts[x] + 1
        total_fg = total_fg + 1
      }
    }
  }
  let min_person_pixels = if w * h / 400 > 20 { w * h / 400 } else { 20 }
  if total_fg < min_person_pixels {
    return (invisible, invisible)
  }
  // person center from the torso (upper half of the box): legs swinging or
  // hidden must not pull the split point toward one side
  let _ = total_fg

  // person bounding box from histogram thresholds
  let min_row_pixels = if w / 25 > 2 { w / 25 } else { 2 }
  let min_col_pixels = if h / 25 > 2 { h / 25 } else { 2 }
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
    return (invisible, invisible)
  }
  let mut xmin = -1
  let mut xmax = -1
  for x in 0..<w {
    if col_counts[x] >= min_col_pixels {
      if xmin < 0 {
        xmin = x
      }
      xmax = x
    }
  }
  if xmin < 0 {
    return (invisible, invisible)
  }
  // Split the feet by the widest horizontal gap between foreground columns
  // in the bottom third of the person box. A fixed midpoint split cannot
  // survive legs crossing or one leg fully hidden mid-swing.
  let person_h = ymax - ymin + 1
  let region_top = if ymax - person_h / 3 > ymin {
    ymax - person_h / 3
  } else {
    ymin
  }
  let cols = FixedArray::make(w, 0)
  for y in region_top..<=ymax {
    for x in xmin..<=xmax {
      let i = y * w + x
      let v = frame[i].to_int().to_double()
      if v - self.bg[i] > threshold {
        cols[x] = cols[x] + 1
      }
    }
  }
  let mut first_active = -1
  let mut last_active = -1
  for x in xmin..<=xmax {
    if cols[x] >= 2 {
      if first_active < 0 {
        first_active = x
      }
      last_active = x
    }
  }
  if first_active < 0 {
    return (invisible, invisible)
  }
  // widest run of inactive columns strictly between the outer active columns
  let mut gap_start = -1
  let mut gap_width = 0
  let mut run_start = -1
  for x in (first_active + 1)..<last_active {
    if cols[x] < 2 {
      if run_start < 0 {
        run_start = x
      }
    } else if run_start >= 0 {
      let width = x - run_start
      if width > gap_width {
        gap_width = width
        gap_start = run_start
      }
      run_start = -1
    }
  }
  if run_start >= 0 {
    let width = last_active - run_start
    if width > gap_width {
      gap_width = width
      gap_start = run_start
    }
  }
  if gap_width >= 2 {
    // two blobs: smaller x is the left foot
    let split = gap_start + gap_width / 2
    let lower = foot_in_side(
      self, frame, ymin, ymax, first_active, split, threshold,
    )
    let upper = foot_in_side(
      self,
      frame,
      ymin,
      ymax,
      split,
      last_active + 1,
      threshold,
    )
    (lower, upper)
  } else {
    // one blob: a single visible foot; name it by the last known center
    let foot = foot_in_side(
      self,
      frame,
      ymin,
      ymax,
      first_active,
      last_active + 1,
      threshold,
    )
    let right_side = foot.x > 0.5
    if right_side {
      (invisible, foot)
    } else {
      (foot, invisible)
    }
  }
}

///|
/// Lowest foreground position inside one horizontal half of the person box.

///|
fn foot_in_side(
  det : FeetDetector,
  frame : Bytes,
  box_top : Int,
  box_bottom : Int,
  x_from : Int,
  x_to : Int,
  threshold : Double,
) -> @track.KeyPoint {
  let w = det.width
  let row_counts = FixedArray::make(det.height, 0)
  // scan from the ground upward; keep the first row with enough pixels
  let mut foot_y = -1
  let mut foot_x_sum = 0.0
  let mut foot_x_count = 0
  let mut y = box_bottom
  while y >= box_top {
    let mut count = 0
    let mut x_sum = 0.0
    for x in x_from..<x_to {
      let i = y * w + x
      let v = frame[i].to_int().to_double()
      if (v - det.bg[i]).abs() > threshold {
        count = count + 1
        x_sum = x_sum + x.to_double()
      }
    }
    row_counts[y] = count
    if count >= 2 && foot_y < 0 {
      foot_y = y
      foot_x_sum = x_sum
      foot_x_count = count
    }
    y = y - 1
  }
  if foot_y < 0 {
    return invisible
  }
  let x = foot_x_sum / foot_x_count.to_double()
  let side_width = x_to - x_from
  // visibility: foreground support in the rows right above the foot
  let window_top = if foot_y - 5 > box_top { foot_y - 5 } else { box_top }
  let mut support = 0
  let mut row = foot_y
  while row >= window_top {
    support = support + row_counts[row]
    row = row - 1
  }
  let density = support.to_double() / (side_width * 6).to_double()
  {
    x: x / w.to_double(),
    y: foot_y.to_double() / det.height.to_double(),
    v: clamp01(density * 1.5),
  }
}
