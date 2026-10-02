const String _envApiUrl = String.fromEnvironment('API_BASE_URL');
const String _envGrpcHost = String.fromEnvironment('GRPC_HOST');
const String _envGrpcPort = String.fromEnvironment('GRPC_PORT');

/// Default backend for both the REST API and gRPC (derived below from this
/// same URL, so the two can never disagree). Override at build time with
/// `--dart-define=API_BASE_URL=...` to target another deployment, e.g.
/// `http://10.0.2.2:3000` for the Android emulator or `http://localhost:3000`
/// for a local server.
const String _defaultApiUrl = 'https://mobile-shares.up.railway.app';

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

GrpcTarget grpcTargetFrom(
  String baseUrl, {
  String? host,
  int? port,
}) {
  final uri = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), ''));
  final secure = uri.scheme != 'http';
  return GrpcTarget(
    host: (host == null || host.isEmpty) ? uri.host : host,
    port: port ?? (uri.hasPort ? uri.port : (secure ? 443 : 80)),
    secure: secure,
  );
}

GrpcTarget get grpcTarget => grpcTargetFrom(
      apiBaseUrl,
      host: _envGrpcHost.trim(),
      port: int.tryParse(_envGrpcPort.trim()),
    );
