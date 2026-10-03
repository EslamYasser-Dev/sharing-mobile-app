import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../services/media_staging.dart';
import '../state/auth_controller.dart';
import '../theme.dart';

/// Full-screen image viewer. Owners stream directly; anyone else is gated on
/// a fetched [VisibilitySetting] (link/public + streaming allowed) before a
/// single byte is downloaded. The server re-checks on every byte served.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.owner,
    required this.path,
    required this.name,
    required this.size,
  });

  final String owner;
  final String path;
  final String name;
  final int size;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  File? _file;
  double? _progress;
  int _received = 0;
  String? _error;
  bool _gateDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isOwner =>
      ref.read(authControllerProvider).user?.username == widget.owner;

  void _onProgress(int received) {
    if (!mounted) return;
    setState(() {
      _received = received;
      // Unknown sizes (feed share entries) stay indeterminate rather than
      // reporting a bogus fraction.
      _progress = widget.size > 0 ? (received / widget.size).clamp(0.0, 1.0) : null;
    });
  }

  Future<void> _load() async {
    try {
      final file = await stageMediaForPlayback(
        api: ref.read(apiClientProvider),
        owner: widget.owner,
        path: widget.path,
        isOwner: _isOwner,
        onProgress: _onProgress,
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _progress = 1;
      });
    } on MediaGateDenied {
      if (!mounted) return;
      setState(() => _gateDenied = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is StateError ? e.message : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, overflow: TextOverflow.ellipsis),
            Text(
              formatBytes(widget.size),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: _body(pal),
    );
  }

  Widget _body(SfsPalette pal) {
    if (_gateDenied) {
      return _message(
        pal,
        Icons.lock_outlined,
        'Not shared with you',
        'The owner has not enabled viewing for this image.',
      );
    }
    if (_error != null) {
      return _message(
        pal,
        Icons.broken_image_outlined,
        'Could not load image',
        _error!,
        retry: true,
      );
    }
    final file = _file;
    if (file == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: _progress,
                semanticsLabel: 'Downloading ${widget.name}',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _progress == null && _received == 0
                  ? 'Checking access…'
                  : 'Downloading… ${formatBytes(_received)}'
                      '${widget.size > 0 ? ' of ${formatBytes(widget.size)}' : ''}',
              style: TextStyle(color: pal.muted),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        // Cap the decoded width at 2x the screen: full-res photos (12+ MP)
        // would otherwise spike memory by hundreds of MB, while 2x still
        // looks sharp at max pinch zoom.
        child: Image(
          image: ResizeImage(
            FileImage(file),
            width: _maxDecodeWidth(context),
          ),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _message(
            pal,
            Icons.broken_image_outlined,
            'Could not decode image',
            'The file is not a valid image.',
          ),
          semanticLabel: widget.name,
        ),
      ),
    );
  }

  int _maxDecodeWidth(BuildContext context) {
    final mq = MediaQuery.of(context);
    return (mq.size.width * mq.devicePixelRatio * 2).round().clamp(1, 8192);
  }

  Widget _message(
    SfsPalette pal,
    IconData icon,
    String title,
    String detail, {
    bool retry = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                onPressed: () => setState(() {
                  _error = null;
                  _progress = null;
                  _load();
                }),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
