# REC-08 第三步：共享原生 AAC 后端

日期：2026-10-12。共享后端和 AAC 录音能力已接入；第一步真实录音、听音和定位仍待真机。保存/恢复的 AAC 媒体验证适配留在第四步，不将本次构建或替身测试视为完整功能验收。

后续状态（2026-10-14）：第四步已接入 AAC 保存/时长验证/恢复，见 [第四步记录](aac-adts-step4.md)。本文第四步未开始及 KEY_DURATION 待适配的描述保留第三步当时边界；真实音频和真机验收仍待完成。

## 后端与会话

- `M4aRecordingBackend`、`M4aRecorder`、`AndroidM4aRecorder` 分别整理为 `AacRecordingBackend`、`AacRecorder`、`AndroidAacRecorder`，由固定的 `RecordingFormat` 选择封装。AAC 使用 `MediaRecorder.OutputFormat.AAC_ADTS`，旧 M4A 使用 `MPEG_4`；两者继续使用 MIC、AAC-LC、128 kbps、44.1 kHz 配置，声道策略保持。
- 复用原有 prepare/start/pause/resume/stop/cancel/release、同一实例和临时文件续录、状态顺序检查、短录音取消及错误后的资源清理。后端只完成录音器收尾，不移动文件、不清理草稿、不发布索引保存成功。
- `format` 固定为构造时的值，prepare 只接受对应的 `.aac.part` 或 `.m4a.part`；不能把 AAC 会话写到 M4A 路径。工厂将 AAC/M4A 交给同一个后端类型，明确验证返回格式；MP3 继续使用原后端，不回退或转换。
- AAC/M4A 的 `elapsedMs` 保持 null，继续由 `RecordingService` 的单调时钟与暂停累计计时；不增加 PCM 采集、编码队列、采样计时或线程。前台服务、串行命令及开始/停止状态发布顺序保持。
- 新录音能力列表为 AAC、MP3，MP3 不可用时仅返回 AAC。内部仍接受显式 M4A 请求、旧草稿与旧会话格式；移除产品能力列表中的 M4A 不等于删除其兼容路径。

## 设置与验证工具的衔接

现有设置页读取原生能力后即可选择 AAC，默认 AAC 可以发起原生录音；MP3 不可用的提示改为引导选择 AAC。旧 M4A 选项目前仍由枚举显示，但按能力列表禁用，正式选择器仅展示 AAC/MP3 的整理留在第五步。已保存录音的格式、文件、标题和默认偏好不因本步骤再次迁移。

第一步独立验证包也改用正式 `AacRecordingBackend(AAC)`：先写 `.aac.part`，停止释放后由验证工具重命名为 `.aac`，再独立完整解码及播放检查。因而后续真机样本将来自同一正式录音配置和生命周期实现，而非另一份 MediaRecorder 配置；其文件仍只属于独立验证包，不进入正式索引。

## 验证与剩余工作

- 14 项原后端生命周期测试按 AAC/M4A 参数化，共 28 项；覆盖同一文件续录、暂停时停止、停止/取消幂等、准备/开始/暂停/继续/停止失败、释放失败、临时数据保留及文件提交职责。新增两项测试检查 Android 输出格式选择与错误封装后端拒绝；既有格式测试改为验证 AAC 已可用及 M4A 内部兼容。
- 新增三项 Flutter 测试覆盖 AAC 默认启动、暂停 AAC 会话时改偏好保持格式、原生能力启用 AAC 并禁用新选 M4A；MP3 不可用时主动改选 AAC 的回归通过。原 M4A 会话、混合格式管理及第二步迁移继续回归。
- `flutter analyze` 无问题，全量 219 项 Flutter 测试、81 项 Android JVM 测试通过。普通 debug APK 与独立验证 APK 构建及产物证据见 [验证快照](../verification/rec08-aac-step3-2026-10-12.json)。独立包运行命令沿用 [第一步记录](aac-adts-step1.md)。
- 当前无连接 Android 设备，没有真实 ADTS 样本、暂停连续性或定位效果证据。原生测试使用替身录音器，不运行实际麦克风。
- 第四步需要适配保存和恢复中的 ADTS 时长验证：现有正式解码器仍核对媒体 KEY_DURATION，ADTS 的时长元数据可能是估算，不能据此宣称已验证 AAC 保存成功。暂不新增损坏尾帧修复，也不降低旧 M4A/MP3 的验证要求。

REC-08 保持“进行中”，第四步以后未开始。完整计划见 [AAC / ADTS 方案](aac-adts-plan.md)，格式和数据库证据见 [第二步记录](aac-adts-step2.md)。
