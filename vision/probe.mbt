///|
/// Container metadata for the first video stream.

///|
pub(all) struct VideoInfo {
  width : Int
  height : Int
  fps : Double
  nb_frames : Int?
} derive(Debug, Eq)

///|
struct StreamJson {
  width : Int
  height : Int
  r_frame_rate : String
  avg_frame_rate : String
  nb_frames : String?
} derive(FromJson)

///|
struct ProbeJson {
  streams : Array[StreamJson]
} derive(FromJson)

///|
fn fraction_to_double(
  text : String,
  path~ : String,
) -> Double raise VisionError {
  match text.split("/").to_array() {
    [num, den] => {
      let n : Int = @parse.parse_int(num) catch {
        _ => raise VisionError::ProbeFailed(path~, status=0)
      }
      let d : Int = @parse.parse_int(den) catch {
        _ => raise VisionError::ProbeFailed(path~, status=0)
      }
      n.to_double() / d.to_double()
    }
    _ => raise VisionError::ProbeFailed(path~, status=0)
  }
}

///|
/// Probe a video with ffprobe and verify it is constant frame rate.

///|
pub fn probe(path : String) -> VideoInfo raise VisionError {
  let proc = @fsio.spawn([
    "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate,avg_frame_rate,nb_frames",
    "-of", "json", path,
  ]) catch {
    _ => raise VisionError::ToolMissing(tool="ffprobe")
  }
  let text = read_all(proc)
  let status = proc.finish()
  if status != 0 {
    raise VisionError::ProbeFailed(path~, status~)
  }
  let doc : ProbeJson = @json.from_json(@json.parse(text)) catch {
    _ => raise VisionError::ProbeFailed(path~, status~)
  }
  guard doc.streams.length() > 0 else {
    raise VisionError::NoVideoStream(path~)
  }
  let stream = doc.streams[0]
  let fps = fraction_to_double(stream.r_frame_rate, path~)
  let avg = fraction_to_double(stream.avg_frame_rate, path~)
  if fps <= 0.0 {
    raise VisionError::NoVideoStream(path~)
  }
  if (fps - avg).abs() > 0.001 {
    raise VisionError::VariableFrameRate(rate=fps, avg~)
  }
  let nb_frames = match stream.nb_frames {
    Some(text) => {
      let n : Int = @parse.parse_int(text) catch {
        _ => raise VisionError::ProbeFailed(path~, status~)
      }
      Some(n)
    }
    None => None
  }
  { width: stream.width, height: stream.height, fps, nb_frames, }
}

///|
/// Drain a process' stdout as a UTF-8 string.

///|
fn read_all(proc : @fsio.Proc) -> String {
  let buf = Buffer::Buffer()
  let mut chunk = proc.read_chunk()
  while chunk.length() > 0 {
    buf.write_bytes(chunk[:])
    chunk = proc.read_chunk()
  }
  @utf8.decode_lossy(buf.to_bytes())
}
