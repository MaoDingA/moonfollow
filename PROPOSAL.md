# moonfollow · 项目说明（一页）

> 仓库：<https://github.com/MaoDingA/moonfollow> · License: Apache-2.0 · 语言：MoonBit（100%）

## 一句话

从视频画面中检测脚步落点，推算 SMPTE 时码，把脚步声音效合成为一条与视频同步的音轨——为 Foley 后期补脚步声提供自动化第一步。

## 解决的真实问题

影视后期给行走镜头补脚步声（Foley）目前完全靠人工：剪辑师逐帧盯住脚接触地面的瞬间、记时码、手动摆放音效。一段几分钟的行走镜头就是上百次重复劳动，且容易在疲劳后对不齐。moonfollow 把"看画面找落点 → 算时码 → 摆音效"整条链自动化，剪辑师只需要在时间线上做最后微调。

## 方案与架构

```
video.mp4 →[detect: 解码+足部跟踪]→ foottrack.json
         →[steps: 落点检测+SMPTE时码]→ 落点列表（可人工核对/修剪）
         →[render: 采样级混音]→ footsteps.wav（拖进 NLE 对齐片头即同步）
```

项目代码全部 MoonBit（native 后端）。ffmpeg/ffprobe 仅作为外部工具二进制用于解码与容器探测；另有 MoonBit 官方 FFI 规范要求的少量 C 胶水（文件 IO 与子进程管道，约 150 行）。

## 技术亮点

- **纯 MoonBit 视觉管线**：像素级时序最小值背景模型（触地驻留的脚不会污染背景——滑动平均背景的经典败点）、前景直方图人物框、底部区域最大横向间隙分脚（对并腿/交叉腿/单腿缺失稳健）。
- **落点 = 平台期起点**的检测判据：脚落地后驻留数帧，"y 升入该帧且未来无更高帧"同时解决了尖峰判定与行量化噪声，配显著性过滤与同脚去抖。
- **SMPTE 时码完整实现**：有理帧率（30000/1001 等）、非丢帧/丢帧互转与解析，2 万帧往返扫描测试保证正逆变换互逆。
- **纯 MoonBit 音频混音**：RIFF/WAVE 编解码、逐声道线性插值重采样、落地强度→增益映射、峰值向下归一，无任何音频库依赖。
- **工程质量**：27 个黑盒快照测试；`examples/demo.sh` 用 ffmpeg 纯命令合成测试素材跑通端到端（无第三方脚本）；GitHub Actions CI 同时跑单测与端到端演示；开发全程遵循 MoonBit 官方 agent skills 并在 AGENTS.md 固化为仓库规则。

## 使用

```sh
moon run cmd/moonfollow -- detect clip.mp4 -o foottrack.json
moon run cmd/moonfollow -- run foottrack.json --sfx step.wav -o footsteps.wav
```

29.97/59.94 素材自动使用 drop-frame 时码；输出 48 kHz 16-bit PCM 音轨。

## 当前状态与边界

v0.1 已端到端可用：合成行走视频上 9/9 落点与时码全部正确、误差 ≤1 帧。已知边界：单人、机位固定或缓慢移动、行人需比背景亮；开头约 0.3 s 背景暖机期不检测。

## 后续计划（见仓库 Issues）

亚帧插值提升时码精度；暗色行人极性支持；ffmpeg 直出合成视频与 DaVinci Resolve FCPXML 导出；真实素材批量验证。
