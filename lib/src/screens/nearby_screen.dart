import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/peer.dart';
import '../state/auth_controller.dart';
import '../state/nearby_controller.dart';
import '../state/nearby_enabled_controller.dart';
import '../theme.dart';

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final nearby = ref.watch(nearbyControllerProvider);
    final controller = ref.read(nearbyControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(pal, auth, nearby, controller)),
            SliverToBoxAdapter(child: _buildEnabledBanner(pal)),
            SliverToBoxAdapter(child: _buildDiscoverabilitySection(pal, nearby, controller)),
            SliverToBoxAdapter(child: _buildActionButtons(pal, nearby, controller)),
            SliverToBoxAdapter(child: _buildPeersList(pal, nearby, controller)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SfsPalette pal, AuthState auth, NearbyState nearby, NearbyController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: pal.text),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text('Nearby', style: SfsTextStyles.title(pal)),
          ),
          IconButton(
            icon: Icon(
              nearby.isScanning ? Icons.radar : Icons.radar_outlined,
              color: nearby.isScanning ? pal.accent : pal.muted,
            ),
            onPressed: nearby.isScanning
                ? () => controller.stopScanning()
                : () => controller.startScanning(),
          ),
        ],
      ),
    );
  }

  Widget _buildEnabledBanner(SfsPalette pal) {
    final enabled = ref.watch(nearbyEnabledProvider);
    if (enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SfsGlass.of(pal).tint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SfsGlass.of(pal).border),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_outlined, color: pal.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nearby sharing is off. Turn it on to discover devices.',
                style: TextStyle(color: pal.muted, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(nearbyEnabledProvider.notifier).set(true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverabilitySection(SfsPalette pal, NearbyState nearby, NearbyController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VISIBILITY', style: SfsTextStyles.eyebrow(pal)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SfsGlass.of(pal).tint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SfsGlass.of(pal).border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.visibility, color: pal.accent, size: 20),
                    const SizedBox(width: 12),
                    Text('Who can discover you', style: SfsTextStyles.title(pal).copyWith(fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose who can see your device on the local network',
                  style: TextStyle(color: pal.muted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
                _DiscoverabilitySelector(
                  currentMode: nearby.discoverability,
                  onChanged: (mode) => controller.setDiscoverability(mode),
                  pal: pal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(SfsPalette pal, NearbyState nearby, NearbyController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showQrCodeDialog(pal, controller),
              icon: Icon(Icons.qr_code, size: 18, color: pal.accent),
              label: Text('My QR Code', style: TextStyle(color: pal.accent)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: pal.accent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showScanQrDialog(pal, controller),
              icon: Icon(Icons.key_outlined, size: 18, color: pal.accent),
              label: Text('Enter code', style: TextStyle(color: pal.accent)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: pal.accent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeersList(SfsPalette pal, NearbyState nearby, NearbyController controller) {
    if (nearby.discoveredPeers.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.radar_outlined, size: 48, color: pal.muted),
              const SizedBox(height: 16),
              Text(
                nearby.isScanning ? 'Scanning for devices...' : 'No nearby devices found',
                style: TextStyle(color: pal.muted, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pull down to refresh or tap the radar icon to start scanning',
                style: TextStyle(color: pal.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final peer = nearby.discoveredPeers[index];
            return _PeerTile(
              peer: peer,
              pal: pal,
              onTap: () => _showPeerActions(pal, peer, controller),
              onSendFile: () => _sendFileToPeer(pal, peer, controller),
            );
          },
          childCount: nearby.discoveredPeers.length,
        ),
      );
    }
  }

  void _showQrCodeDialog(SfsPalette pal, NearbyController controller) {
    final qrCode = controller.generatePairingQrCode();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SfsPalette.of(context).card,
        title: Text('Your QR Code', style: SfsTextStyles.title(SfsPalette.of(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this QR code with another device to pair securely',
              style: TextStyle(color: SfsPalette.of(context).muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                size: const Size(200, 200),
                painter: _QrCodePainter(qrCode),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Device: ${ref.read(authControllerProvider).user?.username ?? 'Unknown'}',
              style: TextStyle(color: SfsPalette.of(context).muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: SfsPalette.of(context).accent)),
          ),
          FilledButton.icon(
            onPressed: () async {
              await SharePlus.instance.share(ShareParams(text: qrCode));
              Navigator.pop(context);
            },
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  /// Manual pairing-code entry.
  ///
  /// The abandoned `qr_code_scanner` native plugin breaks the Android build
  /// (missing namespace, JVM mismatch with AGP 9), so camera scanning is
  /// replaced with a manual short-lived pairing-code flow: the other device
  /// shows its code via "My QR Code" → Share, and it is pasted here.
  /// The code is verified (signature + 5-minute expiry) before pairing.
  void _showScanQrDialog(SfsPalette pal, NearbyController controller) {
    final codeController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SfsPalette.of(context).card,
        title: Text('Enter pairing code', style: SfsTextStyles.title(SfsPalette.of(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask the other device to open Nearby → My QR Code → Share, then paste the pairing code here.',
              style: TextStyle(color: SfsPalette.of(context).muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Paste pairing code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: SfsPalette.of(context).accent)),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text.trim();
              Navigator.pop(context);
              if (code.isEmpty) return;
              _handleScannedQrCode(SfsPalette.of(context), controller, code);
            },
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }

  void _handleScannedQrCode(SfsPalette pal, NearbyController controller, String qrData) {
    final result = controller.processScannedQrCode(qrData);
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully paired with ${result.payload!.displayName}'),
          backgroundColor: pal.accent,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to pair'),
          backgroundColor: pal.danger,
        ),
      );
    }
  }

  void _showPeerActions(SfsPalette pal, NearbyPeer peer, NearbyController controller) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: SfsPalette.of(context).card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: SfsPalette.of(context).muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: SfsPalette.of(context).accentDim,
                child: Text(
                  peer.displayName.substring(0, 1).toUpperCase(),
                  style: TextStyle(color: SfsPalette.of(context).accent, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(peer.displayName, style: TextStyle(color: SfsPalette.of(context).text, fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${peer.deviceName ?? 'Unknown device'} • ${peer.transportType.name.toUpperCase()}',
                style: TextStyle(color: SfsPalette.of(context).muted, fontSize: 12),
              ),
            ),
            Divider(height: 1, color: SfsPalette.of(context).rule),
            if (!peer.isTrusted)
              ListTile(
                leading: Icon(Icons.check_circle_outline, color: SfsPalette.of(context).accent),
                title: Text('Trust Device', style: TextStyle(color: SfsPalette.of(context).accent)),
                onTap: () {
                  Navigator.pop(context);
                  controller.trustPeer(peer.id);
                },
              ),
            if (peer.isTrusted)
              ListTile(
                leading: Icon(Icons.check_circle, color: SfsPalette.of(context).accent),
                title: Text('Trusted Device', style: TextStyle(color: SfsPalette.of(context).accent)),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text('Untrust', style: TextStyle(color: SfsPalette.of(context).danger)),
                ),
              ),
            if (!peer.isBlocked)
              ListTile(
                leading: Icon(Icons.block_outlined, color: SfsPalette.of(context).danger),
                title: Text('Block Device', style: TextStyle(color: SfsPalette.of(context).danger)),
                onTap: () {
                  Navigator.pop(context);
                  controller.blockPeer(peer.id);
                },
              ),
            if (peer.isBlocked)
              ListTile(
                leading: Icon(Icons.block, color: SfsPalette.of(context).danger),
                title: Text('Blocked', style: TextStyle(color: SfsPalette.of(context).danger)),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    controller.unblockPeer(peer.id);
                  },
                  child: Text('Unblock', style: TextStyle(color: SfsPalette.of(context).accent)),
                ),
              ),
            ListTile(
              leading: Icon(Icons.send_outlined, color: SfsPalette.of(context).accent),
              title: Text('Send File', style: TextStyle(color: SfsPalette.of(context).accent)),
              onTap: () {
                Navigator.pop(context);
                _sendFileToPeer(pal, peer, controller);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFileToPeer(SfsPalette pal, NearbyPeer peer, NearbyController controller) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('File sending to ${peer.displayName} - integrate with file picker'),
        backgroundColor: pal.accent,
      ),
    );
  }
}

class _DiscoverabilitySelector extends StatelessWidget {
  const _DiscoverabilitySelector({
    required this.currentMode,
    required this.onChanged,
    required this.pal,
  });

  final DiscoverabilityMode currentMode;
  final ValueChanged<DiscoverabilityMode> onChanged;
  final SfsPalette pal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: DiscoverabilityMode.values.map((mode) {
        return RadioListTile<DiscoverabilityMode>(
          value: mode,
          groupValue: currentMode,
          onChanged: (value) => onChanged(value!),
          title: Text(
            _getModeLabel(mode),
            style: TextStyle(color: pal.text, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            _getModeDescription(mode),
            style: TextStyle(color: pal.muted, fontSize: 12),
          ),
          activeColor: pal.accent,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
      }).toList(),
    );
  }

  String _getModeLabel(DiscoverabilityMode mode) {
    switch (mode) {
      case DiscoverabilityMode.everyone:
        return 'Everyone';
      case DiscoverabilityMode.contacts:
        return 'Contacts Only';
      case DiscoverabilityMode.hidden:
        return 'Hidden';
    }
  }

  String _getModeDescription(DiscoverabilityMode mode) {
    switch (mode) {
      case DiscoverabilityMode.everyone:
        return 'Visible to all nearby devices on the network';
      case DiscoverabilityMode.contacts:
        return 'Only visible to approved/trusted contacts';
      case DiscoverabilityMode.hidden:
        return 'Not discoverable by other devices';
    }
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.pal,
    required this.onTap,
    required this.onSendFile,
  });

  final NearbyPeer peer;
  final SfsPalette pal;
  final VoidCallback onTap;
  final VoidCallback onSendFile;

  @override
  Widget build(BuildContext context) {
    final isTrusted = peer.isTrusted;
    final isBlocked = peer.isBlocked;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: SfsGlass.of(pal).tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBlocked ? pal.dangerBorder : (isTrusted ? pal.accentBorder : pal.border),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: isBlocked ? pal.dangerBorder : (isTrusted ? pal.accentDim : pal.accentDim),
                child: Text(
                  peer.displayName.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: isBlocked ? pal.danger : (isTrusted ? pal.accent : pal.accent),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          peer.displayName,
                          style: TextStyle(
                            color: pal.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (peer.isTrusted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: pal.accentDim,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'TRUSTED',
                              style: TextStyle(
                                color: pal.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (peer.isBlocked)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: pal.dangerBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'BLOCKED',
                              style: TextStyle(
                                color: pal.danger,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      peer.deviceName ?? 'Unknown device',
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          peer.transportType == PeerTransportType.lan
                              ? Icons.wifi
                              : Icons.bluetooth,
                          size: 12,
                          color: pal.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          peer.transportType.name.toUpperCase(),
                          style: TextStyle(
                            color: pal.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          peer.status == PeerStatus.online
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: 8,
                          color: peer.status == PeerStatus.online ? Colors.green : pal.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          peer.status.name.toUpperCase(),
                          style: TextStyle(
                            color: peer.status == PeerStatus.online ? Colors.green : pal.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.send_outlined, color: pal.accent, size: 20),
                onPressed: () {},
                tooltip: 'Send file',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  final String qrData;
  _QrCodePainter(this.qrData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final cellSize = size.width / 25;
    final random = Random(qrData.hashCode);

    for (int y = 0; y < 25; y++) {
      for (int x = 0; x < 25; x++) {
        if (random.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }

    final borderPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}