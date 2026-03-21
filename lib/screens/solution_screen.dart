import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../widgets/problem_card.dart';
import '../widgets/solution_step.dart';
import '../widgets/final_answer_card.dart';
import '../models/models.dart';

class SolutionScreen extends StatelessWidget {
  final Map<String, dynamic>? problem;
  final Map<String, dynamic>? solution;

  const SolutionScreen({
    super.key,
    this.problem,
    this.solution,
  });

  @override
  Widget build(BuildContext context) {
    // Use provided data or fallback to mock data
    final problemData = problem ?? {
      'title': 'Solve for x:',
      'equation': r'3(x - 5) + 4 = 2x + 8',
      'subject': 'Algebra',
      'topic': 'Linear Equations',
      'difficulty': 'intermediate',
    };

    final solutionData = solution ?? {
      'finalAnswer': r'$x = 19$',
      'steps': [
        {
          'number': 1,
          'title': 'Expand the expression',
          'description': 'Apply the distributive property to the left side.',
          'formula': r'$$3(x - 5) + 4 = 2x + 8$$' + '\n' + r'$$3x - 15 + 4 = 2x + 8$$',
        },
        {
          'number': 2,
          'title': 'Combine like terms',
          'description': 'On the left side, combine the constant terms -15 and +4.',
          'formula': r'$$3x - 11 = 2x + 8$$',
        },
        {
          'number': 3,
          'title': 'Isolate variable terms',
          'description': r'Subtract $2x$ from both sides to move all x-terms to the left.',
          'formula': r'$$3x - 2x - 11 = 2x - 2x + 8$$' + '\n' + r'$$x - 11 = 8$$',
        },
        {
          'number': 4,
          'title': 'Solve for x',
          'description': 'Add 11 to both sides to isolate x.',
          'formula': r'$$x - 11 + 11 = 8 + 11$$' + '\n' + r'$$x = 19$$',
        },
      ],
      'method': 'Algebraic manipulation',
    };

    final steps = (solutionData['steps'] as List<dynamic>? ?? []).map((step) {
      return SolutionStepModel(
        stepNumber: step['number'] ?? 1,
        title: step['title'] ?? '',
        description: step['description'] ?? '',
        latexFormula: step['formula'] ?? '',
      );
    }).toList();

    // Convert difficulty string to enum
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
      isVerified: true,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Academic Atelier'),
        actions: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey[300],
            child: const Icon(Icons.person, size: 18),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            
            // Current problem label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'CURRENT PROBLEM',
                  style: TextStyle(
                    color: AppColors.accentBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Problem card
            ProblemCard(
              title: problemObj.title,
              equation: problemObj.rawEquation,
              subject: problemObj.subject,
              topic: problemObj.topic,
              level: problemObj.levelLabel,
              isVerified: problemObj.isVerified,
            ),
            
            const SizedBox(height: 24),
            
            // Final result section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'FINAL RESULT',
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
              answer: solutionData['finalAnswer'] ?? r'$x = ?$',
              isVerified: true,
            ),
            
            const SizedBox(height: 16),
            
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.bookmark),
                      label: const Text('Save to History'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Explain More'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Logical Breakdown section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Logical Breakdown',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Steps
            if (steps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: steps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    return SolutionStep(
                      stepNumber: step.stepNumber,
                      title: step.title,
                      description: step.description,
                      formula: step.latexFormula,
                      isLast: index == steps.length - 1,
                    );
                  }).toList(),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'No solution steps available.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Related concept card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lightbulb,
                      color: AppColors.accentBlue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Related Concept',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Method used: ${solutionData['method'] ?? 'Standard approach'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                      ),
                      child: const Text('View Formula Sheet'),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
