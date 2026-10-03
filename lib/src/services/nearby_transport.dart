import 'dart:async';
import 'dart:io';

import '../models/peer.dart';
import '../models/transfer.dart';
import 'mdns_discovery.dart';

abstract class NearbyTransport {
  String get transportName;
  PeerTransportType get transportType;
  Future<void> start();
  Future<void> stop();
  Stream<NearbyPeer> get discoveredPeers;
  Future<void> sendFile({
    required NearbyPeer peer,
    required Transfer transfer,
    required File file,
    void Function(int sent, int total)? onProgress,
    Future<void> Function()? awaitResume,
    bool Function()? shouldCancel,
  });
  Future<void> acceptIncomingTransfer({
    required Transfer transfer,
    required String localPath,
    void Function(int received, int total)? onProgress,
  });
  Stream<Transfer> get incomingTransfers;
  Future<void> cancelIncomingTransfer(String transferId);
  void dispose();
}

class LanTransport implements NearbyTransport {
  LanTransport({
    required MdnsDiscoveryService discoveryService,
    required String localPeerId,
    required String deviceName,
    String? displayName,
    int port = 0,
  })  : _discovery = discoveryService,
        _localPeerId = localPeerId,
        _deviceName = deviceName,
        _displayName = displayName,
        _port = port;

  final MdnsDiscoveryService _discovery;
  final String _localPeerId;
  final String _deviceName;
  final String? _displayName;
  final int _port;
  final StreamController<Transfer> _incomingController = StreamController<Transfer>.broadcast();
  final Map<String, _IncomingTransfer> _incomingTransfers = {};

  @override
  String get transportName => 'LAN (mDNS)';

  @override
  PeerTransportType get transportType => PeerTransportType.lan;

  @override
  Future<void> start() async {
    await _discovery.start(
      localPeerId: _localPeerId,
      port: _port,
      txtRecord: {
        'displayName': _displayName ?? _deviceName,
        'deviceName': _deviceName,
        'supportsResume': 'true',
        'maxFileSize': '1073741824',
        'version': '1',
      },
    );
  }

  @override
  Future<void> stop() async {
    await _discovery.stop();
    await _incomingController.close();
  }

  @override
  Stream<NearbyPeer> get discoveredPeers => _discovery.peerStream;

  @override
  Future<void> sendFile({
    required NearbyPeer peer,
    required Transfer transfer,
    required File file,
    void Function(int sent, int total)? onProgress,
    Future<void> Function()? awaitResume,
    bool Function()? shouldCancel,
  }) async {
    // Implementation would use WebRTC data channel or direct TCP
    // For now, this is a placeholder for the actual P2P implementation
    throw UnimplementedError('LAN file send not yet implemented');
  }

  @override
  Future<void> acceptIncomingTransfer({
    required Transfer transfer,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    final incoming = _IncomingTransfer(
      transfer: transfer,
      localPath: localPath,
      onProgress: onProgress,
    );
    _incomingTransfers[transfer.id] = incoming;
    _incomingController.add(transfer);
  }

  @override
  Stream<Transfer> get incomingTransfers => _incomingController.stream;

  @override
  Future<void> cancelIncomingTransfer(String transferId) async {
    _incomingTransfers.remove(transferId);
  }

  @override
  void dispose() {
    stop();
  }
}

class _IncomingTransfer {
  _IncomingTransfer({
    required this.transfer,
    required this.localPath,
    this.onProgress,
  });

  final Transfer transfer;
  final String localPath;
  final void Function(int received, int total)? onProgress;
}

class BluetoothTransport implements NearbyTransport {
  BluetoothTransport({required String localPeerId}) : _localPeerId = localPeerId;

  final String _localPeerId;
  final StreamController<NearbyPeer> _peerController = StreamController<NearbyPeer>.broadcast();
  final StreamController<Transfer> _incomingController = StreamController<Transfer>.broadcast();

  @override
  String get transportName => 'Bluetooth';

  @override
  PeerTransportType get transportType => PeerTransportType.bluetooth;

  @override
  Future<void> start() async {
    // Platform-specific Bluetooth implementation would go here
    // Using flutter_blue_plus or similar
  }

  @override
  Future<void> stop() async {
    await _peerController.close();
    await _incomingController.close();
  }

  @override
  Stream<NearbyPeer> get discoveredPeers => _peerController.stream;

  @override
  Future<void> sendFile({
    required NearbyPeer peer,
    required Transfer transfer,
    required File file,
    void Function(int sent, int total)? onProgress,
    Future<void> Function()? awaitResume,
    bool Function()? shouldCancel,
  }) async {
    throw UnimplementedError('Bluetooth file send not yet implemented');
  }

  @override
  Future<void> acceptIncomingTransfer({
    required Transfer transfer,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    _incomingController.add(transfer);
  }

  @override
  Stream<Transfer> get incomingTransfers => _incomingController.stream;

  @override
  Future<void> cancelIncomingTransfer(String transferId) async {
    // Implementation
  }

  @override
  void dispose() {
    stop();
  }
}

class WebRtcTransport implements NearbyTransport {
  WebRtcTransport({
    required this.localPeerId,
    required this.signalingUrl,
    required this.getToken,
  });

  final String localPeerId;
  final String signalingUrl;
  final Future<String?> Function() getToken;
  final StreamController<NearbyPeer> _peerController = StreamController<NearbyPeer>.broadcast();
  final StreamController<Transfer> _incomingController = StreamController<Transfer>.broadcast();

  @override
  String get transportName => 'WebRTC (Internet)';

  @override
  PeerTransportType get transportType => PeerTransportType.webrtc;

  @override
  Future<void> start() async {
    // Connect to signaling server
  }

  @override
  Future<void> stop() async {
    await _peerController.close();
    await _incomingController.close();
  }

  @override
  Stream<NearbyPeer> get discoveredPeers => _peerController.stream;

  @override
  Future<void> sendFile({
    required NearbyPeer peer,
    required Transfer transfer,
    required File file,
    void Function(int sent, int total)? onProgress,
    Future<void> Function()? awaitResume,
    bool Function()? shouldCancel,
  }) async {
    // Use existing P2P session
    throw UnimplementedError('Use P2PController for WebRTC transfers');
  }

  @override
  Future<void> acceptIncomingTransfer({
    required Transfer transfer,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    _incomingController.add(transfer);
  }

  @override
  Stream<Transfer> get incomingTransfers => _incomingController.stream;

  @override
  Future<void> cancelIncomingTransfer(String transferId) async {
    // Implementation
  }

  @override
  void dispose() {
    stop();
  }
}

class TransportSelector {
  static final List<NearbyTransport> _transports = [];

  static void registerTransport(NearbyTransport transport) {
    _transports.add(transport);
  }

  static List<NearbyTransport> getAllTransports() => List.unmodifiable(_transports);

  static List<NearbyTransport> getAvailableTransports() {
    return _transports;
  }

  static NearbyTransport? getBestTransport({
    required PeerTransportType preferredType,
    required NearbyPeer peer,
  }) {
    for (final transport in _transports) {
      if (transport.transportType == preferredType) {
        return transport;
      }
    }
    return _transports.isNotEmpty ? _transports.first : null;
  }

  static Future<void> startAll() async {
    for (final transport in _transports) {
      await transport.start();
    }
  }

  static Future<void> stopAll() async {
    for (final transport in _transports) {
      await transport.stop();
    }
  }
}