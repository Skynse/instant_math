import 'problem.dart';
import 'solution.dart';

class HistoryItem {
  final String id;
  final Problem problem;
  final Solution? solution;
  final DateTime timestamp;
  final bool isFavorite;

  HistoryItem({
    required this.id,
    required this.problem,
    this.solution,
    required this.timestamp,
    this.isFavorite = false,
  });
}
