import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../services/call_config.dart';
import '../services/call_session.dart';
import '../services/p2p_session.dart' show SignalSender;
import 'p2p_controller.dart';
import 'nearby_enabled_controller.dart';

final callControllerProvider =
    NotifierProvider<CallController, CallState>(CallController.new);

enum CallStatus { idle, inviting, ringing, connecting, active, ended }

/// One call's UI state. Media itself lives in [CallSession]; this is the
/// ringer, timers, toggles, and route badge.
class CallState {
  const CallState({
    this.status = CallStatus.idle,
    this.peerId,
    this.peerLabel,
    this.callId,
    this.video = false,
    this.muted = false,
    this.speaker = false,
    this.cameraOn = true,
    this.route = CallRoute.unknown,
    this.error,
    this.declined = false,
  });

  final CallStatus status;
  final String? peerId;
  final String? peerLabel;
  final String? callId;
  final bool video;
  final bool muted;
  final bool speaker;
  final bool cameraOn;
  final CallRoute route;
  final String? error;
  final bool declined;

  bool get inCall =>
      status == CallStatus.inviting ||
      status == CallStatus.ringing ||
      status == CallStatus.connecting ||
      status == CallStatus.active;

  CallState copyWith({
    CallStatus? status,
    String? peerId,
    String? peerLabel,
    String? callId,
    bool? video,
    bool? muted,
    bool? speaker,
    bool? cameraOn,
    CallRoute? route,
    String? error,
    bool? declined,
    bool clearPeer = false,
  }) {
    return CallState(
      status: status ?? this.status,
      peerId: clearPeer ? null : (peerId ?? this.peerId),
      peerLabel: clearPeer ? null : (peerLabel ?? this.peerLabel),
      callId: callId ?? this.callId,
      video: video ?? this.video,
      muted: muted ?? this.muted,
      speaker: speaker ?? this.speaker,
      cameraOn: cameraOn ?? this.cameraOn,
      route: route ?? this.route,
      error: error,
      declined: declined ?? this.declined,
    );
  }
}

class CallController extends Notifier<CallState> {
  static const Duration _inviteTimeout = Duration(seconds: 30);

  CallSession? _session;
  StreamSubscription<P2PSignalFrame>? _bus;
  StreamSubscription<RTCPeerConnectionState>? _connStates;
  Timer? _timeout;

  /// Test seam: builds the media session. Defaults to the real one.
  CallSession Function(SignalSender send)? sessionFactory;

  /// Live media session for the current call (null when idle). UI attaches
  /// renderers to its [CallSession.remoteStreams].
  CallSession? get session => _session;

  @override
  CallState build() {
    final bus = ref.read(p2pControllerProvider.notifier).signalBus.stream;
    _bus = bus.listen(_onSignal, onError: (_) {});
    ref.onDispose(() {
      _bus?.cancel();
      _timeout?.cancel();
      _connStates?.cancel();
      unawaited(_session?.close(notify: false));
    });
    // Killing nearby drops the call immediately: no discovery, no relay.
    ref.listen<bool>(nearbyEnabledProvider, (_, enabled) {
      if (!enabled && state.inCall) unawaited(hangup());
    });
    return const CallState();
  }

  String _newCallId() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'call-$stamp';
  }

  Future<bool> _ensureMediaPermission(bool video) async {
    // Desktop WebRTC prompts natively; the plugin has no Linux backend.
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    try {
      final types = [Permission.microphone, if (video) Permission.camera];
      final results = await types.request();
      return results.values.every((s) => s.isGranted || s.isLimited);
    } catch (_) {
      return true;
    }
  }

  Future<void> _relay(
    String to,
    P2PSignalKind kind, [
    Object? payload,
  ]) {
    return ref
        .read(p2pControllerProvider.notifier)
        .relaySignal(to: to, kind: kind, payload: payload);
  }

  CallSession _newSession() {
    final factory = sessionFactory;
    if (factory != null) {
      return factory((to, kind, payload) => _relay(to, kind, payload));
    }
    return CallSession(
      sendSignal: (to, kind, payload) => _relay(to, kind, payload),
    );
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(_inviteTimeout, () {
      if (state.status == CallStatus.inviting ||
          state.status == CallStatus.connecting) {
        final peerId = state.peerId;
        final callId = state.callId;
        unawaited(hangup(silent: true));
        if (peerId != null && callId != null) {
          unawaited(
            _relay(
              peerId,
              P2PSignalKind.callEnd,
              {'callId': callId},
            ).catchError((_) {}),
          );
        }
        state = state.copyWith(
          status: CallStatus.ended,
          error: 'No answer',
          clearPeer: true,
        );
      }
    });
  }

  /// Starts an outgoing call: invite first (no media captured yet), SDP only
  /// after the peer accepts.
  Future<void> startCall({
    required String peerId,
    String? peerLabel,
    required bool video,
  }) async {
    if (state.inCall) return;
    if (!await _ensureMediaPermission(video)) {
      state = state.copyWith(error: 'Microphone permission denied');
      return;
    }
    final callId = _newCallId();
    _session?.close(notify: false);
    _session = _newSession();
    _listenSession(_session!);
    try {
      await _relay(peerId, P2PSignalKind.callInvite, {
        'callId': callId,
        'video': video,
      });
    } catch (e) {
      state = state.copyWith(error: 'Could not reach peer');
      return;
    }
    state = CallState(
      status: CallStatus.inviting,
      peerId: peerId,
      peerLabel: peerLabel,
      callId: callId,
      video: video,
    );
    _armTimeout();
  }

  /// Accepts the ringing call: tells the caller, then waits for its SDP
  /// offer (which arrives scoped and is answered in [_onSignal]).
  Future<void> acceptCall() async {
    final peerId = state.peerId;
    final callId = state.callId;
    if (state.status != CallStatus.ringing || peerId == null || callId == null) {
      return;
    }
    if (!await _ensureMediaPermission(state.video)) {
      state = state.copyWith(error: 'Microphone permission denied');
      return;
    }
    _session?.close(notify: false);
    _session = _newSession();
    _listenSession(_session!);
    try {
      await _relay(peerId, P2PSignalKind.callAccept, {'callId': callId});
    } catch (_) {
      state = state.copyWith(
        status: CallStatus.ended,
        error: 'Connection lost',
        clearPeer: true,
      );
      return;
    }
    state = state.copyWith(status: CallStatus.connecting);
    _armTimeout();
  }

  Future<void> declineCall() async {
    final peerId = state.peerId;
    final callId = state.callId;
    state = const CallState();
    _timeout?.cancel();
    await _session?.close(notify: false);
    _session = null;
    if (peerId != null && callId != null) {
      await _relay(
        peerId,
        P2PSignalKind.callDecline,
        {'callId': callId},
      ).catchError((_) {});
    }
  }

  Future<void> hangup({bool silent = false}) async {
    _timeout?.cancel();
    final session = _session;
    _session = null;
    if (!silent) {
      // Signal the end explicitly when the media session hasn't started
      // (invite timeout, disconnect), then let the session finish teardown.
      if (session != null && session.callId != null && session.peerId != null) {
        await session.hangup().catchError((_) {});
      } else if (state.peerId != null && state.callId != null) {
        await _relay(
          state.peerId!,
          P2PSignalKind.callEnd,
          {'callId': state.callId!},
        ).catchError((_) {});
      }
    } else {
      await session?.close(notify: false).catchError((_) {});
    }
    await _connStates?.cancel();
    _connStates = null;
    if (!silent) {
      state = const CallState(status: CallStatus.ended);
    }
  }

  Future<void> dismiss() async {
    await hangup(silent: true);
    state = const CallState();
  }

  Future<void> toggleMute() async {
    final muted = !state.muted;
    await _session?.setMuted(muted).catchError((_) {});
    state = state.copyWith(muted: muted);
  }

  Future<void> toggleSpeaker() async {
    final speaker = !state.speaker;
    await _session?.setSpeaker(speaker).catchError((_) {});
    state = state.copyWith(speaker: speaker);
  }

  Future<void> toggleCamera() async {
    final cameraOn = !state.cameraOn;
    await _session?.setVideoEnabled(cameraOn).catchError((_) {});
    state = state.copyWith(cameraOn: cameraOn);
  }

  Future<void> switchCamera() async {
    await _session?.switchCamera().catchError((_) {});
  }

  void _listenSession(CallSession session) {
    _connStates?.cancel();
    _connStates = session.states.listen((pcState) async {
      if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _timeout?.cancel();
        final route = await session.route().catchError((_) => CallRoute.unknown);
        if (!state.inCall) return;
        state = state.copyWith(status: CallStatus.active, route: route);
      } else if (pcState ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          pcState ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (state.inCall) {
          await hangup(silent: true);
          state = state.copyWith(
            status: CallStatus.ended,
            error: 'Connection lost',
            clearPeer: true,
          );
        }
      }
    });
  }

  Future<void> _onSignal(P2PSignalFrame frame) async {
    final signal = frame;
    switch (signal.kind) {
      case P2PSignalKind.callInvite:
        await _onInvite(signal);
      case P2PSignalKind.callAccept:
        await _onAccept(signal);
      case P2PSignalKind.callDecline:
        _onDecline(signal);
      case P2PSignalKind.callEnd:
        await _onRemoteEnd(signal);
      case P2PSignalKind.offer:
        await _onOffer(signal);
      case P2PSignalKind.answer:
      case P2PSignalKind.candidate:
        await _session?.handleSignal(signal).catchError((_) {});
      case P2PSignalKind.bye:
        break;
    }
  }

  Future<void> _onInvite(P2PSignalFrame signal) async {
    final payload = signal.payload;
    if (payload is! Map) return;
    final callId = payload['callId']?.toString();
    if (callId == null || callId.isEmpty) return;
    // Busy: decline politely so the caller stops ringing.
    if (state.inCall) {
      await _relay(
        signal.from,
        P2PSignalKind.callDecline,
        {'callId': callId},
      ).catchError((_) {});
      return;
    }
    state = CallState(
      status: CallStatus.ringing,
      peerId: signal.from,
      peerLabel: _peerLabel(signal.from),
      callId: callId,
      video: payload['video'] == true,
    );
  }

  Future<void> _onAccept(P2PSignalFrame signal) async {
    if (state.status != CallStatus.inviting) return;
    if (!_matches(signal)) return;
    // Peer accepted: capture media and offer now (never before accept).
    final session = _session;
    final peerId = state.peerId;
    final callId = state.callId;
    if (session == null || peerId == null || callId == null) return;
    state = state.copyWith(status: CallStatus.connecting);
    try {
      await session.startCall(peerId: peerId, callId: callId, video: state.video);
    } catch (_) {
      await hangup(silent: true);
      state = state.copyWith(
        status: CallStatus.ended,
        error: 'Could not start media',
        clearPeer: true,
      );
    }
  }

  void _onDecline(P2PSignalFrame signal) {
    if (state.status != CallStatus.inviting) return;
    if (!_matches(signal)) return;
    _timeout?.cancel();
    _session?.close(notify: false);
    _session = null;
    state = state.copyWith(
      status: CallStatus.ended,
      declined: true,
      clearPeer: true,
    );
  }

  Future<void> _onRemoteEnd(P2PSignalFrame signal) async {
    if (!state.inCall) return;
    if (state.callId != null && !_matches(signal)) return;
    await hangup(silent: true);
    state = const CallState(status: CallStatus.ended);
  }

  Future<void> _onOffer(P2PSignalFrame signal) async {
    // Call-scoped offers are answered here; file offers never reach this bus
    // consumer... actually every frame fans out, so filter by scope.
    final payload = signal.payload;
    if (payload is! Map || payload['scope'] != 'call') return;
    if (state.status != CallStatus.connecting &&
        state.status != CallStatus.ringing) {
      return;
    }
    if (!_matches(signal)) return;
    final session = _session;
    final peerId = state.peerId;
    final callId = state.callId;
    if (session == null || peerId == null || callId == null) return;
    final sdp = payload['sdp']?.toString();
    final type = payload['type']?.toString();
    if (sdp == null || type == null) return;
    // If we never accepted (glare: both dialed), answer only when ringing.
    if (state.status == CallStatus.ringing) {
      if (!await _ensureMediaPermission(state.video)) return;
    }
    try {
      await session.answerCall(
        peerId: peerId,
        callId: callId,
        video: payload['video'] == true || state.video,
        remoteOffer: RTCSessionDescription(sdp, type),
      );
      state = state.copyWith(
        status: CallStatus.connecting,
        video: payload['video'] == true || state.video,
      );
    } catch (_) {
      await hangup(silent: true);
      state = state.copyWith(
        status: CallStatus.ended,
        error: 'Could not start media',
        clearPeer: true,
      );
    }
  }

  bool _matches(P2PSignalFrame signal) {
    final payload = signal.payload;
    if (payload is! Map) return state.callId == null;
    final callId = payload['callId']?.toString();
    return callId != null && callId == state.callId && signal.from == state.peerId;
  }

  String? _peerLabel(String peerId) {
    try {
      final peers = ref.read(p2pControllerProvider).peers;
      for (final peer in peers) {
        if (peer.id == peerId) return peer.user;
      }
    } catch (_) {}
    return null;
  }
}
