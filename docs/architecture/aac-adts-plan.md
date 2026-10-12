# AAC / ADTS 原生输出实现计划

日期：2026-10-12。关联需求：[REC-08](../product/feature-list.md)。状态：第一步工具、第二步格式/迁移与第三步共享原生后端已实现，第一步真机待验收；第四步以后未开始。实际证据见 [第一步记录](aac-adts-step1.md)、[第二步记录](aac-adts-step2.md)与 [第三步记录](aac-adts-step3.md)，本计划不代表完整功能已验收。

## 目标与技术选择

新录音入口提供 AAC、MP3，初始默认 AAC。AAC 文件使用 AAC-LC 编码、ADTS 封装及 `.aac` 后缀。旧 M4A 文件、索引和未完成草稿保持原格式，不批量转换；MP3 实现保持。

采用 Android 原生 `MediaRecorder`，将输出封装配置为 `MediaRecorder.OutputFormat.AAC_ADTS`，编码器继续使用 `MediaRecorder.AudioEncoder.AAC`。沿用现有 44.1 kHz、128 kbps 配置，暂不改变声道策略。直接录制 ADTS，不改名伪装格式，不先录 M4A 再转换。

复用现有平台桥接、前台服务、会话状态机、暂停排除计时和保存协议。仅将现有 M4A 后端中共同的 MediaRecorder 生命周期整理为可选择封装的 AAC 后端，不增加编码依赖、通用插件框架或手写 ADTS 写入器。保留必要的格式校验、资源释放及保存失败反馈，不增加重复校验、自动格式回退或额外重试层。

## 分步骤实施

### 1. 最小录音与播放验证

- 以原生 AAC_ADTS 配置生成短 `.aac` 样本，验证实际封装、AAC 编码、完整解码及暂停/继续/停止，确认暂停期间不引入额外静音。
- 使用项目当前 `just_audio` 播放样本，检查总时长、拖动、快进/快退和倍速。核对实际依赖版本提供的 Android 提取器配置，优先经现有接口开启 ADTS 所需的按码率估算定位。
- ADTS 没有 M4A 的样本定位索引；按码率估算属于近似定位，配置码率不保证每帧长度一致。验收记录实际偏差与可用性，不承诺逐帧准确。若现有依赖没有可用配置入口，先评估最小依赖调整，验证通过后再扩大接入，不先重写播放器。
- 产出：真实样本、录音和播放验证记录，以及后续采用的播放器配置。此步骤不要求先完成产品入口或数据库迁移。

### 2. 格式定义与数据库迁移

- Dart 和 Kotlin 统一增加 `aac` 格式，映射 `.aac` / `audio/aac`；临时文件为 `recording-<id>.aac.part`，最终文件为 `recording-<id>.aac`。保留 `m4a` / `audio/mp4` 和 `mp3` / `audio/mpeg`。
- 现有 SQLite `recordings.format` 与 `recording_preferences.default_format` 均有格式 CHECK 约束，需扩展为 `m4a/mp3/aac`。从实施时的最新 schema 递增版本，按 SQLite 标准建新表、复制数据、替换旧表流程迁移，不直接修改 sqlite_master。
- 在既有迁移事务中保留所有列、索引、文件夹关联、删除状态、标题、路径及其他偏好；按项目外键配置安排表重建。失败回滚，验证各受支持旧版本的升级路径。
- 新安装默认 AAC。升级将已有 M4A 默认偏好改为 AAC，MP3 偏好保留；没有格式偏好的升级用户按新默认 AAC 初始化。未知或损坏偏好沿用现有失败处理，不用迁移掩盖错误。
- 已有录音格式与文件不改；旧 M4A 草稿或活动会话仍按原格式完成。不要把数据库中所有 `m4a` 值替换为 `aac`。
- 产出：一致的跨层格式契约、迁移及回归测试。

### 3. 复用原生后端

- 将现有 MediaRecorder 后端整理为一个简单的 AAC 后端，格式参数决定 MPEG_4（旧 M4A）或 AAC_ADTS（新 AAC）输出。
- 复用 prepare/start/pause/resume/stop/cancel/release、异常清理和同一临时文件续录行为；AAC 沿用服务时钟，不新增 PCM 采集线程或编码队列。
- 工厂按会话格式创建后端；新录音能力列表为 AAC、MP3，内部继续支持 M4A 兼容路径。会话格式在开始时固定，变更偏好不影响活动会话。
- 产出：AAC 原生录音后端和生命周期、格式选择相关原生测试。

### 4. 保存、验证与恢复

- 沿用停止收尾 → 媒体验证 → 最终文件提交 → Flutter 事务入库 → 确认清理草稿的既有协议。文件就绪事件不等于索引已保存。
- 优先复用 `MediaExtractor + MediaCodec` 的完整解码验证；AAC/M4A 音轨均为 AAC MIME，文件封装仍按真实格式区分。AAC 时长使用实际解码样本计算，不依赖 ADTS 的时长元数据，也不只按服务时钟写入保存时长。
- 恢复根据草稿的实际格式处理。可完整验证的 AAC 文件按现有规则提交为中断录音；验证失败保留残留并反馈。取消残留及入库失败重放沿用既有语义。
- 首版不新增 ADTS 损坏尾帧裁剪、帧扫描修复或所有异常均可恢复的承诺；不降低已有 M4A/MP3 验证要求。
- 产出：AAC 保存、幂等恢复、取消及入库失败回归覆盖。

### 5. 设置、显示与分享

- 新录音选择器显示 AAC、MP3；可为 AAC 添加“ADTS 文件，后缀 .aac”说明，保留下次录音生效的提示。
- 更新中英文录音格式名称与错误引导，显示实际会话格式；编码失败保留明确反馈，用户主动选择其他格式，不静默回退。
- 分享使用录音自身格式：AAC 为 `.aac` / `audio/aac`，旧 M4A 为 `.m4a` / `audio/mp4`，MP3 为 `.mp3` / `audio/mpeg`。继续使用标题命名的临时附件与现有清理流程，不转换原件。
- 产出：设置、活动会话固定格式、混合格式显示/分享测试，并回归窄屏、大字体及中英文界面。

### 6. 回归与真机验收

- 实现过程中运行受影响的定向测试；最终运行 `flutter analyze`、全量 `flutter test`、相关 Android JVM 测试及 Android debug APK 构建。迁移和保存协议跨层变更需全量回归，不以构建成功代替媒体验证。
- 真机验证极短及 1–5 分钟 AAC 录音，覆盖暂停/继续、停止/取消、锁屏/后台、播放时长、拖动、快进/快退、倍速及系统分享后的接收文件。用 `ffprobe` 等工具确认产物为 ADTS（工具可能显示格式名 `aac`）与 AAC 编码，并完整解码；仅检查后缀或 MIME 不算通过。
- 验证升级前后的 M4A/MP3 偏好、旧文件与草稿、文件夹、最近删除、主题和语言偏好；回归旧 M4A/MP3 的播放、管理与分享。覆盖 AAC 中断恢复和索引提交失败重放，记录实际可恢复边界。
- 记录设备、系统版本、参数、播放器配置和定位效果；长期压力测试继续暂缓，不新增应用录音时长限制。
- 同步需求、架构和进度，逐步记录实施证据；只有自动化检查及规定真机验收通过才将 REC-08 标为已完成。没有设备时保留待验收状态。

## 相关文档与依据

- [产品功能列表](../product/feature-list.md)、[用户流程](../product/user-flows.md)、[UI 交互设计](../product/ui-interaction-design.md)
- [录音生命周期](recording-lifecycle.md)、[保存与恢复记录](recording-save-recovery.md)、[格式设置与分享](recording-format-settings-sharing.md)、[开发进度](../development-progress.md)
- [Android MediaRecorder 输出格式](https://developer.android.com/reference/android/media/MediaRecorder.OutputFormat)：原生 AAC_ADTS 支持。
- [Android 支持的媒体格式](https://developer.android.com/media/platform/supported-formats)：AAC 与 ADTS 文件支持。
- [ExoPlayer 格式支持](https://developer.android.com/media/media3/exoplayer/supported-formats)：ADTS 播放和按码率估算定位限制；具体接入以项目实际播放器版本为准。
- [SQLite ALTER TABLE](https://www.sqlite.org/lang_altertable.html)：表结构重建流程；实施时结合现有外键及迁移事务安排操作。
