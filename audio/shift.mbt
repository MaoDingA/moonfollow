///|
/// Shift a track in time by `by_s` seconds: positive delays the audio
/// (silence prepended), negative advances it (front trimmed). The output
/// keeps the input length -- the tail (or head) that falls off is replaced
/// by silence, so a shifted footstep never changes the track duration.
pub fn shift(wav : @wav.WavData, by_s : Double) -> @wav.WavData {
  let per_channel = (by_s * wav.sample_rate.to_double()).round().to_int()
  let stride = wav.channels
  let moved = per_channel * stride
  let n = wav.samples.length()
  let out : Array[Double] = Array::make(n, 0.0)
  if moved == 0 || n == 0 {
    for i in 0..<n {
      out[i] = wav.samples[i]
    }
    return {
      sample_rate: wav.sample_rate,
      channels: wav.channels,
      samples: out,
    }
  }
  if moved > 0 {
    // delay: copy what fits after the inserted silence
    let copy = if n - moved > 0 { n - moved } else { 0 }
    for i in 0..<copy {
      out[i + moved] = wav.samples[i]
    }
  } else {
    // advance: drop -moved frames from the front, pad the end with silence
    let drop = -moved
    let copy = if n - drop > 0 { n - drop } else { 0 }
    for i in 0..<copy {
      out[i] = wav.samples[i + drop]
    }
  }
  { sample_rate: wav.sample_rate, channels: wav.channels, samples: out, }
}
