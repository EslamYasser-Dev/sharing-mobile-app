import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class IntegrityService {
  static const int _chunkSize = 64 * 1024;

  static Future<String> computeFileHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  static Future<String> computeBytesHash(Uint8List bytes) async {
    return sha256.convert(bytes).toString();
  }

  static Future<String> computeStreamHash(Stream<List<int>> stream) async {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
    }
    return sha256.convert(Uint8List.fromList(buffer)).toString();
  }

  static Future<ChunkedHashResult> computeChunkedHash({
    required String filePath,
    int chunkSize = _chunkSize,
    void Function(int chunkIndex, int totalChunks)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final fileSize = await file.length();
    final totalChunks = (fileSize / chunkSize).ceil();
    final chunkHashes = <String>[];

    final stream = file.openRead();
    var buffer = <int>[];
    var chunkIndex = 0;

    await for (final piece in stream) {
      buffer.addAll(piece);
      while (buffer.length >= chunkSize) {
        final chunk = Uint8List.fromList(buffer.sublist(0, chunkSize));
        buffer = buffer.sublist(chunkSize);
        final hash = sha256.convert(chunk).toString();
        chunkHashes.add(hash);
        chunkIndex++;
        onProgress?.call(chunkIndex, totalChunks);
      }
    }
    if (buffer.isNotEmpty) {
      final hash = sha256.convert(Uint8List.fromList(buffer)).toString();
      chunkHashes.add(hash);
      chunkIndex++;
      onProgress?.call(chunkIndex, totalChunks);
    }

    final fullHash = sha256.convert(chunkHashes.join().codeUnits).toString();
    return ChunkedHashResult(
      fullHash: fullHash,
      chunkHashes: chunkHashes,
      chunkSize: chunkSize,
    );
  }

  static Future<bool> verifyFileHash({
    required String filePath,
    required String expectedHash,
  }) async {
    final actualHash = await computeFileHash(filePath);
    return actualHash == expectedHash;
  }

  static Future<VerificationResult> verifyChunkedHash({
    required String filePath,
    required ChunkedHashResult expected,
    void Function(int chunkIndex, int totalChunks)? onProgress,
  }) async {
    final actual = await computeChunkedHash(
      filePath: filePath,
      chunkSize: expected.chunkSize,
      onProgress: onProgress,
    );

    final mismatchedChunks = <int>[];
    final minChunks = actual.chunkHashes.length < expected.chunkHashes.length
        ? actual.chunkHashes.length
        : expected.chunkHashes.length;
    for (var i = 0; i < minChunks; i++) {
      if (actual.chunkHashes[i] != expected.chunkHashes[i]) {
        mismatchedChunks.add(i);
      }
    }
    if (actual.chunkHashes.length != expected.chunkHashes.length) {
      final maxChunks = actual.chunkHashes.length > expected.chunkHashes.length
          ? actual.chunkHashes.length
          : expected.chunkHashes.length;
      for (var i = minChunks; i < maxChunks; i++) {
        mismatchedChunks.add(i);
      }
    }

    return VerificationResult(
      isValid: mismatchedChunks.isEmpty && actual.fullHash == expected.fullHash,
      fullHashMatch: actual.fullHash == expected.fullHash,
      mismatchedChunks: mismatchedChunks,
      actual: actual,
      expected: expected,
    );
  }
}

class ChunkedHashResult {
  const ChunkedHashResult({
    required this.fullHash,
    required this.chunkHashes,
    required this.chunkSize,
  });

  final String fullHash;
  final List<String> chunkHashes;
  final int chunkSize;

  Map<String, dynamic> toJson() => {
    'fullHash': fullHash,
    'chunkHashes': chunkHashes,
    'chunkSize': chunkSize,
  };

  factory ChunkedHashResult.fromJson(Map<String, dynamic> json) => ChunkedHashResult(
    fullHash: json['fullHash'] as String,
    chunkHashes: (json['chunkHashes'] as List).cast<String>(),
    chunkSize: json['chunkSize'] as int,
  );
}

class VerificationResult {
  const VerificationResult({
    required this.isValid,
    required this.fullHashMatch,
    required this.mismatchedChunks,
    required this.actual,
    required this.expected,
  });

  final bool isValid;
  final bool fullHashMatch;
  final List<int> mismatchedChunks;
  final ChunkedHashResult actual;
  final ChunkedHashResult expected;
}

class StreamingHashSink {
  StreamingHashSink();

  final _buffer = <int>[];
  IOSink? _fileSink;
  int _bytesWritten = 0;

  void add(List<int> data) {
    _buffer.addAll(data);
    _bytesWritten += data.length;
    _fileSink?.add(data);
  }

  void addError(Object error, [StackTrace? stackTrace]) {
    _fileSink?.addError(error, stackTrace);
  }

  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  Future<String> close() async {
    await _fileSink?.close();
    _fileSink = null;
    return sha256.convert(Uint8List.fromList(_buffer)).toString();
  }

  String get currentHash => sha256.convert(Uint8List.fromList(_buffer)).toString();
  int get bytesWritten => _bytesWritten;
}

extension StreamingHash on Stream<List<int>> {
  Future<String> sha256Hash() async {
    final buffer = <int>[];
    await for (final chunk in this) {
      buffer.addAll(chunk);
    }
    return sha256.convert(Uint8List.fromList(buffer)).toString();
  }
}