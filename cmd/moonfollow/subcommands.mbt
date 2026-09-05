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
fn events_to_json(
  events : Array[@steps.StepEvent],
  rate : @timecode.FrameRate,
) -> Array[Json] {
  let out : Array[Json] = []
  for e in events {
    let tc = @timecode.Timecode::make(e.frame, rate~)
    out.push({
      "frame": e.frame,
      "time": e.time,
      "foot": if e.foot is Left {
        "left"
      } else {
        "right"
      },
      "strength": e.strength,
      "timecode": tc.display(),
    })
  }
  out
}

///|
/// Load a foottrack, detect landings, and print the timecode list.

///|
fn load_and_detect(
  path : String,
) -> (String, @timecode.FrameRate, Array[@steps.StepEvent], Double, String) raise {
  let text = @fsio.read_string(path)
  let track = @track.FootTrack::parse(text)
  let rate = @timecode.FrameRate::of_double(track.fps)
  let events = @steps.detect(track)
  let last = track.frames[track.frames.length() - 1]
  let duration = last.t + 1.0 / track.fps
  println(
    "\{track.video}: \{events.length()} steps at \{rate} (\{track.fps} fps source)",
  )
  for e in events {
    let tc = @timecode.Timecode::make(e.frame, rate~)
    let foot = if e.foot is Left { "left " } else { "right" }
    let display = tc.display()
    println("\{display}  \{foot}  strength \{e.strength}  frame \{e.frame}")
  }
  let doc : Json = {
    "video": track.video,
    "fps": track.fps,
    "duration_s": duration,
    "events": events_to_json(events, rate),
  }
  (track.video, rate, events, duration, doc.stringify(indent=2))
}

///|
fn render_track(
  events : Array[@steps.StepEvent],
  duration : Double,
  sfx_path : String,
  output_path : String,
  rate_str : String,
) -> Unit raise {
  let sample_rate : Int = @strconv.from_str(rate_str) catch {
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
  let width : Int = @strconv.from_str(required_value(m, "width")) catch {
    _ => fail("invalid --width")
  }
  let track = @vision.detect_track(path, width~)
  @fsio.write_string(out, @json.to_json(track).stringify())
  println(
    "wrote \{out}: \{track.n_frames} frames @ \{track.fps} fps, \{track.width}x\{track.height}",
  )
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
fn run_render(m : @argparse.Matches) -> Unit raise {
  let path = required_value(m, "steps")
  let sfx_path = required_value(m, "sfx")
  let output_path = required_value(m, "output")
  let doc : StepsDoc = @json.from_json(@json.parse(@fsio.read_string(path)))
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
      let d : Double = @strconv.from_str(text) catch {
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
