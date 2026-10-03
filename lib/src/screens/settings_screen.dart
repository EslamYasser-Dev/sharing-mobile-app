import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models.dart';
import '../state/avatar_controller.dart';
import '../state/auth_controller.dart';
import '../state/nearby_controller.dart';
import '../state/nearby_enabled_controller.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _avatarBusy = false;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Settings', style: SfsTextStyles.title(pal)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: pal.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: auth.user == null
          ? Center(child: CircularProgressIndicator(color: pal.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildProfileSection(context, pal, auth),
                const SizedBox(height: 24),
                _buildAccountSection(pal, auth),
                const SizedBox(height: 24),
                _buildDiscoverabilitySection(pal),
                const SizedBox(height: 24),
                _buildSecuritySection(pal),
                const SizedBox(height: 24),
                _buildStorageSection(pal, auth),
                const SizedBox(height: 24),
                _buildAboutSection(pal),
              ],
            ),
    );
  }

  Widget _buildProfileSection(BuildContext context, SfsPalette pal, AuthState auth) {
    final avatarUrl = ref.watch(avatarControllerProvider).avatarUrl;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SfsGlass.of(pal).tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SfsGlass.of(pal).border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: pal.accentDim,
                    backgroundImage: avatarUrl != null
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null
                        ? Text(
                            auth.user!.username.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: pal.accent,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  AnimatedOpacity(
                    opacity: _avatarBusy ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_avatarBusy,
                      child: Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: CircularProgressIndicator(color: pal.onAccent, strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: pal.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.camera_alt, color: pal.onAccent, size: 18),
                        onPressed: _pickAndUploadAvatar,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user!.username,
                      style: TextStyle(
                        color: pal.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.user!.isAdmin ? 'Administrator' : 'Member',
                      style: TextStyle(color: pal.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _buildQuotaSection(context, pal, auth),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    }

  Widget _buildQuotaSection(BuildContext context, SfsPalette pal, AuthState auth) {
    final user = auth.user!;
    final quota = user.quotaBytes ?? 0;
    final used = user.size ?? 0;

    if (quota == 0) return const SizedBox.shrink();

    return Column(
      children: [
        LinearProgressIndicator(
          value: (used / quota).clamp(0.0, 1.0),
          minHeight: 4,
          backgroundColor: pal.surfaceOverlay,
          valueColor: AlwaysStoppedAnimation<Color>(
            used >= quota ? Colors.red : pal.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${formatBytes(used)} of ${formatBytes(quota)} used',
          style: TextStyle(color: pal.muted, fontSize: 11),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    setState(() => _avatarBusy = true);
    try {
      await ref.read(avatarControllerProvider.notifier).pickAndUploadAvatar();
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Widget _buildAccountSection(SfsPalette pal, AuthState auth) {
    return _buildSection(
      pal,
      'ACCOUNT',
      [
        ListTile(
          leading: Icon(Icons.email_outlined, color: pal.muted),
          title: Text('Email', style: TextStyle(color: pal.text)),
          subtitle: Text('Not set', style: TextStyle(color: pal.muted)),
          trailing: TextButton(
            onPressed: () => _showAddEmailDialog(),
            child: Text('Add', style: TextStyle(color: pal.accent)),
          ),
        ),
        ListTile(
          leading: Icon(Icons.lock_outline, color: pal.muted),
          title: Text('Password', style: TextStyle(color: pal.text)),
          subtitle: Text('Change password', style: TextStyle(color: pal.muted)),
          trailing: TextButton(
            onPressed: () => _showChangePasswordDialog(),
            child: Text('Change', style: TextStyle(color: pal.accent)),
          ),
        ),
        ListTile(
          leading: Icon(Icons.link_outlined, color: pal.muted),
          title: Text('Linked Accounts', style: TextStyle(color: pal.text)),
          subtitle: Text('Manage linked accounts', style: TextStyle(color: pal.muted)),
          trailing: TextButton(
            onPressed: () => _showLinkedAccountsDialog(),
            child: Text('Manage', style: TextStyle(color: pal.accent)),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverabilitySection(SfsPalette pal) {
    final nearby = ref.watch(nearbyControllerProvider);
    final controller = ref.read(nearbyControllerProvider.notifier);
    final enabled = ref.watch(nearbyEnabledProvider);

    return _buildSection(
      pal,
      'DISCOVERABILITY',
      [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SfsGlass.of(pal).tint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SfsGlass.of(pal).border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: (v) => ref
                    .read(nearbyEnabledProvider.notifier)
                    .set(v),
                title: Text(
                  'Nearby sharing',
                  style: TextStyle(
                    color: pal.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  enabled
                      ? 'Discovery, pairing, and direct transfer are on'
                      : 'Everything nearby is off: no discovery, pairing, or direct transfer',
                  style: TextStyle(color: pal.muted, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              Text('VISIBILITY', style: SfsTextStyles.eyebrow(pal)),
              const SizedBox(height: 12),
              Text(
                'Choose who can see your device on the local network',
                style: TextStyle(color: pal.muted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              _DiscoverabilitySelector(
                currentMode: nearby.discoverability,
                onChanged: enabled
                    ? (mode) => controller.setDiscoverability(mode)
                    : (_) {},
                pal: pal,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecuritySection(SfsPalette pal) {
    return _buildSection(
      pal,
      'SECURITY',
      [
        ListTile(
          leading: Icon(Icons.fingerprint, color: pal.muted),
          title: Text('Biometric Lock', style: TextStyle(color: pal.text)),
          subtitle: Text('Require biometric to open app', style: TextStyle(color: pal.muted)),
          trailing: Switch(
            value: false,
            onChanged: (value) {},
            activeColor: pal.accent,
          ),
        ),
        ListTile(
          leading: Icon(Icons.history_outlined, color: pal.muted),
          title: Text('Session History', style: TextStyle(color: pal.text)),
          subtitle: Text('View active sessions', style: TextStyle(color: pal.muted)),
          trailing: TextButton(
            onPressed: () => _showSessionHistoryDialog(),
            child: Text('View', style: TextStyle(color: pal.accent)),
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection(SfsPalette pal, AuthState auth) {
    final quota = auth.user?.quotaBytes ?? 0;
    final used = auth.user?.size ?? 0;

    return _buildSection(
      pal,
      'STORAGE',
      [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SfsGlass.of(pal).tint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SfsGlass.of(pal).border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StorageStat(
                      pal: pal,
                      label: 'Used',
                      value: formatBytes(auth.user?.size ?? 0),
                    ),
                  ),
                  Expanded(
                    child: _StorageStat(
                      pal: pal,
                      label: quota > 0 ? 'Quota' : 'Unlimited',
                      value: quota > 0 ? formatBytes(quota) : '∞',
                    ),
                  ),
                  Expanded(
                    child: _StorageStat(
                      pal: pal,
                      label: 'Files',
                      value: '${auth.user?.files ?? 0}',
                    ),
                  ),
                ],
              ),
              if (quota > 0) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (used / quota).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: pal.surfaceOverlay,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      used >= quota ? Colors.red : pal.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatBytes(used)} of ${formatBytes(quota)} used',
                  style: TextStyle(color: pal.muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        ListTile(
          leading: Icon(Icons.cleaning_services_outlined, color: pal.muted),
          title: Text('Clear Cache', style: TextStyle(color: pal.text)),
          subtitle: Text('Free up space', style: TextStyle(color: pal.muted)),
          trailing: TextButton(
            onPressed: () => _showClearCacheDialog(),
            child: Text('Clear', style: TextStyle(color: pal.accent)),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(SfsPalette pal) {
    return _buildSection(
      pal,
      'ABOUT',
      [
        ListTile(
          leading: Icon(Icons.info_outline, color: pal.muted),
          title: Text('Version', style: TextStyle(color: pal.text)),
          subtitle: Text('1.0.0+1', style: TextStyle(color: pal.muted)),
        ),
        ListTile(
          leading: Icon(Icons.description_outlined, color: pal.muted),
          title: Text('Licenses', style: TextStyle(color: pal.text)),
          trailing: TextButton(
            onPressed: () => _showLicenses(),
            child: Text('View', style: TextStyle(color: pal.accent)),
          ),
        ),
        ListTile(
          leading: Icon(Icons.privacy_tip_outlined, color: pal.muted),
          title: Text('Privacy Policy', style: TextStyle(color: pal.text)),
          trailing: TextButton(
            onPressed: () => _openUrl('https://example.com/privacy'),
            child: Text('View', style: TextStyle(color: pal.accent)),
          ),
        ),
        ListTile(
          leading: Icon(Icons.logout_outlined, color: pal.danger),
          title: Text('Sign Out', style: TextStyle(color: pal.danger)),
          onTap: () => _showSignOutDialog(),
        ),
      ],
    );
  }

  Widget _buildSection(SfsPalette pal, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SfsTextStyles.eyebrow(pal)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: SfsGlass.of(pal).tint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SfsGlass.of(pal).border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  void _showAddEmailDialog() {
    // TODO: Implement
  }

  void _showChangePasswordDialog() {
    // TODO: Implement
  }

  void _showLinkedAccountsDialog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: SfsPalette.of(context).card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: SfsPalette.of(context).muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red,
                child: Icon(Icons.g_mobiledata, color: Colors.white),
              ),
              title: Text('Google Account', style: TextStyle(color: SfsPalette.of(context).text, fontWeight: FontWeight.w600)),
              subtitle: Text('Linked via Google Sign-In', style: TextStyle(color: SfsPalette.of(context).muted, fontSize: 12)),
              trailing: TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(authControllerProvider.notifier).unlinkGoogleAccount();
                },
                child: Text('Unlink', style: TextStyle(color: SfsPalette.of(context).danger)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: SfsPalette.of(context).accent),
              title: Text('Link Google Account', style: TextStyle(color: SfsPalette.of(context).accent, fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                // TODO: Show link dialog
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSessionHistoryDialog() {
    // TODO: Implement
  }

  void _showClearCacheDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SfsPalette.of(context).card,
        title: Text('Clear Cache', style: SfsTextStyles.title(SfsPalette.of(context))),
        content: Text('This will clear temporary files and cached data. Your files and settings will not be affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: SfsPalette.of(context).muted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cache cleared'), backgroundColor: SfsPalette.of(context).accent),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SfsPalette.of(context).card,
        title: Text('Sign Out', style: SfsTextStyles.title(SfsPalette.of(context))),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: SfsPalette.of(context).muted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authControllerProvider.notifier).signOut();
            },
            style: FilledButton.styleFrom(backgroundColor: SfsPalette.of(context).danger),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showLicenses() {
    showLicensePage(context: context);
  }

  void _openUrl(String url) {
    // TODO: Implement url_launcher
  }
}

class _StorageStat extends StatelessWidget {
  const _StorageStat({
    required this.pal,
    required this.label,
    required this.value,
  });

  final SfsPalette pal;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: SfsTextStyles.eyebrow(pal)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: pal.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DiscoverabilitySelector extends StatelessWidget {
  const _DiscoverabilitySelector({
    required this.currentMode,
    required this.onChanged,
    required this.pal,
  });

  final DiscoverabilityMode currentMode;
  final ValueChanged<DiscoverabilityMode> onChanged;
  final SfsPalette pal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: DiscoverabilityMode.values.map((mode) {
        return RadioListTile<DiscoverabilityMode>(
          value: mode,
          groupValue: currentMode,
          onChanged: (value) => onChanged(value!),
          title: Text(
            _getModeLabel(mode),
            style: TextStyle(color: pal.text, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            _getModeDescription(mode),
            style: TextStyle(color: pal.muted, fontSize: 12),
          ),
          activeColor: pal.accent,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
      }).toList(),
    );
  }

  String _getModeLabel(DiscoverabilityMode mode) {
    switch (mode) {
      case DiscoverabilityMode.everyone:
        return 'Everyone';
      case DiscoverabilityMode.contacts:
        return 'Contacts Only';
      case DiscoverabilityMode.hidden:
        return 'Hidden';
    }
  }

  String _getModeDescription(DiscoverabilityMode mode) {
    switch (mode) {
      case DiscoverabilityMode.everyone:
        return 'Visible to all nearby devices on the network';
      case DiscoverabilityMode.contacts:
        return 'Only visible to approved/trusted contacts';
      case DiscoverabilityMode.hidden:
        return 'Not discoverable by other devices';
    }
  }
}