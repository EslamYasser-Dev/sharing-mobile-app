import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transfer.dart';
import '../services/download_service.dart'
    show DownloadCancelledException, HttpDownloadService;
import '../services/transfer_persistence.dart';
import '../services/upload_service.dart'
    show HttpUploadService, UploadCancelledException;

/// Hooks handed to the transfer executor so pause/resume/cancel work
/// uniformly across transports without the executor knowing UI details.
class TransferHooks {
  TransferHooks({this.onProgress, this.awaitResume, this.shouldCancel});

  void Function(int transferred, int total)? onProgress;
  Future<bool> Function()? awaitResume;
  bool Function()? shouldCancel;
}

/// Runs one transfer to completion (or throws). Injected for tests.
typedef TransferExecutor =
    Future<void> Function(Transfer transfer, TransferHooks hooks);

final transferControllerProvider =
    NotifierProvider<TransferController, List<Transfer>>(
      TransferController.new,
    );

/// High-frequency byte counters, one entry per live transfer. Progress ticks
/// (5 Hz) update only this map, so progress bars watching a single entry via
/// `select` rebuild alone — the transfer list, and every screen watching it,
/// stays quiet. The list itself refreshes bytes at ~1 Hz plus every terminal
/// event, so slow polls and fallbacks never show stale data for long.
class _TransferProgress extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void set(String id, int bytes) {
    if (state[id] == bytes) return;
    state = {...state, id: bytes};
  }

  void remove(String id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}

final transferProgressProvider =
    NotifierProvider<_TransferProgress, Map<String, int>>(
      _TransferProgress.new,
    );

/// Aggregate stats for the transfers header / pill.
class TransferStats {
  const TransferStats({
    required this.uploadSpeed,
    required this.downloadSpeed,
    required this.activeCount,
    required this.queuedCount,
  });

  final double uploadSpeed;
  final double downloadSpeed;
  final int activeCount;
  final int queuedCount;

  static const empty = TransferStats(
    uploadSpeed: 0,
    downloadSpeed: 0,
    activeCount: 0,
    queuedCount: 0,
  );
}

/// Riverpod facade over parallel resumable transfers.
///
/// Single-threaded Dart makes state mutation race-free: every mutation goes
/// through [_update], workers are bounded ([maxConcurrency]), progress emits
/// are throttled to 5 Hz, and persistence writes are throttled to 500 ms.
class TransferController extends Notifier<List<Transfer>> {
  static const int maxConcurrency = 3;
  static const int maxQueued = 100;
  static const int maxRetries = 3;

  static const Duration _slowEmitInterval = Duration(seconds: 1);
  static const Duration _persistInterval = Duration(milliseconds: 500);

  TransferExecutor? _executorOverride;

  final Map<String, Future<void>> _workers = {};
  final Map<String, bool> _cancelFlags = {};
  final Map<String, Completer<void>> _resumeGates = {};
  final Map<String, TransferSpeedCalculator> _speed = {};
  final Map<String, DateTime> _lastEmit = {};
  final Map<String, DateTime> _lastPersist = {};
  final Map<String, int> _lastPersistedBytes = {};

  final Random _jitter = Random.secure();
  bool _pumpScheduled = false;

  HttpUploadService? _uploads;
  HttpDownloadService? _downloads;

  /// Test hook: replace the real network executor with a fake.
  // coverage:ignore-start (test hook)
  void debugSetExecutor(TransferExecutor? executor) {
    _executorOverride = executor;
  }
  // coverage:ignore-end

  @override
  List<Transfer> build() {
    ref.onDispose(_onDispose);
    unawaited(_restore());
    return [];
  }

  void _onDispose() {
    for (final gate in _resumeGates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    _resumeGates.clear();
    _cancelFlags.clear();
  }

  // ------------------------------------------------------------ enqueue

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = _jitter.nextInt(1 << 32).toRadixString(36);
    return '$stamp-$rand';
  }

  Future<String> enqueueUpload({
    required String fileName,
    required String dirPath,
    File? file,
    List<int>? bytes,
  }) async {
    late final File source;
    var size = 0;
    var cleanupTemp = false;
    if (file != null) {
      source = file;
      size = await file.length();
    } else {
      final data = bytes ?? const <int>[];
      size = data.length;
      final dir = await getTemporaryDirectory();
      source = File(
        '${dir.path}/upload-${DateTime.now().millisecondsSinceEpoch}-$fileName',
      );
      await source.writeAsBytes(data, flush: true);
      cleanupTemp = true;
    }
    final now = DateTime.now();
    final transfer = Transfer(
      id: _newId(),
      fileId: 'local-$fileName-$size',
      name: fileName,
      size: size,
      direction: TransferDirection.upload,
      status: TransferStatus.queued,
      localPath: source.path,
      destinationPath: dirPath,
      createdAt: now,
      updatedAt: now,
      transport: TransferTransportType.http,
      resumeMetadata: cleanupTemp ? const {'tempSource': true} : const {},
    );
    await _add(transfer);
    return transfer.id;
  }

  Future<String> enqueueDownload({
    required String remotePath,
    required String name,
    required int size,
    String? sha256Hash,
  }) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now();
    final transfer = Transfer(
      id: _newId(),
      fileId: 'remote-$remotePath',
      name: name,
      size: size,
      direction: TransferDirection.download,
      status: TransferStatus.queued,
      localPath: '${dir.path}/$stamp-$name',
      destinationPath: remotePath,
      sha256Hash: sha256Hash,
      createdAt: now,
      updatedAt: now,
      transport: TransferTransportType.http,
    );
    await _add(transfer);
    return transfer.id;
  }

  Future<void> _add(Transfer transfer) async {
    if (state.length >= maxQueued) {
      throw StateError('Transfer queue full (max $maxQueued)');
    }
    await TransferPersistence.instance.insert(transfer);
    _speed[transfer.id] = TransferSpeedCalculator();
    state = [...state, transfer];
    _pump();
  }

  Future<void> _restore() async {
    final persisted = await TransferPersistence.instance.getActive();
    if (persisted.isEmpty) return;
    final now = DateTime.now();
    final restorable = <Transfer>[];
    for (final t in persisted) {
      if (t.isTerminal) continue;
      final resumed = t.status == TransferStatus.completed
          ? t
          : t.copyWith(status: TransferStatus.queued, updatedAt: now);
      await TransferPersistence.instance.update(resumed);
      _speed[resumed.id] = TransferSpeedCalculator();
      restorable.add(resumed);
    }
    state = [...state, ...restorable];
    _pump();
  }

  // ------------------------------------------------------------ controls

  Future<void> pauseTransfer(String id) async {
    final t = _byId(id);
    if (t == null || !t.canPause) return;
    await _setStatus(id, TransferStatus.paused);
    _pump();
  }

  Future<void> resumeTransfer(String id) async {
    final t = _byId(id);
    if (t == null || !t.canResume) return;
    final gate = _resumeGates.remove(id);
    if (gate != null && !gate.isCompleted) gate.complete();
    await _setStatus(
      id,
      TransferStatus.resuming,
      retryCount: t.status == TransferStatus.failed ? t.retryCount + 1 : t.retryCount,
      clearError: true,
    );
    // A still-running worker (blocked in _awaitResume's gate when it was
    // paused) resumes in place; _awaitResume now owns returning it to
    // `transferring`. A finished/failed worker has no gate in flight, so
    // re-queue it for a fresh attempt.
    if (_workers.containsKey(id)) return;
    await _setStatus(id, TransferStatus.queued);
    _pump();
  }

  Future<void> cancelTransfer(String id) async {
    final t = _byId(id);
    if (t == null || !t.canCancel) return;
    _cancelFlags[id] = true;
    final gate = _resumeGates.remove(id);
    if (gate != null && !gate.isCompleted) gate.complete();
    if (!_workers.containsKey(id)) {
      await _setStatus(id, TransferStatus.cancelled);
      await _cleanup(id);
    }
    // else: worker notices the flag and finalizes as cancelled
  }

  Future<void> retryTransfer(String id) => resumeTransfer(id);

  Future<void> dismissTransfer(String id) async {
    final t = _byId(id);
    if (t == null || !t.isTerminal) return;
    state = state.where((e) => e.id != id).toList(growable: false);
    _speed.remove(id);
    await TransferPersistence.instance.delete(id);
  }

  Future<void> pauseAll() async {
    for (final t in state) {
      if (t.canPause) await pauseTransfer(t.id);
    }
  }

  Future<void> resumeAll() async {
    for (final t in state) {
      if (t.status == TransferStatus.paused ||
          t.status == TransferStatus.failed) {
        await resumeTransfer(t.id);
      }
    }
  }

  Future<void> clearCompleted() async {
    final done = state
        .where((t) => t.status == TransferStatus.completed)
        .map((t) => t.id)
        .toList();
    state = state.where((t) => t.status != TransferStatus.completed).toList();
    for (final id in done) {
      _speed.remove(id);
      await TransferPersistence.instance.delete(id);
    }
  }

  TransferSpeedCalculator? getSpeedCalculator(String id) => _speed[id];

  TransferStats stats() {
    final now = DateTime.now();
    var up = 0.0;
    var down = 0.0;
    var active = 0;
    var queued = 0;
    for (final t in state) {
      if (t.status == TransferStatus.queued) queued++;
      if (!t.isActive) continue;
      active++;
      final s = _speed[t.id]?.getSmoothedSpeed(now) ?? 0;
      if (t.direction == TransferDirection.download ||
          t.direction == TransferDirection.p2pReceive) {
        down += s;
      } else {
        up += s;
      }
    }
    return TransferStats(
      uploadSpeed: up,
      downloadSpeed: down,
      activeCount: active,
      queuedCount: queued,
    );
  }

  Transfer? _byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ------------------------------------------------------------ pump/workers

  void _pump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pumpNow();
    });
  }

  void _pumpNow() {
    if (!ref.mounted) return;
    // Reap finished workers.
    _workers.removeWhere((_, f) => _isDone(f));
    while (_workers.length < maxConcurrency) {
      Transfer? next;
      for (final t in state) {
        if (t.status == TransferStatus.queued && !_workers.containsKey(t.id)) {
          next = t;
          break;
        }
      }
      if (next == null) break;
      final id = next.id;
      _workers[id] = _runGuarded(id);
    }
  }

  bool _isDone(Future<void> f) {
    var done = false;
    f.then((_) => done = true, onError: (_) => done = true);
    return done;
  }

  Future<void> _runGuarded(String id) async {
    try {
      await _run(id);
    } finally {
      _workers.remove(id);
      _cancelFlags.remove(id);
      _pump();
    }
  }

  Future<void> _run(String id) async {
    var transfer = _byId(id);
    if (transfer == null) return;
    if (_cancelFlags[id] == true) {
      await _setStatus(id, TransferStatus.cancelled);
      await _cleanup(id);
      return;
    }
    await _setStatus(id, TransferStatus.preparing);
    await _setStatus(id, TransferStatus.connecting);

    var attempt = transfer.retryCount;
    while (true) {
      transfer = _byId(id);
      if (transfer == null || _cancelFlags[id] == true) {
        await _setStatus(id, TransferStatus.cancelled);
        await _cleanup(id);
        return;
      }
      await _setStatus(id, TransferStatus.transferring);
      try {
        final hooks = TransferHooks(
          onProgress: (sent, total) => _onProgress(id, sent, total),
          awaitResume: () => _awaitResume(id),
          shouldCancel: () => _cancelFlags[id] == true,
        );
        final exec = _executorOverride ?? _defaultExecute;
        await exec(transfer, hooks);
        await _setStatus(id, TransferStatus.verifying);
        await _setStatus(
          id,
          TransferStatus.completed,
          completedAt: DateTime.now(),
        );
        _lastPersist.remove(id);
        _lastPersistedBytes.remove(id);
        return;
      } on _Paused {
        await _setStatus(id, TransferStatus.paused);
        return; // resume re-queues via resumeTransfer
      } on _Cancelled
      catch (_) {
        await _setStatus(id, TransferStatus.cancelled);
        await _cleanup(id);
        return;
      } on UploadCancelledException
      catch (_) {
        await _setStatus(id, TransferStatus.cancelled);
        await _cleanup(id);
        return;
      } on DownloadCancelledException
      catch (_) {
        await _setStatus(id, TransferStatus.cancelled);
        await _cleanup(id);
        return;
      } catch (error) {
        if (_cancelFlags[id] == true) {
          await _setStatus(id, TransferStatus.cancelled);
          await _cleanup(id);
          return;
        }
        attempt++;
        final msg = _friendlyMessage(error);
        if (!_isRetryable(error) || attempt > maxRetries) {
          await _setStatus(
            id,
            TransferStatus.failed,
            errorMessage: msg,
            retryCount: attempt,
          );
          return;
        }
        await _setStatus(
          id,
          TransferStatus.retrying,
          errorMessage: msg,
          retryCount: attempt,
        );
        final backoff = Duration(
          milliseconds:
              (1000 * (1 << (attempt - 1).clamp(0, 4)) + _jitter.nextInt(500))
                  .clamp(1000, 30000),
        );
        await Future<void>.delayed(backoff);
        if (_cancelFlags[id] == true) {
          await _setStatus(id, TransferStatus.cancelled);
          await _cleanup(id);
          return;
        }
      }
    }
  }

  Future<bool> _awaitResume(String id) async {
    final t = _byId(id);
    if (t == null || t.status != TransferStatus.paused) return false;
    final gate =
        _resumeGates.putIfAbsent(id, () => Completer<void>());
    await gate.future;
    if (_cancelFlags[id] == true) throw _Cancelled();
    // Break the `resuming` interlude so the UI tracks that the live worker
    // is moving bytes again.
    await _setStatus(id, TransferStatus.transferring);
    return true;
  }

  Future<void> _defaultExecute(Transfer transfer, TransferHooks hooks) async {
    _uploads ??= HttpUploadService();
    _downloads ??= HttpDownloadService();
    _uploads!.setPersistence(TransferPersistence.instance);
    _downloads!.setPersistence(TransferPersistence.instance);
    switch (transfer.direction) {
      case TransferDirection.upload:
        await _uploads!.uploadFile(
          transfer: transfer,
          file: File(transfer.localPath),
          onProgress: hooks.onProgress,
          awaitResume: hooks.awaitResume,
          shouldCancel: hooks.shouldCancel,
        );
      case TransferDirection.download:
        await _downloads!.downloadFile(
          transfer: transfer,
          remotePath: transfer.destinationPath ?? transfer.fileId,
          localPath: transfer.localPath,
          onProgress: hooks.onProgress,
          awaitResume: hooks.awaitResume,
          shouldCancel: hooks.shouldCancel,
        );
      case TransferDirection.p2pSend:
      case TransferDirection.p2pReceive:
        throw StateError(
          'P2P transfers run in the Direct tab session, not the HTTP queue',
        );
    }
  }

  void _onProgress(String id, int sent, int total) {
    final calc = _speed.putIfAbsent(id, () => TransferSpeedCalculator());
    calc.addSample(sent, DateTime.now());
    final now = DateTime.now();
    final terminal = sent >= total;
    // Fast path: progress map only, so just the bar rebuilds.
    ref.read(transferProgressProvider.notifier).set(id, sent);
    _throttledPersist(id, sent);
    if (terminal) {
      _lastEmit[id] = now;
      _dropProgress(id);
      _setBytes(id, sent);
      return;
    }
    // Slow path: list state at ~1 Hz for counts, fallbacks, and persistence
    // of the visible number.
    final last = _lastEmit[id];
    if (last != null && now.difference(last) < _slowEmitInterval) return;
    _lastEmit[id] = now;
    _setBytes(id, sent);
  }

  void _dropProgress(String id) {
    ref.read(transferProgressProvider.notifier).remove(id);
  }

  void _throttledPersist(String id, int sent) {
    final now = DateTime.now();
    final last = _lastPersist[id];
    final lastBytes = _lastPersistedBytes[id] ?? -1;
    if (last != null &&
        now.difference(last) < _persistInterval &&
        (sent - lastBytes).abs() < 262144) {
      return;
    }
    _lastPersist[id] = now;
    _lastPersistedBytes[id] = sent;
    unawaited(TransferPersistence.instance.updateBytesTransferred(id, sent));
  }

  void _setBytes(String id, int sent) {
    final t = _byId(id);
    if (t == null) return;
    final clamped = sent.clamp(0, t.size);
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(bytesTransferred: clamped) else e,
    ];
  }

  Future<void> _setStatus(
    String id,
    TransferStatus status, {
    String? errorMessage,
    int? retryCount,
    bool clearError = false,
    DateTime? completedAt,
  }) async {
    final t = _byId(id);
    if (t == null) return;
    if (status == TransferStatus.completed ||
        status == TransferStatus.failed ||
        status == TransferStatus.cancelled) {
      _dropProgress(id);
    }
    final next = t.copyWith(
      status: status,
      errorMessage: clearError ? null : (errorMessage ?? t.errorMessage),
      retryCount: retryCount ?? t.retryCount,
      completedAt: completedAt ?? t.completedAt,
      updatedAt: DateTime.now(),
    );
    state = [
      for (final e in state)
        if (e.id == id) next else e,
    ];
    await TransferPersistence.instance.update(next);
  }

  Future<void> _cleanup(String id) async {
    final t = _byId(id);
    _resumeGates.remove(id);
    // Remove staged download remainder only on cancel; keep for pause.
    if (t != null &&
        t.status == TransferStatus.cancelled &&
        t.direction == TransferDirection.download) {
      try {
        final part = File('${t.localPath}.part');
        if (await part.exists()) await part.delete();
      } catch (_) {}
    }
    if (t != null &&
        t.status == TransferStatus.cancelled &&
        t.direction == TransferDirection.upload) {
      final sessionId = t.resumeMetadata['sessionId'] as String?;
      if (sessionId != null && sessionId.isNotEmpty) {
        try {
          _uploads ??= HttpUploadService();
          await _uploads!.abortSession(sessionId);
        } catch (_) {}
      }
      if (t.resumeMetadata['tempSource'] == true) {
        try {
          final f = File(t.localPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  bool _isRetryable(Object error) {
    if (error is _Cancelled || error is _Paused) return false;
    final msg = error.toString();
    if (msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('404') ||
        msg.contains('quota') ||
        msg.contains('Quota')) {
      return false;
    }
    if (error is SocketException || error is TimeoutException) return true;
    if (error is HttpException) return true;
    return true;
  }

  String _friendlyMessage(Object error) {
    final msg = error.toString();
    if (error is SocketException) {
      return 'Connection was interrupted. The transfer will retry automatically.';
    }
    if (error is TimeoutException) {
      return 'The server is taking too long to respond. The transfer will retry automatically.';
    }
    if (msg.contains('401') || msg.contains('Not authorized')) {
      return 'Your session expired. Please sign in again.';
    }
    if (msg.contains('quota') || msg.contains('Quota')) {
      return 'Not enough storage space for this transfer.';
    }
    if (msg.contains('No space') || msg.contains('disk full')) {
      return 'Your device is out of storage space.';
    }
    if (msg.length > 160) return msg.substring(0, 160);
    return msg.replaceFirst(RegExp(r'^.*Exception:\s*'), '');
  }
}

class _Paused implements Exception {
  const _Paused();
}

class _Cancelled implements Exception {
  const _Cancelled();
}
