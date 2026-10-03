This is a Flutter mobile application. Prioritize mobile-first patterns, performance, and cross-platform compatibility.

## Flutter — verify before you write

Flutter and package APIs change across releases. Before writing code that touches Flutter, Riverpod, grpc, or any plugin API:

1. Read the versions in `pubspec.yaml` / `pubspec.lock`.
2. Check the local package source when unsure: `~/.pub-cache/hosted/pub.dev/<package>-<version>/lib/`.
3. Prefer `dart doc` / the package README over memory for plugin APIs (file_picker, share_plus, flutter_secure_storage, flutter_webrtc, video_player, google_sign_in, permission_handler).

## Commands

The Flutter SDK lives at `~/flutter` (add `export PATH="$HOME/flutter/bin:$PATH"` if the shell has no `flutter`).

```bash
flutter pub get          # install dependencies
flutter run              # run on a device/emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000   # target a specific API
flutter analyze          # static analysis (lint) — MUST be clean
flutter test             # unit tests — MUST pass
flutter test --dart-define=RUN_GRPC_IT=1   # integration test (needs a backend on localhost:3000)
dart run flutter_launcher_icons   # regenerate launcher icons from assets/
flutter build apk --debug          # debug APK
flutter build linux --debug         # Linux desktop build
```

Run `flutter analyze` and `flutter test` before declaring any task done. There is no Android SDK on this machine — analyze + test are the verification floor; never claim an emulator run.

## Architecture

- **State**: Riverpod 3 (`flutter_riverpod`). Notifier/NotifierProvider for stateful controllers, Provider for services, `ConsumerWidget`/`ConsumerStatefulWidget` for widgets. Providers live in `lib/src/state/`.
- **Services** (`lib/src/services/`): `grpc_connection.dart` (lazy `ClientChannel` with pinned TLS cert + generated service clients exposed as async getters), `api_client.dart` (gRPC wrapper: bearer metadata, `ApiResult` mapping, client-stream upload, stream download, HTTP helpers for search/thumbs/view), `events_service.dart` (gRPC `Subscribe` stream with reconnect backoff), `token_store.dart` (flutter_secure_storage wrapper), `p2p_signaling.dart` (pure SSE byte parser + typed `P2PFrame` mapping), `p2p_session.dart` (one `RTCPeerConnection` per peer for file transfer), `call_session.dart` (one `RTCPeerConnection` per peer for voice/video calls), `call_config.dart` (ICE/media config + route detection), `google_auth.dart` (Google Sign-In OIDC flow), `viewer_gate.dart` (pure media access control), `haptics.dart` (tactile feedback).
- **Widgets** (`lib/src/widgets/`): `aurora_background.dart` (slow-drifting aurora wash), `motion.dart` (GlassCard, StaggerList, ShimmerSkeleton, showSpringSheet, glassPageRoute, showGlassToast).
- **Screens** (`lib/src/screens/`): auth gate → login (password + Google) or home shell (IndexedStack with files/shares/transfers/timeline/direct/account tabs). Call overlays mount above the shell.
- **Models/format helpers** in `lib/src/models.dart` and `lib/src/format.dart`; keep them pure — they are unit-tested in `test/`.
- **Generated stubs** live in `lib/src/grpc/` (from `backend/api/proto/`) — never hand-edit; regenerate with `protoc` + `protoc-gen-dart`.
- Config is compile-time: `String.fromEnvironment(...)` for `API_BASE_URL`, `GRPC_HOST`, `GRPC_PORT`, `GOOGLE_SERVER_CLIENT_ID`, `STUN_URL`, `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL`. Defaults in `config.dart` are the only baked-in endpoints.

## Rules

- Token storage key is `fs_access_token` — matches the other clients; do not rename it.
- Any gRPC `unauthenticated` status must clear the token and flip auth state to signed-out (wired through `ApiClient.onUnauthorized`).
- Events use gRPC `EventsService.Subscribe` (authenticated bearer metadata) and must reconnect with exponential backoff (1s → 30s); mapping is isolated in the pure `serverEventFromProto` function — keep it testable.
- Uploads are one gRPC client stream (metadata message first, then 256 KiB `chunk` messages); downloads are a server stream (filename on the first chunk). Unary calls carry a 30s timeout; streams carry none.
- Service clients are async: `(await connection.auth).login(...)`. The channel is created lazily on first use. Secure targets fetch `GET /api/grpc/cert` over HTTPS and pass it as `onBadCertificate`, so the channel accepts exactly that certificate **in addition to** the system trust store (`ChannelCredentials.secure(onBadCertificate: ...)`). Never use `certificates:` — it removes system roots and still enforces hostname checks, which the backend's self-signed `localhost` certificate can never satisfy on a proxy host. Never construct a `ClientChannel` directly outside `grpc_connection.dart`.
- A failed channel open must not poison later calls: `_pendingChannel` is cleared on error so the next attempt redials.
- OAuth sign-in uses the browser session cookie flow, so the app supports username/password JWT login only. Google sign-in uses OIDC ID-token exchange (`POST /api/auth/google/exchange`).
- Native folders (`android/`, `ios/`) are generated by `flutter create` — only edit manifest/plist entries that are deliberate (app label `File Share`, bundle id `dev.eslam.simplefileshare`), never regenerate them blindly.
- App colors come from `SfsPalette.of(context)` in `lib/src/theme.dart`, a `ThemeExtension` carrying both palettes; `buildAppTheme(Brightness)` is the only place palettes are attached. Never hardcode a color — resolve from the palette or the light/dark setting silently stops working.
- The theme choice persists under the `fs_theme` key (`state/theme_controller.dart`, shared_preferences) and falls back to following the system when unset.
- Peer-to-peer transfer is signalling-only on the server: `P2PController` opens its own `GET /api/p2p/stream` SSE with the bearer token, publishes via `POST /api/p2p/signal`, lists peers via `GET /api/p2p/peers`, and reconnects with the same 1s → 30s exponential backoff as the events stream (guarded by a generation counter). The file itself then moves over a WebRTC data channel. `SseParser` is the only place bytes become frames (and `p2pFrameFromSse` returns null rather than throwing on anything malformed), and `p2pSafeFileName` is the only place a peer-supplied filename is trusted — never write a received file outside that path.
- Calls use the same relay with a separate `call-*` signal namespace and call-scoped SDP (`{'scope':'call'}`). File-transfer sessions ignore call frames and vice versa. The nearby master switch (`fs_nearby_enabled`) gates scanning, P2P, and calls — turning it off auto-hangs-up active calls.
- Media previews stream via HTTP byte-range (`Image.network` / `VideoPlayerController.networkUrl` with bearer headers) — never download the whole file first. The server answers `206 Partial Content` on `/api/files/view` and `/api/shared`.
- Thumbnails: `GET /api/thumbs` serves cached EXIF-stripped JPEG previews. Client falls back to local downscale (≤8 MB) when the endpoint is absent.
- There is no Android SDK on this machine, so `flutter_webrtc` and the theme control are verified only by `flutter analyze` + `flutter test`; never claim an emulator or device run.
- Desktop (Linux/Windows): `main.dart` initializes `sqfliteFfiInit()` + `databaseFactory = databaseProvider` before any provider touches the transfer DB.
