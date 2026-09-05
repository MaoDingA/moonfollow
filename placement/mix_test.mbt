///|
fn click_sfx(rate : Int, frames : Int, peak : Double) -> @wav.WavData {
  let samples : Array[Double] = []
  for i in 0..<frames {
    let decay = 1.0 - i.to_double() / frames.to_double()
    samples.push(peak * decay)
  }
  { sample_rate: rate, channels: 1, samples, }
}

///|
fn event(t : Double, strength : Double) -> @steps.StepEvent {
  { frame: 0, time: t, foot: @steps.Left, strength, }
}

///|
test "mix places the sfx at each event time" {
  let sfx = click_sfx(48000, 4, 0.2)
  let out = mix([event(0.5, 1.0), event(1.0, 1.0)], sfx, 2.0)
  inspect(out.sample_rate, content="48000")
  inspect(out.channels, content="1")
  inspect(out.samples.length(), content="96000")
  // event at 0.5 s -> frame 24000, full strength, peak 0.2 -> no normalization
  inspect(out.samples[24000].to_string(), content="0.2")
  inspect(
    out.samples[24001].to_string(),
    content=(
      #|0.15000000000000002
    ),
  )
  inspect(out.samples[24003].to_string(), content="0.05")
  inspect(out.samples[23999].to_string(), content="0")
  // second event at frame 48000
  inspect(out.samples[48000].to_string(), content="0.2")
  // silence between the two effects
  inspect(out.samples[30000].to_string(), content="0")
}

///|
test "strength scales the gain with an audible floor" {
  let sfx = click_sfx(48000, 4, 0.2)
  let out = mix([event(0.5, 0.0), event(1.0, 1.0)], sfx, 2.0)
  // strength 0 -> floor 0.35; strength 1 -> full gain
  inspect(
    out.samples[24000].to_string(),
    content=(
      #|0.06999999999999999
    ),
  )
  inspect(out.samples[48000].to_string(), content="0.2")
}

///|
test "normalization attenuates overlapping events" {
  let sfx = click_sfx(48000, 4, 0.8)
  // two events 1 sample apart overlap almost fully: peak approaches 1.4
  let out = mix([event(0.5, 1.0), event(0.5 + 1.0 / 48000.0, 1.0)], sfx, 2.0)
  let mut peak = 0.0
  for sample in out.samples {
    let magnitude = sample.abs()
    if magnitude > peak {
      peak = magnitude
    }
  }
  inspect((peak > 0.89 && peak < 0.91).to_string(), content="true")
}

///|
test "resamples the sfx to the output rate" {
  // 2 samples at 24 kHz become 4 at 48 kHz with linear interpolation
  let sfx : @wav.WavData = {
    sample_rate: 24000,
    channels: 1,
    samples: [1.0, 0.0],
  }
  let out = mix(
    [event(0.0, 1.0)],
    sfx,
    0.001,
    sample_rate=48000,
    normalize=false,
  )
  inspect(out.samples[0].to_string(), content="1")
  inspect(out.samples[1].to_string(), content="0.5")
  inspect(out.samples[2].to_string(), content="0")
  inspect(out.samples[3].to_string(), content="0")
}

///|
test "track extends past the duration when an effect would be cut" {
  let sfx = click_sfx(48000, 48, 0.2) // 1 ms effect
  let out = mix([event(0.9995, 1.0)], sfx, 1.0)
  // starts at frame 47976, needs 48 frames -> 48024 total
  inspect(out.samples.length(), content="48024")
}
