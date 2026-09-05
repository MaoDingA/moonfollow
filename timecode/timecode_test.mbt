///|
test "format non-drop rates" {
  let r25 = @timecode.FrameRate::fps25()
  inspect(
    @timecode.Timecode::make(0, rate=r25).to_string(),
    content="00:00:00:00",
  )
  inspect(
    @timecode.Timecode::make(24, rate=r25).to_string(),
    content="00:00:00:24",
  )
  inspect(
    @timecode.Timecode::make(25, rate=r25).to_string(),
    content="00:00:01:00",
  )
  inspect(
    @timecode.Timecode::make(90000, rate=r25).to_string(),
    content="01:00:00:00",
  )
  let r24 = @timecode.FrameRate::fps24()
  inspect(
    @timecode.Timecode::make(23, rate=r24).to_string(),
    content="00:00:00:23",
  )
  inspect(
    @timecode.Timecode::make(24, rate=r24).to_string(),
    content="00:00:01:00",
  )
  let r30 = @timecode.FrameRate::fps30()
  inspect(
    @timecode.Timecode::make(29, rate=r30).to_string(),
    content="00:00:00:29",
  )
  inspect(
    @timecode.Timecode::make(30, rate=r30).to_string(),
    content="00:00:01:00",
  )
}

///|
test "format drop-frame 29.97" {
  let r = @timecode.FrameRate::fps2997()
  inspect(
    @timecode.Timecode::make(0, rate=r).to_string(),
    content="00:00:00;00",
  )
  inspect(
    @timecode.Timecode::make(1797, rate=r).to_string(),
    content="00:00:59;27",
  )
  inspect(
    @timecode.Timecode::make(1800, rate=r).to_string(),
    content="00:01:00;02",
  )
  inspect(
    @timecode.Timecode::make(17982, rate=r).to_string(),
    content="00:10:00;00",
  )
  inspect(
    @timecode.Timecode::make(35964, rate=r).to_string(),
    content="00:20:00;00",
  )
}

///|
test "format drop-frame 59.94" {
  let r = @timecode.FrameRate::fps5994()
  inspect(
    @timecode.Timecode::make(3597, rate=r).to_string(),
    content="00:00:59;57",
  )
  inspect(
    @timecode.Timecode::make(3600, rate=r).to_string(),
    content="00:01:00;04",
  )
  inspect(
    @timecode.Timecode::make(35964, rate=r).to_string(),
    content="00:10:00;00",
  )
}

///|
test "parse non-drop and drop-frame" {
  let r25 = @timecode.FrameRate::fps25()
  inspect(
    @timecode.Timecode::parse("00:00:01:00", rate=r25).frame_index(),
    content="25",
  )
  inspect(
    @timecode.Timecode::parse("01:02:03:24", rate=r25).frame_index(),
    content="93099",
  )
  let r = @timecode.FrameRate::fps2997()
  inspect(
    @timecode.Timecode::parse("00:01:00;02", rate=r).frame_index(),
    content="1800",
  )
  inspect(
    @timecode.Timecode::parse("00:10:00;00", rate=r).frame_index(),
    content="17982",
  )
  inspect(
    @timecode.Timecode::parse("00:12:34;12", rate=r).to_string(),
    content="00:12:34;12",
  )
}

///|
test "parse rejects invalid timecodes" {
  let r25 = @timecode.FrameRate::fps25()
  try ignore(@timecode.Timecode::parse("00:00:00:25", rate=r25)) catch {
    err =>
      inspect(
        err.to_string(),
        content="00:00:00:25: frame number 25 out of range for 25 fps",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  try ignore(@timecode.Timecode::parse("00:00:00;00", rate=r25)) catch {
    err =>
      inspect(
        err.to_string(),
        content="00:00:00;00: drop-frame separator ';' used with non-drop rate 25 fps",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  let r = @timecode.FrameRate::fps2997()
  try ignore(@timecode.Timecode::parse("00:01:00;00", rate=r)) catch {
    err =>
      inspect(
        err.to_string(),
        content="00:01:00;00: frame numbers 00-01 are dropped at the start of minute 1",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  try ignore(@timecode.Timecode::parse("1:2:3", rate=r)) catch {
    err =>
      inspect(
        err.to_string(),
        content="1:2:3: drop-frame rate 29.97 fps (drop-frame) requires ';' before the frame number",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "from_seconds and seconds roundtrip" {
  let r25 = @timecode.FrameRate::fps25()
  inspect(
    @timecode.Timecode::from_seconds(1.0, rate=r25).frame_index(),
    content="25",
  )
  inspect(
    @timecode.Timecode::from_seconds(0.999, rate=r25).frame_index(),
    content="25",
  )
  inspect(
    @timecode.Timecode::from_seconds(12.52, rate=r25).seconds().to_string(),
    content="12.52",
  )
  let r = @timecode.FrameRate::fps2997()
  inspect(
    @timecode.Timecode::from_seconds(60.0, rate=r).frame_index(),
    content="1798",
  )
  try ignore(@timecode.Timecode::from_seconds(-0.5, rate=r25)) catch {
    err =>
      inspect(
        err.to_string(),
        content="negative time -0.5 has no SMPTE timecode",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "of_double snaps known rates" {
  inspect(@timecode.FrameRate::of_double(25.0).to_string(), content="25 fps")
  inspect(
    @timecode.FrameRate::of_double(29.97).to_string(),
    content="29.97 fps (drop-frame)",
  )
  inspect(
    @timecode.FrameRate::of_double(30000.0 / 1001.0).to_string(),
    content="29.97 fps (drop-frame)",
  )
  inspect(
    @timecode.FrameRate::of_double(23.976).to_string(),
    content="23.976 fps",
  )
  inspect(
    @timecode.FrameRate::of_double(59.94).to_string(),
    content="59.94 fps (drop-frame)",
  )
  inspect(@timecode.FrameRate::of_double(50.0).to_string(), content="50 fps")
  try ignore(@timecode.FrameRate::of_double(12.5)) catch {
    err =>
      inspect(
        err.to_string(),
        content="unsupported frame rate 12.5 (supported: 23.976, 24, 25, 29.97, 30, 50, 59.94, 60)",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "drop-frame format and parse are inverse over a sweep" {
  let r = @timecode.FrameRate::fps2997()
  for i in 0..<20000 {
    let tc = @timecode.Timecode::make(i, rate=r)
    let back = @timecode.Timecode::parse(tc.display(), rate=r)
    if back.frame_index() != i {
      fail("roundtrip broke at frame \{i}: \{tc.display()}")
    }
  }
}
