///|
/// Detect a foot track from a video file:
/// probe (ffprobe, CFR-verified) -> decode (ffmpeg, downscaled gray)
/// -> classical foot tracking. Requires ffmpeg/ffprobe on PATH.

///|
pub fn detect_track(
  path : String,
  width? : Int = 320,
) -> @track.FootTrack raise VisionError {
  let info = probe(path)
  let reader = FrameReader::open(
    path,
    src_width=info.width,
    src_height=info.height,
    width~,
  )
  let detector = FeetDetector::new(reader.width, reader.height)
  let frames : Array[@track.FrameRecord] = []
  let fps = info.fps
  while true {
    match reader.next_frame() {
      Some(frame) => {
        let (left, right) = detector.process_frame(frame)
        let i = frames.length()
        frames.push({ i, t: i.to_double() / fps, left, right, })
      }
      None => break
    }
  }
  reader.finish()
  {
    video: path,
    fps,
    n_frames: frames.length(),
    width: info.width,
    height: info.height,
    frames,
  }
}
