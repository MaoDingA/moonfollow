///|
/// Which foot produced a step.

///|
pub(all) enum FootSide {
  Left
  Right
} derive(Debug, Eq, ToJson)

///|
/// One detected footstep landing.

///|
pub(all) struct StepEvent {
  frame : Int // frame index of the landing
  time : Double // timestamp in seconds
  foot : FootSide
  strength : Double // landing prominence mapped to [0, 1]
} derive(Debug, Eq, ToJson)

///|
/// Detect footstep landings from a foot track.
///
/// Image y grows downward, so a foot on the ground is a local *maximum* of y.
/// For each foot independently:
///
/// 1. frames with visibility below `min_visibility` are ignored;
/// 2. a frame is a candidate when y rises into it and nothing higher
///    follows within `window` frames: a landing is the start of the ground
///    plateau (the foot rests there for several frames), while quantised
///    steps on a rising edge always have higher frames ahead (the first and
///    last frame of the track can never be a landing);
/// 3. the candidate's prominence (peak y minus the minimum over the
///    +-`window` visible neighbourhood) must reach `min_prominence`;
/// 4. candidates closer than `min_interval_s` on the same foot are
///    debounced, keeping the stronger one;
/// 5. prominence is mapped to `strength` in [0, 1] against `full_stride`
///    (the y swing of a full stride in normalised units).
pub fn detect(
  track : @track.FootTrack,
  min_visibility? : Double = 0.5,
  window? : Int = 0,
  min_prominence? : Double = 0.02,
  min_interval_s? : Double = 0.2,
  full_stride? : Double = 0.1,
) -> Array[StepEvent] {
  // Default window: a quarter stride at the minimum plausible cadence
  // (2 steps/s on one foot), clamped to [2, 8] frames.
  let w = if window > 0 {
    window
  } else {
    let estimated = (track.fps * 0.25).round().to_int()
    if estimated < 2 {
      2
    } else if estimated > 8 {
      8
    } else {
      estimated
    }
  }
  let left = detect_side(
    track,
    Left,
    min_visibility,
    w,
    min_prominence,
    min_interval_s,
    full_stride,
  )
  let right = detect_side(
    track,
    Right,
    min_visibility,
    w,
    min_prominence,
    min_interval_s,
    full_stride,
  )
  let events : Array[StepEvent] = []
  for event in left {
    events.push(event)
  }
  for event in right {
    events.push(event)
  }
  events.sort_by((a, b) => a.time.compare(b.time))
  events
}

///|
fn detect_side(
  track : @track.FootTrack,
  foot : FootSide,
  min_visibility : Double,
  w : Int,
  min_prominence : Double,
  min_interval_s : Double,
  full_stride : Double,
) -> Array[StepEvent] {
  let frames = track.frames
  let ys : Array[Double?] = []
  for frame in frames {
    let p = if foot is Left { frame.left } else { frame.right }
    if p.v >= min_visibility {
      ys.push(Some(p.y))
    } else {
      ys.push(None)
    }
  }
  let n = ys.length()
  // candidates: strict local maxima confirmed by both adjacent visible frames
  let candidates : Array[StepEvent] = []
  for i in 1..<(n - 1) {
    guard ys[i] is Some(peak) else { continue }
    guard ys[i - 1] is Some(before) && before < peak else { continue }
    let look_end = if i + w < n - 1 { i + w } else { n - 1 }
    let mut rising_ahead = false
    for j in (i + 1)..<=look_end {
      guard ys[j] is Some(y) && y > peak else { continue }
      rising_ahead = true
      break
    }
    guard !rising_ahead else { continue }
    // prominence against the wider neighbourhood
    let mut neighborhood_min = peak
    for j in (i - w)..<=(i + w) {
      if j == i || j < 0 || j >= n {
        continue
      }
      guard ys[j] is Some(y) else { continue }
      if y < neighborhood_min {
        neighborhood_min = y
      }
    }
    let prominence = peak - neighborhood_min
    if prominence >= min_prominence {
      let strength = clamp01(prominence / full_stride)
      candidates.push({ frame: frames[i].i, time: frames[i].t, foot, strength, })
    }
  }
  // debounce: candidates arrive in time order; events closer than
  // min_interval_s collapse into the stronger one
  let kept : Array[StepEvent] = []
  for event in candidates {
    if kept.length() == 0 {
      kept.push(event)
    } else {
      let last = kept[kept.length() - 1]
      if event.time - last.time < min_interval_s {
        if event.strength > last.strength {
          kept[kept.length() - 1] = event
        }
      } else {
        kept.push(event)
      }
    }
  }
  kept
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
