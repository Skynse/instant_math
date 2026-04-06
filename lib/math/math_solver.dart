import 'dart:math' as math;
import 'expression_evaluator.dart';
import 'latex_translator.dart';

// ── Problem classification ─────────────────────────────────────────────────

enum ProblemType {
  arithmetic,           // constant expression — just evaluate
  expression,           // expression with a variable, no equation
  linearEquation,       // ax + b = c
  quadraticEquation,    // ax² + bx + c = 0
  systemOfEquations,    // 2 equations, 2 unknowns
  trigEquation,         // sin/cos/tan(expr) = k
  logEquation,          // log(expr) = k
  exponentialEquation,  // a^expr = b  (variable in exponent)
  linearInequality,     // ax + b > c
  identityCheck,        // numeric = numeric
  unsupported,
}

// ── Result types ─────────────────────────────────────────────────────────────

class SolverStep {
  final int number;
  final String title;
  final String description;
  final String formula;
  final String? explanation;

  const SolverStep({
    required this.number,
    required this.title,
    required this.description,
    required this.formula,
    this.explanation,
  });

  Map<String, dynamic> toMap() => {
        'number': number,
        'title': title,
        'description': description,
        'formula': formula,
        if (explanation != null) 'explanation': explanation,
      };
}

class SolverResult {
  final String finalAnswer;
  final List<SolverStep> steps;
  final String method;
  final bool success;
  final String? error;
  final ProblemType problemType;

  const SolverResult({
    required this.finalAnswer,
    required this.steps,
    required this.method,
    required this.success,
    required this.problemType,
    this.error,
  });

  Map<String, dynamic> toMap() => {
        'finalAnswer': finalAnswer,
        'steps': steps.map((s) => s.toMap()).toList(),
        'method': method,
        'problemType': problemType.name,
        if (error != null) 'error': error,
      };
}

// ── Solver ────────────────────────────────────────────────────────────────────

class MathSolver {
  static const _functionNames = {
    'sin', 'cos', 'tan', 'asin', 'acos', 'atan',
    'sqrt', 'log', 'log10', 'log2', 'logb', 'exp', 'abs', 'cbrt',
    'pi', 'e',
  };

  // ── entry point ────────────────────────────────────────────────────────────

  static SolverResult solve(String latex) {
    try {
      // System of equations: \begin{cases} ... \end{cases}
      if (latex.contains(r'\begin{cases}')) {
        return _solveSystemFromCases(latex);
      }

      final expr = LatexTranslator.translate(latex);

      // Semicolon-separated system (from _expandCases or manual input)
      if (expr.contains(';')) {
        final parts = expr.split(';').map((p) => p.trim()).toList();
        if (parts.length == 2 && parts.every((p) => p.contains('='))) {
          return _solveSystem(parts[0], parts[1], latex);
        }
      }

      // Inequality
      final ineqOp = _detectInequalityOp(expr);
      if (ineqOp.isNotEmpty) {
        return _solveLinearInequality(expr, latex, ineqOp);
      }

      // Expression vs equation
      if (!expr.contains('=')) {
        final variable = _detectVariable(expr);
        if (variable == null) return _evaluateArithmetic(expr, latex);
        return _displayExpression(expr, latex);
      }

      final eqIdx = expr.indexOf('=');
      final lhs = expr.substring(0, eqIdx).trim();
      final rhs = expr.substring(eqIdx + 1).trim();
      final variable = _detectVariable('$lhs $rhs');

      if (variable == null) return _checkIdentity(lhs, rhs, latex);

      // Classify equation type
      final type = _classifyEquation(lhs, rhs, variable);

      switch (type) {
        case ProblemType.trigEquation:
          return _solveTrigEquation(lhs, rhs, variable, latex);
        case ProblemType.logEquation:
          return _solveLogEquation(lhs, rhs, variable, latex);
        case ProblemType.exponentialEquation:
          return _solveExponentialEquation(lhs, rhs, variable, latex);
        default:
          return _solvePolynomial(lhs, rhs, variable, latex);
      }
    } on UnsupportedError catch (e) {
      return SolverResult(
        finalAnswer: 'Unsupported',
        steps: [],
        method: 'N/A',
        success: false,
        problemType: ProblemType.unsupported,
        error: e.message,
      );
    } catch (e) {
      return SolverResult(
        finalAnswer: 'Error',
        steps: [],
        method: 'N/A',
        success: false,
        problemType: ProblemType.unsupported,
        error: e.toString(),
      );
    }
  }

  // ── classification ─────────────────────────────────────────────────────────

  static ProblemType _classifyEquation(String lhs, String rhs, String variable) {
    final combined = '$lhs $rhs';

    // Trig: contains sin/cos/tan with the variable inside
    if (_containsTrig(combined) && _varInsideFunctions(combined, variable, {'sin', 'cos', 'tan'})) {
      return ProblemType.trigEquation;
    }

    // Log: contains log/log10/log2/logb with the variable inside
    if (_containsLog(combined) && _varInsideFunctions(combined, variable, {'log', 'log10', 'log2', 'logb'})) {
      return ProblemType.logEquation;
    }

    // Exponential: variable appears in an exponent position
    if (_hasVariableInExponent(combined, variable)) {
      return ProblemType.exponentialEquation;
    }

    // Polynomial degree via finite differences
    double h(double v) {
      final l = MathExpressionEvaluator.tryEvaluate(lhs, variables: {variable: v}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhs, variables: {variable: v}) ?? 0;
      return l - r;
    }

    final h0 = h(0), h1 = h(1), hm1 = h(-1), h2 = h(2), h3 = h(3);
    final thirdDiff = h3 - 3 * h2 + 3 * h1 - h0;
    if (thirdDiff.abs() > 1e-4) {
      throw UnsupportedError('Higher-degree or transcendental equations require a CAS.');
    }
    final secondDiff = h1 - 2 * h0 + hm1;
    return secondDiff.abs() > 1e-6
        ? ProblemType.quadraticEquation
        : ProblemType.linearEquation;
  }

  static String _detectInequalityOp(String expr) {
    if (expr.contains('>=')) return '>=';
    if (expr.contains('<=')) return '<=';
    if (expr.contains('>') && !expr.contains('=>')) return '>';
    if (expr.contains('<') && !expr.contains('=<')) return '<';
    return '';
  }

  static bool _containsTrig(String expr) =>
      RegExp(r'\b(sin|cos|tan)\(').hasMatch(expr);

  static bool _containsLog(String expr) =>
      RegExp(r'\b(log|log10|log2|logb)\(').hasMatch(expr);

  static bool _varInsideFunctions(String expr, String variable, Set<String> funcs) {
    for (final fn in funcs) {
      final pattern = RegExp('\\b$fn\\(');
      for (final m in pattern.allMatches(expr)) {
        final inner = _extractBalancedParens(expr, m.end - 1);
        if (inner.contains(variable)) return true;
      }
    }
    return false;
  }

  static bool _hasVariableInExponent(String expr, String variable) {
    // Look for: digits/letters followed by ^ with variable in the exponent
    final matches = RegExp(r'[0-9a-zA-Z.]+\^').allMatches(expr);
    for (final m in matches) {
      int i = m.end;
      if (i < expr.length && expr[i] == '(') {
        final inner = _extractBalancedParens(expr, i);
        if (inner.contains(variable)) return true;
      } else if (i < expr.length && expr[i] == variable) {
        return true;
      }
    }
    return false;
  }

  // ── arithmetic / expression display ───────────────────────────────────────

  static SolverResult _evaluateArithmetic(String expr, String original) {
    final value = MathExpressionEvaluator.tryEvaluate(expr);
    if (value == null) throw Exception('Cannot evaluate: $expr');
    final answer = _fmt(value);
    return SolverResult(
      finalAnswer: answer,
      steps: [
        SolverStep(
          number: 1,
          title: 'Evaluate',
          description: 'Compute the expression',
          formula: _latex(original),
          explanation: 'Substitute known values and apply the order of operations.',
        ),
        SolverStep(
          number: 2,
          title: 'Result',
          description: '= $answer',
          formula: _latex(answer),
        ),
      ],
      method: 'Direct evaluation',
      success: true,
      problemType: ProblemType.arithmetic,
    );
  }

  static SolverResult _displayExpression(String expr, String original) {
    return SolverResult(
      finalAnswer: 'Expression (no equation to solve)',
      steps: [
        SolverStep(
          number: 1,
          title: 'Expression',
          description: 'This is a mathematical expression, not an equation.',
          formula: _latex(original),
          explanation: 'Without an equals sign there is nothing to solve for — the expression can be simplified or evaluated at specific values.',
        ),
      ],
      method: 'Display only',
      success: true,
      problemType: ProblemType.expression,
    );
  }

  // ── identity check ─────────────────────────────────────────────────────────

  static SolverResult _checkIdentity(String lhs, String rhs, String original) {
    final lVal = MathExpressionEvaluator.tryEvaluate(lhs);
    final rVal = MathExpressionEvaluator.tryEvaluate(rhs);
    if (lVal != null && rVal != null) {
      final equal = (lVal - rVal).abs() < 1e-9;
      return SolverResult(
        finalAnswer: equal ? 'True' : 'False',
        steps: [
          SolverStep(
            number: 1,
            title: 'Evaluate both sides',
            description: 'LHS = ${_fmt(lVal)},  RHS = ${_fmt(rVal)}',
            formula: _latex(original),
          ),
          SolverStep(
            number: 2,
            title: 'Compare',
            description: equal ? 'Both sides are equal.' : 'The sides are not equal.',
            formula: _latex(equal ? r'\text{True}' : r'\text{False}'),
          ),
        ],
        method: 'Direct evaluation',
        success: true,
        problemType: ProblemType.identityCheck,
      );
    }
    throw Exception('Cannot evaluate identity');
  }

  // ── polynomial equations ───────────────────────────────────────────────────

  static SolverResult _solvePolynomial(
      String lhs, String rhs, String variable, String original) {
    double h(double v) {
      final l = MathExpressionEvaluator.tryEvaluate(lhs, variables: {variable: v}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhs, variables: {variable: v}) ?? 0;
      return l - r;
    }

    final h0 = h(0), h1 = h(1), hm1 = h(-1), h2 = h(2), h3 = h(3);
    final thirdDiff = h3 - 3 * h2 + 3 * h1 - h0;
    if (thirdDiff.abs() > 1e-4) {
      throw UnsupportedError('Only linear and quadratic equations are supported.');
    }
    final secondDiff = h1 - 2 * h0 + hm1;
    if (secondDiff.abs() > 1e-6) {
      final a = secondDiff / 2;
      final b = (h1 - hm1) / 2;
      final c = h0;
      return _solveQuadratic(a, b, c, variable, original);
    }
    final a = h1 - h0;
    final b = h0;
    return _solveLinear(a, b, variable, original);
  }

  // ── linear ────────────────────────────────────────────────────────────────

  static SolverResult _solveLinear(
      double a, double b, String variable, String original) {
    if (a.abs() < 1e-10) {
      final trivial = b.abs() < 1e-10;
      return SolverResult(
        finalAnswer: trivial ? 'All real numbers' : 'No solution',
        steps: [
          SolverStep(
            number: 1,
            title: trivial ? 'Identity' : 'Contradiction',
            description: trivial
                ? 'The equation holds for every value of $variable.'
                : 'No value of $variable satisfies this equation.',
            formula: _latex(original),
            explanation: trivial
                ? 'Both sides simplify to the same expression, so all real numbers are solutions.'
                : 'Both sides simplify to different constants — a contradiction.',
          ),
        ],
        method: 'Linear equation',
        success: true,
        problemType: ProblemType.linearEquation,
      );
    }

    final x = -b / a;
    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'Original equation',
        description: 'Start with the given equation.',
        formula: _latex(original),
        explanation: 'This is a linear equation in $variable — the highest power of $variable is 1.',
      ),
    ];

    if (b.abs() > 1e-10) {
      steps.add(SolverStep(
        number: 2,
        title: 'Isolate the variable term',
        description: 'Move the constant ${_fmt(b)} to the right side.',
        formula: _latex('${_fmt(a)}$variable = ${_fmt(-b)}'),
        explanation: 'Add ${_fmt(-b)} to both sides to isolate the term containing $variable.',
      ));
    }

    if ((a - 1).abs() > 1e-10) {
      steps.add(SolverStep(
        number: steps.length + 1,
        title: 'Solve for $variable',
        description: 'Divide both sides by ${_fmt(a)}.',
        formula: _latex('$variable = ${_fmt(x)}'),
        explanation: a < 0
            ? 'Dividing by a negative number does not affect the solution (unlike inequalities).'
            : 'Dividing isolates $variable on the left side.',
      ));
    }

    steps.add(SolverStep(
      number: steps.length + 1,
      title: 'Solution',
      description: '$variable = ${_fmt(x)}',
      formula: _latex('$variable = ${_fmt(x)}'),
    ));

    return SolverResult(
      finalAnswer: '$variable = ${_fmt(x)}',
      steps: steps,
      method: 'Linear equation',
      success: true,
      problemType: ProblemType.linearEquation,
    );
  }

  // ── quadratic ─────────────────────────────────────────────────────────────

  static SolverResult _solveQuadratic(
      double a, double b, double c, String variable, String original) {
    final disc = b * b - 4 * a * c;
    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'Identify as quadratic',
        description: 'Equation has degree 2 — use the quadratic formula.',
        formula: _latex('${_fmt(a)}${variable}^2 + (${_fmt(b)})$variable + (${_fmt(c)}) = 0'),
        explanation: 'A quadratic equation has the form ax² + bx + c = 0. Here a = ${_fmt(a)}, b = ${_fmt(b)}, c = ${_fmt(c)}.',
      ),
      SolverStep(
        number: 2,
        title: 'Compute the discriminant',
        description: r'Δ = b² − 4ac',
        formula: _latex(r'\Delta = ' '${_fmt(b)}^2 - 4 \\cdot ${_fmt(a)} \\cdot ${_fmt(c)} = ${_fmt(disc)}'),
        explanation: 'The discriminant Δ = b² − 4ac determines the number and type of solutions: Δ > 0 gives two real roots, Δ = 0 one repeated root, Δ < 0 complex roots.',
      ),
    ];

    String finalAnswer;
    if (disc < -1e-9) {
      final re = _fmt(-b / (2 * a));
      final im = _fmt(math.sqrt(-disc) / (2 * a));
      finalAnswer = '$variable = $re ± ${im}i';
      steps.add(SolverStep(
        number: 3,
        title: 'Complex roots (Δ < 0)',
        description: 'No real solutions exist.',
        formula: _latex('$variable = $re \\pm ${im}i'),
        explanation: 'When Δ < 0, the square root of a negative number introduces the imaginary unit i.',
      ));
    } else if (disc.abs() < 1e-9) {
      final x = _fmt(-b / (2 * a));
      finalAnswer = '$variable = $x (double root)';
      steps.add(SolverStep(
        number: 3,
        title: 'One repeated root (Δ = 0)',
        description: 'Both roots are equal.',
        formula: _latex('$variable = \\frac{-b}{2a} = $x'),
        explanation: 'When Δ = 0 the parabola is tangent to the x-axis — there is exactly one (repeated) solution.',
      ));
    } else {
      final sqrtDisc = math.sqrt(disc);
      final x1 = _fmt((-b + sqrtDisc) / (2 * a));
      final x2 = _fmt((-b - sqrtDisc) / (2 * a));
      finalAnswer = '$variable = $x1  or  $variable = $x2';
      steps.add(SolverStep(
        number: 3,
        title: 'Apply the quadratic formula',
        description: 'Two distinct real roots.',
        formula: _latex('$variable = \\frac{${_fmt(-b)} \\pm \\sqrt{${_fmt(disc)}}}{${_fmt(2 * a)}}'),
        explanation: 'The ± gives two solutions. Both are valid roots of the equation.',
      ));
      steps.add(SolverStep(
        number: 4,
        title: 'Evaluate both roots',
        description: '$variable = $x1  or  $variable = $x2',
        formula: _latex('$variable = $x1 \\quad \\text{or} \\quad $variable = $x2'),
      ));
    }

    return SolverResult(
      finalAnswer: finalAnswer,
      steps: steps,
      method: 'Quadratic formula',
      success: true,
      problemType: ProblemType.quadraticEquation,
    );
  }

  // ── system of 2 linear equations ─────────────────────────────────────────

  static SolverResult _solveSystemFromCases(String latex) {
    // Extract content inside \begin{cases}...\end{cases}
    final match = RegExp(
      r'\\begin\{cases\}(.*?)\\end\{cases\}',
      dotAll: true,
    ).firstMatch(latex);
    if (match == null) throw Exception('Could not parse \\begin{cases}');
    final inner = match.group(1)!;
    final rawEqs = inner
        .split(RegExp(r'\\\\|\\newline'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (rawEqs.length != 2) {
      throw UnsupportedError('Only 2-equation systems are supported.');
    }
    final eq1 = LatexTranslator.translate(rawEqs[0]);
    final eq2 = LatexTranslator.translate(rawEqs[1]);
    return _solveSystem(eq1, eq2, latex);
  }

  static SolverResult _solveSystem(
      String eq1, String eq2, String original) {
    // Detect two distinct variables
    final vars = _detectVariables('$eq1 $eq2');
    if (vars.length != 2) {
      throw UnsupportedError('Expected exactly 2 variables, found ${vars.length}.');
    }

    final varList = vars.toList();
    // Prefer common ordering
    const preferred = ['x', 'y', 'z', 'a', 'b'];
    varList.sort((a, b) {
      final ai = preferred.indexOf(a);
      final bi = preferred.indexOf(b);
      if (ai == -1 && bi == -1) return a.compareTo(b);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    final vx = varList[0];
    final vy = varList[1];

    final eqIdx1 = eq1.indexOf('=');
    final eqIdx2 = eq2.indexOf('=');
    if (eqIdx1 == -1 || eqIdx2 == -1) throw Exception('Equations must contain =');

    final lhs1 = eq1.substring(0, eqIdx1).trim();
    final rhs1 = eq1.substring(eqIdx1 + 1).trim();
    final lhs2 = eq2.substring(0, eqIdx2).trim();
    final rhs2 = eq2.substring(eqIdx2 + 1).trim();

    double h1(double x, double y) {
      final l = MathExpressionEvaluator.tryEvaluate(lhs1, variables: {vx: x, vy: y}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhs1, variables: {vx: x, vy: y}) ?? 0;
      return l - r;
    }

    double h2(double x, double y) {
      final l = MathExpressionEvaluator.tryEvaluate(lhs2, variables: {vx: x, vy: y}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhs2, variables: {vx: x, vy: y}) ?? 0;
      return l - r;
    }

    // Extract linear coefficients: h(x,y) = a*x + b*y + c
    final c1 = h1(0, 0);
    final a1 = h1(1, 0) - c1;
    final b1 = h1(0, 1) - c1;
    final c2 = h2(0, 0);
    final a2 = h2(1, 0) - c2;
    final b2 = h2(0, 1) - c2;

    // Verify linearity (cross-term check)
    final cross1 = h1(1, 1) - (h1(1, 0) + h1(0, 1) - c1);
    final cross2 = h2(1, 1) - (h2(1, 0) + h2(0, 1) - c2);
    if (cross1.abs() > 1e-6 || cross2.abs() > 1e-6) {
      throw UnsupportedError('Non-linear systems are not supported.');
    }

    // System: a1*x + b1*y = -c1,  a2*x + b2*y = -c2
    final k1 = -c1;
    final k2 = -c2;
    final det = a1 * b2 - a2 * b1;

    if (det.abs() < 1e-10) {
      // Check consistent or inconsistent
      final ratio = (a1.abs() > 1e-10) ? a2 / a1 : (b1.abs() > 1e-10 ? b2 / b1 : 0);
      final kRatio = (k1.abs() > 1e-10) ? k2 / k1 : 0;
      final infinite = (ratio - kRatio).abs() < 1e-9;
      return SolverResult(
        finalAnswer: infinite ? 'Infinitely many solutions' : 'No solution',
        steps: [
          SolverStep(
            number: 1,
            title: infinite ? 'Dependent system' : 'Inconsistent system',
            description: infinite
                ? 'The two equations represent the same line.'
                : 'The two equations are parallel lines — no intersection.',
            formula: _latex(original),
            explanation: 'The determinant D = 0 means the coefficient matrix is singular.',
          ),
        ],
        method: 'Cramer\'s Rule',
        success: true,
        problemType: ProblemType.systemOfEquations,
      );
    }

    final xVal = (k1 * b2 - k2 * b1) / det;
    final yVal = (a1 * k2 - a2 * k1) / det;

    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'System of 2 linear equations',
        description: 'Two equations, two unknowns ($vx and $vy).',
        formula: '${_latex(eq1)}\n${_latex(eq2)}',
        explanation: 'A 2×2 linear system has a unique solution when the lines it describes intersect at exactly one point.',
      ),
      SolverStep(
        number: 2,
        title: 'Standard form',
        description: 'Rewrite as a$vx + b$vy = k.',
        formula: '${_latex('${_fmt(a1)}$vx + (${_fmt(b1)})$vy = ${_fmt(k1)}')}\n'
            '${_latex('${_fmt(a2)}$vx + (${_fmt(b2)})$vy = ${_fmt(k2)}')}',
        explanation: 'Moving all variable terms to the left and constants to the right prepares the system for Cramer\'s Rule.',
      ),
      SolverStep(
        number: 3,
        title: 'Compute the determinant',
        description: 'D = a₁b₂ − a₂b₁ = ${_fmt(det)}',
        formula: _latex(
          'D = \\begin{vmatrix} ${_fmt(a1)} & ${_fmt(b1)} \\\\ ${_fmt(a2)} & ${_fmt(b2)} \\end{vmatrix} = ${_fmt(det)}',
        ),
        explanation: 'D ≠ 0 confirms the system has a unique solution.',
      ),
      SolverStep(
        number: 4,
        title: 'Apply Cramer\'s Rule',
        description: '$vx = D_x / D,  $vy = D_y / D',
        formula: _latex(
          '$vx = \\frac{${_fmt(k1 * b2 - k2 * b1)}}{${_fmt(det)}} = ${_fmt(xVal)}, \\quad '
          '$vy = \\frac{${_fmt(a1 * k2 - a2 * k1)}}{${_fmt(det)}} = ${_fmt(yVal)}',
        ),
        explanation: 'Cramer\'s Rule replaces each column of the coefficient matrix with the constant vector and divides by D.',
      ),
      SolverStep(
        number: 5,
        title: 'Solution',
        description: '$vx = ${_fmt(xVal)},  $vy = ${_fmt(yVal)}',
        formula: _latex('$vx = ${_fmt(xVal)}, \\quad $vy = ${_fmt(yVal)}'),
      ),
    ];

    return SolverResult(
      finalAnswer: '$vx = ${_fmt(xVal)},  $vy = ${_fmt(yVal)}',
      steps: steps,
      method: 'Cramer\'s Rule',
      success: true,
      problemType: ProblemType.systemOfEquations,
    );
  }

  // ── trig equation ─────────────────────────────────────────────────────────

  static SolverResult _solveTrigEquation(
      String lhs, String rhs, String variable, String original) {
    final trigMatch =
        RegExp(r'\b(sin|cos|tan)\(').firstMatch('$lhs $rhs');
    if (trigMatch == null) throw Exception('No trig function found');
    final funcName = trigMatch.group(1)!;

    // Locate the call in lhs or rhs
    final inLhs = lhs.contains('$funcName(');
    final targetExpr = inLhs ? lhs : rhs;

    final callStart = targetExpr.indexOf('$funcName(') + funcName.length;
    final innerExpr = _extractBalancedParens(targetExpr, callStart);
    final trigCall = '$funcName($innerExpr)';

    // Substitute u = trig(inner)
    final lhsU = lhs.replaceFirst(trigCall, 'u');
    final rhsU = rhs.replaceFirst(trigCall, 'u');

    double hU(double u) {
      final l = MathExpressionEvaluator.tryEvaluate(lhsU, variables: {'u': u}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhsU, variables: {'u': u}) ?? 0;
      return l - r;
    }

    final h0 = hU(0), h1 = hU(1), hm1 = hU(-1);
    final secondDiff = h1 - 2 * h0 + hm1;
    double uValue;
    if (secondDiff.abs() < 1e-6) {
      final slope = h1 - h0;
      if (slope.abs() < 1e-10) throw Exception('Cannot isolate trig value');
      uValue = -h0 / slope;
    } else {
      final a = secondDiff / 2;
      final b = (h1 - hm1) / 2;
      final c = h0;
      final disc = b * b - 4 * a * c;
      if (disc < 0) throw Exception('No real value for $funcName');
      uValue = (-b + math.sqrt(disc)) / (2 * a);
    }

    // Domain check
    if ((funcName == 'sin' || funcName == 'cos') && uValue.abs() > 1 + 1e-9) {
      return SolverResult(
        finalAnswer: 'No real solution',
        steps: [
          SolverStep(
            number: 1,
            title: 'Domain check failed',
            description:
                '|$funcName($variable)| must be ≤ 1, but the equation requires $funcName = ${_fmt(uValue)}.',
            formula: _latex(original),
            explanation: 'Sine and cosine are bounded in [−1, 1]. This equation has no real solutions.',
          ),
        ],
        method: 'Trigonometric substitution',
        success: true,
        problemType: ProblemType.trigEquation,
      );
    }

    // Compute base angle(s) (degrees)
    final List<double> baseAngles;
    final String periodStr;
    final String inverseLatex;
    switch (funcName) {
      case 'sin':
        final p = math.asin(uValue.clamp(-1.0, 1.0)) * 180 / math.pi;
        baseAngles = [p, 180 - p];
        periodStr = '360';
        inverseLatex = r'\arcsin';
        break;
      case 'cos':
        final p = math.acos(uValue.clamp(-1.0, 1.0)) * 180 / math.pi;
        baseAngles = [p, -p];
        periodStr = '360';
        inverseLatex = r'\arccos';
        break;
      default: // tan
        final p = math.atan(uValue) * 180 / math.pi;
        baseAngles = [p];
        periodStr = '180';
        inverseLatex = r'\arctan';
    }

    // For each base angle, solve innerExpr = angle for variable
    final solutions = <String>[];
    for (final deg in baseAngles.toSet()) {
      try {
        double hi(double v) =>
            (MathExpressionEvaluator.tryEvaluate(innerExpr,
                    variables: {variable: v}) ??
                0) -
            deg;
        final hiA = hi(1) - hi(0);
        if (hiA.abs() > 1e-10) {
          final xVal = -hi(0) / hiA;
          solutions.add(
              '$variable = ${_fmt(xVal)}° + n·$periodStr°');
        }
      } catch (_) {}
    }

    final solutionStr = solutions.isEmpty
        ? 'Principal value: $innerExpr = ${_fmt(baseAngles.first)}°'
        : solutions.join('  or  ');

    final uFmtd = _fmt(uValue);
    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'Trigonometric equation',
        description: 'Contains $funcName — use inverse trig.',
        formula: _latex(original),
        explanation:
            'We treat the entire trig call as a new variable u, solve algebraically, then invert.',
      ),
      SolverStep(
        number: 2,
        title: 'Let u = $funcName($innerExpr)',
        description: 'Substitute to get an algebraic equation in u.',
        formula: _latex('${lhsU.replaceAll('*', r' \cdot ')} = ${rhsU.replaceAll('*', r' \cdot ')}'),
        explanation:
            'Replacing the trig call with u converts the transcendental equation into a linear or quadratic one.',
      ),
      SolverStep(
        number: 3,
        title: 'Solve for u',
        description: 'u = $uFmtd',
        formula: _latex('u = $uFmtd'),
        explanation: 'This is the value that $funcName($innerExpr) must equal.',
      ),
      if (funcName == 'sin' || funcName == 'cos')
        SolverStep(
          number: 4,
          title: 'Check domain',
          description: '|u| = ${_fmt(uValue.abs())} ≤ 1 ✓',
          formula: _latex('-1 \\leq u \\leq 1'),
          explanation:
              'Sine and cosine output values only in [−1, 1]. Here the value is in range.',
        ),
      SolverStep(
        number: (funcName == 'tan') ? 4 : 5,
        title: 'Invert: $innerExpr = $inverseLatex(u)',
        description: baseAngles.map(_fmt).map((s) => '$s°').join(' or '),
        formula: _latex(
          '$innerExpr = $inverseLatex($uFmtd) = ${_fmt(baseAngles.first)}°'
          '${baseAngles.length > 1 ? " \\quad \\text{or} \\quad ${_fmt(baseAngles[1])}°" : ""}',
        ),
        explanation: funcName == 'sin'
            ? 'sin(θ) = sin(180° − θ), so there are two base solutions per full period.'
            : funcName == 'cos'
                ? 'cos(θ) = cos(−θ), so there are two base solutions per full period.'
                : 'tan has period 180°, giving one base solution per period.',
      ),
      SolverStep(
        number: (funcName == 'tan') ? 5 : 6,
        title: 'General solution',
        description: solutionStr,
        formula: _latex(
            solutionStr.replaceAll('·', r'\cdot').replaceAll('°', '^{\\circ}')),
        explanation:
            'Adding n·$periodStr° accounts for the periodicity of $funcName.',
      ),
    ];

    return SolverResult(
      finalAnswer: solutionStr,
      steps: steps,
      method: 'Trigonometric substitution',
      success: true,
      problemType: ProblemType.trigEquation,
    );
  }

  // ── log equation ──────────────────────────────────────────────────────────

  static SolverResult _solveLogEquation(
      String lhs, String rhs, String variable, String original) {
    // Find which log function appears
    final logMatch =
        RegExp(r'\b(log10|log2|logb|log)\(').firstMatch('$lhs $rhs');
    if (logMatch == null) throw Exception('No log function found');
    final funcName = logMatch.group(1)!;

    final inLhs = lhs.contains('$funcName(');
    final targetExpr = inLhs ? lhs : rhs;

    // Extract the argument to the log call
    final callStart = targetExpr.indexOf('$funcName(') + funcName.length;
    final fullInner = _extractBalancedParens(targetExpr, callStart);

    // For logb(base, expr) separate the base from the actual argument
    String innerExpr;
    double logBase;
    if (funcName == 'logb') {
      final commaIdx = _topLevelCommaIdx(fullInner);
      if (commaIdx == -1) throw Exception('logb requires two arguments');
      logBase = double.tryParse(fullInner.substring(0, commaIdx).trim()) ?? 10;
      innerExpr = fullInner.substring(commaIdx + 1).trim();
    } else {
      innerExpr = fullInner;
      logBase = funcName == 'log10'
          ? 10
          : funcName == 'log2'
              ? 2
              : math.e;
    }

    final logCall = '$funcName($fullInner)';
    final lhsU = lhs.replaceFirst(logCall, 'u');
    final rhsU = rhs.replaceFirst(logCall, 'u');

    // Solve for u (the log value)
    double hU(double u) {
      final l = MathExpressionEvaluator.tryEvaluate(lhsU, variables: {'u': u}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhsU, variables: {'u': u}) ?? 0;
      return l - r;
    }

    final slope = hU(1) - hU(0);
    if (slope.abs() < 1e-10) throw Exception('Cannot isolate log value');
    final uValue = -hU(0) / slope;

    // Invert: innerExpr = base^uValue
    final innerValue = math.pow(logBase, uValue).toDouble();

    // Solve innerExpr = innerValue for variable
    final solverResult = _solvePolynomial(innerExpr, _fmt(innerValue), variable, original);
    final finalX = solverResult.finalAnswer;

    final baseStr = logBase == math.e
        ? 'e'
        : logBase == 10
            ? '10'
            : _fmt(logBase);
    final logLabel = logBase == math.e
        ? r'\ln'
        : logBase == 10
            ? r'\log_{10}'
            : '\\log_{$baseStr}';

    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'Logarithmic equation',
        description: 'Contains $logLabel — exponentiate to isolate $variable.',
        formula: _latex(original),
        explanation:
            'The strategy is to isolate the log expression, then raise the base to both sides.',
      ),
      SolverStep(
        number: 2,
        title: 'Isolate the logarithm',
        description: '$logLabel($innerExpr) = ${_fmt(uValue)}',
        formula: _latex('$logLabel($innerExpr) = ${_fmt(uValue)}'),
        explanation:
            'Treat $logLabel($innerExpr) as a new variable u and solve the surrounding linear equation.',
      ),
      SolverStep(
        number: 3,
        title: 'Exponentiate both sides',
        description: '$innerExpr = $baseStr^${_fmt(uValue)} = ${_fmt(innerValue)}',
        formula: _latex(
          '$baseStr^{$logLabel($innerExpr)} = $baseStr^{${_fmt(uValue)}} \\implies $innerExpr = ${_fmt(innerValue)}',
        ),
        explanation:
            'Applying $baseStr^x to both sides cancels the logarithm: $baseStr^{$logLabel(x)} = x.',
      ),
      ...solverResult.steps
          .skip(1)
          .map((s) => SolverStep(
                number: s.number + 3,
                title: s.title,
                description: s.description,
                formula: s.formula,
                explanation: s.explanation,
              ))
          .toList(),
    ];

    return SolverResult(
      finalAnswer: finalX,
      steps: steps,
      method: 'Logarithmic equation',
      success: true,
      problemType: ProblemType.logEquation,
    );
  }

  // ── exponential equation ──────────────────────────────────────────────────

  static SolverResult _solveExponentialEquation(
      String lhs, String rhs, String variable, String original) {
    // Determine which side has the exponent with the variable
    final expMatch = RegExp(r'([0-9.]+)\^\(([^)]*)\)').firstMatch(lhs) ??
        RegExp(r'([0-9.]+)\^\(([^)]*)\)').firstMatch(rhs);
    if (expMatch == null) {
      // Try base^variable (no parens)
      final simpleMatch = RegExp(r'([0-9.]+)\^$variable').firstMatch('$lhs $rhs');
      if (simpleMatch != null) {
        final base = double.parse(simpleMatch.group(1)!);
        final constSide = lhs.contains('^') ? rhs : lhs;
        final constVal = MathExpressionEvaluator.tryEvaluate(constSide);
        if (constVal == null) throw Exception('Cannot evaluate right-hand side');
        return _exponentialSteps(base, variable, variable, constVal, original);
      }
      throw Exception('Cannot parse exponential form');
    }

    final base = double.parse(expMatch.group(1)!);
    final exponentExpr = expMatch.group(2)!;
    final constSide = expMatch.input == lhs ? rhs : lhs;
    final constVal = MathExpressionEvaluator.tryEvaluate(constSide);
    if (constVal == null || constVal <= 0) {
      throw Exception('Right-hand side must be a positive constant.');
    }

    return _exponentialSteps(base, exponentExpr, variable, constVal, original);
  }

  static SolverResult _exponentialSteps(double base, String exponentExpr,
      String variable, double constVal, String original) {
    if (base <= 0 || base == 1) {
      throw Exception('Base must be positive and ≠ 1.');
    }

    // exponentExpr = log(constVal) / log(base)
    final uValue = math.log(constVal) / math.log(base);
    final baseStr = _fmt(base);

    // Solve exponentExpr = uValue for variable
    final innerResult = _solvePolynomial(exponentExpr, _fmt(uValue), variable, original);

    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'Exponential equation',
        description: 'The variable appears in the exponent.',
        formula: _latex(original),
        explanation:
            'The strategy is to take the logarithm of both sides to bring the exponent down.',
      ),
      SolverStep(
        number: 2,
        title: 'Take log of both sides',
        description: 'log($baseStr^($exponentExpr)) = log(${_fmt(constVal)})',
        formula: _latex('\\log($baseStr^{$exponentExpr}) = \\log(${_fmt(constVal)})'),
        explanation: 'Any base logarithm works here. We use natural log for convenience.',
      ),
      SolverStep(
        number: 3,
        title: 'Apply log power rule',
        description: '($exponentExpr) · log($baseStr) = log(${_fmt(constVal)})',
        formula: _latex(
            '($exponentExpr) \\cdot \\ln($baseStr) = \\ln(${_fmt(constVal)})'),
        explanation: 'The power rule log(aⁿ) = n·log(a) moves the exponent to a coefficient.',
      ),
      SolverStep(
        number: 4,
        title: 'Isolate the exponent expression',
        description: '$exponentExpr = ${_fmt(uValue)}',
        formula: _latex(
            '$exponentExpr = \\frac{\\ln(${_fmt(constVal)})}{\\ln($baseStr)} = ${_fmt(uValue)}'),
        explanation:
            'Dividing both sides by ln($baseStr) gives the value the exponent expression must equal.',
      ),
      ...innerResult.steps
          .skip(1)
          .map((s) => SolverStep(
                number: s.number + 4,
                title: s.title,
                description: s.description,
                formula: s.formula,
                explanation: s.explanation,
              ))
          .toList(),
    ];

    return SolverResult(
      finalAnswer: innerResult.finalAnswer,
      steps: steps,
      method: 'Exponential equation',
      success: true,
      problemType: ProblemType.exponentialEquation,
    );
  }

  // ── linear inequality ─────────────────────────────────────────────────────

  static SolverResult _solveLinearInequality(
      String expr, String original, String op) {
    final parts = expr.split(op);
    if (parts.length != 2) throw Exception('Cannot parse inequality');
    final lhs = parts[0].trim();
    final rhs = parts[1].trim();
    final combined = '$lhs $rhs';
    final variable = _detectVariable(combined);
    if (variable == null) throw Exception('No variable found in inequality');

    // h(v) = lhs(v) - rhs(v) → linear coefficients
    double h(double v) {
      final l = MathExpressionEvaluator.tryEvaluate(lhs, variables: {variable: v}) ?? 0;
      final r = MathExpressionEvaluator.tryEvaluate(rhs, variables: {variable: v}) ?? 0;
      return l - r;
    }

    final a = h(1) - h(0);
    final b = h(0);

    if (a.abs() < 1e-10) {
      final trivial = b < 0; // h(v) < 0 means lhs < rhs always
      return SolverResult(
        finalAnswer: trivial ? 'All real numbers' : 'No solution',
        steps: [
          SolverStep(
            number: 1,
            title: trivial ? 'Always true' : 'Never true',
            description: trivial
                ? 'The inequality holds for all real $variable.'
                : 'No value of $variable satisfies this inequality.',
            formula: _latex(original),
          ),
        ],
        method: 'Linear inequality',
        success: true,
        problemType: ProblemType.linearInequality,
      );
    }

    final x = -b / a;
    // If a < 0, flip the inequality sign
    final resultOp = a < 0 ? _flipOp(op) : op;

    final steps = <SolverStep>[
      SolverStep(
        number: 1,
        title: 'Linear inequality',
        description: 'Solve for $variable — treat it like an equation, but watch for sign flips.',
        formula: _latex(original),
        explanation:
            'Inequalities are solved exactly like equations, except multiplying or dividing by a negative number reverses the direction.',
      ),
      if (b.abs() > 1e-10)
        SolverStep(
          number: 2,
          title: 'Move constant to the right',
          description: 'Subtract ${_fmt(b)} from both sides.',
          formula: _latex('${_fmt(a)}$variable $op ${_fmt(-b)}'),
          explanation: 'Adding or subtracting the same value from both sides does not change the inequality direction.',
        ),
      SolverStep(
        number: stepsCount(b) + 1,
        title: 'Divide by ${_fmt(a)}',
        description: a < 0
            ? 'Coefficient is negative — inequality sign flips!'
            : 'Coefficient is positive — sign is preserved.',
        formula: _latex('$variable $resultOp ${_fmt(x)}'),
        explanation: a < 0
            ? 'Dividing by a negative number reverses the ordering of the number line, so the inequality sign flips.'
            : 'Dividing by a positive number preserves the inequality direction.',
      ),
      SolverStep(
        number: stepsCount(b) + 2,
        title: 'Solution',
        description: '$variable $resultOp ${_fmt(x)}',
        formula: _latex('$variable $resultOp ${_fmt(x)}'),
      ),
    ];

    return SolverResult(
      finalAnswer: '$variable $resultOp ${_fmt(x)}',
      steps: steps,
      method: 'Linear inequality',
      success: true,
      problemType: ProblemType.linearInequality,
    );
  }

  static int stepsCount(double b) => b.abs() > 1e-10 ? 2 : 1;

  static String _flipOp(String op) => switch (op) {
        '>' => '<',
        '<' => '>',
        '>=' => '<=',
        '<=' => '>=',
        _ => op,
      };

  // ── helpers ───────────────────────────────────────────────────────────────

  static String? _detectVariable(String expr) {
    final identifiers =
        RegExp(r'[a-zA-Z]+').allMatches(expr).map((m) => m.group(0)!).toSet();
    final variables = identifiers
        .where((id) => !_functionNames.contains(id) && id.length == 1)
        .toList();
    if (variables.isEmpty) return null;
    const preferred = ['x', 'y', 'z', 't', 'n', 'm'];
    for (final v in preferred) {
      if (variables.contains(v)) return v;
    }
    return variables.first;
  }

  static Set<String> _detectVariables(String expr) {
    final identifiers =
        RegExp(r'[a-zA-Z]+').allMatches(expr).map((m) => m.group(0)!).toSet();
    return identifiers
        .where((id) => !_functionNames.contains(id) && id.length == 1)
        .toSet();
  }

  /// Extracts the content inside balanced parentheses starting at index [i]
  /// (which must point to the opening paren).
  static String _extractBalancedParens(String s, int i) {
    if (i >= s.length || s[i] != '(') return '';
    int depth = 0;
    final buf = StringBuffer();
    while (i < s.length) {
      final c = s[i++];
      if (c == '(') {
        if (++depth > 1) buf.write(c);
      } else if (c == ')') {
        if (--depth == 0) return buf.toString();
        buf.write(c);
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  /// Returns the index of the first top-level comma in [s] (not inside parens).
  static int _topLevelCommaIdx(String s) {
    int depth = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '(') depth++;
      else if (s[i] == ')') depth--;
      else if (s[i] == ',' && depth == 0) return i;
    }
    return -1;
  }

  static String _latex(String formula) => '\$\$${formula.trim()}\$\$';

  static String _fmt(double value) {
    if (value.isNaN) return 'undefined';
    if (value.isInfinite) return value > 0 ? '∞' : '-∞';
    if ((value - value.roundToDouble()).abs() < 1e-9) return value.toInt().toString();
    return value
        .toStringAsFixed(6)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  static String _fmtSigned(double value) {
    final s = _fmt(value);
    return value >= 0 ? '+$s' : s;
  }
}
