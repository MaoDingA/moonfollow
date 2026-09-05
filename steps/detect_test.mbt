///|
/// Synthetic walk: feet swing as triangular waves, left peaks at
/// t = 0.32 + k s (frame 8 + 25k), right at t = 0.84 + k s (frame 21 + 25k).

///|
fn tri_walk(n : Int, amp : Double, vis : Double) -> @track.FootTrack {
  let fps = 25.0
  let frames : Array[@track.FrameRecord] = []
  for i in 0..<n {
    let t = i.to_double() / fps
    // triangle wave in [0,1] peaking when (t - phase) is a whole stride
    fn swing(phase : Double) -> Double {
      let u = (t - phase) % 1.0
      let u = if u < 0.0 { u + 1.0 } else { u }
      let d = if u < 0.5 { u } else { 1.0 - u }
      1.0 - 2.0 * d
    }
    frames.push({
      i,
      t,
      left: { x: 0.4, y: 0.85 + amp * swing(0.32), v: vis, },
      right: { x: 0.6, y: 0.85 + amp * swing(0.84), v: vis, },
    })
  }
  { video: "synthetic", fps, n_frames: n, width: 1920, height: 1080, frames, }
}

///|
test "triangular walk: landings at the peaks, feet interleaved" {
  let events = detect(tri_walk(125, 0.1, 0.9))
  inspect(events.length(), content="10")
  // left foot: frames 8, 33, 58, 83, 108
  let left = events.filter(e => e.foot is Left)
  let left_frames = left.map(e => e.frame)
  debug_inspect(left_frames, content="[8, 33, 58, 83, 108]")
  // right foot: frames 21, 46, 71, 96, 121
  let right = events.filter(e => e.foot is Right)
  debug_inspect(right.map(e => e.frame), content="[21, 46, 71, 96, 121]")
  // merged output is time-sorted and alternates feet
  inspect(events[0].time.to_string(), content="0.32")
  inspect(events[1].time.to_string(), content="0.84")
  inspect(events[9].time.to_string(), content="4.84")
  for i in 0..<events.length() {
    let e = events[i]
    if e.strength <= 0.0 || e.strength > 1.0 {
      fail("strength out of range at \{e.time}: \{e.strength}")
    }
  }
}

///|
test "sinusoidal walk: landings within one frame of the peaks" {
  let fps = 25.0
  let n = 125
  let frames : Array[@track.FrameRecord] = []
  for i in 0..<n {
    let t = i.to_double() / fps
    fn swing(phase : Double) -> Double {
      @math.cos(2.0 * @math.PI * (t - phase))
    }
    frames.push({
      i,
      t,
      left: { x: 0.4, y: 0.85 + 0.1 * swing(0.32), v: 0.9, },
      right: { x: 0.6, y: 0.85 + 0.1 * swing(0.84), v: 0.9, },
    })
  }
  let track : @track.FootTrack = {
    video: "synthetic",
    fps,
    n_frames: n,
    width: 1920,
    height: 1080,
    frames,
  }
  let events = detect(track)
  inspect(events.length(), content="10")
  let expected : Array[Int] = [8, 21, 33, 46, 58, 71, 83, 96, 108, 121]
  for k, want in expected {
    if (events[k].frame - want).abs() > 1 {
      fail("event \{k} at frame \{events[k].frame}, expected ~\{want}")
    }
  }
}

///|
test "filters: low visibility, shallow swing" {
  // visibility below the gate -> nothing detected
  inspect(detect(tri_walk(50, 0.1, 0.3)).length(), content="0")
  // swing amplitude far below min prominence -> nothing detected
  inspect(detect(tri_walk(50, 0.005, 0.9)).length(), content="0")
}

///|
test "debounce collapses near-simultaneous events" {
  // two left-foot peaks 0.12 s apart (frames 3 and 6), same strength
  let fps = 25.0
  let frames : Array[@track.FrameRecord] = []
  for i in 0..<12 {
    let t = i.to_double() / fps
    // peaks at frames 3 and 6; swing down to baseline between and after
    let ly = 0.85 +
      0.1 *
      (if i == 3 || i == 6 {
        1.0
      } else if i == 4 || i == 5 {
        0.5
      } else {
        0.0
      })
    frames.push({
      i,
      t,
      left: { x: 0.4, y: ly, v: 0.9, },
      right: { x: 0.6, y: 0.8, v: 0.9, },
    })
  }
  let track : @track.FootTrack = {
    video: "synthetic",
    fps,
    n_frames: 12,
    width: 1920,
    height: 1080,
    frames,
  }
  // default min_interval_s = 0.2 s > 0.12 s -> one event, at the stronger peak
  let merged = detect(track)
  inspect(merged.length(), content="1")
  // with a tiny interval both survive
  let split = detect(track, min_interval_s=0.05)
  debug_inspect(split.map(e => e.frame), content="[3, 6]")
}
