import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../state/p2p_controller.dart';
import '../theme.dart';

/// Direct device-to-device transfer.
///
/// Peers appear as soon as they open this screen; sending opens a file
/// picker and streams the selection over a WebRTC data channel, so the bytes
/// never touch the server.
class P2PScreen extends ConsumerStatefulWidget {
  const P2PScreen({super.key});

  @override
  ConsumerState<P2PScreen> createState() => _P2PScreenState();
}

class _P2PScreenState extends ConsumerState<P2PScreen> {
  bool _picking = false;

  Future<void> _pickAndSend(P2PPeer peer) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;
      final controller = ref.read(p2pControllerProvider.notifier);
      for (final item in picked) {
        String? path;
        Uint8List? bytes;
        int size;
        final pickedPath = item.path;
        if (pickedPath != null) {
          path = pickedPath;
          size = await File(pickedPath).length();
        } else {
          bytes = await item.readAsBytes();
          size = bytes.length;
        }
        try {
          await controller.sendFile(
            peerId: peer.id,
            name: item.name,
            size: size,
            peerLabel: peer.user,
            path: path,
            bytes: bytes,
          );
        } catch (_) {
          // The failed transfer is already listed with its error attached.
        }
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _shareReceived(P2PTransfer transfer) async {
    final path = transfer.localPath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], title: transfer.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final p2p = ref.watch(p2pControllerProvider);
    final controller = ref.read(p2pControllerProvider.notifier);

    return Scaffold(
      backgroundColor: pal.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PEER TO PEER', style: SfsTextStyles.eyebrow(pal)),
                      const SizedBox(height: 6),
                      Text('Direct transfer', style: SfsTextStyles.title(pal)),
                      const SizedBox(height: 4),
                      Text(
                        'Send files straight to another device — nothing is '
                        'uploaded.',
                        style: TextStyle(color: pal.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ConnectionChip(
                  connected: p2p.connected,
                  peerId: p2p.peerId,
                  pal: pal,
                ),
              ],
            ),
            if (!p2p.connected) ...[
              const SizedBox(height: 16),
              _StatusRow(
                pal: pal,
                label: p2p.reconnecting ? 'Reconnecting…' : 'Connecting…',
              ),
            ],
            const SizedBox(height: 20),
            _panel(
              pal: pal,
              title: p2p.peers.length == 1
                  ? '1 PEER'
                  : '${p2p.peers.length} PEERS',
              child: p2p.peers.isEmpty
                  ? _emptyPeers(pal)
                  : Column(
                      children: [
                        for (final peer in p2p.peers)
                          _PeerRow(
                            peer: peer,
                            pal: pal,
                            enabled: p2p.connected && !_picking,
                            onSend: () => unawaited(_pickAndSend(peer)),
                          ),
                      ],
                    ),
            ),
            if (p2p.transfers.isNotEmpty) ...[
              const SizedBox(height: 20),
              _panel(
                pal: pal,
                title: 'TRANSFERS',
                child: Column(
                  children: [
                    for (final transfer in p2p.transfers)
                      _TransferRow(
                        transfer: transfer,
                        pal: pal,
                        onDismiss: () => controller.dismiss(transfer.id),
                        onShare:
                            transfer.direction ==
                                    P2PTransferDirection.receive &&
                                transfer.isComplete
                            ? () => unawaited(_shareReceived(transfer))
                            : null,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Center(child: Text('FILESHARE', style: SfsTextStyles.label(pal))),
          ],
        ),
      ),
    );
  }

  Widget _panel({
    required SfsPalette pal,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: pal.rule)),
            ),
            child: Text(title, style: SfsTextStyles.label(pal)),
          ),
          child,
        ],
      ),
    );
  }

  Widget _emptyPeers(SfsPalette pal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        children: [
          Icon(Icons.devices_other, size: 32, color: pal.muted),
          const SizedBox(height: 10),
          Text(
            'No other devices connected',
            style: TextStyle(color: pal.text, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Open this screen in another browser or on another phone to '
            'see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({
    required this.connected,
    required this.peerId,
    required this.pal,
  });

  final bool connected;
  final String? peerId;
  final SfsPalette pal;

  @override
  Widget build(BuildContext context) {
    final accent = connected ? pal.accent : pal.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: pal.surfaceOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: pal.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'Online' : 'Offline',
            style: TextStyle(color: pal.text, fontSize: 12),
          ),
          if (peerId != null) ...[
            const SizedBox(width: 6),
            Text(
              peerId!.substring(0, peerId!.length < 8 ? peerId!.length : 8),
              style: TextStyle(
                fontFamilyFallback: const <String>['monospace'],
                color: pal.muted,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.pal, required this.label});

  final SfsPalette pal;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pal.surfaceOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: pal.warn.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: pal.warn),
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: pal.text, fontSize: 13)),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.peer,
    required this.pal,
    required this.enabled,
    required this.onSend,
  });

  final P2PPeer peer;
  final SfsPalette pal;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final label = (peer.user != null && peer.user!.isNotEmpty)
        ? peer.user!
        : 'Anonymous';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pal.accentDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: pal.accent,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.text, fontSize: 14),
                ),
                Text(
                  peer.id.length > 12 ? peer.id.substring(0, 12) : peer.id,
                  style: TextStyle(
                    fontFamilyFallback: const <String>['monospace'],
                    color: pal.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.near_me_outlined, size: 14),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.transfer,
    required this.pal,
    required this.onDismiss,
    this.onShare,
  });

  final P2PTransfer transfer;
  final SfsPalette pal;
  final VoidCallback onDismiss;
  final VoidCallback? onShare;

  String get _statusLabel {
    switch (transfer.status) {
      case P2PTransferStatus.connecting:
        return 'Connecting…';
      case P2PTransferStatus.error:
        return transfer.error ?? 'Transfer failed';
      case P2PTransferStatus.done:
        return 'Done';
      case P2PTransferStatus.active:
        return '${(transfer.progress * 100).round()}%';
    }
  }

  @override
  Widget build(BuildContext context) {
    final barColor = switch (transfer.status) {
      P2PTransferStatus.error => pal.danger,
      P2PTransferStatus.done => pal.accent,
      _ => pal.accent,
    };
    final iconColor = transfer.direction == P2PTransferDirection.receive
        ? pal.accent
        : pal.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            transfer.direction == P2PTransferDirection.receive
                ? Icons.south_west
                : Icons.north_east,
            size: 16,
            color: iconColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transfer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.text, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${formatBytes(transfer.loaded)} / '
                      '${formatBytes(transfer.size)}',
                      style: TextStyle(
                        color: pal.muted,
                        fontSize: 11,
                        fontFeatures: const [],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: transfer.progress,
                          minHeight: 4,
                          backgroundColor: pal.surfaceOverlay,
                          color: barColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 84,
                      child: Text(
                        _statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: transfer.status == P2PTransferStatus.error
                              ? pal.danger
                              : pal.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (transfer.peerLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    (transfer.direction == P2PTransferDirection.receive
                            ? 'From '
                            : 'To ') +
                        transfer.peerLabel!,
                    style: TextStyle(color: pal.muted, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (onShare != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onShare,
              tooltip: 'Share',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.share, size: 16, color: pal.accent),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 16, color: pal.muted),
          ),
        ],
      ),
    );
  }
}
