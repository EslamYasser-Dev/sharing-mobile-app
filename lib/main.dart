import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/screens/auth_gate.dart';
import 'src/state/theme_controller.dart';
import 'src/theme.dart';

void main() {
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
