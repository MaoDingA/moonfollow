///|
/// Resample interleaved samples with per-channel linear interpolation.

///|
fn resample(
  samples : Array[Double],
  channels : Int,
  from_rate : Int,
  to_rate : Int,
) -> Array[Double] {
  if from_rate == to_rate || samples.length() == 0 || channels < 1 {
    return samples
  }
  let in_frames = samples.length() / channels
  let ratio = from_rate.to_double() / to_rate.to_double()
  let out_frames = (in_frames.to_double() / ratio).ceil().to_int()
  let out : Array[Double] = []
  for frame in 0..<out_frames {
    let src = frame.to_double() * ratio
    let i = src.floor().to_int()
    let frac = src - i.to_double()
    for ch in 0..<channels {
      let cur = samples[i * channels + ch]
      let next = if i + 1 < in_frames {
        samples[(i + 1) * channels + ch]
      } else {
        cur
      }
      out.push(cur + (next - cur) * frac)
    }
  }
  out
}

///|
/// Mix a footstep sound effect at every step event, producing a track that
/// runs alongside the source video.
///
/// - the SFX is resampled to `sample_rate` (linear interpolation) and keeps
///   its own channel count;
/// - each event's gain is `base_gain` scaled by the landing strength when
///   `strength_to_gain` is on (soft steps stay audible: the scale bottoms
///   out at 0.35);
/// - when `normalize` is on, the mix is attenuated (never boosted) so its
///   peak does not exceed `target_peak`;
/// - the track is at least `duration_s` long, and extends further when an
///   event's effect would be cut off at the end.

///|
pub fn mix(
  events : Array[@steps.StepEvent],
  sfx : @wav.WavData,
  duration_s : Double,
  sample_rate? : Int = 48000,
  base_gain? : Double = 1.0,
  strength_to_gain? : Bool = true,
  normalize? : Bool = true,
  target_peak? : Double = 0.9,
) -> @wav.WavData {
  let channels = sfx.channels
  let body = resample(sfx.samples, channels, sfx.sample_rate, sample_rate)
  let sfx_frames = if channels > 0 { body.length() / channels } else { 0 }
  let duration_frames = (duration_s * sample_rate.to_double()).ceil().to_int()
  let mut total_frames = duration_frames
  for event in events {
    let start = (event.time * sample_rate.to_double()).round().to_int()
    let end = start + sfx_frames
    if end > total_frames {
      total_frames = end
    }
  }
  let mix : Array[Double] = []
  for _ in 0..<(total_frames * channels) {
    mix.push(0.0)
  }
  for event in events {
    let start = (event.time * sample_rate.to_double()).round().to_int()
    let scale = base_gain *
      (if strength_to_gain { 0.35 + 0.65 * event.strength } else { 1.0 })
    for frame in 0..<sfx_frames {
      let dst = (start + frame) * channels
      for ch in 0..<channels {
        mix[dst + ch] = mix[dst + ch] + body[frame * channels + ch] * scale
      }
    }
  }
  if normalize {
    let mut peak = 0.0
    for sample in mix {
      let magnitude = sample.abs()
      if magnitude > peak {
        peak = magnitude
      }
    }
    if peak > target_peak {
      let scale = target_peak / peak
      for i in 0..<mix.length() {
        mix[i] = mix[i] * scale
      }
    }
  }
  { sample_rate, channels, samples: mix, }
}
