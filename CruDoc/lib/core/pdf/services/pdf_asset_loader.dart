import 'dart:typed_data';

import 'package:http/http.dart' as http;

class PdfAssetLoader {
  const PdfAssetLoader({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<Uint8List?> loadRemoteBytes(String? url) async {
    final trimmedUrl = url?.trim();
    if (trimmedUrl == null || trimmedUrl.isEmpty) return null;

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || !uri.hasScheme) return null;

    final client = _client ?? http.Client();
    final shouldCloseClient = _client == null;

    try {
      final response = await client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.isNotEmpty && !contentType.toLowerCase().startsWith('image/')) {
        return null;
      }
      return response.bodyBytes.isEmpty ? null : response.bodyBytes;
    } catch (_) {
      return null;
    } finally {
      if (shouldCloseClient) client.close();
    }
  }
}