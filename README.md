# FileShare — Mobile (Flutter)

Flutter app for the Simple File Share server: browse and upload files, manage
share links, watch usage, react to live server events over the gRPC
`EventsService.Subscribe` stream, send files directly to another device over
WebRTC, make voice/video calls, follow the system's light or dark preference,
and scroll a social upload timeline (TailTime) with per-file privacy.

## Features

- **Files** — browse, resumable uploads/downloads with pause/resume, thumbnails
  for images, streaming image/video preview (byte-range, never full-download)
- **TailTime** — upload timeline with All/Mine/Following filters, follow/unfollow,
  per-file visibility (Private / Followers / Public + streaming toggle)
- **Shares** — links with optional password, expiry, and download budget
- **Direct** — WebRTC file transfer, nearby discovery with a master on/off
  switch, username search with presence, and voice/video calls (direct LAN
  media, optional TURN relay, transport route badge)
- **Auth** — username/password JWT plus Google sign-in (OIDC ID-token exchange)

## Stack

- **Flutter** (stable, Dart 3) — Android, iOS, and Linux desktop
- **Riverpod** for state management
- **grpc** / **protobuf** for files, shares and events
- **flutter_secure_storage** for the JWT
- **flutter_webrtc** for peer-to-peer transfers and calls — HTTP/SSE carries only the
  signalling between peers, never the file or call media
- **video_player** for streaming video preview/playback
- **google_sign_in** for Google sign-in (OIDC ID token → app JWT exchange)
- **permission_handler** for mic/camera runtime permission (calls)
- **image** for client-side thumbnail fallback
- **shared_preferences** for the persisted theme, nearby-switch, and UI settings
- **file_picker** / **share_plus** / **path_provider** for native integrations

## Development

```bash
flutter pub get
flutter run
```

Out of the box the app talks to two deployed endpoints: the API at
`https://simple-file-share-production.up.railway.app` and gRPC at
`reseau.proxy.rlwy.net:54492`. They differ because Railway's HTTP edge accepts
HTTP/2 from the client but demuxes it to HTTP/1.1 for the origin, so gRPC has to
cross a raw TCP proxy instead. Point both at a local server with one define:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000    # Android emulator
flutter run --dart-define=API_BASE_URL=http://localhost:3000   # local server
```

Supplying an `API_BASE_URL` moves gRPC along with it, so local runs stay on one
machine. To send gRPC somewhere else entirely, override it outright:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://files.example.com \
  --dart-define=GRPC_HOST=shuttle.proxy.rlwy.net \
  --dart-define=GRPC_PORT=15140
```

Secure targets fetch `GET /api/grpc/cert` over HTTPS and keep it as an extra
certificate the channel will accept, **alongside** the system trust store. That
is what lets the app dial the gRPC endpoint through a raw TCP proxy: the
backend's certificate is self-signed for `localhost` and could never pass a
hostname check, but it is the certificate we were told to trust.

Sign in with a username and password (JWT) or with Google
(`Continue with Google` appears once the app is built with
`--dart-define=GOOGLE_SERVER_CLIENT_ID=<web OAuth client id>` and the server
sets the matching `GOOGLE_CLIENT_ID`).

## Scripts

| Command | Description |
| --- | --- |
| `flutter pub get` | Install dependencies |
| `flutter run` | Build and run on a connected device/emulator |
| `flutter analyze` | Static analysis (must be clean) |
| `flutter test` | Unit tests (formatting, models, config, event mapping) |
| `flutter test --dart-define=RUN_GRPC_IT=1` | Live gRPC integration test (needs a backend on localhost:3000) |
| `dart run flutter_launcher_icons` | Regenerate launcher icons from `assets/` |

## Configuration

`lib/src/config.dart` reads its settings via `String.fromEnvironment`. With
no defines:

| | default |
| --- | --- |
| `API_BASE_URL` | `https://simple-file-share-production.up.railway.app` |
| gRPC target | `reseau.proxy.rlwy.net:54492`, TLS on |
| `GOOGLE_SERVER_CLIENT_ID` | `""` (Google button hidden) |
| `STUN_URL` / `TURN_URL` (+ `TURN_USERNAME`/`TURN_CREDENTIAL`) | `""` (LAN-only calls) |

Supplying an `API_BASE_URL` moves gRPC with it; `GRPC_HOST`/`GRPC_PORT`
override the gRPC side alone:

```bash
flutter run --dart-define=API_BASE_URL=https://files.example.com
```

Calls need no relay on the same LAN (host-only ICE). Across NATs, point the
app at a TURN server:

```bash
flutter run \
  --dart-define=TURN_URL=turn:turn.example.com:3478 \
  --dart-define=TURN_USERNAME=user \
  --dart-define=TURN_CREDENTIAL=secret
```

## Project layout

```
lib/
├── main.dart                 # ProviderScope + MaterialApp
└── src/
    ├── config.dart           # API_BASE_URL + gRPC target resolution
    ├── theme.dart            # SfsPalette light/dark ThemeExtension
    ├── format.dart           # bytes/date/path helpers (tested)
    ├── models.dart           # API DTOs + P2P models (tested)
    ├── state/                # Riverpod auth, theme, transfers, P2P, calls,
    │                         # timeline, follow, nearby-switch controllers
    ├── services/             # gRPC connection (cert pinning), API client,
    │                         # events stream, token store, P2P signalling,
    │                         # call session, thumbnails, viewer gate
    ├── widgets/              # aurora background, motion kit, glass chrome
    ├── grpc/                 # generated gRPC/protobuf stubs (do not edit)
    └── screens/              # login, files, shares, transfers, timeline,
                              # direct (P2P + calls), account, viewers
test/                         # unit tests + gated live integration test
assets/                       # launcher icon sources
```
