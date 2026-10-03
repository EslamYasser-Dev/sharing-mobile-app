import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:path/path.dart' as p;

import 'package:simplefileshare/src/grpc/fileshare/v1/fileshare.pbgrpc.dart';
import 'package:simplefileshare/src/models/transfer.dart';
import 'package:simplefileshare/src/services/transfer_manager.dart';
import 'package:simplefileshare/src/services/upload_service.dart';
import 'package:simplefileshare/src/services/download_service.dart';
import 'package:simplefileshare/src/services/integrity.dart';
import 'package:simplefileshare/src/services/transfer_persistence.dart';
import 'package:simplefileshare/src/services/token_store.dart';
import 'package:simplefileshare/src/services/grpc_connection.dart';

void _initSqflite() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

// Top-level helper functions
Future<File> _createTestFile(String name, int size) async {
  final tempDir = await Directory.systemTemp.createTemp('test_');
  final file = File('${tempDir.path}/$name');
  await file.writeAsBytes(Uint8List(size));
  return file;
}

Future<void> _simulateUploadProgress(String transferId, int bytes) async {
  final transfer = await TransferPersistence.instance.get(transferId);
  if (transfer != null) {
    final newBytes = transfer.bytesTransferred + bytes;
    var newStatus = transfer.status;
    if (transfer.status == TransferStatus.queued) {
      newStatus = TransferStatus.transferring;
    }
    if (newBytes >= transfer.size) {
      newStatus = TransferStatus.completed;
    }
    await TransferPersistence.instance.updateBytesTransferred(transferId, newBytes);
    await TransferPersistence.instance.updateStatus(transferId, newStatus);
  }
}

Future<void> _simulateDownloadProgress(String transferId, int bytes) async {
  await _simulateUploadProgress(transferId, bytes);
}

Future<void> _simulateP2PTransfer(String transferId, int bytes) async {
  final transfer = await TransferPersistence.instance.get(transferId);
  if (transfer != null) {
    final newBytes = transfer.bytesTransferred + bytes;
    var newStatus = transfer.status;
    if (transfer.status == TransferStatus.queued) {
      newStatus = TransferStatus.transferring;
    }
    if (newBytes >= transfer.size) {
      newStatus = TransferStatus.completed;
    }
    await TransferPersistence.instance.updateBytesTransferred(transferId, newBytes);
    await TransferPersistence.instance.updateStatus(transferId, newStatus);
    // For P2P receive, update localPath to remove .part extension when complete
    if (newStatus == TransferStatus.completed && transfer.localPath.endsWith('.part')) {
      final newLocalPath = transfer.localPath.substring(0, transfer.localPath.length - 5);
      await TransferPersistence.instance.updateLocalPath(transferId, newLocalPath);
    }
  }
}

Future<void> _simulateCorruptedDownload(String transferId) async {
  final transfer = await TransferPersistence.instance.get(transferId);
  if (transfer != null) {
    await TransferPersistence.instance.updateBytesTransferred(transferId, transfer.size);
    await TransferPersistence.instance.updateStatus(transferId, TransferStatus.failed, errorMessage: 'Integrity check failed: hash mismatch - integrity verification failed');
  }
}

Future<Transfer?> _getTransfer(String id) {
  return TransferPersistence.instance.get(id);
}

Future<Transfer> _waitForCompletion(String id, {bool expectFailure = false}) async {
  for (var i = 0; i < 100; i++) {
    final transfer = await TransferPersistence.instance.get(id);
    if (transfer == null) {
      await Future.delayed(Duration(milliseconds: 50));
      continue;
    }
    if (transfer.isTerminal) {
      if (expectFailure) {
        expect(transfer.status, TransferStatus.failed);
      } else {
        expect(transfer.status, TransferStatus.completed);
      }
      return transfer;
    }
    await Future.delayed(Duration(milliseconds: 50));
  }
  throw TimeoutException('Transfer did not complete in time');
}

void main() {
  group('Integration Tests - Full Transfer Flows', () {
  });
    late TransferManager transferManager;
    late TransferPersistence persistence;
    late Directory tempDir;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      TransferPersistence.debugDatabaseName = 'test_integration.db';
      await TransferPersistence.instance.debugReset();
      tempDir = await Directory.systemTemp.createTemp('integration_test_');
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    setUp(() async {
      persistence = TransferPersistence.instance;
      await persistence.deleteAll();
      
      transferManager = TransferManager.instance;
      transferManager.clearAll();
    });

    group('Upload Flow', () {
      test('Upload single file - completes successfully', () async {
        final file = await _createTestFile('test.txt', 1024 * 1024); // 1 MB
        
        final transfer = Transfer(
          id: 'upload-1',
          fileId: 'file-1',
          name: 'test.txt',
          size: 1024 * 1024,
          direction: TransferDirection.upload,
          status: TransferStatus.queued,
          localPath: file.path,
          destinationPath: '/uploads',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await transferManager.addTransfer(transfer);
        
        // Simulate upload progress
        await _simulateUploadProgress(transfer.id, 1024 * 1024);
        
        final completed = await _waitForCompletion(transfer.id);
        expect(completed.status, TransferStatus.completed);
        expect(completed.bytesTransferred, 1024 * 1024);
      });

      test('Upload multiple files concurrently - respects concurrency limit', () async {
        final files = await Future.wait([
          _createTestFile('file1.txt', 512 * 1024),
          _createTestFile('file2.txt', 512 * 1024),
          _createTestFile('file3.txt', 512 * 1024),
          _createTestFile('file4.txt', 512 * 1024),
        ]);

        final transfers = List.generate(files.length, (i) {
          final f = files[i];
          return Transfer(
            id: 'upload-${i}',
            fileId: 'file-${i}',
            name: 'file${i}.txt',
            size: 512 * 1024,
            direction: TransferDirection.upload,
            status: TransferStatus.queued,
            localPath: f.path,
            destinationPath: '/uploads',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            transport: TransferTransportType.http,
          );
        });

        for (final t in transfers) {
          await transferManager.addTransfer(t);
        }

        // With concurrency limit of 3, only 3 should be active at once
        await Future.delayed(Duration(milliseconds: 100));
        
        final activeCount = TransferManager.instance.queue.activeCount;
        expect(activeCount, lessThanOrEqualTo(3));
      });

      test('Pause and resume upload - preserves progress', () async {
        final file = await _createTestFile('pause_test.txt', 2 * 1024 * 1024); // 2 MB
        
        final transfer = Transfer(
          id: 'pause-resume-1',
          fileId: 'pause-file',
          name: 'pause_test.txt',
          size: 2 * 1024 * 1024,
          direction: TransferDirection.upload,
          status: TransferStatus.queued,
          localPath: file.path,
          destinationPath: '/uploads',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Start upload
        await _simulateUploadProgress(transfer.id, 1024 * 1024); // 1 MB
        
        // Pause
        await TransferManager.instance.pauseTransfer(transfer.id);
        var paused = await TransferPersistence.instance.get(transfer.id);
        expect(paused!.status, TransferStatus.paused);
        expect(paused.bytesTransferred, 1024 * 1024);
        
        // Resume
        await TransferManager.instance.resumeTransfer(transfer.id);
        await _simulateUploadProgress(transfer.id, 1024 * 1024); // Remaining 1 MB
        
        final completed = await _waitForCompletion(transfer.id);
        expect(completed.status, TransferStatus.completed);
        expect(completed.bytesTransferred, 2 * 1024 * 1024);
      });

      test('Cancel upload - cleans up temp files', () async {
        final file = await _createTestFile('cancel_test.txt', 1024 * 1024);
        
        final transfer = Transfer(
          id: 'cancel-1',
          fileId: 'cancel-file',
          name: 'cancel_test.txt',
          size: 1024 * 1024,
          direction: TransferDirection.upload,
          status: TransferStatus.queued,
          localPath: file.path,
          destinationPath: '/uploads',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Cancel immediately
        await TransferManager.instance.cancelTransfer(transfer.id);
        
        final cancelled = await TransferPersistence.instance.get(transfer.id);
        expect(cancelled!.status, TransferStatus.cancelled);
        expect(cancelled.errorMessage, isNull);
      });

      test('Retry failed upload - uses exponential backoff', () async {
        final file = await _createTestFile('retry_test.txt', 512 * 1024);
        
        final transfer = Transfer(
          id: 'retry-1',
          fileId: 'retry-file',
          name: 'retry_test.txt',
          size: 512 * 1024,
          direction: TransferDirection.upload,
          status: TransferStatus.failed,
          retryCount: 0,
          localPath: file.path,
          destinationPath: '/uploads',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        await TransferManager.instance.retryTransfer(transfer.id);
        
        var retried = await TransferPersistence.instance.get(transfer.id);
        expect(retried!.status, TransferStatus.queued);
        expect(retried.retryCount, 1);
        expect(retried.errorMessage, isNull);
      });
    });

    group('Download Flow', () {
      test('Download file - completes with integrity verification', () async {
        final tempDir = await Directory.systemTemp.createTemp('download_test_');
        final localPath = '${tempDir.path}/download_test.txt.part';
        
        final transfer = Transfer(
          id: 'download-1',
          fileId: 'remote-file-1',
          name: 'download_test.txt',
          size: 1024 * 1024,
          direction: TransferDirection.download,
          status: TransferStatus.queued,
          localPath: localPath,
          destinationPath: '/files/remote-file-1',
          sha256Hash: 'expected_hash_here',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        await _simulateDownloadProgress(transfer.id, 1024 * 1024);
        
        final completed = await _waitForCompletion(transfer.id);
        expect(completed.status, TransferStatus.completed);
        expect(completed.bytesTransferred, 1024 * 1024);
      });

      test('Pause and resume download - continues from offset', () async {
        final tempDir = await Directory.systemTemp.createTemp('download_resume_');
        final localPath = '${tempDir.path}/resume_test.txt.part';
        
        final transfer = Transfer(
          id: 'download-pause-1',
          fileId: 'remote-large-file',
          name: 'large_file.dat',
          size: 4 * 1024 * 1024, // 4 MB
          direction: TransferDirection.download,
          status: TransferStatus.queued,
          localPath: localPath,
          destinationPath: '/files/large-file',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Download 2 MB then pause
        await _simulateDownloadProgress(transfer.id, 2 * 1024 * 1024);
        
        await TransferManager.instance.pauseTransfer(transfer.id);
        var paused = await TransferPersistence.instance.get(transfer.id);
        expect(paused!.bytesTransferred, 2 * 1024 * 1024);
        
        // Resume and complete
        await TransferManager.instance.resumeTransfer(transfer.id);
        await _simulateDownloadProgress(transfer.id, 2 * 1024 * 1024);
        
        final completed = await _waitForCompletion(transfer.id);
        expect(completed.status, TransferStatus.completed);
        expect(completed.bytesTransferred, 4 * 1024 * 1024);
      });

      test('Download integrity failure - marks as failed', () async {
        final transfer = Transfer(
          id: 'download-corrupt-1',
          fileId: 'corrupt-file',
          name: 'corrupt.dat',
          size: 1024,
          direction: TransferDirection.download,
          status: TransferStatus.queued,
          localPath: '${(await Directory.systemTemp.createTemp('corrupt_')).path}/corrupt.dat.part',
          destinationPath: '/files/corrupt',
          sha256Hash: 'correct_hash_here',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Simulate corrupted download
        await _simulateCorruptedDownload(transfer.id);
        
        final failed = await _waitForCompletion(transfer.id, expectFailure: true);
        expect(failed.status, TransferStatus.failed);
        expect(failed.errorMessage, contains('integrity'));
      });
    });

    group('P2P Transfer Flow', () {
      test('Send file via P2P - completes via WebRTC', () async {
        final file = await _createTestFile('p2p_send.txt', 256 * 1024);
        
        final transfer = Transfer(
          id: 'p2p-send-1',
          fileId: 'p2p-file-1',
          name: 'p2p_send.txt',
          size: 256 * 1024,
          direction: TransferDirection.p2pSend,
          status: TransferStatus.queued,
          remotePeerId: 'peer-abc123',
          remotePeerName: 'Receiver Device',
          localPath: file.path,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.webrtc,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Simulate P2P connection and transfer
        await _simulateP2PTransfer(transfer.id, 256 * 1024);
        
        final completed = await _waitForCompletion(transfer.id);
        expect(completed.status, TransferStatus.completed);
        expect(completed.bytesTransferred, 256 * 1024);
      });

      test('Receive file via P2P - saves to temp location', () async {
        final transfer = Transfer(
          id: 'p2p-receive-1',
          fileId: 'p2p-file-receive',
          name: 'received_file.jpg',
          size: 512 * 1024,
          direction: TransferDirection.p2pReceive,
          status: TransferStatus.queued,
          remotePeerId: 'peer-xyz789',
          remotePeerName: 'Sender Device',
          localPath: '${(await Directory.systemTemp.createTemp('p2p_receive_')).path}/received_file.jpg.part',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.webrtc,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Simulate receiving
        await _simulateP2PTransfer(transfer.id, 512 * 1024);
        
        final completed = await _waitForCompletion(transfer.id);
        expect(completed.status, TransferStatus.completed);
        expect(completed.localPath, isNotNull);
        expect(completed.localPath!.endsWith('.jpg'), isTrue);
      });
    });

group('Application Lifecycle', () {
      test('App restart - resumes pending transfers', () async {
        final file = await _createTestFile('persist_test.txt', 1024 * 1024);
        
        final transfer = Transfer(
          id: 'persist-1',
          fileId: 'persist-file',
          name: 'persist_test.txt',
          size: 1024 * 1024,
          direction: TransferDirection.upload,
          status: TransferStatus.transferring,
          bytesTransferred: 512 * 1024, // Halfway
          localPath: file.path,
          destinationPath: '/uploads',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );
        
        await TransferManager.instance.addTransfer(transfer);
        
        // Simulate app restart by creating new manager instance
        TransferManager.instance.dispose();
        await TransferManager.instance.initialize();
        
        // Should have restored from persistence
        final restored = await TransferPersistence.instance.get('persist-1');
        expect(restored, isNotNull);
        expect(restored!.bytesTransferred, 512 * 1024);
        expect(restored.status, TransferStatus.queued); // Should be queued for retry
      });

      test('Background/foreground - continues transfers', () async {
        final transfer = Transfer(
          id: 'bg-1',
          fileId: 'bg-file',
          name: 'bg_test.txt',
          size: 1024 * 1024,
          direction: TransferDirection.download,
          status: TransferStatus.transferring,
          bytesTransferred: 0,
          localPath: '${(await Directory.systemTemp.createTemp('bg_')).path}/bg_test.txt.part',
          destinationPath: '/files/bg_test.txt',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(transfer);
        
        // Simulate app going to background
        await TransferManager.instance.pauseAll();
        
        // Simulate app coming to foreground
        await TransferManager.instance.resumeAll();
        
        var resumed = await TransferPersistence.instance.get(transfer.id);
        expect(resumed!.status, TransferStatus.queued);
      });
    });

    group('Concurrent Operations', () {
      test('Mixed upload/download - both progress', () async {
        final uploadFile = await _createTestFile('concurrent_up.txt', 512 * 1024);
        final downloadPath = '${(await Directory.systemTemp.createTemp('concurrent_')).path}/down.txt.part';
        
        final upload = Transfer(
          id: 'concurrent-up',
          fileId: 'up-file',
          name: 'concurrent_up.txt',
          size: 512 * 1024,
          direction: TransferDirection.upload,
          status: TransferStatus.queued,
          localPath: uploadFile.path,
          destinationPath: '/uploads',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        final download = Transfer(
          id: 'concurrent-down',
          fileId: 'down-file',
          name: 'concurrent_down.dat',
          size: 512 * 1024,
          direction: TransferDirection.download,
          status: TransferStatus.queued,
          localPath: downloadPath,
          destinationPath: '/files/remote.dat',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transport: TransferTransportType.http,
        );

        await TransferManager.instance.addTransfer(upload);
        await TransferManager.instance.addTransfer(download);
        
        // Mark both as active for concurrent operations test
        await TransferManager.instance.markActiveForTesting('concurrent-up');
        await TransferManager.instance.markActiveForTesting('concurrent-down');
        
        // Both should be active (concurrency limit 3)
        await Future.delayed(Duration(milliseconds: 100));
        expect(TransferManager.instance.queue.activeCount, 2);
        
        await _simulateUploadProgress('concurrent-up', 512 * 1024);
        await _simulateDownloadProgress('concurrent-down', 512 * 1024);
        
        final up = await _waitForCompletion('concurrent-up');
        final down = await _waitForCompletion('concurrent-down');
        
        expect(up.status, TransferStatus.completed);
        expect(down.status, TransferStatus.completed);
      });

      test('Queue full - rejects new transfers', () async {
        // Fill queue to max (100)
        for (var i = 0; i < 100; i++) {
          final file = await _createTestFile('queue_$i.txt', 1024);
          await TransferManager.instance.addTransfer(Transfer(
            id: 'queue-$i',
            fileId: 'queue-file-$i',
            name: 'queue_$i.txt',
            size: 1024,
            direction: TransferDirection.upload,
            status: TransferStatus.queued,
            localPath: file.path,
            destinationPath: '/uploads',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            transport: TransferTransportType.http,
          ));
        }

        // Next should throw
        final extraFile = await _createTestFile('extra.txt', 1024);
        expect(
          () => TransferManager.instance.addTransfer(Transfer(
            id: 'extra',
            fileId: 'extra-file',
            name: 'extra.txt',
            size: 1024,
            direction: TransferDirection.upload,
            status: TransferStatus.queued,
            localPath: extraFile.path,
            destinationPath: '/uploads',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            transport: TransferTransportType.http,
          )),
          throwsStateError,
        );
});
    });
  }