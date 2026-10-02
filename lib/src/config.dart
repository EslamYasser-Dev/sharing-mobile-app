const String _envApiUrl = String.fromEnvironment('API_BASE_URL');
const String _envGrpcHost = String.fromEnvironment('GRPC_HOST');
const String _envGrpcPort = String.fromEnvironment('GRPC_PORT');

/// Default deployment. REST and gRPC are two separate Railway endpoints:
/// gRPC cannot ride an HTTP domain (Railway's edge demuxes HTTP/2 down to
/// HTTP/1.1 for the origin), so it is reached through a raw TCP proxy instead.
///
/// Override at build time with `--dart-define=API_BASE_URL=...` to move both
/// — e.g. `http://10.0.2.2:3000` for the Android emulator — or with
/// `GRPC_HOST`/`GRPC_PORT` to point gRPC somewhere else on its own.
const String _defaultApiUrl =
    'https://simple-file-share-production.up.railway.app';
const String _defaultGrpcHost = 'reseau.proxy.rlwy.net';
const int _defaultGrpcPort = 54492;

String get apiBaseUrl {
  final raw = _envApiUrl.trim();
  final base = raw.isEmpty ? _defaultApiUrl : raw;
  return base.replaceAll(RegExp(r'/+$'), '');
}

class GrpcTarget {
  const GrpcTarget({
    required this.host,
    required this.port,
    required this.secure,
  });

  final String host;
  final int port;
  final bool secure;
}

GrpcTarget grpcTargetFrom(String baseUrl, {String? host, int? port}) {
  final uri = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), ''));
  final secure = uri.scheme != 'http';
  return GrpcTarget(
    host: (host == null || host.isEmpty) ? uri.host : host,
    port: port ?? (uri.hasPort ? uri.port : (secure ? 443 : 80)),
    secure: secure,
  );
}

/// Resolves the gRPC target for [baseUrl].
///
/// With no overrides the API and gRPC live on different hosts, so gRPC gets
/// its own default host and port while TLS still follows [baseUrl]'s scheme.
/// Supplying an API origin without an explicit [host] moves gRPC along with
/// it, keeping local and emulator runs on one machine.
GrpcTarget resolveGrpcTarget(
  String baseUrl, {
  String? host,
  int? port,
  bool apiOverridden = false,
}) {
  final resolved = (host ?? '').trim();
  if (resolved.isNotEmpty) {
    return grpcTargetFrom(baseUrl, host: resolved, port: port);
  }
  if (apiOverridden) return grpcTargetFrom(baseUrl, port: port);
  return grpcTargetFrom(
    baseUrl,
    host: _defaultGrpcHost,
    port: port ?? _defaultGrpcPort,
  );
}

GrpcTarget get grpcTarget => resolveGrpcTarget(
  apiBaseUrl,
  host: _envGrpcHost,
  port: int.tryParse(_envGrpcPort.trim()),
  apiOverridden: _envApiUrl.trim().isNotEmpty,
);
