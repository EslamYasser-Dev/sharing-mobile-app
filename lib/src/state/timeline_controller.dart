import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'auth_controller.dart';

final timelineControllerProvider =
    NotifierProvider<TimelineController, TimelineState>(
      TimelineController.new,
    );

enum TimelineFilter { all, mine, following }

class TimelineState {
  const TimelineState({
    this.events = const [],
    this.cursor = '',
    this.hasMore = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.filter = TimelineFilter.all,
  });

  final List<FeedEvent> events;
  final String cursor;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final TimelineFilter filter;

  List<FeedEvent> filtered(String? me) {
    switch (filter) {
      case TimelineFilter.mine:
        if (me == null || me.isEmpty) return const [];
        return events.where((e) => e.owner == me).toList();
      case TimelineFilter.following:
        if (me == null || me.isEmpty) return const [];
        return events.where((e) => e.owner != me).toList();
      case TimelineFilter.all:
        return events;
    }
  }

  TimelineState copyWith({
    List<FeedEvent>? events,
    String? cursor,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    TimelineFilter? filter,
  }) {
    return TimelineState(
      events: events ?? this.events,
      cursor: cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
      filter: filter ?? this.filter,
    );
  }
}

class TimelineController extends Notifier<TimelineState> {
  static const int _pageSize = 20;

  @override
  TimelineState build() => const TimelineState();

  void setFilter(TimelineFilter filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
  }

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    // Belt and braces: any unexpected throw still lands in the error state
    // with a retry button — the spinner can never stick forever.
    try {
      final result = await ref
          .read(apiClientProvider)
          .listFeed(limit: _pageSize);
      final page = result.data;
      if (page == null) {
        state = state.copyWith(
          isLoading: false,
          error: result.error ?? 'Failed to load timeline',
        );
        return;
      }
      state = state.copyWith(
        events: page.events,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load timeline',
      );
    }
  }

  Future<void> refresh() async {
    try {
      final result = await ref
          .read(apiClientProvider)
          .listFeed(limit: _pageSize);
      final page = result.data;
      if (page == null) {
        state = state.copyWith(error: result.error ?? 'Failed to refresh');
        return;
      }
      state = state.copyWith(
        events: page.events,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        error: null,
      );
    } catch (_) {
      state = state.copyWith(error: 'Failed to refresh');
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final result = await ref
          .read(apiClientProvider)
          .listFeed(cursor: state.cursor, limit: _pageSize);
      final page = result.data;
      if (page == null) {
        state = state.copyWith(
          isLoadingMore: false,
          error: result.error ?? 'Failed to load more',
        );
        return;
      }
      final seen = state.events.map((e) => e.id).toSet();
      state = state.copyWith(
        events: [
          ...state.events,
          for (final e in page.events)
            if (!seen.contains(e.id)) e,
        ],
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingMore: false,
        error: 'Failed to load more',
      );
    }
  }

  /// Re-scopes one file, then patches matching feed entries with the new
  /// level so the UI reflects the change without a full reload.
  Future<bool> setVisibility({
    required String path,
    required String level,
    required bool allowStream,
  }) async {
    final result = await ref
        .read(apiClientProvider)
        .setVisibility(path: path, level: level, allowStream: allowStream);
    final vis = result.data;
    if (vis == null) {
      state = state.copyWith(
        error: result.error ?? 'Failed to update visibility',
      );
      return false;
    }
    state = state.copyWith(
      events: [
        for (final e in state.events)
          if (e.owner == vis.owner && e.path == vis.path)
            e.copyWith(visibility: vis.level)
          else
            e,
      ],
      error: null,
    );
    return true;
  }
}
