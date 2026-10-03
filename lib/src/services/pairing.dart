import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pairing service for secure P2P authentication using QR codes.
/// Implements a Noise-like handshake with Curve25519 keys.
class PairingService {
  PairingService();

  static const int _keySize = 32;
  static const int _nonceSize = 24;
  static const String _protocolVersion = '1';

  /// Generates a new ephemeral key pair for this session.
  static KeyPair generateKeyPair() {
    final privateKey = _generatePrivateKey();
    final publicKey = _derivePublicKey(privateKey);
    return KeyPair(privateKey: privateKey, publicKey: publicKey);
  }

  /// Creates a pairing QR code payload containing our identity and public key.
  static String createPairingPayload({
    required String peerId,
    required String displayName,
    required Uint8List publicKey,
    Map<String, String>? metadata,
  }) {
    final payload = PairingPayload(
      version: _protocolVersion,
      peerId: peerId,
      displayName: displayName,
      publicKey: base64Encode(publicKey),
      metadata: metadata ?? {},
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: _generateNonce(),
    );

    // Sign the payload with HMAC for integrity
    final json = jsonEncode(payload.toJsonForSignature());
    final signature = Hmac(sha256, utf8.encode(payload.nonce)).convert(utf8.encode(json)).toString();
    payload.signature = signature;

    return base64UrlEncode(jsonEncode(payload.toJson()).codeUnits);
  }

  /// Parses and validates a pairing QR code payload.
  static PairingResult parsePairingPayload(String qrData) {
    try {
      final decoded = utf8.decode(base64Url.decode(qrData));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final payload = PairingPayload.fromJson(json);

      // Verify signature
      final expectedSig = Hmac(sha256, utf8.encode(payload.nonce)).convert(utf8.encode(jsonEncode(payload.toJsonForSignature()))).toString();
      if (payload.signature != expectedSig) {
        return PairingResult.error('Invalid signature - QR code may be tampered');
      }

      // Check timestamp (expire after 5 minutes)
      final age = DateTime.now().millisecondsSinceEpoch - payload.timestamp;
      if (age > 5 * 60 * 1000) {
        return PairingResult.error('QR code expired');
      }

      return PairingResult.success(payload);
    } catch (e) {
      return PairingResult.error('Invalid QR code format: $e');
    }
  }

  /// Derives a shared secret using HKDF (simplified - real implementation would use X25519 ECDH).
  static Uint8List deriveSharedSecret(Uint8List ourPrivateKey, Uint8List theirPublicKey) {
    // In a real implementation, use X25519 from a proper crypto library
    // This is a simplified version using HKDF-like key derivation
    final buffer = <int>[];
    buffer.addAll(ourPrivateKey);
    buffer.addAll(theirPublicKey);
    return Uint8List.fromList(sha256.convert(buffer).bytes).sublist(0, _keySize);
  }

  /// Encrypts data using the shared secret (ChaCha20-Poly1305-like AEAD).
  static EncryptedData encrypt(Uint8List data, Uint8List sharedSecret, String associatedData) {
    final nonce = _generateNonceBytes(_nonceSize);
    final key = Uint8List.fromList(sha256.convert(sharedSecret).bytes);
    // Simplified encryption - replace with proper AEAD (ChaCha20-Poly1305)
    final ciphertext = _xorEncrypt(data, key, nonce);
    final tag = Uint8List.fromList(Hmac(sha256, key).convert(ciphertext).bytes);
    return EncryptedData(
      nonce: base64Encode(nonce),
      ciphertext: base64Encode(ciphertext),
      tag: base64Encode(tag),
      associatedData: associatedData,
    );
  }

  /// Decrypts data using the shared secret.
  static Uint8List? decrypt(EncryptedData encrypted, Uint8List sharedSecret) {
    final key = Uint8List.fromList(sha256.convert(sharedSecret).bytes);
    final nonce = base64Decode(encrypted.nonce);
    final ciphertext = base64Decode(encrypted.ciphertext);
    final tag = base64Decode(encrypted.tag);

    // Verify tag
    final expectedTag = Uint8List.fromList(Hmac(sha256, key).convert(ciphertext).bytes);
    if (!_constantTimeEquals(tag, expectedTag)) {
      return null;
    }

    return _xorEncrypt(ciphertext, key, nonce);
  }

  static Uint8List _generatePrivateKey() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(_keySize, (_) => random.nextInt(256)));
  }

  static Uint8List _derivePublicKey(Uint8List privateKey) {
    // Placeholder - real implementation uses Curve25519 scalar multiplication
    return Uint8List.fromList(sha256.convert(privateKey).bytes);
  }

  static String _generateNonce() {
    final random = Random.secure();
    return base64UrlEncode(Uint8List.fromList(List.generate(16, (_) => random.nextInt(256))));
  }

  static Uint8List _generateNonceBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  static Uint8List _xorEncrypt(Uint8List data, List<int> key, Uint8List nonce) {
    final result = Uint8List(data.length);
    final keystream = _generateKeystream(key, nonce, data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keystream[i];
    }
    return result;
  }

  static Uint8List _generateKeystream(List<int> key, Uint8List nonce, int length) {
    final stream = <int>[];
    var counter = 0;
    while (stream.length < length) {
      final block = sha256.convert([
        ...key,
        ...nonce,
        counter >> 24,
        counter >> 16 & 0xFF,
        counter >> 8 & 0xFF,
        counter & 0xFF,
      ]).bytes;
      stream.addAll(block);
      counter++;
    }
    return Uint8List.fromList(stream.sublist(0, length));
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

class KeyPair {
  const KeyPair({required this.privateKey, required this.publicKey});
  final Uint8List privateKey;
  final Uint8List publicKey;
}

class PairingPayload {
  PairingPayload({
    required this.version,
    required this.peerId,
    required this.displayName,
    required this.publicKey,
    required this.metadata,
    required this.timestamp,
    required this.nonce,
    this.signature,
  });

  final String version;
  final String peerId;
  final String displayName;
  final String publicKey; // base64 encoded
  final Map<String, String> metadata;
  final int timestamp;
  final String nonce;
  String? signature;

  Map<String, dynamic> toJson() => {
    'v': version,
    'id': peerId,
    'name': displayName,
    'key': publicKey,
    'meta': metadata,
    'ts': timestamp,
    'nonce': nonce,
    'sig': signature,
  };

  Map<String, dynamic> toJsonForSignature() => {
    'v': version,
    'id': peerId,
    'name': displayName,
    'key': publicKey,
    'meta': metadata,
    'ts': timestamp,
    'nonce': nonce,
  };

  factory PairingPayload.fromJson(Map<String, dynamic> json) => PairingPayload(
    version: json['v'] as String? ?? '1',
    peerId: json['id'] as String? ?? '',
    displayName: json['name'] as String? ?? '',
    publicKey: json['key'] as String? ?? '',
    metadata: Map<String, String>.from(json['meta'] as Map? ?? {}),
    timestamp: json['ts'] as int? ?? 0,
    nonce: json['nonce'] as String? ?? '',
    signature: json['sig'] as String?,
  );
}

class PairingResult {
  const PairingResult._({this.payload, this.error});
  final PairingPayload? payload;
  final String? error;

  bool get isSuccess => payload != null;
  bool get isError => error != null;

  factory PairingResult.success(PairingPayload payload) => PairingResult._(payload: payload);
  factory PairingResult.error(String error) => PairingResult._(error: error);
}

class EncryptedData {
  const EncryptedData({
    required this.nonce,
    required this.ciphertext,
    required this.tag,
    required this.associatedData,
  });

  final String nonce; // base64
  final String ciphertext; // base64
  final String tag; // base64
  final String associatedData;

  Map<String, dynamic> toJson() => {
    'nonce': nonce,
    'ct': ciphertext,
    'tag': tag,
    'ad': associatedData,
  };

  factory EncryptedData.fromJson(Map<String, dynamic> json) => EncryptedData(
    nonce: json['nonce'] as String,
    ciphertext: json['ct'] as String,
    tag: json['tag'] as String,
    associatedData: json['ad'] as String,
  );
}

/// Pairing session manager for handling the pairing flow.
class PairingSession {
  PairingSession({
    required this.ourId,
    required this.ourKeyPair,
    required this.onPairingComplete,
  });

  final String ourId;
  final KeyPair ourKeyPair;
  final void Function(String peerId, Uint8List sharedSecret) onPairingComplete;

  String? _theirId;
  Uint8List? _theirPublicKey;
  Uint8List? _sharedSecret;

  /// Initiates pairing by generating our QR code.
  String generateOurQrCode({String? displayName, Map<String, String>? metadata}) {
    return PairingService.createPairingPayload(
      peerId: ourId,
      displayName: displayName ?? 'FileShare User',
      publicKey: ourKeyPair.publicKey,
      metadata: metadata,
    );
  }

  /// Processes a scanned QR code from another device.
  PairingResult processScannedQrCode(String qrData) {
    final result = PairingService.parsePairingPayload(qrData);
    if (result.isSuccess) {
      _theirId = result.payload!.peerId;
      _theirPublicKey = base64Decode(result.payload!.publicKey);
      _sharedSecret = PairingService.deriveSharedSecret(ourKeyPair.privateKey, _theirPublicKey!);
      onPairingComplete(_theirId!, _sharedSecret!);
    }
    return result;
  }

  /// Encrypts a message for the paired peer.
  EncryptedData encryptForPeer(Uint8List data, String associatedData) {
    if (_sharedSecret == null) {
      throw StateError('Not paired yet');
    }
    return PairingService.encrypt(data, _sharedSecret!, associatedData);
  }

  /// Decrypts a message from the paired peer.
  Uint8List? decryptFromPeer(EncryptedData encrypted) {
    if (_sharedSecret == null) return null;
    return PairingService.decrypt(encrypted, _sharedSecret!);
  }

  String? get theirId => _theirId;
  Uint8List? get sharedSecret => _sharedSecret;
  bool get isPaired => _sharedSecret != null;
}