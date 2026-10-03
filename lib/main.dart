import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'src/screens/auth_gate.dart';
import 'src/state/theme_controller.dart';
import 'src/theme.dart';

void main() {
  // Desktop has no sqflite platform plugin: drive the global database factory
  // with FFI before any provider touches TransferPersistence. Mobile keeps
  // the native plugin (do not set the factory there).
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const ProviderScope(child: FileShareApp()));
}

class FileShareApp extends ConsumerWidget {
  const FileShareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'File Share',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}
