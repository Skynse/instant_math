import 'dart:math' as math;

/// Token types for the math expression parser
enum TokenType {
  number,
  variable,
  operator,
  function,
  leftParen,
  rightParen,
  comma,
}

/// Token class representing a single token in the expression
class Token {
  final TokenType type;
  final String value;
  final int precedence;
  final bool rightAssociative;

  Token({
    required this.type,
    required this.value,
    this.precedence = 0,
    this.rightAssociative = false,
  });

  @override
  String toString() => 'Token($type: $value)';
}

/// Math expression evaluator using shunting yard algorithm
class MathExpressionEvaluator {
  static final Map<String, int> _operatorPrecedence = {
    '+': 1,
    '-': 1,
    '*': 2,
    '/': 2,
    '%': 2,
    '^': 3,
    '√': 4,
  };

  static final Map<String, bool> _rightAssociative = {
    '^': true,
    '√': true,
  };

  static final Map<String, Function> _functions = {
    'sin': (List<dynamic> args) => args.isNotEmpty ? math.sin(_toRadians(args[0])) : 0,
    'cos': (List<dynamic> args) => args.isNotEmpty ? math.cos(_toRadians(args[0])) : 0,
    'tan': (List<dynamic> args) => args.isNotEmpty ? math.tan(_toRadians(args[0])) : 0,
    'asin': (List<dynamic> args) => args.isNotEmpty ? math.asin(args[0]) : 0,
    'acos': (List<dynamic> args) => args.isNotEmpty ? math.acos(args[0]) : 0,
    'atan': (List<dynamic> args) => args.isNotEmpty ? math.atan(args[0]) : 0,
    'sqrt': (List<dynamic> args) => args.isNotEmpty ? math.sqrt(args[0]) : 0,
    'cbrt': (List<dynamic> args) => args.isNotEmpty ? math.pow(args[0], 1 / 3) : 0,
    'log': (List<dynamic> args) => args.isNotEmpty ? math.log(args[0]) : 0,
    'log10': (List<dynamic> args) => args.isNotEmpty ? math.log(args[0]) / math.ln10 : 0,
    'exp': (List<dynamic> args) => args.isNotEmpty ? math.exp(args[0]) : 0,
    'abs': (List<dynamic> args) => args.isNotEmpty ? args[0].abs() : 0,
    'floor': (List<dynamic> args) => args.isNotEmpty ? args[0].floorToDouble() : 0,
    'ceil': (List<dynamic> args) => args.isNotEmpty ? args[0].ceilToDouble() : 0,
    'round': (List<dynamic> args) => args.isNotEmpty ? args[0].roundToDouble() : 0,
    'max': (List<dynamic> args) => args.isNotEmpty ? args.reduce((a, b) => a > b ? a : b) : 0,
    'min': (List<dynamic> args) => args.isNotEmpty ? args.reduce((a, b) => a < b ? a : b) : 0,
    'pow': (List<dynamic> args) => args.length >= 2 ? math.pow(args[0], args[1]) : 0,
    'fact': (List<dynamic> args) => args.isNotEmpty ? _factorial(args[0].toInt()) : 0,
    'log2': (List<dynamic> args) => args.isNotEmpty ? math.log(args[0]) / math.log(2) : 0,
    // logb(base, x) = log(x)/log(base)
    'logb': (List<dynamic> args) => args.length >= 2 ? math.log(args[1]) / math.log(args[0]) : 0,
    'pi': (List<dynamic> args) => math.pi,
    'e': (List<dynamic> args) => math.e,
  };

  // Functions that consume two arguments from the stack
  static const _twoArgFunctions = {'logb', 'pow'};

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _factorial(int n) {
    if (n <= 1) return 1;
    double result = 1;
    for (int i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  /// Tokenize the input expression
  static List<Token> tokenize(String expression) {
    List<Token> tokens = [];
    String current = '';
    int i = 0;

    while (i < expression.length) {
      String char = expression[i];

      // Skip whitespace
      if (char.trim().isEmpty) {
        i++;
        continue;
      }

      // Handle numbers (including decimals)
      if (_isDigit(char) || (char == '.' && current.isEmpty)) {
        current = '';
        while (i < expression.length && (_isDigit(expression[i]) || expression[i] == '.')) {
          current += expression[i];
          i++;
        }
        tokens.add(Token(type: TokenType.number, value: current));
        continue;
      }

      // Handle negative numbers and unary minus
      if (char == '-') {
        // Check if it's a unary minus (start of expression or after operator or after left paren)
        if (tokens.isEmpty ||
            tokens.last.type == TokenType.operator ||
            tokens.last.type == TokenType.leftParen ||
            tokens.last.type == TokenType.comma) {
          // This is a unary minus, treat as part of number
          current = '-';
          i++;
          // Continue reading the number
          while (i < expression.length && (_isDigit(expression[i]) || expression[i] == '.')) {
            current += expression[i];
            i++;
          }
          tokens.add(Token(type: TokenType.number, value: current));
          continue;
        }
      }

      // Handle operators
      if (_operatorPrecedence.containsKey(char)) {
        tokens.add(Token(
          type: TokenType.operator,
          value: char,
          precedence: _operatorPrecedence[char]!,
          rightAssociative: _rightAssociative[char] ?? false,
        ));
        i++;
        continue;
      }

      // Handle parentheses
      if (char == '(') {
        tokens.add(Token(type: TokenType.leftParen, value: char));
        i++;
        continue;
      }

      if (char == ')') {
        tokens.add(Token(type: TokenType.rightParen, value: char));
        i++;
        continue;
      }

      // Handle commas (for function arguments)
      if (char == ',') {
        tokens.add(Token(type: TokenType.comma, value: char));
        i++;
        continue;
      }

      // Handle functions and variables (letters)
      if (_isLetter(char)) {
        current = '';
        while (i < expression.length && (_isLetter(expression[i]) || _isDigit(expression[i]))) {
          current += expression[i];
          i++;
        }

        // Check if it's a function
        if (_functions.containsKey(current.toLowerCase())) {
          tokens.add(Token(type: TokenType.function, value: current.toLowerCase()));
        } else if (current == 'pi' || current == 'e') {
          // Constants
          tokens.add(Token(type: TokenType.function, value: current.toLowerCase()));
        } else {
          // Variable
          tokens.add(Token(type: TokenType.variable, value: current));
        }
        continue;
      }

      // Handle square root symbol
      if (char == '√') {
        tokens.add(Token(
          type: TokenType.operator,
          value: '√',
          precedence: 4,
          rightAssociative: true,
        ));
        i++;
        continue;
      }

      i++;
    }

    return tokens;
  }

  /// Convert infix tokens to postfix notation using shunting yard algorithm
  static List<Token> shuntingYard(List<Token> tokens) {
    List<Token> output = [];
    List<Token> operatorStack = [];

    for (Token token in tokens) {
      switch (token.type) {
        case TokenType.number:
        case TokenType.variable:
          output.add(token);
          break;

        case TokenType.function:
          operatorStack.add(token);
          break;

        case TokenType.operator:
          while (operatorStack.isNotEmpty) {
            Token top = operatorStack.last;
            if (top.type == TokenType.operator &&
                ((token.rightAssociative && token.precedence < top.precedence) ||
                    (!token.rightAssociative && token.precedence <= top.precedence))) {
              output.add(operatorStack.removeLast());
            } else {
              break;
            }
          }
          operatorStack.add(token);
          break;

        case TokenType.leftParen:
          operatorStack.add(token);
          break;

        case TokenType.rightParen:
          while (operatorStack.isNotEmpty && operatorStack.last.type != TokenType.leftParen) {
            output.add(operatorStack.removeLast());
          }
          // Pop the left parenthesis
          if (operatorStack.isNotEmpty && operatorStack.last.type == TokenType.leftParen) {
            operatorStack.removeLast();
          }
          // If there's a function on top of the stack, pop it
          if (operatorStack.isNotEmpty && operatorStack.last.type == TokenType.function) {
            output.add(operatorStack.removeLast());
          }
          break;

        case TokenType.comma:
          // Pop operators until left parenthesis
          while (operatorStack.isNotEmpty && operatorStack.last.type != TokenType.leftParen) {
            output.add(operatorStack.removeLast());
          }
          break;
      }
    }

    // Pop remaining operators
    while (operatorStack.isNotEmpty) {
      output.add(operatorStack.removeLast());
    }

    return output;
  }

  /// Evaluate postfix expression
  static double evaluatePostfix(List<Token> postfix, {Map<String, double>? variables}) {
    List<dynamic> stack = [];

    for (Token token in postfix) {
      switch (token.type) {
        case TokenType.number:
          stack.add(double.parse(token.value));
          break;

        case TokenType.variable:
          if (variables != null && variables.containsKey(token.value)) {
            stack.add(variables[token.value]!);
          } else {
            throw Exception('Unknown variable: ${token.value}');
          }
          break;

        case TokenType.operator:
          if (token.value == '√') {
            // Unary square root
            if (stack.isEmpty) throw Exception('Insufficient operands for √');
            double operand = stack.removeLast();
            stack.add(math.sqrt(operand));
          } else {
            // Binary operators
            if (stack.length < 2) throw Exception('Insufficient operands for ${token.value}');
            double b = stack.removeLast();
            double a = stack.removeLast();
            stack.add(_applyOperator(token.value, a, b));
          }
          break;

        case TokenType.function:
          List<dynamic> args = [];
          if (_twoArgFunctions.contains(token.value) && stack.length >= 2) {
            final arg2 = stack.removeLast();
            final arg1 = stack.removeLast();
            args = [arg1, arg2];
          } else if (stack.isNotEmpty) {
            args.add(stack.removeLast());
          }

          if (_functions.containsKey(token.value)) {
            double result = _functions[token.value]!(args);
            stack.add(result);
          } else {
            throw Exception('Unknown function: ${token.value}');
          }
          break;

        default:
          break;
      }
    }

    if (stack.length != 1) {
      throw Exception('Invalid expression');
    }

    return stack.first;
  }

  static double _applyOperator(String op, double a, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '*':
        return a * b;
      case '/':
        if (b == 0) throw Exception('Division by zero');
        return a / b;
      case '%':
        return a % b;
      case '^':
        return math.pow(a, b).toDouble();
      default:
        throw Exception('Unknown operator: $op');
    }
  }

  /// Main evaluation method
  static double evaluate(String expression, {Map<String, double>? variables}) {
    List<Token> tokens = tokenize(expression);
    List<Token> postfix = shuntingYard(tokens);
    return evaluatePostfix(postfix, variables: variables);
  }

  /// Safe evaluation that returns null on error instead of throwing
  static double? tryEvaluate(String expression, {Map<String, double>? variables}) {
    try {
      return evaluate(expression, variables: variables);
    } catch (e) {
      print('Math evaluation error: $e');
      return null;
    }
  }

  static bool _isDigit(String char) => char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
  static bool _isLetter(String char) {
    int code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}

/// Extension methods for math operations
extension MathExpressionExtension on String {
  double? evaluateMath({Map<String, double>? variables}) {
    return MathExpressionEvaluator.tryEvaluate(this, variables: variables);
  }
}
