///|
/// One step event as stored in the steps JSON.

///|
struct StepIn {
  frame : Int
  time : Double
  foot : String
  strength : Double
} derive(Debug, FromJson)

///|
/// The steps JSON document written by `moonfollow steps -o`.

///|
struct StepsDoc {
  video : String
  fps : Double
  duration_s : Double
  events : Array[StepIn]
} derive(Debug, FromJson)

///|
fn required_value(m : @argparse.Matches, name : String) -> String raise {
  match m.values.get(name) {
    Some([path, ..]) => path
    _ => fail("missing required argument --\{name}")
  }
}

///|
fn optional_value(m : @argparse.Matches, name : String) -> String? {
  match m.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn parse_foot(foot : String) -> @steps.FootSide raise {
  match foot {
    "left" => @steps.Left
    "right" => @steps.Right
    other => fail("unknown foot '\{other}' (expected left/right)")
  }
}

///|
fn load_and_detect(
  path : String,
) -> (String, @timecode.FrameRate, Array[@steps.StepEvent], Double, String) raise {
  let tracks = load_tracks(path)
  let rate = @timecode.FrameRate::of_double(tracks[0].fps)
  let events : Array[@steps.StepEvent] = []
  let mut duration = 0.0
  let mut frames_total = 0
  let mut video = tracks[0].video
  for _, track in tracks {
    for e in @steps.detect(track) {
      events.push(e)
    }
    frames_total = frames_total + track.frames.length()
    if track.frames.length() > 0 {
      let last = track.frames[track.frames.length() - 1]
      let d = last.t + 1.0 / track.fps
      if d > duration {
        duration = d
      }
    }
    video = track.video
  }
  events.sort_by((a, b) => a.time.compare(b.time))
  // frames without a single landing means detection found nothing usable:
  // refuse instead of writing an empty steps JSON / a silent SFX track
  if events.length() == 0 {
    fail(
      "\{path}: no footstep landings detected in \{frames_total} frames of track data (feet never seen landing?)",
    )
  }
  // profile view: alternate the feet (the edge signal has no foot identity)
  if tracks.length() == 1 &&
    tracks[0].frames.length() > 0 &&
    tracks[0].frames[0].right.v == 0.0 {
    let flipped : Array[@steps.StepEvent] = []
    let mut turn = false // start with the left foot
    for e in events {
      let foot = if turn { @steps.Right } else { @steps.Left }
      flipped.push({ ..e, foot, })
      turn = !turn
    }
    events.clear()
    for e in flipped {
      events.push(e)
    }
  }
  if tracks.length() > 1 {
    println(
      "\{video}: \{tracks.length()} persons, \{events.length()} steps total at \{rate}",
    )
  } else {
    println(
      "\{video}: \{events.length()} steps at \{rate} (\{tracks[0].fps} fps source)",
    )
  }
  for e in events {
    let tc = @timecode.Timecode::make(e.frame, rate~)
    let foot = if e.foot is Left { "left " } else { "right" }
    let display = tc.display()
    println("\{display}  \{foot}  strength \{e.strength}  frame \{e.frame}")
  }
  // (time, person, event) sorted by time, then rendered once
  let tagged : Array[(Double, Int, @steps.StepEvent)] = []
  for k, track in tracks {
    for e in @steps.detect(track) {
      tagged.push((e.time, k, e))
    }
  }
  tagged.sort_by((a, b) => a.0.compare(b.0))
  let out_events : Array[Json] = []
  for entry in tagged {
    let (_, k, e) = entry
    let tc = @timecode.Timecode::make(e.frame, rate~)
    let foot_str : String = if e.foot is Left { "left" } else { "right" }
    if tracks.length() > 1 {
      out_events.push({
        "frame": e.frame,
        "time": e.time,
        "foot": foot_str,
        "strength": e.strength,
        "timecode": tc.display(),
        "person": k,
      })
    } else {
      out_events.push({
        "frame": e.frame,
        "time": e.time,
        "foot": foot_str,
        "strength": e.strength,
        "timecode": tc.display(),
      })
    }
  }
  let doc : Json = {
    "video": video,
    "fps": tracks[0].fps,
    "duration_s": duration,
    "events": out_events,
  }
  (video, rate, events, duration, doc.stringify(indent=2))
}

///|
fn render_track(
  events : Array[@steps.StepEvent],
  duration : Double,
  sfx_path : String,
  output_path : String,
  rate_str : String,
) -> Unit raise {
  let sample_rate : Int = @parse.parse_int(rate_str) catch {
    _ => fail("invalid --rate \{rate_str}")
  }
  let sfx = @wav.WavData::parse(@fsio.read_bytes(sfx_path))
  let mixed = @placement.mix(events, sfx, duration, sample_rate~)
  @fsio.write_bytes(output_path, mixed.encode_pcm16())
  println(
    "wrote \{output_path}: \{events.length()} steps, \{mixed.channels} ch, \{sample_rate} Hz, \{mixed.samples.length() / mixed.channels} frames",
  )
}

///|
fn run_detect(m : @argparse.Matches) -> Unit raise {
  let path = required_value(m, "video")
  let out = required_value(m, "output")
  let width : Int = @parse.parse_int(required_value(m, "width")) catch {
    _ => fail("invalid --width")
  }
  let polarity : @vision.Polarity = if m.flags.get("dark") == Some(true) {
    @vision.Dark
  } else if m.flags.get("bright") == Some(true) {
    @vision.Bright
  } else {
    @vision.Auto
  }
  if m.flags.get("profile") == Some(true) {
    let edge = @vision.detect_edge_track(path, width~, polarity~)
    @fsio.write_string(out, @json.to_json(edge).stringify())
    println(
      "wrote \{out}: leading-edge track, \{edge.n_frames} frames @ \{edge.fps} fps",
    )
    return
  }
  if m.flags.get("multi") == Some(true) {
    let tracks = @vision.detect_tracks(path, width~, polarity~)
    @fsio.write_string(out, @json.to_json(tracks).stringify())
    if tracks.length() == 0 {
      println("wrote \{out}: 0 person tracks (nobody detected)")
    } else {
      println(
        "wrote \{out}: \{tracks.length()} person track(s) @ \{tracks[0].fps} fps, \{tracks[0].width}x\{tracks[0].height}",
      )
    }
    return
  }
  let track = @vision.detect_track(path, width~, polarity~)
  @fsio.write_string(out, @json.to_json(track).stringify())
  println(
    "wrote \{out}: \{track.n_frames} frames @ \{track.fps} fps, \{track.width}x\{track.height}",
  )
}

///|
/// Load one track or an array of per-person tracks (written by
/// `detect --multi`). The result is never empty and every track carries at
/// least one frame; anything else fails with the file named.

///|
fn load_tracks(path : String) -> Array[@track.FootTrack] raise {
  let text = @fsio.read_string(path)
  let view = text[:]
  let mut i = 0
  while i < view.length() &&
        (
          view[i] == ' ' ||
          view[i] == '\n' ||
          view[i] == '\r' ||
          view[i] == '\t'
        ) {
    i = i + 1
  }
  if i < view.length() && view[i] == '[' {
    let tracks : Array[@track.FootTrack] = @json.from_json(@json.parse(text)) catch {
      err => fail("\{path}: not a valid multi-track JSON array (\{err})")
    }
    if tracks.length() == 0 {
      fail("\{path}: track array is empty -- detect --multi found no person")
    }
    for k, track in tracks {
      if track.frames.length() == 0 {
        fail("\{path}: person track \{k} has 0 frames -- nobody was detected")
      }
    }
    tracks
  } else {
    let json = @json.parse(text) catch {
      err => fail("\{path}: not valid JSON (\{err})")
    }
    if json is Json::Object(m) && m.get("frames") is Some(Json::Array(items)) {
      if items.length() == 0 {
        fail(
          "\{path}: track has 0 frames -- nobody was detected in the source video",
        )
      }
      // an edge track's samples carry "x"; a foot track's frames carry "left"
      if items[0] is Json::Object(fm) &&
        fm.contains("x") &&
        !fm.contains("left") {
        return [
          edge_to_foot(
            @track.EdgeTrack::parse(text) catch {
              err => fail("\{path}: \{err}")
            },
          ),
        ]
      }
    }
    [@track.FootTrack::parse(text) catch { err => fail("\{path}: \{err}") }]
  }
}

///|
/// Convert a leading-edge track into a foot track the steps engine can
/// consume: the edge x plays the y role (a dwell start is the same
/// plateau-start rule). The right foot stays invisible; foot labels get
/// alternated afterwards because profile view cannot tell the feet apart.

///|
fn edge_to_foot(edge : @track.EdgeTrack) -> @track.FootTrack {
  // normalise the direction: the plateau-start rule needs the series to
  // ASCEND into each dwell, so right-to-left walks (falling edge) are
  // mirrored with y = 1 - x
  let visible : Array[Double] = []
  for s in edge.frames {
    if s.v > 0.0 {
      visible.push(s.x)
    }
  }
  let mut invert = false
  if visible.length() >= 10 {
    let half = visible.length() / 2
    let mut early = 0.0
    for k in 0..<half {
      early = early + visible[k]
    }
    let mut late = 0.0
    for k in half..<visible.length() {
      late = late + visible[k]
    }
    early = early / half.to_double()
    late = late / (visible.length() - half).to_double()
    invert = late < early
  }
  let frames : Array[@track.FrameRecord] = []
  for s in edge.frames {
    let y = if invert { 1.0 - s.x } else { s.x }
    frames.push({
      i: s.i,
      t: s.t,
      left: { x: s.x, y, v: s.v, },
      right: { x: 0.5, y: 1.0, v: 0.0, },
    })
  }
  {
    video: edge.video,
    fps: edge.fps,
    n_frames: frames.length(),
    width: edge.width,
    height: edge.height,
    frames,
  }
}

///|
fn run_steps(m : @argparse.Matches) -> Unit raise {
  let path = required_value(m, "track")
  let (_, _, _, _, json_text) = load_and_detect(path)
  match optional_value(m, "output") {
    Some(out) => {
      @fsio.write_string(out, json_text)
      println("wrote \{out}")
    }
    None => ()
  }
}

///|
/// Parse a steps JSON written by `steps -o`, naming the file on any error.

///|
fn load_steps_doc(path : String) -> StepsDoc raise {
  let json = @json.parse(@fsio.read_string(path)) catch {
    err => fail("\{path}: not a valid steps JSON (\{err})")
  }
  @json.from_json(json) catch {
    err => fail("\{path}: not a valid steps JSON (\{err})")
  }
}

///|
fn run_render(m : @argparse.Matches) -> Unit raise {
  let path = required_value(m, "steps")
  let sfx_path = required_value(m, "sfx")
  let output_path = required_value(m, "output")
  let doc : StepsDoc = load_steps_doc(path)
  let events : Array[@steps.StepEvent] = []
  for e in doc.events {
    events.push({
      frame: e.frame,
      time: e.time,
      foot: parse_foot(e.foot),
      strength: e.strength,
    })
  }
  let duration = match optional_value(m, "duration") {
    Some(text) => {
      let d : Double = @parse.parse_double(text) catch {
        _ => fail("invalid --duration \{text}")
      }
      d
    }
    None => doc.duration_s
  }
  render_track(
    events,
    duration,
    sfx_path,
    output_path,
    required_value(m, "rate"),
  )
}

///|
fn run_pipeline(m : @argparse.Matches) -> Unit raise {
  let path = required_value(m, "track")
  let sfx_path = required_value(m, "sfx")
  let output_path = required_value(m, "output")
  let (_, _, events, duration, _) = load_and_detect(path)
  render_track(
    events,
    duration,
    sfx_path,
    output_path,
    required_value(m, "rate"),
  )
}

///|
fn run_export(m : @argparse.Matches) -> Unit raise {
  let path = required_value(m, "steps")
  let out = required_value(m, "output")
  let format = match optional_value(m, "format") {
    Some(f) => f
    None => "fcpxml"
  }
  if format != "fcpxml" {
    fail("unknown --format '\{format}' (only fcpxml)")
  }
  let doc : StepsDoc = load_steps_doc(path)
  // an FCPXML with no markers is never what the caller wants; fail loudly
  // instead of writing an empty timeline (same policy as steps/run)
  if doc.events.length() == 0 {
    fail("\{path}: no step events in the steps JSON; nothing to export")
  }
  let info = @vision.probe(doc.video)
  let rate = @timecode.FrameRate::of_double(doc.fps)
  let mut total = (doc.duration_s * doc.fps).round().to_int()
  for e in doc.events {
    if e.frame + 1 > total {
      total = e.frame + 1
    }
  }
  if total < 1 {
    total = 1
  }
  let events : Array[@fcpxml.FootstepMarker] = []
  for e in doc.events {
    events.push({ frame: e.frame, foot: e.foot, strength: e.strength, })
  }
  let xml = @fcpxml.build(
    video=doc.video,
    width=info.width,
    height=info.height,
    rate~,
    total_frames=total,
    events~,
  )
  @fsio.write_string(out, xml)
  println("wrote \{out}: \{events.length()} markers at \{rate} (\{doc.video})")
}

///|
fn run_mux(m : @argparse.Matches) -> Unit raise {
  let video = required_value(m, "video")
  let wav = required_value(m, "wav")
  let out = required_value(m, "output")
  ffmpeg_mux(video, wav, out)
  println(
    "wrote \{out}: \{video} + \{wav} (video stream copied, audio re-encoded AAC; any original audio is replaced)",
  )
}

///|
/// Mux an audio track into a video with the video stream copied.

///|
fn ffmpeg_mux(video : String, wav : String, out : String) -> Unit raise {
  let proc = @fsio.spawn([
    "ffmpeg", "-v", "error", "-y", "-i", video, "-i", wav, "-map", "0:v:0", "-map",
    "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", out,
  ]) catch {
    _ => fail("ffmpeg not found on PATH (required for mux)")
  }
  // drain stdout so the pipe never blocks, then require a clean exit
  while proc.read_chunk().length() > 0 {
    ()
  }
  let status = proc.finish()
  if status != 0 {
    fail("ffmpeg exited with status \{status}")
  }
}

///|
/// Extract the video's first audio track as 48 kHz PCM WAV bytes.

///|
fn extract_audio_wav(video : String) -> Bytes raise {
  let proc = @fsio.spawn([
    "ffmpeg", "-v", "error", "-i", video, "-map", "0:a:0", "-vn", "-ar", "48000",
    "-f", "wav", "-",
  ]) catch {
    _ => fail("ffmpeg not found on PATH (required for align)")
  }
  let buf = Buffer::Buffer()
  while true {
    let chunk = proc.read_chunk()
    if chunk.length() == 0 {
      break
    }
    buf.write_bytes(chunk)
  }
  let status = proc.finish()
  if status != 0 || buf.length() == 0 {
    fail("no decodable audio track in \{video}")
  }
  buf.to_bytes()
}

///|
fn run_align(m : @argparse.Matches) -> Unit raise {
  let video = required_value(m, "video")
  let out = required_value(m, "output")
  // visual landings, sub-frame times; every person's landings, because the
  // audio track mixes everyone's footsteps -- matching a single person's
  // grid against the mix aliases to the inter-person phase shift
  let tracks = @vision.detect_tracks(video)
  let steps : Array[@steps.StepEvent] = []
  for _, track in tracks {
    for e in @steps.detect(track) {
      steps.push(e)
    }
  }
  steps.sort_by((a, b) => a.time.compare(b.time))
  if steps.length() == 0 {
    fail("no footstep landings detected in the video; nothing to align to")
  }
  let video_times : Array[Double] = steps.map(e => e.time)
  // original audio: onsets and shift target
  let wav = @wav.WavData::parse(extract_audio_wav(video)) catch {
    _ => fail("audio track is not uncompressed PCM WAV after decode")
  }
  let onsets = @audio.detect_onsets(
    wav.samples,
    wav.sample_rate,
    channels=wav.channels,
  )
  if onsets.length() == 0 {
    fail("no footstep onsets found in the audio track")
  }
  let audio_times : Array[Double] = onsets.map(o => o.time)
  match @audio.estimate_offset(audio_times, video_times) {
    None =>
      fail(
        "could not align: \{audio_times.length()} onsets vs \{video_times.length()} landings, no consistent offset",
      )
    Some(a) => {
      // confidence gate: a forced pairing of mismatched material still
      // yields an offset, but one built on few, scattered coincidences.
      // Better to refuse than to confidently apply a fake correction.
      if !a.passes_confidence_gate(audio_times.length()) {
        let limit_ms = (a.residual_limit_s() * 1000.0).round()
        let residual_ms = (a.median_abs_residual_s * 1000.0).round()
        fail(
          "could not align: matched \{a.matched}/\{audio_times.length()} onsets (needs >= 60%), median |residual| \{residual_ms} ms (allowed \{limit_ms} ms) -- audio and video look like different takes; refusing to force-sync mismatched material",
        )
      }
      // meaningful drift (>= one tolerance accumulated) needs a speed
      // correction through interpolation; otherwise the sample-exact shift
      // is strictly better
      let corrected = if a.drift == 0.0 {
        @audio.shift(wav, -a.offset_s)
      } else {
        @audio.retime(wav, offset_s=a.offset_s, drift=a.drift)
      }
      let wav_out = "\{out}.aligned.wav"
      @fsio.write_bytes(wav_out, corrected.encode_pcm16())
      ffmpeg_mux(video, wav_out, out)
      let sign = if a.offset_s >= 0.0 { "late" } else { "early" }
      println(
        "\{video}: footstep audio was \{sign} by \{a.offset_s.abs() * 1000.0} ms",
      )
      if a.drift != 0.0 {
        // ms of extra lag per minute of footage, and the recorder speed
        // error it implies
        let ms_per_min = a.drift * 60000.0
        println(
          "clock drift \{ms_per_min} ms/min (recorder ran \{if a.drift > 0.0 { "slow" } else { "fast" }} by \{a.drift.abs() * 100.0}%) -- speed corrected",
        )
      }
      println(
        "matched \{a.matched}/\{audio_times.length()} onsets to \{video_times.length()} landings; corrected track \{wav_out}; video \{out}",
      )
    }
  }
}
