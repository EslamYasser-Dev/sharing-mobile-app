import 'dart:async';
import 'dart:convert';

enum TransferDirection {
  upload,
  download,
  p2pSend,
  p2pReceive,
}

enum TransferStatus {
  queued,
  preparing,
  connecting,
  transferring,
  paused,
  resuming,
  verifying,
  completed,
  failed,
  cancelled,
  retrying,
}

enum TransferTransportType {
  grpc,
  http,
  webrtc,
  bluetooth,
}

class Transfer {
  const Transfer({
    required this.id,
    required this.fileId,
    required this.name,
    required this.size,
    required this.direction,
    required this.status,
    this.bytesTransferred = 0,
    this.remotePeerId,
    this.remotePeerName,
    required this.localPath,
    this.destinationPath,
    this.sha256Hash,
    this.partialHash,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.errorMessage,
    this.retryCount = 0,
    this.resumeMetadata = const {},
    required this.transport,
    this.priority = 0,
  });

  final String id;
  final String fileId;
  final String name;
  final int size;
  final int bytesTransferred;
  final TransferDirection direction;
  final TransferStatus status;
  final String? remotePeerId;
  final String? remotePeerName;
  final String localPath;
  final String? destinationPath;
  final String? sha256Hash;
  final String? partialHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? errorMessage;
  final int retryCount;
  final Map<String, dynamic> resumeMetadata;
  final TransferTransportType transport;
  final int priority;

  double get progress {
    if (size <= 0) return status == TransferStatus.completed ? 1.0 : 0.0;
    final value = bytesTransferred / size;
    if (value <= 0) return 0.0;
    if (value >= 1) return 1.0;
    return value;
  }

  bool get isTerminal =>
      status == TransferStatus.completed ||
      status == TransferStatus.cancelled ||
      status == TransferStatus.failed;

  bool get isActive =>
      status == TransferStatus.preparing ||
      status == TransferStatus.connecting ||
      status == TransferStatus.transferring ||
      status == TransferStatus.resuming ||
      status == TransferStatus.verifying;

  bool get canPause =>
      status == TransferStatus.transferring ||
      status == TransferStatus.connecting ||
      status == TransferStatus.preparing;

  bool get canResume =>
      status == TransferStatus.paused ||
      status == TransferStatus.failed ||
      status == TransferStatus.retrying;

  bool get canCancel => !isTerminal;

  bool get canRetry =>
      status == TransferStatus.failed && retryCount < 3;

  Transfer copyWith({
    String? id,
    String? fileId,
    String? name,
    int? size,
    int? bytesTransferred,
    TransferDirection? direction,
    TransferStatus? status,
    String? remotePeerId,
    String? remotePeerName,
    String? localPath,
    String? destinationPath,
    String? sha256Hash,
    String? partialHash,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    String? errorMessage,
    int? retryCount,
    Map<String, dynamic>? resumeMetadata,
    TransferTransportType? transport,
    int? priority,
  }) {
    return Transfer(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      name: name ?? this.name,
      size: size ?? this.size,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      remotePeerId: remotePeerId ?? this.remotePeerId,
      remotePeerName: remotePeerName ?? this.remotePeerName,
      localPath: localPath ?? this.localPath,
      destinationPath: destinationPath ?? this.destinationPath,
      sha256Hash: sha256Hash ?? this.sha256Hash,
      partialHash: partialHash ?? this.partialHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      resumeMetadata: resumeMetadata ?? this.resumeMetadata,
      transport: transport ?? this.transport,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_id': fileId,
      'name': name,
      'size': size,
      'bytes_transferred': bytesTransferred,
      'direction': direction.name,
      'status': status.name,
      'remote_peer_id': remotePeerId,
      'remote_peer_name': remotePeerName,
      'local_path': localPath,
      'destination_path': destinationPath,
      'sha256_hash': sha256Hash,
      'partial_hash': partialHash,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'error_message': errorMessage,
      'retry_count': retryCount,
      'resume_metadata': jsonEncode(resumeMetadata),
      'transport': transport.name,
      'priority': priority,
    };
  }

  factory Transfer.fromJson(Map<String, dynamic> json) {
    final resumeMetadataStr = json['resume_metadata'] as String? ?? '{}';
    return Transfer(
      id: json['id'] as String,
      fileId: json['file_id'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      bytesTransferred: json['bytes_transferred'] as int? ?? 0,
      direction: TransferDirection.values.byName(json['direction'] as String),
      status: TransferStatus.values.byName(json['status'] as String),
      remotePeerId: json['remote_peer_id'] as String?,
      remotePeerName: json['remote_peer_name'] as String?,
      localPath: json['local_path'] as String,
      destinationPath: json['destination_path'] as String?,
      sha256Hash: json['sha256_hash'] as String?,
      partialHash: json['partial_hash'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
      retryCount: json['retry_count'] as int? ?? 0,
      resumeMetadata: Map<String, dynamic>.from(jsonDecode(resumeMetadataStr) as Map),
      transport: TransferTransportType.values.byName(json['transport'] as String),
      priority: json['priority'] as int? ?? 0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static Transfer fromJsonString(String str) => Transfer.fromJson(jsonDecode(str) as Map<String, dynamic>);
}

class TransferStateError implements Exception {
  const TransferStateError(this.message, this.transfer);
  final String message;
  final Transfer transfer;

  @override
  String toString() => 'TransferStateError: $message (transfer: ${transfer.id})';
}

class TransferQueue {
  TransferQueue({this.maxConcurrency = 3, this.maxQueued = 100});

  final int maxConcurrency;
  final int maxQueued;

  final List<Transfer> _queue = [];
  final Set<String> _activeIds = {};

  int get activeCount => _activeIds.length;
  int get queuedCount => _queue.length;
  int get totalCount => _queue.length + _activeIds.length;

  List<Transfer> get allTransfers => [..._queue];

  void add(Transfer transfer) {
    if (totalCount >= maxQueued) {
      throw StateError('Transfer queue full (max $maxQueued)');
    }
    _insertByPriority(transfer);
  }

  void _insertByPriority(Transfer transfer) {
    int index = 0;
    while (index < _queue.length && _queue[index].priority >= transfer.priority) {
      index++;
    }
    _queue.insert(index, transfer);
  }

  Transfer? next() {
    if (_activeIds.length >= maxConcurrency) return null;
    if (_queue.isEmpty) return null;

    final transfer = _queue.removeAt(0);
    _activeIds.add(transfer.id);
    return transfer;
  }

  void markActive(String id) {
    _activeIds.add(id);
  }

  void markInactive(String id) {
    _activeIds.remove(id);
  }

  void requeue(Transfer transfer) {
    _activeIds.remove(transfer.id);
    _insertByPriority(transfer);
  }

  void remove(String id) {
    _queue.removeWhere((t) => t.id == id);
    _activeIds.remove(id);
  }

  void clear() {
    _queue.clear();
    _activeIds.clear();
  }

  bool isActive(String id) => _activeIds.contains(id);
}

class TransferSpeedCalculator {
  static const Duration _window = Duration(seconds: 3);

  final List<_SpeedSample> _samples = [];

  void addSample(int bytes, DateTime timestamp) {
    _samples.add(_SpeedSample(bytes: bytes, timestamp: timestamp));
    _purgeOldSamples(timestamp);
  }

  void _purgeOldSamples(DateTime now) {
    final cutoff = now.subtract(_window);
    _samples.removeWhere((s) => s.timestamp.isBefore(cutoff));
  }

  double getCurrentSpeed(DateTime now) {
    _purgeOldSamples(now);
    if (_samples.length < 2) return 0;

    final oldest = _samples.first;
    final newest = _samples.last;
    final duration = newest.timestamp.difference(oldest.timestamp).inMilliseconds;
    if (duration <= 0) return 0;

    final totalBytes = _samples.fold<int>(0, (sum, s) => sum + s.bytes);
    return (totalBytes / duration) * 1000; // bytes/second
  }

  double getSmoothedSpeed(DateTime now) {
    final current = getCurrentSpeed(now);
    return current; // Simple implementation; can add EMA later
  }

  Duration? estimateRemaining(int bytesTransferred, int totalSize, DateTime now) {
    if (totalSize <= 0) return null;
    final remaining = totalSize - bytesTransferred;
    if (remaining <= 0) return Duration.zero;

    final speed = getSmoothedSpeed(now);
    if (speed <= 0) return null;

    final seconds = remaining / speed;
    return Duration(seconds: seconds.ceil());
  }

  void reset() {
    _samples.clear();
  }
}

class _SpeedSample {
  final int bytes;
  final DateTime timestamp;
  _SpeedSample({required this.bytes, required this.timestamp});
}

abstract class TransferControllerInterface {
  Stream<List<Transfer>> get transfersStream;
  Stream<Transfer?> get activeTransferStream;
  Future<void> addTransfer(Transfer transfer);
  Future<void> pauseTransfer(String id);
  Future<void> resumeTransfer(String id);
  Future<void> cancelTransfer(String id);
  Future<void> retryTransfer(String id);
  Future<void> pauseAll();
  Future<void> resumeAll();
  Future<void> clearCompleted();
  Future<void> clearAll();
}