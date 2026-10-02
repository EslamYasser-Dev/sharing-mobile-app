import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference key. The web client writes the same key to `localStorage`, so
/// every client agrees on the name — an unknown value (the web only stores
/// `light`/`dark`) simply falls back to following the system.
const String kThemePreferenceKey = 'fs_theme';

/// Parses a persisted theme name. Anything unrecognised follows the system.
ThemeMode themeModeFromStorage(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

class ThemeModeController extends Notifier<ThemeMode> {
  /// Set once the user has chosen, so a slow restore cannot clobber it.
  bool _userChose = false;

  @override
  ThemeMode build() {
    unawaited(_restore());
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userChose) return;
    final restored = themeModeFromStorage(prefs.getString(kThemePreferenceKey));
    if (restored != state) state = restored;
  }

  Future<void> set(ThemeMode mode) async {
    _userChose = true;
    if (mode != state) state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemePreferenceKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
