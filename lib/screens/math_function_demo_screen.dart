import 'package:flutter/material.dart';
import '../math/math.dart';
import '../services/ai_service.dart';
import '../theme/theme.dart';

class MathFunctionDemoScreen extends StatefulWidget {
  const MathFunctionDemoScreen({super.key});

  @override
  State<MathFunctionDemoScreen> createState() => _MathFunctionDemoScreenState();
}

class _MathFunctionDemoScreenState extends State<MathFunctionDemoScreen> {
  final TextEditingController _expressionController = TextEditingController();
  final AIService _aiService = AIService();
  
  String _result = '';
  String _steps = '';
  bool _isCalculating = false;

  void _evaluateExpression() {
    final expression = _expressionController.text;
    if (expression.isEmpty) return;

    setState(() {
      _isCalculating = true;
      _result = 'Calculating...';
      _steps = '';
    });

    try {
      // Use the expression evaluator directly
      final result = MathExpressionEvaluator.tryEvaluate(expression);
      
      setState(() {
        _isCalculating = false;
        if (result != null) {
          _result = 'Result: $result';
          _steps = 'Expression: $expression\nParsed and evaluated using shunting yard algorithm';
        } else {
          _result = 'Error: Could not evaluate expression';
        }
      });
    } catch (e) {
      setState(() {
        _isCalculating = false;
        _result = 'Error: $e';
      });
    }
  }

  void _testFunctionCalling() {
    setState(() {
      _isCalculating = true;
      _result = 'Testing function calling...';
    });

    // Simulate LLM response with function calls
    const llmResponse = '''
Step 1: Calculate 2 + 3
\$\$add({"numbers": [2, 3]})\$\$

Step 2: Multiply result by 4
\$\$multiply({"numbers": [5, 4]})\$\$

Final answer: 20
''';

    setState(() {
      _isCalculating = false;
      _result = 'Function calling test complete!';
      _steps = llmResponse;
    });
  }

  void _testQuadraticSolver() {
    setState(() {
      _isCalculating = true;
      _result = 'Solving quadratic equation...';
    });

    try {
      // Solve x² - 5x + 6 = 0
      final result = MathTools.executeTool('solve_quadratic', {
        'a': 1,
        'b': -5,
        'c': 6,
      });

      setState(() {
        _isCalculating = false;
        _result = 'Solutions: ${result['solutions']}';
        _steps = 'Equation: x² - 5x + 6 = 0\nUsing quadratic formula';
      });
    } catch (e) {
      setState(() {
        _isCalculating = false;
        _result = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Math Function Demo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Expression input
            TextField(
              controller: _expressionController,
              decoration: InputDecoration(
                labelText: 'Enter math expression',
                hintText: 'e.g., 2 + 3 * 4, sin(30), sqrt(16)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calculate),
                  onPressed: _evaluateExpression,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Evaluate button
            ElevatedButton.icon(
              onPressed: _isCalculating ? null : _evaluateExpression,
              icon: _isCalculating 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.calculate),
              label: const Text('Evaluate Expression'),
            ),
            const SizedBox(height: 8),
            
            // Test function calling
            OutlinedButton.icon(
              onPressed: _isCalculating ? null : _testFunctionCalling,
              icon: const Icon(Icons.functions),
              label: const Text('Test Function Calling'),
            ),
            const SizedBox(height: 8),
            
            // Test quadratic solver
            OutlinedButton.icon(
              onPressed: _isCalculating ? null : _testQuadraticSolver,
              icon: const Icon(Icons.scatter_plot),
              label: const Text('Test Quadratic Solver'),
            ),
            
            const SizedBox(height: 24),
            
            // Results
            if (_result.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Result:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _result,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            if (_steps.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Steps:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _steps,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Available functions list
            const Text(
              'Available Math Functions:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'add', 'subtract', 'multiply', 'divide',
                'power', 'square_root', 'factorial',
                'sin', 'cos', 'tan',
                'log', 'log10',
                'solve_linear', 'solve_quadratic',
              ].map((name) => Chip(
                label: Text(name),
                backgroundColor: AppColors.accentTeal.withValues(alpha: 0.1),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _expressionController.dispose();
    super.dispose();
  }
}
