import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models.dart';
import '../services/haptics.dart';
import '../services/viewer_gate.dart';
import '../state/auth_controller.dart';
import '../state/follow_controller.dart';
import '../state/timeline_controller.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import 'image_viewer_screen.dart';
import 'video_screen.dart';
import 'visibility_sheet.dart';

/// Upload timeline: paginated feed of uploads/shares/visibility changes from
/// the signed-in user, followed accounts (link-scoped), and public posts.
/// Owners can re-scope their files inline; others can follow/unfollow and
/// open playable media.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(timelineControllerProvider.notifier).loadInitial();
      ref.read(followControllerProvider.notifier).refreshFollowing();
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
      ref.read(timelineControllerProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final state = ref.watch(timelineControllerProvider);
    final me = ref.watch(authControllerProvider).user?.username;
    final items = state.filtered(me);

    return Scaffold(
      // Transparent over the shell aurora; cards paint glass.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('TailTime'),
      ),
      body: Column(
        children: [
          _FilterChips(state: state, pal: pal),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(timelineControllerProvider.notifier)
                  .refresh(),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: _list(context, state, items, me, pal),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    TimelineState state,
    List<FeedEvent> items,
    String? me,
    SfsPalette pal,
  ) {
    if (state.isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && items.isEmpty) {
      return _empty(
        pal,
        Icons.cloud_off_outlined,
        'Could not load TailTime',
        state.error!,
        retry: true,
      );
    }
    if (items.isEmpty) {
      return _empty(
        pal,
        Icons.dynamic_feed_outlined,
        state.filter == TimelineFilter.mine
            ? 'Nothing here yet'
            : 'Your TailTime is quiet',
        state.filter == TimelineFilter.mine
            ? 'Upload a file and it will show up here.'
            : 'Follow people to see their shared uploads, or check back later.',
      );
    }
    // Crossfade when the feed contents swap (refresh / filter change):
    // keyed by filter + head event so appends don't replay it.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      child: ListView.separated(
        key: ValueKey('${state.filter.name}:${items.isEmpty ? '' : items.first.id}:${items.length}'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        itemCount: items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _FeedCard(event: items[i], me: me);
        },
      ),
    );
  }

  Widget _empty(
    SfsPalette pal,
    IconData icon,
    String title,
    String detail, {
    bool retry = false,
  }) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(icon, size: 48, color: pal.muted),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(color: pal.text, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.muted),
              ),
              if (retry) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref
                      .read(timelineControllerProvider.notifier)
                      .loadInitial(),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Segmented glass filter: All / Mine / Following with a sliding thumb.
/// Paint-only glass (no blur) so it stays cheap inside the scroll view.
class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.state, required this.pal});

  final TimelineState state;
  final SfsPalette pal;

  static const _options = [
    (TimelineFilter.all, 'All'),
    (TimelineFilter.mine, 'Mine'),
    (TimelineFilter.following, 'Following'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timelineControllerProvider.notifier);
    final selected = _options.indexWhere((o) => o.$1 == state.filter);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: SfsDecor.glass(pal, radius: SfsRadii.pill),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth / _options.length;
            return Stack(
              children: [
                AnimatedAlign(
                  alignment: Alignment(
                    -1 + (selected * 2 / (_options.length - 1)),
                    0,
                  ),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: w,
                    height: 34,
                    decoration: BoxDecoration(
                      color: pal.accent,
                      borderRadius: BorderRadius.circular(SfsRadii.pill),
                      boxShadow: SfsShadows.glow(pal, pal.accent),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _options.length; i++)
                      SizedBox(
                        width: w,
                        height: 34,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            sfsTap();
                            notifier.setFilter(_options[i].$1);
                          },
                          child: Center(
                            child: Text(
                              _options[i].$2,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: i == selected
                                    ? pal.onAccent
                                    : pal.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeedCard extends ConsumerWidget {
  const _FeedCard({required this.event, required this.me});

  final FeedEvent event;
  final String? me;

  bool get _mine => me != null && me == event.owner;
  ViewerKind get _kind => viewerKindFor(event.name);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = SfsPalette.of(context);
    // Paint-only glass: a scrolling list of real blurs would sink the GPU.
    // Own posts get the neon accent edge.
    return Container(
      decoration: _mine
          ? SfsDecor.liveGlass(pal, radius: 14)
          : SfsDecor.glass(pal, radius: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _kind == ViewerKind.none
              ? null
              : () {
                  sfsTap();
                  _open(context);
                },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _leading(pal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${event.owner} · ${formatBytes(event.size)} · ${formatDate(event.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.muted,
                          fontSize: 11,
                          fontFamilyFallback: const ['monospace'],
                        ),
                      ),
                    ],
                  ),
                ),
                _VisibilityDot(visibility: event.visibility),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: pal.muted, size: 20),
                  onSelected: (v) => _onMenu(context, ref, v),
                  itemBuilder: (_) => _menuItems(ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(SfsPalette pal) {
    final (icon, tint) = switch (event.kind) {
      'share' => (Icons.link_rounded, pal.accent),
      'visibility' => (Icons.visibility_outlined, pal.muted),
      _ => switch (_kind) {
        ViewerKind.image => (Icons.image_outlined, pal.accent),
        ViewerKind.video => (
          Icons.play_circle_outlined,
          const Color(0xFF8B7CF6),
        ),
        ViewerKind.none => (
          Icons.insert_drive_file_outlined,
          pal.muted,
        ),
      },
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Icon(icon, size: 19, color: tint),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(WidgetRef ref) {
    final items = <PopupMenuEntry<String>>[];
    if (_kind != ViewerKind.none) {
      items.add(const PopupMenuItem(value: 'open', child: Text('Open')));
    }
    if (_mine) {
      items.add(
        const PopupMenuItem(value: 'visibility', child: Text('Who can see…')),
      );
    } else {
      // Bool-only subscription: follow changes for other users must not
      // rebuild every card.
      final following = ref.watch(
        followControllerProvider.select(
          (s) => s.following.contains(event.owner),
        ),
      );
      items.add(
        PopupMenuItem(
          value: following ? 'unfollow' : 'follow',
          child: Text(following ? 'Unfollow ${event.owner}' : 'Follow ${event.owner}'),
        ),
      );
    }
    return items;
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String value) async {
    switch (value) {
      case 'open':
        _open(context);
      case 'visibility':
        await showSpringSheet<void>(
          context: context,
          builder: (_) => VisibilitySheet(
            owner: event.owner,
            path: event.path,
            name: event.name,
          ),
        );
      case 'follow':
      case 'unfollow':
        final ok = value == 'follow'
            ? await ref
                .read(followControllerProvider.notifier)
                .follow(event.owner)
            : await ref
                .read(followControllerProvider.notifier)
                .unfollow(event.owner);
        if (ok) {
          sfsConfirm();
        } else if (context.mounted) {
          sfsError();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ref.read(followControllerProvider).error ?? 'Request failed',
              ),
            ),
          );
        }
    }
  }

  void _open(BuildContext context) {
    final dest = switch (_kind) {
      ViewerKind.image => ImageViewerScreen(
        owner: event.owner,
        path: event.path,
        name: event.name,
        size: event.size,
      ),
      ViewerKind.video => VideoScreen(
        owner: event.owner,
        path: event.path,
        name: event.name,
        size: event.size,
      ),
      ViewerKind.none => null,
    };
    if (dest == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => dest));
  }
}

/// Visibility as a glowing status dot + mono label. Color is status, not
/// decoration: private reads calm, followers warm, public bright.
class _VisibilityDot extends StatelessWidget {
  const _VisibilityDot({required this.visibility});

  final String visibility;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final (label, color) = switch (visibility) {
      'public' => ('PUBLIC', pal.accent),
      'link' => ('FOLLOWERS', const Color(0xFF8B7CF6)),
      _ => ('PRIVATE', pal.muted),
    };
    return Semantics(
      label: 'Visibility: $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.8),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
              color: pal.muted,
              fontFamilyFallback: const ['monospace'],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

