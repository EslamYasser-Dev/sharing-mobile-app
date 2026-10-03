import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/models.dart';
import 'package:simplefileshare/src/services/api_client.dart';
import 'package:simplefileshare/src/state/auth_controller.dart';
import 'package:simplefileshare/src/state/timeline_controller.dart';

class _ThrowingApi extends ApiClient {
  @override
  Future<ApiResult<FeedPage>> listFeed({String cursor = '', int limit = 20}) {
    throw StateError('connection exploded');
  }
}

class _EmptyApi extends ApiClient {
  @override
  Future<ApiResult<FeedPage>> listFeed({String cursor = '', int limit = 20}) async {
    return const ApiResult<FeedPage>(
      data: FeedPage(events: [], nextCursor: ''),
    );
  }
}

ProviderContainer _container(ApiClient api) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('unexpected throw lands in error state, never stuck loading', () async {
    final container = _container(_ThrowingApi());
    final notifier = container.read(timelineControllerProvider.notifier);
    await notifier.loadInitial();
    final state = container.read(timelineControllerProvider);
    expect(state.isLoading, isFalse);
    expect(state.error, isNotNull);
  });

  test('empty feed resolves to empty, not loading', () async {
    final container = _container(_EmptyApi());
    final notifier = container.read(timelineControllerProvider.notifier);
    await notifier.loadInitial();
    final state = container.read(timelineControllerProvider);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.events, isEmpty);
  });
}
