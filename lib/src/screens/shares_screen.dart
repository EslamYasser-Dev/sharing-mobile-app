import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../state/auth_controller.dart';
import '../theme.dart';

class SharesScreen extends ConsumerStatefulWidget {
  const SharesScreen({super.key});

  @override
  ConsumerState<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends ConsumerState<SharesScreen> {
  List<ShareItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final res = await ref.read(apiClientProvider).listShares();
    if (!mounted) return;
    setState(() {
      if (res.error != null) {
        _error = res.error;
        _items = const [];
      } else {
        _error = null;
        _items = res.data ?? const [];
      }
      _loading = false;
    });
  }

  void _showError(String title, String message) {
    final pal = SfsPalette.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: pal.danger)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(ShareItem item) async {
    final pal = SfsPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke link'),
        content: Text('Revoke the share for ${item.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await ref.read(apiClientProvider).revokeShare(item.token);
    if (!mounted) return;
    if (!res.ok) {
      _showError('Revoke failed', res.error ?? 'Unknown error');
      return;
    }
    unawaited(_load());
  }

  Widget _buildBody() {
    final pal = SfsPalette.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.danger),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: pal.accent,
                foregroundColor: pal.onAccent,
              ),
              onPressed: () {
                setState(() => _loading = true);
                unawaited(_load());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No shared links yet',
              style: TextStyle(color: pal.muted, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              'Create one from a file’s menu.',
              style: TextStyle(color: pal.muted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: pal.accent,
      backgroundColor: pal.card,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SfsGlass.of(pal).tint,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SfsGlass.of(pal).border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          color: pal.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('/${item.path}', style: SfsTextStyles.path(pal)),
                  ],
                ),
                const SizedBox(height: 6),
                if (item.createdAt.isNotEmpty)
                  Text(
                    'by ${item.owner} · created ${formatDate(item.createdAt)}',
                    style: TextStyle(color: pal.muted, fontSize: 12),
                  )
                else if (item.owner.isNotEmpty)
                  Text(
                    'by ${item.owner}',
                    style: TextStyle(color: pal.muted, fontSize: 12),
                  ),
                if (item.expiresAt.isNotEmpty)
                  Text(
                    'Expires ${formatDate(item.expiresAt)}',
                    style: TextStyle(color: pal.warn, fontSize: 12),
                  ),
                const SizedBox(height: 10),
                Container(height: 1, color: pal.rule),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      // Landing Chip accent tone: accent ink on an accent/30
                      // border, so the positive action reads apart from the
                      // destructive one beside it.
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.accent,
                        side: BorderSide(color: pal.accentBorder),
                      ),
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: ref
                              .read(apiClientProvider)
                              .shareUrl(item.token),
                        ),
                      ),
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Share'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.danger,
                        side: BorderSide(color: pal.dangerBorder),
                      ),
                      onPressed: () => unawaited(_revoke(item)),
                      icon: const Icon(Icons.link_off, size: 16),
                      label: const Text('Revoke'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text('SHARES', style: SfsTextStyles.eyebrow(pal)),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Shared links', style: SfsTextStyles.title(pal)),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
