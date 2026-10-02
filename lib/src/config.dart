const String _envApiUrl = String.fromEnvironment('API_BASE_URL');
const String _envGrpcHost = String.fromEnvironment('GRPC_HOST');
const String _envGrpcPort = String.fromEnvironment('GRPC_PORT');

/// Default deployments: REST and gRPC are two separate Railway services.
/// Override at build time with `--dart-define=API_BASE_URL=...`, which moves
/// both REST and the gRPC target (so `http://10.0.2.2:3000` or
/// `http://localhost:3000` keeps a local backend in sync), or with
/// `GRPC_HOST`/`GRPC_PORT` for a raw TCP proxy.
const String _defaultApiUrl = 'https://simple-file-share.up.railway.app';
const String _defaultGrpcHost = 'mobile-shares.up.railway.app';

/// True when the caller supplied their own REST origin.
bool get _hasExplicitApi => _envApiUrl.trim().isNotEmpty;

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
/// With no overrides the app talks to the two separate default services, so
/// the standalone gRPC host wins over the REST origin. As soon as the caller
/// supplies a REST origin ([apiOverridden]) or an explicit [host], the
/// target derives from those instead — keeping local runs on one machine.
GrpcTarget resolveGrpcTarget(
  String baseUrl, {
  String? host,
  int? port,
  bool apiOverridden = false,
}) {
  final resolved = (host == null || host.isEmpty) && !apiOverridden
      ? _defaultGrpcHost
      : host;
  return grpcTargetFrom(baseUrl, host: resolved, port: port);
}

GrpcTarget get grpcTarget => resolveGrpcTarget(
  apiBaseUrl,
  host: _envGrpcHost.trim(),
  port: int.tryParse(_envGrpcPort.trim()),
  apiOverridden: _hasExplicitApi,
);
