import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../services/haptics.dart';
import '../services/viewer_gate.dart';
import '../state/auth_controller.dart';
import '../state/transfer_controller.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import 'image_viewer_screen.dart';
import 'video_screen.dart';
import 'visibility_sheet.dart';

/// Disk-cached JPEG preview per file, keyed by path + modification time.
/// Riverpod memoizes the future per key, so scrolling never refetches.
final _thumbProvider =
    FutureProvider.family<File?, ({String path, String modified, int size})>((
      ref,
      key,
    ) async {
      final api = ref.read(apiClientProvider);
      return api.fetchThumbnail(
        path: key.path,
        modified: key.modified,
        size: key.size,
      );
    });

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, this.onOpenShares, this.onOpenTransfers});

  final VoidCallback? onOpenShares;
  final VoidCallback? onOpenTransfers;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _path = '';
  List<FileItem> _items = const [];
  bool _loading = true;
  String? _error;
  bool _picking = false;
  final _newFolderName = TextEditingController();
  StreamSubscription<ServerEvent>? _eventsSub;

  @override
  void initState() {
    super.initState();
    unawaited(_load(_path));
    _eventsSub = ref.read(eventsServiceProvider).stream.listen((_) {
      unawaited(_load(_path));
      unawaited(ref.read(authControllerProvider.notifier).refreshUser());
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _newFolderName.dispose();
    super.dispose();
  }

  Future<void> _load(String target) async {
    final res = await ref.read(apiClientProvider).listFiles(target);
    if (!mounted || target != _path) return;
    setState(() {
      if (res.error != null) {
        _error = res.error;
        _items = const [];
      } else {
        _error = null;
        final sorted = [...?res.data]
          ..sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        _items = sorted;
      }
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      _load(_path),
      ref.read(authControllerProvider.notifier).refreshUser(),
    ]);
  }

  void _navigate(String path) {
    setState(() {
      _path = path;
      _loading = true;
      _items = const [];
      _error = null;
    });
    unawaited(_load(path));
  }

  void _goUp() {
    if (_path.isNotEmpty) _navigate(parentPath(_path));
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

  Future<void> _openNewFolder() async {
    final pal = SfsPalette.of(context);
    _newFolderName.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: _newFolderName,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.accent),
            onPressed: () => Navigator.pop(context, _newFolderName.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final res = await ref
        .read(apiClientProvider)
        .createDirectory(joinPath(_path, name));
    if (!mounted) return;
    if (!res.ok) {
      _showError('Create failed', res.error ?? 'Unknown error');
      return;
    }
    unawaited(_load(_path));
    unawaited(ref.read(authControllerProvider.notifier).refreshUser());
  }

  /// Enqueues one resumable upload per picked file (up to the queue limit)
  /// and surfaces progress through the Transfers tab + global pill instead
  /// of a single inline percentage.
  Future<void> _upload() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty || !mounted) return;
      final controller = ref.read(transferControllerProvider.notifier);
      var queued = 0;
      String? firstError;
      for (final pf in picked) {
        try {
          if (pf.path != null) {
            await controller.enqueueUpload(
              fileName: pf.name,
              dirPath: _path,
              file: File(pf.path!),
            );
          } else {
            await controller.enqueueUpload(
              fileName: pf.name,
              dirPath: _path,
              file: null,
              bytes: await pf.readAsBytes(),
            );
          }
          queued++;
        } catch (e) {
          firstError ??= e.toString();
        }
      }
      if (!mounted) return;
      if (queued == 0) {
        _showError(
          'Upload failed',
          firstError ?? 'No files could be queued',
        );
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              queued == 1
                  ? '1 upload queued — pause or resume it in Transfers'
                  : '$queued uploads queued — pause or resume them in Transfers',
            ),
            behavior: SnackBarBehavior.floating,
            action: widget.onOpenTransfers == null
                ? null
                : SnackBarAction(
                    label: 'View',
                    onPressed: widget.onOpenTransfers!,
                  ),
          ),
        );
      unawaited(_load(_path));
      unawaited(ref.read(authControllerProvider.notifier).refreshUser());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Enqueues a resumable download (pause/resume in Transfers) instead of a
  /// blocking one-shot fetch.
  Future<void> _download(FileItem item) async {
    try {
      await ref
          .read(transferControllerProvider.notifier)
          .enqueueDownload(
            remotePath: item.path,
            name: item.name,
            size: item.size,
          );
    } catch (e) {
      if (!mounted) return;
      _showError('Download failed', e.toString());
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(
            content: Text(
              'Download queued for ${item.name} — pause or resume it in Transfers',
            ),
            behavior: SnackBarBehavior.floating,
            action: widget.onOpenTransfers == null
                ? null
                : SnackBarAction(
                    label: 'View',
                    onPressed: widget.onOpenTransfers!,
                  ),
          ),
      );
  }

  Future<void> _downloadAndShare(FileItem item) async {
    final res = await ref.read(apiClientProvider).download(item.path);
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      _showError('Download failed', res.error ?? 'Unknown error');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(res.data!.file.path)], title: res.data!.name),
    );
  }

  Future<void> _confirmDelete(FileItem item) async {
    final pal = SfsPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete ${item.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await ref.read(apiClientProvider).deletePath(item.path);
    if (!mounted) return;
    if (!res.ok) {
      _showError('Delete failed', res.error ?? 'Unknown error');
      return;
    }
    unawaited(_load(_path));
    unawaited(ref.read(authControllerProvider.notifier).refreshUser());
  }

  void _openPreview(FileItem item) {
    final owner = ref.read(authControllerProvider).user?.username ?? '';
    final dest = switch (viewerKindFor(item.name)) {
      ViewerKind.image => ImageViewerScreen(
        owner: owner,
        path: item.path,
        name: item.name,
        size: item.size,
      ),
      ViewerKind.video => VideoScreen(
        owner: owner,
        path: item.path,
        name: item.name,
        size: item.size,
      ),
      ViewerKind.none => null,
    };
    if (dest == null) {
      _openActions(item);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => dest));
  }

  void _openActions(FileItem item) {
    final playable = viewerKindFor(item.name) != ViewerKind.none;
    sfsTap();
    unawaited(
      showSpringSheet<void>(
        context: context,
        // Explicit callbacks: a dialog route has no screen ancestor, so the
        // sheet must never look one up (it silently yields null and every
        // tile dead-ends).
        builder: (_) => _FileActionsSheet(
          item: item,
          playable: playable,
          onPreview: () => _openPreview(item),
          onDownloadShare: () => unawaited(_downloadAndShare(item)),
          onQueueDownload: () => unawaited(_download(item)),
          onCreateLink: () => _openShareDialog(item),
          onVisibility: () => _openVisibility(item),
          onDelete: () => unawaited(_confirmDelete(item)),
        ),
      ),
    );
  }

  void _openShareDialog(FileItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => _ShareDialog(item: item),
    );
  }

  void _openVisibility(FileItem item) {
    final owner = ref.read(authControllerProvider).user?.username ?? '';
    unawaited(
      showSpringSheet<void>(
        context: context,
        builder: (_) =>
            VisibilitySheet(owner: owner, path: item.path, name: item.name),
      ),
    );
  }

  /// Shimmering placeholder rows while the listing loads. One shared shimmer
  /// over static glass rows keeps the shader cost flat.
  Widget _skeletons(SfsPalette pal) {
    return ShimmerSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        itemBuilder: (context, index) => Container(
          margin: EdgeInsets.fromLTRB(12, index == 0 ? 12 : 0, 12, 8),
          padding: const EdgeInsets.all(12),
          decoration: SfsDecor.glass(pal, radius: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: pal.surfaceOverlay,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: pal.surfaceOverlay,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 90,
                      decoration: BoxDecoration(
                        color: pal.surfaceOverlay,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// File-type glyph: distinct icon + tint per kind so images, video, and
  /// documents scan at a glance.
  Widget _glyph(SfsPalette pal, FileItem item) {
    final kind = item.isDir ? ViewerKind.none : viewerKindFor(item.name);
    final (icon, tint) = item.isDir
        ? (Icons.folder_outlined, pal.accent)
        : switch (kind) {
            ViewerKind.image => (Icons.image_outlined, pal.accent),
            ViewerKind.video => (Icons.play_circle_outlined, const Color(0xFF8B7CF6)),
            ViewerKind.none => (Icons.description_outlined, pal.muted),
          };
    // NOTE: the image Hero lives on the loaded thumbnail in [_MediaThumb],
    // never here, so the tag is never duplicated in one tree.
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

  Widget _buildBody() {
    final pal = SfsPalette.of(context);
    if (_loading && _items.isEmpty && _error == null) {
      return _skeletons(pal);
    }
    if (_error != null && _items.isEmpty) {
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
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                unawaited(_load(_path));
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: pal.accent,
      backgroundColor: pal.card,
      onRefresh: _refresh,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: 160),
                Center(
                  child: Text(
                    'Empty folder',
                    style: TextStyle(color: pal.muted, fontSize: 15),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemBuilder: (context, index) {
                final item = _items[index];
                final playable =
                    !item.isDir && viewerKindFor(item.name) != ViewerKind.none;
                return Container(
                  // Paint-only glass (no per-row blur): hundreds of
                  // BackdropFilters would sink the GPU; the aurora still
                  // reads through the translucent tint.
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: SfsDecor.glass(pal, radius: 14),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        sfsTap();
                        if (item.isDir) {
                          _navigate(item.path);
                        } else if (playable) {
                          _openPreview(item);
                        } else {
                          _openActions(item);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _MediaThumb(
                              item: item,
                              glyph: _glyph(pal, item),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: pal.text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (!item.isDir) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      formatBytes(item.size),
                                      style: TextStyle(
                                        color: pal.muted,
                                        fontSize: 11,
                                        fontFamilyFallback: const [
                                          'monospace',
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (playable)
                              Icon(
                                Icons.play_arrow_rounded,
                                color: pal.accent,
                                size: 20,
                              ),
                            item.isDir
                                ? Icon(
                                    Icons.chevron_right,
                                    color: pal.muted,
                                  )
                                : IconButton(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: pal.muted,
                                      size: 20,
                                    ),
                                    onPressed: () => _openActions(item),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final user = ref.watch(authControllerProvider).user;
    final quota = user?.quotaBytes ?? 0;
    final used = user?.size ?? 0;
    // Count-only subscriptions: progress ticks must not rebuild the file
    // browser — meters subscribe to single entries via select.
    final activeCount = ref.watch(
      transferControllerProvider.select(
        (transfers) => transfers.where((t) => t.isActive).length,
      ),
    );
    final queuedCount = ref.watch(
      transferControllerProvider.select(
        (transfers) =>
            transfers.where((t) => t.status == TransferStatus.queued).length,
      ),
    );

    return Scaffold(
      // Transparent over the shell aurora; rows paint glass.
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        onPressed: widget.onOpenShares,
        child: const Icon(Icons.link, size: 22),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                decoration: SfsDecor.glass(pal, radius: 14),
                child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    color: pal.muted,
                    onPressed: _path.isEmpty ? null : _goUp,
                  ),
                  Expanded(
                    child: Text(
                      _path.isEmpty ? '/' : '/$_path',
                      overflow: TextOverflow.ellipsis,
                      style: SfsTextStyles.path(pal),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New folder',
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 22,
                    ),
                    color: pal.text,
                    onPressed: _openNewFolder,
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    onPressed: _picking ? null : _upload,
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: Text(
                      activeCount > 0
                          ? 'Uploading $activeCount'
                          : queuedCount > 0
                              ? '$queuedCount queued'
                              : 'Upload',
                    ),
                  ),
                  if (activeCount + queuedCount > 0)
                    TextButton(
                      onPressed: widget.onOpenTransfers,
                      child: const Text('View'),
                    ),
                ],
                ),
              ),
            ),
            if (quota > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (used / quota).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: pal.surfaceOverlay,
                        color: used >= quota ? pal.danger : pal.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatBytes(used)} of ${formatBytes(quota)} used',
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}

/// File action sheet: springy glass list of everything a file can do.
class _FileActionsSheet extends ConsumerWidget {
  const _FileActionsSheet({
    required this.item,
    required this.playable,
    required this.onPreview,
    required this.onDownloadShare,
    required this.onQueueDownload,
    required this.onCreateLink,
    required this.onVisibility,
    required this.onDelete,
  });

  final FileItem item;
  final bool playable;
  final VoidCallback onPreview;
  final VoidCallback onDownloadShare;
  final VoidCallback onQueueDownload;
  final VoidCallback onCreateLink;
  final VoidCallback onVisibility;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = SfsPalette.of(context);
    Widget tile({
      required IconData icon,
      required String label,
      String? hint,
      Color? color,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: color ?? pal.text, size: 22),
        title: Text(label, style: TextStyle(color: color ?? pal.text)),
        subtitle: hint == null
            ? null
            : Text(hint, style: TextStyle(color: pal.muted, fontSize: 12)),
        onTap: () {
          sfsTap();
          Navigator.pop(context);
          onTap();
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatBytes(item.size),
                  style: TextStyle(
                    color: pal.muted,
                    fontSize: 11,
                    fontFamilyFallback: const ['monospace'],
                  ),
                ),
              ],
            ),
          ),
          if (playable)
            tile(
              icon: Icons.play_arrow_rounded,
              label: 'Preview',
              hint: 'Open in the app',
              color: pal.accent,
              onTap: onPreview,
            ),
          tile(
            icon: Icons.ios_share_outlined,
            label: 'Download & share',
            onTap: onDownloadShare,
          ),
          tile(
            icon: Icons.cloud_download_outlined,
            label: 'Queue download',
            hint: 'Resumable in Transfers',
            onTap: onQueueDownload,
          ),
          tile(
            icon: Icons.link,
            label: 'Create link',
            onTap: onCreateLink,
          ),
          tile(
            icon: Icons.visibility_outlined,
            label: 'Who can see…',
            onTap: onVisibility,
          ),
          tile(
            icon: Icons.delete_outlined,
            label: 'Delete',
            color: pal.danger,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Media preview tile: real thumbnail for images, cinematic tile for video,
/// glyph for the rest. Thumbs stream from `/api/thumbs` once, then come from
/// disk; anything unthumbable falls back silently to the glyph.
class _MediaThumb extends ConsumerWidget {
  const _MediaThumb({required this.item, required this.glyph});

  final FileItem item;
  final Widget glyph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = item.isDir ? ViewerKind.none : viewerKindFor(item.name);
    if (kind == ViewerKind.video) return _videoTile(context);
    if (kind != ViewerKind.image) return glyph;
    final thumb = ref.watch(
      _thumbProvider(
        (path: item.path, modified: item.modified, size: item.size),
      ),
    );
    return thumb.when(
      loading: () => _shimmerBox(context),
      error: (_, _) => glyph,
      data: (file) {
        if (file == null) return glyph;
        return Hero(
          tag: 'file-image:${item.path}',
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: SfsPalette.of(context).accentBorder,
              ),
              image: DecorationImage(
                image: FileImage(file),
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shimmerBox(BuildContext context) {
    final pal = SfsPalette.of(context);
    return ShimmerSkeleton(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: pal.surfaceOverlay,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _videoTile(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF8B7CF6).withValues(alpha: 0.55),
            pal.card.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF8B7CF6).withValues(alpha: 0.45),
        ),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _ShareDialog extends ConsumerStatefulWidget {
  const _ShareDialog({required this.item});

  final FileItem item;

  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  final _password = TextEditingController();
  final _maxDownloads = TextEditingController();
  bool _busy = false;
  bool _created = false;
  String? _url;
  String? _error;
  ShareItem? _share;

  @override
  void dispose() {
    _password.dispose();
    _maxDownloads.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final maxDownloads = int.tryParse(_maxDownloads.text.trim()) ?? 0;
    if (maxDownloads < 0) {
      setState(() => _error = 'Download limit must be zero or more.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final res = await api.createShare(
      widget.item.path,
      0,
      password: _password.text,
      maxDownloads: maxDownloads,
    );
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      setState(() {
        _busy = false;
        _error = res.error ?? 'Unknown error';
      });
      return;
    }
    setState(() {
      _busy = false;
      _created = true;
      _share = res.data;
      _url = api.shareUrl(res.data!.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return AlertDialog(
      title: Text(
        'Share ${widget.item.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: _created ? _resultContent(pal) : _formContent(pal),
      actions: _actions(),
    );
  }

  Widget _formContent(SfsPalette pal) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Password (optional)',
              hintText: 'Empty means anyone with the link',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxDownloads,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Download limit (optional)',
              hintText: 'Empty means unlimited',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: pal.danger)),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _resultContent(SfsPalette pal) {
    final share = _share;
    final meta = [
      if (share != null && share.passwordProtected) 'password-protected',
      if (share != null && share.isLimited)
        '${share.remainingDownloads} of ${share.maxDownloads} downloads left',
    ].join(' · ');
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            _url!,
            style: TextStyle(
              color: pal.accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(meta, style: TextStyle(color: pal.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions() {
    if (_created) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            final url = _url;
            Navigator.pop(context);
            if (url != null) {
              await SharePlus.instance.share(ShareParams(text: url));
            }
          },
          child: const Text('Share'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _create,
        child: const Text('Create link'),
      ),
    ];
  }
}
