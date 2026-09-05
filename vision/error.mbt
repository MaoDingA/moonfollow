///|
pub(all) suberror VisionError {
  ToolMissing(tool~ : String)
  ProbeFailed(path~ : String, status~ : Int)
  NoVideoStream(path~ : String)
  VariableFrameRate(rate~ : Double, avg~ : Double)
  DecodeFailed(status~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for VisionError with fn output(self, logger) {
  match self {
    ToolMissing(tool~) =>
      logger <+
        "required tool \{tool} not found on PATH (install ffmpeg, which ships ffprobe)"
    ProbeFailed(path~, status~) =>
      logger <+ "ffprobe failed on \{path} (exit \{status})"
    NoVideoStream(path~) => logger <+ "no video stream in \{path}"
    VariableFrameRate(rate~, avg~) =>
      logger <+
        "variable frame rate suspected (r=\{rate}, avg=\{avg}); re-encode to CFR first, e.g. ffmpeg -i in.mp4 -vsync cfr -r 25 out.mp4"
    DecodeFailed(status~) =>
      logger <+ "ffmpeg frame decoding failed (exit \{status})"
  }
}
