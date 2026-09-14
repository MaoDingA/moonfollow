///|
/// Decode one pass at the given detection width and track the feet.
/// Returns one track per detected person (dominant first) and the median
/// person box height in detection pixels. Multi-person tracks carry a
/// person index; the frame indices stay global.

///|
/// Subject polarity for detection.

///|
pub(all) enum Polarity {
  Auto // score both, keep the better
  Bright // subject brighter than the background
  Dark // subject darker than the background
} derive(Debug)

///|
fn decode_and_track(
  path : String,
  src_width~ : Int,
  src_height~ : Int,
  fps~ : Double,
  width~ : Int,
  dark? : Bool = false,
) -> (Array[@track.FootTrack], Int) raise VisionError {
  let reader = FrameReader::open(path, src_width~, src_height~, width~)
  let detector = FeetDetector::new(reader.width, reader.height, dark~)
  // frames_by_person[k] collects one record per frame for stable person id
  // k (ids come from the detector's torso-run center matching, so a person
  // briefly lost and refound appends to their own track). Absent frames are
  // invisible placeholders; when the person reappears within `max_gap`
  // frames the placeholder window is retro-interpolated between the last
  // seen and the new keypoints, so the landing rise keeps its slope instead
  // of being chopped and mistimed (small/distant feet flicker around the
  // visibility gate).
  let frames_by_person : Array[Array[@track.FrameRecord]] = []
  let pending_by_person : Array[Array[Int]] = [] // placeholder frame indices
  let heights : Array[Int] = []
  let mut frame_index = 0
  let max_gap = 6
  while true {
    match reader.next_frame() {
      Some(frame) => {
        let persons = detector.process_frame_persons(frame)
        for k, frames in frames_by_person {
          let pair : (Int, @track.KeyPoint, @track.KeyPoint)? = {
            let mut found : (Int, @track.KeyPoint, @track.KeyPoint)? = None
            for entry in persons {
              if entry.0 == k {
                found = Some(entry)
                break
              }
            }
            found
          }
          match pair {
            Some((_, left, right)) => {
              let pending = pending_by_person[k]
              if pending.length() > 0 &&
                pending.length() <= max_gap &&
                frames.length() > 0 {
                let last = frames[frames.length() - 1]
                let span = frame_index - last.i
                if span > 0 {
                  let start_i = frames[0].i // one record per frame since then
                  for idx in pending {
                    let u = (idx - last.i).to_double() / span.to_double()
                    frames[idx - start_i] = {
                      i: idx,
                      t: idx.to_double() / fps,
                      left: lerp_key(last.left, left, u),
                      right: lerp_key(last.right, right, u),
                    }
                  }
                }
              }
              pending_by_person[k] = []
              frames.push({
                i: frame_index,
                t: frame_index.to_double() / fps,
                left,
                right,
              })
            }
            None => {
              pending_by_person[k].push(frame_index)
              frames.push({
                i: frame_index,
                t: frame_index.to_double() / fps,
                left: { x: 0.5, y: 1.0, v: 0.0, },
                right: { x: 0.5, y: 1.0, v: 0.0, },
              })
            }
          }
        }
        // newly sighted persons start their track at this frame
        for entry in persons {
          let (id, left, right) = entry
          while frames_by_person.length() <= id {
            frames_by_person.push([])
            pending_by_person.push([])
          }
          if frames_by_person[id].length() == 0 {
            frames_by_person[id].push({
              i: frame_index,
              t: frame_index.to_double() / fps,
              left,
              right,
            })
          }
        }
        if detector.person_height() > 0 && frame_index % 10 == 0 {
          heights.push(detector.person_height())
        }
        frame_index = frame_index + 1
      }
      None => break
    }
  }
  reader.finish()
  heights.sort()
  let median_height = if heights.length() > 0 {
    heights[heights.length() / 2]
  } else {
    0
  }
  let tracks : Array[@track.FootTrack] = []
  for frames in frames_by_person {
    if frames.length() == 0 {
      continue
    }
    tracks.push({
      video: path,
      fps,
      n_frames: frames.length(),
      width: src_width,
      height: src_height,
      frames,
    })
  }
  // dominant (most frames) person first
  tracks.sort_by((a, b) => b.frames.length().compare(a.frames.length()))
  (tracks, median_height)
}

///|
fn visible_ratio(track : @track.FootTrack) -> Double {
  if track.n_frames == 0 {
    return 0.0
  }
  let mut seen = 0
  for f in track.frames {
    if f.left.v >= 0.5 || f.right.v >= 0.5 {
      seen = seen + 1
    }
  }
  seen.to_double() / track.n_frames.to_double()
}

///|
/// Detect foot tracks from a video file, one per person:
/// probe (ffprobe, CFR-verified) -> decode (ffmpeg, downscaled gray)
/// -> classical per-person foot tracking. Requires ffmpeg/ffprobe on PATH.
/// The dominant person (most tracked frames) comes first; a single-person
/// video yields exactly one track.
///
/// Polarity: by default a bright-subject pass runs first and a
/// dark-subject pass (pedestrian in dark clothes against a bright street)
/// retries automatically when few frames show a visible foot; pass
/// `Bright`/`Dark` to force one.
///
/// Resolution is adaptive: a first pass runs at `width`; when people span
/// fewer than 100 pixels there, the video is re-decoded wider so foot
/// swing survives quantisation (capped at 1280 px).

///|
pub fn detect_tracks(
  path : String,
  width? : Int = 320,
  polarity? : Polarity = Auto,
) -> Array[@track.FootTrack] raise VisionError {
  let info = probe(path)
  // (tracks, median height, polarity of the winning pass)
  let (tracks, median_h, chosen_dark) : (Array[@track.FootTrack], Int, Bool) = match
    polarity {
    Dark => {
      let (t, h) = decode_and_track(
        path,
        src_width=info.width,
        src_height=info.height,
        fps=info.fps,
        width~,
        dark=true,
      )
      (t, h, true)
    }
    _ => {
      let bright = decode_and_track(
        path,
        src_width=info.width,
        src_height=info.height,
        fps=info.fps,
        width~,
      )
      match polarity {
        Bright => (bright.0, bright.1, false)
        _ => {
          // Both polarities can produce a high-presence "ghost" track on the
          // wrong subject type (the subject's absence read as foreground),
          // so presence alone cannot pick the pass. Score presence times
          // oscillation instead: a real foot swings visibly through its
          // stride, a ghost's y series is nearly flat.
          let dark_pass = decode_and_track(
            path,
            src_width=info.width,
            src_height=info.height,
            fps=info.fps,
            width~,
            dark=true,
          )
          let bright_score = dominant_score(bright.0)
          let dark_score = dominant_score(dark_pass.0)
          if dark_score > bright_score {
            (dark_pass.0, dark_pass.1, true)
          } else {
            (bright.0, bright.1, false)
          }
        }
      }
    }
  }
  if median_h >= 100 || width >= 1280 {
    return tracks
  }
  let scaled = width * 100 / median_h
  let wider = if scaled > 1280 {
    1280
  } else if scaled % 2 == 1 {
    scaled + 1
  } else {
    scaled
  }
  if wider <= width + 40 {
    return tracks
  }
  let (better, _) = decode_and_track(
    path,
    src_width=info.width,
    src_height=info.height,
    fps=info.fps,
    width=wider,
    dark=chosen_dark,
  )
  better
}

///|
/// Single-person convenience: the dominant person's track.

///|
pub fn detect_track(
  path : String,
  width? : Int = 320,
  polarity? : Polarity = Auto,
) -> @track.FootTrack raise VisionError {
  let tracks = detect_tracks(path, width~, polarity~)
  if tracks.length() > 0 {
    return tracks[0]
  }
  let info = probe(path)
  {
    video: path,
    fps: info.fps,
    n_frames: 0,
    width: info.width,
    height: info.height,
    frames: [],
  }
}

///|
/// Linear interpolation between two keypoints; a foot invisible at either
/// endpoint stays invisible through the fill (never invent a foot).

///|
fn lerp_key(
  a : @track.KeyPoint,
  b : @track.KeyPoint,
  u : Double,
) -> @track.KeyPoint {
  if a.v <= 0.0 || b.v <= 0.0 {
    return { x: 0.5, y: 1.0, v: 0.0, }
  }
  {
    x: a.x + (b.x - a.x) * u,
    y: a.y + (b.y - a.y) * u,
    v: if a.v < b.v {
      a.v
    } else {
      b.v
    },
  }
}

///|
/// Mean consecutive-frame |dy| of a foot over visible pairs: a real foot
/// oscillates through its stride, a polarity-ghost track (the subject's
/// absence read as foreground) barely moves. Max over both feet.

///|
fn oscillation(track : @track.FootTrack) -> Double {
  let mut best = 0.0
  for foot in [0, 1] {
    let mut total = 0.0
    let mut n = 0
    let mut prev : Double? = None
    for f in track.frames {
      let p = if foot == 0 { f.left } else { f.right }
      if p.v >= 0.5 {
        match prev {
          Some(y0) => {
            total = total + (p.y - y0).abs()
            n = n + 1
          }
          None => ()
        }
        prev = Some(p.y)
      } else {
        prev = None
      }
    }
    if n > 0 {
      let mean = total / n.to_double()
      if mean > best {
        best = mean
      }
    }
  }
  best
}

///|
/// Ghost-resistant pass score: presence times oscillation quality. A
/// polarity ghost shows high presence but a nearly flat y series, so it
/// scores near zero against the real subject pass.

///|
fn pass_score(track : @track.FootTrack) -> Double {
  if track.frames.length() == 0 {
    return 0.0
  }
  let quality = oscillation(track) / 0.02
  let quality = if quality < 0.0 {
    0.0
  } else if quality > 1.0 {
    1.0
  } else {
    quality
  }
  visible_ratio(track) * quality
}

///|
/// Ghost-resistant score of the dominant track, 0 for an empty pass.

///|
fn dominant_score(tracks : Array[@track.FootTrack]) -> Double {
  if tracks.length() == 0 {
    return 0.0
  }
  pass_score(tracks[0])
}

///|
fn decode_edge(
  path : String,
  src_width~ : Int,
  src_height~ : Int,
  fps~ : Double,
  width~ : Int,
  dark? : Bool = false,
) -> @track.EdgeTrack raise VisionError {
  let reader = FrameReader::open(path, src_width~, src_height~, width~)
  let detector = EdgeDetector::new(reader.width, reader.height, dark~)
  let frames : Array[@track.EdgeSample] = []
  let mut last_x = 0.5
  while true {
    match reader.next_frame() {
      Some(frame) => {
        let i = frames.length()
        match detector.process_frame(frame) {
          Some(x) => {
            last_x = x
            frames.push({ i, t: i.to_double() / fps, x, v: 1.0, })
          }
          None => frames.push({ i, t: i.to_double() / fps, x: last_x, v: 0.0, })
        }
      }
      None => break
    }
  }
  reader.finish()
  {
    video: path,
    fps,
    n_frames: frames.length(),
    width: src_width,
    height: src_height,
    frames,
  }
}

///|
/// Profile-view detection: track the leading foot's x edge across the
/// frame. Feed the resulting track to `steps` (the dwell-start rule is the
/// same); foot labels alternate because profile view cannot tell the feet
/// apart.

///|
pub fn detect_edge_track(
  path : String,
  width? : Int = 320,
  polarity? : Polarity = Auto,
) -> @track.EdgeTrack raise VisionError {
  let info = probe(path)
  fn presence(track : @track.EdgeTrack) -> Double {
    if track.n_frames == 0 {
      return 0.0
    }
    let mut seen = 0
    for f in track.frames {
      if f.v >= 0.5 {
        seen = seen + 1
      }
    }
    seen.to_double() / track.n_frames.to_double()
  }
  let bright = decode_edge(
    path,
    src_width=info.width,
    src_height=info.height,
    fps=info.fps,
    width~,
  )
  match polarity {
    Bright => bright
    Dark => {
      let (t, _) = (
        decode_edge(
          path,
          src_width=info.width,
          src_height=info.height,
          fps=info.fps,
          width~,
          dark=true,
        ),
        0,
      )
      ignore(t)
      t
    }
    _ => {
      let bright_ratio = presence(bright)
      if bright_ratio >= 0.35 {
        bright
      } else {
        let dark_pass = decode_edge(
          path,
          src_width=info.width,
          src_height=info.height,
          fps=info.fps,
          width~,
          dark=true,
        )
        if presence(dark_pass) > bright_ratio * 1.5 {
          dark_pass
        } else {
          bright
        }
      }
    }
  }
}
