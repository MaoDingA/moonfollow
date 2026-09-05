///|
fn good_track_json() -> String {
  let text : String =
    #|{
    #|  "video": "clip.mp4", "fps": 25.0, "n_frames": 3, "width": 1920, "height": 1080,
    #|  "frames": [
    #|    { "i": 0, "t": 0.0,
    #|      "left":  { "x": 0.50, "y": 0.90, "v": 0.8 },
    #|      "right": { "x": 0.52, "y": 0.86, "v": 0.7 } },
    #|    { "i": 1, "t": 0.04,
    #|      "left":  { "x": 0.51, "y": 0.91, "v": 0.9 },
    #|      "right": { "x": 0.53, "y": 0.84, "v": 0.6 } },
    #|    { "i": 2, "t": 0.08,
    #|      "left":  { "x": 0.52, "y": 0.88, "v": 0.7 },
    #|      "right": { "x": 0.54, "y": 0.87, "v": 0.9 } }
    #|  ]
    #|}
  text
}

///|
test "parse valid foottrack" {
  let track = @track.FootTrack::parse(good_track_json())
  inspect(track.fps.to_string(), content="25")
  inspect(track.frames.length(), content="3")
  let second = track.frames[1]
  inspect(second.i, content="1")
  inspect(second.left.y.to_string(), content="0.91")
  inspect(second.right.v.to_string(), content="0.6")
}

///|
test "parse -> to_json -> parse roundtrip is stable" {
  let track = @track.FootTrack::parse(good_track_json())
  let json = @json.to_json(track)
  let again = @track.FootTrack::parse(json.stringify())
  inspect(again == track, content="true")
}

///|
test "rejects malformed json" {
  try ignore(@track.FootTrack::parse("{ not json")) catch {
    err =>
      inspect(
        err.to_string().has_prefix("invalid foottrack JSON:"),
        content="true",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "rejects semantic violations" {
  fn track_with(n_frames : Int, frames : String) -> String {
    "{\"video\": \"clip.mp4\", \"fps\": 25.0, \"n_frames\": \{n_frames}, \"width\": 1920, \"height\": 1080, \"frames\": \{frames}}"
  }
  fn frame(i : Int, t : Double) -> String {
    "{\"i\": \{i}, \"t\": \{t}, \"left\": {\"x\": 0.5, \"y\": 0.5, \"v\": 0.5}, \"right\": {\"x\": 0.5, \"y\": 0.5, \"v\": 0.5}}"
  }
  // fps must be positive
  let bad_fps = "{\"video\": \"v\", \"fps\": 0.0, \"n_frames\": 1, \"width\": 1, \"height\": 1, \"frames\": [" +
    frame(0, 0.0) +
    "]}"
  try ignore(@track.FootTrack::parse(bad_fps)) catch {
    err =>
      inspect(
        err.to_string(),
        content="invalid foottrack data: fps must be > 0, got 0",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  // frame indices must strictly increase
  let dup = track_with(2, "[" + frame(0, 0.0) + ", " + frame(0, 0.04) + "]")
  try ignore(@track.FootTrack::parse(dup)) catch {
    err =>
      inspect(
        err.to_string(),
        content="invalid foottrack data: frame indices must strictly increase: 0 then 0",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  // coordinates outside [0,1]
  let far = "{\"video\": \"v\", \"fps\": 25.0, \"n_frames\": 1, \"width\": 1, \"height\": 1, \"frames\": [{\"i\": 0, \"t\": 0.0, \"left\": {\"x\": 1.5, \"y\": 0.5, \"v\": 0.5}, \"right\": {\"x\": 0.5, \"y\": 0.5, \"v\": 0.5}}]}"
  try ignore(@track.FootTrack::parse(far)) catch {
    err =>
      inspect(
        err.to_string(),
        content="invalid foottrack data: frame 0 left x=1.5 outside [0,1]",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  // timestamps must not decrease
  let back = track_with(2, "[" + frame(0, 0.08) + ", " + frame(1, 0.04) + "]")
  try ignore(@track.FootTrack::parse(back)) catch {
    err =>
      inspect(
        err.to_string(),
        content="invalid foottrack data: timestamps must not decrease: 0.08 then 0.04",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  // n_frames mismatch
  let mismatch = track_with(3, "[" + frame(0, 0.0) + "]")
  try ignore(@track.FootTrack::parse(mismatch)) catch {
    err =>
      inspect(
        err.to_string(),
        content="invalid foottrack data: n_frames=3 does not match 1 frame records",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}
