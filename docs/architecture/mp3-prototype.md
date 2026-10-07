# REC-07 第一步：实时 MP3 原型

日期：2026-10-07。当前阶段为**原型实现和构建/桌面验证完成，Android 运行与长录音验证待完成**。这份记录不代表 REC-07 或 REC-06 已验收。

## 实验范围

`android/mp3-prototype` 是独立 Android 应用，包名为 `io.github.renial.ya_recorder.mp3prototype`，仅在 Gradle 显式传入 `-Prec07Prototype=true` 时启用。Flutter 应用不依赖此模块，普通应用构建不编译或打包原型，原有 M4A 录音、SQLite 索引、默认设置及分享行为均未接入 MP3。原型输出保存在自己的私有 `files/runs/<id>` 目录，每次测试使用新标识。

原型路径为：`AudioRecord → 100 ms PCM 块 → 有界队列 → 编码线程 → LAME → MP3 临时文件`。线程启动时先确认编码器可用，再启动采集。输出成功收尾并通过媒体检查后，才将 `.mp3.part` 改名为 `.mp3`。测试音来源替代采集端，同样按实际音频时间产生 PCM，不加速、不积存整段 PCM。

原型只覆盖连续采集、编码、停止收尾和观测。暂停/继续、用户确认取消、音频焦点、生产会话草稿、SQLite 提交及进程恢复属于后续阶段。发生溢出、编码或写入错误时明确报告失败并保留 `.part`，此处尚未实现生产要求的“尽力保存已录部分”。提前停止属于开发测试控制，不是产品取消录音。

## 来源与构建选择

使用 [LAME 官方发布列表](https://sourceforge.net/projects/lame/files/lame/)中的 **4.0** 源码，采用项目自己的 C/JNI 封装与 CMake 构建。原始完整源码包、许可及来源记录随仓库保存，SHA-256 校验失败时停止构建；不依赖旧 Android 封装的预编译库，不在构建期间下载源码。详见 [依赖说明](../../android/mp3-prototype/third_party/lame/NOTICE.md)。

采用可移植 C 实现，关闭可选解码器、汇编/SSE 和分析功能。NDK Clang 发现 upstream `SHIFT_IN_BITS_VALUE` 对负数做左移；构建生成的 `VbrTag_project.c` 将位掩码改为无符号运算，原始归档不变。CMake 和桌面验证脚本都检查原表达式后再应用该单行修改，修改及日期记录在依赖说明中。上游仍有整数参数传给 `fabs` 的编译警告；项目封装启用 `-Wall -Wextra -Werror`。

构建固定为 NDK `28.2.13676358`、CMake `3.22.1`、AGP `8.11.1`、Android API 24–36，ABI 为 `armeabi-v7a`、`arm64-v8a`、`x86_64`。原型共享库显式配置 16 KB ELF 对齐，检查 APK 未压缩库的 ZIP 对齐；[Android 官方检查说明](https://developer.android.com/guide/practices/page-sizes)要求同时检查 ELF、APK 打包及实际运行。静态对齐通过不代表在 16 KB 系统上运行通过。

## 编码参数候选

| 参数 | 原型默认候选 | 可对比候选 |
| --- | --- | --- |
| 输入/输出采样率 | 44,100 Hz | 本阶段固定 |
| PCM | 单声道、16 bit | 本阶段固定 |
| MP3 码率 | CBR 64 kbps | CBR 96 kbps |
| LAME quality | 5 | 2 |
| 采集块 | 最多 4,410 样本，约 100 ms | 最后一个块允许不足 100 ms |
| 队列 | 最多 16 块 | 溢出立即报告失败，不静默丢帧 |

队列最多存放 141,120 字节 PCM 数组内容，另有采集端、编码端各一个块及对象开销。原生输出缓冲固定约 13 KB；实际进程内存还包括系统采集缓冲、JVM、LAME 和界面，必须实测。停止后排空已接受的队列，只 flush 一次编码器，回填 LAME/Info 标签中的帧数及延迟/尾部填充信息，同步并关闭文件。正式参数仍待真实语音试听和目标设备性能验证，不能由单频合成音决定。

## 可复现命令

在仓库根目录，PowerShell：

```powershell
Push-Location android
.\gradlew.bat -Prec07Prototype=true :mp3-prototype:assembleDebug :mp3-prototype:testDebugUnitTest :mp3-prototype:lintDebug --console=plain
Pop-Location
python tools/mp3-prototype/check_apk_alignment.py build/mp3-prototype/outputs/apk/debug/mp3-prototype-debug.apk --report build/mp3-prototype/apk-alignment.json
```

APK：`build/mp3-prototype/outputs/apk/debug/mp3-prototype-debug.apk`。安装的是单独的测试应用，可与丫丫录音并存。

Linux/WSL 桌面测试需 `cc`、Python 3.9+、`ffmpeg`、`ffprobe`。在 Linux 的仓库目录运行：

```sh
python3 tools/mp3-prototype/host_smoke.py --long-seconds 3600
```

脚本编译同一份原生 C 编码封装，逐块产生测试音，并通过 FFmpeg 完整解码核对样本数、信号相关性和每秒 RMS。不会写 PCM/WAV 中间文件。这里的 3600 秒指**音频长度**，输入在桌面加速生成，不能作为一小时 Android 实时录音证据。

连接并授权 Android 设备后，在仓库根目录执行：

```powershell
# 首次安装；确认设备上可正常初始化 JNI/编码器、录制并解码。
python tools/mp3-prototype/run_device.py --apk build/mp3-prototype/outputs/apk/debug/mp3-prototype-debug.apk --seconds 10 --source microphone
# 同一编码链路的实时合成音长测。
python tools/mp3-prototype/run_device.py --seconds 3600 --source tone
# 真实采集的一小时长测；期间手动锁屏、切换应用并返回。
python tools/mp3-prototype/run_device.py --seconds 3600 --source microphone
# 对比参数（应分别改变码率、quality，而非仅比较两个组合）。
python tools/mp3-prototype/run_device.py --seconds 10 --source microphone --bitrate 96 --quality 5
python tools/mp3-prototype/run_device.py --seconds 10 --source microphone --bitrate 64 --quality 2
# 人为放慢编码，验证积压最终明确报错。
python tools/mp3-prototype/run_device.py --seconds 10 --source tone --encoder-delay-ms 250 --expect-overflow
```

可用 `--serial` 指定设备、`--adb` 指定 adb 路径。脚本会授权测试应用的麦克风和适用的通知权限，从可见 Activity 启动前台服务。运行期间持有有时限的 partial wake lock，该选择是原型测试条件，生产后台策略需另行确认。脚本不会重置电量统计、删除录音或强停应用。

结果写入 `build/mp3-prototype/device/<run-id>`：设备/API/ABI/页大小信息、每 5 秒采集的进度 JSONL、最终结果、MP3/失败残留和测试前后电量状态。应用每秒刷新观测值，包括 PSS、Java/native heap、累计进程 CPU 时间、采样数、编码线程 CPU 时间、块编码最大耗时、队列观测高水位、排空/收尾耗时和输出大小。`drainAndFinishMs` 排除随后的完整媒体解码耗时；`wallMs` 包括检查。电量快照只是辅助记录，不能单独据此归因编码耗电。

Android 校验通过 MediaExtractor 确认 MP3、采样率、声道和时长，再用 MediaCodec 完整解码。媒体时长与接受样本时长允许 100 ms 偏差；解码样本数允许不超过一个 PCM 块的偏差，以容纳 Android 解码器处理编码延迟/尾部填充的差异。桌面解码则要求与输入样本数完全一致。命令脚本还要求实际接受的样本数达到指定完整时长，提前停止不会被当作一小时通过。

## 本轮验证证据

- 三个 ABI 的独立 debug APK 构建通过；6 项 JVM 测试通过，覆盖有界队列溢出保留已接受块、顺序/并发排空、最后短块和非法参数。
- 原型 Android lint 通过（0 errors，开发界面文本仍有本地化提示）。ELF LOAD 段和未压缩 APK 库的 16 KB 对齐检查通过，SDK `zipalign -c -P 16 4` 检查通过。
- 桌面 C 测试覆盖 1 样本、10 秒加 37 样本的非整块尾部、两组参数及 3600 秒音频；另验证无效参数、初始化失败、重复 flush、收尾后写入和 `/dev/full` 写入失败。
- 3600 秒合成音输出 158,760,000 样本，FFmpeg 完整解码样本数一致，无解码错误；每秒信号 RMS 和相关性检查通过。验证环境为 Ryzen 7 8845H、WSL2 Debian、GCC 12.2.0、FFmpeg 5.1.6、Python 3.11.2。本轮桌面编码耗时约 14.08 秒，flush/sync 约 22.36 ms，编码进程 max RSS 在采样点为 18,364 KB；这些加速合成音数字不能外推 Android 的内存、耗时或耗电。原始测量写入 `build/mp3-prototype/host/results.json`，本轮 [验证快照](../verification/rec07-prototype-2026-10-07.json) 随仓库保存。
- 现有应用 `flutter analyze` 无问题，`flutter test` 117 项通过，Android debug APK 构建通过。
- `adb devices -l` 无连接设备，设备脚本明确报告 `no devices/emulators found`。没有 Android 上的麦克风、JNI 执行、MediaCodec 解码、16 KB 运行或一小时实时录音通过证据。

## 第一步通过条件及后续衔接

以下检查全部完成后，才能认为第一步的技术验证关口通过：

- [x] 固定源码来源、校验值、许可和可重现构建。
- [x] 验证目标 ABI 编译、原生接口导出及 16 KB ELF/APK 静态对齐。
- [x] 桌面短/长音频解码、样本数和失败边界验证。
- [ ] 在目标 Android 真机录制短语音，试听并比较参数，记录选定参数的理由。
- [ ] 完成至少一小时真机连续采集和实时编码，检查音频连续性、时长、内存趋势、CPU、耗电、队列积压和停止耗时。
- [ ] 在 Android 上验证 JNI/MediaCodec、锁屏/后台、提前停止及人为队列溢出的实际结果。
- [ ] 在 16 KB 系统（设备或模拟器）运行原型；记录实际页大小并确认无兼容模式依赖。

当前第一步的设备关口仍未通过。后续格式契约与旧索引迁移可以基于已验证的输出结构设计，但正式编码参数及生产后端不能视为已经验收；设备测试失败时应先修复本原型，再接入正式录音流程。
