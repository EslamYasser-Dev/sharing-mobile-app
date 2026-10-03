import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'pairing.dart';

/// Simplified mTLS-like security for P2P connections.
/// Uses the pairing service's shared secret for encrypted P2P communication.
/// This is a simplified implementation - production would use proper X.509 certificates.
class P2PSecurityManager {
  P2PSecurityManager();

  final Map<String, _SessionSecurity> _sessions = {};

  /// Creates a secure context for P2P communication with a paired peer.
  /// Uses the shared secret from pairing for encryption.
  Future<SecurityContext> createSecureContext({
    required String localPeerId,
    required String remotePeerId,
    required Uint8List sharedSecret,
  }) async {
    final session = _SessionSecurity(
      localPeerId: localPeerId,
      remotePeerId: remotePeerId,
      sharedSecret: sharedSecret,
    );

    _sessions[remotePeerId] = session;

    // Create a SecurityContext for TLS
    final context = SecurityContext(withTrustedRoots: false);
    
    // For production, we'd use proper certificate management
    // For now, we'll use the shared secret for application-layer encryption
    // and rely on the platform's default TLS verification for the transport layer
    
    return context;
  }

  /// Gets the session security for a peer.
  _SessionSecurity? getSession(String remotePeerId) => _sessions[remotePeerId];

  /// Encrypts data for a remote peer using the session's shared secret.
  EncryptedData encryptForPeer(String remotePeerId, Uint8List data, String associatedData) {
    final session = _sessions[remotePeerId];
    if (session == null) {
      throw StateError('No session for peer: $remotePeerId');
    }
    return _encrypt(data, session.sharedSecret, associatedData);
  }

  /// Decrypts data from a remote peer using the session's shared secret.
  Uint8List? decryptFromPeer(String remotePeerId, EncryptedData encrypted) {
    final session = _sessions[remotePeerId];
    if (session == null) {
      return null;
    }
    return _decrypt(encrypted, session.sharedSecret);
  }

  /// Removes a session.
  void removeSession(String remotePeerId) {
    _sessions.remove(remotePeerId);
  }

  /// Clears all sessions.
  void clear() {
    _sessions.clear();
  }

  EncryptedData _encrypt(Uint8List data, Uint8List sharedSecret, String associatedData) {
    final nonce = _generateNonce(12);
    final key = sha256.convert(sharedSecret).bytes;
    final ciphertext = _xorEncrypt(data, key, nonce);
    final tag = Hmac(sha256, key).convert(ciphertext).bytes;
    return EncryptedData(
      nonce: base64Encode(nonce),
      ciphertext: base64Encode(ciphertext),
      tag: base64Encode(tag),
      associatedData: associatedData,
    );
  }

  Uint8List? _decrypt(EncryptedData encrypted, Uint8List sharedSecret) {
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

  static Uint8List _generateNonce(int length) {
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

  void dispose() {
    _sessions.clear();
  }
}

class _SessionSecurity {
  _SessionSecurity({
    required this.localPeerId,
    required this.remotePeerId,
    required this.sharedSecret,
  });

  final String localPeerId;
  final String remotePeerId;
  final Uint8List sharedSecret;
}

/// Secure socket wrapper that adds application-layer encryption on top of TLS.
class SecureP2PSocket {
  SecureP2PSocket({
    required this.socket,
    required this.securityManager,
    required this.remotePeerId,
  });

  final Socket socket;
  final P2PSecurityManager securityManager;
  final String remotePeerId;

  /// Sends encrypted data.
  Future<void> send(Uint8List data) async {
    final encrypted = securityManager.encryptForPeer(remotePeerId, data, 'p2p-data');
    final json = jsonEncode(encrypted.toJson());
    final payload = utf8.encode(json);
    final lengthBytes = Uint8List(4);
    ByteData.view(lengthBytes.buffer).setUint32(0, payload.length, Endian.big);
    socket.add(lengthBytes);
    socket.add(payload);
    await socket.flush();
  }

  /// Receives and decrypts data.
  Future<Uint8List?> receive() async {
    // Read length prefix (4 bytes)
    final lengthBytes = await _readExact(4);
    if (lengthBytes == null) return null;
    final length = ByteData.view(lengthBytes.buffer).getUint32(0, Endian.big);
    
    // Read payload
    final payload = await _readExact(length);
    if (payload == null) return null;
    
    // Parse and decrypt
    final jsonStr = utf8.decode(payload);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    final encrypted = EncryptedData.fromJson(json);
    
    return securityManager.decryptFromPeer(remotePeerId, encrypted);
  }

  Future<Uint8List?> _readExact(int length) async {
    final buffer = <int>[];
    while (buffer.length < length) {
      final chunk = await socket.firstWhere((chunk) => true);
      buffer.addAll(chunk);
    }
    return Uint8List.fromList(buffer.sublist(0, length));
  }

  void close() {
    socket.close();
  }
}

/// Simplified certificate-based authentication for initial connection.
/// Uses the pairing service's shared secret to derive connection keys.
class ConnectionAuthenticator {
  ConnectionAuthenticator();

  /// Authenticates an incoming connection using the pairing secret.
  Future<bool> authenticateIncoming({
    required String remotePeerId,
    required Uint8List sharedSecret,
    required Socket socket,
  }) async {
    // Challenge-response authentication
    final challenge = _generateChallenge();
    final expectedResponse = _computeResponse(challenge, sharedSecret);
    
    // Send challenge
    final challengeMsg = {
      'type': 'auth_challenge',
      'challenge': base64Encode(challenge),
    };
    socket.add(utf8.encode(jsonEncode(challengeMsg)));
    await socket.flush();
    
    // Read response
    final responseBytes = await _readLine(socket);
    if (responseBytes == null) return false;
    
    final response = jsonDecode(utf8.decode(responseBytes)) as Map<String, dynamic>;
    if (response['type'] != 'auth_response') return false;
    
    final responseBytes64 = response['response'] as String?;
    if (responseBytes64 == null) return false;
    
    final receivedResponse = base64Decode(responseBytes64);
    if (!_constantTimeEquals(receivedResponse, expectedResponse)) {
      return false;
    }
    
    // Send success
    socket.add(utf8.encode(jsonEncode({'type': 'auth_success'})));
    await socket.flush();
    return true;
  }

  /// Authenticates an outgoing connection.
  Future<bool> authenticateOutgoing({
    required String remotePeerId,
    required Uint8List sharedSecret,
    required Socket socket,
  }) async {
    // Read challenge
    final challengeBytes = await _readLine(socket);
    if (challengeBytes == null) return false;
    
    final challengeMsg = jsonDecode(utf8.decode(challengeBytes)) as Map<String, dynamic>;
    if (challengeMsg['type'] != 'auth_challenge') return false;
    
    final challenge = base64Decode(challengeMsg['challenge'] as String);
    final response = _computeResponse(challenge, sharedSecret);
    
    // Send response
    final responseMsg = {
      'type': 'auth_response',
      'response': base64Encode(response),
    };
    socket.add(utf8.encode(jsonEncode(responseMsg)));
    await socket.flush();
    
    // Read success/failure
    final resultBytes = await _readLine(socket);
    if (resultBytes == null) return false;
    
    final result = jsonDecode(utf8.decode(resultBytes)) as Map<String, dynamic>;
    return result['type'] == 'auth_success';
  }

  static Uint8List _generateChallenge() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  }

  static Uint8List _computeResponse(Uint8List challenge, Uint8List sharedSecret) {
    final key = sha256.convert(sharedSecret).bytes;
    return Uint8List.fromList(Hmac(sha256, key).convert(challenge).bytes);
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  static Future<Uint8List?> _readLine(Socket socket) async {
    final buffer = <int>[];
    await for (final chunk in socket) {
      buffer.addAll(chunk);
      if (buffer.contains(10)) { // newline
        final lineEnd = buffer.indexOf(10);
        return Uint8List.fromList(buffer.sublist(0, lineEnd));
      }
    }
    return null;
  }
}