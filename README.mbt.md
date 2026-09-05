# moonfollow

根据画面中脚步的落点推算 SMPTE 时码，再把脚步声音效按这些时码合成为一条与视频同步的音轨。

```
video.mp4 --detect/foottrack.py--> foottrack.json
foottrack.json --moonfollow CLI--> 落点时码列表 (steps JSON)
steps JSON + 脚步声 WAV --moonfollow CLI--> footsteps.wav（拖进 Resolve 对齐片头即同步）
```

项目用 [MoonBit](https://www.moonbitlang.com) 实现（native 后端），核心逻辑全部在 MoonBit 里：
姿态检测是唯一的外部环节（Python + MediaPipe，只产出关键点数据）。

## 使用

### 1. 提取足部轨迹（需要 Python）

```sh
pip install -r detect/requirements.txt   # mediapipe, opencv-python
python3 detect/foottrack.py clip.mp4 -o foottrack.json
python3 detect/foottrack.py clip.mp4 --probe-only   # 只看容器信息/CFR 校验
```

脚本用 ffprobe 拒绝可变帧率（VFR）素材（VFR 下帧级时码无意义，先
`ffmpeg -i in.mp4 -vsync cfr -r 25 out.mp4` 转恒定帧率）。

### 2. 检测落点 + 合成音轨

```sh
# 一步到位：检测落点并渲染音效轨
moon run cmd/moonfollow -- run foottrack.json --sfx step.wav -o footsteps.wav

# 或分两步：先看时码列表（可人工核对/修剪），再渲染
moon run cmd/moonfollow -- steps foottrack.json -o steps.json
moon run cmd/moonfollow -- render steps.json --sfx step.wav -o footsteps.wav --rate 48000
```

`run`/`steps` 会打印每个落点的时码、左右脚、强度与帧号：

```text
clip.mp4: 10 steps at 29.97 fps (drop-frame)
00:00:00;08  left   strength 0.48  frame 8
00:00:00;21  right  strength 0.48  frame 21
```

29.97/59.94 fps 的素材自动使用 drop-frame 时码（`;` 分隔），25/24/30 等
整帧率使用非丢帧格式（`:` 分隔）。

输出的 `footsteps.wav` 为 16-bit PCM、默认 48 kHz，与视频等长（末尾
音效不会被截断，音轨可能略长于 `--duration`）。直接拖进
DaVinci Resolve 等时间线，与源片对齐片头即可同步。

## 数据格式

`foottrack.json`（检测脚本产出，坐标归一化 [0,1]，y 向下）：

```json
{
  "video": "clip.mp4", "fps": 25.0, "n_frames": 125, "width": 1920, "height": 1080,
  "frames": [
    { "i": 0, "t": 0.0,
      "left":  { "x": 0.40, "y": 0.85, "v": 0.9 },
      "right": { "x": 0.60, "y": 0.78, "v": 0.8 } }
  ]
}
```

`steps.json`（`moonfollow steps -o` 产出，`render` 的输入）：

```json
{
  "video": "clip.mp4", "fps": 25.0, "duration_s": 5.0,
  "events": [
    { "frame": 8, "time": 0.32, "foot": "left", "strength": 0.48, "timecode": "00:00:00:08" }
  ]
}
```

## 算法要点

- **落点判定**（`steps/`）：画面 y 向下，脚触地即 y 的局部极大。候选 =
  两侧相邻可见帧都严格更低的严格局部极大；再用 ±window 邻域显著性
  （峰值 − 谷值）过滤抖动，同脚 0.2 s 内去抖（保留强者）。
- **时码**（`timecode/`）：帧号 × 有理帧率（如 30000/1001）换算 SMPTE；
  drop-frame 按标准规则在非整分跳过 00/01 帧编号。
- **混音**（`placement/` + `wav/`）：纯 MoonBit 采样级叠加，SFX 线性插值
  重采样到输出采样率，落地强度映射到增益（下限 0.35），整体峰值超过
  0.9 时向下归一。

## 开发

```sh
moon check            # 快速类型检查
moon test             # 24 个黑盒快照测试
moon fmt && moon info # 提交前格式化并刷新 .mbti 接口
```

包结构：`timecode/`（SMPTE 数学）、`track/`（轨迹解析）、`steps/`（落点
检测）、`wav/`（RIFF 编解码）、`placement/`（混音）、`internal/fsio/`
（native FFI 文件读写）、`cmd/moonfollow/`（CLI）。

**规则**：所有 MoonBit 实现代码必须遵循 `.agents/skills/` 下的官方
MoonBit skills（见 [AGENTS.md](AGENTS.md)）。

## 已知边界（v0.1）

- 单人素材；MediaPipe 脚本未在真实视频上联调（本机未安装依赖）。
- WAV 输入仅支持未压缩 PCM 16/24-bit；float/compressed 需先转换。
- 亚帧精度的落点插值、ffmpeg 直接合成视频、Resolve XML 导出为后续项。
