import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models.dart';
import 'call_config.dart';
import 'p2p_session.dart' show SignalSender;

/// One voice/video call: exactly one [RTCPeerConnection] carrying local
/// mic/camera tracks to the peer. Signaling rides the shared P2P relay in
/// the `call-*` namespace with call-scoped SDP (`{'scope': 'call', ...}`),
/// which file-transfer sessions ignore.
///
/// Lifecycle snapshots arrive on [states]; the remote media arrives on
/// [remoteStreams]. Renderers ([RTCVideoRenderer]) stay UI-owned.
class CallSession {
  CallSession({required this.sendSignal, CallConfig? config})
      : _config = config ?? CallConfig.fromEnvironment();

  final SignalSender sendSignal;
  final CallConfig _config;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  String? _callId;
  String? _peerId;
  bool _video = false;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _closed = false;

  final StreamController<MediaStream> _remoteStreams =
      StreamController<MediaStream>.broadcast();
  final StreamController<MediaStream> _localStreams =
      StreamController<MediaStream>.broadcast();
  final StreamController<RTCPeerConnectionState> _states =
      StreamController<RTCPeerConnectionState>.broadcast();

  Stream<MediaStream> get remoteStreams => _remoteStreams.stream;
  Stream<MediaStream> get localStreams => _localStreams.stream;
  Stream<RTCPeerConnectionState> get states => _states.stream;

  String? get callId => _callId;
  String? get peerId => _peerId;
  bool get video => _video;
  bool get hasConnection => _pc != null;

  Future<RTCPeerConnection> _peerConnection(String remoteId) async {
    final existing = _pc;
    if (existing != null) return existing;
    final pc = await createPeerConnection(_config.iceConfiguration);
    pc.onIceCandidate = (candidate) {
      if (_callId == null) return;
      unawaited(
        sendSignal(
          remoteId,
          P2PSignalKind.candidate,
          _scoped({'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex}),
        ).catchError((_) {}),
      );
    };
    pc.onConnectionState = (state) {
      if (!_states.isClosed) _states.add(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(close(notify: false));
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remote = event.streams.first;
        if (!_remoteStreams.isClosed) _remoteStreams.add(_remote!);
      }
    };
    _pc = pc;
    return pc;
  }

  Map<String, Object?> _scoped(Map<String, Object?> payload) => {
        ...payload,
        'scope': 'call',
        'callId': _callId,
      };

  Future<MediaStream> _localMedia(bool video) async {
    final stream = await navigator.mediaDevices.getUserMedia(
      _config.mediaConstraints(video: video),
    );
    _local = stream;
    _video = video;
    if (!_localStreams.isClosed) _localStreams.add(stream);
    return stream;
  }

  /// Starts an outgoing call: captures media, offers, waits for accept+answer.
  Future<void> startCall({
    required String peerId,
    required String callId,
    required bool video,
  }) async {
    _callId = callId;
    _peerId = peerId;
    final pc = await _peerConnection(peerId);
    final local = await _localMedia(video);
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await sendSignal(
      peerId,
      P2PSignalKind.offer,
      _scoped({...offer.toMap(), 'video': video}),
    );
  }

  /// Answers an incoming call whose offer is [remoteOffer].
  Future<void> answerCall({
    required String peerId,
    required String callId,
    required bool video,
    required RTCSessionDescription remoteOffer,
  }) async {
    _callId = callId;
    _peerId = peerId;
    final pc = await _peerConnection(peerId);
    await pc.setRemoteDescription(remoteOffer);
    final local = await _localMedia(video);
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await sendSignal(
      peerId,
      P2PSignalKind.answer,
      _scoped(answer.toMap()),
    );
    await _flushCandidates(pc);
  }

  /// Applies one relayed frame addressed to this call. Anything else —
  /// file-transfer SDP, other calls, malformed payloads — is ignored.
  Future<void> handleSignal(P2PSignalFrame signal) async {
    if (_closed || _callId == null || _peerId == null) return;
    final payload = signal.payload;
    if (payload is! Map || payload['scope'] != 'call') return;
    if (payload['callId']?.toString() != _callId) return;
    if (signal.from != _peerId) return;
    final pc = _pc;
    if (pc == null) return;

    if (signal.kind == P2PSignalKind.answer) {
      final description = _asSessionDescription(payload);
      if (description == null) return;
      await pc.setRemoteDescription(description);
      await _flushCandidates(pc);
      return;
    }
    if (signal.kind == P2PSignalKind.candidate) {
      final candidate = _asIceCandidate(payload);
      if (candidate == null) return;
      if (await pc.getRemoteDescription() == null) {
        _pendingCandidates.add(candidate);
        return;
      }
      await pc.addCandidate(candidate).catchError((_) {});
    }
  }

  Future<void> _flushCandidates(RTCPeerConnection pc) async {
    if (_pendingCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.of(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in pending) {
      await pc.addCandidate(candidate).catchError((_) {});
    }
  }

  RTCSessionDescription? _asSessionDescription(Map payload) {
    final sdp = payload['sdp'];
    final type = payload['type'];
    if (sdp is! String || type is! String) return null;
    return RTCSessionDescription(sdp, type);
  }

  RTCIceCandidate? _asIceCandidate(Map payload) {
    final candidate = payload['candidate'];
    if (candidate is! String || candidate.isEmpty) return null;
    return RTCIceCandidate(
      candidate,
      payload['sdpMid'] as String?,
      (payload['sdpMLineIndex'] as num?)?.toInt(),
    );
  }

  Future<void> setMuted(bool muted) async {
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> setVideoEnabled(bool enabled) async {
    for (final track in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    for (final track in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      await Helper.switchCamera(track);
    }
  }

  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  /// Current transport route (direct LAN vs TURN relay), or unknown before
  /// the nominated pair exists.
  Future<CallRoute> route() async {
    final pc = _pc;
    if (pc == null) return CallRoute.unknown;
    final stats = await pc.getStats();
    return callRouteFromStats([
      for (final report in stats)
        <String, dynamic>{
          'id': report.id,
          'type': report.type,
          ...Map<String, dynamic>.from(report.values),
        },
    ]);
  }

  /// Hangs up, optionally telling the peer. Idempotent.
  Future<void> hangup({bool notify = true}) async {
    final peerId = _peerId;
    final callId = _callId;
    _peerId = null;
    _callId = null;
    if (notify && peerId != null && callId != null) {
      await sendSignal(
        peerId,
        P2PSignalKind.callEnd,
        {'callId': callId},
      ).catchError((_) {});
    }
    await close(notify: false);
  }

  Future<void> close({bool notify = true}) async {
    if (notify) {
      await hangup(notify: true);
      return;
    }
    _closed = true;
    _pendingCandidates.clear();
    for (final track in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    _local = null;
    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
    if (!_remoteStreams.isClosed) await _remoteStreams.close();
    if (!_localStreams.isClosed) await _localStreams.close();
    if (!_states.isClosed) await _states.close();
  }
}
