项目名称：moonfollow：脚步落点检测与音效时码对齐工具

项目方向：MoonBit 应用与内容工具 / 音视频后期处理

moonfollow 从视频画面中检测人物脚步的落点，推算 SMPTE 时码，并把脚步声音效合成为一条与视频同步的音轨，为影视后期补脚步声（Foley）提供自动化管线。项目面向需要为行走镜头同步音效的剪辑师、音频工具作者和视频处理开发者，提供纯 MoonBit 实现的足部跟踪、落点检测、时码换算与音频混音能力，替代逐帧人工对位。

提供纯 MoonBit 视觉管线：ffmpeg 解码低分辨率灰度帧，像素级时序最小值背景模型，前景直方图人物定位，底部区域最大横向间隙分脚；

支持并腿、交叉腿与单腿临时缺失等常见步态干扰下的稳定跟踪，可见度不足时自动降低置信度并被下游过滤；

提供“平台期起点”落点检测判据，配合显著性过滤与同脚去抖，免疫行量化噪声；

提供完整 SMPTE 时码实现，支持有理帧率与非丢帧/丢帧（29.97/59.94）双向换算与解析；

支持 ffprobe 容器探测与可变帧率（VFR）拒绝，保证帧级时码有意义；

提供纯 MoonBit 音频处理：RIFF/WAVE 编解码（PCM 16/24-bit）、逐声道线性插值重采样、落地强度映射增益、峰值归一；

提供 detect / steps / render / run 四个子命令的 CLI，中间产物为可人工核对与修剪的 JSON；

提供不少于 27 个 MoonBit 黑盒快照测试，并持续保持全部测试通过；

提供 GitHub Actions CI，覆盖类型检查、单元测试与 ffmpeg 端到端演示；

提供 README 示例与 examples/demo.sh，覆盖检测、时码列表与音轨渲染全流程。

原项目名称：无（本项目为原创项目，非移植）

本项目许可证：Apache-2.0

项目代码 100% 使用 MoonBit（native 后端）实现，ffmpeg/ffprobe 仅作为外部工具二进制调用，C 代码仅限 MoonBit 官方 FFI 规范所需的胶水（文件读写与子进程管道，约 150 行）；

使用 MoonBit 原生包结构、类型系统和快照测试方式组织代码，遵循 MoonBit 官方 agent skills 并在 AGENTS.md 中固化为仓库规则；

将文件读写与子进程等系统调用以官方 native FFI 胶水封装在 internal/fsio 包中，与算法包解耦；

以 CLI 与 JSON 文件（foottrack.json / steps.json）为主要交付接口，方便接入 NLE 工作流、脚本与后续的 DaVinci Resolve FCPXML 导出。
