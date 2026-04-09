import 'dart:typed_data';
import 'server_service.dart';

/// Service class for handling AI/math operations via the Python FastAPI server.
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final ServerService _server = ServerService();

  bool get isInitialized => true;
  bool get isModelInstalled => true;
  bool get isModelLoaded => true;

  // ── Server connectivity ────────────────────────────────────────────────────

  /// Returns true if the Python server is reachable.
  Future<bool> checkServerHealth() => _server.checkHealth();

  // ── Image → solution pipeline ──────────────────────────────────────────────

  /// Process an image: run OCR on server, return problem map.
  Future<Map<String, dynamic>> processImage(Uint8List imageBytes) async {
    final latex = await _server.ocrImage(imageBytes);
    return {
      'title': 'Detected Problem',
      'equation': latex,
      'subject': 'Mathematics',
      'topic': _inferTopic(latex),
      'difficulty': 'intermediate',
    };
  }

  /// Solve a LaTeX equation via the server; returns a solution map.
  Future<Map<String, dynamic>> generateSolution(String equation, String subject) async {
    final result = await _server.solve(equation);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Server failed to solve equation');
    }
    return _serverResultToMap(result);
  }

  /// Process image AND solve in a single server round-trip.
  Future<Map<String, dynamic>> processImageAndSolve(Uint8List imageBytes) async {
    final result = await _server.ocrAndSolve(imageBytes);
    return _serverResultToMap(result);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _serverResultToMap(Map<String, dynamic> r) {
    final rawSteps = r['steps'] as List<dynamic>? ?? [];
    final steps = rawSteps.map((s) {
      final m = s as Map<String, dynamic>;
      return {
        'number': m['number'],
        'title': m['title'] ?? '',
        'description': m['description'] ?? '',
        'formula': m['formula'] ?? '',
        'explanation': m['explanation'],
      };
    }).toList();

    final latex = r['latex'] as String? ?? '';

    return {
      'finalAnswer': r['finalAnswer'] as String? ?? r['answer'] as String? ?? '',
      'steps': steps,
      'method': r['method'] ?? '',
      'success': r['success'] ?? false,
      'problemType': r['problem_type'] ?? 'unknown',
      'error': r['error'],
      'equation': latex,
      'title': _titleFromLatex(latex, r['problem_type'] as String? ?? ''),
    };
  }

  String _titleFromLatex(String latex, String problemType) {
    if (latex.isEmpty) return 'Detected Problem';
    final typeLabel = {
      'linear': 'Linear Equation',
      'quadratic': 'Quadratic Equation',
      'polynomial': 'Polynomial Equation',
      'system': 'System of Equations',
      'inequality': 'Inequality',
      'indefinite_integral': 'Indefinite Integral',
      'definite_integral': 'Definite Integral',
      'derivative_order_1': 'Derivative',
      'derivative_order_2': 'Second Derivative',
      'limit': 'Limit',
      'arithmetic': 'Expression',
    }[problemType];
    return typeLabel ?? 'Math Problem';
  }

  String _inferTopic(String latex) {
    final lower = latex.toLowerCase();
    if (lower.contains(r'\int') || lower.contains('dx')) return 'Calculus';
    if (lower.contains(r'\lim')) return 'Limits';
    if (lower.contains(r'\frac{d}') || lower.contains(r"d/d")) return 'Calculus';
    if (lower.contains(r'\sin') ||
        lower.contains(r'\cos') ||
        lower.contains(r'\tan')) return 'Trigonometry';
    if (lower.contains(r'\begin{cases}') || lower.split('=').length > 2) {
      return 'Systems of Equations';
    }
    if (lower.contains(r'\frac') || lower.contains('=')) return 'Algebra';
    return 'General';
  }

  Future<void> dispose() async {
    _server.dispose();
  }
}
