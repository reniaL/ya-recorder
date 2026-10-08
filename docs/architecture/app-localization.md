# 应用语言选择（UX-07）

用户在设置中选择简体中文或 English，初始默认简体中文，不随设备语言自动切换。语言选项使用自身名称，方便用户在误选语言后找回入口。选择成功即时生效，应用重启后恢复。

## Flutter 资源与显示

- 采用 [Flutter 本地化机制](https://docs.flutter.dev/ui/internationalization)：`flutter_localizations`、ARB 和 `flutter gen-l10n`。`lib/l10n/app_en.arb`、`app_zh.arb` 为唯一翻译来源，生成的 Dart 文件一起提交；`l10n.yaml` 定义生成选项。
- 根组件设置 `locale`、`supportedLocales` 和 delegates，Material 系统控件也使用所选语言。切换仅更新 locale，保留 Navigator、页面状态与同一个录音/播放服务实例。
- 页面、弹窗、按钮、状态、辅助提示、无障碍描述使用生成的 getter 或带类型参数的方法。数量采用 ICU plural，英文区分 recording/recordings 和 day/days，避免逐字拼接。
- 异步错误与成功提示存储稳定的消息标识，在渲染时转换，已经显示的提示也随语言切换。原生错误码映射为应用提示，不直接显示原生诊断字符串；未知错误显示本地化的通用提示。技术诊断继续保留原生日志。
- 自动录音标题在提交时使用当时语言。用户标题、已有自动标题、文件夹名称及分享原件不翻译、不重命名。仅空分享标题的附件名使用本地化兜底名称。
- 启动恢复先读取语言偏好。标题生成使用缓存的语言资源，不依赖已关闭页面的 BuildContext，排队中的保存仍能完整入库。
- 英文词汇统一为 recording、folder、playback speed、Discard recording、Recently Deleted 等常见表达；恢复错误区分已保留文件和已保存可用录音，不扩大恢复保证。
- 空列表/错误说明、录音页及最近删除的长文案可滚动阅读，避免英文和大字体溢出。系统权限弹窗、系统分享面板属于应用外界面，继续遵循系统语言。

## 偏好与失败处理

SQLite 版本 6 为 `app_preferences` 新增 `language` 列，允许 `zh`/`en`，默认 `zh`。版本 5 升级只增加列，旧主题、格式、索引与音频保持；版本 1–4 沿用原迁移再创建包含语言的新偏好表。新增/更新偏好在事务内完成，只更新目标列，主题和语言互不覆盖。

设置先同步原生语言，再写 SQLite，两个操作都成功才更新 Flutter 界面。SQLite 写入失败时尽力回退原生语言，显示错误并保持旧界面/偏好；保存期间禁止重复选择和退出。应用启动重新从 SQLite 同步原生语言；若同步或回退遇到平台错误，下次启动会再次同步。SQLite 为权威偏好，双存储间不声称跨进程原子事务。

## Android 录音通知

`setAppLanguage` 桥接命令验证语言值，并保存通知用的 SharedPreferences。通知通过指定语言的 Configuration Context 读取 `values`/`values-zh` 字符串，不改变设备语言，不重建 Activity。活动服务仅接收语言刷新命令，更新通知及通知渠道名称，不调用录音开始/暂停/停止、编码器或保存路径。锁屏通知和真实设备切换仍需真机确认。

## 新增语言

1. 新增 ARB 翻译，补齐全部键与参数元数据，审核语义和该语言的复数规则。
2. 在 `AppLanguage` 中增加稳定存储代码、locale 与语言自身名称；对应增加 SQLite 允许值的迁移，保留旧值。
3. 扩展原生语言校验与 locale 映射，新增 Android 通知资源目录。
4. 运行 `flutter gen-l10n`，验证语言目录与资源覆盖、布局、无障碍、持久化和通知同步，执行全量回归与 Android 构建；最后做设备验收。

## 验证

2026-10-08：`flutter analyze` 无问题；全量 195 项 Flutter 测试通过，覆盖两种语言设置与布局、资源/参数完整性、英文复数、即时切换/重建恢复、保存/原生同步失败回退与重试、偏好独立及升级保留数据、录音/播放状态和页面关闭后的排队保存。Android `:app:testDebugUnitTest` 全部 64 项通过，包含 3 项语言值校验测试。`flutter build apk --debug` 成功，产物为 `build/app/outputs/flutter-apk/app-debug.apk`。详细结果及 APK 校验值见 [验证快照](../verification/ux07-language-2026-10-08.json)。

当前无连接 Android 设备。锁屏通知及渠道名称切换、真实录音/播放中的语言切换、设备重启保持、屏幕阅读器及实际视觉仍待真机确认；不把已有功能的真机验收用于新增语言功能。编码核心及原型未改，未重复独立 MP3 原型检查或长期压力测试。
