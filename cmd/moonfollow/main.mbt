///|
/// moonfollow: footstep landings -> SMPTE timecodes -> synced SFX track.
/// Run with `moon run cmd/moonfollow -- <subcommand> ...` from the project root.
fn main raise {
  let root = build_command()
  let args = @env.args()
  let matches = root.parse(argv=args[1:])
  match matches.subcommand {
    Some(("detect", m)) => run_detect(m)
    Some(("steps", m)) => run_steps(m)
    Some(("render", m)) => run_render(m)
    Some(("run", m)) => run_pipeline(m)
    Some(("export", m)) => run_export(m)
    Some(("mux", m)) => run_mux(m)
    _ => println(root.render_help())
  }
}
