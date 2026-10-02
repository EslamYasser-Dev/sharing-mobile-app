import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// One complete `text/event-stream` frame: a named event and its data.
class SseFrame {
  const SseFrame({required this.event, required this.data});

  final String event;
  final String data;
}

/// Incremental Server-Sent Events parser.
///
/// Feed it decoded text in arbitrary chunk sizes; it hands back whole frames
/// as they complete, so a chunk boundary falling inside a JSON payload is
/// harmless. Comments (`: connected`, `: ping`) and unknown fields are
/// dropped, which keeps the backend's heartbeat out of the app. The `data`
/// lines of one frame are joined with `\n`, per the SSE spec.
class SseParser {
  String _buffer = '';
  String _event = '';
  final List<String> _data = <String>[];

  /// Consumes [chunk] and returns every frame completed by it.
  List<SseFrame> feed(String chunk) {
    _buffer += chunk;
    final frames = <SseFrame>[];
    while (true) {
      final newline = _buffer.indexOf('\n');
      if (newline < 0) break;
      var line = _buffer.substring(0, newline);
      _buffer = _buffer.substring(newline + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      final frame = _accept(line);
      if (frame != null) frames.add(frame);
    }
    return frames;
  }

  SseFrame? _accept(String line) {
    // A blank line dispatches whatever has accumulated.
    if (line.isEmpty) {
      final event = _event.isEmpty ? 'message' : _event;
      final data = _data.join('\n');
      _event = '';
      _data.clear();
      if (data.isEmpty) return null;
      return SseFrame(event: event, data: data);
    }
    // `: comment` — the backend's keep-alive lines.
    if (line.startsWith(':')) return null;

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    // The spec allows exactly one space of padding after the colon.
    if (value.startsWith(' ')) value = value.substring(1);

    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      _data.add(value);
    }
    // `id:` and `retry:` have no meaning for this client.
    return null;
  }
}

/// Decodes one SSE frame's payload, or null when there is nothing usable —
/// malformed JSON, a non-object body, or a signal kind this client does not
/// know. Returning null rather than throwing keeps a stray frame from
/// tearing down the whole stream.
P2PFrame? p2pFrameFromSse(SseFrame frame) {
  if (frame.data.isEmpty) return null;
  try {
    final decoded = jsonDecode(frame.data);
    if (decoded is! Map<String, dynamic>) return null;
    return p2pFrameFromJson(decoded);
  } on FormatException {
    return null;
  }
}

class P2PSignalingException implements Exception {
  const P2PSignalingException(this.message);

  final String message;

  @override
  String toString() => 'P2PSignalingException: $message';
}

/// HTTP client for the signaling endpoints.
///
/// The server relays presence and SDP/ICE frames only; file bytes travel
/// over the WebRTC data channel and never pass through here. Peer identity
/// comes from the stream itself — the server assigns a peer id on `hello` —
/// and every signal must echo it back in `X-Peer-Id`.
class P2PSignaling {
  P2PSignaling({
    required this.baseUrl,
    required this.readToken,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  final String baseUrl;
  final Future<String?> Function() readToken;
  final HttpClient _http;

  Uri _uri(String path) {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<String> _bearerToken() async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      throw const P2PSignalingException('not signed in');
    }
    return token;
  }

  /// Opens the SSE stream. Ends when the server closes it or an error stops
  /// it; reconnect backoff is the caller's responsibility.
  ///
  /// Cancelling the returned stream aborts the in-flight response, so a
  /// disposed session does not leave a socket open.
  Stream<P2PFrame> connect() async* {
    HttpClientRequest? request;
    HttpClientResponse? response;
    try {
      final token = await _bearerToken();
      request = await _http.getUrl(_uri('/api/p2p/stream'));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw P2PSignalingException('stream failed (${response.statusCode})');
      }

      final parser = SseParser();
      // utf8.decoder is chunk-boundary safe, so a multi-byte character
      // split across packets cannot corrupt a frame.
      await for (final text in response.transform(utf8.decoder)) {
        for (final frame in parser.feed(text)) {
          final decoded = p2pFrameFromSse(frame);
          if (decoded != null) yield decoded;
        }
      }
    } finally {
      // Released on cancel so a disposed session leaves no socket open.
      // Both are no-ops once the exchange has finished normally.
      try {
        // abort() releases the socket even while the response body is
        // still streaming.
        request?.abort();
      } catch (_) {
        // Already finished — nothing to release.
      }
    }
  }

  /// Relays one offer/answer/candidate/bye to [to].
  Future<void> sendSignal({
    required String from,
    required String to,
    required P2PSignalKind kind,
    Object? payload,
  }) async {
    final token = await _bearerToken();
    final request = await _http.postUrl(_uri('/api/p2p/signal'));
    request.headers
      ..contentType = ContentType.json
      ..set('X-Peer-Id', from)
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(
      jsonEncode(<String, dynamic>{
        'to': to,
        'kind': kind.name,
        'payload': ?payload,
      }),
    );

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.accepted) {
      throw P2PSignalingException(_errorOf(body, response.statusCode));
    }
  }

  /// Lists the peers currently connected, excluding self.
  Future<List<P2PPeer>> peers() async {
    final token = await _bearerToken();
    final request = await _http.getUrl(_uri('/api/p2p/peers'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw P2PSignalingException(_errorOf(body, response.statusCode));
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const <P2PPeer>[];
      return <P2PPeer>[
        for (final peer in (decoded['peers'] as List<dynamic>? ?? const []))
          if (peer is Map<String, dynamic>) P2PPeer.fromJson(peer),
      ];
    } on FormatException {
      return const <P2PPeer>[];
    }
  }

  String _errorOf(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) return error;
      }
    } on FormatException {
      // fall through to the status line
    }
    return 'request failed ($status)';
  }

  Future<void> dispose() async {
    _http.close(force: true);
  }
}
