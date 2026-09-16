///|
/// Burst fixture: footsteps as 60 ms loud bursts separated by silence.

///|
fn burst_track(times : Array[Double]) -> (Array[Double], Int) {
  let sr = 48000
  let samples : Array[Double] = Array::make(sr * 4, 0.0)
  for t in times {
    let start = (t * sr.to_double()).to_int()
    for i in 0..<(sr * 60 / 1000) {
      // decaying burst like a footstep slap
      let env = 1.0 - i.to_double() / (sr * 60 / 1000).to_double()
      samples[start + i] = 0.8 * env
    }
  }
  (samples, sr)
}

///|
test "onsets: bursts detected at their start times" {
  let (samples, sr) = burst_track([0.5, 1.5, 2.5, 3.5])
  let onsets = @audio.detect_onsets(samples, sr)
  inspect(onsets.length(), content="4")
  for k, want in [0.5, 1.5, 2.5, 3.5] {
    if (onsets[k].time - want).abs() > 0.03 {
      fail("onset \{k} at \{onsets[k].time}, want ~\{want}")
    }
    if onsets[k].strength <= 0.0 || onsets[k].strength > 1.0 {
      fail("strength out of range: \{onsets[k].strength}")
    }
  }
}

///|
test "onsets: digital silence yields nothing" {
  let samples : Array[Double] = Array::make(48000, 0.0)
  inspect(@audio.detect_onsets(samples, 48000).length(), content="0")
}

///|
test "onsets: min_gap debounces a double burst" {
  // two bursts 60 ms apart (echo of the same step) collapse into one onset
  let (samples, sr) = burst_track([1.0, 1.06, 2.0])
  let onsets = @audio.detect_onsets(samples, sr)
  inspect(onsets.length(), content="2")
  if (onsets[0].time - 1.0).abs() > 0.03 {
    fail("first onset at \{onsets[0].time}, want ~1.0")
  }
}

///|
test "onsets: stereo input times on the first channel" {
  let sr = 48000
  // left channel carries the bursts, right stays silent
  let (mono, _) = burst_track([0.5, 1.5])
  let stereo : Array[Double] = Array::make(mono.length() * 2, 0.0)
  for i in 0..<mono.length() {
    stereo[i * 2] = mono[i]
  }
  let onsets = @audio.detect_onsets(stereo, sr, channels=2)
  inspect(onsets.length(), content="2")
}

///|
/// Deterministic pseudo-noise: sin of an irrational-ish ramp looks like a
/// flat broadband floor at 20 ms frame granularity.

///|
fn noise_floor(n : Int, amp : Double) -> Array[Double] {
  let out : Array[Double] = Array::make(n, 0.0)
  for i in 0..<n {
    out[i] = amp * @math.sin((i.to_double() + 1.0) * 12.9898)
  }
  out
}

///|
test "onsets: steady noise floor alone yields nothing" {
  // loud flat noise (well above the global threshold relative to itself)
  // has no local excess, so the detector stays silent
  let samples = noise_floor(48000 * 4, 0.5)
  inspect(@audio.detect_onsets(samples, 48000).length(), content="0")
}

///|
test "onsets: footsteps picked out of a loud steady floor" {
  let (steps, sr) = burst_track([0.5, 1.5, 2.5, 3.5])
  let floor = noise_floor(steps.length(), 0.5)
  for i in 0..<steps.length() {
    steps[i] = steps[i] + floor[i]
  }
  let onsets = @audio.detect_onsets(steps, sr)
  inspect(onsets.length(), content="4")
  for k, want in [0.5, 1.5, 2.5, 3.5] {
    if (onsets[k].time - want).abs() > 0.03 {
      fail("onset \{k} at \{onsets[k].time}, want ~\{want}")
    }
  }
}
