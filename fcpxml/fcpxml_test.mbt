///|
test "fcpxml: drop-frame markers at exact rational offsets" {
  let events : Array[@fcpxml.FootstepMarker] = [
    { frame: 0, foot: "left", strength: 0.5, },
    { frame: 1802, foot: "right", strength: 1.0, },
  ]
  let xml = @fcpxml.build(
    video="/tmp/clip 1.mp4",
    width=1280,
    height=720,
    rate=@timecode.FrameRate::fps2997(),
    total_frames=1803,
    events~,
  )
  inspect(
    xml,
    content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n<fcpxml version=\"1.8\">\n <resources>\n  <format id=\"r1\" name=\"FFVideoFormat30p720\" frameDuration=\"1001/30000s\" width=\"1280\" height=\"720\"/>\n  <asset id=\"r2\" name=\"clip 1\" start=\"0s\" duration=\"1804803/30000s\" hasVideo=\"1\" format=\"r1\">\n   <media-rep kind=\"original-media\" src=\"file:///tmp/clip%201.mp4\"/>\n  </asset>\n </resources>\n <library>\n  <event name=\"moonfollow footsteps\">\n   <project name=\"steps\">\n    <sequence format=\"r1\" duration=\"1804803/30000s\" tcStart=\"0s\" tcFormat=\"DF\">\n     <spine>\n      <asset-clip ref=\"r2\" offset=\"0s\" duration=\"1804803/30000s\" tcFormat=\"DF\">\n       <marker start=\"0/30000s\" duration=\"1001/30000s\" value=\"footstep left (50%)\"/>\n       <marker start=\"1803802/30000s\" duration=\"1001/30000s\" value=\"footstep right (100%)\"/>\n      </asset-clip>\n     </spine>\n    </sequence>\n   </project>\n  </event>\n </library>\n</fcpxml>\n",
  )
}

///|
test "fcpxml: NDF rate, relative path stays relative, xml escaped" {
  let events : Array[@fcpxml.FootstepMarker] = [
    { frame: 20, foot: "right", strength: 1.0, },
  ]
  let xml = @fcpxml.build(
    video="clips/a&b <walk>.mp4",
    width=1920,
    height=1080,
    rate=@timecode.FrameRate::fps25(),
    total_frames=125,
    events~,
  )
  inspect(xml.contains("frameDuration=\"1/25s\""), content="true")
  inspect(xml.contains("tcFormat=\"NDF\""), content="true")
  inspect(
    xml.contains("src=\"clips/a&amp;b%20&lt;walk&gt;.mp4\""),
    content="true",
  )
  inspect(xml.contains("name=\"a&b <walk>\""), content="true")
  inspect(xml.contains("start=\"20/25s\""), content="true")
  inspect(xml.contains("duration=\"125/25s\""), content="true")
}
