import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config.dart';
import '../models/transfer.dart';
import 'token_store.dart';
import 'integrity.dart';
import 'transfer_persistence.dart';

class HttpDownloadService {
  HttpDownloadService({
    String? baseUrl,
    TokenStore? tokenStore,
    HttpClient? httpClient,
  })  : _baseUrl = (baseUrl ?? apiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _tokenStore = tokenStore ?? TokenStore(),
        _http = httpClient ?? HttpClient();

  final String _baseUrl;
  final TokenStore _tokenStore;
  final HttpClient _http;

  // HTTP range size: 256 KiB quarters request count over 64 KiB while each
  // staged write stays small for slow links and pause granularity.
  static const int _defaultChunkSize = 256 * 1024;

  Uri _uri(String path, [Map<String, String>? query]) {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    return uri;
  }

  Future<String> _getToken() async {
    final token = await _tokenStore.get();
    if (token == null || token.isEmpty) {
      throw StateError('Not authenticated');
    }
    return token;
  }

  Future<void> _persistBytesTransferred(String id, int bytes) async {
    if (_persistence != null) {
      await _persistence!.updateBytesTransferred(id, bytes);
    }
  }

  Future<void> _persistResumeMetadata(String id, Map<String, dynamic> metadata) async {
    if (_persistence != null) {
      await _persistence!.updateResumeMetadata(id, metadata);
    }
  }

  Future<DownloadInfo> getFileInfo(String path) async {
    final token = await _getToken();
    final request = await _http.getUrl(_uri('/api/files/info', {'path': path}));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Failed to get file info: $body', uri: _uri('/api/files/info'));
    }

    return DownloadInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<DownloadResult> downloadFile({
    required Transfer transfer,
    required String remotePath,
    required String localPath,
    void Function(int bytesReceived, int totalBytes)? onProgress,
    Future<bool> Function()? awaitResume,
    bool Function()? shouldCancel,
  }) async {
    final info = await getFileInfo(remotePath);
    if (info.size != transfer.size) {
      throw StateError('File size mismatch: expected ${transfer.size}, got ${info.size}');
    }

    final tempPath = '$localPath.part';
    final tempFile = File(tempPath);
    var offset = 0;

    if (await tempFile.exists()) {
      offset = await tempFile.length();
      if (offset > transfer.size) {
        await tempFile.delete();
        offset = 0;
      }
    }

    await _persistBytesTransferred(transfer.id, offset);
    await _persistResumeMetadata(transfer.id, {
      'offset': offset,
      'tempPath': tempPath,
    });

    while (offset < transfer.size) {
      if (shouldCancel?.call() ?? false) {
        await _persistBytesTransferred(transfer.id, offset);
        throw DownloadCancelledException();
      }

      if (awaitResume != null) {
        await awaitResume();
        if (shouldCancel?.call() ?? false) throw DownloadCancelledException();
      }

      final end = offset + _defaultChunkSize > transfer.size ? transfer.size : offset + _defaultChunkSize;
      final range = await _downloadRange(remotePath, offset, end - 1);
      var chunk = range.data;
      if (!range.isPartial && offset > 0) {
        // Server ignored Range: restart from zero rather than corrupting
        // the staged file by appending a full copy after existing bytes.
        await tempFile.delete();
        offset = 0;
        await _persistBytesTransferred(transfer.id, offset);
        await _persistResumeMetadata(transfer.id, {'offset': offset});
        continue;
      }
      if (!range.isPartial && chunk.length != transfer.size) {
        throw StateError('Download size mismatch: expected ${transfer.size}, got ${chunk.length}');
      }

      final sink = tempFile.openWrite(mode: FileMode.append);
      try {
        sink.add(chunk);
      } finally {
        await sink.close();
      }

      offset += chunk.length;
      await _persistBytesTransferred(transfer.id, offset);
      await _persistResumeMetadata(transfer.id, {'offset': offset});
      onProgress?.call(offset, transfer.size);
    }

    final expectedHash = transfer.sha256Hash;
    if (expectedHash != null && expectedHash.isNotEmpty) {
      if (!await IntegrityService.verifyFileHash(
        filePath: tempPath,
        expectedHash: expectedHash,
      )) {
        await tempFile.delete();
        throw StateError('File integrity check failed: SHA-256 mismatch');
      }
    } else {
      // No server-provided hash: fall back to size verification only.
      final stagedSize = await tempFile.length();
      if (stagedSize != transfer.size) {
        await tempFile.delete();
        throw StateError('File integrity check failed: size mismatch');
      }
    }

    if (await tempFile.exists()) {
      final targetFile = File(localPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(localPath);
    }

    return DownloadResult(file: File(localPath), name: info.name);
  }

  Future<({Uint8List data, bool isPartial})> _downloadRange(String path, int start, int end) async {
    final token = await _getToken();
    final request = await _http.getUrl(_uri('/api/files/download', {'path': path}));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.rangeHeader, 'bytes=$start-$end');

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException('Failed to download range: $body', uri: _uri('/api/files/download'));
    }
    final isPartial = response.statusCode == HttpStatus.partialContent;

    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final match = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange);
      if (match != null) {
        final receivedStart = int.parse(match.group(1)!);
        if (receivedStart != start) {
          throw StateError('Range mismatch: requested $start, got $receivedStart');
        }
      }
    }

    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }

    return (data: Uint8List.fromList(chunks), isPartial: isPartial);
  }

  TransferPersistence? _persistence;
  void setPersistence(TransferPersistence persistence) {
    _persistence = persistence;
  }

  void dispose() {
    _http.close(force: true);
  }
}

class DownloadInfo {
  const DownloadInfo({
    required this.name,
    required this.path,
    required this.size,
    this.contentType,
  });

  final String name;
  final String path;
  final int size;
  final String? contentType;

  factory DownloadInfo.fromJson(Map<String, dynamic> json) => DownloadInfo(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    contentType: json['contentType'] as String?,
  );
}

class DownloadResult {
  const DownloadResult({required this.file, required this.name});

  final File file;
  final String name;
}

class DownloadCancelledException implements Exception {}