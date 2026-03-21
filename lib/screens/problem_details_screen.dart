import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../widgets/problem_card.dart';
import '../widgets/solution_step.dart';
import '../widgets/final_answer_card.dart';
import '../models/models.dart';

class ProblemDetailsScreen extends StatelessWidget {
  const ProblemDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock data for calculus problem
    final problem = Problem(
      id: '1024',
      title: 'Evaluate the following definite integral:',
      rawEquation: r'$\int_0^{\pi/2} \sin^5(x) \cos^3(x) \, dx$',
      subject: 'Calculus II',
      topic: 'Integration Techniques',
      level: DifficultyLevel.advanced,
      status: ProblemStatus.solved,
      createdAt: DateTime.now(),
      solvedAt: DateTime.now(),
      isVerified: true,
    );

    final steps = [
      SolutionStepModel(
        stepNumber: 1,
        title: 'Identity Application',
        description: 'Rewrite the cosine term using the Pythagorean identity to prepare for u-substitution.',
        latexFormula: r'$$\cos^2(x) = 1 - \sin^2(x)$$' + '\n' + 
                     r'$$\int_0^{\pi/2} \sin^5(x) \cdot \cos^2(x) \cdot \cos(x) \, dx$$' + '\n' +
                     r'$$= \int_0^{\pi/2} \sin^5(x) \cdot (1 - \sin^2(x)) \cdot \cos(x) \, dx$$',
      ),
      SolutionStepModel(
        stepNumber: 2,
        title: 'Substitution Variable',
        description: r'Let $u = \sin(x)$, then $du = \cos(x) \, dx$. Adjust the limits of integration accordingly.',
        latexFormula: r'$$u = \sin(x) \Rightarrow du = \cos(x) \, dx$$' + '\n' +
                     r'$$\text{When } x = 0: u = \sin(0) = 0$$' + '\n' +
                     r'$$\text{When } x = \frac{\pi}{2}: u = \sin\left(\frac{\pi}{2}\right) = 1$$',
      ),
      SolutionStepModel(
        stepNumber: 3,
        title: 'Expand and Simplify',
        description: 'Distribute and separate the integral into simpler polynomial terms.',
        latexFormula: r'$$= \int_0^1 u^5(1 - u^2) \, du$$' + '\n' +
                     r'$$= \int_0^1 (u^5 - u^7) \, du$$',
      ),
      SolutionStepModel(
        stepNumber: 4,
        title: 'Integration',
        description: 'Integrate the polynomial form with respect to u using the power rule.',
        latexFormula: r'$$= \left[\frac{u^6}{6} - \frac{u^8}{8}\right]_0^1$$' + '\n' +
                     r'$$= \left(\frac{1^6}{6} - \frac{1^8}{8}\right) - \left(\frac{0^6}{6} - \frac{0^8}{8}\right)$$' + '\n' +
                     r'$$= \frac{1}{6} - \frac{1}{8}$$',
      ),
      SolutionStepModel(
        stepNumber: 5,
        title: 'Final Calculation',
        description: 'Find a common denominator and compute the final result.',
        latexFormula: r'$$= \frac{4}{24} - \frac{3}{24} = \frac{1}{24}$$' + '\n' +
                     r'$$\approx 0.04167$$',
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Problem #1024'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            
            // Problem card
            ProblemCard(
              title: problem.title,
              equation: problem.rawEquation,
              subject: problem.subject,
              topic: problem.topic,
              level: problem.levelLabel,
              isVerified: problem.isVerified,
            ),
            
            const SizedBox(height: 32),
            
            // Step-by-Step Solution header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step-by-Step',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Guided derivation using u-substitution',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.unfold_less, size: 18),
                    label: const Text('Collapse\nSteps'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accentTeal,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Steps
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
            ),
            
            const SizedBox(height: 24),
            
            // Final answer
            FinalAnswerCard(
              answer: r'$\frac{1}{24}$',
              numericValue: 0.04167,
              isVerified: true,
            ),
            
            const SizedBox(height: 16),
            
            // Verify Solution button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.verified),
                  label: const Text('Verify Solution'),
                ),
              ),
            ),
            
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
