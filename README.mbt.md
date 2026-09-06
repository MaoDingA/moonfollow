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

# 3) 交给剪辑：时码标记导入 Resolve/FCP，或直接把音效轨合成进视频
moon run cmd/moonfollow -- export steps.json -o steps.fcpxml
moon run cmd/moonfollow -- mux clip.mp4 footsteps.wav -o clip-with-steps.mp4

# 4) 原视频已有脚步声但错位？不替换，自动对齐回去
moon run cmd/moonfollow -- align wrong-sync.mp4 -o fixed.mp4
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
  → 前景行/列直方图求人物框 → 躯干列锚定 → 腿部区域内**列聚类成 blob
  分脚**，每只脚取其最低前景行，前景支撑密度作为可见度。支持**亮/暗
  双极性**：暗色行人（亮景暗人）使用时序最大值背景的镜像模型，脚部
  blob 用更严的强度阈值剔除行人拖在地上的软阴影；自动模式先跑亮色，
  亮色明显失败才切换暗色（亮主体视频在暗色模型下会产生"鬼影"轨迹，
  不能简单比较两遍得分）。
- **steps/**：落点 = "y 上升进入该帧，且未来 window 帧内无更高值"——
  即触地平台期的起始帧（脚落地后会驻留数帧，平台期是落点的本质特征；
  行量化上升沿的台阶则总有更高帧在后）。配 ±window 显著性过滤与同脚
  0.2 s 去抖；≤0.1 s 的可见度闪断（远距小脚的检测抖动）用线性插值桥接。
- **timecode/**：帧号 × 有理帧率（30000/1001 等）换算 SMPTE；drop-frame
  按标准规则在非整分跳过帧编号。
- **placement/ + wav/**：纯 MoonBit 采样级混音；SFX 线性插值重采样、
  落地强度映射增益（下限 0.35）、峰值超过 0.9 时整体向下归一。
- **audio/**：纯 MoonBit 音频脚步检测（20ms 帧能量、相对阈值、0.15s 去抖）
  与声画对齐——候选偏移按"配对数"打分、平局取更小偏移（步距混叠防呆），
  中位数残差精修；`align` 子命令提取原音轨、求偏移、采样级平移后重合成，
  保留原声音色。wav 解析兼容 ffmpeg 管道输出的流式 WAV（0xFFFFFFFF
  占位 data 长度）。
- **fcpxml/**：FCPXML 1.8 导出——视频作为单条 asset-clip，每个落点一个
  marker（有理数时间 `帧×den/num` 秒，29.97 丢帧率帧号精确），Resolve/FCP
  导入后剪辑可在时间线上逐个微调；`mux` 走 ffmpeg `-c:v copy` 不重编码
  视频，音效轨转 AAC（原视频音轨被替换）。

## 已知边界（v0.2）

- 单人素材；固定或缓慢移动的机位。检测域：**双脚需在画面内且离底边
  有上下摆动空间**（y 轴振荡是落点信号）。
- 真实素材实测（2026-09，Mixkit 四段）：常见构图恰好都压在检测域外——
  行走者脚被画框裁切、脚贴底边走（远景跟拍常见）、侧面视角（双脚水平
  重叠、无 y 摆动）、低角度硬阴影拖地。域内素材（正面/三分之三视角、
  双脚在画、静态机位）可正常工作；侧面视角需要 x 方向接触点追踪，
  列为后续项。
- 开头约 0.3 s（背景暖机）内的落点不检测。
- WAV 输入仅支持未压缩 PCM 16/24-bit。
- 后续项：侧面视角 x 接触点追踪（#5）、远距小目标追踪（#6）。

## 开发

```sh
moon check            # 快速类型检查
moon test             # 40 个黑盒快照测试
moon fmt && moon info # 提交前格式化并刷新 .mbti 接口
```

包结构：`vision/`（解码 + 足部跟踪）、`timecode/`（SMPTE 数学）、`track/`
（轨迹模型）、`steps/`（落点检测）、`wav/`（RIFF 编解码）、`placement/`
（混音）、`internal/fsio/`（native FFI：文件 IO 与子进程管道）、
`cmd/moonfollow/`（CLI）、`fcpxml/`（Resolve/FCP 标记导出）、
`audio/`（音频脚步检测与声画对齐）。

**规则**：所有 MoonBit 实现代码必须遵循 `.agents/skills/` 下的官方
MoonBit skills（见 [AGENTS.md](AGENTS.md)）。

License: Apache-2.0（见 [LICENSE](LICENSE)）
