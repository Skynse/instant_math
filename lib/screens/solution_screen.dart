import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../widgets/problem_card.dart';
import '../widgets/solution_step.dart';
import '../widgets/final_answer_card.dart';
import '../models/models.dart';

class SolutionScreen extends StatelessWidget {
  final Map<String, dynamic>? problem;
  final Map<String, dynamic>? solution;

  const SolutionScreen({super.key, this.problem, this.solution});

  @override
  Widget build(BuildContext context) {
    final problemData = problem ?? {
      'title': 'Solve for x:',
      'equation': r'3(x - 5) + 4 = 2x + 8',
      'subject': 'Algebra',
      'topic': 'Linear Equations',
      'difficulty': 'intermediate',
    };
    final solutionData = solution ?? {
      'finalAnswer': r'$$x = 19$$',
      'steps': [
        {
          'number': 1,
          'title': 'Expand',
          'description': 'Apply the distributive property.',
          'formula': r'$$3x - 15 + 4 = 2x + 8$$',
        },
        {
          'number': 2,
          'title': 'Combine like terms',
          'description': '',
          'formula': r'$$3x - 11 = 2x + 8$$',
        },
        {
          'number': 3,
          'title': 'Isolate x',
          'description': '',
          'formula': r'$$x = 19$$',
        },
      ],
      'method': 'Algebraic manipulation',
      'success': true,
    };

    final steps = (solutionData['steps'] as List<dynamic>? ?? []).map((step) {
      return SolutionStepModel(
        stepNumber: step['number'] ?? 1,
        title: step['title'] ?? '',
        description: step['description'] ?? '',
        latexFormula: step['formula'] ?? '',
        explanation: step['explanation'] as String?,
      );
    }).toList();

    DifficultyLevel difficultyLevel;
    switch (problemData['difficulty']?.toString().toLowerCase()) {
      case 'beginner':
        difficultyLevel = DifficultyLevel.beginner;
        break;
      case 'advanced':
        difficultyLevel = DifficultyLevel.advanced;
        break;
      case 'graduate':
        difficultyLevel = DifficultyLevel.graduate;
        break;
      default:
        difficultyLevel = DifficultyLevel.intermediate;
    }

    final problemObj = Problem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: problemData['title'] ?? 'Problem',
      rawEquation: problemData['equation'] ?? '',
      subject: problemData['subject'] ?? 'Mathematics',
      topic: problemData['topic'] ?? 'General',
      level: difficultyLevel,
      status: ProblemStatus.solved,
      createdAt: DateTime.now(),
      solvedAt: DateTime.now(),
      isVerified: solutionData['success'] == true,
    );

    final finalAnswer = _resolveAnswer(solutionData, problemData);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('MathWizard'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'SOLUTION',
                  style: TextStyle(
                    color: AppColors.accentBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            ProblemCard(
              title: problemObj.title,
              equation: problemObj.rawEquation,
              subject: problemObj.subject,
              topic: problemObj.topic,
              level: problemObj.levelLabel,
              isVerified: problemObj.isVerified,
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'FINAL ANSWER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FinalAnswerCard(
              answer: finalAnswer,
              isVerified: solutionData['success'] == true,
            ),

            if (solutionData['method'] != null &&
                (solutionData['method'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Method: ${solutionData['method']}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Step-by-Step Solution',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),

            if (steps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: steps.asMap().entries.map((entry) {
                    return SolutionStep(
                      stepNumber: entry.value.stepNumber,
                      title: entry.value.title,
                      description: entry.value.description,
                      formula: entry.value.latexFormula,
                      explanation: entry.value.explanation,
                      isLast: entry.key == steps.length - 1,
                    );
                  }).toList(),
                ),
              )
            else if (solutionData['success'] == false)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          solutionData['error']?.toString() ??
                              'Could not solve this problem.',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('No steps available.'),
              ),
          ],
        ),
      ),
    );
  }

  static String _resolveAnswer(
      Map<String, dynamic> solution, Map<String, dynamic> problem) {
    final a = solution['finalAnswer']?.toString() ?? '';
    if (a.isNotEmpty) return a;
    final eq = problem['equation']?.toString() ?? '';
    if (eq.isNotEmpty) return '\$\$${eq.trim()}\$\$';
    return 'Could not solve';
  }
}
