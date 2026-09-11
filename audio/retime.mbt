///|
/// Remap a track in time under the alignment model: an event heard at input
/// time `a` belongs at output time `(a - offset) / (1 + drift)`.
///
/// One interpolation pass applies both the shift and the speed correction;
/// `drift = 0` degenerates to a plain (interpolated) shift, so callers that
/// measured no meaningful drift should prefer the sample-exact `shift`
/// instead. The output is as long as the remapped input allows.
pub fn retime(
  wav : @wav.WavData,
  offset_s~ : Double,
  drift~ : Double,
) -> @wav.WavData {
  let sr = wav.sample_rate
  let ch = wav.channels
  let n_in = wav.samples.length() / ch
  let denom = 1.0 + drift
  if denom <= 0.000001 || n_in == 0 || ch < 1 || sr < 1 {
    return {
      sample_rate: wav.sample_rate,
      channels: wav.channels,
      samples: [],
    }
  }
  let dur_in = n_in.to_double() / sr.to_double()
  let dur_out = (dur_in - offset_s) / denom
  if dur_out <= 0.0 {
    return {
      sample_rate: wav.sample_rate,
      channels: wav.channels,
      samples: [],
    }
  }
  let n_out = (dur_out * sr.to_double()).round().to_int()
  let out : Array[Double] = Array::make(n_out * ch, 0.0)
  for j in 0..<n_out {
    // output time j/sr -> input position in frames
    let pos = (offset_s + denom * j.to_double() / sr.to_double()) *
      sr.to_double()
    if pos < 0.0 || pos >= n_in.to_double() - 1.0 {
      continue // outside the source: leave silence
    }
    let i0 = pos.floor().to_int()
    let frac = pos - i0.to_double()
    for c in 0..<ch {
      let a = wav.samples[i0 * ch + c]
      let b = wav.samples[(i0 + 1) * ch + c]
      out[j * ch + c] = a + (b - a) * frac
    }
  }
  { sample_rate: wav.sample_rate, channels: wav.channels, samples: out, }
}
