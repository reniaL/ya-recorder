# MP3 正式开放记录

日期：2026-10-08。

## 真机反馈与开放决定

用户在上一轮安装的 M2102K1AC（Android 13 / API 33，4096 字节页）上反馈：“设置功能正常，MP3 文件录制、播放、分享等各个功能也正常”，并明确要求正式放开 MP3 格式设置。这是用户报告的真机功能验证；没有新增录音时长、性能采样、参数对比或 16 KB 运行测量，不能将这些专项记为已通过。

据此解除临时构建限制，普通 debug、profile、release 均开放 MP3。先前“仅显式开启的 debug 可选择 MP3”“普通构建会显示暂不可用”等记录保留为历史，以本记录为当前开放状态。未完成的专项回归继续跟踪，不再作为阻止用户选择 MP3 的构建开关。

## 当前行为

- Android `defaultConfig` 统一设置 `BuildConfig.REC07_MP3_ENABLED = true`，各 build type 不再覆盖该值；无需 `-Prec07Mp3=true`，旧属性也不再控制开放状态。
- 普通 `flutter run`、`flutter build apk --debug`、`flutter build apk --profile` 和 `flutter build apk --release` 均提供 M4A、MP3 两个可选格式。初始默认仍为 M4A，已有用户的格式偏好保持原值。
- 原生能力查询、开始命令校验和后端工厂继续共用这一配置。运行时采集/编码/保存失败仍明确反馈，不静默改用 M4A；保留不可用能力的测试和处理分支，不把静态开放等同于永不失败。
- 本次不改编码参数：44.1 kHz、单声道、PCM16、CBR 64 kbps、LAME quality 5，沿用已测试的实际配置。用户确认现有录音效果可用，不声称已完成多参数试听比较。
- 分享仍依据录音自身格式提供 `.mp3` / `audio/mpeg` 或 `.m4a` / `audio/mp4`，不读取当前偏好或转换已有文件。

## 进度与验证

设置及 MP3 录制、播放、分享的基本真机功能记为用户确认通过；MGT-03 结合既有 MIME、附件命名和原件保护自动化证据标为已完成。REC-07 的实现和普通构建入口已开放，整体保持进行中，继续跟踪 REC-06 系统中断策略、极短/1–5 分钟专项、后台/异常恢复、升级/重启和 16 KB 运行的明确证据；一小时压力测试仍暂缓。

自动化与构建结果见 [本轮验证快照](../verification/rec07-mp3-open-2026-10-08.json)。新增原生测试校验普通构建无需 opt-in 即提供并接受 MP3；debug/profile/release 生成的 BuildConfig 逐一检查。编码核心、原型及媒体恢复算法未改，不重复原型或桌面编码测试；既有完整应用 lint 环境限制沿用此前记录。

本轮 `flutter analyze` 无问题，全量 174 项 Flutter 测试及 61 项正式 JVM 测试通过；普通 debug 与 release APK 构建成功，分别保存在 `build/app/outputs/flutter-apk/app-debug.apk`、`app-release.apk`。两份 APK 的原生库均通过 16 KB ELF/APK 静态对齐和 SDK zipalign 检查。profile 仅检查配置生成，未另构建完整 APK。release 编译出现既有 Pub 缓存 C 盘/项目 D 盘的 Kotlin 增量缓存不同盘提示后最终构建成功，未删除缓存或改动仓库编译策略。本轮结束时设备已断开，未安装新普通包或新增麦克风采集证据；用户反馈针对上一轮测试包。
