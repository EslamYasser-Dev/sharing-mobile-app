export 'models/transfer.dart';
export 'models/peer.dart';

class FileItem {
  const FileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.isDir,
    required this.modified,
    this.mimeType,
    this.version,
  });

  final String name;
  final String path;
  final int size;
  final bool isDir;
  final String modified;
  final String? mimeType;
  final int? version;

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    isDir: json['isDir'] as bool? ?? false,
    modified: json['modified'] as String? ?? '',
    mimeType: json['mimeType'] as String?,
    version: (json['version'] as num?)?.toInt(),
  );
}

class AuthUser {
  const AuthUser({
    required this.username,
    required this.isAdmin,
    this.role,
    this.enabled,
    this.permissions,
    this.createdAt,
    this.quotaBytes,
    this.size,
    this.files,
  });

  final String username;
  final bool isAdmin;
  final String? role;
  final bool? enabled;
  final List<String>? permissions;
  final String? createdAt;
  final int? quotaBytes;
  final int? size;
  final int? files;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    username: json['username'] as String? ?? '',
    isAdmin: json['isAdmin'] as bool? ?? false,
    role: json['role'] as String?,
    enabled: json['enabled'] as bool?,
    permissions: (json['permissions'] as List?)
        ?.map((e) => e.toString())
        .toList(),
    createdAt: json['createdAt'] as String?,
    quotaBytes: (json['quotaBytes'] as num?)?.toInt(),
    size: (json['size'] as num?)?.toInt(),
    files: (json['files'] as num?)?.toInt(),
  );
}

class ShareItem {
  const ShareItem({
    required this.token,
    required this.path,
    required this.name,
    required this.owner,
    required this.createdAt,
    required this.expiresAt,
    this.passwordProtected = false,
    this.maxDownloads = 0,
    this.downloads = 0,
  });

  final String token;
  final String path;
  final String name;
  final String owner;
  final String createdAt;
  final String expiresAt;
  final bool passwordProtected;
  final int maxDownloads;
  final int downloads;

  bool get isLimited => maxDownloads > 0;
  int get remainingDownloads =>
      isLimited ? (maxDownloads - downloads).clamp(0, maxDownloads) : -1;

  factory ShareItem.fromJson(Map<String, dynamic> json) => ShareItem(
    token: json['token'] as String? ?? '',
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    owner: json['owner'] as String? ?? '',
    createdAt: json['createdAt'] as String? ?? '',
    expiresAt: json['expiresAt'] as String? ?? '',
    passwordProtected: json['passwordProtected'] as bool? ?? false,
    maxDownloads: (json['maxDownloads'] as num?)?.toInt() ?? 0,
    downloads: (json['downloads'] as num?)?.toInt() ?? 0,
  );
}

/// Per-file privacy setting. Absence on the server means private.
class VisibilitySetting {
  const VisibilitySetting({
    required this.owner,
    required this.path,
    required this.level,
    required this.allowStream,
    required this.updatedAt,
  });

  static const String private = 'private';
  static const String link = 'link';
  static const String pub = 'public';

  static const List<String> levels = [private, link, pub];

  final String owner;
  final String path;
  final String level;
  final bool allowStream;
  final String updatedAt;

  bool get isPrivate => level == private;
  bool get isLink => level == link;
  bool get isPublic => level == pub;

  factory VisibilitySetting.fromJson(Map<String, dynamic> json) =>
      VisibilitySetting(
        owner: json['owner'] as String? ?? '',
        path: json['path'] as String? ?? '',
        level: json['level'] as String? ?? private,
        allowStream: json['allowStream'] as bool? ?? false,
        updatedAt: json['updatedAt'] as String? ?? '',
      );
}

/// One upload-timeline feed entry: metadata only, never content.
class FeedEvent {
  const FeedEvent({
    required this.id,
    required this.owner,
    required this.kind,
    required this.path,
    required this.name,
    required this.size,
    required this.visibility,
    required this.createdAt,
  });

  final String id;
  final String owner;
  final String kind;
  final String path;
  final String name;
  final int size;
  final String visibility;
  final String createdAt;

  FeedEvent copyWith({String? visibility}) => FeedEvent(
    id: id,
    owner: owner,
    kind: kind,
    path: path,
    name: name,
    size: size,
    visibility: visibility ?? this.visibility,
    createdAt: createdAt,
  );

  factory FeedEvent.fromJson(Map<String, dynamic> json) => FeedEvent(
    id: json['id'] as String? ?? '',
    owner: json['owner'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    visibility: json['visibility'] as String? ?? VisibilitySetting.private,
    createdAt: json['createdAt'] as String? ?? '',
  );
}

/// One cursor page of the upload timeline.
class FeedPage {
  const FeedPage({required this.events, required this.nextCursor});

  final List<FeedEvent> events;
  final String nextCursor;

  bool get hasMore => nextCursor.isNotEmpty;
}

class TokenResponse {
  const TokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
  });

  final String accessToken;
  final String tokenType;
  final int expiresIn;

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    accessToken: json['accessToken'] as String? ?? '',
    tokenType: json['tokenType'] as String? ?? '',
    expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
  );
}

class GoogleTokenExchangeResponse {
  const GoogleTokenExchangeResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.user,
    this.isNewAccount,
  });

  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final AuthUser? user;
  final bool? isNewAccount;

  factory GoogleTokenExchangeResponse.fromJson(Map<String, dynamic> json) => GoogleTokenExchangeResponse(
    accessToken: json['accessToken'] as String? ?? '',
    tokenType: json['tokenType'] as String? ?? 'Bearer',
    expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
    user: json['user'] != null ? AuthUser.fromJson(json['user'] as Map<String, dynamic>) : null,
    isNewAccount: json['isNewAccount'] as bool?,
  );
}

class ServerEvent {
  const ServerEvent({required this.type, this.path, this.user, this.at});

  final String type;
  final String? path;
  final String? user;
  final String? at;

  factory ServerEvent.fromJson(Map<String, dynamic> json) => ServerEvent(
    type: json['type'] as String? ?? '',
    path: json['path'] as String?,
    user: json['user'] as String?,
    at: json['at'] as String?,
  );
}

class ApiResult<T> {
  const ApiResult({this.data, this.error, this.unauthorized = false});

  factory ApiResult.success(T? data) => ApiResult<T>(data: data);
  factory ApiResult.failure(String error) => ApiResult<T>(error: error);

  final T? data;
  final String? error;
  final bool unauthorized;

  bool get ok => error == null && !unauthorized;
}

/// One connected peer session, as reported by the signaling server.
class P2PPeer {
  const P2PPeer({required this.id, this.user});

  final String id;
  final String? user;

  factory P2PPeer.fromJson(Map<String, dynamic> json) =>
      P2PPeer(id: json['id'] as String? ?? '', user: json['user'] as String?);
}

/// The relayed frame kinds — the backend's `P2PSignal*` constants, plus the
/// call namespace (`P2PCall*`) which file-transfer sessions ignore.
enum P2PSignalKind {
  offer,
  answer,
  candidate,
  bye,
  callInvite,
  callAccept,
  callDecline,
  callEnd,
}

/// Maps a wire value onto [P2PSignalKind]; unknown kinds yield null so a
/// future backend addition is ignored rather than crashing the session.
P2PSignalKind? p2pSignalKindFrom(String raw) {
  switch (raw) {
    case 'offer':
      return P2PSignalKind.offer;
    case 'answer':
      return P2PSignalKind.answer;
    case 'candidate':
      return P2PSignalKind.candidate;
    case 'bye':
      return P2PSignalKind.bye;
    case 'call-invite':
      return P2PSignalKind.callInvite;
    case 'call-accept':
      return P2PSignalKind.callAccept;
    case 'call-decline':
      return P2PSignalKind.callDecline;
    case 'call-end':
      return P2PSignalKind.callEnd;
    default:
      return null;
  }
}

/// Wire value for an outgoing signal kind.
String p2pSignalKindToWire(P2PSignalKind kind) => switch (kind) {
      P2PSignalKind.offer => 'offer',
      P2PSignalKind.answer => 'answer',
      P2PSignalKind.candidate => 'candidate',
      P2PSignalKind.bye => 'bye',
      P2PSignalKind.callInvite => 'call-invite',
      P2PSignalKind.callAccept => 'call-accept',
      P2PSignalKind.callDecline => 'call-decline',
      P2PSignalKind.callEnd => 'call-end',
    };

/// One SDP/ICE/bye frame relayed between two peers. [payload] is opaque to
/// the app — an SDP description for offer/answer, an ICE candidate dict for
/// candidate — and is handed straight back to WebRTC.
class P2PSignalFrame {
  const P2PSignalFrame({
    required this.from,
    required this.to,
    required this.kind,
    this.payload,
  });

  final String from;
  final String to;
  final P2PSignalKind kind;
  final Object? payload;
}

/// One decoded `data:` payload from the `/api/p2p/stream` SSE stream.
class P2PFrame {
  const P2PFrame({
    required this.type,
    this.peerId,
    this.peers = const <P2PPeer>[],
    this.signal,
  });

  /// `hello`, `peers` or `signal`.
  final String type;
  final String? peerId;
  final List<P2PPeer> peers;
  final P2PSignalFrame? signal;
}

/// Decodes one SSE payload. Returns null when the frame carries nothing the
/// client can use (unknown signal kind, malformed signal).
P2PFrame? p2pFrameFromJson(Map<String, dynamic> json) {
  final rawSignal = json['signal'];
  final signal = rawSignal is Map<String, dynamic>
      ? p2pSignalFromJson(rawSignal)
      : null;
  if (rawSignal is Map<String, dynamic> && signal == null) return null;

  return P2PFrame(
    type: json['type'] as String? ?? '',
    peerId: json['peerId'] as String?,
    peers: [
      for (final peer in (json['peers'] as List<dynamic>? ?? const []))
        if (peer is Map<String, dynamic>) P2PPeer.fromJson(peer),
    ],
    signal: signal,
  );
}

P2PSignalFrame? p2pSignalFromJson(Map<String, dynamic> json) {
  final kind = p2pSignalKindFrom(json['kind'] as String? ?? '');
  if (kind == null) return null;
  return P2PSignalFrame(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    kind: kind,
    payload: json['payload'],
  );
}

/// A control frame sent over the data channel to bracket a file's bytes.
///
/// The channel carries interleaved JSON control frames and raw binary
/// chunks; `meta` opens a transfer, `end` completes it, `error` aborts it.
class P2PControlMessage {
  const P2PControlMessage({
    required this.type,
    this.id,
    this.name,
    this.size,
    this.mime,
  });

  /// `meta`, `end` or `error`.
  final String type;
  final String? id;
  final String? name;
  final int? size;
  final String? mime;

  Map<String, dynamic> toJson() => <String, dynamic>{
    't': type,
    if (id != null) 'id': id,
    if (name != null) 'name': name,
    if (size != null) 'size': size,
    if (mime != null) 'mime': mime,
  };

  factory P2PControlMessage.fromJson(Map<String, dynamic> json) =>
      P2PControlMessage(
        type: json['t'] as String? ?? '',
        id: json['id'] as String?,
        name: json['name'] as String?,
        size: (json['size'] as num?)?.toInt(),
        mime: json['mime'] as String?,
      );
}

enum P2PTransferStatus { connecting, active, done, error }

enum P2PTransferDirection { send, receive }

/// One file moving between two peers. Kept immutable — progress updates go
/// through [copyWith] so a transfer is cheap to rebuild in the UI.
class P2PTransfer {
  const P2PTransfer({
    required this.id,
    required this.peerId,
    required this.name,
    required this.size,
    required this.direction,
    this.peerLabel,
    this.loaded = 0,
    this.status = P2PTransferStatus.connecting,
    this.error,
    this.localPath,
  });

  final String id;
  final String peerId;
  final String? peerLabel;
  final String name;
  final int size;
  final int loaded;
  final P2PTransferStatus status;
  final P2PTransferDirection direction;
  final String? error;

  /// Where a received file was written, once it is complete.
  final String? localPath;

  /// Progress in `[0, 1]`, clamped so a late or duplicate update can never
  /// push the bar past full. A size of zero reports 0 until it completes, so
  /// a zero-byte file never renders as "done" at 0%.
  double get progress {
    if (size <= 0) return status == P2PTransferStatus.done ? 1 : 0;
    final value = loaded / size;
    if (value <= 0) return 0;
    if (value >= 1) return 1;
    return value;
  }

  /// Whether the transfer still needs bytes from the wire.
  bool get isComplete => status == P2PTransferStatus.done;

  P2PTransfer copyWith({
    int? loaded,
    P2PTransferStatus? status,
    String? error,
    String? localPath,
    String? peerLabel,
  }) {
    return P2PTransfer(
      id: id,
      peerId: peerId,
      name: name,
      size: size,
      direction: direction,
      peerLabel: peerLabel ?? this.peerLabel,
      loaded: loaded ?? this.loaded,
      status: status ?? this.status,
      error: error ?? this.error,
      localPath: localPath ?? this.localPath,
    );
  }
}
