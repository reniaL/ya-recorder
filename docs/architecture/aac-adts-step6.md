# REC-08 第六步：最终回归与真机验收

> 当前验收状态（2026-10-14）：用户确认 AAC 设置、录音、播放、分享等各项功能真机测试通过，REC-08 已按功能验收确认关闭，见 [验收反馈](../device-feedback.md#aac-功能验收确认2026-10-14)。下文保留本步骤当时的实施证据和验证边界；待真机、进行中不代表当前功能状态。用户未提供的样本、测量或专项场景不新增通过结论。

日期：2026-10-14。基于 `0b9b23f` 完成最终自动化回归及普通 debug APK 构建；ADB 无连接设备，真机验收未执行。第六步及 REC-08 保持“进行中”，第一步真实录播关口仍未关闭。

## 本轮已验证

| 检查 | 结果 | 证据与边界 |
| --- | --- | --- |
| `flutter analyze --no-pub` | 无问题 | `build/aac-step6-analyze.log` |
| `flutter test --no-pub` | 全量 225 项通过 | `build/aac-step6-tests.log`，包括数据库升级、保存/恢复、设置、分享及播放控制回归 |
| `android/gradlew.bat :app:testDebugUnitTest --offline` | 94 项通过，0 失败/错误/跳过 | `build/aac-step6-jvm.log`，计数来自 `build/app/test-results/testDebugUnitTest/TEST-*.xml`；未执行平台麦克风/解码器 |
| `flutter build apk --debug --no-pub` | 成功 | `build/aac-step6-build.log`，普通应用包 |
| APK 包名与入口 | 符合预期 | `io.github.renial.ya_recorder`；MainActivity enabled，AacAdtsProbeActivity disabled；核对 APK 二进制 Manifest |
| `zipalign -c -P 16 -v 4` | Verification successful | APK ZIP 对齐检查；不代表所有 ELF 或 16 KB 真机运行验证 |
| `adb devices -l` | 无设备 | 未安装、采集音频、执行系统分享或升级 |

本轮未修改产品代码。沿用当前正式 MediaRecorder AAC-LC / AAC_ADTS、44.1 kHz、128 kbps 配置及原有声道策略。锁定 `just_audio 0.10.6`，再次核对缓存源码：`constantBitrateSeekingEnabled=true`、`constantBitrateSeekingAlwaysEnabled=false`，Android 将参数传入提取器。正式播放器仍使用依赖默认值；本地 ADTS 定位为按码率估算，实际听音位置偏差尚未测量。

## 可安装产物

- 原始输出：`build/app/outputs/flutter-apk/app-debug.apk`。
- 本轮归档：`build/rec08-aac-step6/ya-recorder-aac-debug.apk`（188330512 字节）。
- SHA-256：`efd4435c65a44897d476237908061e258bb156b231e3a88e925c2943173060b9`。
- Manifest 与 ZIP 对齐日志：`build/rec08-aac-step6/manifest.txt`、`zipalign.log`。

归档为本地构建产物，不提交 APK 或麦克风样本到 Git。普通包不会自动启动第一步录音验证页；第一步使用独立验证包和 [运行/导出工具](aac-adts-step1.md#构建与运行)。

## 原真机验收清单与证据边界

以下为第六步自动化回归时整理的清单，当时均未执行。后续用户已确认 AAC 各项功能真机测试正常，但未逐项提供以下专项场景的结果；保留操作与证据要求供补充验证，不将用户反馈改写为逐项测量报告。记录设备型号、Android/API、页大小、安装包哈希、前后版本与每项结论，附样本/报告位置；不能以自动测试或后缀检查代替。

| 项目 | 操作与通过依据 |
| --- | --- |
| 第一步录播关口 | 用独立验证包录制、暂停、继续、停止，导出报告与样本；自动检查通过后人工确认暂停处无额外静音、拖动/跳转和倍速听感。报告记录定位偏差，不能仅依据 seek 返回位置。 |
| 正式 AAC 保存 | 普通包验证立即停止、极短录音和 1–5 分钟代表性录音；暂停/继续排除暂停时长，停止后列表及重启索引唯一、时长合理，失败有明确反馈。 |
| 实际格式与解码 | 分享接收端保存原始 `.aac` 附件；用 `tools/aac-adts/inspect_sample.py` 检查 ffprobe 的 `format_name=aac`、AAC-LC/44100 Hz，并经 `ffmpeg -xerror` 完整解码。脚本命令见第一步文档。 |
| 播放控制 | 正式 AAC 总时长、拖动、±5 秒、0.75/1/1.25/1.5/2 倍速及完整播放可用；听音核对内容位置，记录近似定位偏差。 |
| 生命周期与取消 | 代表性录音期间切后台、锁屏、返回，界面与实际采集一致；录音中及暂停时取消后不新增列表项，重启不误恢复取消文件。 |
| 混合格式与分享 | AAC、旧 M4A、MP3 分别播放、重命名、移动、最近删除/恢复、分享；附件标题、扩展名、MIME 与原录音一致，默认格式变更不影响旧条目，原件不被转换。注明接收应用及版本。 |
| 偏好与旧库升级 | 在保留数据的测试设备上从升级前版本覆盖安装本轮包，分别覆盖旧 M4A 默认→AAC、旧 MP3 默认保留、无偏好→AAC；核对旧文件/草稿、标题、文件夹、最近删除、主题和语言。不得以卸载重装当作升级证据。 |
| 活动会话固定格式 | AAC 暂停后更改下次格式，继续/保存仍为 AAC；保留的旧 M4A 会话/草稿按 M4A 完成，不因偏好变化改格式。 |
| 中断恢复 | 在可控测试录音中结束进程再启动，完整可解码 AAC 才恢复为中断录音；不完整尾帧保留残留并反馈，重复启动不重复入库。旧 M4A/MP3 恢复边界保持。 |
| 索引失败重放 | 使用可控故障注入验证文件就绪后入库失败保留草稿，恢复后幂等入库、不覆盖用户元数据；当前普通 UI 不提供故障开关，本轮仅有自动化证据，设备场景仍待准备和执行。 |

长期压力测试继续暂缓，不新增录音时长限制。系统音频焦点/来电策略及任意旧索引不一致修复沿用既有未实现边界，不借本轮回归宣称已实现。

机器可读结果见 [第六步验证快照](../verification/rec08-aac-step6-2026-10-14.json)。后续用户功能验收确认与 REC-08 关闭依据见 [验收快照](../verification/rec08-aac-acceptance-2026-10-14.json)；本次自动化快照和专项证据边界保持。
