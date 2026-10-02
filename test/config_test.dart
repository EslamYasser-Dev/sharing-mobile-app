import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/config.dart';

void main() {
  group('backend default', () {
    test('apiBaseUrl points at the deployed service', () {
      expect(apiBaseUrl, 'https://simple-file-share-production.up.railway.app');
    });

    test('grpc target points at the separate TCP proxy over TLS', () {
      expect(grpcTarget.host, 'reseau.proxy.rlwy.net');
      expect(grpcTarget.port, 54492);
      expect(grpcTarget.secure, isTrue);
    });
  });

  group('resolveGrpcTarget', () {
    test('no overrides uses the standalone gRPC host and port', () {
      final target = resolveGrpcTarget(
        'https://simple-file-share-production.up.railway.app',
      );
      expect(target.host, 'reseau.proxy.rlwy.net');
      expect(target.port, 54492);
      expect(target.secure, isTrue);
    });

    test('an explicit API origin moves gRPC along with it', () {
      final target = resolveGrpcTarget(
        'http://localhost:3000',
        apiOverridden: true,
      );
      expect(target.host, 'localhost');
      expect(target.port, 3000);
      expect(target.secure, isFalse);
    });

    test('an explicit gRPC host wins over the default host', () {
      final target = resolveGrpcTarget(
        'https://simple-file-share-production.up.railway.app',
        host: 'other.proxy.rlwy.net',
        port: 15140,
      );
      expect(target.host, 'other.proxy.rlwy.net');
      expect(target.port, 15140);
      expect(target.secure, isTrue);
    });
  });

  group('grpcTargetFrom', () {
    test('https defaults to port 443 and TLS', () {
      final target = grpcTargetFrom('https://shares.up.railway.app');
      expect(target.host, 'shares.up.railway.app');
      expect(target.port, 443);
      expect(target.secure, true);
    });

    test('http keeps an explicit port and is insecure', () {
      final target = grpcTargetFrom('http://localhost:3000');
      expect(target.host, 'localhost');
      expect(target.port, 3000);
      expect(target.secure, false);
    });

    test('http without port defaults to 80', () {
      final target = grpcTargetFrom('http://example.test');
      expect(target.port, 80);
      expect(target.secure, false);
    });

    test('trailing slashes are ignored', () {
      final target = grpcTargetFrom('https://example.test/');
      expect(target.host, 'example.test');
      expect(target.port, 443);
    });

    test('host and port overrides target the TCP proxy', () {
      final target = grpcTargetFrom(
        'https://shares.up.railway.app',
        host: 'shuttle.proxy.rlwy.net',
        port: 15140,
      );
      expect(target.host, 'shuttle.proxy.rlwy.net');
      expect(target.port, 15140);
      expect(target.secure, true);
    });

    test('empty host override falls back to the base URL host', () {
      final target = grpcTargetFrom('http://localhost:3000', host: '');
      expect(target.host, 'localhost');
      expect(target.port, 3000);
      expect(target.secure, false);
    });

    test('port override without explicit base port keeps TLS default', () {
      final target = grpcTargetFrom('https://example.test', port: 50051);
      expect(target.host, 'example.test');
      expect(target.port, 50051);
      expect(target.secure, true);
    });
  });
}
