///|
fn build_command() -> @argparse.Command {
  let steps_cmd = @argparse.Command::Command(
    "steps",
    about="detect footstep landings and print/write their timecodes",
    positionals=[
      @argparse.PositionArg::PositionArg(
        "track",
        about="foottrack.json produced by detect/foottrack.py",
      ),
    ],
    options=[
      @argparse.OptionArg::OptionArg(
        "output",
        short='o',
        long="output",
        about="write the step list as steps JSON (otherwise print only)",
      ),
    ],
  )
  let render_cmd = @argparse.Command::Command(
    "render",
    about="mix a footstep SFX at the timecodes of a steps JSON",
    positionals=[
      @argparse.PositionArg::PositionArg(
        "steps",
        about="steps JSON written by `moonfollow steps -o`",
      ),
    ],
    options=[
      @argparse.OptionArg::OptionArg(
        "sfx",
        long="sfx",
        about="footstep sound effect (16/24-bit PCM WAV)",
        required=true,
      ),
      @argparse.OptionArg::OptionArg(
        "output",
        short='o',
        long="output",
        about="output WAV path",
        required=true,
      ),
      @argparse.OptionArg::OptionArg(
        "rate",
        long="rate",
        about="output sample rate",
        default_values=["48000"],
      ),
      @argparse.OptionArg::OptionArg(
        "duration",
        long="duration",
        about="track duration in seconds (overrides the steps JSON)",
      ),
    ],
  )
  let run_cmd = @argparse.Command::Command(
    "run",
    about="detect steps and render the SFX track in one go",
    positionals=[
      @argparse.PositionArg::PositionArg(
        "track",
        about="foottrack.json produced by detect/foottrack.py",
      ),
    ],
    options=[
      @argparse.OptionArg::OptionArg(
        "sfx",
        long="sfx",
        about="footstep sound effect (16/24-bit PCM WAV)",
        required=true,
      ),
      @argparse.OptionArg::OptionArg(
        "output",
        short='o',
        long="output",
        about="output WAV path",
        required=true,
      ),
      @argparse.OptionArg::OptionArg(
        "rate",
        long="rate",
        about="output sample rate",
        default_values=["48000"],
      ),
    ],
  )
  @argparse.Command::Command(
    "moonfollow",
    about="footstep landings -> SMPTE timecodes -> synced SFX track",
    version="0.1.0",
    subcommands=[steps_cmd, render_cmd, run_cmd],
    arg_required_else_help=true,
    subcommand_required=true,
  )
}
