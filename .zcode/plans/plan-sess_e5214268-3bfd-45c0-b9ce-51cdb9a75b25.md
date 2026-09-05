# moonfollow 实施方案

**目标**：视频 → 检测脚步落点 → 推算 SMPTE 时码 → 在对应时码合成脚步声音效。

**架构决策**（按推荐默认，未收到用户选择）：
- 检测用外部脚本（Python + MediaPipe Pose）输出每帧脚部关键点 JSON；MoonBit 承担其后全部核心逻辑（落点判定、时码、混音）。检测脚本非 MoonBit 代码，不违反项目规则。
- 首版输出**混好的脚步声音轨 WAV**（纯 MoonBit 采样级混音，与视频等长、48kHz），拖进 Resolve 对齐片头即同步；`placement` 渲染层留接口，后续可加 ffmpeg 直出、Resolve FCPXML/EDL。
- 工程规范严格遵循 `.agents/skills/moonbit-agent-guide`：`moon.mod` 新格式、`native` 后端、黑盒快照测试、`moon fmt` + `moon info` 收尾。

## 数据流水线

```
video.mp4 --detect/foottrack.py--> foottrack.json
foottrack.json --moonfollow CLI--> steps.json（落点事件+SMPTE时码）--> footsteps.wav
```

`foottrack.json` schema（坐标归一化 [0,1]）：
```json
{"video":"clip.mp4","fps":25.0,"n_frames":1234,"width":1920,"height":1080,
 "frames":[{"i":0,"t":0.0,"feet":{"L":{"x":0.5,"y":0.9,"v":0.8},"R":{"x":0.52,"y":0.88,"v":0.7}}}]}
```

## 目录结构（MoonBit，遵循官方 agent-guide 布局）

```
moonfollow/
├── moon.mod                # phenom8010/moonfollow，options: preferred-target native
├── moon.pkg                # 根 facade 包，re-export 公共类型
├── cmd/moonfollow/         # is-main 可执行入口
│   ├── moon.pkg
│   └── main.mbt            # 子命令：steps / render / run；@env.args() 解析
├── timecode/               # SMPTE 时码数学
│   ├── timecode.mbt        # Timecode 类型、frames↔HH:MM:SS:FF、NDF 与 DF（29.97/59.94 丢帧规则）
│   └── timecode_test.mbt   # 快照测试：DF 整分跳帧、parse∘format 往返、24/25/30 边界
├── track/                  # 足部轨迹模型与解析
│   ├── types.mbt           # FootTrack / FrameRecord / FootSide(L|R) / KeyPoint{x,y,v}
│   ├── parse.mbt           # @json 解析 + 校验（帧号单调、fps>0、可见性 [0,1]）
│   └── parse_test.mbt
├── steps/                  # 落点事件检测（信号处理核心）
│   ├── detect.mbt          # 每只脚独立：y 局部极大（画面坐标系脚最低点）+ 显著性阈值
│   │                       # （按身高/腿长归一）+ 同脚最小间隔 0.2s 去抖 + 可见性 ≥0.5 → 事件
│   └── detect_test.mbt     # 合成步态轨迹（正弦+落地尖峰）快照测试
├── wav/                    # WAV 读写（纯 MoonBit）
│   ├── wav.mbt             # RIFF 解析/写出；16bit PCM 读、16/24bit 与 float 读，48k 输出
│   └── wav_test.mbt        # 往返测试
├── placement/              # 混音渲染
│   ├── mix.mbt             # 事件→采样偏移，SFX 叠加（落地显著性映射增益）、峰值限幅、
│   │                       # 线性插值重采样到输出采样率、mono→stereo
│   └── mix_test.mbt
├── detect/
│   └── foottrack.py        # MediaPipe Pose（foot_index+heel 均值）；CFR 校验，VFR 拒绝
└── README.mbt.md           # 含 ```mbt check``` 可执行用法文档（链到 README.md）
```

## 关键算法

1. **落点判定**：画面 y 轴向下，脚触地 = y 局部极大。对每只脚的 y 序列找带显著性的局部极大（峰值 − 邻域谷值 ≥ 阈值，按轨迹自身的幅度 IQR 自适应），同脚间隔 <0.2s 的次峰丢弃；输出 `{frame, time_s, foot, confidence}`。v0 取整帧，预留抛物线亚帧插值接口。
2. **时码**：帧号 × 有理数 fps（30000/1001 等）→ SMPTE；29.97/59.94 按 DF 规则跳 0/1 帧编号，25/24/30 NDF。
3. **混音**：`offset = round(event_time × 48000)`，SFX 以增益叠加进等长输出轨，结束时软限幅 + 峰值归一防削波。

## CLI 形态

```
moon run cmd/moonfollow -- steps foottrack.json --fps 25        # 列出落点时码
moon run cmd/moonfollow -- render steps.json --sfx step.wav --duration 30 -o footsteps.wav
moon run cmd/moonfollow -- run foottrack.json --sfx step.wav -o footsteps.wav
```

## 实施顺序与验证

1. 脚手架：`git init`、`moon.mod`、空包骨架、CLI hello 跑通（`moon run cmd/moonfollow`）
2. `timecode` 包 + 测试 → 3. `track` 解析 + 测试 → 4. `steps` 检测 + 测试 → 5. `wav` 读写 + 测试 → 6. `placement` 混音 + 测试 → 7. CLI 串联
8. `detect/foottrack.py`；端到端验证优先用合成 foottrack.json 夹具（不依赖装 MediaPipe），真实视频联调留作可选步骤（需 `pip install mediapipe opencv-python`）
9. `README.mbt.md` 文档；每步交付前跑 `moon check`、`moon test --target native`、`moon fmt`、`moon info`

每完成一个阶段做一次 git 提交。测试全部为黑盒快照测试（`inspect()`），错误处理用 `fn main raise`。
