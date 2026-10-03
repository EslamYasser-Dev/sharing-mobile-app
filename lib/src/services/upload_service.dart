import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config.dart';
import '../models/transfer.dart';
import 'token_store.dart';
import 'transfer_persistence.dart';

class HttpUploadService {
  HttpUploadService({
    String? baseUrl,
    TokenStore? tokenStore,
    HttpClient? httpClient,
  })  : _baseUrl = (baseUrl ?? apiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _tokenStore = tokenStore ?? TokenStore(),
        _http = httpClient ?? HttpClient();

  final String _baseUrl;
  final TokenStore _tokenStore;
  final HttpClient _http;

  static const int _defaultChunkSize = 4 * 1024 * 1024; // 4 MiB

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<String> _getToken() async {
    final token = await _tokenStore.get();
    if (token == null || token.isEmpty) {
      throw StateError('Not authenticated');
    }
    return token;
  }

  Future<void> _persistResumeMetadata(String id, Map<String, dynamic> metadata) async {
    if (_persistence != null) {
      await _persistence!.updateResumeMetadata(id, metadata);
    }
  }

  Future<void> _persistBytesTransferred(String id, int bytes) async {
    if (_persistence != null) {
      await _persistence!.updateBytesTransferred(id, bytes);
    }
  }

  Future<UploadSessionResponse> createSession({
    required String path,
    required String filename,
    required int size,
    required String fingerprint,
  }) async {
    final token = await _getToken();
    final request = await _http.postUrl(_uri('/api/uploads'));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(jsonEncode({
      'path': path,
      'filename': filename,
      'size': size,
      'fingerprint': fingerprint,
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Failed to create upload session: $body', uri: _uri('/api/uploads'));
    }

    return UploadSessionResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<UploadSessionResponse> getSession(String sessionId) async {
    final token = await _getToken();
    final request = await _http.getUrl(_uri('/api/uploads/$sessionId'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Failed to get session: $body', uri: _uri('/api/uploads/$sessionId'));
    }

    return UploadSessionResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<UploadSessionResponse> appendChunk({
    required String sessionId,
    required int offset,
    required Uint8List chunk,
    void Function(int sent, int total)? onProgress,
  }) async {
    final token = await _getToken();
    final request = await _http.patchUrl(_uri('/api/uploads/$sessionId'));
    request.headers
      ..contentType = ContentType('application', 'octet-stream')
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set('Upload-Offset', offset.toString());

    var sent = 0;
    request.add(chunk);
    onProgress?.call(sent + chunk.length, chunk.length);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode == HttpStatus.conflict) {
      final error = jsonDecode(body) as Map<String, dynamic>;
      throw OffsetMismatchException(error['expected'] as int);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Failed to append chunk: $body', uri: _uri('/api/uploads/$sessionId'));
    }

    return UploadSessionResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<UploadCompleteResponse> completeSession(String sessionId) async {
    final token = await _getToken();
    final request = await _http.postUrl(_uri('/api/uploads/$sessionId/complete'));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode == HttpStatus.conflict) {
      final error = jsonDecode(body) as Map<String, dynamic>;
      throw OffsetMismatchException(error['expected'] as int);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Failed to complete upload: $body', uri: _uri('/api/uploads/$sessionId/complete'));
    }

    return UploadCompleteResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<void> abortSession(String sessionId) async {
    final token = await _getToken();
    final request = await _http.deleteUrl(_uri('/api/uploads/$sessionId'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final response = await request.close();
    if (response.statusCode != HttpStatus.noContent && response.statusCode != HttpStatus.notFound) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException('Failed to abort upload: $body', uri: _uri('/api/uploads/$sessionId'));
    }
  }

  Future<List<PendingUploadSession>> listSessions() async {
    final token = await _getToken();
    final request = await _http.getUrl(_uri('/api/uploads'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Failed to list sessions: $body', uri: _uri('/api/uploads'));
    }

    final list = jsonDecode(body) as List;
    return list.map((e) => PendingUploadSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> uploadFile({
    required Transfer transfer,
    required File file,
    void Function(int bytesSent, int totalBytes)? onProgress,
    Future<void> Function()? awaitResume,
    bool Function()? shouldCancel,
  }) async {
    final fingerprint = '${transfer.destinationPath}|${transfer.name}|${transfer.size}|${await file.lastModified()}';

    var session = await createSession(
      path: transfer.destinationPath ?? '',
      filename: transfer.name,
      size: transfer.size,
      fingerprint: fingerprint,
    );

    var offset = session.offset;
    final chunkSize = session.chunkSize > 0 ? session.chunkSize : _defaultChunkSize;

    await _persistResumeMetadata(transfer.id, {
      'sessionId': session.id,
      'offset': offset,
    });

    while (offset < transfer.size) {
      if (shouldCancel?.call() ?? false) {
        await _persistResumeMetadata(transfer.id, {
          'sessionId': session.id,
          'offset': offset,
        });
        throw UploadCancelledException();
      }

      if (awaitResume != null) {
        await awaitResume();
        if (shouldCancel?.call() ?? false) throw UploadCancelledException();

        session = await getSession(session.id);
        offset = session.offset;
      }

      final end = offset + chunkSize > transfer.size ? transfer.size : offset + chunkSize;
      final chunk = await _readChunk(file, offset, end - offset);

      try {
        session = await appendChunk(
          sessionId: session.id,
          offset: offset,
          chunk: chunk,
          onProgress: (sent, total) => onProgress?.call(offset + sent, transfer.size),
        );
        offset = session.offset;
        await _persistBytesTransferred(transfer.id, offset);
        await _persistResumeMetadata(transfer.id, {
          'sessionId': session.id,
          'offset': offset,
        });
      } on OffsetMismatchException catch (e) {
        offset = e.expectedOffset;
        session = await getSession(session.id);
        continue;
      }
    }

    final result = await completeSession(session.id);
    if (result.path != transfer.name) {
      throw StateError('Upload completed but path mismatch');
    }

    await _persistResumeMetadata(transfer.id, {
      'sessionId': null,
      'offset': transfer.size,
    });
  }

  Future<Uint8List> _readChunk(File file, int offset, int length) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }

  TransferPersistence? _persistence;
  void setPersistence(TransferPersistence persistence) {
    _persistence = persistence;
  }

  void dispose() {
    _http.close(force: true);
  }
}

class UploadSessionResponse {
  const UploadSessionResponse({
    required this.id,
    required this.offset,
    required this.size,
    required this.chunkSize,
    required this.expiresAt,
  });

  final String id;
  final int offset;
  final int size;
  final int chunkSize;
  final DateTime expiresAt;

  factory UploadSessionResponse.fromJson(Map<String, dynamic> json) => UploadSessionResponse(
    id: json['id'] as String,
    offset: json['offset'] as int,
    size: json['size'] as int,
    chunkSize: json['chunkSize'] as int,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

class PendingUploadSession {
  const PendingUploadSession({
    required this.id,
    this.fingerprint,
    this.destination,
    required this.filename,
    required this.size,
    required this.offset,
    this.updatedAt,
    required this.expiresAt,
  });

  final String id;
  final String? fingerprint;
  final String? destination;
  final String filename;
  final int size;
  final int offset;
  final DateTime? updatedAt;
  final DateTime expiresAt;

  factory PendingUploadSession.fromJson(Map<String, dynamic> json) => PendingUploadSession(
    id: json['id'] as String,
    fingerprint: json['fingerprint'] as String?,
    destination: json['destination'] as String?,
    filename: json['filename'] as String,
    size: json['size'] as int,
    offset: json['offset'] as int,
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

class UploadCompleteResponse {
  const UploadCompleteResponse({
    required this.path,
    required this.size,
  });

  final String path;
  final int size;

  factory UploadCompleteResponse.fromJson(Map<String, dynamic> json) => UploadCompleteResponse(
    path: json['path'] as String,
    size: json['size'] as int,
  );
}

class OffsetMismatchException implements Exception {
  const OffsetMismatchException(this.expectedOffset);
  final int expectedOffset;
}

class UploadCancelledException implements Exception {}