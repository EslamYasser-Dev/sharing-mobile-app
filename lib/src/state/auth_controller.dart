import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/events_service.dart';
import '../services/grpc_connection.dart';
import '../services/token_store.dart';
import '../services/google_auth.dart';
import 'p2p_controller.dart';

enum AuthStatus { loading, signedOut, signedIn }

class AuthState {
  const AuthState(this.status, [this.user]);

  final AuthStatus status;
  final AuthUser? user;
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final grpcConnectionProvider = Provider<GrpcConnection>((ref) {
  final connection = GrpcConnection();
  ref.onDispose(connection.shutdown);
  return connection;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(connection: ref.watch(grpcConnectionProvider)),
);

final eventsServiceProvider = Provider<EventsService>((ref) {
  final service = EventsService(connection: ref.watch(grpcConnectionProvider));
  ref.onDispose(service.dispose);
  return service;
});

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  final service = GoogleAuthService(
    apiClient: ref.read(apiClientProvider),
    tokenStore: ref.read(tokenStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final api = ref.read(apiClientProvider);
    api.onUnauthorized = () {
      ref.read(eventsServiceProvider).stop();
      ref.read(p2pControllerProvider.notifier).stop();
      state = const AuthState(AuthStatus.signedOut);
    };
    unawaited(_restore());
    return const AuthState(AuthStatus.loading);
  }

  Future<void> _restore() async {
    final token = await ref.read(tokenStoreProvider).get();
    if (token == null) {
      // Try silent Google sign-in
      final googleAuth = ref.read(googleAuthServiceProvider);
      final silentResult = await googleAuth.trySilentSignIn();
      if (silentResult != null && silentResult.ok) {
        state = AuthState(AuthStatus.signedIn, silentResult.user);
        ref.read(eventsServiceProvider).start();
        ref.read(p2pControllerProvider.notifier).start();
      } else {
        state = const AuthState(AuthStatus.signedOut);
      }
      return;
    }
    final res = await ref.read(apiClientProvider).me();
    if (res.data != null) {
      state = AuthState(AuthStatus.signedIn, res.data);
      ref.read(eventsServiceProvider).start();
      ref.read(p2pControllerProvider.notifier).start();
    } else {
      state = const AuthState(AuthStatus.signedOut);
    }
  }

  Future<String?> signIn(String username, String password) async {
    final api = ref.read(apiClientProvider);
    final login = await api.login(username, password);
    if (!login.ok || login.data == null) {
      return login.error ?? 'Sign-in failed';
    }
    final me = await api.me();
    if (!me.ok || me.data == null) {
      return me.error ?? 'Unable to load account';
    }
    state = AuthState(AuthStatus.signedIn, me.data);
    ref.read(eventsServiceProvider).start();
    ref.read(p2pControllerProvider.notifier).start();
    return null;
  }

  Future<void> signOut() async {
    ref.read(eventsServiceProvider).stop();
    ref.read(p2pControllerProvider.notifier).stop();
    await ref.read(apiClientProvider).revoke();
    await ref.read(googleAuthServiceProvider).signOut();
    state = const AuthState(AuthStatus.signedOut);
  }

  Future<String?> signInWithGoogle() async {
    final googleAuth = ref.read(googleAuthServiceProvider);
    final result = await googleAuth.signInWithGoogle();
    if (!result.ok) {
      return result.error ?? 'Google sign-in failed';
    }
    state = AuthState(AuthStatus.signedIn, result.user);
    ref.read(eventsServiceProvider).start();
    ref.read(p2pControllerProvider.notifier).start();
    return null;
  }

  Future<String?> linkGoogleAccount({
    required String username,
    required String password,
  }) async {
    final googleAuth = ref.read(googleAuthServiceProvider);
    final result = await googleAuth.linkGoogleAccount(username: username, password: password);
    if (!result.ok) {
      return result.error ?? 'Failed to link Google account';
    }
    state = AuthState(AuthStatus.signedIn, result.user);
    return null;
  }

  Future<String?> unlinkGoogleAccount() async {
    final googleAuth = ref.read(googleAuthServiceProvider);
    final result = await googleAuth.unlinkGoogleAccount();
    if (!result.ok) {
      return result.error ?? 'Failed to unlink Google account';
    }
    state = const AuthState(AuthStatus.signedOut);
    return null;
  }

  Future<void> refreshUser() async {
    final res = await ref.read(apiClientProvider).me();
    if (res.data != null && state.status == AuthStatus.signedIn) {
      state = AuthState(AuthStatus.signedIn, res.data);
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
