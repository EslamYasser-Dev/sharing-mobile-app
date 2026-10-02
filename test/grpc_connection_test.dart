import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/services/grpc_connection.dart';

const _certA =
    '-----BEGIN CERTIFICATE-----\n'
    'MIIBkTCB+wIJAJH8b3RsaW5n\n'
    '-----END CERTIFICATE-----\n';

const _certB =
    '-----BEGIN CERTIFICATE-----\n'
    'MIIBkjCB+wIJAJH8b3RzaW5n\n'
    '-----END CERTIFICATE-----\n';

void main() {
  group('sameCertificatePem', () {
    test('accepts the pinned certificate', () {
      expect(sameCertificatePem(_certA, _certA), isTrue);
    });

    test('ignores line wrapping and trailing whitespace', () {
      final rewrapped =
          '-----BEGIN CERTIFICATE-----\r\n'
          'MIIBkTCB+wIJ\r\n'
          'AJH8b3RsaW5n\r\n'
          '-----END CERTIFICATE-----';
      expect(sameCertificatePem(rewrapped, _certA), isTrue);
    });

    test('rejects a different certificate', () {
      expect(sameCertificatePem(_certB, _certA), isFalse);
    });

    test('rejects an empty presentation against a pinned certificate', () {
      expect(sameCertificatePem('', _certA), isFalse);
    });
  });
}
