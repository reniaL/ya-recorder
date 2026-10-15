# BKP-03：文档访问与长任务基础

实现日期：2026-10-15。状态：实现及自动化验证已交付，Android 文档服务和真实生命周期待设备验收，保留“进行中”。对应 [七步计划](manual-backup-and-restore-implementation-plan.md)第三步。

## 执行路径

固定采用 **Android 原生流式工作执行器**。`BackupTaskService` 使用独立 `dataSync` 前台服务，`BackupTaskRuntime` 的单线程执行器实际打开 URI、分块复制并关闭流；不依赖 Activity、页面回调或 Flutter Engine 执行复制。没有新建后台 Dart isolate/FlutterEngine，也没有第二个 SQLite 写入者。后续 ZIP/哈希等重工作需要扩展这个执行器，不能仅让空服务包裹 UI isolate 中的打包操作。

本步只交付运输层，不生成或导入备份 ZIP。Dart `BackupDocumentService.copy` 的输出准备/消费回调供探针和后续适配使用；回调本身不获得后台执行保证。BKP-04/05 仍需实现原生重工作、完整包验证和数据库事务协议，不能把一次复制成功作为完整备份成功。

平台代码：

- [BackupPlatformBridge](../../android/app/src/main/kotlin/io/github/renial/ya_recorder/BackupPlatformBridge.kt)：选择器、平台命令及快照。
- [BackupTaskService](../../android/app/src/main/kotlin/io/github/renial/ya_recorder/BackupTaskService.kt)：前台生命周期、通知与超时。
- [BackupTaskRuntime](../../android/app/src/main/kotlin/io/github/renial/ya_recorder/BackupTaskRuntime.kt)：工作线程、日志与清理。
- [BackupStreamCopy](../../android/app/src/main/kotlin/io/github/renial/ya_recorder/BackupStreamCopy.kt)：可独立 JVM 测试的流式复制。
- [BackupDocumentService](../../lib/backup/backup_document_service.dart)：Dart 适配及协调器租约。

## 文档、进度和保护

使用 `ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT` 和 `CATEGORY_OPENABLE`，返回 `content://` URI、显示名称。选择取消不创建任务、不进入数据保护。选择器属于 Activity；Activity 销毁时结束未完成的选择请求，需要重新选择。支持可用时持久化 URI 授权，不请求麦克风或通用存储权限。

64 KiB 缓冲复制，不跨桥传音频数组，不使用 URI 对应的磁盘路径，不要求 seek 或目标可用空间查询。源内容先流式写入任务私有 `payload.zip`，后续 ZIP 解析可在普通暂存文件上 seek。单次运输上限为 64 GiB，保护未知大小输入；这不是 ZIP 有效性或导入容量规则，BKP-01 的 16 GiB 音频等限制仍由包验证器执行。

状态携带任务 ID、单调递增序号、阶段、实际字节数及错误；写出总量来自已准备文件的长度，未知输入保持不定进度。250 ms 轮询从当前快照开始，不存在先订阅后补快照的事件缺口；原生通知更新同样节流，取消请求只匹配当前任务 ID。通知展示读取/保存和字节量，写出可展示阶段百分比，提供返回应用及取消。中英文资源随应用语言读取；完整结果页和任务导航留在 BKP-06。

`copy` 通过 `RecordingService.runBackup` 进入门禁，覆盖准备、传输、消费和清理。提前取消、准备/消费异常或桥失败均走收尾；活动 IO 在分块边界接受取消，等待流关闭与清理后才释放数据保护。不把仍在写的工作遗留在解锁后的后台。原生通知取消也会在快照反映取消状态。

## 生命周期与中断

| 情况 | 本步行为 |
| --- | --- |
| 离开页面、切后台 | 原生复制继续，Dart 回调不归页面持有；通知返回应用。 |
| Activity / Flutter Engine 销毁 | 复制仍由进程级原生工作线程持有；新 Engine 启动屏障等待现存复制结束，再释放暂存。不会自动重跑旧 Dart 消费回调。完整业务流程重建仍需 BKP-04/05 状态协议。 |
| 通知不可见/被系统禁用 | 不请求额外通知授权，不因通知显示失败主动取消；服务启动限制仍正常回报。真实系统行为待验收。 |
| 前台服务无法启动 | 返回失败，清理暂存与目标；10 秒未开始执行的预约按启动失败收尾。只允许从前台用户操作启动。 |
| 超时/服务销毁 | Android 15+ `onTimeout` 立即退出服务并请求工作取消；另有 30 分钟运输时限。关闭流/清理在工作线程完成，不能强制解锁仍阻塞于 provider 的 IO。 |
| 进程终止、重启 | 原子任务日志保留 ID、URI、方向、路径及状态；未结束任务标记中断并清理，不自动续传，不注册开机恢复。 |
| 等待导入确认 | 每次原生复制结束即停止工作服务，未来等待确认不需要维持无限期前台服务；等待期间业务状态由后续导入协调器持有。 |

启动屏障已接到生产库协调器，在录音恢复和过期清理前等待原生运输结束/清理。日志仅用于本步传输文件，不是导入事务提交证据；BKP-05 仍必须加入与 SQLite 同事务的提交标记。

输出流成功关闭后才产生运输 `completed`，Dart 消费成功后另行持久化接受标记。取消/失败、未接受输出或启动中断会尽力删除本次选择器创建的目标；成功接受的输出保留。源文档永不删除。删除失败保留 `residualUri`，本地清理失败保留 `cleanupPending`，阻止覆盖旧日志，可通过 `release` 重试。清理目录从任务 UUID 和私有根目录推导，不信任日志中的任意绝对路径。保留最终快照供后续结果页读取。

## 验证与探针

自动化结果见 [验证快照](../verification/bkp03-platform-2026-10-15.json)：静态分析无问题，284 项 Flutter、105 项 Android JVM、普通 debug APK 构建通过。新增 9 项 Dart 桥接/门禁测试和 6 项 JVM 流复制测试。覆盖非 seek 输入、缓冲上限、字节进度、分块取消、资源上限、读/写/flush 故障、选择取消、活动录音拒绝、消费失败、清理时锁保持、服务启动失败、残留目标与启动屏障。JVM 测试没有运行 Android Service、真实 ContentResolver 或进程终止，不把它们列为已验证。

设备探针：[backup_transport_probe.dart](../../tool/backup_transport_probe.dart)。运行 `flutter run -t tool/backup_transport_probe.dart`；它可读取选择的 ZIP 并报告字节数/SHA-256，或写出 4 MiB 全零运输样本。样本**不是有效备份包**，仅验证 URI 运输，正式设置页未新增入口。探针源代码通过静态分析；本次只构建普通应用 APK，未构建/安装独立探针 APK。

ADB 无连接设备；未安装、录音或执行真实文件选择。待验收：

1. 本地 DocumentsProvider、外置文档源的实际 URI/显示名称/权限及非 seek 流；读回探针输出核对 SHA-256。
2. 选择取消与 Activity 重建，服务启动失败、权限撤销、空间不足及关闭流失败。
3. 前后台、锁屏、返回应用、通知禁用及通知取消；延迟/阻塞 provider 的取消边界。
4. Android 15+ 服务超时和系统终止，重启后先清理再恢复录音与过期清理；成功输出不误删，失败残留可报告和重试。
5. 等待确认及正式 ZIP 重工作、入库仍由 BKP-04/05 实现后联合验收。

平台依据已于 2026-10-15 核对：[文档访问](https://developer.android.com/training/data-storage/shared/documents-files)、[dataSync 类型](https://developer.android.com/develop/background-work/services/fgs/service-types)、[前台服务超时](https://developer.android.com/develop/background-work/services/fgs/timeout)。
