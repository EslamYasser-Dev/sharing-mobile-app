import 'dart:async';

enum PeerTransportType {
  lan,
  bluetooth,
  webrtc,
}

enum PeerStatus {
  online,
  offline,
  connecting,
}

enum DiscoverabilityMode {
  everyone,
  contacts,
  hidden,
}

class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.displayName,
    this.deviceName,
    required this.transportType,
    required this.status,
    this.capabilities = const {},
    this.ipAddress,
    this.port,
    this.avatarHash,
    this.isTrusted = false,
    this.isBlocked = false,
    required this.lastSeen,
    this.pairingState = PairingState.none,
  });

  final String id;
  final String displayName;
  final String? deviceName;
  final PeerTransportType transportType;
  final PeerStatus status;
  final Map<String, dynamic> capabilities;
  final String? ipAddress;
  final int? port;
  final String? avatarHash;
  final bool isTrusted;
  final bool isBlocked;
  final DateTime lastSeen;
  final PairingState pairingState;

  NearbyPeer copyWith({
    String? id,
    String? displayName,
    String? deviceName,
    PeerTransportType? transportType,
    PeerStatus? status,
    Map<String, dynamic>? capabilities,
    String? ipAddress,
    int? port,
    String? avatarHash,
    bool? isTrusted,
    bool? isBlocked,
    DateTime? lastSeen,
    PairingState? pairingState,
  }) {
    return NearbyPeer(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      deviceName: deviceName ?? this.deviceName,
      transportType: transportType ?? this.transportType,
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      avatarHash: avatarHash ?? this.avatarHash,
      isTrusted: isTrusted ?? this.isTrusted,
      isBlocked: isBlocked ?? this.isBlocked,
      lastSeen: lastSeen ?? this.lastSeen,
      pairingState: pairingState ?? this.pairingState,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'deviceName': deviceName,
    'transportType': transportType.name,
    'status': status.name,
    'capabilities': capabilities,
    'ipAddress': ipAddress,
    'port': port,
    'avatarHash': avatarHash,
    'isTrusted': isTrusted,
    'isBlocked': isBlocked,
    'lastSeen': lastSeen.toIso8601String(),
    'pairingState': pairingState.name,
  };

  factory NearbyPeer.fromJson(Map<String, dynamic> json) => NearbyPeer(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    deviceName: json['deviceName'] as String?,
    transportType: PeerTransportType.values.byName(json['transportType'] as String),
    status: PeerStatus.values.byName(json['status'] as String),
    capabilities: Map<String, dynamic>.from(json['capabilities'] as Map? ?? {}),
    ipAddress: json['ipAddress'] as String?,
    port: json['port'] as int?,
    avatarHash: json['avatarHash'] as String?,
    isTrusted: json['isTrusted'] as bool? ?? false,
    isBlocked: json['isBlocked'] as bool? ?? false,
    lastSeen: DateTime.parse(json['lastSeen'] as String),
    pairingState: PairingState.values.byName(json['pairingState'] as String? ?? 'none'),
  );

  bool get supportsResume => capabilities['supportsResume'] == true;
  int get maxFileSize => capabilities['maxFileSize'] as int? ?? 0;
  String get version => capabilities['version'] as String? ?? '1';
}

enum PairingState {
  none,
  pending,
  paired,
  rejected,
}

class PeerRepository {
  PeerRepository._();

  static final PeerRepository instance = PeerRepository._();

  final Map<String, NearbyPeer> _peers = {};
  final StreamController<NearbyPeer> _peerUpdates = StreamController<NearbyPeer>.broadcast();
  final StreamController<String> _peerRemoved = StreamController<String>.broadcast();

  Stream<NearbyPeer> get peerUpdates => _peerUpdates.stream;
  Stream<String> get peerRemoved => _peerRemoved.stream;

  List<NearbyPeer> get allPeers => _peers.values.toList();

  List<NearbyPeer> get trustedPeers => _peers.values.where((p) => p.isTrusted).toList();

  List<NearbyPeer> get onlinePeers => _peers.values.where((p) => p.status == PeerStatus.online).toList();

  NearbyPeer? getPeer(String id) => _peers[id];

  void updatePeer(NearbyPeer peer) {
    final existing = _peers[peer.id];
    if (existing == null || existing.lastSeen.isBefore(peer.lastSeen)) {
      _peers[peer.id] = peer;
      _peerUpdates.add(peer);
    }
  }

  void removePeer(String id) {
    _peers.remove(id);
    _peerRemoved.add(id);
  }

  void markPeerTrusted(String id, {bool trusted = true}) {
    final peer = _peers[id];
    if (peer != null) {
      updatePeer(peer.copyWith(isTrusted: trusted));
    }
  }

  void markPeerBlocked(String id, {bool blocked = true}) {
    final peer = _peers[id];
    if (peer != null) {
      updatePeer(peer.copyWith(isBlocked: blocked));
    }
  }

  void updatePairingState(String id, PairingState state) {
    final peer = _peers[id];
    if (peer != null) {
      updatePeer(peer.copyWith(pairingState: state));
    }
  }

  void clear() {
    _peers.clear();
  }

  void dispose() {
    _peerUpdates.close();
    _peerRemoved.close();
  }
}