import 'problem.dart';
import 'step.dart' as models;

class Solution {
  final String id;
  final String problemId;
  final String finalAnswer;
  final String? finalAnswerLatex;
  final double? numericValue;
  final List<models.SolutionStepModel> steps;
  final String method;
  final String? verificationLogic;
  final bool isVerified;
  final DateTime solvedAt;
  final String? relatedFormulaId;

  Solution({
    required this.id,
    required this.problemId,
    required this.finalAnswer,
    this.finalAnswerLatex,
    this.numericValue,
    required this.steps,
    required this.method,
    this.verificationLogic,
    this.isVerified = false,
    required this.solvedAt,
    this.relatedFormulaId,
  });
}
