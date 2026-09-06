///|
/// Classical two-foot tracker over downscaled grayscale frames.
///
/// Method (per frame):
/// 1. the background is a per-pixel temporal *minimum* that creeps slowly
///    upward (`bg = min(pixel, bg + lift)`), so a foot dwelling on the
///    ground at landing never pollutes the background model (the classic
///    failure of running-average backgrounds, which absorb whatever moves
///    slowly);
/// 2. the foreground is the subject differing from the background by more
///    than `threshold` in one direction: brighter subjects use a temporal
///    minimum background creeping upward, darker subjects a temporal
///    maximum creeping downward (mirror images of each other);
/// 3. the person is the bounding box of foreground row/column histograms;
/// 4. the torso is the active column range in the upper half of the box,
///    which stays stable while legs swing, cross, or hide each other;
/// 5. in the lower 60% of the box, foreground columns are clustered into
///    blobs; up to the two lowest blobs inside the torso range are the feet
///    (a blob away from the torso is scenery, not a foot);
/// 6. visibility is the foreground support around the foot, so occluded or
///    merged feet report low confidence and get gated downstream.
///
/// `person_height` exposes the last person box height so callers can pick a
/// resolution where the person spans enough pixels for feet to swing visibly.

///|
pub(all) struct FeetDetector {
  width : Int
  height : Int
  dark : Bool // true: subject darker than background
  bg : FixedArray[Double]
  mut frames_seen : Int
  mut last_person_height : Int
  mut last_left_x : Double // last known foot positions, for identity
  mut last_right_x : Double
}

///|
pub fn FeetDetector::new(
  width : Int,
  height : Int,
  dark? : Bool = false,
) -> FeetDetector {
  {
    width,
    height,
    dark,
    bg: FixedArray::make(width * height, if dark { 0.0 } else { 255.0 }),
    frames_seen: 0,
    last_person_height: 0,
    last_left_x: -1.0,
    last_right_x: -1.0,
  }
}

///|
/// Foreground difference in the active polarity.

///|
fn FeetDetector::fg_diff(
  self : FeetDetector,
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
/// One step of the background model towards the current pixel.

///|
fn FeetDetector::bg_step(
  self : FeetDetector,
  v : Double,
  bg : Double,
) -> Double {
  let lift = 0.15
  if self.dark {
    // temporal maximum creeping downward
    if bg - lift > v {
      bg - lift
    } else {
      v
    }
    // temporal minimum creeping upward
  } else if bg + lift < v {
    bg + lift
  } else {
    v
  }
}

///|
pub fn FeetDetector::person_height(self : FeetDetector) -> Int {
  self.last_person_height
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
    return (invisible, invisible)
  }
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
  let person_h = ymax - ymin + 1
  self.last_person_height = person_h
  // torso column range: active columns in the upper half of the box
  let torso_bottom = ymin + person_h / 2
  let mut torso_xmin = -1
  let mut torso_xmax = -1
  for x in xmin..<=xmax {
    let mut count = 0
    for y in ymin..<=torso_bottom {
      let v = frame[y * w + x].to_int().to_double()
      if self.fg_diff(v, self.bg[y * w + x]) > threshold {
        count = count + 1
      }
    }
    if count >= 2 {
      if torso_xmin < 0 {
        torso_xmin = x
      }
      torso_xmax = x
    }
  }
  if torso_xmin < 0 {
    return (invisible, invisible)
  }
  // dark subjects drag their cast shadow into the foreground; the shadow is
  // considerably fainter than the subject itself, so feet blobs use a much
  // stricter threshold to stay on the body
  let foot_threshold = if self.dark { threshold * 2.2 } else { threshold }
  // foot blob search region: everything below one box height above ymin. The
  // swing foot rises to mid-box, and when a static body is absorbed into the
  // background the box shrinks to the legs, so the search must extend a full
  // box height above ymin or the top of the swing turns invisible; the rows
  // up there are foreground-limited anyway (absorbed body = no fg)
  let region_top = if ymin - person_h > 0 { ymin - person_h } else { 0 }
  let cols = FixedArray::make(w, 0)
  for y in region_top..<=ymax {
    for x in torso_xmin..<=torso_xmax {
      let i = y * w + x
      let v = frame[i].to_int().to_double()
      if self.fg_diff(v, self.bg[i]) > foot_threshold {
        cols[x] = cols[x] + 1
      }
    }
  }
  let x_lo = if torso_xmin - 2 > 0 { torso_xmin - 2 } else { 0 }
  let x_hi = if torso_xmax + 2 < w - 1 { torso_xmax + 2 } else { w - 1 }
  // blobs = runs of active columns separated by gaps >= 3
  let blobs : Array[(Int, Int)] = [] // (x_from, x_to)
  let mut run_start = -1
  let mut last_active = -1
  let mut gap = 99
  for x in x_lo..<=x_hi {
    if cols[x] >= 2 {
      if run_start < 0 {
        run_start = x
        gap = 0
      } else if gap > 0 {
        if gap >= 3 {
          blobs.push((run_start, last_active))
          run_start = x
        }
        gap = 0
      }
      last_active = x
    } else if run_start >= 0 {
      gap = gap + 1
    }
  }
  if run_start >= 0 {
    blobs.push((run_start, last_active))
  }
  if blobs.length() == 0 {
    return (invisible, invisible)
  }
  // rank blobs by their foot height (lower = more foot-like); keep two
  let feet : Array[@track.KeyPoint] = []
  for blob in blobs {
    let (x_from, x_to) = blob
    feet.push(
      foot_in_blob(
        self,
        frame,
        region_top,
        ymax,
        x_from,
        x_to + 1,
        foot_threshold,
      ),
    )
  }
  feet.sort_by((a, b) => b.y.compare(a.y)) // lowest first
  if feet[0].v == 0.0 {
    return (invisible, invisible)
  }
  let first = feet[0]
  let second = if feet.length() > 1 && feet[1].v > 0.0 {
    feet[1]
  } else {
    invisible
  }
  // identity: name the two feet by continuity with the last known positions
  name_feet(self, first, second)
}

///|
/// Assign left/right by continuity with the previous frame's feet so a
/// single visible blob keeps its identity while it walks across.

///|
fn name_feet(
  det : FeetDetector,
  a : @track.KeyPoint,
  b : @track.KeyPoint,
) -> (@track.KeyPoint, @track.KeyPoint) {
  if b.v == 0.0 {
    // one foot: closer to last left or last right keeps its name. Without
    // anchors nothing anchors identity yet: emit the foot in the left slot
    // without recording an anchor, so a guessed name can never flip against
    // the first real two-foot frame (left = smaller x there)
    if det.last_left_x < 0.0 && det.last_right_x < 0.0 {
      return (a, invisible)
    }
    let d_left = if det.last_left_x >= 0.0 {
      (a.x - det.last_left_x).abs()
    } else {
      2.0
    }
    let d_right = if det.last_right_x >= 0.0 {
      (a.x - det.last_right_x).abs()
    } else {
      2.0
    }
    if d_left <= d_right {
      det.last_left_x = a.x
      return (a, invisible)
    }
    det.last_right_x = a.x
    return (invisible, a)
  }
  let (lo, hi) = if a.x <= b.x { (a, b) } else { (b, a) }
  det.last_left_x = lo.x
  det.last_right_x = hi.x
  (lo, hi)
}

///|
/// Lowest foreground position inside one blob's column range.

///|
fn foot_in_blob(
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
      if det.fg_diff(v, det.bg[i]) > threshold {
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
  let blob_width = x_to - x_from
  // visibility: foreground support in the rows right above the foot
  let window_top = if foot_y - 5 > box_top { foot_y - 5 } else { box_top }
  let mut support = 0
  let mut row = foot_y
  while row >= window_top {
    support = support + row_counts[row]
    row = row - 1
  }
  let density = support.to_double() / (blob_width * 6).to_double()
  {
    x: x / w.to_double(),
    y: foot_y.to_double() / det.height.to_double(),
    v: clamp01(density * 1.5),
  }
}
