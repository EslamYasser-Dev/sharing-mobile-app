import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Relays one signaling frame to a peer. The caller closes over the session's
/// own peer id, which the server assigns when the stream opens.
typedef SignalSender = Future<void> Function(
  String to,
  P2PSignalKind kind,
  Object? payload,
);

/// One file being received, held while its bytes arrive.
class _ReceiveBuffer {
  _ReceiveBuffer({
    required this.id,
    required this.peerId,
    required this.name,
    required this.size,
    required this.path,
    required this.sink,
  });

  final String id;
  final String peerId;
  final String name;
  final int size;
  final String path;
  final IOSink sink;
  int loaded = 0;
}

/// WebRTC side of peer-to-peer sharing.
///
/// The server only relays SDP/ICE frames; once a data channel is open the
/// bytes travel directly between devices. Transfers are bracketed by JSON
/// control frames (`meta`/`end`/`error`) interleaved with raw binary chunks,
/// exactly as the web client does, so both ends stay interoperable.
///
/// Progress and lifecycle arrive on [transfers] as [P2PTransfer] snapshots.
class P2PSession {
  P2PSession({
    required this.sendSignal,
    this.chunkSize = 16 * 1024,
    this.maxBuffered = 1500000,
    this.openTimeout = const Duration(seconds: 20),
  });

  /// Bytes per data channel message — matches the web client.
  final int chunkSize;

  /// Backpressure threshold: stop reading the file while this many bytes are
  /// still queued on the channel.
  final int maxBuffered;

  final Duration openTimeout;
  final SignalSender sendSignal;

  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, _ReceiveBuffer> _buffers = {};
  final Map<String, DateTime> _lastEmit = {};

  final StreamController<P2PTransfer> _transfers =
      StreamController<P2PTransfer>.broadcast();

  /// Emits a snapshot whenever a transfer starts, progresses or finishes.
  Stream<P2PTransfer> get transfers => _transfers.stream;

  void _emit(P2PTransfer transfer, {bool force = false}) {
    if (_transfers.isClosed) return;
    final now = DateTime.now();
    if (!force) {
      final last = _lastEmit[transfer.id];
      if (last != null && now.difference(last).inMilliseconds < 100) return;
    }
    _lastEmit[transfer.id] = now;
    _transfers.add(transfer);
  }

  // ---------------------------------------------------------------- signaling

  Future<RTCPeerConnection> _peerConnection(String remoteId) async {
    final existing = _connections[remoteId];
    if (existing != null) return existing;

    // No TURN: candidates only, so peers on the same LAN connect directly,
    // mirroring the web client's empty ICE server list.
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': <dynamic>[],
    });

    pc.onIceCandidate = (candidate) {
      unawaited(
        sendSignal(
          remoteId,
          P2PSignalKind.candidate,
          candidate.toMap(),
        ).catchError((_) {}),
      );
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_cleanup(remoteId));
      }
    };
    pc.onDataChannel = (channel) => _attach(remoteId, channel);

    _connections[remoteId] = pc;

    // Candidates can arrive before the remote description is set; the spec
    // requires them to wait, so they are buffered until it lands.
    final pending = _pendingCandidates.remove(remoteId);
    if (pending != null) {
      for (final candidate in pending) {
        await pc.addCandidate(candidate).catchError((_) {});
      }
    }
    return pc;
  }

  RTCSessionDescription? _asSessionDescription(Object? payload) {
    if (payload is! Map) return null;
    final sdp = payload['sdp'];
    final type = payload['type'];
    if (sdp is! String || type is! String) return null;
    return RTCSessionDescription(sdp, type);
  }

  RTCIceCandidate? _asIceCandidate(Object? payload) {
    if (payload is! Map) return null;
    final candidate = payload['candidate'];
    if (candidate is! String || candidate.isEmpty) return null;
    return RTCIceCandidate(
      candidate,
      payload['sdpMid'] as String?,
      (payload['sdpMLineIndex'] as num?)?.toInt(),
    );
  }

  Future<void> _setRemote(
    RTCPeerConnection pc,
    String remoteId,
    RTCSessionDescription description,
  ) async {
    await pc.setRemoteDescription(description);
    final pending = _pendingCandidates.remove(remoteId);
    if (pending == null) return;
    for (final candidate in pending) {
      await pc.addCandidate(candidate).catchError((_) {});
    }
  }

  /// Applies one relayed frame. Unknown or malformed payloads are ignored
  /// rather than thrown, so a bad frame cannot kill the session.
  Future<void> handleSignal(P2PSignalFrame signal) async {
    final remoteId = signal.from;
    if (remoteId.isEmpty || remoteId == '') return;

    if (signal.kind == P2PSignalKind.bye) {
      await _cleanup(remoteId);
      return;
    }

    final pc = await _peerConnection(remoteId);

    if (signal.kind == P2PSignalKind.offer) {
      final description = _asSessionDescription(signal.payload);
      if (description == null) return;
      await _setRemote(pc, remoteId, description);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await sendSignal(remoteId, P2PSignalKind.answer, answer.toMap());
      return;
    }

    if (signal.kind == P2PSignalKind.answer) {
      final description = _asSessionDescription(signal.payload);
      if (description == null) return;
      await _setRemote(pc, remoteId, description);
      return;
    }

    if (signal.kind == P2PSignalKind.candidate) {
      final candidate = _asIceCandidate(signal.payload);
      if (candidate == null) return;
      if (await pc.getRemoteDescription() == null) {
        _pendingCandidates.putIfAbsent(remoteId, () => []).add(candidate);
        return;
      }
      await pc.addCandidate(candidate).catchError((_) {});
    }
  }

  // ------------------------------------------------------------------ sending

  /// Sends one file over a fresh ordered data channel.
  ///
  /// Exactly one file is in flight per channel: a new channel is opened per
  /// transfer, which is what lets the receiver tell streams apart without
  /// any in-band multiplexing.
  Future<void> sendFile({
    required String peerId,
    required String transferId,
    required String name,
    required int size,
    String? peerLabel,
    File? file,
    Uint8List? bytes,
  }) async {
    if (file == null && bytes == null) {
      throw StateError('no file data');
    }

    final pc = await _peerConnection(peerId);
    final init = RTCDataChannelInit()
      ..ordered = true
      ..binaryType = 'binary';
    final channel = await pc.createDataChannel('file-$transferId', init);
    channel.bufferedAmountLowThreshold = maxBuffered ~/ 2;

    var transfer = P2PTransfer(
      id: transferId,
      peerId: peerId,
      peerLabel: peerLabel,
      name: name,
      size: size,
      direction: P2PTransferDirection.send,
    );
    _emit(transfer, force: true);

    try {
      await _waitForOpen(channel);
      transfer = transfer.copyWith(status: P2PTransferStatus.active);
      _emit(transfer, force: true);

      await channel.send(
        RTCDataChannelMessage(
          jsonEncode(
            P2PControlMessage(
              type: 'meta',
              id: transferId,
              name: name,
              size: size,
            ).toJson(),
          ),
        ),
      );

      await _streamFile(channel, file, bytes, (loaded) {
        transfer = transfer.copyWith(
          loaded: min(loaded, size),
          status: P2PTransferStatus.active,
        );
        _emit(transfer);
      });

      await channel.send(
        RTCDataChannelMessage(
          jsonEncode(P2PControlMessage(type: 'end', id: transferId).toJson()),
        ),
      );
      transfer = transfer.copyWith(
        loaded: size,
        status: P2PTransferStatus.done,
      );
      _emit(transfer, force: true);
    } catch (error) {
      transfer = transfer.copyWith(
        status: P2PTransferStatus.error,
        error: error.toString(),
      );
      _emit(transfer, force: true);
      rethrow;
    } finally {
      try {
        await channel.close();
      } catch (_) {
        // The peer may already have torn it down.
      }
    }
  }

  Future<void> _waitForOpen(RTCDataChannel channel) async {
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) return;
    final opened = Completer<void>();
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (!opened.isCompleted) opened.complete();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed ||
          state == RTCDataChannelState.RTCDataChannelClosing) {
        if (!opened.isCompleted) {
          opened.completeError(StateError('data channel closed'));
        }
      }
    };
    await opened.future.timeout(
      openTimeout,
      onTimeout: () => throw StateError('data channel timeout'),
    );
  }

  /// Waits while the send buffer is above [maxBuffered].
  ///
  /// Polled rather than event-driven because `bufferedamountlow` is not
  /// reported consistently across the native WebRTC builds; the deadline
  /// keeps a stuck channel from stalling the transfer forever.
  Future<void> _waitWritable(RTCDataChannel channel) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while ((channel.bufferedAmount ?? 0) > maxBuffered) {
      if (DateTime.now().isAfter(deadline)) return;
      if (channel.state != RTCDataChannelState.RTCDataChannelOpen) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _streamFile(
    RTCDataChannel channel,
    File? file,
    Uint8List? bytes,
    void Function(int loaded) onProgress,
  ) async {
    final source = file != null
        ? file.openRead()
        : Stream<List<int>>.value(bytes!);
    var buffer = <int>[];
    var sent = 0;

    await for (final piece in source) {
      buffer.addAll(piece);
      while (buffer.length >= chunkSize) {
        final chunk = Uint8List.fromList(buffer.sublist(0, chunkSize));
        buffer = buffer.sublist(chunkSize);
        await _sendChunk(channel, chunk);
        sent += chunk.length;
        onProgress(sent);
      }
    }
    if (buffer.isNotEmpty) {
      await _sendChunk(channel, Uint8List.fromList(buffer));
      sent += buffer.length;
      onProgress(sent);
    }
  }

  Future<void> _sendChunk(RTCDataChannel channel, Uint8List chunk) async {
    await _waitWritable(channel);
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('channel closed');
    }
    await channel.send(RTCDataChannelMessage.fromBinary(chunk));
  }

  // ---------------------------------------------------------------- receiving

  void _attach(String remoteId, RTCDataChannel channel) {
    channel.onMessage = (message) {
      unawaited(_onMessage(remoteId, message).catchError((_) {}));
    };
  }

  Future<void> _onMessage(
    String remoteId,
    RTCDataChannelMessage message,
  ) async {
    if (!message.isBinary) {
      await _onControl(remoteId, message.text);
      return;
    }
    await _onChunk(message.binary);
  }

  Future<void> _onControl(String remoteId, String text) async {
    final P2PControlMessage control;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      control = P2PControlMessage.fromJson(decoded);
    } on FormatException {
      return; // A malformed control frame is dropped, not fatal.
    }

    if (control.type == 'meta' &&
        control.id != null &&
        control.name != null &&
        control.size != null) {
      await _beginReceive(
        remoteId: remoteId,
        id: control.id!,
        name: control.name!,
        size: control.size!,
        mime: control.mime,
      );
      return;
    }

    if (control.type == 'end' && control.id != null) {
      final buffer = _buffers.remove(control.id!);
      if (buffer == null) return;
      await buffer.sink.flush();
      await buffer.sink.close();
      _lastEmit.remove(control.id);
      _emit(
        P2PTransfer(
          id: buffer.id,
          peerId: buffer.peerId,
          name: buffer.name,
          size: buffer.size,
          loaded: buffer.loaded,
          status: P2PTransferStatus.done,
          direction: P2PTransferDirection.receive,
          localPath: buffer.path,
        ),
        force: true,
      );
      return;
    }

    if (control.type == 'error' && control.id != null) {
      final buffer = _buffers.remove(control.id!);
      if (buffer == null) return;
      try {
        await buffer.sink.close();
      } catch (_) {}
      await _deleteQuietly(buffer.path);
      _emit(
        P2PTransfer(
          id: buffer.id,
          peerId: buffer.peerId,
          name: buffer.name,
          size: buffer.size,
          status: P2PTransferStatus.error,
          direction: P2PTransferDirection.receive,
          error: 'transfer failed',
        ),
        force: true,
      );
    }
  }

  Future<void> _beginReceive({
    required String remoteId,
    required String id,
    required String name,
    required int size,
    String? mime,
  }) async {
    // `mime` is part of the wire protocol but unused here: the file lands on
    // disk and is opened by name.
    final path = await _reservePath(name);
    final buffer = _ReceiveBuffer(
      id: id,
      peerId: remoteId,
      name: name,
      size: size,
      path: path,
      sink: File(path).openWrite(),
    );
    _buffers[id] = buffer;
    _emit(
      P2PTransfer(
        id: id,
        peerId: remoteId,
        name: name,
        size: size,
        direction: P2PTransferDirection.receive,
        status: P2PTransferStatus.active,
      ),
      force: true,
    );
  }

  Future<void> _onChunk(Uint8List bytes) async {
    if (_buffers.isEmpty) return;
    // One file is in flight per channel and only one receive is tracked at a
    // time, so the first buffer still short of its size owns this chunk.
    _ReceiveBuffer? target;
    for (final buffer in _buffers.values) {
      if (buffer.loaded < buffer.size) {
        target = buffer;
        break;
      }
    }
    if (target == null) {
      if (_buffers.isEmpty) return;
      target = _buffers.values.first;
    }

    target.sink.add(bytes);
    target.loaded += bytes.length;
    _emit(
      P2PTransfer(
        id: target.id,
        peerId: target.peerId,
        name: target.name,
        size: target.size,
        loaded: min(target.loaded, target.size),
        status: P2PTransferStatus.active,
        direction: P2PTransferDirection.receive,
      ),
    );
  }

  Future<String> _reservePath(String name) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/$stamp-p2p-${p2pSafeFileName(name)}';
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort — a leftover temp file is not worth failing over.
    }
  }

  // ----------------------------------------------------------------- teardown

  Future<void> _cleanup(String remoteId) async {
    final pc = _connections.remove(remoteId);
    _pendingCandidates.remove(remoteId);
    if (pc == null) return;
    try {
      await pc.close();
    } catch (_) {}
    try {
      await pc.dispose();
    } catch (_) {}
  }

  /// Says goodbye to every peer and releases all native resources.
  Future<void> close() async {
    final ids = _connections.keys.toList();
    for (final id in ids) {
      await sendSignal(id, P2PSignalKind.bye, null).catchError((_) {});
      await _cleanup(id);
    }
    for (final buffer in _buffers.values) {
      try {
        await buffer.sink.close();
      } catch (_) {}
      await _deleteQuietly(buffer.path);
    }
    _buffers.clear();
    _lastEmit.clear();
    if (!_transfers.isClosed) await _transfers.close();
  }
}

/// Strips any directory component from a peer-supplied [name] so a remote
/// device cannot choose where the file is written. Empty and traversal-only
/// names fall back to a fixed name.
///
/// Exposed for testing — this is the only place a received filename is
/// trusted.
String p2pSafeFileName(String name) {
  final base = name.split(RegExp(r'[/\\]')).last.trim();
  if (base.isEmpty || base == '.' || base == '..') return 'received.bin';
  return base;
}
