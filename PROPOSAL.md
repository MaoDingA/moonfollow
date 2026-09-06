项目名称：moonfollow：脚步落点检测与音效时码对齐工具

项目方向：MoonBit 应用与内容工具 / 音视频后期处理

moonfollow 从视频画面中检测人物脚步的落点，推算 SMPTE 时码，并把脚步声音效合成为一条与视频同步的音轨。项目面向需要给行走镜头补脚步声（Foley）的剪辑师与视频工具开发者，提供纯 MoonBit 实现的视频足部跟踪、落点检测、时码换算和音频混音完整管线，替代逐帧人工对位。

提供纯 MoonBit 视觉管线：ffmpeg 解码低分辨率灰度帧，像素级时序最小值背景模型（触地驻留不污染背景），前景直方图人物定位，底部区域最大横向间隙分脚（对并腿、交叉腿、单腿缺失稳健）；

提供"平台期起点"落点检测：脚落地后驻留数帧，以"y 升入该帧且未来窗口内无更高帧"判定落点，配合显著性过滤与同脚去抖，天然免疫行量化噪声；

提供完整 SMPTE 时码实现：有理帧率（30000/1001 等）、非丢帧与丢帧（29.97/59.94）双向换算与解析；

提供纯 MoonBit 音频混音：RIFF/WAVE 编解码（PCM 16/24-bit）、逐声道线性插值重采样、落地强度映射增益、峰值归一；

提供 detect / steps / render / run 四个子命令的 CLI，ffprobe 校验并拒绝可变帧率素材；

提供 27 个黑盒快照测试与 GitHub Actions CI（类型检查、单测、ffmpeg 端到端演示），examples/demo.sh 纯 ffmpeg 合成素材一键复现全流程。

本项目为原创项目，非移植。

本项目许可证：Apache-2.0

项目代码 100% MoonBit（native 后端）；ffmpeg/ffprobe 仅作为外部工具二进制用于解码与容器探测；C 代码仅限 MoonBit 官方 FFI 规范所需的胶水（文件读写与子进程管道，约 150 行）；

使用 MoonBit 原生包结构、类型系统与快照测试方式组织代码，遵循官方 agent skills 并在 AGENTS.md 固化为仓库规则；

以 CLI 与 JSON 文件为主要交付接口（foottrack.json / steps.json），便于接入 NLE 工作流、脚本与后续的 Resolve FCPXML 导出。

仓库：https://github.com/MaoDingA/moonfollow
