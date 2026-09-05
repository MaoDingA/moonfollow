///|
/// Streams downscaled grayscale frames from ffmpeg.
///
/// ffmpeg is spawned with `-vf scale=W:H -f rawvideo -pix_fmt gray`, so each
/// frame is exactly `width * height` bytes. The detector only needs relative
/// positions, so a small frame (320 px wide) keeps everything fast.

///|
pub(all) struct FrameReader {
  proc : @fsio.Proc
  width : Int
  height : Int
  mut cur : Bytes // current chunk being consumed
  mut pos : Int // read offset into cur
}

///|
fn even(n : Int) -> Int {
  if n % 2 == 0 {
    n
  } else {
    n + 1
  }
}

///|
pub fn FrameReader::open(
  path : String,
  src_width~ : Int,
  src_height~ : Int,
  width? : Int = 320,
) -> FrameReader raise VisionError {
  if src_width <= 0 || src_height <= 0 {
    raise VisionError::NoVideoStream(path~)
  }
  let height = if src_width <= width {
    even(src_height)
  } else {
    let scaled = src_height * width / src_width
    if scaled < 2 {
      2
    } else {
      even(scaled)
    }
  }
  let scale = "\{width}x\{height}"
  let proc = @fsio.spawn([
    "ffmpeg",
    "-v",
    "error",
    "-i",
    path,
    "-vf",
    "scale=\{scale}",
    "-f",
    "rawvideo",
    "-pix_fmt",
    "gray",
    "-",
  ]) catch {
    _ => raise VisionError::ToolMissing(tool="ffmpeg")
  }
  { proc, width, height, cur: b"", pos: 0, }
}

///|
fn FrameReader::buffered(self : FrameReader) -> Int {
  self.cur.length() - self.pos
}

///|
/// Next frame as `width * height` gray bytes, or None at end of stream.

///|
pub fn FrameReader::next_frame(self : FrameReader) -> Bytes? {
  let frame_bytes = self.width * self.height
  while self.buffered() < frame_bytes {
    let chunk = self.proc.read_chunk()
    if chunk.length() == 0 {
      // EOF: drop any trailing partial frame
      self.cur = b""
      self.pos = 0
      return None
    }
    // keep the unconsumed tail and continue reading after it
    self.cur = self.cur[self.pos:].to_owned() + chunk
    self.pos = 0
  }
  let frame = self.cur[self.pos:self.pos + frame_bytes].to_owned()
  self.pos = self.pos + frame_bytes
  Some(frame)
}

///|
/// Close ffmpeg and check its exit status.

///|
pub fn FrameReader::finish(self : FrameReader) -> Unit raise VisionError {
  let status = self.proc.finish()
  if status != 0 {
    raise VisionError::DecodeFailed(status~)
  }
}
