import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../models/transfer.dart';
import '../services/mdns_discovery.dart';
import '../services/nearby_transport.dart';
import '../services/pairing.dart';
import '../services/transfer_manager.dart';
import '../state/auth_controller.dart';
import 'nearby_enabled_controller.dart';

final mdnsDiscoveryProvider = Provider<MdnsDiscoveryService>((ref) {
  final service = MdnsDiscoveryService();
  ref.onDispose(service.dispose);
  return service;
});

final lanTransportProvider = Provider<LanTransport>((ref) {
  final auth = ref.read(authControllerProvider);
  final discovery = ref.read(mdnsDiscoveryProvider);
  final transport = LanTransport(
    discoveryService: discovery,
    localPeerId: auth.user?.username ?? 'anonymous',
    deviceName: 'Flutter Device',
    displayName: auth.user?.username,
  );
  ref.onDispose(transport.dispose);
  return transport;
});

final bluetoothTransportProvider = Provider<BluetoothTransport>((ref) {
  final auth = ref.read(authControllerProvider);
  final transport = BluetoothTransport(localPeerId: auth.user?.username ?? 'anonymous');
  ref.onDispose(transport.dispose);
  return transport;
});

final nearbyTransportSelectorProvider = Provider<TransportSelector>((ref) {
  // TransportSelector uses static methods, so we just provide a dummy instance
  return TransportSelector();
});

final pairingServiceProvider = Provider<PairingService>((ref) => PairingService());

final peerRepositoryProvider = Provider<PeerRepository>((ref) => PeerRepository.instance);

class NearbyState {
  const NearbyState({
    this.discoverability = DiscoverabilityMode.everyone,
    this.discoveredPeers = const [],
    this.pairingStates = const {},
    this.isScanning = false,
    this.error,
  });

  final DiscoverabilityMode discoverability;
  final List<NearbyPeer> discoveredPeers;
  final Map<String, PairingState> pairingStates;
  final bool isScanning;
  final String? error;

  NearbyState copyWith({
    DiscoverabilityMode? discoverability,
    List<NearbyPeer>? discoveredPeers,
    Map<String, PairingState>? pairingStates,
    bool? isScanning,
    String? error,
  }) {
    return NearbyState(
      discoverability: discoverability ?? this.discoverability,
      discoveredPeers: discoveredPeers ?? this.discoveredPeers,
      pairingStates: pairingStates ?? this.pairingStates,
      isScanning: isScanning ?? this.isScanning,
      error: error ?? this.error,
    );
  }
}

class NearbyController extends Notifier<NearbyState> {
  StreamSubscription<NearbyPeer>? _peerSubscription;
  PairingSession? _pairingSession;

  @override
  NearbyState build() {
    ref.onDispose(_cleanup);
    // Master switch: turning nearby off stops discovery immediately, even
    // mid-scan. Restarting requires the switch (startScanning re-checks).
    ref.listen<bool>(nearbyEnabledProvider, (_, enabled) {
      if (!enabled) unawaited(stopScanning());
    });
    return const NearbyState();
  }

  void _cleanup() {
    _peerSubscription?.cancel();
    _pairingSession = null;
  }

  Future<void> startScanning() async {
    if (!ref.read(nearbyEnabledProvider)) {
      state = state.copyWith(
        isScanning: false,
        error: 'Nearby sharing is turned off',
      );
      return;
    }
    state = state.copyWith(isScanning: true, error: null);

    try {
      final auth = ref.read(authControllerProvider);
      if (auth.user == null) {
        state = state.copyWith(isScanning: false, error: 'Not signed in');
        return;
      }

      await TransportSelector.startAll();

      _peerSubscription = ref.read(lanTransportProvider).discoveredPeers.listen((peer) {
        _updatePeer(peer);
      });
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  Future<void> stopScanning() async {
    await TransportSelector.stopAll();
    _peerSubscription?.cancel();
    _peerSubscription = null;
    state = state.copyWith(isScanning: false);
  }

  Future<void> setDiscoverability(DiscoverabilityMode mode) async {
    state = state.copyWith(discoverability: mode);

    final auth = ref.read(authControllerProvider);
    if (auth.user == null) return;

    // Update mDNS TXT record with new discoverability
    final discovery = ref.read(mdnsDiscoveryProvider);
    await discovery.updateTxtRecord({
      'discoverability': mode.name,
    });
  }

  void _updatePeer(NearbyPeer peer) {
    final repo = ref.read(peerRepositoryProvider);
    repo.updatePeer(peer);

    final peers = repo.allPeers;
    state = state.copyWith(discoveredPeers: peers);
  }

  Future<void> trustPeer(String peerId) async {
    final repo = ref.read(peerRepositoryProvider);
    repo.markPeerTrusted(peerId, trusted: true);
    _refreshPeers();
  }

  Future<void> blockPeer(String peerId) async {
    final repo = ref.read(peerRepositoryProvider);
    repo.markPeerBlocked(peerId, blocked: true);
    _refreshPeers();
  }

  Future<void> unblockPeer(String peerId) async {
    final repo = ref.read(peerRepositoryProvider);
    repo.markPeerBlocked(peerId, blocked: false);
    _refreshPeers();
  }

  void _refreshPeers() {
    final repo = ref.read(peerRepositoryProvider);
    state = state.copyWith(discoveredPeers: repo.allPeers);
  }

  String generatePairingQrCode() {
    final auth = ref.read(authControllerProvider);
    if (auth.user == null) throw StateError('Not signed in');

    final keyPair = PairingService.generateKeyPair();

    _pairingSession = PairingSession(
      ourId: auth.user!.username,
      ourKeyPair: keyPair,
      onPairingComplete: (peerId, sharedSecret) {
        // Store shared secret for encrypted communication
        final repo = ref.read(peerRepositoryProvider);
        final peer = repo.getPeer(peerId);
        if (peer != null) {
          repo.updatePeer(peer.copyWith(pairingState: PairingState.paired));
        }
      },
    );

    return _pairingSession!.generateOurQrCode(displayName: auth.user!.username);
  }

  PairingResult processScannedQrCode(String qrData) {
    if (_pairingSession == null) {
      return PairingResult.error('No active pairing session');
    }
    return _pairingSession!.processScannedQrCode(qrData);
  }

  Future<void> sendFileToPeer({
    required String peerId,
    required String filePath,
    required String fileName,
    required int fileSize,
    void Function(int sent, int total)? onProgress,
  }) async {
    final repo = ref.read(peerRepositoryProvider);
    final peer = repo.getPeer(peerId);
    if (peer == null) throw StateError('Peer not found');

    if (peer.isBlocked) throw StateError('Peer is blocked');

    final auth = ref.read(authControllerProvider);
    if (auth.user == null) throw StateError('Not signed in');

    final file = File(filePath);
    if (!await file.exists()) throw StateError('File not found');

    final transferManager = TransferManager.instance;
    final transfer = Transfer(
      id: 'p2p-${DateTime.now().millisecondsSinceEpoch}',
      fileId: 'p2p-$peerId-$fileName',
      name: fileName,
      size: fileSize,
      direction: TransferDirection.p2pSend,
      status: TransferStatus.queued,
      remotePeerId: peer.id,
      remotePeerName: peer.displayName,
      localPath: filePath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      transport: TransferTransportType.webrtc,
    );

    await transferManager.addTransfer(transfer);

    final selector = TransportSelector.getBestTransport(
      preferredType: peer.transportType,
      peer: peer,
    );

    if (selector == null) {
      throw StateError('No available transport for peer');
    }

    await selector.sendFile(
      peer: peer,
      transfer: transfer,
      file: file,
      onProgress: onProgress,
    );
  }

  void dispose() {
    _peerSubscription?.cancel();
    _pairingSession = null;
  }
}

final nearbyControllerProvider = NotifierProvider<NearbyController, NearbyState>(
  NearbyController.new,
);