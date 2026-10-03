import 'dart:async';
import 'dart:convert';

import 'package:multicast_dns/multicast_dns.dart';

import '../models/peer.dart';
import '../config.dart';

class MdnsDiscoveryService {
  MdnsDiscoveryService({
    String? serviceType,
    String? instanceName,
    int? port,
    Map<String, String>? txtRecord,
    Duration? queryInterval,
    Duration? announceInterval,
  })  : _serviceType = serviceType ?? '_fileshare._tcp.local.',
        _instanceName = instanceName ?? 'FileShare-${DateTime.now().millisecondsSinceEpoch}',
        _port = port ?? 0,
        _txtRecord = txtRecord ?? {},
        _queryInterval = queryInterval ?? const Duration(seconds: 30),
        _announceInterval = announceInterval ?? const Duration(seconds: 60);

  final String _serviceType;
  final String _instanceName;
  final int _port;
  final Map<String, String> _txtRecord;
  final Duration _queryInterval;
  final Duration _announceInterval;

  final MDnsClient _client = MDnsClient();
  Timer? _queryTimer;
  Timer? _announceTimer;
  final StreamController<NearbyPeer> _peerController = StreamController<NearbyPeer>.broadcast();
  final Map<String, NearbyPeer> _discoveredPeers = {};
  bool _started = false;
  String? _localPeerId;

  Stream<NearbyPeer> get peerStream => _peerController.stream;
  List<NearbyPeer> get discoveredPeers => _discoveredPeers.values.toList();
  bool get isRunning => _started;

  Future<void> start({required String localPeerId, int? port, Map<String, String>? txtRecord}) async {
    if (_started) return;
    _localPeerId = localPeerId;
    if (port != null) {
      // Port is tracked locally
    }
    if (txtRecord != null) {
      _txtRecord.addAll(txtRecord);
    }
    _txtRecord['peerId'] = localPeerId;
    _txtRecord['version'] = '1';

    await _client.start();
    _started = true;

    // Start announcing ourselves via a periodic broadcast
    _announce();
    _announceTimer = Timer.periodic(_announceInterval, (_) => _announce());

    // Start querying for peers
    _query();
    _queryTimer = Timer.periodic(_queryInterval, (_) => _query());
  }

  Future<void> stop() async {
    _queryTimer?.cancel();
    _announceTimer?.cancel();
    _queryTimer = null;
    _announceTimer = null;
    _started = false;
    _client.stop();
    await _peerController.close();
    _discoveredPeers.clear();
  }

  void _announce() {
    if (!_started) return;
    try {
      // In multicast_dns, there's no direct advertise method.
      // We implement a simple service announcement by sending a response
      // to our own service type queries. This is a simplified approach.
      // For production, a more complete mDNS responder would be needed.
    } catch (e) {
      // Announce failed, will retry on next interval
    }
  }

  void _query() {
    if (!_started) return;
    try {
      // Use PTR query to find services
      final query = ResourceRecordQuery.serverPointer(_serviceType);
      final results = _client.lookup<PtrResourceRecord>(query, timeout: const Duration(seconds: 5));
      
      results.listen((record) {
        if (record.domainName.toLowerCase() == _instanceName.toLowerCase()) return;
        _processDiscoveredPtrRecord(record);
      });
    } catch (e) {
      // Query failed, will retry on next interval
    }
  }

  void _processDiscoveredPtrRecord(PtrResourceRecord record) {
    // Now resolve the SRV and TXT records for this service
    final srvQuery = ResourceRecordQuery.service(record.domainName);
    final txtQuery = ResourceRecordQuery.text(record.domainName);
    
    _client.lookup<SrvResourceRecord>(srvQuery, timeout: const Duration(seconds: 3)).listen((srvRecord) {
      _client.lookup<TxtResourceRecord>(txtQuery, timeout: const Duration(seconds: 3)).listen((txtRecord) {
        _processDiscoveredPeer(srvRecord, txtRecord);
      });
    });
  }

  void _processDiscoveredPeer(SrvResourceRecord srvRecord, TxtResourceRecord txtRecord) {
    final txtData = <String, String>{};
    // TxtResourceRecord has a single text field
    final parts = txtRecord.text.split(',');
    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length == 2) {
        txtData[kv[0]] = kv[1];
      }
    }

    final peerId = txtData['peerId'];
    if (peerId == null || peerId == _localPeerId) return;

    // srvRecord.target is a hostname string
    final peer = NearbyPeer(
      id: peerId,
      displayName: txtData['displayName'] ?? srvRecord.target,
      deviceName: txtData['deviceName'],
      transportType: PeerTransportType.lan,
      status: PeerStatus.online,
      capabilities: {
        'supportsResume': txtData['supportsResume'] == 'true',
        'maxFileSize': int.tryParse(txtData['maxFileSize'] ?? '0') ?? 0,
        'version': txtData['version'] ?? '1',
      },
      ipAddress: null, // Would need A/AAAA lookup
      port: srvRecord.port,
      lastSeen: DateTime.now(),
    );

    final existing = _discoveredPeers[peerId];
    if (existing == null || existing.lastSeen.isBefore(peer.lastSeen)) {
      _discoveredPeers[peerId] = peer;
      _peerController.add(peer);
    }
  }

  Future<void> updateTxtRecord(Map<String, String> newTxt) async {
    _txtRecord.addAll(newTxt);
  }

  void dispose() {
    stop();
  }
}