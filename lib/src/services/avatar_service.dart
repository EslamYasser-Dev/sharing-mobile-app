import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/integrity.dart';

class AvatarService {
  AvatarService({
    http.Client? httpClient,
    String? baseUrl,
  })  : _http = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? '').replaceAll(RegExp(r'/+$'), '');

  final http.Client _http;
  final String _baseUrl;
  final ImagePicker _picker = ImagePicker();

  static const int _maxDimension = 512;
  static const int _thumbnailDimension = 128;
  static const int _quality = 85;
  static const List<String> _allowedMimeTypes = ['image/jpeg', 'image/png', 'image/webp'];

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  /// Picks an image from the device gallery or camera.
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: _maxDimension.toDouble(),
        maxHeight: _maxDimension.toDouble(),
        imageQuality: _quality,
      );
    } catch (e) {
      return null;
    }
  }

  /// Processes an image file: validates, strips metadata, resizes, compresses.
  Future<ProcessedAvatar> processAvatar(XFile file) async {
    // Read raw bytes
    final bytes = await file.readAsBytes();

    // Validate MIME type by checking magic bytes
    final mimeType = _detectMimeType(bytes);
    if (!_allowedMimeTypes.contains(mimeType)) {
      throw AvatarException('Unsupported image format. Allowed: JPEG, PNG, WebP');
    }

    // Decode image
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw AvatarException('Failed to decode image');
    }

    // Validate dimensions
    if (image.width > 4096 || image.height > 4096) {
      throw AvatarException('Image dimensions too large (max 4096x4096)');
    }

    // Strip EXIF/metadata by re-encoding
    _stripMetadata(image, mimeType);

    // Generate thumbnail
    final thumbnail = img.copyResize(image, width: _thumbnailDimension, height: _thumbnailDimension);
    final thumbnailBytes = _encodeImage(thumbnail, mimeType);

    // Resize main image if needed
    img.Image processedImage = image;
    if (image.width > _maxDimension || image.height > _maxDimension) {
      processedImage = img.copyResize(image, width: _maxDimension, height: _maxDimension);
    }

    final processedBytes = _encodeImage(processedImage, mimeType);

    // Compute hashes for integrity
    final fullHash = await IntegrityService.computeBytesHash(Uint8List.fromList(processedBytes));
    final thumbHash = await IntegrityService.computeBytesHash(Uint8List.fromList(thumbnailBytes));

    return ProcessedAvatar(
      originalBytes: bytes,
      processedBytes: processedBytes,
      thumbnailBytes: thumbnailBytes,
      mimeType: mimeType,
      width: processedImage.width,
      height: processedImage.height,
      fullHash: fullHash,
      thumbnailHash: thumbHash,
    );
  }

  String _detectMimeType(Uint8List bytes) {
    if (bytes.length < 12) return 'application/octet-stream';

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return 'image/png';
    }
    // WebP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }

  void _stripMetadata(img.Image image, String mimeType) {
    // Re-encode without metadata - caller handles encoding
  }

  List<int> _encodeImage(img.Image image, String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return img.encodeJpg(image, quality: _quality);
      case 'image/png':
        return img.encodePng(image);
      case 'image/webp':
        // image package doesn't have encodeWebp, fallback to JPEG
        return img.encodeJpg(image, quality: _quality);
      default:
        return img.encodeJpg(image, quality: _quality);
    }
  }

  /// Uploads avatar to server.
  Future<AvatarUploadResult> uploadAvatar({
    required ProcessedAvatar avatar,
    required String accessToken,
  }) async {
    if (_baseUrl.isEmpty) {
      throw AvatarException('Base URL not configured');
    }

    final uri = _uri('/api/avatar');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';

    // Main avatar
    request.files.add(http.MultipartFile.fromBytes(
      'avatar',
      avatar.processedBytes,
      filename: 'avatar.${_mimeToExt(avatar.mimeType)}',
    ));

    // Thumbnail
    request.files.add(http.MultipartFile.fromBytes(
      'thumbnail',
      avatar.thumbnailBytes,
      filename: 'thumb.${_mimeToExt(avatar.mimeType)}',
    ));

    // Metadata
    request.fields['metadata'] = jsonEncode({
      'width': avatar.width,
      'height': avatar.height,
      'fullHash': avatar.fullHash,
      'thumbnailHash': avatar.thumbnailHash,
    });

    final streamedResponse = await _http.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.created) {
      throw AvatarException('Upload failed: ${response.body}');
    }

    return AvatarUploadResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Deletes current avatar.
  Future<void> deleteAvatar(String accessToken) async {
    if (_baseUrl.isEmpty) return;

    final response = await _http.delete(
      _uri('/api/avatar'),
      headers: {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
    );

    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.noContent) {
      throw AvatarException('Delete failed: ${response.body}');
    }
  }

  /// Fetches avatar URL for a user.
  String getAvatarUrl(String username, {bool thumbnail = false}) {
    return '${_baseUrl}/api/avatar/${Uri.encodeComponent(username)}${thumbnail ? '?thumbnail=true' : ''}';
  }

  String _mimeToExt(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg': return 'jpg';
      case 'image/png': return 'png';
      case 'image/webp': return 'webp';
      default: return 'jpg';
    }
  }

  void dispose() {
    _http.close();
  }
}

class ProcessedAvatar {
  const ProcessedAvatar({
    required this.originalBytes,
    required this.processedBytes,
    required this.thumbnailBytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.fullHash,
    required this.thumbnailHash,
  });

  final List<int> originalBytes;
  final List<int> processedBytes;
  final List<int> thumbnailBytes;
  final String mimeType;
  final int width;
  final int height;
  final String fullHash;
  final String thumbnailHash;

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'mimeType': mimeType,
    'fullHash': fullHash,
    'thumbnailHash': thumbnailHash,
  };
}

class AvatarUploadResult {
  const AvatarUploadResult({
    required this.url,
    required this.thumbnailUrl,
    required this.hash,
  });

  final String url;
  final String thumbnailUrl;
  final String hash;

  factory AvatarUploadResult.fromJson(Map<String, dynamic> json) => AvatarUploadResult(
    url: json['url'] as String? ?? '',
    thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
    hash: json['hash'] as String? ?? '',
  );
}

class AvatarException implements Exception {
  const AvatarException(this.message);
  final String message;

  @override
  String toString() => 'AvatarException: $message';
}

