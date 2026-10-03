import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../services/viewer_gate.dart';
import '../state/auth_controller.dart';
import '../state/transfer_controller.dart';
import '../theme.dart';
import 'image_viewer_screen.dart';
import 'video_screen.dart';
import 'visibility_sheet.dart';

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
    final pal = SfsPalette.of(context);
    final playable = viewerKindFor(item.name) != ViewerKind.none;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Text(formatBytes(item.size)),
        actions: [
          if (playable)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _openPreview(item);
              },
              child: const Text('Preview'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_downloadAndShare(item));
            },
            child: const Text('Download & share'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_download(item));
            },
            child: const Text('Queue download'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              showDialog<void>(
                context: this.context,
                builder: (context) => _ShareDialog(item: item),
              );
            },
            child: const Text('Create link'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final owner =
                  ref.read(authControllerProvider).user?.username ?? '';
              showModalBottomSheet<void>(
                context: this.context,
                builder: (_) => VisibilitySheet(
                  owner: owner,
                  path: item.path,
                  name: item.name,
                ),
              );
            },
            child: const Text('Who can see…'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: pal.danger),
            onPressed: () {
              Navigator.pop(context);
              unawaited(_confirmDelete(item));
            },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final pal = SfsPalette.of(context);
    if (_loading && _items.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
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
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 56, color: pal.rule),
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    item.isDir
                        ? Icons.folder_outlined
                        : Icons.description_outlined,
                    size: 20,
                    color: item.isDir ? pal.accent : pal.muted,
                  ),
                  title: Text(
                    item.name,
                    style: TextStyle(
                      color: pal.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: item.isDir
                      ? null
                      : Text(
                          formatBytes(item.size),
                          style: TextStyle(color: pal.muted, fontSize: 12),
                        ),
                  trailing: item.isDir
                      ? Icon(Icons.chevron_right, color: pal.muted)
                      : IconButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: pal.muted,
                            size: 20,
                          ),
                          onPressed: () => _openActions(item),
                        ),
                  onTap: () {
                    if (item.isDir) {
                      _navigate(item.path);
                    } else if (viewerKindFor(item.name) != ViewerKind.none) {
                      _openPreview(item);
                    } else {
                      _openActions(item);
                    }
                  },
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
      backgroundColor: pal.background,
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
