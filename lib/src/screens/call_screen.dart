import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/haptics.dart';
import '../services/call_config.dart' show CallRoute;
import '../state/call_controller.dart';
import '../theme.dart';

/// Full-screen incoming call: accept / decline. Mounted as an overlay by the
/// shell while [CallStatus.ringing] holds.
class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = SfsPalette.of(context);
    final call = ref.watch(callControllerProvider);
    final controller = ref.read(callControllerProvider.notifier);
    final label = call.peerLabel ?? call.peerId ?? 'Unknown peer';

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.72),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            _PulsingAvatar(pal: pal, video: call.video),
            const SizedBox(height: 20),
            Text(
              label,
              style: TextStyle(
                color: pal.text,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              call.video ? 'Incoming video call…' : 'Incoming voice call…',
              style: TextStyle(color: pal.muted, fontSize: 14),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: Icons.call_end,
                  color: pal.danger,
                  label: 'Decline',
                  onPressed: () {
                    sfsToggle(false);
                    controller.declineCall();
                  },
                ),
                _CallButton(
                  icon: Icons.call,
                  color: const Color(0xFF34C759),
                  label: 'Accept',
                  onPressed: () {
                    sfsConfirm();
                    controller.acceptCall();
                  },
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({required this.pal, required this.video});

  final SfsPalette pal;
  final bool video;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.pal.accentDim,
          border: Border.all(color: widget.pal.accentBorder),
          boxShadow: [
            BoxShadow(
              color: widget.pal.accent.withValues(
                alpha: 0.25 + 0.25 * _pulse.value,
              ),
              blurRadius: 24 + 16 * _pulse.value,
            ),
          ],
        ),
        child: Icon(
          widget.video ? Icons.videocam_outlined : Icons.call_outlined,
          size: 40,
          color: widget.pal.accent,
        ),
      ),
    );
  }
}

/// In-call screen: remote video fullscreen (or voice avatar), local PiP,
/// mute/speaker/camera/hangup, and the transport route badge.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  final RTCVideoRenderer _local = RTCVideoRenderer();
  StreamSubscription<MediaStream>? _remoteSub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _remote.initialize();
    await _local.initialize();
    final session = ref.read(callControllerProvider.notifier).session;
    if (session == null || !mounted) return;
    _remoteSub = session.remoteStreams.listen((stream) {
      _remote.srcObject = stream;
    });
    // Local preview: the session owns the stream; renderers just view it.
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    _remote.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final call = ref.watch(callControllerProvider);
    final controller = ref.read(callControllerProvider.notifier);
    final label = call.peerLabel ?? call.peerId ?? 'Peer';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video or voice avatar.
            Positioned.fill(
              child: call.video
                  ? RTCVideoView(
                      _remote,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_circle_outlined,
                            size: 96,
                            color: pal.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            label,
                            style: TextStyle(
                              color: pal.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            // Status header.
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _statusText(call.status),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _RouteBadge(route: call.route),
                ],
              ),
            ),
            // Local PiP for video calls.
            if (call.video)
              Positioned(
                right: 16,
                top: 84,
                child: _LocalPreview(renderer: _local),
              ),
            // Controls.
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: call.muted ? Icons.mic_off : Icons.mic,
                    color: Colors.white24,
                    label: call.muted ? 'Unmute' : 'Mute',
                    onPressed: () {
                      sfsTap();
                      controller.toggleMute();
                    },
                  ),
                  _CallButton(
                    icon: call.speaker
                        ? Icons.volume_up
                        : Icons.volume_down_outlined,
                    color: Colors.white24,
                    label: 'Speaker',
                    onPressed: () {
                      sfsTap();
                      controller.toggleSpeaker();
                    },
                  ),
                  if (call.video) ...[
                    _CallButton(
                      icon: call.cameraOn
                          ? Icons.videocam
                          : Icons.videocam_off,
                      color: Colors.white24,
                      label: 'Camera',
                      onPressed: () {
                        sfsTap();
                        controller.toggleCamera();
                      },
                    ),
                    _CallButton(
                      icon: Icons.flip_camera_ios_outlined,
                      color: Colors.white24,
                      label: 'Flip',
                      onPressed: () {
                        sfsTap();
                        controller.switchCamera();
                      },
                    ),
                  ],
                  _CallButton(
                    icon: Icons.call_end,
                    color: pal.danger,
                    label: 'End',
                    onPressed: () {
                      sfsToggle(false);
                      controller.hangup();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(CallStatus status) => switch (status) {
        CallStatus.inviting => 'Ringing…',
        CallStatus.connecting => 'Connecting…',
        CallStatus.active => 'Connected',
        CallStatus.ringing => 'Incoming…',
        CallStatus.ended => 'Ended',
        CallStatus.idle => '',
      };
}

/// Local preview PiP. Attaches once the session exists; the renderer is
/// owned by [_CallScreenState].
class _LocalPreview extends ConsumerWidget {
  const _LocalPreview({required this.renderer});

  final RTCVideoRenderer renderer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 96,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: RTCVideoView(
          renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: true,
        ),
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.route});

  final CallRoute route;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final (label, color) = switch (route) {
      CallRoute.direct => ('DIRECT', const Color(0xFF34C759)),
      CallRoute.relay => ('RELAY', const Color(0xFF8B7CF6)),
      CallRoute.unknown => ('…', pal.muted),
    };
    return Semantics(
      label: 'Transport route: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            fontFamilyFallback: const ['monospace'],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
