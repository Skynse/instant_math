import 'step.dart' as models;

enum ProblemStatus {
  scanned,
  solved,
  archived,
}

enum DifficultyLevel {
  beginner,
  intermediate,
  advanced,
  graduate,
}

class Problem {
  final String id;
  final String title;
  final String rawEquation;
  final String? latexEquation;
  final String subject;
  final String topic;
  final DifficultyLevel level;
  final ProblemStatus status;
  final DateTime createdAt;
  final DateTime? solvedAt;
  final bool isVerified;
  final bool isFavorite;
  final String? imageUrl;

  Problem({
    required this.id,
    required this.title,
    required this.rawEquation,
    this.latexEquation,
    required this.subject,
    required this.topic,
    required this.level,
    this.status = ProblemStatus.scanned,
    required this.createdAt,
    this.solvedAt,
    this.isVerified = false,
    this.isFavorite = false,
    this.imageUrl,
  });

  Problem copyWith({
    String? id,
    String? title,
    String? rawEquation,
    String? latexEquation,
    String? subject,
    String? topic,
    DifficultyLevel? level,
    ProblemStatus? status,
    DateTime? createdAt,
    DateTime? solvedAt,
    bool? isVerified,
    bool? isFavorite,
    String? imageUrl,
  }) {
    return Problem(
      id: id ?? this.id,
      title: title ?? this.title,
      rawEquation: rawEquation ?? this.rawEquation,
      latexEquation: latexEquation ?? this.latexEquation,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      level: level ?? this.level,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      solvedAt: solvedAt ?? this.solvedAt,
      isVerified: isVerified ?? this.isVerified,
      isFavorite: isFavorite ?? this.isFavorite,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  String get levelLabel {
    switch (level) {
      case DifficultyLevel.beginner:
        return 'Beginner';
      case DifficultyLevel.intermediate:
        return 'Intermediate';
      case DifficultyLevel.advanced:
        return 'Advanced';
      case DifficultyLevel.graduate:
        return 'Graduate';
    }
  }

  String get statusLabel {
    switch (status) {
      case ProblemStatus.scanned:
        return 'Scanned';
      case ProblemStatus.solved:
        return 'Solved';
      case ProblemStatus.archived:
        return 'Archived';
    }
  }
}
