///|
/// Result of matching audio onsets against visual landings.

///|
pub(all) struct Alignment {
  offset_s : Double // audio = video + offset; positive means audio is late
  drift : Double // extra lag per second of video (clock drift / speed error)
  matched : Int // events paired within tolerance
  tolerance_s : Double
} derive(Debug, Eq)

///|
fn median_of(values : Array[Double]) -> Double? {
  if values.length() == 0 {
    return None
  }
  let sorted = values.copy()
  sorted.sort()
  Some(sorted[sorted.length() / 2])
}

///|
/// Estimate the offset and drift between audio onsets and visual landings.
///
/// Model: audio event time ~= video time + offset + drift * video time. A
/// constant offset covers wrong slates and shifted exports; the drift term
/// covers clock drift between recorders, PAL speedup, and wrong-rate pulls,
/// where the error grows over the take.
///
/// Candidate offsets come from every (audio - video) pair inside the search
/// bound; each candidate is scored by how many events it pairs within
/// `tolerance_s`, and the winner is refined to the median residual of its
/// pairs. Scoring rather than averaging makes the estimate immune to
/// spurious onsets (doors, music) and missed detections; the median kills
/// any remaining outlier pairs. The drift is then the two-halves median
/// slope of the residuals against video time, the offset is re-fitted at
/// that slope over the same pairs, and matches are recounted against the
/// full linear model. Slopes beyond ±10% are rejected as nonsense data.
pub fn estimate_offset(
  audio_events : Array[Double],
  video_events : Array[Double],
  tolerance_s? : Double = 0.1,
  max_search_s? : Double = 1.5,
) -> Alignment? {
  if audio_events.length() == 0 || video_events.length() == 0 {
    return None
  }
  // candidate offsets; a real pairing repeats the same difference many
  // times, noise candidates land everywhere, so the best-scored candidate
  // wins even with heavy contamination
  let candidates : Array[Double] = []
  for a in audio_events {
    for v in video_events {
      let d = a - v
      if d >= -max_search_s && d <= max_search_s {
        candidates.push(d)
      }
    }
  }
  if candidates.length() == 0 {
    return None
  }
  let mut best_d = 0.0
  let mut best_score = 0
  for d in candidates {
    let mut score = 0
    for a in audio_events {
      let mut hit = false
      for v in video_events {
        if (a - v - d).abs() <= tolerance_s {
          hit = true
          break
        }
      }
      if hit {
        score = score + 1
      }
    }
    // ties are broken toward the smaller magnitude: with a ~0.5 s stride,
    // matching every audio event to the *neighbouring* landing scores as
    // well as the true pairing (a whole-step alias), and real sync errors
    // are far smaller than a stride
    if score > best_score || (score == best_score && d.abs() < best_d.abs()) {
      best_score = score
      best_d = d
    }
  }
  if best_score == 0 {
    return None
  }
  // collect the residual and video time of the strongest pairing per audio
  // event (an audio event may sit near several video events)
  let residuals : Array[Double] = []
  let times : Array[Double] = []
  for a in audio_events {
    let mut best = 1000000000.0
    let mut best_v = 0.0
    for v in video_events {
      let r = a - v - best_d
      if r.abs() <= tolerance_s && r.abs() < best.abs() {
        best = r
        best_v = v
      }
    }
    if best.abs() <= tolerance_s {
      residuals.push(best)
      times.push(best_v)
    }
  }
  // drift: least-squares slope of residual vs video time over the matched
  // pairs (already outlier-filtered by the constant match); fewer than
  // three pairs spread over time carries no slope information. Only a slope
  // whose accumulated effect over the clip reaches half the tolerance is
  // real: jittered points always produce some slope, and resampling a clean
  // constant-offset track by ~1% because of measurement noise would damage
  // it -- one outlier onset drags the least-squares fit, so the bar is a
  // full tolerance of accumulated drift. Slopes beyond ±10% are nonsense
  // data.
  let mut drift = 0.0
  if times.length() >= 3 {
    let n = times.length().to_double()
    let mut t_mean = 0.0
    let mut r_mean = 0.0
    for k in 0..<times.length() {
      t_mean = t_mean + times[k]
      r_mean = r_mean + residuals[k]
    }
    t_mean = t_mean / n
    r_mean = r_mean / n
    let mut num = 0.0
    let mut den = 0.0
    let mut t_min = times[0]
    let mut t_max = times[0]
    for k in 0..<times.length() {
      let dt = times[k] - t_mean
      num = num + dt * (residuals[k] - r_mean)
      den = den + dt * dt
      if times[k] < t_min {
        t_min = times[k]
      }
      if times[k] > t_max {
        t_max = times[k]
      }
    }
    if den > 0.000001 {
      let slope = num / den
      let span = t_max - t_min
      if slope.abs() <= 0.1 && slope.abs() * span >= tolerance_s {
        drift = slope
      }
    }
  }
  // re-fit the constant at this slope over the same pairs: the model gives
  // per-pair offset estimates a - v - drift * v
  let offs : Array[Double] = []
  for k in 0..<times.length() {
    offs.push(residuals[k] + best_d - drift * times[k])
  }
  let final_offset = match median_of(offs) {
    Some(m) => m
    None => best_d
  }
  // recount matches against the full linear model
  let mut matched = 0
  for a in audio_events {
    let mut hit = false
    for v in video_events {
      if (a - v - final_offset - drift * v).abs() <= tolerance_s {
        hit = true
        break
      }
    }
    if hit {
      matched = matched + 1
    }
  }
  Some({ offset_s: final_offset, drift, matched, tolerance_s, })
}
