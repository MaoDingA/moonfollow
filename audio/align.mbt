///|
/// Result of matching audio onsets against visual landings.

///|
pub(all) struct Alignment {
  offset_s : Double // audio = video + offset; positive means audio is late
  matched : Int // events paired within tolerance
  tolerance_s : Double
} derive(Debug, Eq)

///|
/// Estimate the constant offset between audio onsets and visual landings.
///
/// Candidate offsets come from every (audio - video) pair inside the search
/// bound; each candidate is scored by how many events it pairs within
/// `tolerance_s`, and the winner is refined to the median residual of its
/// pairs. Scoring rather than averaging makes the estimate immune to
/// spurious onsets (doors, music) and missed detections; the median kills
/// any remaining outlier pairs. Only a constant offset is estimated --
/// drift/speed correction is a follow-up.
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
  let mut best_pairs : Array[Double] = []
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
  // refine: collect the residuals of the strongest pairing per audio event
  // (an audio event may sit near several video events), then take the median
  let residuals : Array[Double] = []
  for a in audio_events {
    let mut best = 1000000000.0
    for v in video_events {
      let r = a - v - best_d
      if r.abs() <= tolerance_s && r.abs() < best.abs() {
        best = r
      }
    }
    if best.abs() <= tolerance_s {
      residuals.push(best)
    }
  }
  residuals.sort()
  let refined = best_d + residuals[residuals.length() / 2]
  // recount matches at the refined offset
  let mut matched = 0
  for a in audio_events {
    let mut hit = false
    for v in video_events {
      if (a - v - refined).abs() <= tolerance_s {
        hit = true
        break
      }
    }
    if hit {
      matched = matched + 1
    }
  }
  Some({ offset_s: refined, matched, tolerance_s, })
}
