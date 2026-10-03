import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state/auth_controller.dart';
import '../state/timeline_controller.dart';
import '../theme.dart';
import '../widgets/motion.dart';

/// Bottom sheet to re-scope one file (Private / Followers / Public + the
/// streaming toggle). Used from the timeline and the file browser.
class VisibilitySheet extends ConsumerStatefulWidget {
  const VisibilitySheet({
    super.key,
    required this.owner,
    required this.path,
    required this.name,
  });

  final String owner;
  final String path;
  final String name;

  @override
  ConsumerState<VisibilitySheet> createState() => _VisibilitySheetState();
}

class _VisibilitySheetState extends ConsumerState<VisibilitySheet> {
  String _level = VisibilitySetting.private;
  bool _allowStream = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final vis = await ref
          .read(apiClientProvider)
          .getVisibility(owner: widget.owner, path: widget.path);
      if (!mounted || vis.data == null) return;
      setState(() {
        _level = VisibilitySetting.levels.contains(vis.data!.level)
            ? vis.data!.level
            : VisibilitySetting.private;
        _allowStream = vis.data!.allowStream;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Who can see "${widget.name}"?',
              style: TextStyle(
                color: pal.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            for (final level in VisibilitySetting.levels)
              RadioListTile<String>(
                value: level,
                groupValue: _level,
                onChanged: _saving ? null : (v) => setState(() => _level = v!),
                title: Text(_title(level)),
                subtitle: Text(_subtitle(level)),
              ),
            SwitchListTile(
              value: _allowStream,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _allowStream = v),
              title: const Text('Allow viewing & playback'),
              subtitle: const Text(
                'Off means others see the entry but cannot open the file.',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(String level) => switch (level) {
    'public' => 'Public',
    'link' => 'Followers',
    _ => 'Private',
  };

  String _subtitle(String level) => switch (level) {
    'public' => 'Every signed-in user can see and open it.',
    'link' => 'Only people who follow you can see it.',
    _ => 'Only you can see it.',
  };

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await ref
        .read(timelineControllerProvider.notifier)
        .setVisibility(
          path: widget.path,
          level: _level,
          allowStream: _allowStream,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showGlassToast(context, 'Visibility updated');
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(timelineControllerProvider).error ??
                'Failed to update visibility',
          ),
        ),
      );
    }
  }
}
