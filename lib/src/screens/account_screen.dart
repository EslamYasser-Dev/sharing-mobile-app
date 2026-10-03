import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../theme.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = SfsPalette.of(context);
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final user = auth.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final role = user.isAdmin
        ? 'Admin'
        : ((user.role != null && user.role!.isNotEmpty)
              ? user.role!
              : 'Member');
    final joined = (user.createdAt != null && user.createdAt!.isNotEmpty)
        ? ' · joined ${formatDate(user.createdAt!)}'
        : '';
    final quota = user.quotaBytes ?? 0;
    final used = user.size ?? 0;
    final files = user.files ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('ACCOUNT', style: SfsTextStyles.eyebrow(pal)),
            const SizedBox(height: 6),
            Text(user.username, style: SfsTextStyles.title(pal)),
            const SizedBox(height: 4),
            Text(
              '$role$joined',
              style: TextStyle(color: pal.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
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
                        child: _Stat(label: 'Files', value: '$files'),
                      ),
                      Expanded(
                        child: _Stat(label: 'Used', value: formatBytes(used)),
                      ),
                      Expanded(
                        child: _Stat(
                          label: 'Quota',
                          value: quota > 0 ? formatBytes(quota) : 'Unlimited',
                        ),
                      ),
                    ],
                  ),
                  if (quota > 0) ...[
                    const SizedBox(height: 14),
                    Container(height: 1, color: pal.rule),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (used / quota).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: pal.surfaceOverlay,
                        color: used >= quota ? pal.danger : pal.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatBytes(used)} of ${formatBytes(quota)} used',
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SfsGlass.of(pal).tint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SfsGlass.of(pal).border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('APPEARANCE', style: SfsTextStyles.eyebrow(pal)),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 16),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (modes) => unawaited(
                      ref.read(themeModeProvider.notifier).set(modes.first),
                    ),
                    style: ButtonStyle(
                      elevation: const WidgetStatePropertyAll(0),
                      side: WidgetStatePropertyAll(
                        BorderSide(color: pal.border),
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        return states.contains(WidgetState.selected)
                            ? pal.accent
                            : pal.surfaceOverlay;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        return states.contains(WidgetState.selected)
                            ? pal.onAccent
                            : pal.text;
                      }),
                      iconSize: const WidgetStatePropertyAll(16),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: pal.danger,
                side: BorderSide(color: pal.dangerBorder),
              ),
              onPressed: () => unawaited(
                ref.read(authControllerProvider.notifier).signOut(),
              ),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 24),
            Center(child: Text('FILESHARE', style: SfsTextStyles.label(pal))),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: SfsTextStyles.label(pal)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: pal.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
