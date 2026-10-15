# BKP-01：备份 v1 契约与文件夹 UUID

实现日期：2026-10-15。对应 [七步计划](manual-backup-and-restore-implementation-plan.md)第一步。

## 交付边界

已提供严格 JSON 解析、ZIP 原始条目描述校验、流式内容哈希校验、阶段进度模型，以及新文件夹 UUID。没有增加备份页面、文件选择器、任务锁、生产 ZIP 读写或数据库导入；后续步骤负责把这些协议接口接到真实 ZIP 和存储流程。

`BackupContract.parse` 返回的是元数据与条目清单已通过校验的 `BackupDocument`，不代表音频内容已经验证。调用方必须对所有清单文件调用 `verifyContent`，包括导入将跳过的音频，才可报告备份完整。元数据哈希在 parse 内已验证。

代码入口：

- [协议与解析](../../lib/backup/backup_contract.dart)
- [进度契约](../../lib/backup/backup_progress.dart)
- [文件夹 ID](../../lib/storage/folder_id.dart)
- [协议及 ZIP 流式探针测试](../../test/backup/backup_contract_test.dart)
- [测试夹具](../../test/backup/backup_fixture.dart)
- [旧 ID 与 UUID 共存测试](../../test/storage/folder_id_test.dart)

## v1 固定格式

所有字段必需；允许空数组及 `folder_id: null`，拒绝未知字段，未来扩展通过格式版本升级。JSON 使用严格 UTF-8，时间为 Dart `toUtc().toIso8601String()` 的规范 UTC 字符串（毫秒或非零微秒，尾缀 `Z`），拒绝非 UTC 或被日期解析器自动规范化的无效日期。

### manifest.json

| 字段 | 类型与含义 |
| --- | --- |
| backup_type | 固定字符串 `io.github.renial.ya_recorder.backup` |
| format_version | 整数 `1`；字符串、浮点数或其他版本拒绝 |
| created_at | 规范 UTC 时间 |
| recording_count | 非负整数，与 metadata 录音数量一致 |
| folder_count | 非负整数，与 metadata 文件夹数量一致 |
| files | 每项含 `path`、`size_bytes`、`sha256`；涵盖 metadata 和所有音频，不涵盖 manifest 自身 |

`sha256` 为文件实际字节的 SHA-256，小写 64 位十六进制字符串。manifest 不对自身递归计算哈希；校验用于检测损坏，不提供来源认证。

### metadata.json

根对象仅包含 `folders` 和 `recordings`。

| 数组 | 每项字段 |
| --- | --- |
| folders | `id`、`name`、`created_at`、`sort_order` |
| recordings | `id`、`title`、`created_at`、`duration_ms`、`format`、`path`、`file_size_bytes`、`folder_id`、`was_interrupted` |

录音格式仅为 `aac`、`mp3`、`m4a`。录音路径必须精确为 `recordings/recording-<id>.<format>`，且与清单大小匹配；音频大小必须大于零。时间和文件夹关联保留，`was_interrupted` 为布尔值。

不含绝对路径、设置、删除状态和草稿。源库范围筛选在第二/四步实现；不能通过删掉 metadata 的删除字段来把最近删除内容混入备份。

文件夹名称为非空、首尾无空白字符串，名称重复按 SQLite NOCASE 的 ASCII 折叠检查，不用 Unicode 小写错误模拟数据库规则。`sort_order` 非负，实际导入如何排序和追加由第五步处理。

### ZIP 条目规则

- v1 所有条目均采用 STORE（包括 JSON），不接收加密、压缩、目录、链接或额外文件。
- 必须有 manifest、metadata，清单与其余条目精确对应；重复名称必须在任何按名称去重前被检查。
- 禁止绝对路径、反斜线、`..`、编码路径别名和未知后缀；ID 限定 ASCII 字母、数字、下划线、连字符，长度 1～128。
- 重复文件清单、录音 ID、文件夹 ID 或无效文件夹引用拒绝。
- 库选型支持 ZIP64；协议大小使用 Dart 整数，不按 32 位截断。已测 5 GiB 条目描述，无实际大文件读写证据，实际 ZIP64 导出/导入需在第四/五步验证。

真实 ZIP 适配层必须先限制中央目录大小与条目数量，核对原始 local/central 头、加密标志、文件类型、STORE 大小和多卷状态，再构造 `BackupEntry`。不能直接把 `ZipDecoder` 去重后的结果当原始清单，也不能调用全包内存解码或不受控的解压到目录。该适配层尚未实现。

## 资源上限

| 项目 | v1 默认上限 | 理由 |
| --- | --- | --- |
| 录音数量 | 10,000 条 | 限制清单及逐条校验成本 |
| 文件夹数量 | 10,000 个 | 保留空文件夹，限制关系处理成本 |
| 音频总量 | 16 GiB | 允许大容量及 ZIP64，防止无界磁盘消耗 |
| 每份 JSON | 16 MiB | JSON 需解析到内存，单独限制 |
| ZIP 条目数 | 录音上限 + 2 | 音频、metadata、manifest，没有目录条目 |
| 文本长度 | 4,096 个 Dart UTF-16 单元 | 容纳长标题，拒绝异常大字段 |
| ID 长度 | 128 个 ASCII 字符 | 同时兼容旧 ID 和 UUID |
| 普通整数 | 0～2^53−1 | 保持 JSON 工具间精确交换；音频另受容量限制 |

这些是备份资源策略，不改变应用录音时长或当前库的存储限制。超过时明确拒绝，不能截断标题或悄悄遗漏录音；导出预检查需向用户说明。原始 ZIP 中央目录的具体预检上限及流块大小在 ZIP 适配实现时固定，不能在构造全部条目后才限制分配。

`verifyContent` 对流块累计长度，实际长度大于声明时立即报错，短于声明或哈希不一致也拒绝。它不校验媒体解码能力，测试音频为三个字节的合成内容，不代表真实 AAC/MP3/M4A 已验证。

## 错误与进度契约

稳定校验错误码：`unsupportedVersion`、`invalidMetadata`、`invalidEntry`、`duplicateEntry`、`encryptedArchive`、`resourceLimit`、`missingFile`、`checksumMismatch`。错误含诊断 detail，后续 UI 使用本地化文案，不能直接将技术 detail 作为用户流程。

`BackupProgress` 带任务 ID、序号、操作类型、阶段、字节和录音数量。字节进度只代表当前阶段；总量未知或为零返回不确定进度。提交、取消中和终态不可取消；任务执行与 URI/存储错误将在后续步骤扩展，不混入格式校验错误。

## 文件夹兼容与依赖

新建文件夹调用 `newFolderId()`，使用随机 UUID v4，格式为 `folder-<uuid>`。旧 ID 不重写，数据库仍为 v7，不增加迁移。测试覆盖混合 ID 关闭重开、排序、重命名及录音移动，原音频保持。

锁定依赖：`archive 4.5.2`（MIT）、`crypto 3.0.7`（BSD-3-Clause）、`uuid 4.6.0`（MIT）；crypto/uuid 原本为传递依赖，现改为直接依赖；新增 archive 和其 posix 依赖。均为 Dart 库，无新增原生插件、权限或云端接口。

来源：[archive](https://pub.dev/packages/archive)、[crypto](https://pub.dev/packages/crypto)、[uuid](https://pub.dev/packages/uuid)。已检查锁定版本的库源码，STORE 原始内容通过文件流分块读，而非使用会整条加载的 `getStream(decompress: true)`。

## 验证

定向测试已通过；最终全量静态分析和 Flutter 回归结果见 [验证快照](../verification/bkp01-contract-2026-10-15.json)。

本步没有 Android 原生或平台插件改动，按纯 Dart 依赖及逻辑影响运行全量 Flutter，不重复 JVM、APK 或麦克风专项测试。没有新设备录音/换机/后台验证证据；这些属于后续完整流程验收。协议与旧数据兼容的本步关口不依赖新平台功能。
