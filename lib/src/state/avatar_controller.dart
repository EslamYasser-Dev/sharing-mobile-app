import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../services/avatar_service.dart';
import '../services/token_store.dart';
import '../state/auth_controller.dart';

class AvatarController extends Notifier<AvatarState> {
  late final AvatarService _avatarService;

  @override
  AvatarState build() {
    _avatarService = ref.read(avatarServiceProvider);
    return const AvatarState();
  }

  Future<void> pickAndUploadAvatar({ImageSource source = ImageSource.gallery}) async {
    state = state.copyWith(busy: true, error: null);

    try {
      final picked = await _avatarService.pickImage(source: source);
      if (picked == null) {
        state = state.copyWith(busy: false);
        return;
      }

      final processed = await _avatarService.processAvatar(picked);
      final token = await _getAccessToken();
      if (token == null) throw AvatarException('Not authenticated');

      final result = await _avatarService.uploadAvatar(avatar: processed, accessToken: token);

      state = state.copyWith(
        busy: false,
        avatarUrl: result.url,
        thumbnailUrl: result.thumbnailUrl,
        error: null,
      );
    } on AvatarException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } catch (e) {
      state = state.copyWith(busy: false, error: 'Failed to upload avatar: $e');
    }
  }

  Future<void> removeAvatar() async {
    state = state.copyWith(busy: true, error: null);

    try {
      final token = await _getAccessToken();
      if (token == null) throw AvatarException('Not authenticated');

      await _avatarService.deleteAvatar(token);

      state = state.copyWith(
        busy: false,
        avatarUrl: null,
        thumbnailUrl: null,
        error: null,
      );
    } on AvatarException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } catch (e) {
      state = state.copyWith(busy: false, error: 'Failed to remove avatar: $e');
    }
  }

  void setAvatarUrl(String url) {
    state = state.copyWith(avatarUrl: url);
  }

  void setThumbnailUrl(String url) {
    state = state.copyWith(thumbnailUrl: url);
  }

  Future<String?> _getAccessToken() async {
    return ref.read(tokenStoreProvider).get();
  }
}

class AvatarState {
  const AvatarState({
    this.avatarUrl,
    this.thumbnailUrl,
    this.error,
    this.busy = false,
  });

  final String? avatarUrl;
  final String? thumbnailUrl;
  final String? error;
  final bool busy;

  AvatarState copyWith({
    String? avatarUrl,
    String? thumbnailUrl,
    String? error,
    bool? busy,
  }) {
    return AvatarState(
      avatarUrl: avatarUrl ?? this.avatarUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      error: error ?? this.error,
      busy: busy ?? this.busy,
    );
  }
}

final avatarServiceProvider = Provider<AvatarService>((ref) {
  final service = AvatarService(
    baseUrl: apiBaseUrl,
  );
  ref.onDispose(service.dispose);
  return service;
});

final avatarControllerProvider = NotifierProvider<AvatarController, AvatarState>(
  AvatarController.new,
);