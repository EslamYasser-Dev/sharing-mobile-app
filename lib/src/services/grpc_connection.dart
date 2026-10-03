import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show HttpClient;

import 'package:grpc/grpc.dart';

import '../config.dart';
import '../grpc/fileshare/v1/fileshare.pbgrpc.dart';

class GrpcConnection {
  GrpcConnection({GrpcTarget? target, ClientChannel? channel})
    : _target = target ?? grpcTarget,
      _providedChannel = channel;

  final GrpcTarget _target;
  final ClientChannel? _providedChannel;

  Future<ClientChannel>? _pendingChannel;

  Future<ClientChannel> get _channel {
    final provided = _providedChannel;
    if (provided != null) return Future<ClientChannel>.value(provided);
    final pending = _pendingChannel;
    if (pending != null) return pending;
    final future = _openChannel();
    _pendingChannel = future;
    // A failed open must not poison every later call: drop it so the next
    // attempt redials instead of replaying the same error forever.
    unawaited(
      future.then(
        (_) {},
        onError: (_) {
          if (identical(_pendingChannel, future)) _pendingChannel = null;
        },
      ),
    );
    return future;
  }

  Future<ClientChannel> _openChannel() async {
    final pinnedPem = _target.secure ? await _fetchCertPem() : null;
    return ClientChannel(
      _target.host,
      port: _target.port,
      options: ChannelOptions(
        credentials: _target.secure
            ? ChannelCredentials.secure(
                onBadCertificate: pinnedPem == null
                    ? null
                    : (certificate, _) => sameCertificatePem(
                        certificate.pem,
                        utf8.decode(pinnedPem),
                      ),
              )
            : const ChannelCredentials.insecure(),
        keepAlive: const ClientKeepAliveOptions(
          pingInterval: Duration(seconds: 30),
          permitWithoutCalls: true,
        ),
      ),
    );
  }

  /// Fetches the server's gRPC certificate over the trusted HTTPS API so the
  /// channel can additionally accept it. Returns null (system trust store
  /// only) on any failure, including the endpoint being absent.
  Future<List<int>?> _fetchCertPem() async {
    try {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('$apiBaseUrl/api/grpc/cert'))
            .timeout(const Duration(seconds: 10));
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        if (response.statusCode != 200) return null;
        final bytes = await response.expand((chunk) => chunk).toList();
        return bytes.isEmpty ? null : bytes;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  late final Future<AuthServiceClient> auth = _channel.then(
    (channel) => AuthServiceClient(channel),
  );
  late final Future<FileServiceClient> files = _channel.then(
    (channel) => FileServiceClient(channel),
  );
  late final Future<ShareServiceClient> shares = _channel.then(
    (channel) => ShareServiceClient(channel),
  );
  late final Future<EventsServiceClient> events = _channel.then(
    (channel) => EventsServiceClient(channel),
  );
  late final Future<SocialServiceClient> social = _channel.then(
    (channel) => SocialServiceClient(channel),
  );

  Future<void> shutdown() async {
    final provided = _providedChannel;
    if (provided != null) {
      await provided.shutdown();
      return;
    }
    final pending = _pendingChannel;
    if (pending == null) return;
    await (await pending).shutdown();
  }
}

/// Whether [presented] and [pinned] encode the same certificate.
///
/// Whitespace is ignored because the API response and
/// `X509Certificate.pem` may wrap the base64 body differently. Comparing the
/// certificate itself — rather than trusting the system store plus a hostname
/// check — is what lets the channel accept the backend's self-signed
/// certificate on a proxy such as `*.proxy.rlwy.net`: that certificate is
/// issued for `localhost`, so it could never pass hostname validation, yet it
/// is still the only certificate we were told to trust.
bool sameCertificatePem(String presented, String pinned) =>
    _compactPem(presented) == _compactPem(pinned);

String _compactPem(String pem) => pem.replaceAll(RegExp(r'\s'), '');
