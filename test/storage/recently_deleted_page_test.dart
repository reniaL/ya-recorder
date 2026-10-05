import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recently_deleted_page.dart';
import 'package:ya_recorder/storage/recording_store.dart';

final _now = DateTime.utc(2026, 10, 5, 12);

class _TrashStore extends RecordingStore {
  _TrashStore()
    : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);

  List<Recording> deleted = [
    Recording(
      id: 'one',
      title: '会议录音',
      filePath: '/private/one.m4a',
      createdAt: _now,
      duration: const Duration(seconds: 12),
      fileSizeBytes: 12,
      deletedAt: _now.subtract(const Duration(days: 2)),
    ),
  ];
  bool fail = false;
  int restoreCalls = 0;
  int deleteCalls = 0;
  int cleanupCalls = 0;
  Completer<void>? gate;

  @override
  Future<List<String>> purgeExpiredRecordings({DateTime? now}) async {
    cleanupCalls++;
    return [];
  }

  @override
  Future<List<Recording>> listRecentlyDeleted() async => deleted;

  @override
  Future<void> restoreRecording(String recordingId, {DateTime? now}) async {
    restoreCalls++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('restore failed');
    deleted = [];
  }

  @override
  Future<void> permanentlyDeleteRecording(String recordingId) async {
    deleteCalls++;
    if (fail) throw StateError('delete failed');
    deleted = [];
  }
}

void main() {
  Future<void> open(WidgetTester tester, _TrashStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedPage(store: store, now: () => _now),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('会议录音的操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows retention, restores and prevents duplicate submission', (
    tester,
  ) async {
    final store = _TrashStore();
    await open(tester, store);
    expect(find.textContaining('剩余 28 天'), findsOneWidget);
    expect(find.textContaining('删除于'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    store.gate = Completer<void>();
    await action(tester, '恢复');
    expect(store.restoreCalls, 1);
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isFalse,
    );
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('最近删除为空'), findsOneWidget);
    expect(find.text('录音已恢复'), findsOneWidget);
  });

  testWidgets('permanent deletion requires confirmation and cancel keeps row', (
    tester,
  ) async {
    final store = _TrashStore();
    await open(tester, store);
    await action(tester, '永久删除');
    expect(find.text('永久删除录音？'), findsOneWidget);
    expect(find.textContaining('无法恢复'), findsOneWidget);
    expect(store.deleteCalls, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('会议录音'), findsOneWidget);
    expect(store.deleteCalls, 0);
    await action(tester, '永久删除');
    await tester.tap(find.widgetWithText(TextButton, '永久删除'));
    await tester.pumpAndSettle();
    expect(store.deleteCalls, 1);
    expect(find.text('最近删除为空'), findsOneWidget);
  });

  testWidgets('failed deletion stays visible and can be retried', (
    tester,
  ) async {
    final store = _TrashStore()..fail = true;
    await open(tester, store);
    await action(tester, '永久删除');
    await tester.tap(find.widgetWithText(TextButton, '永久删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('永久删除失败'), findsOneWidget);
    expect(find.text('会议录音'), findsOneWidget);
    store.fail = false;
    await action(tester, '永久删除');
    await tester.tap(find.widgetWithText(TextButton, '永久删除'));
    await tester.pumpAndSettle();
    expect(store.deleteCalls, 2);
    expect(find.text('最近删除为空'), findsOneWidget);
  });

  testWidgets('expired rows stay hidden and foreground triggers cleanup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _TrashStore();
    await open(tester, store);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(store.cleanupCalls, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedPage(
          store: store,
          now: () => _now.add(const Duration(days: 30)),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('会议录音'), findsNothing);
    expect(find.text('最近删除为空'), findsOneWidget);
  });
}
