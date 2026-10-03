import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference key for the nearby-sharing master switch. On means LAN
/// discovery (mDNS), pairing, and WebRTC direct transfer may run; off stops
/// all of them and blocks restarts until re-enabled.
const String kNearbyEnabledKey = 'fs_nearby_enabled';

class NearbyEnabledController extends Notifier<bool> {
  /// Set once the user has chosen, so a slow restore cannot clobber it.
  bool _userChose = false;

  @override
  bool build() {
    unawaited(_restore());
    return true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userChose) return;
    final restored = prefs.getBool(kNearbyEnabledKey) ?? true;
    if (restored != state) state = restored;
  }

  Future<void> set(bool enabled) async {
    _userChose = true;
    if (enabled != state) state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kNearbyEnabledKey, enabled);
  }
}

final nearbyEnabledProvider =
    NotifierProvider<NearbyEnabledController, bool>(
      NearbyEnabledController.new,
    );
