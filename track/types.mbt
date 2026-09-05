///|
/// A tracked foot position in one frame.
///
/// Coordinates are normalised to [0, 1] (origin at the top-left of the
/// picture, y grows downward, so the foot *on the ground* is the local
/// maximum of y). `v` is the detector's visibility/confidence in [0, 1].

///|
pub(all) struct KeyPoint {
  x : Double
  y : Double
  v : Double
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Per-frame record: frame index, timestamp in seconds, and both feet.

///|
pub(all) struct FrameRecord {
  i : Int
  t : Double
  left : KeyPoint
  right : KeyPoint
} derive(Debug, Eq, FromJson, ToJson)

///|
/// A whole tracked-feet track for one video.

///|
pub(all) struct FootTrack {
  video : String
  fps : Double
  n_frames : Int
  width : Int
  height : Int
  frames : Array[FrameRecord]
} derive(Debug, Eq, FromJson, ToJson)
