# FileShare — Mobile (Flutter)

Flutter app for the Simple File Share server: browse and upload files, manage
share links, watch usage, and react to live server events over the gRPC
`EventsService.Subscribe` stream.

## Stack

- **Flutter** (stable, Dart 3) — Android, iOS, and Linux desktop
- **Riverpod** for state management
- **grpc** / **protobuf** for all API traffic (REST/SSE are not used)
- **flutter_secure_storage** for the JWT
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

Sign in with a username and password (JWT). OAuth is only available in the
web app.

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

`lib/src/config.dart` reads `API_BASE_URL`, `GRPC_HOST`, and `GRPC_PORT` via
`String.fromEnvironment`. With no define:

| | default |
| --- | --- |
| `API_BASE_URL` | `https://simple-file-share-production.up.railway.app` |
| gRPC target | `reseau.proxy.rlwy.net:54492`, TLS on |

Supplying an `API_BASE_URL` moves gRPC with it; `GRPC_HOST`/`GRPC_PORT`
override the gRPC side alone:

```bash
flutter run --dart-define=API_BASE_URL=https://files.example.com
```

## Project layout

```
lib/
├── main.dart                 # ProviderScope + MaterialApp
└── src/
    ├── config.dart           # API_BASE_URL + gRPC target resolution
    ├── theme.dart            # SfsColors + dark theme
    ├── format.dart           # bytes/date/path helpers (tested)
    ├── models.dart           # API DTOs (tested)
    ├── state/                # Riverpod auth controller + providers
    ├── services/             # gRPC connection (cert pinning), API client,
    │                         # events stream, token store
    ├── grpc/                 # generated gRPC/protobuf stubs (do not edit)
    └── screens/              # login, files, shares, account
test/                         # unit tests + gated live integration test
assets/                       # launcher icon sources
```
