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
  // a foot lifted out of the bottom region entirely is simply not reported
  let (_, gone) = det.process_frame(walker_frame(88, 64))
  inspect(gone.v == 0.0, content="true")
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
