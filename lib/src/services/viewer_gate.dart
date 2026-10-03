import '../models.dart';

/// In-app viewer kind for a file name. Mirrors the web client's
/// `viewerKindFor` for the media types the app can actually render; audio,
/// PDF, and text fall through to [ViewerKind.none] until they get players.
enum ViewerKind { image, video, none }

const _imageExts = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'ico',
};

const _videoExts = {'mp4', 'webm'};

ViewerKind viewerKindFor(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return ViewerKind.none;
  final ext = name.substring(dot + 1).toLowerCase();
  if (_imageExts.contains(ext)) return ViewerKind.image;
  if (_videoExts.contains(ext)) return ViewerKind.video;
  return ViewerKind.none;
}

/// Client-side playback gate: owners always pass; anyone else needs a
/// fetched [VisibilitySetting] that is link- or public-scoped with streaming
/// allowed. This is UX-only — the server re-checks on every byte served.
bool canPlayMedia({required bool isOwner, required VisibilitySetting? setting}) {
  if (isOwner) return true;
  if (setting == null) return false;
  return !setting.isPrivate && setting.allowStream;
}
