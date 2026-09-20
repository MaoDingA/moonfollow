///|
/// moonfollow: footstep landings -> SMPTE timecodes -> synced SFX track.
/// Run with `moon run cmd/moonfollow -- <subcommand> ...` from the project root.
fn main {
  let root = build_command()
  let args = @env.args()
  try {
    let matches = root.parse(argv=args[1:])
    match matches.subcommand {
      Some(("detect", m)) => run_detect(m)
      Some(("steps", m)) => run_steps(m)
      Some(("render", m)) => run_render(m)
      Some(("run", m)) => run_pipeline(m)
      Some(("export", m)) => run_export(m)
      Some(("mux", m)) => run_mux(m)
      Some(("align", m)) => run_align(m)
      _ => println(root.render_help())
    }
  } catch {
    err => fatal(err)
  }
}

///|
/// Collapse an error's display text into the one line a CLI user should
/// see: `fail` bakes "<source location> FAILED: " into its message, and
/// argparse errors carry the whole usage text after a newline.

///|
fn error_line(err : Error) -> String {
  let text = match err {
    Failure(full) =>
      match full.split_once(" FAILED: ") {
        Some((_, message)) => message.to_owned()
        None => full
      }
    other => "\{other}"
  }
  let line = match text.split_once("\n") {
    Some((first, _)) => first.to_owned()
    None => text
  }
  // argparse messages already start with "error: "; don't double it
  match line[:].strip_prefix("error: ") {
    Some(rest) => rest.trim().to_owned()
    None => line
  }
}

///|
/// Report `err` on stderr as a single readable line and exit nonzero: no
/// stack trace, no panic output. Every CLI failure path funnels through
/// here.

///|
fn fatal(err : Error) -> Unit {
  @fsio.eprint("moonfollow: error: \{error_line(err)}\n")
  @fsio.exit(1)
}
