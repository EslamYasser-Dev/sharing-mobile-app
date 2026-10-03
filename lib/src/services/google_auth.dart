import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../services/token_store.dart';

/// Google Sign-In service using official Google SDK with OIDC ID token validation.
class GoogleAuthService {
  GoogleAuthService({
    GoogleSignIn? googleSignIn,
    ApiClient? apiClient,
    TokenStore? tokenStore,
  })  : _googleSignIn = googleSignIn ?? _createDefaultGoogleSignIn(),
        _apiClient = apiClient ?? ApiClient(),
        _tokenStore = tokenStore ?? TokenStore();

  final GoogleSignIn _googleSignIn;
  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  static GoogleSignIn _createDefaultGoogleSignIn() {
    final serverClientId = googleServerClientId.isEmpty
        ? null
        : googleServerClientId;
    return GoogleSignIn(
      scopes: ['email', 'profile', 'openid'],
      signInOption: SignInOption.standard,
      serverClientId: serverClientId,
    );
  }

  /// Whether Google sign-in is configured (needs a server client ID for the
  /// ID-token audience the backend verifies).
  static bool get isConfigured => googleServerClientId.isNotEmpty;

  /// The OIDC ID token for [account]. NOTE: this is NOT `authHeaders` (that
  /// carries the OAuth access token); the JWT the backend verifies lives in
  /// `authentication.idToken`.
  Future<String?> _idToken(GoogleSignInAccount account) async {
    try {
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) return null;
      return idToken;
    } catch (_) {
      return null;
    }
  }

  /// Sign in with Google and exchange ID token for app access token.
  Future<GoogleAuthResult> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return GoogleAuthResult.cancelled();
      }

      final idToken = await _idToken(account);

      if (idToken == null || idToken.isEmpty) {
        return GoogleAuthResult.error('Failed to obtain ID token from Google');
      }

      // Validate ID token locally (basic checks)
      if (!_validateIdToken(idToken)) {
        return GoogleAuthResult.error('Invalid ID token format');
      }

      // Exchange ID token for app access token
      final exchangeResult = await _exchangeIdTokenForAccessToken(idToken);
      if (!exchangeResult.ok) {
        return GoogleAuthResult.error(exchangeResult.error ?? 'Token exchange failed');
      }

      // Store access token
      await _tokenStore.set(exchangeResult.accessToken!);

      // Fetch user profile
      final meResult = await _apiClient.me();
      if (!meResult.ok || meResult.data == null) {
        return GoogleAuthResult.error('Failed to load user profile after sign-in');
      }

      return GoogleAuthResult.success(
        accessToken: exchangeResult.accessToken!,
        user: meResult.data!,
        isNewAccount: exchangeResult.isNewAccount ?? false,
      );
    } on MissingPluginException {
      return GoogleAuthResult.error('Google sign-in is not available on this platform');
    } on Exception catch (e) {
      return GoogleAuthResult.error('Google Sign-In failed: $e');
    }
  }

  /// Sign in silently (for app restoration) if user previously signed in.
  Future<GoogleAuthResult?> trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return null;

      final idToken = await _idToken(account);

      if (idToken == null || idToken.isEmpty) return null;

      if (!_validateIdToken(idToken)) return null;

      final exchangeResult = await _exchangeIdTokenForAccessToken(idToken);
      if (!exchangeResult.ok) return null;

      await _tokenStore.set(exchangeResult.accessToken!);

      final meResult = await _apiClient.me();
      if (!meResult.ok || meResult.data == null) return null;

      return GoogleAuthResult.success(
        accessToken: exchangeResult.accessToken!,
        user: meResult.data!,
        isNewAccount: false,
      );
    } catch (e) {
      return null;
    }
  }

  /// Link Google account to existing username/password account.
  Future<GoogleAuthResult> linkGoogleAccount({
    required String username,
    required String password,
  }) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return GoogleAuthResult.cancelled();
      }

      final idToken = await _idToken(account);

      if (idToken == null || idToken.isEmpty) {
        return GoogleAuthResult.error('Failed to obtain ID token');
      }

      if (!_validateIdToken(idToken)) {
        return GoogleAuthResult.error('Invalid ID token');
      }

      // First authenticate with username/password to get current session
      final loginResult = await _apiClient.login(username, password);
      if (!loginResult.ok) {
        return GoogleAuthResult.error('Invalid username or password');
      }

      // Exchange Google ID token for linking
      final linkResult = await _linkGoogleAccount(idToken);
      if (!linkResult.ok) {
        return GoogleAuthResult.error(linkResult.error ?? 'Failed to link Google account');
      }

      return GoogleAuthResult.success(
        accessToken: linkResult.accessToken!,
        user: linkResult.user!,
        isNewAccount: false,
      );
    } catch (e) {
      return GoogleAuthResult.error('Linking failed: $e');
    }
  }

  /// Unlink Google account from current user.
  Future<GoogleAuthResult> unlinkGoogleAccount() async {
    try {
      final result = await _apiClient.unlinkGoogle();
      if (!result.ok) {
        return GoogleAuthResult.error(result.error ?? 'Failed to unlink Google account');
      }
      await _tokenStore.clear();
      return GoogleAuthResult.success(accessToken: '', user: null);
    } catch (e) {
      return GoogleAuthResult.error('Unlink failed: $e');
    }
  }

  /// Sign out from Google and clear local tokens.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on MissingPluginException {
      // google_sign_in has no Linux/desktop implementation — nothing to sign out of.
    }
    await _tokenStore.clear();
  }

  /// Exchange Google ID token for app access token.
  Future<TokenExchangeResult> _exchangeIdTokenForAccessToken(String idToken) async {
    try {
      final result = await _apiClient.exchangeGoogleToken(idToken);
      if (!result.ok) {
        return TokenExchangeResult.error(result.error ?? 'Token exchange failed');
      }
      return TokenExchangeResult.success(
        accessToken: result.data!.accessToken,
        user: result.data!.user,
        isNewAccount: result.data!.isNewAccount ?? false,
      );
    } catch (e) {
      return TokenExchangeResult.error('Token exchange failed: $e');
    }
  }

  /// Link Google account to existing authenticated session.
  Future<TokenExchangeResult> _linkGoogleAccount(String idToken) async {
    try {
      final result = await _apiClient.linkGoogleAccount(idToken);
      if (!result.ok) {
        return TokenExchangeResult.error(result.error ?? 'Link failed');
      }
      return TokenExchangeResult.success(
        accessToken: result.data!.accessToken,
        user: result.data!.user,
      );
    } catch (e) {
      return TokenExchangeResult.error('Link failed: $e');
    }
  }

  /// Basic ID token validation (format, not cryptographic verification).
  /// The server re-verifies signature, audience, issuer, and expiry.
  bool _validateIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) return false;

    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      // Check expiration
      final exp = payload['exp'] as int?;
      if (exp != null) {
        final expTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        if (expTime.isBefore(DateTime.now())) return false;
      }

      // Check issuer
      final iss = payload['iss'] as String?;
      if (iss != 'https://accounts.google.com' && iss != 'accounts.google.com') {
        return false;
      }

      // Check audience (should match our client ID)
      final aud = payload['aud'] as String?;
      if (aud == null || aud.isEmpty) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    // GoogleSignIn doesn't require explicit disposal
  }
}

class GoogleAuthResult {
  const GoogleAuthResult._({
    this.accessToken,
    this.user,
    this.isNewAccount,
    this.error,
    this.cancelled = false,
  });

  final String? accessToken;
  final AuthUser? user;
  final bool? isNewAccount;
  final String? error;
  final bool cancelled;

  bool get ok => error == null && !cancelled && accessToken != null;

  factory GoogleAuthResult.success({
    required String accessToken,
    AuthUser? user,
    bool isNewAccount = false,
  }) => GoogleAuthResult._(
    accessToken: accessToken,
    user: user,
    isNewAccount: isNewAccount,
  );

  factory GoogleAuthResult.error(String error) =>
      GoogleAuthResult._(error: error);

  factory GoogleAuthResult.cancelled() => GoogleAuthResult._(cancelled: true);
}

class TokenExchangeResult {
  const TokenExchangeResult._({
    this.accessToken,
    this.user,
    this.isNewAccount,
    this.error,
  });

  final String? accessToken;
  final AuthUser? user;
  final bool? isNewAccount;
  final String? error;

  bool get ok => error == null && accessToken != null;

  factory TokenExchangeResult.success({
    required String accessToken,
    AuthUser? user,
    bool isNewAccount = false,
  }) => TokenExchangeResult._(
    accessToken: accessToken,
    user: user,
    isNewAccount: isNewAccount,
  );

  factory TokenExchangeResult.error(String error) => TokenExchangeResult._(error: error);
}