import 'dart:typed_data';
import '../math/expression_evaluator.dart';
import '../math/math_tools.dart';
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
  Future<Map<String, dynamic>> generateSolution(
      String equation, String subject) async {
    final result = await _server.solve(equation);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Server failed to solve equation');
    }
    return _serverResultToMap(result);
  }

  /// Process image AND solve in a single server round-trip.
  Future<Map<String, dynamic>> processImageAndSolve(
      Uint8List imageBytes) async {
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

    return {
      'finalAnswer': r['answer'] ?? '',
      'steps': steps,
      'method': r['method'] ?? '',
      'success': r['success'] ?? false,
      'problemType': r['problem_type'] ?? 'unknown',
      'error': r['error'],
      // Keep equation accessible at top level
      'equation': r['latex'] ?? '',
    };
  }

  String _inferTopic(String latex) {
    final lower = latex.toLowerCase();
    if (lower.contains(r'\int') || lower.contains('dx')) return 'Calculus';
    if (lower.contains(r'\sin') ||
        lower.contains(r'\cos') ||
        lower.contains(r'\tan')) return 'Trigonometry';
    if (lower.contains(r'\begin{cases}') || lower.split('=').length > 2) {
      return 'Systems of Equations';
    }
    if (lower.contains(r'\frac') || lower.contains('=')) return 'Algebra';
    return 'General';
  }

  // ── Local math utilities (no server needed) ────────────────────────────────

  double? calculate(String expression) =>
      MathExpressionEvaluator.tryEvaluate(expression);

  dynamic executeMathTool(String toolName, Map<String, dynamic> args) =>
      MathTools.executeTool(toolName, args);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {}

  Future<void> dispose() async {
    _server.dispose();
  }
}
