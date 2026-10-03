import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../models.dart';
import '../services/p2p_session.dart';
import '../services/p2p_signaling.dart';
import '../services/token_store.dart';
import 'nearby_enabled_controller.dart';

/// Everything the P2P screen renders.
class P2PState {
  const P2PState({
    this.connected = false,
    this.peerId,
    this.peers = const <P2PPeer>[],
    this.transfers = const <P2PTransfer>[],
    this.reconnecting = false,
  });

  /// True once the signaling stream has delivered a `hello`.
  final bool connected;

  /// This session's id, assigned by the server on `hello`.
  final String? peerId;

  final List<P2PPeer> peers;
  final List<P2PTransfer> transfers;

  /// A retry is scheduled, so the screen can say "reconnecting" rather than
  /// "connecting".
  final bool reconnecting;

  P2PState copyWith({
    bool? connected,
    String? peerId,
    List<P2PPeer>? peers,
    List<P2PTransfer>? transfers,
    bool? reconnecting,
  }) {
    return P2PState(
      connected: connected ?? this.connected,
      peerId: peerId ?? this.peerId,
      peers: peers ?? this.peers,
      transfers: transfers ?? this.transfers,
      reconnecting: reconnecting ?? this.reconnecting,
    );
  }
}

final p2pSignalingProvider = Provider<P2PSignaling>((ref) {
  final store = TokenStore();
  final signaling = P2PSignaling(baseUrl: apiBaseUrl, readToken: store.get);
  ref.onDispose(signaling.dispose);
  return signaling;
});

/// Drives the signaling stream and the WebRTC session.
///
/// Reconnects with the same exponential backoff the events stream uses
/// (1s → 30s), guarded by a generation counter so a superseded attempt
/// cannot resurrect itself.
class P2PController extends Notifier<P2PState> {
  static const int _maxRetryMs = 30000;

  P2PSession? _session;
  StreamSubscription<P2PFrame>? _frames;
  StreamSubscription<P2PTransfer>? _transfers;
  Timer? _retryTimer;
  bool _running = false;
  int _retryDelay = 1000;
  int _generation = 0;
  int _seq = 0;

  /// Broadcast of every relayed signal frame. Call handling subscribes here
  /// so voice/video shares the single SSE stream (and peer id) with file
  /// transfer instead of opening a second identity.
  final StreamController<P2PSignalFrame> signalBus =
      StreamController<P2PSignalFrame>.broadcast();

  /// Relays one frame as this peer. Throws when the stream is down.
  Future<void> relaySignal({
    required String to,
    required P2PSignalKind kind,
    Object? payload,
  }) {
    final self = state.peerId;
    if (self == null || !_running) {
      throw const P2PSignalingException('not connected');
    }
    return ref
        .read(p2pSignalingProvider)
        .sendSignal(from: self, to: to, kind: kind, payload: payload);
  }

  @override
  P2PState build() {
    ref.onDispose(_stop);
    // Master switch: turning nearby off tears the session down immediately.
    ref.listen<bool>(nearbyEnabledProvider, (_, enabled) {
      if (!enabled) _stop();
    });
    return const P2PState();
  }

  void start() {
    if (_running) return;
    if (!ref.read(nearbyEnabledProvider)) return;
    _running = true;
    _retryDelay = 1000;
    unawaited(_open(_generation));
  }

  void stop() => _stop();

  void _stop() {
    _running = false;
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    final frames = _frames;
    _frames = null;
    if (frames != null) unawaited(frames.cancel());
    final transfers = _transfers;
    _transfers = null;
    if (transfers != null) unawaited(transfers.cancel());
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.close());
    state = const P2PState();
  }

  void _scheduleRetry(int generation) {
    if (!_running || generation != _generation) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: _retryDelay), () {
      _retryTimer = null;
      unawaited(_open(generation));
    });
    _retryDelay = min(_retryDelay * 2, _maxRetryMs);
  }

  P2PSession _ensureSession() {
    final existing = _session;
    if (existing != null) return existing;

    final signaling = ref.read(p2pSignalingProvider);
    final session = P2PSession(
      sendSignal: (to, kind, payload) async {
        final self = state.peerId;
        if (self == null) {
          throw const P2PSignalingException('no peer session');
        }
        await signaling.sendSignal(
          from: self,
          to: to,
          kind: kind,
          payload: payload,
        );
      },
    );
    _session = session;
    _transfers = session.transfers.listen(_onTransfer, onError: (_) {});
    return session;
  }

  /// Listens until the stream ends, then schedules the reconnect. Using a
  /// subscription (rather than `await for`) is what lets [stop] cancel an
  /// attempt that is still in flight.
  Future<void> _open(int generation) async {
    if (!_running || generation != _generation) return;
    final session = _ensureSession();

    final finished = Completer<void>();
    final subscription = ref
        .read(p2pSignalingProvider)
        .connect()
        .listen(
          (frame) {
            if (!_running || generation != _generation) return;
            _retryDelay = 1000;
            _handle(frame, session);
          },
          // Failures arrive as error events; the stream still closes, which is
          // what drives the reconnect below.
          onError: (Object _) {},
          onDone: () {
            if (!finished.isCompleted) finished.complete();
          },
        );

    _frames = subscription;
    await finished.future;
    await subscription.cancel();
    if (identical(_frames, subscription)) _frames = null;

    if (_running && generation == _generation) {
      state = state.copyWith(connected: false, reconnecting: true);
      _scheduleRetry(generation);
    }
  }

  void _handle(P2PFrame frame, P2PSession session) {
    if (frame.type == 'hello') {
      state = state.copyWith(
        connected: true,
        reconnecting: false,
        peerId: frame.peerId ?? state.peerId,
        peers: frame.peers,
      );
      return;
    }
    if (frame.type == 'peers') {
      state = state.copyWith(peers: frame.peers);
      return;
    }
    final signal = frame.signal;
    if (frame.type == 'signal' && signal != null) {
      unawaited(session.handleSignal(signal).catchError((_) {}));
      // File sessions ignore call namespaced frames (and vice versa), so
      // fanning every frame out to the bus is safe for both.
      if (!signalBus.isClosed) signalBus.add(signal);
    }
  }

  void _onTransfer(P2PTransfer transfer) {
    var next = transfer;
    // The session does not know usernames; resolve the label here, where the
    // peer list already lives, so a snapshot is always display-ready.
    if (next.peerLabel == null) {
      for (final peer in state.peers) {
        if (peer.id == next.peerId) {
          next = next.copyWith(peerLabel: peer.user);
          break;
        }
      }
    }

    final list = [...state.transfers];
    final index = list.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      list[index] = next;
    } else {
      list.insert(0, next);
    }
    state = state.copyWith(transfers: list);
  }

  String _newTransferId() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _seq = (_seq + 1) & 0xffff;
    return '$stamp-${_seq.toRadixString(36)}';
  }

  /// Sends one file to [peerId]. Completes when the transfer finishes, or
  /// throws if it fails — the transfer is recorded either way, so the screen
  /// can show the failure.
  Future<void> sendFile({
    required String peerId,
    required String name,
    required int size,
    String? peerLabel,
    String? path,
    Uint8List? bytes,
  }) {
    return _ensureSession().sendFile(
      peerId: peerId,
      transferId: _newTransferId(),
      name: name,
      size: size,
      peerLabel: peerLabel,
      file: path == null ? null : File(path),
      bytes: bytes,
    );
  }

  /// Drops one transfer from the list.
  void dismiss(String transferId) {
    state = state.copyWith(
      transfers: state.transfers
          .where((transfer) => transfer.id != transferId)
          .toList(growable: false),
    );
  }
}

final p2pControllerProvider = NotifierProvider<P2PController, P2PState>(
  P2PController.new,
);
