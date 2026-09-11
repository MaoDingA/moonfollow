///|
test "offset: delayed audio recovers the exact delay" {
  let video = [0.8, 1.28, 1.8, 2.28, 2.8]
  let audio = video.map(t => t + 0.4)
  match @audio.estimate_offset(audio, video) {
    Some(a) => {
      if (a.offset_s - 0.4).abs() > 0.001 {
        fail("offset \{a.offset_s}, want 0.4")
      }
      inspect(a.matched, content="5")
    }
    None => fail("no alignment found")
  }
}

///|
test "offset: spurious onsets and misses do not break the estimate" {
  let video = [0.8, 1.28, 1.8, 2.28, 2.8, 3.28, 3.8, 4.28, 4.8]
  // two audio events deleted, one door slam at a random time added
  let audio = [1.21, 1.71, 2.69, 3.21, 3.71, 4.21, 2.05]
  match @audio.estimate_offset(audio, video) {
    Some(a) => {
      if (a.offset_s - -0.07).abs() > 0.02 {
        fail("offset \{a.offset_s}, want ~-0.07")
      }
      inspect(a.matched >= 6, content="true")
    }
    None => fail("no alignment found")
  }
}

///|
test "offset: unmatchable inputs yield None" {
  let video = [0.8, 1.28, 1.8]
  inspect(@audio.estimate_offset([], video) is None, content="true")
  // audio 5 s away from every landing: outside the search bound
  inspect(@audio.estimate_offset([6.0, 7.0], video) is None, content="true")
}

///|
test "shift: delay and advance keep length and move the burst" {
  let sr = 1000
  let samples : Array[Double] = Array::make(sr, 0.0)
  // burst at 0.5 s
  for i in 500..<560 {
    samples[i] = 0.8
  }
  let wav : @wav.WavData = { sample_rate: sr, channels: 1, samples, }
  let late = @audio.shift(wav, 0.2)
  inspect(late.samples.length(), content="1000")
  inspect((late.samples[700] - 0.8).abs() < 0.001, content="true")
  inspect(late.samples[500] == 0.0, content="true")
  let early = @audio.shift(wav, -0.2)
  inspect(early.samples.length(), content="1000")
  inspect((early.samples[300] - 0.8).abs() < 0.001, content="true")
  inspect(early.samples[900] == 0.0, content="true")
  // shifting by more than the track length yields silence
  let gone = @audio.shift(wav, 2.0)
  let mut any = false
  for s in gone.samples {
    if s != 0.0 {
      any = true
    }
  }
  inspect(any, content="false")
}

///|
test "drift: clock-drifted audio recovers offset and slope" {
  // audio runs 4% fast on the recorder clock: events land early by 0.04*v
  let video = [0.8, 1.3, 1.8, 2.3, 2.8, 3.3, 3.8, 4.3, 4.8]
  let audio = video.map(v => v - 0.04 * v + 0.1)
  match @audio.estimate_offset(audio, video) {
    Some(a) => {
      if (a.offset_s - 0.1).abs() > 0.005 {
        fail("offset \{a.offset_s}, want ~0.1")
      }
      if (a.drift - -0.04).abs() > 0.005 {
        fail("drift \{a.drift}, want ~-0.04")
      }
      inspect(a.matched, content="9")
    }
    None => fail("no alignment found")
  }
}

///|
test "drift: noise below the significance gate stays constant" {
  // residuals jitter ±20 ms around a constant with no trend; any slope
  // fit is noise and must stay under the significance gate
  let video = [0.8, 1.3, 1.8, 2.3, 2.8, 3.3, 3.8, 4.3, 4.8]
  let audio = [0.9, 1.32, 1.82, 2.32, 2.78, 3.28, 3.82, 4.28, 4.78]
  match @audio.estimate_offset(audio, video) {
    Some(a) => {
      inspect(a.drift == 0.0, content="true")
      inspect(a.matched >= 8, content="true")
    }
    None => fail("no alignment found")
  }
}

///|
test "retime: drift=0 is a plain shift, drift moves a burst predictably" {
  let sr = 1000
  let samples : Array[Double] = Array::make(sr, 0.0)
  for i in 500..<560 {
    samples[i] = 0.8
  }
  let wav : @wav.WavData = { sample_rate: sr, channels: 1, samples, }
  // positive offset = audio late: the correction moves content earlier,
  // burst 0.5 s -> 0.3 s (shift() takes the negated amount, retime takes
  // the model offset directly)
  let shifted = @audio.retime(wav, offset_s=0.2, drift=0.0)
  inspect((shifted.samples[300] - 0.8).abs() < 0.01, content="true")
  // recorder 4% fast with a 0.1 s start offset: audio time 0.5 s belongs
  // at (0.5 - 0.1) / 0.96 in the corrected timeline
  let fast = @audio.retime(wav, offset_s=0.1, drift=-0.04)
  let want_pos = ((0.5 - 0.1) / 0.96 * sr.to_double()).to_int()
  let mut peak_at = -1
  for i in 0..<fast.samples.length() {
    if fast.samples[i] > 0.5 {
      peak_at = i
      break
    }
  }
  inspect((peak_at - want_pos).abs() <= 2, content="true")
}
