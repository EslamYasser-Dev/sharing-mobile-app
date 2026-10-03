import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models.dart';
import '../services/viewer_gate.dart';
import '../state/auth_controller.dart';
import '../state/follow_controller.dart';
import '../state/timeline_controller.dart';
import '../theme.dart';
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
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(() {
      ref.read(timelineControllerProvider.notifier).loadInitial();
      ref.read(followControllerProvider.notifier).refreshFollowing();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      ref.read(timelineControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final state = ref.watch(timelineControllerProvider);
    final me = ref.watch(authControllerProvider).user?.username;
    final items = state.filtered(me);

    return Scaffold(
      backgroundColor: pal.background,
      appBar: AppBar(title: const Text('Timeline')),
      body: Column(
        children: [
          _FilterChips(state: state, pal: pal),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(timelineControllerProvider.notifier)
                  .refresh(),
              child: _list(context, state, items, me, pal),
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
        'Could not load timeline',
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
            : 'Your timeline is quiet',
        state.filter == TimelineFilter.mine
            ? 'Upload a file and it will show up here.'
            : 'Follow people to see their shared uploads, or check back later.',
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
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

class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.state, required this.pal});

  final TimelineState state;
  final SfsPalette pal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timelineControllerProvider.notifier);
    Widget chip(TimelineFilter filter, String label) => ChoiceChip(
      label: Text(label),
      selected: state.filter == filter,
      onSelected: (_) => notifier.setFilter(filter),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          chip(TimelineFilter.all, 'All'),
          const SizedBox(width: 8),
          chip(TimelineFilter.mine, 'Mine'),
          const SizedBox(width: 8),
          chip(TimelineFilter.following, 'Following'),
        ],
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
    return Card(
      child: ListTile(
        leading: _leading(pal),
        title: Text(event.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${event.owner} · ${formatBytes(event.size)} · ${formatDate(event.createdAt)}',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VisibilityChip(visibility: event.visibility),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => _onMenu(context, ref, v),
              itemBuilder: (_) => _menuItems(ref),
            ),
          ],
        ),
        onTap: _kind == ViewerKind.none
            ? null
            : () => _open(context),
      ),
    );
  }

  Widget _leading(SfsPalette pal) {
    switch (event.kind) {
      case 'share':
        return Icon(Icons.link, color: pal.accent);
      case 'visibility':
        return Icon(Icons.visibility_outlined, color: pal.muted);
      default:
        switch (_kind) {
          case ViewerKind.image:
            return Icon(Icons.image_outlined, color: pal.accent);
          case ViewerKind.video:
            return Icon(Icons.play_circle_outlined, color: pal.accent);
          case ViewerKind.none:
            return Icon(Icons.insert_drive_file_outlined, color: pal.muted);
        }
    }
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
        await showModalBottomSheet<void>(
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
        if (!ok && context.mounted) {
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

class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip({required this.visibility});

  final String visibility;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final (label, icon) = switch (visibility) {
      'public' => ('Public', Icons.public_outlined),
      'link' => ('Followers', Icons.group_outlined),
      _ => ('Private', Icons.lock_outlined),
    };
    return Semantics(
      label: 'Visibility: $label',
      child: Chip(
        avatar: Icon(icon, size: 14, color: pal.muted),
        label: Text(label, style: TextStyle(fontSize: 11, color: pal.muted)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

