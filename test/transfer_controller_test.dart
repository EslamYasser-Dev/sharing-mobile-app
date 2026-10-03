import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:simplefileshare/src/models/transfer.dart';
import 'package:simplefileshare/src/services/transfer_persistence.dart';
import 'package:simplefileshare/src/state/transfer_controller.dart';

/// Fake executor: N progress steps with per-step pause/cancel hooks,
/// mirroring how the real HTTP services drive [TransferHooks].
TransferExecutor _steppedFake({int steps = 40, int stepMs = 10}) {
  return (Transfer transfer, TransferHooks hooks) async {
    for (var i = 1; i <= steps; i++) {
      if (hooks.shouldCancel?.call() ?? false) {
        throw StateError('cancelled in fake');
      }
      if (hooks.awaitResume != null) await hooks.awaitResume!();
      if (hooks.shouldCancel?.call() ?? false) {
        throw StateError('cancelled in fake');
      }
      hooks.onProgress?.call(
        (transfer.size * i / steps).round(),
        transfer.size,
      );
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
  };
}

Future<void> _failingExecutor(Transfer t, TransferHooks hooks) async {
  throw const _FakeNetworkError();
}

class _FakeNetworkError implements Exception {
  const _FakeNetworkError();
  @override
  String toString() => 'SocketException: connection reset by peer';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TransferPersistence.debugDatabaseName = 'test_transfer_controller.db';
    await TransferPersistence.instance.debugReset();
  });

  setUp(() async {
    await TransferPersistence.instance.deleteAll();
  });

  ProviderContainer _container({TransferExecutor? executor}) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (executor != null) {
      container
          .read(transferControllerProvider.notifier)
          .debugSetExecutor(executor);
    }
    return container;
  }

  Future<String> _enqueue(
    ProviderContainer c, {
    int size = 1000,
  }) async {
    // Real temp file via dart:io (no platform channels needed).
    final dir = await Directory.systemTemp.createTemp('tc_');
    final file = File('${dir.path}/f.bin');
    await file.writeAsBytes(Uint8List.fromList(List<int>.filled(size, 7)));
    return c.read(transferControllerProvider.notifier).enqueueUpload(
          fileName: 'f.bin',
          dirPath: '',
          file: file,
        );
  }

  Future<Transfer> waitForTransfer(
    ProviderContainer c,
    String id,
    TransferStatus status,
  ) async {
    for (var i = 0; i < 400; i++) {
      final list = c.read(transferControllerProvider);
      final match = list.where((t) => t.id == id);
      if (match.isNotEmpty && match.first.status == status) {
        return match.first;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw TimeoutException('Transfer $id did not reach $status');
  }

  test('enqueue completes with progress, speed and stats', () async {
    final c = _container(executor: _steppedFake(steps: 4, stepMs: 5));
    final id = await _enqueue(c);
    final done = await waitForTransfer(c, id, TransferStatus.completed);
    expect(done.bytesTransferred, 1000);
    expect(done.progress, 1.0);
    final stats = c.read(transferControllerProvider.notifier).stats();
    expect(stats.activeCount, 0);
    expect(
      c.read(transferControllerProvider.notifier).getSpeedCalculator(id),
      isNotNull,
    );
  });

  test('pause parks the worker; resume completes it', () async {
    final c = _container(executor: _steppedFake(steps: 40, stepMs: 10));
    final notifier = c.read(transferControllerProvider.notifier);
    final id = await _enqueue(c, size: 4000);
    // Mid-flight with margin (40 steps x 10ms = ~400ms; pause at ~80ms).
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await notifier.pauseTransfer(id);
    expect(
      c.read(transferControllerProvider).firstWhere((t) => t.id == id).status,
      TransferStatus.paused,
    );
    await notifier.resumeTransfer(id);
    final done = await waitForTransfer(c, id, TransferStatus.completed);
    expect(done.bytesTransferred, 4000);
  });

  test('cancel terminates; unknown ids are safe no-ops', () async {
    final c = _container(executor: _steppedFake(steps: 40, stepMs: 10));
    final notifier = c.read(transferControllerProvider.notifier);
    final id = await _enqueue(c);
    await notifier.cancelTransfer(id);
    final cancelled = await waitForTransfer(c, id, TransferStatus.cancelled);
    expect(cancelled.canCancel, isFalse);
    await notifier.pauseTransfer('nope');
    await notifier.resumeTransfer('nope');
    await notifier.cancelTransfer('nope');
    await notifier.retryTransfer('nope');
  });

  test('pauseAll/resumeAll batch; clearCompleted empties', () async {
    final c = _container(executor: _steppedFake(steps: 4, stepMs: 5));
    final notifier = c.read(transferControllerProvider.notifier);
    final a = await _enqueue(c);
    final b = await _enqueue(c);
    await waitForTransfer(c, a, TransferStatus.completed);
    await waitForTransfer(c, b, TransferStatus.completed);
    await notifier.clearCompleted();
    expect(c.read(transferControllerProvider), isEmpty);
    await notifier.pauseAll();
    await notifier.resumeAll();
  });

  test('failing executor surfaces failed with friendly message', () async {
    final c = _container(executor: _failingExecutor);
    final id = await _enqueue(c, size: 100);
    Transfer? terminal;
    for (var i = 0; i < 300; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final list = c.read(transferControllerProvider);
      final match = list.where((t) => t.id == id);
      if (match.isNotEmpty && match.first.isTerminal) {
        terminal = match.first;
        break;
      }
    }
    expect(terminal, isNotNull);
    expect(terminal!.status, TransferStatus.failed);
    expect(terminal.errorMessage, isNotNull);
    expect(terminal.canRetry, isFalse); // retries exhausted
  }, timeout: const Timeout(Duration(seconds: 60)));
}
