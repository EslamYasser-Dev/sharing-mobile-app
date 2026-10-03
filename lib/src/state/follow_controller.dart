import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

final followControllerProvider =
    NotifierProvider<FollowController, FollowState>(FollowController.new);

class FollowState {
  const FollowState({
    this.following = const {},
    this.followers = const [],
    this.followingList = const [],
    this.profileUser,
    this.isLoading = false,
    this.error,
  });

  /// Usernames the signed-in user follows (as currently known).
  final Set<String> following;

  /// Last-loaded followers list (see [profileUser]).
  final List<String> followers;

  /// Last-loaded following list (see [profileUser]).
  final List<String> followingList;

  final String? profileUser;
  final bool isLoading;
  final String? error;

  FollowState copyWith({
    Set<String>? following,
    List<String>? followers,
    List<String>? followingList,
    String? profileUser,
    bool? isLoading,
    String? error,
  }) {
    return FollowState(
      following: following ?? this.following,
      followers: followers ?? this.followers,
      followingList: followingList ?? this.followingList,
      profileUser: profileUser ?? this.profileUser,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class FollowController extends Notifier<FollowState> {
  @override
  FollowState build() => const FollowState();

  bool isFollowing(String username) => state.following.contains(username);

  Future<void> refreshFollowing() async {
    final me = ref.read(authControllerProvider).user?.username;
    if (me == null || me.isEmpty) {
      state = state.copyWith(following: const {});
      return;
    }
    final result = await ref.read(apiClientProvider).listFollowing(me);
    if (result.data != null) {
      state = state.copyWith(following: result.data!.toSet(), error: null);
    } else {
      state = state.copyWith(error: result.error ?? 'Failed to load follows');
    }
  }

  Future<bool> checkFollowing(String username) async {
    if (state.following.contains(username)) return true;
    final result = await ref.read(apiClientProvider).isFollowing(username);
    final following = result.data ?? false;
    if (result.data != null && following) {
      state = state.copyWith(
        following: {...state.following, username},
        error: null,
      );
    }
    return following;
  }

  Future<bool> follow(String username) async {
    final previous = state.following;
    state = state.copyWith(
      following: {...previous, username},
      error: null,
    );
    final result = await ref.read(apiClientProvider).follow(username);
    if (result.data == true) return true;
    state = state.copyWith(
      following: previous,
      error: result.error ?? 'Failed to follow $username',
    );
    return false;
  }

  Future<bool> unfollow(String username) async {
    final previous = state.following;
    final next = {...previous}..remove(username);
    state = state.copyWith(following: next, error: null);
    final result = await ref.read(apiClientProvider).unfollow(username);
    if (result.error == null) return true;
    state = state.copyWith(
      following: previous,
      error: result.error ?? 'Failed to unfollow $username',
    );
    return false;
  }

  Future<void> loadProfileLists(String username) async {
    state = state.copyWith(isLoading: true, error: null, profileUser: username);
    final api = ref.read(apiClientProvider);
    final followers = await api.listFollowers(username);
    final following = await api.listFollowing(username);
    if (followers.data == null || following.data == null) {
      state = state.copyWith(
        isLoading: false,
        error: followers.error ?? following.error ?? 'Failed to load profile',
      );
      return;
    }
    state = state.copyWith(
      followers: followers.data!,
      followingList: following.data!,
      isLoading: false,
    );
  }
}
