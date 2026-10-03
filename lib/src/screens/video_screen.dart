import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../format.dart';
import '../services/media_staging.dart';
import '../state/auth_controller.dart';
import '../theme.dart';

/// Download-then-play video screen. True streaming waits on backend
/// `Range: 206` support; until then the file stages into temp storage with
/// progress + cancel, then plays locally (and offline-capable).
class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({
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
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  VideoPlayerController? _controller;
  double? _progress;
  int _received = 0;
  String? _error;
  bool _gateDenied = false;
  bool _cancelled = false;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelled = true;
    _positionTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  bool get _isOwner =>
      ref.read(authControllerProvider).user?.username == widget.owner;

  Future<void> _load() async {
    try {
      final file = await stageMediaForPlayback(
        api: ref.read(apiClientProvider),
        owner: widget.owner,
        path: widget.path,
        isOwner: _isOwner,
        onProgress: (received) {
          if (!mounted || _cancelled) return;
          setState(() {
            _received = received;
            _progress = widget.size > 0
                ? (received / widget.size).clamp(0.0, 1.0)
                : null;
          });
        },
      );
      if (!mounted || _cancelled) return;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted || _cancelled) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _progress = 1;
      });
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) {
          if (mounted) setState(() {});
        },
      );
      await controller.play();
    } on MediaGateDenied {
      if (!mounted) return;
      setState(() => _gateDenied = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is StateError ? e.message : e.toString());
    }
  }

  String _stamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
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
        'The owner has not enabled video playback for this file.',
      );
    }
    if (_error != null) {
      return _message(
        pal,
        Icons.play_disabled_outlined,
        'Could not play video',
        _error!,
        retry: true,
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
    final value = controller.value;
    final duration = value.duration;
    final position = value.position;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: value.isPlaying ? 'Pause' : 'Play',
                child: IconButton(
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40,
                  ),
                  color: pal.accent,
                  onPressed: () {
                    if (value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                    setState(() {});
                  },
                ),
              ),
              Text(
                _stamp(position),
                style: TextStyle(color: pal.muted, fontSize: 12),
              ),
              Expanded(
                child: Semantics(
                  slider: true,
                  label: 'Seek',
                  child: Slider(
                    min: 0,
                    max: duration.inMilliseconds
                        .toDouble()
                        .clamp(1.0, 9223372036854775807.0),
                    value: position.inMilliseconds.toDouble().clamp(
                      0.0,
                      duration.inMilliseconds
                          .toDouble()
                          .clamp(1.0, 9223372036854775807.0),
                    ),
                    onChanged: (v) {
                      controller.seekTo(
                        Duration(milliseconds: v.round()),
                      );
                    },
                  ),
                ),
              ),
              Text(
                _stamp(duration),
                style: TextStyle(color: pal.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
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
                  _controller?.dispose();
                  _controller = null;
                  _progress = null;
                  _received = 0;
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
