///|
/// Result of matching audio onsets against visual landings.

///|
pub(all) struct Alignment {
  offset_s : Double // audio = video + offset; positive means audio is late
  drift : Double // extra lag per second of video (clock drift / speed error)
  matched : Int // events paired within tolerance
  tolerance_s : Double
  median_abs_residual_s : Double // spread of the matched pairs around the final linear model
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
/// bound; each candidate is scored by how many events it pairs within the
/// working tolerance, and the winner is refined to the median residual of
/// its pairs. Scoring rather than averaging makes the estimate immune to
/// spurious onsets (doors, music) and missed detections; the median kills
/// any remaining outlier pairs. The drift is then the least-squares slope
/// of the residuals against video time over the same pairs, the offset is
/// re-fitted at that slope, and matches are recounted against the full
/// linear model. Slopes beyond ±10% are rejected as nonsense data. The
/// result also carries the median absolute residual of the matched pairs
/// around the final model, consumed by the confidence gate
/// (`Alignment::passes_confidence_gate`).
///
/// The working tolerance tightens itself on dense landing grids (crowds):
/// when the median inter-landing gap falls below ~2.2x the requested
/// tolerance, every onset matches some landing at nearly any candidate
/// offset and the score saturates, so pairings that only respect the
/// grid's own resolution are allowed to count. The floor is 50 ms -- about
/// one onset frame plus one video frame of combined timing precision.
pub fn estimate_offset(
  audio_events : Array[Double],
  video_events : Array[Double],
  tolerance_s? : Double = 0.1,
  max_search_s? : Double = 1.5,
) -> Alignment? {
  if audio_events.length() == 0 || video_events.length() == 0 {
    return None
  }
  let mut tolerance = tolerance_s
  let sorted_v = video_events.copy()
  sorted_v.sort()
  let gaps : Array[Double] = []
  for k in 1..<sorted_v.length() {
    let g = sorted_v[k] - sorted_v[k - 1]
    if g > 0.001 {
      // ignore duplicate landing times reported for different persons
      gaps.push(g)
    }
  }
  match median_of(gaps) {
    Some(g) => {
      let cap = 0.45 * g
      if cap < tolerance {
        tolerance = if cap < 0.05 { 0.05 } else { cap }
      }
    }
    None => ()
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
        if (a - v - d).abs() <= tolerance {
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
      if r.abs() <= tolerance && r.abs() < best.abs() {
        best = r
        best_v = v
      }
    }
    if best.abs() <= tolerance {
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
      if slope.abs() <= 0.1 && slope.abs() * span >= tolerance {
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
      if (a - v - final_offset - drift * v).abs() <= tolerance {
        hit = true
        break
      }
    }
    if hit {
      matched = matched + 1
    }
  }
  // residual concentration on the same final model: the per-audio-event
  // smallest |a - v - offset - drift * v| among the pairs that count as
  // matched, reduced to its median. A true pairing hugs the model line
  // (median near zero); a forced pairing of mismatched material spreads its
  // few coincidental hits across the tolerance band.
  let final_abs : Array[Double] = []
  for a in audio_events {
    let mut best = 1000000000.0
    for v in video_events {
      let r = (a - v - final_offset - drift * v).abs()
      if r <= tolerance && r < best {
        best = r
      }
    }
    if best <= tolerance {
      final_abs.push(best)
    }
  }
  let median_abs_residual = match median_of(final_abs) {
    Some(m) => m
    None => 0.0
  }
  Some({
    offset_s: final_offset,
    drift,
    matched,
    tolerance_s: tolerance,
    median_abs_residual_s: median_abs_residual,
  })
}

///|
/// The largest median |residual| the confidence gate accepts: the given
/// fraction of the working tolerance, never below `residual_floor_s`.
pub fn Alignment::residual_limit_s(
  self : Alignment,
  residual_factor? : Double = 0.32,
  residual_floor_s? : Double = 0.03,
) -> Double {
  let allowed = residual_factor * self.tolerance_s
  if allowed > residual_floor_s {
    allowed
  } else {
    residual_floor_s
  }
}

///|
/// Confidence gate for an alignment: enough onsets must pair, and the pairs
/// must hug the fitted line, before the estimate is trusted enough to move
/// audio. Reject when either
///
/// - fewer than `min_match_ratio` of the onsets paired (most onsets belong
///   to events the video never shows -- wrong take, or audio dominated by
///   non-footstep transients), or
/// - the median |residual| exceeds `residual_factor` of the working
///   tolerance -- a forced pairing of mismatched material scatters its few
///   coincidental hits across the tolerance band instead of hugging the
///   line. The `residual_floor_s` (30 ms) keeps dense landing grids from
///   being over-scrutinised: their adaptive tolerance already tightened to
///   the grid resolution, and 0.32x of a ~74 ms tolerance would demand more
///   precision than one audio frame plus one video frame can carry.
///
/// Calibrated so that clean pairings pass (matched ratios 1.0 down to 0.9
/// with median |residual| at frame precision, measured <= 7 ms) while
/// slow-audio-vs-fast-video (5/7 matched, median |residual| 33.3 ms on the
/// final model at tolerance 100 ms -- 0.32 x 100 = 32 ms refuses it) and
/// slow-audio-vs-profile-view (2/7) are rejected. 0.35 would let the 5/7
/// mismatch through: the refined final model concentrates the forced pairs
/// below the raw candidate-pairing residual of 40 ms.
pub fn Alignment::passes_confidence_gate(
  self : Alignment,
  onset_total : Int,
  min_match_ratio? : Double = 0.6,
  residual_factor? : Double = 0.32,
  residual_floor_s? : Double = 0.03,
) -> Bool {
  if onset_total <= 0 {
    return false
  }
  let ratio = self.matched.to_double() / onset_total.to_double()
  ratio >= min_match_ratio &&
  self.median_abs_residual_s <=
  self.residual_limit_s(residual_factor~, residual_floor_s~)
}
