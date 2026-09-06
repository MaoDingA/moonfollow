///|
/// Audio onset detection for footstep tracks: a footstep is a short burst
/// of energy rising out of near-silence, so the detector frames the signal
/// (20 ms, non-overlapping), measures frame energy, and keeps rising-edge
/// frames whose energy clears a fraction of the loudest frame.

///|
pub(all) struct Onset {
  time : Double // seconds into the track
  strength : Double // onset frame energy relative to the loudest frame, [0, 1]
} derive(Debug, Eq)

///|
/// Detect onsets in an interleaved sample buffer. `min_gap_s` debounces
/// bursts with multiple rising edges (one footstep reports once); the
/// threshold is relative to the loudest frame so both quiet and hot mixes
/// work without tuning.

///|
pub fn detect_onsets(
  samples : Array[Double],
  sample_rate : Int,
  channels? : Int = 1,
  frame_s? : Double = 0.02,
  threshold_ratio? : Double = 0.1,
  min_gap_s? : Double = 0.15,
) -> Array[Onset] {
  let frame = (sample_rate.to_double() * frame_s).round().to_int()
  let onsets : Array[Onset] = []
  if frame < 1 || channels < 1 || samples.length() < frame * channels {
    return onsets
  }
  let n_frames = samples.length() / (frame * channels)
  let energy = FixedArray::make(n_frames, 0.0)
  let mut peak = 0.0
  for k in 0..<n_frames {
    let mut e = 0.0
    let base = k * frame * channels
    for i in 0..<frame {
      // one channel is enough to time a footstep; averaging all channels
      // would only scale the energy by `channels`
      let s = samples[base + i * channels]
      e = e + s * s
    }
    energy[k] = e
    if e > peak {
      peak = e
    }
  }
  if peak <= 0.000000000001 {
    return onsets // digital silence: nothing to time
  }
  let threshold = peak * threshold_ratio
  let min_gap_frames = if min_gap_s / frame_s >= 1.0 {
    (min_gap_s / frame_s).round().to_int()
  } else {
    1
  }
  let mut last_kept = -min_gap_frames - 1
  for k in 0..<n_frames {
    if energy[k] > threshold && k - last_kept >= min_gap_frames {
      onsets.push({
        time: (k * frame).to_double() / sample_rate.to_double(),
        strength: clamp01((energy[k] / peak).sqrt()),
      })
      last_kept = k
    }
  }
  onsets
}

///|
fn clamp01(x : Double) -> Double {
  if x < 0.0 {
    0.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}
