# REC-07 第四步：MP3 录音后端

2026-10-07：`Mp3RecordingBackend` 已接入正式应用的后端工厂和原生通道，普通构建仍只开放 M4A。第一步的 Android 设备关口尚未通过，MP3 暂用原型候选参数，仅在显式开启的 debug 构建中可调用；不视为正式参数或媒体验收通过。设置与分享入口、完整保存协议和异常恢复属于后续步骤。

## 构建与范围

```powershell
cd android
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest -Prec07Mp3=true
# 同时回归独立原型
.\gradlew.bat :mp3-prototype:assembleDebug :mp3-prototype:testDebugUnitTest -Prec07Prototype=true
```

`rec07Mp3=true` 只使 debug 的 `BuildConfig.REC07_MP3_ENABLED` 为真，允许原生开始命令携带 `format: mp3`。普通 debug、profile 与所有 release 均为假，profile/release 即使收到该构建属性也不开放 MP3。主界面本阶段仍明确请求 M4A；此开关没有增加格式选择或设置 UI。实际库加载或初始化失败明确反馈，不回退到 M4A。

候选配置为 44.1 kHz、单声道、PCM16 → LAME 4.0、CBR 64 kbps、quality 5；与原型的一组候选相同。M4A 继续使用原有 MIC / AAC / MPEG-4、44.1 kHz、128 kbps 配置，时长继续由服务单调时钟及保存后的媒体信息获得。

## 原生模块

`android/mp3-encoder` 为正式应用和独立原型提供同一个 Kotlin JNI 声明及 `librec07_lame.so`。第一步的完整、未修改 LAME 源码包、校验值、CMake、配置头、项目 C 流式封装和 JNI 已移入该模块；编码 C 核心未修改，JNI 名称迁移至 `io.github.renial.ya_recorder.mp3.LameEncoder`。

NDK 28.2.13676358 / CMake 3.22.1 构建 armeabi-v7a、arm64-v8a、x86_64，保留 16 KB ELF 对齐设置。`consumer-rules.pro` 保留 JNI 类及方法名。APK 的 `assets/mp3-encoder/` 包含完整源码包、许可/来源说明、项目 C/JNI、Kotlin 声明、CMake 和 Gradle 构建材料；源码包以 `.tar.gz.bin` 保存，防止 AAPT 自动解压 `.gz`，内容与原始 SHA-256 一致。解包后恢复 `.tar.gz` 文件名即可恢复原仓库布局。详见 [依赖说明](../../android/mp3-encoder/third_party/lame/NOTICE.md)。

## 线程和控制边界

- 服务所有命令、计时发布及后端错误处理串行进入 `recording-control`，原生准备、join、排空、flush、fsync 和媒体时长读取不占用 Android 主线程。开始时先进入前台，再执行可能等待的初始化。M4A 同样在该工作线程操作。
- 采集线程使用 `AudioRecord.READ_NON_BLOCKING` 读取，短读取在固定缓冲中汇集；每块最多 4410 样本（100 ms），队列最多 16 块。读取为 0 时短暂等待，负数明确失败。采集、队列、编码器缓冲均有上限，不将整段 PCM/WAV 落盘。[Android AudioRecord 文档](https://developer.android.com/reference/android/media/AudioRecord#read(short%5B%5D,int,int,int))规定非阻塞读取立即返回当前可用样本。
- 暂停与读取共用锁：不再接受新数据，将当前短块交入队列，然后停止麦克风；已接受块可继续编码。继续使用原有 AudioRecord、编码器和文件，暂停不 flush、不拼接独立 MP3。状态时长按已接受样本计算，发布最多存在一个短块的延迟，暂停/停止边界补齐该短块。
- 停止先确定最后样本边界，停止/释放采集，再等待编码线程排空所有已接受块，仅正常停止调用一次最终 flush、Info 标签回填、fsync 和关闭。接受与编码样本数必须一致且非零；服务还要求可读媒体时长与样本时长相差不超过 100 ms，之后沿用现有最终文件提交和事件流程。
- 取消停止采集，等待正在编码/写入的块结束，跳过余下队列及最终 flush，关闭 JNI 后才由服务删除临时文件。重复取消/释放不会再次关闭原生句柄。后端自身不移动或删除文件。
- 溢出、采集、编码/写入、收尾及清理失败明确报错，保留 `.part`，不能报告完整保存；异步错误携带后端及会话身份，旧错误不影响新会话。错误向界面提供简短中文消息，技术原因保留在 Android 日志。
- 线程 join 每个最多等待 5 秒；超时返回失败并保留临时文件，不在仍可能写入时删除文件或报告成功。不能强行销毁执行中的 JNI；其线程退出后仍执行句柄关闭。服务销毁关闭命令队列，跳过排队命令/迟到回调，串行释放资源并清空状态快照。

本步尚未实现队列失败后的部分音频提交、草稿、取消残留分类、跨文件与数据库的保存协议或进程恢复。线程退出超时也不能保证立刻释放正在执行的原生调用。上述情况归入第五步及 REC-06，不因临时文件保留而声称已经可以恢复。

## 本轮证据

- 正式应用 37 项 JVM 测试通过，其中新增 17 项 MP3 后端及 2 项串行调度测试；覆盖短块与暂停边界、样本计时、同一编码器继续、排空等待、取消期间写入、溢出、缺失原生库、初始化/采集/编码/flush/清理失败、超时、空录音、debug 工厂选择与队列关闭。测试使用替身录音器/编码器，不运行 Android 麦克风。
- 共享模块 Android lint 无问题；共享核心迁移后原型 6 项 JVM 测试及 APK 构建通过。
- 追加应用 Android lint 时，默认任务因工作区在 D 盘、Pub 缓存在 C 盘而无法生成 `audio_session` 的单元测试模型。临时 init 脚本仅在检查时忽略依赖测试源，并排除既有 `PropertyEscape`（本地 `local.properties`）和 `UnspecifiedRegisterReceiverFlag`（未改动的 Android 33 以下接收器分支）后，应用主源码 lint 为 0 errors / 7 warnings，余下为既有资源/图标提示。新 AudioRecord 入口显式处理 `SecurityException`，权限撤销的后端测试通过。没有给仓库加入 lint 禁用项/基线或修改上述旧接收器；默认完整应用 lint 不记为通过。
- 桌面真实 JNI 检查运行正式 Kotlin 后端、正式 `AndroidMp3Encoder` 和同一 C/JNI：输入两段连续合成音，中间暂停，停止后独立 FFmpeg 完整解码 220,560 样本，与输入精确一致；PCM 源开始/停止各 2 次、释放 1 次，显示样本时长 5001 ms，暂停时长不增长，信号相关性约 0.9999996。此检查是 Linux 加速合成输入，不能替代 Android 录音、耗电或长录音性能。
- 桌面 C 核心的短音频、非整块尾部、两组候选参数及失败边界回归通过。本步没有新增一小时设备或桌面长录音证据，第一步的历史长合成音记录保留。
- 启用开关的正式 debug APK、普通 Flutter debug APK 与原型 APK 构建通过；正式 APK 全部 10 个原生库与原型 3 个库的 16 KB ELF/APK 静态对齐及 SDK zipalign 检查通过。三个 ABI 的新 JNI 导出、源码材料及原始归档校验值核对通过。profile/release 开关在传入 `rec07Mp3=true` 时仍为假，此处检查配置生成，未构建完整 profile/release APK。
- `flutter analyze` 无问题，全量 129 项 Flutter 测试通过。普通产物为 `build/app/outputs/flutter-apk/app-debug.apk`，启用原生 MP3 的调试产物保存在 `build/rec07-mp3/app-debug-mp3.apk`。
- 没有连接 Android 设备。JNI/AudioRecord/MediaMetadataRetriever 在 Android 上的执行、实际麦克风录音及暂停恢复、一小时实时采集、后台/锁屏和 16 KB 运行均未验收。

机器可读证据见 [本轮快照](../verification/rec07-backend-2026-10-07.json)。

## 桌面 JNI 复现

先运行上面的 Gradle 编译；Linux/WSL 需 JDK 17+、cc、FFmpeg，并传入实际 Kotlin 2.2.20 stdlib 路径：

```bash
python3 tools/mp3-backend/host_lifecycle.py --stdlib-jar /path/to/kotlin-stdlib-2.2.20.jar
```

脚本重用原型的校验/源码展开/补丁及独立解码器，编译 Linux JNI，加载正式 Kotlin 类；输出写入 `build/rec07-mp3/host/`。Android 关口仍按 [原型设备验证](mp3-prototype.md#第一步通过条件及后续衔接)完成，不能用桌面结果解除产品入口的开关。
