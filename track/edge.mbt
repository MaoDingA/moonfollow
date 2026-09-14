///|
/// One leading-edge sample per frame: the x position of the person's
/// leading foot edge in profile view (walking across the frame), with a
/// presence confidence.

///|
pub(all) struct EdgeSample {
  i : Int
  t : Double
  x : Double
  v : Double
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct EdgeTrack {
  video : String
  fps : Double
  n_frames : Int
  width : Int
  height : Int
  frames : Array[EdgeSample]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub fn EdgeTrack::parse(text : String) -> EdgeTrack raise TrackError {
  let json = @json.parse(text) catch {
    err => raise TrackError::BadJson(detail=err.to_string())
  }
  let track : EdgeTrack = @json.from_json(json) catch {
    err => raise TrackError::BadJson(detail=err.to_string())
  }
  if track.fps <= 0.0 {
    raise TrackError::InvalidTrack(detail="fps must be positive")
  }
  if track.n_frames != track.frames.length() {
    raise TrackError::InvalidTrack(
      detail="n_frames \{track.n_frames} != \{track.frames.length()} samples",
    )
  }
  for k in 1..<track.frames.length() {
    if track.frames[k].i <= track.frames[k - 1].i {
      raise TrackError::InvalidTrack(
        detail="indices must strictly increase: \{track.frames[k - 1].i} then \{track.frames[k].i}",
      )
    }
  }
  track
}
