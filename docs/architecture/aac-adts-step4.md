# REC-08 第四步：AAC 保存、验证与恢复

> 当前验收状态（2026-10-14）：用户确认 AAC 设置、录音、播放、分享等各项功能真机测试通过，REC-08 已按功能验收确认关闭，见 [验收反馈](../device-feedback.md#aac-功能验收确认2026-10-14)。下文保留本步骤当时的实施证据和验证边界；待真机、进行中不代表当前功能状态。用户未提供的样本、测量或专项场景不新增通过结论。

日期：2026-10-14。AAC 已接入正式媒体验证及既有提交/恢复协议，自动化回归通过；真实麦克风文件、音频解码和中断恢复仍待 Android 真机。第五步以后未开始，REC-08 保持“进行中”。

## 媒体验证

- `AndroidRecordingMedia` 继续以 MediaExtractor / MediaCodec 完整解码，检查音轨、AAC MIME、44.1 kHz、声道和 PCM 输出，保存时长以实际解码帧数计算。
- AAC / ADTS 的 KEY_DURATION 可能是估算值，不再用于拒绝有效 AAC 文件。缺少、为零或偏差较大的元数据不会覆盖解码时长；没有实际解码音频仍失败。旧 M4A/MP3 的元数据时长核对和 150 ms 误差边界保持，正常 MP3 的采样时长核对也保持。
- 小型只读 `RecordingMediaValidation` 检查 AAC 的 ADTS 同步标识、AAC-LC/44.1 kHz 配置和每帧长度，要求最后一帧完整，不允许通过完整前缀掩盖损坏尾部。支持 7 字节普通头和 9 字节 CRC 头；不重同步、不裁剪、不复制修复文件、不修改原件。
- 旧 M4A 检查应用原生 MP4 输出的首个 ftyp box，再交给原有解码流程；AAC 与 M4A 不能仅靠相同 AAC 音轨 MIME 混用。MP3 保持原有解码与独立前缀修复路径。
- 帧边界检查只证明封装完整，音频 payload 仍需实际解码。代码规则核对了 AOSP [AACWriter](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/libstagefright/AACWriter.cpp) 的 ADTS 帧头与 [MPEG4Writer](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/libstagefright/MPEG4Writer.cpp) 的初始 ftyp 写入；未据此声称所有厂商设备已验证。

## 提交与恢复

现有 `RecordingSaveProtocol` 已按显式格式通用处理文件和草稿，本次复用其流程，未新增 AAC 专用日志、数据库迁移或重试层：

1. 后端停止并释放后，同步临时 `.aac.part` 文件并调用正式媒体验证器。
2. 验证成功记录实际时长和大小，持久化 VALIDATED，再移动为最终 `.aac` 文件并持久化 READY；fileReady 仍只表示文件就绪。
3. Flutter 完成 SQLite 事务入库后才确认清理草稿。入库失败保留可重放 READY，确认丢失按同一 ID 幂等重放，不覆盖用户标题、归属和删除状态。
4. 中断后只恢复帧边界完整、可全段解码的 AAC 文件，按中断录音提交；截断、不可解码或大小/时长不一致的文件保留原件与草稿，并报告未解决残留，不调用 MP3 修复器。
5. 取消先写 DISCARDING，再停止和删除；租约保护、取消不入库、rename/日志失败重放及草稿最后清理的保证保持。

第一步验证包现已同时复用正式录音后端和正式媒体验证器，删除了另一份解码实现。后续真机样本会走相同封装、时长和解码检查；独立包文件仍不进入正式应用索引。

## 验证证据与边界

- 新增 7 项封装/时长策略测试，检查变长帧、CRC 头、截断和垃圾尾部、格式错配、AAC 元数据估算、M4A/MP3 原核对规则及空解码拒绝。ADTS 帧夹具仅用于结构检查，不是真实 AAC 音频。
- 新增 6 项 AAC 原生提交/恢复测试，覆盖正常停止、完整中断重放、截断尾帧拒绝、取消、rename/READY 写入失败、最终文件变更；注入模拟 PCM 时长，不能替代平台音频解码。
- 新增 3 项 Flutter 回归，覆盖 AAC 事务提交前不确认、入库/确认失败后的幂等重放，以及真实 SQLite 重启后保留中断标记、实际时长和用户元数据。
- `flutter analyze --no-pub` 无问题，全量 222 项 Flutter 测试、94 项 Android JVM 测试通过；普通 debug 与独立验证 APK 构建成功。产物和检查结果见 [验证快照](../verification/rec08-aac-step4-2026-10-14.json)。
- 当前 ADB 无连接设备，未生成真实 AAC 样本，未进行平台解码、实际中断、听音、定位或 Android 安装升级验收；独立验证包运行与导出步骤见 [第一步记录](aac-adts-step1.md)。长期录音压力测试继续暂缓。

完整计划见 [AAC / ADTS 实现方案](aac-adts-plan.md)，旧保存协议的历史证据见 [保存与恢复记录](recording-save-recovery.md)。
