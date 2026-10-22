# 丫丫录音

丫丫录音是一款开源、轻量、离线优先的手机录音软件。它不包含广告、会员机制或账户登录，专注于让用户能够快速、可靠地录制、整理和回放本地录音。

主要面向几分钟的短时间录音。当前测试以 1–5 分钟代表性录音及极短操作边界为主，一小时录音压力测试暂缓；具体范围见 [产品基线](docs/product/feature-list.md#产品目标)和 [原型测试指引](docs/architecture/mp3-prototype.md#可复现命令)。测试时长不作为应用录音时长上限。

## 项目状态

2026-10-08 用户确认开发进度中全部“进行中”功能项已在真机验证通过，29 项功能现均标为已完成，详见 [开发进度](docs/development-progress.md)和 [真机验收确认](docs/device-feedback.md#功能验收确认2026-10-08)。普通 debug、profile、release 均支持在“更多 → 设置”选择 M4A 或 MP3，初始默认 M4A；偏好即时保存并从下一次录音生效，MP3 无需额外构建开关。现有技术边界及验证证据见 [正式开放记录](docs/architecture/mp3-availability.md)和 [保存与恢复边界](docs/architecture/recording-save-recovery.md)。

## 首版目标

- 开始、暂停、继续、停止和取消录音。
- 支持 MP3、M4A 录音，并可在设置中选择默认格式。
- 浏览、搜索、播放、重命名、删除和分享录音文件。
- 通过文件夹对录音进行分类管理。
- 提供播放进度控制和倍速回放，便于检查录音内容。
- 录音与元数据仅保存于手机本地，不依赖账户或云端服务。
- 提供最近删除，降低误删录音带来的数据损失风险。

## 产品原则

- 轻量直接：打开应用即可开始录音，减少不必要的步骤与干扰。
- 隐私优先：仅请求实现录音所必需的权限，不上传或分析用户录音。
- 数据可靠：在应用切换、系统中断和存储异常等场景中，优先保障已录内容能够安全落盘。
- 简洁可用：优先完善高频操作，不在首版堆叠转写、云同步、复杂剪辑等功能。

## 技术方向

- 应用框架：Flutter。
- 平台节奏：优先完成 Android 端录音稳定性验证，再支持 iOS。
- 录音格式：初始默认 M4A（AAC-LC），设置可选 MP3/M4A；计划保留 M4A 原生实现，新增 `AudioRecord → PCM → LAME` 实时 MP3 编码，详见 [录音生命周期](docs/architecture/recording-lifecycle.md)。
- 存储方式：录音文件与索引数据保存在设备本地；文件夹在首版中作为应用内分类管理。
- 原生能力：录音、后台运行和系统媒体行为通过清晰的接口隔离；必要时采用 Android Kotlin 与 iOS Swift 的原生实现补足 Flutter 层能力。

## 首版不包含

- 账户登录、会员、广告或行为追踪。
- 云端备份、多设备同步或在线协作。
- 自动语音转写、AI 分析和复杂音频剪辑。
- MP3、M4A 之外的录音格式、已有录音的格式转换与用户可调的高级编码参数。

## 快速安装到 Android 手机（Windows / VS Code）

手机通过 USB 连接电脑，开启“USB 调试”并允许电脑授权。在 VS Code 打开本项目后：

- 按 **Ctrl+Shift+B**，执行默认任务“Android: 构建并覆盖安装（USB，无调试）”。
- 也可按 **Ctrl+Shift+P**，选择“任务: 运行任务”（Tasks: Run Task），再选择上述任务。

任务会先构建当前源码的 debug APK，成功后使用 `adb -d install -r` 覆盖安装到唯一的 USB Android 设备；正常覆盖保留已有录音和设置。安装完成后在手机上手动打开应用，不启动调试或日志会话。构建失败不会安装旧 APK；安装失败会在任务终端显示原因，不自动卸载应用。首次构建耗时较长，后续会复用构建缓存。

也可以在项目终端直接运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-android.ps1
```

脚本从 Flutter 生成的 `android/local.properties` 读取 Android SDK 路径，无需将 ADB 加入 PATH 或写死本机路径。

## 设计文档

- [MVP 功能列表](docs/product/feature-list.md)
- [开发进度](docs/development-progress.md)
- [MVP 用户流程](docs/product/user-flows.md)
- [UI 交互设计](docs/product/ui-interaction-design.md)
- [UI 与交互评审（2026-10-19）](docs/product/ui-ux-review-2026-10-19.md)
- [真机测试反馈](docs/device-feedback.md)
- [录音生命周期](docs/architecture/recording-lifecycle.md)

## 开源许可

许可证尚未确定。发布公开版本前将补充适合本项目的开源许可证文件。
