///|
fn invalid(detail : String) -> Unit raise TrackError {
  raise TrackError::InvalidTrack(detail~)
}

///|
fn validate_point(p : KeyPoint, where_ : String) -> Unit raise TrackError {
  if p.x < 0.0 || p.x > 1.0 {
    invalid("\{where_} x=\{p.x} outside [0,1]")
  }
  if p.y < 0.0 || p.y > 1.0 {
    invalid("\{where_} y=\{p.y} outside [0,1]")
  }
  if p.v < 0.0 || p.v > 1.0 {
    invalid("\{where_} v=\{p.v} outside [0,1]")
  }
}

///|
/// Parse and validate a foottrack JSON document.
///
/// Requires: fps > 0, at least one frame, strictly increasing frame indices,
/// non-decreasing timestamps, and all coordinates/visibilities inside [0, 1].

///|
pub fn FootTrack::parse(text : String) -> FootTrack raise TrackError {
  let json = @json.parse(text) catch {
    err => raise TrackError::BadJson(detail=err.to_string())
  }
  let track : FootTrack = @json.from_json(json) catch {
    err => raise TrackError::BadJson(detail=err.to_string())
  }
  if track.fps <= 0.0 {
    invalid("fps must be > 0, got \{track.fps}")
  }
  if track.frames.length() == 0 {
    invalid("no frames")
  }
  if track.n_frames != track.frames.length() {
    invalid(
      "n_frames=\{track.n_frames} does not match \{track.frames.length()} frame records",
    )
  }
  let mut prev_index : Int? = None
  let mut prev_time = -1.0
  for frame in track.frames {
    if frame.i < 0 {
      invalid("negative frame index \{frame.i}")
    }
    match prev_index {
      Some(prev) =>
        if frame.i <= prev {
          invalid(
            "frame indices must strictly increase: \{prev} then \{frame.i}",
          )
        }
      None => ()
    }
    prev_index = Some(frame.i)
    if frame.t < prev_time {
      invalid("timestamps must not decrease: \{prev_time} then \{frame.t}")
    }
    prev_time = frame.t
    validate_point(frame.left, "frame \{frame.i} left")
    validate_point(frame.right, "frame \{frame.i} right")
  }
  track
}
