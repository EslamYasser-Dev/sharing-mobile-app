import '../config.dart' as app_config;

/// ICE + media configuration for calls.
///
/// Latency story: with no STUN/TURN configured the peer connection gathers
/// host candidates only, so same-LAN calls connect device-to-device with no
/// internet in the path — the ultra-low-latency case. Across NATs, configure
/// a TURN relay (`--dart-define=TURN_URL=...`); media then hairpins through
/// it only when no direct path exists.
class CallConfig {
  const CallConfig({
    this.stunUrl = '',
    this.turnUrl = '',
    this.turnUsername = '',
    this.turnCredential = '',
  });

  factory CallConfig.fromEnvironment() => CallConfig(
        stunUrl: app_config.stunUrl,
        turnUrl: app_config.turnUrl,
        turnUsername: app_config.turnUsername,
        turnCredential: app_config.turnCredential,
      );

  final String stunUrl;
  final String turnUrl;
  final String turnUsername;
  final String turnCredential;

  bool get hasRelay => turnUrl.isNotEmpty;

  /// flutter_webrtc `createPeerConnection` configuration map.
  Map<String, dynamic> get iceConfiguration {
    final servers = <Map<String, dynamic>>[];
    if (stunUrl.isNotEmpty) {
      servers.add({'urls': stunUrl});
    }
    if (turnUrl.isNotEmpty) {
      servers.add({
        'urls': turnUrl,
        'username': turnUsername,
        'credential': turnCredential,
      });
    }
    return {'iceServers': servers};
  }

  /// getUserMedia constraints: voice-first Opus-friendly audio, optional
  /// video. `facingMode: user` keeps selfie framing for video calls.
  Map<String, dynamic> mediaConstraints({required bool video}) => {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '24',
                },
                'facingMode': 'user',
              }
            : false,
      };
}

/// Call transport route derived from the nominated ICE candidate pair.
enum CallRoute { direct, relay, unknown }

/// Picks the route from `getStats` reports: a nominated pair whose local or
/// remote candidate is `relay` means TURN; `host`/`srflx` on both ends means
/// a direct device path. Pure (testable) over the stats JSON shape.
CallRoute callRouteFromStats(List<Map<String, dynamic>> reports) {
  Map<String, dynamic>? activePair;
  final byId = <String, Map<String, dynamic>>{};
  for (final report in reports) {
    final id = report['id']?.toString() ?? '';
    byId[id] = report;
    if (report['type'] == 'candidate-pair' &&
        (report['nominated'] == true || report['writable'] == true) &&
        activePair == null) {
      activePair = report;
    }
  }
  if (activePair == null) return CallRoute.unknown;
  for (final key in ['localCandidateId', 'remoteCandidateId']) {
    final candidate = byId[activePair[key]?.toString() ?? ''];
    final type = candidate?['candidateType']?.toString();
    if (type == 'relay') return CallRoute.relay;
  }
  final localType =
      byId[activePair['localCandidateId']?.toString() ?? '']?['candidateType']
          ?.toString();
  final remoteType =
      byId[activePair['remoteCandidateId']?.toString() ?? '']?['candidateType']
          ?.toString();
  if ((localType == 'host' || localType == 'srflx') &&
      (remoteType == 'host' || remoteType == 'srflx')) {
    return CallRoute.direct;
  }
  return CallRoute.unknown;
}
