import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:simplefileshare/src/models/transfer.dart';
import 'package:simplefileshare/src/services/integrity.dart';

void main() {
  group('Transfer', () {
    test('creates a transfer with all required fields', () {
      final transfer = Transfer(
        id: 'test-id',
        fileId: 'file-123',
        name: 'test.txt',
        size: 1000,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/test.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      );

      expect(transfer.id, 'test-id');
      expect(transfer.fileId, 'file-123');
      expect(transfer.name, 'test.txt');
      expect(transfer.size, 1000);
      expect(transfer.direction, TransferDirection.upload);
      expect(transfer.status, TransferStatus.queued);
      expect(transfer.localPath, '/tmp/test.txt');
      expect(transfer.transport, TransferTransportType.http);
    });

    test('progress is 0 for new transfer', () {
      final transfer = Transfer(
        id: 'test-id',
        fileId: 'file-123',
        name: 'test.txt',
        size: 1000,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/test.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      );

      expect(transfer.progress, 0.0);
    });

    test('progress is 1.0 for completed transfer', () {
      final transfer = Transfer(
        id: 'test-id',
        fileId: 'file-123',
        name: 'test.txt',
        size: 1000,
        bytesTransferred: 1000,
        direction: TransferDirection.upload,
        status: TransferStatus.completed,
        localPath: '/tmp/test.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      );

      expect(transfer.progress, 1.0);
    });

    test('progress is correct for partial transfer', () {
      final transfer = Transfer(
        id: 'test-id',
        fileId: 'file-123',
        name: 'test.txt',
        size: 1000,
        bytesTransferred: 500,
        direction: TransferDirection.upload,
        status: TransferStatus.transferring,
        localPath: '/tmp/test.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      );

      expect(transfer.progress, 0.5);
    });

    test('canPause returns correct values', () {
      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.transferring,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canPause,
        true,
      );

      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.completed,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canPause,
        false,
      );
    });

    test('canResume returns correct values', () {
      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.paused,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canResume,
        true,
      );

      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.failed,
          retryCount: 0,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canResume,
        true,
      );

      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.completed,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canResume,
        false,
      );
    });

    test('canRetry returns correct values', () {
      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.failed,
          retryCount: 0,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canRetry,
        true,
      );

      expect(
        Transfer(
          id: '1',
          fileId: 'f1',
          name: 'test',
          size: 100,
          direction: TransferDirection.upload,
          status: TransferStatus.failed,
          retryCount: 3,
          localPath: '/tmp',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        ).canRetry,
        false,
      );
    });

    test('copyWith updates fields correctly', () {
      final original = Transfer(
        id: 'test-id',
        fileId: 'file-123',
        name: 'test.txt',
        size: 1000,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/test.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      );

      final updated = original.copyWith(
        status: TransferStatus.transferring,
        bytesTransferred: 500,
      );

      expect(updated.status, TransferStatus.transferring);
      expect(updated.bytesTransferred, 500);
      expect(updated.id, original.id);
      expect(updated.name, original.name);
    });

    test('toJson and fromJson roundtrip', () {
      final original = Transfer(
        id: 'test-id',
        fileId: 'file-123',
        name: 'test.txt',
        size: 1000,
        bytesTransferred: 500,
        direction: TransferDirection.upload,
        status: TransferStatus.transferring,
        localPath: '/tmp/test.txt',
        createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
        updatedAt: DateTime.parse('2024-01-01T01:00:00Z'),
        transport: TransferTransportType.http,
      );

      final json = original.toJson();
      final restored = Transfer.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.fileId, original.fileId);
      expect(restored.name, original.name);
      expect(restored.size, original.size);
      expect(restored.bytesTransferred, original.bytesTransferred);
      expect(restored.direction, original.direction);
      expect(restored.status, original.status);
      expect(restored.localPath, original.localPath);
      expect(restored.transport, original.transport);
    });
  });

  group('TransferQueue', () {
    test('adds transfers and respects max concurrency', () {
      final queue = TransferQueue(maxConcurrency: 2);

      queue.add(Transfer(
        id: '1',
        fileId: 'f1',
        name: 'a.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/a.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      queue.add(Transfer(
        id: '2',
        fileId: 'f2',
        name: 'b.txt',
        size: 200,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/b.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      queue.add(Transfer(
        id: '3',
        fileId: 'f3',
        name: 'c.txt',
        size: 300,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/c.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      expect(queue.activeCount, 0);
      expect(queue.queuedCount, 3);

      final first = queue.next();
      expect(first?.id, '1');
      expect(queue.activeCount, 1);
      expect(queue.queuedCount, 2);

      final second = queue.next();
      expect(second?.id, '2');
      expect(queue.activeCount, 2);
      expect(queue.queuedCount, 1);

      final third = queue.next();
      expect(third, isNull);
    });

    test('respects priority ordering', () {
      final queue = TransferQueue(maxConcurrency: 1);

      queue.add(Transfer(
        id: 'low',
        fileId: 'f1',
        name: 'low.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/low.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
        priority: 0,
      ));

      queue.add(Transfer(
        id: 'high',
        fileId: 'f2',
        name: 'high.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/high.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
        priority: 10,
      ));

      final first = queue.next();
      expect(first?.id, 'high');
    });

    test('requeue puts transfer back in queue', () {
      final queue = TransferQueue(maxConcurrency: 1);

      queue.add(Transfer(
        id: '1',
        fileId: 'f1',
        name: 'a.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/a.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      final transfer = queue.next()!;
      queue.requeue(transfer.copyWith(status: TransferStatus.paused));

      expect(queue.activeCount, 0);
      expect(queue.queuedCount, 1);
      expect(queue.next()?.id, '1');
    });

    test('remove removes transfer from queue', () {
      final queue = TransferQueue(maxConcurrency: 2);

      queue.add(Transfer(
        id: '1',
        fileId: 'f1',
        name: 'a.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/a.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      queue.add(Transfer(
        id: '2',
        fileId: 'f2',
        name: 'b.txt',
        size: 200,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/b.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      queue.remove('1');
      expect(queue.queuedCount, 1);
      expect(queue.next()?.id, '2');
    });

    test('throws when queue is full', () {
      final queue = TransferQueue(maxQueued: 2);

      queue.add(Transfer(
        id: '1',
        fileId: 'f1',
        name: 'a.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/a.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      queue.add(Transfer(
        id: '2',
        fileId: 'f2',
        name: 'b.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/b.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      ));

      expect(() => queue.add(Transfer(
        id: '3',
        fileId: 'f3',
        name: 'c.txt',
        size: 100,
        direction: TransferDirection.upload,
        status: TransferStatus.queued,
        localPath: '/tmp/c.txt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transport: TransferTransportType.http,
      )), throwsStateError);
    });
  });

  group('TransferSpeedCalculator', () {
    test('returns 0 for no samples', () {
      final calc = TransferSpeedCalculator();
      expect(calc.getCurrentSpeed(DateTime.now()), 0.0);
    });

    test('calculates speed from samples', () {
      final calc = TransferSpeedCalculator();
      final now = DateTime.now();
      calc.addSample(1000, now);
      calc.addSample(2000, now.add(const Duration(seconds: 1)));

      final speed = calc.getCurrentSpeed(now.add(const Duration(seconds: 2)));
      expect(speed, closeTo(3000, 100)); // 3000 bytes over ~1 second
    });

    test('returns 0 for insufficient samples', () {
      final calc = TransferSpeedCalculator();
      final now = DateTime.now();
      calc.addSample(1000, now);

      expect(calc.getCurrentSpeed(now.add(const Duration(seconds: 1))), 0.0);
    });

    test('estimateRemaining calculates ETA', () {
      final calc = TransferSpeedCalculator();
      final now = DateTime.now();
      calc.addSample(1000, now);
      calc.addSample(2000, now.add(const Duration(seconds: 1)));

      final eta = calc.estimateRemaining(3000, 10000, now.add(const Duration(seconds: 2)));
      expect(eta, isNotNull);
      expect(eta!.inSeconds, greaterThan(0));
    });

    test('estimateRemaining returns null for zero speed', () {
      final calc = TransferSpeedCalculator();
      final now = DateTime.now();

      final eta = calc.estimateRemaining(0, 10000, now);
      expect(eta, isNull);
    });

    test('estimateRemaining returns zero for completed transfer', () {
      final calc = TransferSpeedCalculator();
      final now = DateTime.now();
      calc.addSample(1000, now);

      final eta = calc.estimateRemaining(10000, 10000, now);
      expect(eta, Duration.zero);
    });

    test('purges old samples', () {
      final calc = TransferSpeedCalculator();
      final baseTime = DateTime.fromMillisecondsSinceEpoch(1000000);
      calc.addSample(1000, baseTime.subtract(const Duration(seconds: 5)));
      calc.addSample(2000, baseTime);

      // The 5-second-old sample should be purged (window is 3 seconds)
      // After purging, only 1 sample remains, so speed is 0
      final speed = calc.getCurrentSpeed(baseTime);
      expect(speed, 0.0);
    });

    test('reset clears all samples', () {
      final calc = TransferSpeedCalculator();
      final now = DateTime.now();
      calc.addSample(1000, now);
      calc.addSample(2000, now);

      calc.reset();
      expect(calc.getCurrentSpeed(now), 0.0);
    });
  });

  group('IntegrityService', () {
    late File tempFile;
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('integrity_test_');
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    setUp(() async {
      tempFile = await File('${tempDir.path}/test.txt').create();
    });

    tearDown(() async {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });

    test('computeFileHash returns SHA-256 hash', () async {
      await tempFile.writeAsBytes(Uint8List.fromList('hello world'.codeUnits));
      final hash = await IntegrityService.computeFileHash(tempFile.path);

      expect(hash.length, 64); // SHA-256 hex is 64 chars
      expect(hash, 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9');
    });

    test('computeBytesHash returns SHA-256 hash', () async {
      final bytes = Uint8List.fromList('hello world'.codeUnits);
      final hash = await IntegrityService.computeBytesHash(bytes);

      expect(hash.length, 64);
      expect(hash, 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9');
    });

    test('verifyFileHash returns true for matching hash', () async {
      await tempFile.writeAsBytes(Uint8List.fromList('hello world'.codeUnits));
      final hash = await IntegrityService.computeFileHash(tempFile.path);
      final valid = await IntegrityService.verifyFileHash(
        filePath: tempFile.path,
        expectedHash: hash,
      );

      expect(valid, true);
    });

    test('verifyFileHash returns false for non-matching hash', () async {
      await tempFile.writeAsBytes(Uint8List.fromList('hello world'.codeUnits));
      final valid = await IntegrityService.verifyFileHash(
        filePath: tempFile.path,
        expectedHash: '0000000000000000000000000000000000000000000000000000000000000000',
      );

      expect(valid, false);
    });

    test('computeChunkedHash returns chunk hashes', () async {
      final data = Uint8List(128 * 1024); // 128 KB
      data.fillRange(0, data.length, 65); // 'A'
      await tempFile.writeAsBytes(data);

      final result = await IntegrityService.computeChunkedHash(
        filePath: tempFile.path,
        chunkSize: 32 * 1024, // 32 KB chunks = 4 chunks
      );

      expect(result.chunkHashes.length, 4);
      expect(result.chunkSize, 32 * 1024);
      expect(result.fullHash.length, 64);

      // All chunks are identical (all 'A's)
      for (final hash in result.chunkHashes) {
        expect(hash, result.chunkHashes.first);
      }
    });

    test('verifyChunkedHash detects mismatched chunks', () async {
      final data = Uint8List(128 * 1024);
      data.fillRange(0, 64 * 1024, 65); // 'A'
      data.fillRange(64 * 1024, data.length, 66); // 'B'
      await tempFile.writeAsBytes(data);

      final expected = await IntegrityService.computeChunkedHash(
        filePath: tempFile.path,
        chunkSize: 64 * 1024,
      );

      // Create a file with different content in second chunk
      final wrongData = Uint8List(128 * 1024);
      wrongData.fillRange(0, 64 * 1024, 65); // 'A'
      wrongData.fillRange(64 * 1024, data.length, 67); // 'C'
      await tempFile.writeAsBytes(wrongData);

      final result = await IntegrityService.verifyChunkedHash(
        filePath: tempFile.path,
        expected: expected,
      );

      expect(result.isValid, false);
      expect(result.fullHashMatch, false);
      expect(result.mismatchedChunks, contains(1));
    });
  });
}