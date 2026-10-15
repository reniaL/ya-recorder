enum BackupOperation { export, import }

enum BackupStage {
  preparing,
  checking,
  awaitingConfirmation,
  packing,
  verifying,
  saving,
  importing,
  committing,
  cancelling,
  completed,
  cancelled,
  failed,
}

/// Facts reported by a task. UI pages must not own task lifetime.
class BackupProgress {
  BackupProgress({
    required this.taskId,
    required this.sequence,
    required this.operation,
    required this.stage,
    required this.processedBytes,
    this.totalBytes,
    required this.processedRecordings,
    this.totalRecordings,
  }) {
    if (taskId.isEmpty ||
        sequence < 0 ||
        processedBytes < 0 ||
        processedRecordings < 0 ||
        totalBytes != null && totalBytes! < processedBytes ||
        totalRecordings != null && totalRecordings! < processedRecordings) {
      throw ArgumentError('Invalid backup progress');
    }
  }

  final String taskId;
  final int sequence;
  final BackupOperation operation;
  final BackupStage stage;
  final int processedBytes;
  final int? totalBytes;
  final int processedRecordings;
  final int? totalRecordings;

  /// Stage progress, never overall success. Zero/unknown total is indeterminate.
  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : processedBytes / totalBytes!;

  bool get canCancel => !const {
    BackupStage.committing,
    BackupStage.cancelling,
    BackupStage.completed,
    BackupStage.cancelled,
    BackupStage.failed,
  }.contains(stage);
}
