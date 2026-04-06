import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Configuration for the MathWizard Python server.
/// Change [baseUrl] to match your machine's LAN IP.
class ServerConfig {
  // ── UPDATE THIS IP to your machine's LAN IP ──────────────────────────────
  static const String baseUrl = 'http://192.168.1.10:8000';
  // ─────────────────────────────────────────────────────────────────────────

  static const Duration timeout = Duration(seconds: 180);
}

/// HTTP client for the MathWizard Python FastAPI server.
class ServerService {
  static final ServerService _instance = ServerService._internal();
  factory ServerService() => _instance;
  ServerService._internal();

  final http.Client _client = http.Client();

  /// Check whether the server is reachable.
  Future<bool> checkHealth() async {
    try {
      final res = await _client
          .get(Uri.parse('${ServerConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Send an image to the server for OCR → LaTeX.
  Future<String> ocrImage(Uint8List imageBytes) async {
    final uri = Uri.parse('${ServerConfig.baseUrl}/ocr');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    final streamed = await req.send().timeout(ServerConfig.timeout);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception('OCR failed (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['latex'] as String;
  }

  /// Send a LaTeX string to the server for step-by-step solving.
  Future<Map<String, dynamic>> solve(String latex) async {
    final res = await _client
        .post(
          Uri.parse('${ServerConfig.baseUrl}/solve'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'latex': latex}),
        )
        .timeout(ServerConfig.timeout);

    if (res.statusCode != 200) {
      throw Exception('Solve failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Send an image to the server; returns OCR + solution in one call.
  Future<Map<String, dynamic>> ocrAndSolve(Uint8List imageBytes) async {
    final uri = Uri.parse('${ServerConfig.baseUrl}/ocr-and-solve');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    final streamed = await req.send().timeout(ServerConfig.timeout);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception('OCR+Solve failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void dispose() => _client.close();
}
