///|
/// Audio onset detection for footstep tracks: a footstep is a short burst
/// of energy rising out of the surroundings, so the detector frames the
/// signal (20 ms, non-overlapping), measures frame energy, and keeps
/// frames that clear both a fraction of the loudest frame and a multiple
/// of the local energy baseline. The local test is what rejects steady
/// noise (hum, hiss, traffic): a flat noise floor has no local excess no
/// matter how loud it is, while a real transient always sticks out of its
/// neighborhood.

///|
pub(all) struct Onset {
  time : Double // seconds into the track
  strength : Double // onset frame energy relative to the loudest frame, [0, 1]
} derive(Debug, Eq)

///|
/// Detect onsets in an interleaved sample buffer. `min_gap_s` debounces
/// bursts with multiple rising edges (one footstep reports once); the
/// global threshold is relative to the loudest frame so both quiet and hot
/// mixes work without tuning; `local_excess` requires a frame to exceed
/// the median energy of its +-0.3 s neighborhood by this factor, so dense
/// steady noise cannot flood the detector and alias the offset estimator.

///|
pub fn detect_onsets(
  samples : Array[Double],
  sample_rate : Int,
  channels? : Int = 1,
  frame_s? : Double = 0.02,
  threshold_ratio? : Double = 0.1,
  min_gap_s? : Double = 0.15,
  local_excess? : Double = 3.0,
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
  // +-0.3 s neighborhood, at least +-1 frame: wider than a footstep burst
  // (60 ms) and narrower than a stride, so the median lands on the floor
  // between steps
  let half = (0.3 / frame_s).round().to_int()
  let half = if half < 1 { 1 } else { half }
  let min_gap_frames = if min_gap_s / frame_s >= 1.0 {
    (min_gap_s / frame_s).round().to_int()
  } else {
    1
  }
  let mut last_kept = -min_gap_frames - 1
  for k in 0..<n_frames {
    // sharp attack: a footstep jumps out of its floor within one frame,
    // while noise amplitude wanders gradually (pink-noise swells rise
    // over dozens of frames) -- the rise test tells them apart even when
    // the swell clears the local-excess bar
    let attack = k == 0 || energy[k] >= 2.0 * energy[k - 1]
    if attack &&
      energy[k] > threshold &&
      k - last_kept >= min_gap_frames &&
      energy[k] > local_baseline(energy, k, half) * local_excess {
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
/// Median frame energy in `[k - half, k + half]` (clamped to the array):
/// the robust level of the neighborhood, insensitive to the few burst
/// frames inside the window.

///|
fn local_baseline(energy : FixedArray[Double], k : Int, half : Int) -> Double {
  let lo = if k - half < 0 { 0 } else { k - half }
  let hi = if k + half >= energy.length() {
    energy.length() - 1
  } else {
    k + half
  }
  let window : Array[Double] = []
  for j in lo..<=hi {
    window.push(energy[j])
  }
  window.sort()
  window[window.length() / 2]
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
