import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_controller.dart';
import '../theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(authControllerProvider.notifier)
        .signIn(username, password);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = err;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: pal.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pal.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Landing logo mark: accent glyph in an accent-dim box
                  // outlined with paper/25.
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: pal.accentDim,
                        border: Border.all(color: pal.secondaryBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        color: pal.accent,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        color: pal.text,
                        fontSize: 21,
                        height: 1.15,
                        letterSpacing: -0.4,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(text: 'File'),
                        TextSpan(
                          text: 'Share',
                          style: TextStyle(color: pal.accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to access your files',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Container(height: 1, color: pal.rule),
                  const SizedBox(height: 20),
                  const _FieldLabel('Username'),
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  const _FieldLabel('Password'),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(hintText: 'Password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: pal.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'OAuth sign-in is available on the web app. '
                    'Use a username and password here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: pal.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Text(text.toUpperCase(), style: SfsTextStyles.label(pal));
  }
}
