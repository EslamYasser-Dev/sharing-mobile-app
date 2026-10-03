import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../format.dart';
import '../grpc/fileshare/v1/fileshare.pbgrpc.dart';
import '../models.dart';
import 'grpc_connection.dart';
import 'token_store.dart';

class DownloadResult {
  const DownloadResult({required this.file, required this.name});

  final File file;
  final String name;
}

class ApiClient {
  ApiClient({GrpcConnection? connection, TokenStore? tokens})
      : _conn = connection ?? GrpcConnection(),
        _tokens = tokens ?? TokenStore();

  final GrpcConnection _conn;
  final TokenStore _tokens;

  void Function()? onUnauthorized;

  static const Duration _unaryTimeout = Duration(seconds: 30);
  // gRPC message size: 256 KiB halves per-message framing overhead 4x over
  // 64 KiB while keeping each in-flight buffer small for slow links.
  static const int _uploadChunkSize = 256 * 1024;

  String buildUrl(String endpoint, [Map<String, Object?>? params]) {
    var uri = Uri.parse('$apiBaseUrl$endpoint');
    if (params != null && params.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          ...params.map((k, v) => MapEntry(k, v.toString())),
        },
      );
    }
    return uri.toString();
  }

  Future<void> _handle401() async {
    await _tokens.clear();
    onUnauthorized?.call();
  }

  Future<CallOptions> _options({
    bool authenticated = true,
    bool unary = true,
  }) async {
    final metadata = <String, String>{};
    if (authenticated) {
      final token = await _tokens.get();
      if (token != null && token.isNotEmpty) {
        metadata['authorization'] = 'Bearer $token';
      }
    }
    return CallOptions(
      metadata: metadata,
      timeout: unary ? _unaryTimeout : null,
    );
  }

  String _messageFrom(Object error) {
    if (error is GrpcError) {
      // The server predates this feature: say so instead of leaking
      // "unknown service fileshare.v1.X" transport text.
      if (error.code == StatusCode.unimplemented) {
        return 'This feature needs a newer server — update the backend';
      }
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'Request failed (${error.code})';
    }
    return error.toString();
  }

  Future<ApiResult<T>> _fromError<T>(Object error) async {
    if (error is GrpcError && error.code == StatusCode.unauthenticated) {
      await _handle401();
      return ApiResult<T>(error: 'Not authorized', unauthorized: true);
    }
    return ApiResult<T>(error: _messageFrom(error));
  }

  Future<ApiResult<T>> _guard<T>(
    Future<T> Function(CallOptions options) run, {
    bool authenticated = true,
    bool unary = true,
  }) async {
    try {
      final options = await _options(authenticated: authenticated, unary: unary);
      return ApiResult<T>(data: await run(options));
    } catch (error) {
      return _fromError<T>(error);
    }
  }

  Future<ApiResult<void>> _guardVoid(
    Future<Object?> Function(CallOptions options) run, {
    bool authenticated = true,
    bool unary = true,
  }) async {
    try {
      final options = await _options(authenticated: authenticated, unary: unary);
      await run(options);
      return const ApiResult<void>();
    } catch (error) {
      return _fromError<void>(error);
    }
  }

  Future<ApiResult<TokenResponse>> login(
    String username,
    String password,
  ) async {
    final result = await _guard(
      (options) async => (await _conn.auth).login(
        LoginRequest()
          ..username = username
          ..password = password,
        options: options,
      ),
      authenticated: false,
    );
    final response = result.data;
    if (response == null) {
      return ApiResult<TokenResponse>(
        error: result.error,
        unauthorized: result.unauthorized,
      );
    }
    if (response.accessToken.isNotEmpty) {
      await _tokens.set(response.accessToken);
    }
    return ApiResult<TokenResponse>(
      data: TokenResponse(
        accessToken: response.accessToken,
        tokenType: response.tokenType,
        expiresIn: response.expiresIn.toInt(),
      ),
    );
  }

  Future<ApiResult<void>> revoke() async {
    try {
      final options = await _options();
      await (await _conn.auth)
          .logout(LogoutRequest(), options: options)
          .timeout(_unaryTimeout);
    } catch (_) {}
    await _tokens.clear();
    return const ApiResult<void>();
  }

  Future<ApiResult<AuthUser>> me() async {
    final result = await _guard(
      (options) async => (await _conn.auth).me(MeRequest(), options: options),
    );
    final user = result.data;
    if (user == null) {
      return ApiResult<AuthUser>(
        error: result.error,
        unauthorized: result.unauthorized,
      );
    }
    return ApiResult<AuthUser>(data: _userFromProto(user));
  }

  Future<ApiResult<List<FileItem>>> listFiles([String path = '']) =>
      _guard((options) async {
        final response = await (await _conn.files).listFiles(
          ListFilesRequest()..path = path,
          options: options,
        );
        return response.files.map(_fileFromProto).toList();
      });

  Future<ApiResult<void>> createDirectory(String path) => _guardVoid(
        (options) async => (await _conn.files).createDirectory(
          CreateDirectoryRequest()..path = path,
          options: options,
        ),
      );

  Future<ApiResult<void>> deletePath(String path) => _guardVoid(
        (options) async => (await _conn.files).deletePath(
          DeletePathRequest()..path = path,
          options: options,
        ),
      );

  Future<ApiResult<ShareItem>> createShare(
    String path,
    int expiresInSeconds, {
    String password = '',
    int maxDownloads = 0,
  }) =>
      _guard((options) async {
        final share = await (await _conn.shares).createShare(
          CreateShareRequest()
            ..path = path
            ..expiresInSeconds = Int64(expiresInSeconds)
            ..password = password
            ..maxDownloads = maxDownloads,
          options: options,
        );
        return _shareFromProto(share);
      });

  Future<ApiResult<List<ShareItem>>> listShares() => _guard((options) async {
        final response = await (await _conn.shares).listShares(
          ListSharesRequest(),
          options: options,
        );
        return response.shares.map(_shareFromProto).toList();
      });

  Future<ApiResult<void>> revokeShare(String token) => _guardVoid(
        (options) async => (await _conn.shares).revokeShare(
          RevokeShareRequest()..token = token,
          options: options,
        ),
      );

  String shareUrl(String token) => buildUrl('/api/share/$token');

  Future<ApiResult<void>> uploadFile({
    required String fileName,
    required int size,
    required String dirPath,
    File? file,
    Uint8List? bytes,
    void Function(int loaded, int total)? onProgress,
  }) =>
      _guardVoid(
        (options) async => (await _conn.files).uploadFile(
          _uploadRequests(
            dirPath: dirPath,
            fileName: fileName,
            size: size,
            file: file,
            bytes: bytes,
            onProgress: onProgress,
          ),
          options: options,
        ),
        unary: false,
      );

  Stream<UploadRequest> _uploadRequests({
    required String dirPath,
    required String fileName,
    required int size,
    File? file,
    Uint8List? bytes,
    void Function(int loaded, int total)? onProgress,
  }) async* {
    yield UploadRequest()
      ..metadata = (UploadMetadata()
        ..path = dirPath
        ..filename = fileName);
    if (file == null && bytes == null) {
      throw StateError('No file data');
    }
    final source = file != null
        ? file.openRead()
        : Stream<List<int>>.value(bytes!);
    // BytesBuilder accumulation avoids the O(n²) re-copying of a growable
    // list + sublist drain; each byte is copied a constant number of times.
    final builder = BytesBuilder(copy: false);
    var sent = 0;
    await for (final piece in source) {
      builder.add(piece);
      while (builder.length >= _uploadChunkSize) {
        final all = builder.takeBytes();
        final head = Uint8List.fromList(all.sublist(0, _uploadChunkSize));
        builder.add(all.sublist(_uploadChunkSize));
        yield UploadRequest()..chunk = head;
        sent += head.length;
        onProgress?.call(sent, size);
      }
    }
    if (builder.length > 0) {
      final chunk = builder.takeBytes();
      yield UploadRequest()..chunk = chunk;
      sent += chunk.length;
    }
    onProgress?.call(sent, size);
  }

  Future<ApiResult<DownloadResult>> download(
    String path, {
    void Function(int received)? onProgress,
  }) async {
    try {
      final chunks = (await _conn.files).downloadFile(
        DownloadFileRequest()..path = path,
        options: await _options(unary: false),
      );
      return await _saveStream(chunks, baseName(path), onProgress);
    } catch (error) {
      return _fromError<DownloadResult>(error);
    }
  }

  /// Downloads another owner's file after the server re-checks the streaming
  /// gate (link/public + streaming allowed, or share-equivalent access).
  Future<ApiResult<DownloadResult>> downloadShared({
    required String owner,
    required String path,
    void Function(int received)? onProgress,
  }) async {
    try {
      final chunks = (await _conn.social).downloadSharedFile(
        DownloadSharedRequest()
          ..owner = owner
          ..path = path,
        options: await _options(unary: false),
      );
      return await _saveStream(chunks, baseName(path), onProgress);
    } catch (error) {
      return _fromError<DownloadResult>(error);
    }
  }

  Future<ApiResult<DownloadResult>> _saveStream(
    Stream<DownloadChunk> chunks,
    String suggested, [
    void Function(int received)? onProgress,
  ]) async {
    var savePath = '';
    var name = suggested;
    var received = 0;
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      savePath = '${dir.path}/$stamp-$suggested';
      var first = true;
      final sink = File(savePath).openWrite();
      try {
        await for (final chunk in chunks) {
          if (first) {
            first = false;
            if (chunk.filename.isNotEmpty) name = chunk.filename;
          }
          if (chunk.data.isNotEmpty) {
            sink.add(chunk.data);
            received += chunk.data.length;
            onProgress?.call(received);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      var file = File(savePath);
      if (name != suggested) {
        final target = File(
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}-$name',
        );
        file = await file.rename(target.path);
      }
      return ApiResult(data: DownloadResult(file: file, name: name));
    } catch (error) {
      if (savePath.isNotEmpty) {
        try {
          await File(savePath).delete();
        } catch (_) {}
      }
      return _fromError<DownloadResult>(error);
    }
  }

  AuthUser _userFromProto(User user) => AuthUser(
        username: user.username,
        isAdmin: user.isAdmin,
        role: user.role.isEmpty ? null : user.role,
        enabled: user.enabled,
        permissions: user.permissions.toList(),
        createdAt: user.createdAt.isEmpty ? null : user.createdAt,
        quotaBytes: user.quotaBytes.toInt(),
        size: user.size.toInt(),
        files: user.files.toInt(),
      );

  FileItem _fileFromProto(FileInfo info) => FileItem(
        name: info.name,
        path: info.path,
        size: info.size.toInt(),
        isDir: info.isDir,
        modified: info.hasModified()
            ? info.modified.toDateTime().toUtc().toIso8601String()
            : '',
      );

  ShareItem _shareFromProto(Share share) => ShareItem(
        token: share.token,
        path: share.path,
        name: share.name,
        owner: share.owner,
        createdAt: share.createdAt,
        expiresAt: share.expiresAt,
        passwordProtected: share.passwordProtected,
        maxDownloads: share.maxDownloads,
        downloads: share.downloads,
      );

  Future<ApiResult<bool>> follow(String username) => _guard((options) async {
        final response = await (await _conn.social).follow(
          FollowRequest()..username = username,
          options: options,
        );
        return response.following;
      });

  Future<ApiResult<bool>> unfollow(String username) => _guard((options) async {
        final response = await (await _conn.social).unfollow(
          UnfollowRequest()..username = username,
          options: options,
        );
        return response.following;
      });

  Future<ApiResult<bool>> isFollowing(String username) =>
      _guard((options) async {
        final response = await (await _conn.social).isFollowing(
          IsFollowingRequest()..username = username,
          options: options,
        );
        return response.following;
      });

  Future<ApiResult<List<String>>> listFollowers(String username) =>
      _guard((options) async {
        final response = await (await _conn.social).listFollowers(
          ListFollowersRequest()..username = username,
          options: options,
        );
        return response.usernames.toList();
      });

  Future<ApiResult<List<String>>> listFollowing(String username) =>
      _guard((options) async {
        final response = await (await _conn.social).listFollowing(
          ListFollowingRequest()..username = username,
          options: options,
        );
        return response.usernames.toList();
      });

  Future<ApiResult<VisibilitySetting>> setVisibility({
    required String path,
    required String level,
    required bool allowStream,
  }) =>
      _guard((options) async {
        final vis = await (await _conn.social).setVisibility(
          SetVisibilityRequest()
            ..path = path
            ..level = level
            ..allowStream = allowStream,
          options: options,
        );
        return _visibilityFromProto(vis);
      });

  Future<ApiResult<VisibilitySetting>> getVisibility({
    required String owner,
    required String path,
  }) =>
      _guard((options) async {
        final vis = await (await _conn.social).getVisibility(
          GetVisibilityRequest()
            ..owner = owner
            ..path = path,
          options: options,
        );
        return _visibilityFromProto(vis);
      });

  Future<ApiResult<FeedPage>> listFeed({String cursor = '', int limit = 20}) =>
      _guard((options) async {
        final response = await (await _conn.social).listFeed(
          ListFeedRequest()
            ..cursor = cursor
            ..limit = limit,
          options: options,
        );
        return FeedPage(
          events: response.events.map(_timelineEventFromProto).toList(),
          nextCursor: response.nextCursor,
        );
      });

  VisibilitySetting _visibilityFromProto(FileVisibility vis) =>
      VisibilitySetting(
        owner: vis.owner,
        path: vis.path,
        level: vis.level,
        allowStream: vis.allowStream,
        updatedAt: vis.updatedAt,
      );

  FeedEvent _timelineEventFromProto(TimelineEvent e) => FeedEvent(
        id: e.id,
        owner: e.owner,
        kind: e.kind,
        path: e.path,
        name: e.name,
        size: e.size.toInt(),
        visibility: e.visibility,
        createdAt: e.createdAt,
      );

  // Google OAuth methods (HTTP-based since gRPC doesn't have these endpoints yet)
  Future<ApiResult<GoogleTokenExchangeResponse>> exchangeGoogleToken(String idToken) async {
    final url = buildUrl('/api/auth/google/exchange');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult<GoogleTokenExchangeResponse>(
          data: GoogleTokenExchangeResponse.fromJson(data),
        );
      } else {
        final error = _parseError(response);
        return ApiResult<GoogleTokenExchangeResponse>(error: error);
      }
    } catch (e) {
      return _fromError<GoogleTokenExchangeResponse>(e);
    }
  }

  Future<ApiResult<GoogleTokenExchangeResponse>> linkGoogleAccount(String idToken) async {
    final options = await _options();
    final url = buildUrl('/api/auth/google/link');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          ...options.metadata,
        },
        body: jsonEncode({'id_token': idToken}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult<GoogleTokenExchangeResponse>(
          data: GoogleTokenExchangeResponse.fromJson(data),
        );
      } else {
        final error = _parseError(response);
        return ApiResult<GoogleTokenExchangeResponse>(error: error);
      }
    } catch (e) {
      return _fromError<GoogleTokenExchangeResponse>(e);
    }
  }

  Future<ApiResult<void>> unlinkGoogle() async {
    final options = await _options();
    final url = buildUrl('/api/auth/google/unlink');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          ...options.metadata,
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 204) {
        return const ApiResult<void>();
      } else {
        final error = _parseError(response);
        return ApiResult<void>(error: error);
      }
    } catch (e) {
      return _fromError<void>(e);
    }
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['error'] as String? ?? 'Request failed (${response.statusCode})';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}