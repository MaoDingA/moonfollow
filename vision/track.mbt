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
  // frames_by_person[k] collects the frames of stable person id k; ids come
  // from the detector's torso-run center matching, so a person briefly lost
  // and refound appends to their own track
  let frames_by_person : Array[Array[@track.FrameRecord]] = []
  let heights : Array[Int] = []
  let mut frame_index = 0
  while true {
    match reader.next_frame() {
      Some(frame) => {
        for entry in detector.process_frame_persons(frame) {
          let (id, left, right) = entry
          while frames_by_person.length() <= id {
            frames_by_person.push([])
          }
          frames_by_person[id].push({
            i: frame_index,
            t: frame_index.to_double() / fps,
            left,
            right,
          })
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
          // A bright-subject video also produces an inverted "ghost" track
          // in the dark pass (the foreground's absence reads as dark fg), so
          // the dark pass only wins when bright clearly fails and dark is
          // substantially better: visible ratio >= 0.35 keeps bright, and a
          // retry needs 1.5x the visible frames to switch. Ratio is judged
          // on the dominant person's track.
          let bright_ratio = dominant_ratio(bright.0)
          if bright_ratio >= 0.35 {
            (bright.0, bright.1, false)
          } else {
            let dark_pass = decode_and_track(
              path,
              src_width=info.width,
              src_height=info.height,
              fps=info.fps,
              width~,
              dark=true,
            )
            if dominant_ratio(dark_pass.0) > bright_ratio * 1.5 {
              (dark_pass.0, dark_pass.1, true)
            } else {
              (bright.0, bright.1, false)
            }
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
/// Visible ratio of the dominant track, 0 for an empty pass.

///|
fn dominant_ratio(tracks : Array[@track.FootTrack]) -> Double {
  if tracks.length() == 0 {
    return 0.0
  }
  visible_ratio(tracks[0])
}
