import 'dart:math' as math;

/// Represents a math tool that can be called by the LLM
class MathTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Function(Map<String, dynamic>) execute;

  MathTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters,
  };
}

/// Math tool definitions for function calling
class MathTools {
  static final List<MathTool> tools = [
    // Basic arithmetic
    MathTool(
      name: 'add',
      description: 'Add two or more numbers together',
      parameters: {
        'type': 'object',
        'properties': {
          'numbers': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'Numbers to add',
          },
        },
        'required': ['numbers'],
      },
      execute: (args) {
        List<dynamic> numbers = args['numbers'] ?? [];
        return numbers.fold(0.0, (sum, n) => sum + (n as num));
      },
    ),

    MathTool(
      name: 'subtract',
      description: 'Subtract numbers from the first number',
      parameters: {
        'type': 'object',
        'properties': {
          'minuend': {'type': 'number', 'description': 'The number to subtract from'},
          'subtrahends': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'Numbers to subtract',
          },
        },
        'required': ['minuend', 'subtrahends'],
      },
      execute: (args) {
        double minuend = (args['minuend'] as num).toDouble();
        List<dynamic> subtrahends = args['subtrahends'] ?? [];
        return subtrahends.fold(minuend, (result, n) => result - (n as num));
      },
    ),

    MathTool(
      name: 'multiply',
      description: 'Multiply two or more numbers',
      parameters: {
        'type': 'object',
        'properties': {
          'numbers': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'Numbers to multiply',
          },
        },
        'required': ['numbers'],
      },
      execute: (args) {
        List<dynamic> numbers = args['numbers'] ?? [];
        return numbers.fold(1.0, (product, n) => product * (n as num));
      },
    ),

    MathTool(
      name: 'divide',
      description: 'Divide the dividend by the divisor(s)',
      parameters: {
        'type': 'object',
        'properties': {
          'dividend': {'type': 'number', 'description': 'The number to divide'},
          'divisors': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'Numbers to divide by',
          },
        },
        'required': ['dividend', 'divisors'],
      },
      execute: (args) {
        double dividend = (args['dividend'] as num).toDouble();
        List<dynamic> divisors = args['divisors'] ?? [];
        return divisors.fold(dividend, (result, n) {
          double divisor = (n as num).toDouble();
          if (divisor == 0) throw Exception('Division by zero');
          return result / divisor;
        });
      },
    ),

    MathTool(
      name: 'power',
      description: 'Raise base to the power of exponent',
      parameters: {
        'type': 'object',
        'properties': {
          'base': {'type': 'number', 'description': 'The base number'},
          'exponent': {'type': 'number', 'description': 'The exponent'},
        },
        'required': ['base', 'exponent'],
      },
      execute: (args) {
        double base = (args['base'] as num).toDouble();
        double exponent = (args['exponent'] as num).toDouble();
        return math.pow(base, exponent);
      },
    ),

    MathTool(
      name: 'square_root',
      description: 'Calculate the square root of a number',
      parameters: {
        'type': 'object',
        'properties': {
          'number': {'type': 'number', 'description': 'The number to find square root of'},
        },
        'required': ['number'],
      },
      execute: (args) {
        double number = (args['number'] as num).toDouble();
        if (number < 0) throw Exception('Cannot compute square root of negative number');
        return math.sqrt(number);
      },
    ),

    MathTool(
      name: 'factorial',
      description: 'Calculate the factorial of a non-negative integer',
      parameters: {
        'type': 'object',
        'properties': {
          'n': {'type': 'integer', 'description': 'Non-negative integer'},
        },
        'required': ['n'],
      },
      execute: (args) {
        int n = (args['n'] as num).toInt();
        if (n < 0) throw Exception('Factorial not defined for negative numbers');
        if (n > 170) throw Exception('Number too large for factorial');
        double result = 1;
        for (int i = 2; i <= n; i++) {
          result *= i;
        }
        return result;
      },
    ),

    // Trigonometry
    MathTool(
      name: 'sin',
      description: 'Calculate sine of an angle (in degrees)',
      parameters: {
        'type': 'object',
        'properties': {
          'angle': {'type': 'number', 'description': 'Angle in degrees'},
        },
        'required': ['angle'],
      },
      execute: (args) {
        double angle = (args['angle'] as num).toDouble();
        return math.sin(angle * math.pi / 180);
      },
    ),

    MathTool(
      name: 'cos',
      description: 'Calculate cosine of an angle (in degrees)',
      parameters: {
        'type': 'object',
        'properties': {
          'angle': {'type': 'number', 'description': 'Angle in degrees'},
        },
        'required': ['angle'],
      },
      execute: (args) {
        double angle = (args['angle'] as num).toDouble();
        return math.cos(angle * math.pi / 180);
      },
    ),

    MathTool(
      name: 'tan',
      description: 'Calculate tangent of an angle (in degrees)',
      parameters: {
        'type': 'object',
        'properties': {
          'angle': {'type': 'number', 'description': 'Angle in degrees'},
        },
        'required': ['angle'],
      },
      execute: (args) {
        double angle = (args['angle'] as num).toDouble();
        return math.tan(angle * math.pi / 180);
      },
    ),

    // Logarithms
    MathTool(
      name: 'log',
      description: 'Calculate natural logarithm (ln)',
      parameters: {
        'type': 'object',
        'properties': {
          'number': {'type': 'number', 'description': 'Number to calculate log of'},
        },
        'required': ['number'],
      },
      execute: (args) {
        double number = (args['number'] as num).toDouble();
        if (number <= 0) throw Exception('Logarithm not defined for non-positive numbers');
        return math.log(number);
      },
    ),

    MathTool(
      name: 'log10',
      description: 'Calculate base-10 logarithm',
      parameters: {
        'type': 'object',
        'properties': {
          'number': {'type': 'number', 'description': 'Number to calculate log10 of'},
        },
        'required': ['number'],
      },
      execute: (args) {
        double number = (args['number'] as num).toDouble();
        if (number <= 0) throw Exception('Logarithm not defined for non-positive numbers');
        return math.log(number) / math.ln10;
      },
    ),

    // Constants
    MathTool(
      name: 'get_constant',
      description: 'Get mathematical constants like pi or e',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'enum': ['pi', 'e'],
            'description': 'Constant name',
          },
        },
        'required': ['name'],
      },
      execute: (args) {
        String name = args['name'];
        if (name == 'pi') return math.pi;
        if (name == 'e') return math.e;
        throw Exception('Unknown constant: $name');
      },
    ),

    // Equation solving
    MathTool(
      name: 'solve_linear',
      description: 'Solve a linear equation of form ax + b = c',
      parameters: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number', 'description': 'Coefficient of x'},
          'b': {'type': 'number', 'description': 'Constant term'},
          'c': {'type': 'number', 'description': 'Right side of equation'},
        },
        'required': ['a', 'b', 'c'],
      },
      execute: (args) {
        double a = (args['a'] as num).toDouble();
        double b = (args['b'] as num).toDouble();
        double c = (args['c'] as num).toDouble();
        if (a == 0) throw Exception('Not a linear equation (a = 0)');
        return (c - b) / a;
      },
    ),

    MathTool(
      name: 'solve_quadratic',
      description: 'Solve quadratic equation ax² + bx + c = 0',
      parameters: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number', 'description': 'Coefficient of x²'},
          'b': {'type': 'number', 'description': 'Coefficient of x'},
          'c': {'type': 'number', 'description': 'Constant term'},
        },
        'required': ['a', 'b', 'c'],
      },
      execute: (args) {
        double a = (args['a'] as num).toDouble();
        double b = (args['b'] as num).toDouble();
        double c = (args['c'] as num).toDouble();
        
        if (a == 0) throw Exception('Not a quadratic equation (a = 0)');
        
        double discriminant = b * b - 4 * a * c;
        
        if (discriminant < 0) {
          return {
            'real': false,
            'solutions': [
              {'real': -b / (2 * a), 'imaginary': math.sqrt(-discriminant) / (2 * a)},
              {'real': -b / (2 * a), 'imaginary': -math.sqrt(-discriminant) / (2 * a)},
            ],
          };
        }
        
        double sqrtDisc = math.sqrt(discriminant);
        return {
          'real': true,
          'solutions': [
            (-b + sqrtDisc) / (2 * a),
            (-b - sqrtDisc) / (2 * a),
          ],
        };
      },
    ),

    // Calculus
    MathTool(
      name: 'derivative_power_rule',
      description: 'Find derivative of x^n using power rule',
      parameters: {
        'type': 'object',
        'properties': {
          'n': {'type': 'number', 'description': 'Exponent'},
        },
        'required': ['n'],
      },
      execute: (args) {
        double n = (args['n'] as num).toDouble();
        return {'coefficient': n, 'newExponent': n - 1};
      },
    ),

    // Statistics
    MathTool(
      name: 'mean',
      description: 'Calculate arithmetic mean of a list of numbers',
      parameters: {
        'type': 'object',
        'properties': {
          'numbers': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'List of numbers',
          },
        },
        'required': ['numbers'],
      },
      execute: (args) {
        List<dynamic> numbers = args['numbers'] ?? [];
        if (numbers.isEmpty) throw Exception('Cannot calculate mean of empty list');
        double sum = numbers.fold(0.0, (s, n) => s + (n as num));
        return sum / numbers.length;
      },
    ),

    MathTool(
      name: 'evaluate_expression',
      description: 'Evaluate a mathematical expression string',
      parameters: {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string', 'description': 'Math expression to evaluate'},
        },
        'required': ['expression'],
      },
      execute: (args) {
        String expression = args['expression'];
        // Use the expression evaluator
        return expression;
      },
    ),
  ];

  /// Get a tool by name
  static MathTool? getTool(String name) {
    try {
      return tools.firstWhere((tool) => tool.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Execute a tool by name with arguments
  static dynamic executeTool(String name, Map<String, dynamic> args) {
    final tool = getTool(name);
    if (tool == null) {
      throw Exception('Tool not found: $name');
    }
    return tool.execute(args);
  }

  /// Get all tool definitions as JSON for LLM
  static List<Map<String, dynamic>> getToolDefinitions() {
    return tools.map((tool) => tool.toJson()).toList();
  }
}
