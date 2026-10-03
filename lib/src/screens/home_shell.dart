import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/transfer.dart';
import '../state/transfer_controller.dart';
import '../theme.dart';
import 'account_screen.dart';
import 'files_screen.dart';
import 'p2p_screen.dart';
import 'shares_screen.dart';
import 'timeline_screen.dart';
import 'transfer_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void _openTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    // Count-only subscription: the shell (and its whole IndexedStack) must
    // not rebuild on progress ticks — the pill meters those separately.
    final activeCount = ref.watch(
      transferControllerProvider.select(
        (transfers) => transfers.where((t) => t.isActive).length,
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              FilesScreen(
                onOpenShares: () => _openTab(1),
                onOpenTransfers: () => _openTab(2),
              ),
              const SharesScreen(),
              const TransferScreen(),
              const TimelineScreen(),
              const P2PScreen(),
              const AccountScreen(),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 84,
            child: _TransferPill(
              onOpen: () => _openTab(2),
            ),
          ),
        ],
      ),
      // Hairline rule above the bar, the way the landing separates its
      // header from the page.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: pal.rule)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              label: 'Files',
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.link), label: 'Shares'),
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.swap_vert_circle_outlined),
                  if (activeCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Semantics(
                        label: '$activeCount active transfers',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: SfsPalette.of(context).accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$activeCount',
                            style: TextStyle(
                              color: SfsPalette.of(context).onAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Transfers',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.dynamic_feed_outlined),
              label: 'Timeline',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.devices_other),
              label: 'Direct',
            ),            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating live-transfer pill: current speed, progress, pause/resume/cancel.
///
/// Shows only while a transfer is active or recently finished with an error,
/// so the normal browsing UI stays uncluttered.
class _TransferPill extends ConsumerStatefulWidget {
  const _TransferPill({required this.onOpen});

  final VoidCallback onOpen;

  @override
  ConsumerState<_TransferPill> createState() => _TransferPillState();
}

class _TransferPillState extends ConsumerState<_TransferPill> {
  String? _announcedId;
  TransferStatus? _announcedStatus;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final controller = ref.read(transferControllerProvider.notifier);
    final transfers = ref.watch(transferControllerProvider);

    Transfer? current;
    for (final t in transfers) {
      if (t.isActive) {
        current = t;
        break;
      }
    }
    current ??= transfers.isNotEmpty ? transfers.last : null;
    if (current == null || current.isTerminal) {
      final failed = transfers.where((t) => t.status == TransferStatus.failed);
      if (failed.isEmpty) return const SizedBox.shrink();
      current = failed.last;
    }
    final transfer = current;

    // Announce terminal transitions once for screen readers.
    if ((transfer.status == TransferStatus.completed ||
            transfer.status == TransferStatus.failed) &&
        (_announcedId != transfer.id ||
            _announcedStatus != transfer.status)) {
      _announcedId = transfer.id;
      _announcedStatus = transfer.status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final msg = transfer.status == TransferStatus.completed
            ? '${transfer.name} finished'
            : '${transfer.name} failed. ${transfer.errorMessage ?? ''}';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              action: transfer.status == TransferStatus.failed &&
                      transfer.canRetry
                  ? SnackBarAction(
                      label: 'Retry',
                      onPressed: () => controller.retryTransfer(transfer.id),
                    )
                  : SnackBarAction(
                      label: 'View',
                      onPressed: widget.onOpen,
                    ),
            ),
          );
      });
    }

    return Semantics(
      label:
          '${transfer.direction.name} ${transfer.status.name} transfer ${transfer.name}',
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: transfer.status == TransferStatus.failed
                  ? pal.dangerBorder
                  : pal.accentBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: (transfer.status == TransferStatus.failed
                        ? pal.danger
                        : pal.accent)
                    .withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _PulsingDot(
                color: transfer.status == TransferStatus.failed
                    ? pal.danger
                    : transfer.status == TransferStatus.paused
                        ? pal.warn
                        : pal.accent,
                active: transfer.isActive,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pal.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Bytes tick at 5 Hz but only this meter rebuilds: it
                    // subscribes to the single progress entry via select.
                    _PillMeter(transfer: transfer),
                  ],
                ),
              ),
              if (transfer.canPause)
                IconButton(
                  tooltip: 'Pause ${transfer.name}',
                  icon: const Icon(Icons.pause, size: 20),
                  onPressed: () => controller.pauseTransfer(transfer.id),
                ),
              if (transfer.canResume)
                IconButton(
                  tooltip: 'Resume ${transfer.name}',
                  icon: const Icon(Icons.play_arrow, size: 20),
                  onPressed: () => controller.resumeTransfer(transfer.id),
                ),
              if (transfer.canCancel)
                IconButton(
                  tooltip: 'Cancel ${transfer.name}',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => controller.cancelTransfer(transfer.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live progress meter for the transfer pill. Watches only this transfer's
/// byte counter, so 5 Hz ticks rebuild this meter alone — never the shell.
class _PillMeter extends ConsumerWidget {
  const _PillMeter({required this.transfer});

  final Transfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = SfsPalette.of(context);
    final bytes = ref.watch(
      transferProgressProvider.select((m) => m[transfer.id]),
    );
    final done = (bytes ?? transfer.bytesTransferred).clamp(0, transfer.size);
    final pct = transfer.size <= 0
        ? (transfer.status == TransferStatus.completed ? 100 : 0)
        : (done * 100 / transfer.size).round().clamp(0, 100);
    final calc = ref
        .read(transferControllerProvider.notifier)
        .getSpeedCalculator(transfer.id);
    final speed = calc?.getSmoothedSpeed(DateTime.now()) ?? 0;
    final remaining = calc?.estimateRemaining(done, transfer.size, DateTime.now());

    return Semantics(
      label: '$pct percent complete',
      value: '$pct%',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: transfer.size <= 0 ? null : done / transfer.size,
              minHeight: 4,
              backgroundColor: pal.surfaceOverlay,
              color: transfer.status == TransferStatus.failed
                  ? pal.danger
                  : pal.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$pct% · ${formatBytes(done)} of '
            '${formatBytes(transfer.size)}'
            '${speed > 0 ? ' · ${formatBytes(speed.toInt())}/s' : ''}'
            '${remaining != null ? ' · ${_fmtEta(remaining)} left' : ''}',
            style: TextStyle(color: pal.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _fmtEta(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final Animation<double> _glow =
      Tween(begin: 0.35, end: 1.0).animate(_pulse);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Icon(Icons.circle, size: 10, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.55 * _glow.value),
              blurRadius: 10 * _glow.value,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
