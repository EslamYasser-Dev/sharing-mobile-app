import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/models.dart';
import 'package:simplefileshare/src/services/viewer_gate.dart';

void main() {
  group('viewerKindFor', () {
    test('maps image extensions case-insensitively', () {
      expect(viewerKindFor('photo.JPG'), ViewerKind.image);
      expect(viewerKindFor('pic.webp'), ViewerKind.image);
      expect(viewerKindFor('anim.gif'), ViewerKind.image);
    });

    test('maps video extensions', () {
      expect(viewerKindFor('clip.mp4'), ViewerKind.video);
      expect(viewerKindFor('clip.webm'), ViewerKind.video);
    });

    test('rejects unplayable names', () {
      expect(viewerKindFor('song.mp3'), ViewerKind.none);
      expect(viewerKindFor('doc.pdf'), ViewerKind.none);
      expect(viewerKindFor('noext'), ViewerKind.none);
      expect(viewerKindFor('trailing.'), ViewerKind.none);
    });
  });

  group('canPlayMedia', () {
    test('owner always passes without a setting', () {
      expect(canPlayMedia(isOwner: true, setting: null), isTrue);
    });

    test('stranger needs link/public plus streaming', () {
      VisibilitySetting setting(String level, bool stream) =>
          VisibilitySetting(
            owner: 'alice',
            path: 'a.mp4',
            level: level,
            allowStream: stream,
            updatedAt: '',
          );
      expect(
        canPlayMedia(isOwner: false, setting: null),
        isFalse,
      );
      expect(
        canPlayMedia(
          isOwner: false,
          setting: setting(VisibilitySetting.private, true),
        ),
        isFalse,
      );
      expect(
        canPlayMedia(
          isOwner: false,
          setting: setting(VisibilitySetting.link, false),
        ),
        isFalse,
      );
      expect(
        canPlayMedia(
          isOwner: false,
          setting: setting(VisibilitySetting.link, true),
        ),
        isTrue,
      );
      expect(
        canPlayMedia(
          isOwner: false,
          setting: setting(VisibilitySetting.pub, true),
        ),
        isTrue,
      );
    });
  });
}
