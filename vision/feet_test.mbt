///|
/// Build a 160x90 gray frame: dark background (20), bright person (200).
/// Body spans x in [70, 90), y in [30, 60); legs continue down from y=60:
/// left leg x in [72, 78) down to `left_bottom`, right leg x in [82, 88)
/// down to `right_bottom`.

///|
fn walker_frame(left_bottom : Int, right_bottom : Int) -> Bytes {
  let w = 160
  let h = 90
  let buf = Buffer::Buffer()
  for y in 0..<h {
    for x in 0..<w {
      let bright = (x >= 70 && x < 90 && y >= 30 && y < 60) ||
        (x >= 72 && x < 78 && y >= 60 && y < left_bottom) ||
        (x >= 82 && x < 88 && y >= 60 && y < right_bottom)
      buf.write_byte(if bright { b'\xc8' } else { b'\x14' })
    }
  }
  buf.to_bytes()
}

///|
fn detector_after_warmup() -> FeetDetector {
  let det = FeetDetector::new(160, 90)
  for _ in 0..<13 {
    ignore(det.process_frame(walker_frame(60, 60)))
  }
  det
}

///|
test "feet: lowest point of each leg with correct visibility" {
  let det = detector_after_warmup()
  // left leg occupies rows up to 87 (bottom bound 88), right up to 79
  let (left, right) = det.process_frame(walker_frame(88, 80))
  inspect((left.y - 87.0 / 90.0).abs() < 0.011, content="true")
  inspect((right.y - 79.0 / 90.0).abs() < 0.011, content="true")
  inspect(left.v > 0.5, content="true")
  inspect(right.v > 0.5, content="true")
  // feet are on their own sides of the person
  inspect(left.x < right.x, content="true")
}

///|
test "feet: swing lifts the foot, stance keeps it down" {
  let det = detector_after_warmup()
  // right foot swings up 6 px (still inside the bottom region), left planted
  let (left1, _) = det.process_frame(walker_frame(88, 82))
  ignore(det.process_frame(walker_frame(88, 82)))
  let (left2, right2) = det.process_frame(walker_frame(88, 82))
  // planted foot is unchanged, swung foot is higher
  inspect(left2.y > left1.y - 0.001, content="true")
  inspect(right2.y < left1.y, content="true")
  // a foot lifted out of the bottom region is still tracked mid-swing (the
  // landing oscillation needs the swing to stay visible), just higher up
  let (left3, gone) = det.process_frame(walker_frame(88, 64))
  inspect(gone.v > 0.5, content="true")
  inspect(gone.y < left3.y, content="true")
}

///|
test "feet: empty scene reports invisible feet" {
  let det = detector_after_warmup()
  let empty = walker_frame(60, 60) // body only, legs fully up
  // let the background absorb the standing person
  for _ in 0..<40 {
    ignore(det.process_frame(empty))
  }
  let (left, right) = det.process_frame(empty)
  inspect(left.v == 0.0, content="true")
  inspect(right.v == 0.0, content="true")
}

///|
/// Photometric inverse of `walker_frame`: bright background, dark person.

///|
fn inverted(bytes : Bytes) -> Bytes {
  let buf = Buffer::Buffer()
  for i in 0..<bytes.length() {
    buf.write_byte((255 - bytes[i].to_int()).to_byte())
  }
  buf.to_bytes()
}

///|
test "feet: dark subject against bright background tracks the same feet" {
  let det = FeetDetector::new(160, 90, dark=true)
  for _ in 0..<13 {
    ignore(det.process_frame(inverted(walker_frame(60, 60))))
  }
  let (left, right) = det.process_frame(inverted(walker_frame(88, 80)))
  inspect((left.y - 87.0 / 90.0).abs() < 0.011, content="true")
  inspect((right.y - 79.0 / 90.0).abs() < 0.011, content="true")
  inspect(left.v > 0.5, content="true")
  inspect(left.x < right.x, content="true")
}

///|
/// Two walkers side by side: bodies at x[20,40) and x[110,130), legs under
/// each, y in [30,60).

///|
fn two_walker_frame(
  a_left : Int,
  a_right : Int,
  b_left : Int,
  b_right : Int,
) -> Bytes {
  let w = 160
  let h = 90
  let buf = Buffer::Buffer()
  for y in 0..<h {
    for x in 0..<w {
      let bright = (x >= 20 && x < 40 && y >= 30 && y < 60) ||
        (x >= 110 && x < 130 && y >= 30 && y < 60) ||
        (x >= 22 && x < 28 && y >= 60 && y < a_left) ||
        (x >= 32 && x < 38 && y >= 60 && y < a_right) ||
        (x >= 112 && x < 118 && y >= 60 && y < b_left) ||
        (x >= 122 && x < 128 && y >= 60 && y < b_right)
      buf.write_byte(if bright { b'\xc8' } else { b'\x14' })
    }
  }
  buf.to_bytes()
}

///|
test "feet: two separated walkers each track their own feet" {
  let det = FeetDetector::new(160, 90)
  // warmup with both standing (legs tucked)
  for _ in 0..<13 {
    ignore(det.process_frame(two_walker_frame(60, 60, 60, 60)))
  }
  // person A left foot planted (88), right lifted (78);
  // person B right foot planted (86), left lifted (74)
  let persons = det.process_frame_persons(two_walker_frame(88, 78, 74, 86))
  inspect(persons.length(), content="2")
  // left-to-right: person A first, person B second
  let (_, a_left, a_right) = persons[0]
  inspect((a_left.y - 87.0 / 90.0).abs() < 0.011, content="true")
  inspect((a_right.y - 77.0 / 90.0).abs() < 0.011, content="true")
  inspect(a_left.v > 0.5, content="true")
  inspect(a_left.x < 0.3, content="true")
  let (_, b_left, b_right) = persons[1]
  inspect((b_right.y - 85.0 / 90.0).abs() < 0.011, content="true")
  inspect((b_left.y - 73.0 / 90.0).abs() < 0.011, content="true")
  inspect(b_right.v > 0.5, content="true")
  inspect(b_left.x > 0.7, content="true")
}

///|
test "feet: single walker still yields exactly one person" {
  let det = FeetDetector::new(160, 90)
  for _ in 0..<13 {
    ignore(det.process_frame(walker_frame(60, 60)))
  }
  let persons = det.process_frame_persons(walker_frame(88, 80))
  inspect(persons.length(), content="1")
  // and the legacy single-person API agrees with the first entry
  let (legacy_left, _) = det.process_frame(walker_frame(88, 80))
  let (_, p_left, _) = persons[0]
  inspect((legacy_left.y - p_left.y).abs() < 0.0001, content="true")
}
