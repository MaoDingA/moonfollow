#!/bin/sh
# moonfollow end-to-end demo, self-contained except for ffmpeg + the MoonBit
# toolchain: synthesize a walking subject video and a footstep SFX with
# ffmpeg, run the full pipeline, and check the rendered track has energy at
# every detected landing.
#
# usage: examples/demo.sh [output-dir]   (default /tmp/moonfollow-demo)
set -e
cd "$(dirname "$0")/.."
OUT=${1:-/tmp/moonfollow-demo}
mkdir -p "$OUT"

# 5 s, 25 fps: a bright "person" (body + two legs) walking in place.
# Legs are sinusoidal: each lands (leg bottom 88) at t = phase + k seconds.
ffmpeg -v error -f lavfi -i "color=c=0x141414:s=160x90:r=25:d=5" \
  -vf "geq=lum='if(between(X,70,89)*between(Y,30,59),200, if(between(X,72,77)*gte(Y,60)*lt(Y,88-30*abs(sin(PI*mod(T-0.30,1)))),200, if(between(X,82,87)*gte(Y,60)*lt(Y,88-30*abs(sin(PI*mod(T-0.82,1)))),200,20)))':cb=128:cr=128" \
  -pix_fmt yuv420p -c:v libx264 "$OUT/walker.mp4" -y

# 60 ms decaying pink-noise burst as the footstep sound
ffmpeg -v error -f lavfi -i "anoisesrc=color=pink:amplitude=0.55:duration=0.06:sample_rate=48000" \
  -af "afade=t=in:st=0:d=0.002,afade=t=out:st=0.012:d=0.048" \
  -acodec pcm_s16le -ac 1 "$OUT/step.wav" -y

moon run cmd/moonfollow -- detect "$OUT/walker.mp4" -o "$OUT/foottrack.json"
moon run cmd/moonfollow -- run "$OUT/foottrack.json" --sfx "$OUT/step.wav" -o "$OUT/footsteps.wav"
moon run cmd/moonfollow -- steps "$OUT/foottrack.json" -o "$OUT/steps.json" > /dev/null
moon run cmd/moonfollow -- export "$OUT/steps.json" -o "$OUT/steps.fcpxml"
moon run cmd/moonfollow -- mux "$OUT/walker.mp4" "$OUT/footsteps.wav" -o "$OUT/walker-with-steps.mp4"

# alignment demo 1: deliberately delay the SFX track 0.4 s, then realign it
# from the video alone (all 9 onsets must pair with the 9 landings)
ffmpeg -v error -y -i "$OUT/footsteps.wav" -af "adelay=400" -acodec pcm_s16le "$OUT/delayed.wav"
moon run cmd/moonfollow -- mux "$OUT/walker.mp4" "$OUT/delayed.wav" -o "$OUT/misaligned.mp4" > /dev/null
moon run cmd/moonfollow -- align "$OUT/misaligned.mp4" -o "$OUT/realigned.mp4" | grep -q "matched 9/9" \
  || { echo "align: expected 9/9 matched onsets"; exit 1; }

# alignment demo 2: clock drift -- audio sped up 4% as if from a recorder
# running fast; a constant shift cannot fix growing error, align must
# detect the drift and speed-correct
ffmpeg -v error -y -i "$OUT/footsteps.wav" -af "atempo=1.04" -acodec pcm_s16le "$OUT/drifted.wav"
moon run cmd/moonfollow -- mux "$OUT/walker.mp4" "$OUT/drifted.wav" -o "$OUT/misaligned-drift.mp4" > /dev/null
moon run cmd/moonfollow -- align "$OUT/misaligned-drift.mp4" -o "$OUT/realigned-drift.mp4" | grep -q "speed corrected" \
  || { echo "align: expected a speed correction for the drifted track"; exit 1; }

echo "demo output in $OUT:"
echo "  walker.mp4            source video"
echo "  foottrack.json        per-frame foot positions"
echo "  footsteps.wav         synced SFX track (import alongside walker.mp4)"
echo "  steps.fcpxml          markers for Resolve/FCP import"
echo "  walker-with-steps.mp4 video with the SFX track muxed in"
echo "  realigned.mp4         0.4 s-delayed audio corrected back by \`align\`"
echo "  realigned-drift.mp4   4%-fast (clock-drift) audio speed-corrected by align"
