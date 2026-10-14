# REC-08 第一步：最小录音与播放验证

> 当前验收状态（2026-10-14）：用户确认 AAC 设置、录音、播放、分享等各项功能真机测试通过，REC-08 已按功能验收确认关闭，见 [验收反馈](../device-feedback.md#aac-功能验收确认2026-10-14)。下文保留本步骤当时的实施证据和验证边界；待真机、进行中不代表当前功能状态。用户未提供的样本、测量或专项场景不新增通过结论。

日期：2026-10-12。验证工具已实现，真实设备结果待验证。此步骤不修改正式录音格式、数据库或保存协议，也不开放 AAC 产品入口。

后续状态：第二步格式/迁移和第三步共享后端已实现，见 [第二步记录](aac-adts-step2.md)与 [第三步记录](aac-adts-step3.md)。本验证包现已复用正式 AAC 后端，使用 .aac.part 临时文件并在停止释放后重命名为 .aac。本文历史范围及“第二步以后未开始”描述保留第一步当时状态；其真实录音和听音关口仍未通过。

后续状态（2026-10-14）：第四步已适配正式 AAC 验证器，验证包复用该完整解码和帧边界检查，移除重复解码逻辑，见 [第四步记录](aac-adts-step4.md)。下文 KEY_DURATION 待适配描述保留历史边界，实际设备关口仍待通过。

## 实现与配置

- 调试源码 `AacAdtsProbeActivity` 直接使用 `MediaRecorder` 的 MIC / AAC_ADTS / AAC、44.1 kHz、128 kbps 配置；保持原有声道策略。自动执行录音 4 秒、暂停 2 秒、继续 4 秒、停止；文件写入验证包私有目录，不进入普通录音索引。
- 调试验证器检查 ADTS 首帧标识及 AAC-LC profile，再用 `MediaExtractor + MediaCodec` 从头解码到末尾，以 PCM 样本数计算时长。与有效录音时长比较，容许 500 ms 的收尾/编码差异；不依赖 ADTS 的估算时长元数据。检查不替代听音，也不执行尾帧修复。
- Flutter 验证页使用项目锁定的 `just_audio 0.10.6`，显式传入 `ProgressiveAudioSourceOptions(androidExtractorOptions: AndroidExtractorOptions(constantBitrateSeekingEnabled: true))`。本地依赖源码确认 Dart 参数默认值及 Android `DefaultExtractorsFactory` 默认均已为 true，无需升级依赖或修改正式播放器。`constantBitrateSeekingAlwaysEnabled` 保持 false，本地文件长度已知。
- 自动测量播放器总时长、暂停状态下 0%/50%/10%/90% 定位，以及 0.75×、1×、1.25×、1.5×、2× 的音频进度推进，最后完整播放至完成。播放器时长与解码时长容许 1000 ms 差异，定位返回位置及倍速进度容许 500 ms 差异；这些是本步骤的检查阈值，不是定位精度承诺。
- 验证页提供播放/暂停、拖动、±5 秒和倍速按钮。需人工听数数内容，确认暂停处无额外 2 秒静音、前后跳转符合内容位置、倍速可听；点击“听音通过/失败”后结果写回报告。自动返回位置只能证明 API 响应，不能证明实际音频准确定位。
- 验证包使用独立应用 ID `io.github.renial.ya_recorder.aacprobe`，名称 `AAC ADTS Probe`，可与普通应用并存。只有显式设置 Gradle 属性 `aacAdtsProbe=true` 的 debug 包启用验证入口；普通 debug 禁用该 Activity，profile/release 不含其源码。工具仅在前台录音，保持屏幕点亮；离开页面中止采集，后台和锁屏验收留在第六步。

## 构建与运行

在仓库根目录执行（`flutter` 在 PATH；`adb` 不在 PATH 时显式指定）：

```powershell
python tools/aac-adts/run_device.py --build-only
python tools/aac-adts/run_device.py --skip-build --adb D:/data/app/android_sdk/platform-tools/adb.exe
```

第一条命令显式传入 `-PaacAdtsProbe=true` 并使用 `tools/aac-adts/probe.dart` 作为入口，核对独立包名后生成 `build/aac-adts-probe/aac-adts-probe-debug.apk`。构建成功不代表录音通过。

第二条命令要求一台已授权 Android 设备（多设备使用 `--serial`），安装独立包、授权麦克风、启动前台验证页，并等待报告。录音时分别说出 1–4 和 5–8，暂停期间说话不应录入；操作全程保持页面在前台。也可自行安装归档 APK，从 `AAC ADTS Probe` 图标启动；页面自动开始一次验证。

脚本将真实样本和报告导出到 `build/aac-adts-probe/`。自动检查失败时退出非零；报告的 `listeningCheck` 初始为 pending，自动通过不表示人工验收完成。听音确认后重新导出（不会重录）：

```powershell
python tools/aac-adts/run_device.py --export-only --adb D:/data/app/android_sdk/platform-tools/adb.exe
```

使用已有 FFmpeg 工具对导出的真实样本做独立检查，不转换文件：

```powershell
python tools/aac-adts/inspect_sample.py build/aac-adts-probe/sample-<实际编号>.aac --ffprobe <ffprobe.exe路径> --ffmpeg <ffmpeg.exe路径> --output build/aac-adts-probe/media-report.json
```

工具要求 ffprobe 识别格式名 `aac`（ADTS）、单一 AAC-LC 音轨及 44100 Hz，并通过 `ffmpeg -xerror` 完整解码。FFmpeg 不作为应用依赖。样本含真实麦克风内容，仅本地保存，不提交 Git。实际真机通过后将设备型号、系统、测量结果和听音结论记录到验证文档。

验证包与普通 debug 包共享 Gradle 输出目录；归档 APK 由脚本单独保留。普通开发继续使用 `flutter run` 或 `flutter build apk --debug`，不设置该 Gradle 属性；其入口仍是 `lib/main.dart`。

## 当前证据与下一步

当前无连接 Android 设备，没有真实 AAC 样本或听音结论，第一步的设备关口未通过。工具代码、编译和模拟测试不能替代原生麦克风、媒体解码或实际定位证据；REC-08 保持“进行中”。自动化与构建结果见 [验证快照](../verification/rec08-aac-step1-2026-10-12.json)。

后续采用当前依赖提供的按码率估算定位配置，前提是真实样本定位可用。第四步须注意：现有正式媒体验证器会核对 KEY_DURATION 与解码时长，ADTS 的元数据可能只是估算，接入时应以解码样本时长为准，不能机械沿用 M4A 的精确时长假设。

本次范围不涉及格式枚举、数据库迁移、正式后端重构或产品设置；第二步以后仍未开始。完整步骤见 [AAC / ADTS 计划](aac-adts-plan.md)。
