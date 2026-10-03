import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/models.dart';
import 'package:simplefileshare/src/state/timeline_controller.dart';

void main() {
  group('ShareItem policy fields', () {
    test('default to public unlimited for old payloads', () {
      final item = ShareItem.fromJson({'token': 't'});
      expect(item.passwordProtected, isFalse);
      expect(item.maxDownloads, 0);
      expect(item.downloads, 0);
      expect(item.isLimited, isFalse);
      expect(item.remainingDownloads, -1);
    });

    test('limited link reports remaining budget', () {
      const item = ShareItem(
        token: 't',
        path: 'p',
        name: 'n',
        owner: 'o',
        createdAt: '',
        expiresAt: '',
        passwordProtected: true,
        maxDownloads: 3,
        downloads: 1,
      );
      expect(item.isLimited, isTrue);
      expect(item.remainingDownloads, 2);
    });
  });

  group('VisibilitySetting', () {
    test('unknown level parses without throwing', () {
      final vis = VisibilitySetting.fromJson({'level': 'everyone'});
      expect(vis.isPrivate, isFalse);
      expect(vis.isLink, isFalse);
      expect(vis.isPublic, isFalse);
    });

    test('level helpers match the three supported states', () {
      for (final level in VisibilitySetting.levels) {
        final vis = VisibilitySetting(
          owner: 'o',
          path: 'p',
          level: level,
          allowStream: true,
          updatedAt: '',
        );
        expect(vis.isPrivate, level == VisibilitySetting.private);
        expect(vis.isLink, level == VisibilitySetting.link);
        expect(vis.isPublic, level == VisibilitySetting.pub);
      }
    });
  });

  group('FeedEvent', () {
    test('copyWith patches visibility only', () {
      const event = FeedEvent(
        id: '1',
        owner: 'alice',
        kind: 'upload',
        path: 'a.txt',
        name: 'a.txt',
        size: 5,
        visibility: 'private',
        createdAt: '',
      );
      final patched = event.copyWith(visibility: 'public');
      expect(patched.visibility, 'public');
      expect(patched.id, '1');
      expect(patched.size, 5);
    });
  });

  group('TimelineState.filtered', () {
    const events = [
      FeedEvent(
        id: '1',
        owner: 'alice',
        kind: 'upload',
        path: 'a.txt',
        name: 'a.txt',
        size: 1,
        visibility: 'public',
        createdAt: '',
      ),
      FeedEvent(
        id: '2',
        owner: 'bob',
        kind: 'upload',
        path: 'b.txt',
        name: 'b.txt',
        size: 2,
        visibility: 'link',
        createdAt: '',
      ),
    ];

    test('mine keeps only own entries', () {
      const state = TimelineState(
        events: events,
        filter: TimelineFilter.mine,
      );
      final filtered = state.filtered('alice');
      expect(filtered.map((e) => e.id), ['1']);
    });

    test('following keeps others entries', () {
      const state = TimelineState(
        events: events,
        filter: TimelineFilter.following,
      );
      final filtered = state.filtered('alice');
      expect(filtered.map((e) => e.id), ['2']);
    });

    test('anonymous viewer sees nothing under scoped filters', () {
      const mine = TimelineState(events: events, filter: TimelineFilter.mine);
      const following = TimelineState(
        events: events,
        filter: TimelineFilter.following,
      );
      expect(mine.filtered(null), isEmpty);
      expect(following.filtered(''), isEmpty);
    });
  });

  group('FeedPage', () {
    test('hasMore follows the cursor', () {
      expect(
        const FeedPage(events: [], nextCursor: 'abc').hasMore,
        isTrue,
      );
      expect(const FeedPage(events: [], nextCursor: '').hasMore, isFalse);
    });
  });
}
