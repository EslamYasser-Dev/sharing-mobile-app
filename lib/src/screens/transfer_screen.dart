import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/transfer.dart';
import '../state/transfer_controller.dart';
import '../theme.dart';

class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // No polling timer: live numbers are driven by progress-tick rebuilds of
    // the meter widgets, which subscribe to single entries via select.
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    // Structure-only subscription: ids, statuses, names, and sizes. Byte
    // ticks and 1 Hz list refreshes share this fingerprint, so the list
    // rebuilds only when membership or status actually changes; meters
    // inside the cards subscribe to single progress entries via select.
    ref.watch(
      transferControllerProvider.select(
        (l) => l
            .map((t) => '${t.id}:${t.status.index}:${t.size}:${t.name}')
            .join('|'),
      ),
    );
    final transfers = ref.read(transferControllerProvider);

    final uploads = transfers.where((t) => t.direction == TransferDirection.upload).toList();
    final downloads = transfers.where((t) => t.direction == TransferDirection.download).toList();
    final p2pTransfers = transfers.where((t) =>
        t.direction == TransferDirection.p2pSend || t.direction == TransferDirection.p2pReceive).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Transfers', style: SfsTextStyles.title(pal)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: pal.accent,
          labelColor: pal.accent,
          unselectedLabelColor: pal.muted,
          tabs: [
            Tab(text: 'Uploads ${uploads.length}'),
            Tab(text: 'Downloads ${downloads.length}'),
            Tab(text: 'Direct ${p2pTransfers.length}'),
          ],
        ),
      ),
      body: Column(
        children: [
          _AggregateBar(pal: pal),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTransferList(pal, uploads, TransferDirection.upload),
                _buildTransferList(pal, downloads, TransferDirection.download),
                _buildTransferList(pal, p2pTransfers, TransferDirection.p2pSend),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(pal),
    );
  }

  Widget _buildTransferList(SfsPalette pal, List<Transfer> transfers, TransferDirection filter) {
    if (transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filter == TransferDirection.upload
                  ? Icons.cloud_upload_outlined
                  : filter == TransferDirection.download
                      ? Icons.cloud_download_outlined
                      : Icons.devices_other,
              size: 48,
              color: pal.muted,
            ),
            const SizedBox(height: 16),
            Text(
              'No ${filter.name}s',
              style: TextStyle(color: pal.muted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to start a new transfer',
              style: TextStyle(color: pal.muted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transfers.length,
      itemBuilder: (context, index) {
        final transfer = transfers[index];
        return _TransferCard(
          transfer: transfer,
          pal: pal,
          onPause: transfer.canPause ? () => ref.read(transferControllerProvider.notifier).pauseTransfer(transfer.id) : null,
          onResume: transfer.canResume ? () => ref.read(transferControllerProvider.notifier).resumeTransfer(transfer.id) : null,
          onCancel: transfer.canCancel ? () => ref.read(transferControllerProvider.notifier).cancelTransfer(transfer.id) : null,
          onRetry: transfer.canRetry ? () => ref.read(transferControllerProvider.notifier).retryTransfer(transfer.id) : null,
        );
      },
    );
  }

  Widget _buildBottomBar(SfsPalette pal) {
    final controller = ref.read(transferControllerProvider.notifier);
    // Count-only subscriptions: progress ticks must not rebuild the bar.
    final activeCount = ref.watch(
      transferControllerProvider.select(
        (s) => s.where((t) => t.isActive).length,
      ),
    );
    final pausedCount = ref.watch(
      transferControllerProvider.select(
        (s) => s.where((t) => t.status == TransferStatus.paused).length,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SfsGlass.of(pal).tint,
        border: Border(top: BorderSide(color: pal.border)),
      ),
      child: Row(
        children: [
          if (activeCount > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.pauseAll,
                icon: Icon(Icons.pause_circle_outline, color: pal.accent, size: 18),
                label: Text('Pause All ($activeCount)', style: TextStyle(color: pal.accent)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: pal.accent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (pausedCount > 0) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.resumeAll,
                icon: Icon(Icons.play_circle_outline, color: pal.onAccent, size: 18),
                label: Text('Resume All ($pausedCount)'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (activeCount == 0 && pausedCount == 0)
            Expanded(
              child: Text(
                'No active transfers',
                style: TextStyle(color: pal.muted),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

/// Aggregate strip: total up/down + active/queued counts. Watches the
/// progress map (not the list) so live speeds tick without rebuilding rows.
class _AggregateBar extends ConsumerWidget {
  const _AggregateBar({required this.pal});

  final SfsPalette pal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Any byte tick refreshes this tiny strip; rows are unaffected.
    ref.watch(transferProgressProvider);
    final stats = ref.read(transferControllerProvider.notifier).stats();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: SfsDecor.hero(pal),
      child: Row(
        children: [
          Expanded(
            child: _AggregateStat(
              pal: pal,
              icon: Icons.cloud_upload_outlined,
              label: 'Up',
              value: '${formatBytes(stats.uploadSpeed.toInt())}/s',
            ),
          ),
          Expanded(
            child: _AggregateStat(
              pal: pal,
              icon: Icons.cloud_download_outlined,
              label: 'Down',
              value: '${formatBytes(stats.downloadSpeed.toInt())}/s',
            ),
          ),
          Expanded(
            child: _AggregateStat(
              pal: pal,
              icon: Icons.sync,
              label: 'Active',
              value: '${stats.activeCount}',
            ),
          ),
          Expanded(
            child: _AggregateStat(
              pal: pal,
              icon: Icons.schedule,
              label: 'Queued',
              value: '${stats.queuedCount}',
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregateStat extends StatelessWidget {
  const _AggregateStat({
    required this.pal,
    required this.icon,
    required this.label,
    required this.value,
  });

  final SfsPalette pal;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: pal.accent),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: pal.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: pal.muted,
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends ConsumerWidget {
  const _TransferCard({
    required this.transfer,
    required this.pal,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
  });

  final Transfer transfer;
  final SfsPalette pal;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      label: '${transfer.name}, ${transfer.status.name}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: SfsDecor.liveCard(
          pal,
          failed: transfer.status == TransferStatus.failed,
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIcon(pal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            transfer.name,
                            style: TextStyle(
                              color: pal.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildStatusChip(pal),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          transfer.direction == TransferDirection.upload
                              ? Icons.cloud_upload
                              : transfer.direction == TransferDirection.download
                                  ? Icons.cloud_download
                                  : Icons.devices_other,
                          size: 12,
                          color: pal.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getDirectionLabel(),
                          style: TextStyle(color: pal.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.more_vert, color: pal.muted, size: 20),
                onPressed: () => _showActions(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Bytes tick at 5 Hz but only this meter rebuilds: it subscribes
          // to the single progress entry via select.
          _TransferMeter(transfer: transfer, pal: pal),
          const SizedBox(height: 12),
          _buildActionButtons(),
        ],
        ),
      ),
    );
    }

  Widget _buildStatusIcon(SfsPalette pal) {
    IconData icon;
    Color color;

    switch (transfer.status) {
      case TransferStatus.queued:
        icon = Icons.schedule;
        color = pal.muted;
        break;
      case TransferStatus.preparing:
        icon = Icons.hourglass_empty;
        color = pal.warn;
        break;
      case TransferStatus.connecting:
        icon = Icons.sync;
        color = pal.accent;
        break;
      case TransferStatus.transferring:
        icon = Icons.sync;
        color = pal.accent;
        break;
      case TransferStatus.paused:
        icon = Icons.pause_circle;
        color = pal.warn;
        break;
      case TransferStatus.resuming:
        icon = Icons.play_circle;
        color = pal.accent;
        break;
      case TransferStatus.verifying:
        icon = Icons.verified;
        color = pal.accent;
        break;
      case TransferStatus.completed:
        icon = Icons.check_circle;
        color = pal.accent;
        break;
      case TransferStatus.failed:
        icon = Icons.error;
        color = pal.danger;
        break;
      case TransferStatus.cancelled:
        icon = Icons.cancel;
        color = pal.muted;
        break;
      case TransferStatus.retrying:
        icon = Icons.refresh;
        color = pal.warn;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildStatusChip(SfsPalette pal) {
    String label;
    Color color;

    switch (transfer.status) {
      case TransferStatus.queued:
        label = 'QUEUED';
        color = pal.muted;
        break;
      case TransferStatus.preparing:
        label = 'PREPARING';
        color = pal.warn;
        break;
      case TransferStatus.connecting:
        label = 'CONNECTING';
        color = pal.accent;
        break;
      case TransferStatus.transferring:
        label = 'TRANSFERRING';
        color = pal.accent;
        break;
      case TransferStatus.paused:
        label = 'PAUSED';
        color = pal.warn;
        break;
      case TransferStatus.resuming:
        label = 'RESUMING';
        color = pal.accent;
        break;
      case TransferStatus.verifying:
        label = 'VERIFYING';
        color = pal.accent;
        break;
      case TransferStatus.completed:
        label = 'COMPLETED';
        color = pal.accent;
        break;
      case TransferStatus.failed:
        label = 'FAILED';
        color = pal.danger;
        break;
      case TransferStatus.cancelled:
        label = 'CANCELLED';
        color = pal.muted;
        break;
      case TransferStatus.retrying:
        label = 'RETRYING';
        color = pal.warn;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _getDirectionLabel() {
    switch (transfer.direction) {
      case TransferDirection.upload:
        return 'UPLOAD';
      case TransferDirection.download:
        return 'DOWNLOAD';
      case TransferDirection.p2pSend:
        return 'P2P SEND';
      case TransferDirection.p2pReceive:
        return 'P2P RECEIVE';
    }
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (onPause != null)
          TextButton.icon(
            onPressed: onPause,
            icon: const Icon(Icons.pause, size: 16),
            label: const Text('Pause'),
            style: TextButton.styleFrom(foregroundColor: pal.warn),
          ),
        if (onResume != null)
          TextButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Resume'),
            style: TextButton.styleFrom(foregroundColor: pal.accent),
          ),
        if (onCancel != null)
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.cancel, size: 16),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(foregroundColor: pal.muted),
          ),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: pal.accent),
          ),
      ],
    );
  }

  void _showActions() {
    // TODO: Show full action sheet
  }
}

/// Live progress meter for a transfer card. Watches only this transfer's byte
/// counter, so 5 Hz ticks rebuild this meter alone — never the card or list.
class _TransferMeter extends ConsumerWidget {
  const _TransferMeter({required this.transfer, required this.pal});

  final Transfer transfer;
  final SfsPalette pal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(
      transferProgressProvider.select((m) => m[transfer.id]),
    );
    final done = (bytes ?? transfer.bytesTransferred).clamp(0, transfer.size);
    final pct = transfer.size <= 0
        ? (transfer.status == TransferStatus.completed ? 100 : 0)
        : (done * 100 / transfer.size).round().clamp(0, 100);
    final speedCalc = ref
        .read(transferControllerProvider.notifier)
        .getSpeedCalculator(transfer.id);
    final speed = speedCalc?.getSmoothedSpeed(DateTime.now()) ?? 0.0;
    final eta = speedCalc?.estimateRemaining(done, transfer.size, DateTime.now());

    return Semantics(
      label: '${transfer.name}, $pct percent complete',
      value: '$pct%',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: transfer.size <= 0 ? null : done / transfer.size,
              minHeight: 6,
              backgroundColor: pal.surfaceOverlay,
              valueColor: AlwaysStoppedAnimation<Color>(
                _progressColor(transfer.status),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${formatBytes(done)} / ${formatBytes(transfer.size)}',
                style: TextStyle(
                  color: pal.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              if (speed > 0)
                Text(
                  '${formatBytes(speed.toInt())}/s',
                  style: TextStyle(
                    color: pal.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const Spacer(),
              if (eta != null)
                Text(
                  'ETA: ${_formatDuration(eta)}',
                  style: TextStyle(color: pal.muted, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _progressColor(TransferStatus status) {
    switch (status) {
      case TransferStatus.completed:
        return pal.accent;
      case TransferStatus.failed:
        return pal.danger;
      case TransferStatus.paused:
        return pal.warn;
      default:
        return pal.accent;
    }
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}