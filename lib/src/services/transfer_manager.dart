import 'dart:async';

import '../models/transfer.dart';
import 'transfer_persistence.dart';
import 'integrity.dart';

class TransferManager {
  TransferManager._();

  static final TransferManager instance = TransferManager._();

  final TransferQueue _queue = TransferQueue(maxConcurrency: 3, maxQueued: 100);
  final TransferPersistence _persistence = TransferPersistence.instance;
  final Map<String, TransferSpeedCalculator> _speedCalculators = {};
  final StreamController<List<Transfer>> _transfersController =
      StreamController<List<Transfer>>.broadcast();
  final StreamController<Transfer?> _activeTransferController =
      StreamController<Transfer?>.broadcast();

  bool _initialized = false;
  bool _pausedAll = false;

  Stream<List<Transfer>> get transfersStream => _transfersController.stream;
  Stream<Transfer?> get activeTransferStream => _activeTransferController.stream;
  TransferQueue get queue => _queue;
  bool get isPausedAll => _pausedAll;

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadPersistedTransfers();
    _initialized = true;
  }

  Future<void> _loadPersistedTransfers() async {
    final persisted = await _persistence.getActive();
    for (final transfer in persisted) {
      if (!transfer.isTerminal) {
        final queuedTransfer = transfer.copyWith(status: TransferStatus.queued);
        _queue.add(queuedTransfer);
        await _persistence.update(queuedTransfer);
      }
    }
    _emitTransfers();
  }

  void _emitTransfers() {
    final all = _queue.allTransfers;
    _transfersController.add(all);
    if (all.isNotEmpty) {
      _activeTransferController.add(all.firstWhere(
        (t) => t.isActive,
        orElse: () => all.first,
      ));
    } else {
      _activeTransferController.add(null);
    }
  }

  Future<void> addTransfer(Transfer transfer) async {
    _queue.add(transfer);
    await _persistence.insert(transfer);
    _speedCalculators[transfer.id] = TransferSpeedCalculator();
    _emitTransfers();
  }

  Future<void> pauseTransfer(String id) async {
    final transfer = await _persistence.get(id);
    if (transfer == null || !transfer.canPause) return;

    final paused = transfer.copyWith(status: TransferStatus.paused);
    _queue.remove(id);
    await _persistence.update(paused);
    _emitTransfers();
  }

  Future<void> resumeTransfer(String id) async {
    final transfer = await _persistence.get(id);
    if (transfer == null || !transfer.canResume) return;

    final resumed = transfer.copyWith(status: TransferStatus.queued);
    _queue.requeue(resumed);
    await _persistence.update(resumed);
    _emitTransfers();
  }

  Future<void> cancelTransfer(String id) async {
    final transfer = await _persistence.get(id);
    if (transfer == null || !transfer.canCancel) return;

    final cancelled = transfer.copyWith(status: TransferStatus.cancelled);
    _queue.remove(id);
    await _persistence.update(cancelled);
    _speedCalculators.remove(id);
    _emitTransfers();
  }

  Future<void> retryTransfer(String id) async {
    final transfer = await _persistence.get(id);
    if (transfer == null || !transfer.canRetry) return;

    final retried = transfer.copyWith(
      status: TransferStatus.queued,
      retryCount: transfer.retryCount + 1,
      errorMessage: null,
    );
    _queue.requeue(retried);
    await _persistence.update(retried);
    _emitTransfers();
  }

  Future<void> pauseAll() async {
    _pausedAll = true;
    final active = _queue.allTransfers.where((t) => t.isActive).toList();
    for (final transfer in active) {
      await pauseTransfer(transfer.id);
    }
  }

  Future<void> resumeAll() async {
    _pausedAll = false;
    final paused = await _persistence.getAll(status: TransferStatus.paused);
    for (final transfer in paused) {
      await resumeTransfer(transfer.id);
    }
  }

  Future<void> clearCompleted() async {
    final completed = _queue.allTransfers.where((t) => t.status == TransferStatus.completed).toList();
    for (final transfer in completed) {
      _queue.remove(transfer.id);
      await _persistence.delete(transfer.id);
      _speedCalculators.remove(transfer.id);
    }
    _emitTransfers();
  }

  Future<void> clearAll() async {
    _queue.clear();
    await _persistence.deleteAll();
    _speedCalculators.clear();
    _emitTransfers();
  }

  void recordProgress(String id, int bytesTransferred) {
    final calculator = _speedCalculators[id];
    if (calculator != null) {
      calculator.addSample(bytesTransferred, DateTime.now());
    }
  }

  TransferSpeedCalculator? getSpeedCalculator(String id) => _speedCalculators[id];

  Future<void> updateTransferProgress(String id, int bytesTransferred) async {
    await _persistence.updateBytesTransferred(id, bytesTransferred);
    recordProgress(id, bytesTransferred);
    _emitTransfers();
  }

  Future<void> updateTransferStatus(
    String id,
    TransferStatus status, {
    String? errorMessage,
    Map<String, dynamic>? resumeMetadata,
  }) async {
    final transfer = await _persistence.get(id);
    if (transfer == null) return;

    var updated = transfer.copyWith(
      status: status,
      errorMessage: errorMessage ?? transfer.errorMessage,
    );

    if (resumeMetadata != null) {
      updated = updated.copyWith(resumeMetadata: resumeMetadata);
    }

    if (status == TransferStatus.transferring || status == TransferStatus.resuming) {
      _queue.markActive(id);
    } else if (status == TransferStatus.paused) {
      _queue.markInactive(id);
    } else if (status == TransferStatus.completed ||
        status == TransferStatus.cancelled ||
        status == TransferStatus.failed) {
      _queue.remove(id);
      _speedCalculators.remove(id);
    }

    await _persistence.update(updated);
    _emitTransfers();
  }

  Future<void> markActiveForTesting(String id) async {
    _queue.markActive(id);
    _emitTransfers();
  }

  Future<void> markInactiveForTesting(String id) async {
    _queue.markInactive(id);
    _emitTransfers();
  }

  Future<bool> verifyFileIntegrity({
    required String filePath,
    required String expectedHash,
  }) async {
    return IntegrityService.verifyFileHash(
      filePath: filePath,
      expectedHash: expectedHash,
    );
  }

  Future<VerificationResult> verifyChunkedIntegrity({
    required String filePath,
    required ChunkedHashResult expected,
  }) async {
    return IntegrityService.verifyChunkedHash(
      filePath: filePath,
      expected: expected,
    );
  }

  void dispose() {
    // Don't close stream controllers as TransferManager is a singleton
    // that may be reused across tests. Stream controllers will be
    // garbage collected when the isolate shuts down.
    _initialized = false;
  }
}