#!/usr/bin/env python3
"""Extract per-frame foot keypoint tracks from a video for moonfollow.

Pipeline position:

    video.mp4 --(this script)--> foottrack.json
    foottrack.json --(moon run cmd/moonfollow -- run ...)--> footsteps.wav

For every frame the script records the midpoint of each foot's heel and
foot-index landmarks (MediaPipe Pose landmarks 29/31 left, 30/32 right),
normalised to [0, 1] with y growing downward, plus the averaged visibility.
Constant frame rate is verified via ffprobe; variable-frame-rate sources are
rejected because frame-accurate timecodes are undefined on them.

Dependencies for detection: pip install mediapipe opencv-python
(ffprobe is used for probing and must be on PATH).
"""

import argparse
import json
import subprocess
import sys
from fractions import Fraction


def die(msg, code=2):
    print(f"foottrack: {msg}", file=sys.stderr)
    sys.exit(code)


def run_ffprobe(path):
    """Return {width, height, r_frame_rate, avg_frame_rate, nb_frames, duration}."""
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries",
        "stream=width,height,r_frame_rate,avg_frame_rate,nb_frames:stream_side_data=duration:format=duration",
        "-of", "json", path,
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    except FileNotFoundError:
        die("ffprobe not found on PATH (needed to read container metadata)")
    except subprocess.CalledProcessError as e:
        die(f"ffprobe failed: {e.stderr.strip()}")
    stream = json.loads(out)["streams"][0]
    return {
        "width": int(stream.get("width", 0)),
        "height": int(stream.get("height", 0)),
        "r_frame_rate": stream.get("r_frame_rate", "0/1"),
        "avg_frame_rate": stream.get("avg_frame_rate", "0/1"),
        "nb_frames": int(stream["nb_frames"]) if stream.get("nb_frames") else None,
        "duration": float(stream.get("duration") or json.loads(out).get("format", {}).get("duration", 0) or 0),
    }


def check_cfr(meta):
    r = Fraction(meta["r_frame_rate"])
    avg = Fraction(meta["avg_frame_rate"])
    if r <= 0 or avg <= 0:
        die("cannot determine a positive frame rate; is this a video file?")
    if abs(r - avg) > Fraction(1, 1000):
        die(
            f"variable frame rate suspected (r_frame_rate={r}, "
            f"avg_frame_rate={avg}); re-encode to CFR first, e.g. "
            f'ffmpeg -i in.mp4 -vsync cfr -r 25 out.mp4'
        )
    return float(r)


def probe_only(path):
    meta = run_ffprobe(path)
    fps = check_cfr(meta)
    print(json.dumps({
        "file": path,
        "width": meta["width"],
        "height": meta["height"],
        "fps": fps,
        "nb_frames": meta["nb_frames"],
        "duration_s": meta["duration"],
    }, indent=2))


def detect(path, fps):
    try:
        import cv2
        import mediapipe as mp
    except ImportError as e:
        die(f"detection needs mediapipe and opencv-python ({e}); pip install mediapipe opencv-python")

    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        die(f"cannot open {path}")
    pose = mp.solutions.pose.Pose(model_complexity=1, smooth_landmarks=True)

    def foot(lm, heel_idx, tip_idx):
        if lm is None:
            return {"x": 0.5, "y": 1.0, "v": 0.0}
        heel, tip = lm[heel_idx], lm[tip_idx]
        return {
            "x": (heel.x + tip.x) / 2,
            "y": (heel.y + tip.y) / 2,
            "v": (heel.visibility + tip.visibility) / 2,
        }

    frames = []
    i = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        result = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        lm = result.pose_landmarks.landmark if result.pose_landmarks else None
        frames.append({
            "i": i,
            "t": i / fps,
            "left": foot(lm, 29, 31),   # left heel + left foot_index
            "right": foot(lm, 30, 32),  # right heel + right foot_index
        })
        if i % 200 == 0:
            print(f"  frame {i}", file=sys.stderr)
        i += 1
    cap.release()
    pose.close()
    if not frames:
        die("no frames decoded")
    return frames


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("video", help="input video (CFR)")
    ap.add_argument("-o", "--output", help="write foottrack.json here (default: stdout)")
    ap.add_argument("--probe-only", action="store_true", help="print container info and exit")
    args = ap.parse_args()

    if args.probe_only:
        probe_only(args.video)
        return
    meta = run_ffprobe(args.video)
    fps = check_cfr(meta)
    print(f"probing ok: {meta['width']}x{meta['height']} @ {fps} fps", file=sys.stderr)
    frames = detect(args.video, fps)
    doc = {
        "video": args.video,
        "fps": fps,
        "n_frames": len(frames),
        "width": meta["width"],
        "height": meta["height"],
        "frames": frames,
    }
    text = json.dumps(doc)
    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
        print(f"wrote {args.output} ({len(frames)} frames)", file=sys.stderr)
    else:
        print(text)
    expected = meta["nb_frames"]
    if expected is not None and expected != len(frames):
        print(
            f"warning: decoded {len(frames)} frames but container reports {expected}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
