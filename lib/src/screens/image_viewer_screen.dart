import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../services/viewer_gate.dart';
import '../state/auth_controller.dart';
import '../theme.dart';

/// Full-screen image viewer. The image streams straight from the server
/// (`Image.network` renders progressively as bytes arrive) — nothing is
/// downloaded first. Owners stream directly; anyone else is gated on a
/// fetched [VisibilitySetting] before the first request. The server
/// re-checks the gate on every byte served.
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
  String? _url;
  Map<String, String>? _headers;
  bool _gateDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isOwner =>
      ref.read(authControllerProvider).user?.username == widget.owner;

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    if (!_isOwner) {
      final vis = await api.getVisibility(
        owner: widget.owner,
        path: widget.path,
      );
      if (!mounted) return;
      if (!canPlayMedia(isOwner: false, setting: vis.data)) {
        setState(() => _gateDenied = true);
        return;
      }
    }
    final headers = await api.authHeaders();
    if (!mounted) return;
    setState(() {
      _headers = headers;
      _url = api.viewUrl(
        owner: widget.owner,
        path: widget.path,
        isOwner: _isOwner,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
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
    final url = _url;
    final headers = _headers;
    if (url == null || headers == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                semanticsLabel: 'Checking access',
              ),
            ),
            const SizedBox(height: 12),
            Text('Checking access…', style: TextStyle(color: pal.muted)),
          ],
        ),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        // Hero flight target for the file-row thumbnail (tag includes the
        // path; feed opens the same viewer without a source hero, which
        // simply skips the flight).
        child: Hero(
          tag: 'file-image:${widget.path}',
          child: Image(
            // Cap the decoded width at 2x the screen: full-res photos
            // (12+ MP) would otherwise spike memory by hundreds of MB.
            image: ResizeImage(
              NetworkImage(url, headers: headers),
              width: _maxDecodeWidth(context),
            ),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // Streams in as bytes arrive; the bar only shows while the
            // headers/total are still unknown.
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              final expected = progress.expectedTotalBytes;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 160,
                      child: LinearProgressIndicator(
                        value: expected == null || expected <= 0
                            ? null
                            : (progress.cumulativeBytesLoaded / expected)
                                  .clamp(0.0, 1.0),
                        semanticsLabel: 'Loading ${widget.name}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      expected == null || expected <= 0
                          ? 'Loading… ${formatBytes(progress.cumulativeBytesLoaded)}'
                          : 'Loading… ${formatBytes(progress.cumulativeBytesLoaded)} of ${formatBytes(expected)}',
                      style: TextStyle(color: pal.muted),
                    ),
                  ],
                ),
              );
            },
            errorBuilder: (_, _, _) => _message(
              pal,
              Icons.broken_image_outlined,
              'Could not load image',
              'The file could not be streamed.',
            ),
            semanticLabel: widget.name,
          ),
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
    String detail,
  ) {
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
          ],
        ),
      ),
    );
  }
}
