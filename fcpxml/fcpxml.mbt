///|
/// One footstep landing to be placed as a clip marker.

///|
pub(all) struct FootstepMarker {
  frame : Int
  foot : String // "left" / "right"
  strength : Double
} derive(Debug, Eq)

///|
/// Build an FCPXML 1.8 document placing the video as a single asset-clip
/// with one marker per footstep landing, for import into DaVinci Resolve
/// (or FCP): the editor sees every landing on the clip and can drop the SFX
/// by hand instead of re-rendering.
///
/// Frame math stays rational throughout (`den/num` seconds per frame), so
/// drop-frame rates like 29.97 keep exact frame numbers; `tcFormat` follows
/// the drop flag.
pub fn build(
  video~ : String,
  width~ : Int,
  height~ : Int,
  rate~ : @timecode.FrameRate,
  total_frames~ : Int,
  events~ : Array[FootstepMarker],
) -> String {
  let b = StringBuilder::StringBuilder()
  b.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  b.write_string("<!DOCTYPE fcpxml>\n")
  b.write_string("<fcpxml version=\"1.8\">\n")
  b.write_string(" <resources>\n")
  b.write_string(
    "  <format id=\"r1\" name=\"FFVideoFormat\{rate.nominal}p\{height}\" frameDuration=\"\{rat_seconds(1, rate~)}\" width=\"\{width}\" height=\"\{height}\"/>\n",
  )
  b.write_string(
    "  <asset id=\"r2\" name=\"\{file_stem(video)}\" start=\"0s\" duration=\"\{rat_seconds(total_frames, rate~)}\" hasVideo=\"1\" format=\"r1\">\n",
  )
  b.write_string(
    "   <media-rep kind=\"original-media\" src=\"\{file_url(video)}\"/>\n",
  )
  b.write_string("  </asset>\n")
  b.write_string(" </resources>\n")
  let tc = if rate.drop { "DF" } else { "NDF" }
  b.write_string(" <library>\n")
  b.write_string("  <event name=\"moonfollow footsteps\">\n")
  b.write_string("   <project name=\"steps\">\n")
  b.write_string(
    "    <sequence format=\"r1\" duration=\"\{rat_seconds(total_frames, rate~)}\" tcStart=\"0s\" tcFormat=\"\{tc}\">\n",
  )
  b.write_string("     <spine>\n")
  b.write_string(
    "      <asset-clip ref=\"r2\" offset=\"0s\" duration=\"\{rat_seconds(total_frames, rate~)}\" tcFormat=\"\{tc}\">\n",
  )
  for e in events {
    let pct = (e.strength * 100.0).round().to_int()
    b.write_string(
      "       <marker start=\"\{rat_seconds(e.frame, rate~)}\" duration=\"\{rat_seconds(1, rate~)}\" value=\"footstep \{xml_escape(e.foot)} (\{pct}%)\"/>\n",
    )
  }
  b.write_string("      </asset-clip>\n")
  b.write_string("     </spine>\n")
  b.write_string("    </sequence>\n")
  b.write_string("   </project>\n")
  b.write_string("  </event>\n")
  b.write_string(" </library>\n")
  b.write_string("</fcpxml>\n")
  b.to_string()
}

///|
/// Frame count as an exact rational-seconds string, e.g. "1001/30000s".

///|
fn rat_seconds(frames : Int, rate~ : @timecode.FrameRate) -> String {
  "\{frames * rate.den}/\{rate.num}s"
}

///|
/// XML-escape a path and make it a file URL when absolute; relative paths
/// are left for Resolve to resolve against the FCPXML location.

///|
fn file_url(path : String) -> String {
  let escaped = xml_escape(path).replace(old=" ", new="%20")
  if path.length() > 0 && path[0] == '/' {
    "file://\{escaped}"
  } else {
    escaped
  }
}

///|
fn xml_escape(s : String) -> String {
  let b = StringBuilder::StringBuilder()
  for ch in s {
    match ch {
      '&' => b.write_string("&amp;")
      '<' => b.write_string("&lt;")
      '>' => b.write_string("&gt;")
      '"' => b.write_string("&quot;")
      _ => b.write_char(ch)
    }
  }
  b.to_string()
}

///|
/// Last path component without its extension, for the asset name.

///|
fn file_stem(path : String) -> String {
  let name_start = match path.rev_find("/") {
    Some(i) => i + 1
    None => 0
  }
  let name : String = path[name_start:].to_owned()
  match name.rev_find(".") {
    Some(dot) if dot > 0 => name[:dot].to_owned()
    _ => name
  }
}
