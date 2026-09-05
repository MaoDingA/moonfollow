# moonfollow

根据画面中脚步的落点推算 SMPTE 时码，再把脚步声音效按这些时码合成为一条与视频同步的音轨。

**项目代码 100% MoonBit**（native 后端）：从视频解码、足部跟踪、落点检测、
时码换算到音频混音全部在 MoonBit 里实现。唯一的非 MoonBit 内容是
MoonBit 官方 native FFI 约定所需的少量 C 胶水（`internal/fsio/stub.c`，
文件读写与子进程管道）；外部工具只依赖系统安装的 `ffmpeg`/`ffprobe`
二进制（视频解码与容器探测，属于运行环境而非项目代码）。

```
video.mp4 --[detect]--> foottrack.json --[steps]--> 落点时码列表
                                              +-- [render] --> footsteps.wav
```

输出的 `footsteps.wav` 拖进 DaVinci Resolve / 任何 NLE，与源片对齐片头即同步。

## 快速体验

```sh
sh examples/demo.sh          # 自包含演示：ffmpeg 合成行走视频 + 脚步声，跑通全流程
```

## 使用

```sh
# 1) 从视频提取足部轨迹（ffprobe 做 CFR 校验，ffmpeg 解码低分辨率灰度帧）
moon run cmd/moonfollow -- detect clip.mp4 -o foottrack.json

# 2) 检测落点 + 渲染音效轨（一步到位）
moon run cmd/moonfollow -- run foottrack.json --sfx step.wav -o footsteps.wav

# 或分步：先核对时码（可修剪 steps.json），再渲染
moon run cmd/moonfollow -- steps foottrack.json -o steps.json
moon run cmd/moonfollow -- render steps.json --sfx step.wav -o footsteps.wav
```

`run`/`steps` 打印每个落点的时码、左右脚、强度与帧号：

```text
clip.mp4: 9 steps at 25 fps
00:00:00:20  right  strength 1  frame 20
00:00:01:07  left   strength 1  frame 32
```

29.97/59.94 fps 的素材自动使用 drop-frame 时码（`;` 分隔），25/24/30 等
整帧率使用非丢帧格式（`:` 分隔）。输出为 16-bit PCM、默认 48 kHz、与
视频等长的音轨（末尾音效不截断，音轨可能略长于 `--duration`）。

## 算法（全部 MoonBit 实现）

- **vision/**：ffprobe 探测并拒绝可变帧率 → ffmpeg 解码为小尺寸灰度帧
  （默认 320px 宽，位置只需归一化坐标）→ **像素级时序最小值背景模型**
  （缓慢回升；触地驻留的脚不会污染背景——这正是滑动平均背景的经典败点）
  → 前景行/列直方图求人物框 → 底部三分之一区域内**按最大横向间隙分脚**，
  每只脚取其最低前景行，前景支撑密度作为可见度。
- **steps/**：落点 = "y 上升进入该帧，且未来 window 帧内无更高值"——
  即触地平台期的起始帧（脚落地后会驻留数帧，平台期是落点的本质特征；
  行量化上升沿的台阶则总有更高帧在后）。配 ±window 显著性过滤与同脚
  0.2 s 去抖。
- **timecode/**：帧号 × 有理帧率（30000/1001 等）换算 SMPTE；drop-frame
  按标准规则在非整分跳过帧编号。
- **placement/ + wav/**：纯 MoonBit 采样级混音；SFX 线性插值重采样、
  落地强度映射增益（下限 0.35）、峰值超过 0.9 时整体向下归一。

## 已知边界（v0.1）

- 单人素材；固定或缓慢移动的机位；行人需比背景亮（暗人亮景暂不支持）。
- 开头约 0.3 s（背景暖机）内的落点不检测。
- WAV 输入仅支持未压缩 PCM 16/24-bit。
- 后续项：亚帧插值、暗色行人极性、ffmpeg 直接合成视频、Resolve XML 导出。

## 开发

```sh
moon check            # 快速类型检查
moon test             # 27 个黑盒快照测试
moon fmt && moon info # 提交前格式化并刷新 .mbti 接口
```

包结构：`vision/`（解码 + 足部跟踪）、`timecode/`（SMPTE 数学）、`track/`
（轨迹模型）、`steps/`（落点检测）、`wav/`（RIFF 编解码）、`placement/`
（混音）、`internal/fsio/`（native FFI：文件 IO 与子进程管道）、
`cmd/moonfollow/`（CLI）。

**规则**：所有 MoonBit 实现代码必须遵循 `.agents/skills/` 下的官方
MoonBit skills（见 [AGENTS.md](AGENTS.md)）。

License: Apache-2.0（见 [LICENSE](LICENSE)）
