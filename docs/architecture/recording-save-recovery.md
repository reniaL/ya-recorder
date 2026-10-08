# REC-07 第五步：保存协议、草稿与异常恢复

日期：2026-10-08。已接入两种格式共用的文件/索引提交协议、持久化草稿、取消标记及启动/回前台恢复。MP3 仍受第四步 debug 开关限制；设置与分享留待第六步。此步为 REC-06 提供恢复基础，尚未实现音频焦点、来电等系统中断策略，也未完成 Android 真机验收。

本文件保留第五步的实现与验证边界；第六步已接入设置与两种格式分享，详见 [设置与分享记录](recording-format-settings-sharing.md)。

## 提交与确认

1. 原生在分配录音器/编码器之前，持久化会话 ID、创建时间、显式格式及 `CAPTURING` 草稿。路径仅由受校验的 ID、格式和应用私有根目录生成，不读取草稿内的任意路径。
2. 停止完成采集/编码收尾并确认写入者已静止后，将草稿置为 `FINALIZING`。同步音频文件，用 MediaExtractor/MediaCodec 完整解码验证实际音频、格式、采样率、声道与时长；MP3 正常停止还检查解码时长与接受样本时长相差不超过 100 ms。
3. 持久化含验证结果的 `VALIDATED` 草稿，再在同一应用根目录内 rename 至最终路径。已有最终文件不被覆盖；rename 失败保留音频与草稿。随后持久化 `READY`，原生发送 `fileReady` / Dart `RecordingFileReady`，表示文件已就绪，尚未表示已保存到列表。
4. Flutter 的 `RecordingSaveCoordinator` 串行处理实时通知和恢复结果；`commitNativeRecording` 在 SQLite 事务内校验最终文件存在、大小与结果一致，并写入索引。相同 ID 的重放核对不可变元数据；标题、文件夹及最近删除状态保留，冲突拒绝覆盖。
5. 事务提交后调用 `acknowledgeRecording`；原生删除恢复副本/原始残留，最后删除草稿。界面只在事务成功后显示录音条目与保存成功提示；中断结果持续显示“已录部分已保存”。确认丢失或清理失败时，保留 `READY` 并提示下次清理，已提交索引可安全重放，不报成入库失败。

服务在文件就绪后保持 `stopping` 和前台通知，直到 Flutter 的索引尝试结束。入库失败调用 `deferRecording`，停止等待并保留 `READY`；失败录音不显示普通成功提示，下次启动或回前台可重试。实时事件丢失、Activity/Flutter 不在场或进程终止后，草稿仍可重放。文件与 SQLite 并非一个原子事务，草稿用于衔接中断窗口；此处不宣称断电可恢复全部内容。

## 草稿与恢复边界

草稿位于 `ya_recorder/recovery/<id>.draft`，使用版本化 Properties，格式必须是 `m4a` 或 `mp3`。Android 通过 [AtomicFile](https://developer.android.com/reference/android/util/AtomicFile)写入并读回核对；原子文件本身不提供锁，服务与桥接共享同一个 `RecordingSaveProtocol` 实例及互斥边界。音频仍保存在 `recovery/recording-<id>.<format>.part`，最终文件位于 `recordings/`。没有增加或升级 SQLite schema。

| 草稿阶段 | 启动/回前台时的处理 |
| --- | --- |
| `CAPTURING` / `FINALIZING` | 对已停止写入的音频验证或构造恢复副本，成功后按中断录音提交；失败保留残留，向界面报告。 |
| `VALIDATED` | 若 rename 已完成，重新验证最终文件并补写 `READY`；若尚未 rename，验证候选与已记录的大小/时长一致后继续提交。 |
| `READY` | 重新验证最终文件及元数据，返回待入库结果；SQLite 幂等提交后清理草稿。 |
| `DISCARDING` | 仅清理取消残留，绝不返回待入库录音；草稿最后删除，清理失败下次重试。 |
| 损坏或未知版本/格式 | 保留文件，报告未解决残留；不推断格式或创建普通条目，不影响其他有效草稿恢复。 |

当前进程为写入中的会话保留租约。恢复跳过活动会话；MP3 join 超时或原生释放失败时保留租约直到进程退出，不能在仍可能写入时复制、移动或删除文件。M4A 后端也记录释放失败，重复清理不能把未确认静止的录音器误认作可恢复。租约仅适用于当前单进程 Android 架构。

取消先持久化 `DISCARDING`，再停止后端与清理文件。若取消意图无法落盘，不执行取消、不转为恢复提交，而是提示重试；已记录取消意图的文件永远不自动导入。没有草稿的旧 `.part` 不具备可靠的取消意图/创建元数据，保留并报告，不按扩展名猜测恢复。缺少草稿的旧最终文件自动补索引、任意旧索引损坏修复及残留手工管理不在本步实现范围。

## MP3 与 M4A 的媒体验证

- 正常保存与恢复均使用 [MediaExtractor](https://developer.android.com/reference/android/media/MediaExtractor)检查音轨，并通过 [MediaCodec](https://developer.android.com/reference/android/media/MediaCodec)完整解码，按实际输出帧计算时长；仅有扩展名、文件大小或可读时长不足以入库。处理使用固定/编码器大小的缓冲，不写整段 PCM/WAV。解码无进展 10 秒或处理超过 120 秒返回失败，保留残留。
- MP3 非正常结束时，`Mp3FrameRecovery` 只接受当前编码器的 MPEG-1 Layer III、44.1 kHz、单声道连续完整帧前缀，不越过损坏帧头重新同步。复制到 `.repair` 后禁用副本中可能过期的 Info/Xing 时长提示，再完整解码验证。没有修改 C 编码核心、不重新编码整段录音、不覆盖原始 `.part`；原始残留保留到入库确认。
- 恢复 MP3 的实际可解码时长可能含编码延迟/填充，且缺失未 flush、未写入的样本。成功仅表示这段副本通过验证并已入库，必须标为中断结果；不承诺恢复全部原始样本、所有损坏文件或所有音质损坏。
- M4A 只提交已经能完整解码的容器；未封装、损坏或无可解码音频的文件保留并报告，未实现 M4A 容器重建。

## 本轮验证

- `flutter analyze` 无问题，全量 146 项 Flutter 测试通过。新增 17 项覆盖提交顺序/重放、SQLite 实际事务失败与重试、标题/归属/删除元数据保持、缺失/变化文件、恢复契约及界面成功提示边界。
- 正式应用 59 项 JVM 测试通过，新增 18 项保存协议与 4 项 MP3 帧恢复测试；覆盖 rename/草稿更新之间的中断、确认清理失败、取消 tombstone 重试、活跃/超时租约、坏草稿/格式、缺失文件、冲突不覆盖和无草稿旧残留。JVM 测试注入文件 I/O/媒体验证，不运行 Android AtomicFile 或 MediaCodec。
- 真实 Linux LAME/JNI 输出经正式 Kotlin 恢复代码处理，再由 FFmpeg 完整解码：截断收尾文件恢复 40,332 字节、222,336 解码样本（5041 ms）；未执行 flush 的文件恢复 39,496 字节、217,728 样本（4937 ms）。两种输入残留均未修改，无独立解码错误。输入为约 5 秒合成音，数据包含恢复副本的延迟/填充，不等同于完整恢复源样本，不替代 Android 证据。
- 普通 Flutter debug APK 和显式开启 MP3 的 debug APK 构建通过；全部 10 个原生库的 16 KB ELF/APK 对齐及 SDK zipalign 检查通过。MP3 开关策略保持第四步配置，编码核心、共享库源码材料和独立原型没有功能改动，沿用既有原型证据，未重复原型构建或一小时测试。
- 应用主源码 lint 在第四步同一临时 init 配置下为 0 errors / 7 warnings；忽略依赖测试源并排除已有 `PropertyEscape` / `UnspecifiedRegisterReceiverFlag`，仓库未添加 lint 禁用项。默认完整 lint 的既有跨盘测试模型问题仍未解决，不记为本步通过。
- 未连接 Android 设备。实际 AtomicFile、中断/重启窗口、Android 解码器、麦克风、暂停/继续、取消、锁屏/后台及 16 KB 系统运行仍须真机验证。当前采用 1–5 分钟代表性录音及极短边界，一小时压力测试暂缓。

机器可读结果见 [验证快照](../verification/rec07-save-2026-10-08.json)。普通产物为 `build/app/outputs/flutter-apk/app-debug.apk`，启用 MP3 的本步调试产物为 `build/rec07-mp3/app-debug-save-protocol.apk`。

## 复现

```powershell
flutter analyze
flutter test
Push-Location android
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug -Prec07Mp3=true --console=plain
Pop-Location
```

Linux/WSL 需 JDK 17+、cc、FFmpeg；先生成真实 JNI 的短音频，然后运行恢复检查，传入实际 Kotlin stdlib 路径：

```bash
python3 tools/mp3-backend/host_lifecycle.py --stdlib-jar /path/to/kotlin-stdlib-2.2.20.jar
python3 tools/mp3-backend/host_recovery.py --stdlib-jar /path/to/kotlin-stdlib-2.2.20.jar
```

真机以几分钟录音覆盖：正常停止入库、入库前结束应用后重启、索引提交后确认前中断、暂停/继续后中断、确认取消后清理中断，以及短录音/写入失败的残留结果。分别验证 MP3/M4A，检查只有通过验证并入库的录音可播放，取消内容不会重新出现，无法恢复的文件不会被标为已保存。系统音频焦点/来电处理仍属于 REC-06 后续实现与验证。
