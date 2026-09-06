///|
/// Decode one pass at the given detection width and track the feet.
/// Returns the track and the median person box height in detection pixels.

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
) -> (@track.FootTrack, Int) raise VisionError {
  let reader = FrameReader::open(path, src_width~, src_height~, width~)
  let detector = FeetDetector::new(reader.width, reader.height, dark~)
  let frames : Array[@track.FrameRecord] = []
  let heights : Array[Int] = []
  while true {
    match reader.next_frame() {
      Some(frame) => {
        let (left, right) = detector.process_frame(frame)
        let i = frames.length()
        frames.push({ i, t: i.to_double() / fps, left, right, })
        if detector.person_height() > 0 && i % 10 == 0 {
          heights.push(detector.person_height())
        }
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
  (
    {
      video: path,
      fps,
      n_frames: frames.length(),
      width: src_width,
      height: src_height,
      frames,
    },
    median_height,
  )
}

/// Share of frames with a confidently visible foot; the polarity probe
/// retries the opposite polarity when this is low.

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
/// Detect a foot track from a video file:
/// probe (ffprobe, CFR-verified) -> decode (ffmpeg, downscaled gray)
/// -> classical foot tracking. Requires ffmpeg/ffprobe on PATH.
///
/// Polarity: by default a bright-subject pass runs first and a
/// dark-subject pass (pedestrian in dark clothes against a bright street)
/// retries automatically when few frames show a visible foot; pass
/// `dark=true/false` to force one.
///
/// Resolution is adaptive: a first pass runs at `width`; when the person
/// spans fewer than 100 pixels there, the video is re-decoded wider so foot
/// swing survives quantisation (capped at 1280 px).

///|
pub fn detect_track(
  path : String,
  width? : Int = 320,
  polarity? : Polarity = Auto,
) -> @track.FootTrack raise VisionError {
  let info = probe(path)
  // (track, median height, polarity of the winning pass)
  let (track, median_h, chosen_dark) : (@track.FootTrack, Int, Bool) = match
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
          // retry needs 1.5x the visible frames to switch.
          let bright_ratio = visible_ratio(bright.0)
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
            if visible_ratio(dark_pass.0) > bright_ratio * 1.5 {
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
    return track
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
    return track
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
