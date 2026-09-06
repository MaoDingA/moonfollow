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
