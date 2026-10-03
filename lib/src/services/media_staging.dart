import 'dart:io';

import 'viewer_gate.dart';
import 'api_client.dart';

/// Thrown when the owner's privacy setting forbids playback for this viewer.
class MediaGateDenied implements Exception {
  const MediaGateDenied();
}

/// Gate + download a media file into a temp file for in-app playback.
///
/// Owners stream directly; anyone else is gated on a fetched visibility
/// setting (link/public + streaming allowed) before a single byte is
/// downloaded. The server re-checks the gate on every byte served, so this
/// client check is UX-only. Throws [MediaGateDenied] or [StateError].
Future<File> stageMediaForPlayback({
  required ApiClient api,
  required String owner,
  required String path,
  required bool isOwner,
  void Function(int received)? onProgress,
}) async {
  if (!isOwner) {
    final vis = await api.getVisibility(owner: owner, path: path);
    if (!canPlayMedia(isOwner: false, setting: vis.data)) {
      throw const MediaGateDenied();
    }
  }
  final result = isOwner
      ? await api.download(path, onProgress: onProgress)
      : await api.downloadShared(
          owner: owner,
          path: path,
          onProgress: onProgress,
        );
  final file = result.data?.file;
  if (file == null) {
    throw StateError(result.error ?? 'Download failed');
  }
  return file;
}
