# BKP-04：完整 ZIP 导出

实现日期：2026-10-15。状态：导出实现及自动化已交付，Android 实际文档保存、后台/故障和大容量 ZIP64 验收待补充，保留“进行中”。对应 [七步计划](manual-backup-and-restore-implementation-plan.md)第四步；正式设置入口仍等待完整导入/交互，不开放只能导出的半成品入口。

## 快照与协议

[BackupExportService](../../lib/backup/backup_export_service.dart) 将原生录音适配器绑定到存储的同一协调器，调用第三步平台任务入口。`RecordingService.runBackup` 先确认真实原生录音空闲，再在租约内取得 `snapshotForBackup`。保护覆盖快照、检查、打包、复核、保存与收尾；所有原有业务写入门禁及延后重放保持。

导出正常录音和所有文件夹（含空文件夹），排除最近删除、草稿、设置及源设备绝对路径。保留三格式、标题、时间、时长、归属、排序和中断标记，不转码、不迁移 ID。Dart 使用已有 `BackupContract` 验证快照结构、字段、ID、引用和资源限制；音频哈希的占位值仅供本地结构验证，不传给原生清单生成器。

桥接仅传输有界 JSON 元数据和源路径/大小描述，不传输音频内容，不直接复制 SQLite。备份 JSON 仅包含相对路径；源绝对路径只用于进程内原生读取。损坏的本地元数据不会被静默截断或丢弃后导出。

## 原生工作流程

[BackupZipExporter](../../android/app/src/main/kotlin/io/github/renial/ya_recorder/BackupZipExporter.kt) 是 JVM/Android 共用的工作执行器，由既有独立 `dataSync` 服务及单线程队列执行；整个重工作流程不依赖 UI isolate，也不增加 SQLite 写入者。

1. **检查（preparing）**：核对文件存在、普通文件、扩展名/索引格式和大小；以 64 KiB 缓冲计算 SHA-256/CRC。任何缺失、大小或扩展名不一致整体失败。沿用保存时已验证的媒体，本步不再完整解码音频。
2. **打包（packing）**：在 UUID 私有任务目录生成 `payload.zip`；所有条目采用 STORE，写入 `manifest.json`、`metadata.json` 及原始音频。音频第二遍读取时重新比较哈希、CRC 和大小，防止检查后同大小内容变化。
3. **复核（verifying）**：关闭 ZIP 后以 `ZipFile` 重开，检查条目数量、名称、STORE、长度、CRC，并逐条流式重算 SHA-256，包括两份 JSON。清单覆盖元数据和音频，不递归校验自身。
4. **保存（saving）**：只有完整临时包复核通过才打开目标 URI；分块复制、flush 并成功关闭目标流之后才持久化成功。服务通知和 Dart 状态分别报告各阶段实际字节量，不用打包百分比掩盖最后保存。

采用 Android 标准 `java.util.zip` 的 STORE/ZIP64 实现，全部大小、计数偏移估算使用 `Long`/Dart 整数；不自行实现 ZIP 头。既有 archive 4.5.2 用于独立验证器，并继续保留给后续导入适配。依据：[Android ZIP API](https://developer.android.com/reference/java/util/zip/package-summary.html)、[Android 35 ZIP 实现](https://android.googlesource.com/platform/prebuilts/fullsdk/sources/+/refs/heads/main/android-35/java/util/zip/ZipOutputStream.java)。5 GiB 大小估算通过测试，但没有实际生成/读写超过 4 GiB 的归档，不把 API 源码或整数测试当作真实 ZIP64 验收。

## 空间、取消与清理

估算模型区分音频总量、临时 ZIP 上界及本地目标副本；源音频已存在，不需要先额外复制一遍。上界包含 JSON、逐条头、文件名、ZIP64 附加字段和目录尾部余量。原生在检查前和打包前核对私有卷可用空间。源检查、打包、归档复核和保存合计约四倍音频量的读取 IO，这是读取量，不是临时空间需求。

任意 provider 的目标容量返回未知，不能预检；本地目标可能还占用第二份 ZIP，处理中仍处理空间/授权/读写/关闭失败。导出结果不表示接收服务已上传或已有异地副本。

取消在每个块边界以及阶段切换检查，仍等待当前 IO/流关闭与清理，不强行释放保护。失败/取消不修改原有录音，清理本任务目录并尽力删除本次选择器创建的目标；删除失败保留 `residualUri`，本地清理失败保留 `cleanupPending` 供重试。磁盘已满时的日志/清理异常不会作为未捕获工作线程异常终止应用。测试修复了 CRC 收尾异常可能跳过底层文件句柄关闭的问题。

原生在验证和目标关闭之后原子记录 `accepted` 成功，保留录音/文件夹数量及结果，即使此时 Flutter Engine 消失，重进应用也不会删除已成功输出。取消若晚于这个完成点，按已完成处理，不把成功结果改成取消。这只是导出完成标记，不是 BKP-05 所需的数据库导入提交标记。

成功 ZIP 在任务私有目录保留 24 小时，结果提供路径与到期时间，给后续分享流程使用；释放门禁不会立即删除分享副本。通过私有 UUID 目录内的保留凭据，在后续准备任务/进程启动时清理过期副本；删除失败保留凭据供重试。成功后的暂存清理问题保留成功结果和清理待重试状态，不删除目标。分享页面/调用仍在 BKP-06，不新增当前用户入口。

## 验证

结果见 [验证快照](../verification/bkp04-export-2026-10-15.json)。新增 8 项 Flutter 和 9 项 JVM 测试；完整静态分析、292 项 Flutter、114 项 JVM 及普通 debug APK 构建通过。

- Flutter 使用真实临时 SQLite 验证受保护快照、三格式与空文件夹、最近删除/设置排除、绝对路径不进入 JSON、写入拒绝、阶段字节数重置、取消及迟到取消、失败不报告成功、64 位空间估算和非法元数据。
- JVM 验证实际 STORE 包读回、三格式字节不变、空库/空文件夹、源缺失/大小/扩展名不一致、同大小源变化、检查/打包/复核阶段取消、包内内容损坏、临时空间不足、非法路径/重复/超限，以及 512 个短文件。测试内容是合成字节，不代表三格式已做实际播放验收。
- JVM 生成 `build/bkp04-native-samples/mixed.zip` 和 `empty.zip`；[独立验证器](../../tool/verify_backup_export.dart) 通过 archive 4.5.2 和 Dart v1 协议读取实际包，检查全部清单与 SHA-256。命令：`dart run tool/verify_backup_export.dart build/bkp04-native-samples/mixed.zip build/bkp04-native-samples/empty.zip`。该开发工具仅针对受控产物，不是可直接处理不可信 ZIP 的生产导入器。

ADB 无连接设备，本轮未安装或导出用户实际数据。仍需验证：真实文档 provider 的保存/关闭/授权撤销、目标空间不足、通知取消/后台/锁屏、Activity/Engine 重建及进程终止、真实大量录音和超过 4 GiB 的 ZIP64、三格式播放与分享接收应用延迟读取。Android 服务/ContentResolver/原子日志故障注入没有通过 JVM 桩替代；这些边界继续保留验收状态。

下一依赖就绪开发项为 BKP-05 合并导入与中断恢复；BKP-02/03/04 各自设备事项保留，完整发布由 BKP-07 端到端证据关闭。
