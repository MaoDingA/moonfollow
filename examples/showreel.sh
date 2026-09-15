#!/usr/bin/env bash
# Build the moonfollow showreel: a ~60 s narrated demo concatenating the
# demo scenarios with Chinese caption bars and title cards.
#
# Requires: ffmpeg (with overlay/concat), swiftc (macOS, for examples/mktext.swift
# text rendering -- the local ffmpeg build has no drawtext), and the demo
# outputs (run examples/demo.sh first if /tmp/moonfollow-demo is missing).
#
# Usage: examples/showreel.sh [outdir]     -> outdir/showreel.mp4
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${1:-/tmp/moonfollow-demo}
mkdir -p "$OUT"
W=1280
H=720
BAR_H=96
BG='#0f1115'
FG='#e8eaf0'
DIM='#9aa3b2'
ACC='#f5c542'

if [ ! -f "$OUT/walker-with-steps.mp4" ]; then
  echo "== demo outputs missing, running examples/demo.sh first =="
  examples/demo.sh "$OUT"
fi

# ---------------------------------------------------------------- text tool
# ffmpeg here has no drawtext (no freetype), so captions are pre-rendered
# PNGs from mktext.swift via CoreText; binary cached in /tmp.
MKTEXT=/tmp/mktext-showreel
if [ ! -x "$MKTEXT" ] || [ examples/mktext.swift -nt "$MKTEXT" ]; then
  swiftc -O examples/mktext.swift -o "$MKTEXT"
fi
txt() { # txt <out.png> <WxH> <size> <color> <bg> <x> <y> <text...>
  "$MKTEXT" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${@:8}"
}

GFX=$OUT/showreel-gfx
rm -rf "$GFX"; mkdir -p "$GFX"
SEG=$OUT/showreel-segs
rm -rf "$SEG"; mkdir -p "$SEG"

# ---------------------------------------------------------------- 6) irregular
# slow (1.6 s stride) -> standing pause -> fast (0.5 s stride), shell-only.
irr_lum() { # stride right_phase
  echo "if(between(X,70,89)*between(Y,30,59),200, if(between(X,72,77)*gte(Y,60)*lt(Y,88-30*abs(sin(PI*mod(T-0.30,$1)/$1))),200, if(between(X,82,87)*gte(Y,60)*lt(Y,88-30*abs(sin(PI*mod(T-$2,$1)/$1))),200,20)))"
}
irr_clip() { # file dur stride phase
  ffmpeg -v error -y -f lavfi -i "color=c=0x141414:s=160x90:r=25:d=$2" \
    -vf "geq=lum='$(irr_lum "$3" "$4")':cb=128:cr=128" \
    -pix_fmt yuv420p -c:v libx264 "$GFX/$1" 2>/dev/null
}
if [ ! -f "$OUT/irregular-with-steps.mp4" ]; then
  irr_clip irr-a.mp4 3.2 1.6 1.12
  irr_clip irr-b.mp4 1.6 1000000 1000000.52   # stride never completes: standing
  irr_clip irr-c.mp4 2.6 0.5 0.32
  printf "file '%s/irr-a.mp4'\nfile '%s/irr-b.mp4'\nfile '%s/irr-c.mp4'\n" "$GFX" "$GFX" "$GFX" > "$GFX/irr.txt"
  ffmpeg -v error -y -f concat -safe 0 -i "$GFX/irr.txt" -c:v libx264 -pix_fmt yuv420p "$OUT/walker-irregular.mp4"
  moon run cmd/moonfollow -- detect "$OUT/walker-irregular.mp4" -o "$OUT/irregular-track.json" > /dev/null
  moon run cmd/moonfollow -- run "$OUT/irregular-track.json" --sfx "$OUT/step.wav" -o "$OUT/irregular-steps.wav" > /dev/null
  moon run cmd/moonfollow -- mux "$OUT/walker-irregular.mp4" "$OUT/irregular-steps.wav" -o "$OUT/irregular-with-steps.mp4"
fi

# ---------------------------------------------------------------- captions
card() { # card <name.png> <title> <subtitle>  (writes into $GFX)
  txt "$GFX/$1" ${W}x${H} 96 "$FG" "$BG" c 280 "$2"
  # transparent overlay so it does not cover the title layer
  txt "$GFX/${1%.png}-sub.png" ${W}x${H} 36 "$DIM" none c 430 "$3"
}
bar() { # bar <name.png> <text>  (writes into $GFX)
  txt "$GFX/$1" ${W}x${BAR_H} 38 "$FG" "$BG" c c "$2"
}

card title.png "moonfollow" "画面脚步 → SMPTE 时码 → 同步脚步声，全 MoonBit 实现"
card s1.png "① 自动配音" "无声视频 → 检测脚步落点 → 按时码合成脚步声"
card s2.png "② 错位修正" "声音对不上画面？一步修正"
card s3.png "③ 时钟漂移修正" "录音与视频时钟不一致？双参数修正"
card s4.png "④ 多人" "两人分开走，逐人分割跟踪"
card s5.png "⑤ 侧面视角" "没有脚起脚落，也能检测"
card s6.png "⑥ 不规律脚步" "步距乱跳 + 中途停顿"
card end.png "github.com/MaoDingA/moonfollow" "100% MoonBit · 48 tests · 20 fixtures · CI green"
bar b1.png "9 步落地逐帧对上 —— 检测·时码·混音全在 MoonBit"
bar b2a.png "脚步声被故意延迟 0.4 秒：踩点错位"
bar b2b.png "align 一步修正：偏移归零，每步踩上"
bar b3a.png "录音时钟快 4%：偏差 60 → 200 ms 越走越错"
bar b3b.png "偏移 + 漂移双参数修正：声音贴回脚步"
bar b4.png "两人各自跟踪：两倍步数混成一条音轨"
bar b5.png "侧面没有上下摆动 —— 用『跃进→驻留』找落点"
bar b6.png "慢走 → 停顿 → 快走：不发明脚步，也不漏"

# ---------------------------------------------------------------- segments
enc="-c:v libx264 -crf 20 -pix_fmt yuv420p -r 25 -c:a aac -ar 48000 -ac 2"

card_seg() { # card_seg <file> <title.png> <dur>
  ffmpeg -v error -y -loop 1 -i "$GFX/$2" -loop 1 -i "$GFX/${2%.png}-sub.png" \
    -f lavfi -i "anullsrc=r=48000:cl=stereo" \
    -filter_complex "[0:v][1:v]overlay=0:0[v]" -map "[v]" -map 2:a -t "$3" \
    $enc "$SEG/$1"
}
vid_seg() { # vid_seg <file> <src.mp4> <bar.png> <dur>
  ffmpeg -v error -y -i "$OUT/$2" -loop 1 -i "$GFX/$3" \
    -filter_complex "[0:v]scale=$W:$H:force_original_aspect_ratio=decrease:flags=neighbor,pad=$W:$H:(ow-iw)/2:(oh-ih)/2:color=0x0f1115[b];[b][1:v]overlay=0:$((H-BAR_H))[v]" \
    -map "[v]" -map 0:a -t "$4" \
    $enc "$SEG/$1"
}

i=0
add() { printf "file '%s'\n" "$1" >> "$SEG/list.txt"; i=$((i+1)); }
: > "$SEG/list.txt"

card_seg 01-title.mp4 title.png 4;                  add 01-title.mp4
card_seg 02-s1.mp4     s1.png 2;                    add 02-s1.mp4
vid_seg   03-auto.mp4  walker-with-steps.mp4 b1.png 5;   add 03-auto.mp4
card_seg 04-s2.mp4     s2.png 2;                    add 04-s2.mp4
vid_seg   05-mis.mp4   misaligned.mp4        b2a.png 5; add 05-mis.mp4
vid_seg   06-fix.mp4   realigned.mp4         b2b.png 5; add 06-fix.mp4
card_seg 07-s3.mp4     s3.png 2;                    add 07-s3.mp4
vid_seg   08-mis.mp4   misaligned-drift.mp4  b3a.png 5; add 08-mis.mp4
vid_seg   09-fix.mp4   realigned-drift.mp4   b3b.png 5; add 09-fix.mp4
card_seg 10-s4.mp4     s4.png 2;                    add 10-s4.mp4
vid_seg   11-two.mp4   two-with-steps.mp4    b4.png 5; add 11-two.mp4
card_seg 12-s5.mp4     s5.png 2;                    add 12-s5.mp4
vid_seg   13-prof.mp4  profile-with-steps.mp4 b5.png 6; add 13-prof.mp4
card_seg 14-s6.mp4     s6.png 2;                    add 14-s6.mp4
vid_seg   15-irr.mp4   irregular-with-steps.mp4 b6.png 5; add 15-irr.mp4
card_seg 16-end.mp4    end.png 5;                   add 16-end.mp4

ffmpeg -v error -y -f concat -safe 0 -i "$SEG/list.txt" -c copy "$OUT/showreel.mp4"
echo "showreel written: $OUT/showreel.mp4 ($i segments)"
