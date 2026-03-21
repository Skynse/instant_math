import 'dart:convert';
import '../math/expression_evaluator.dart';
import '../math/math_tools.dart';

/// Represents a function call from the LLM
class FunctionCall {
  final String name;
  final Map<String, dynamic> arguments;

  FunctionCall({
    required this.name,
    required this.arguments,
  });

  factory FunctionCall.fromJson(Map<String, dynamic> json) {
    return FunctionCall(
      name: json['name'] ?? '',
      arguments: json['arguments'] ?? {},
    );
  }
}

/// Result of a function execution
class FunctionResult {
  final String functionName;
  final dynamic result;
  final String? error;

  FunctionResult({
    required this.functionName,
    this.result,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'function': functionName,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };
}

/// Service for handling function calling with math operations
class FunctionCallingService {
  static final FunctionCallingService _instance = FunctionCallingService._internal();
  factory FunctionCallingService() => _instance;
  FunctionCallingService._internal();

  /// Parse function calls from LLM response
  List<FunctionCall> parseFunctionCalls(String response) {
    List<FunctionCall> calls = [];
    
    // Look for function call patterns in the response
    // Pattern: <function_name>({arguments}) or ```function\n{...}\n```
    
    // Try JSON format first
    final jsonPattern = RegExp(r'```(?:json)?\s*\n?({[\s\S]*?})\n?```');
    final jsonMatches = jsonPattern.allMatches(response);
    
    for (var match in jsonMatches) {
      try {
        final jsonStr = match.group(1);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr);
          if (json is Map && json.containsKey('function')) {
            calls.add(FunctionCall.fromJson(Map<String, dynamic>.from(json)));
          }
        }
      } catch (e) {
        // Not valid JSON, continue
      }
    }
    
    // Try explicit function call pattern
    final functionPattern = RegExp(r'\$\$(\w+)\s*\(([^)]*)\)\$\$');
    final functionMatches = functionPattern.allMatches(response);
    
    for (var match in functionMatches) {
      final name = match.group(1);
      final argsStr = match.group(2);
      
      if (name != null && argsStr != null) {
        try {
          // Try to parse arguments as JSON
          final args = jsonDecode('{$argsStr}');
          calls.add(FunctionCall(name: name, arguments: args));
        } catch (e) {
          // If not JSON, try simple key=value parsing
          final args = _parseSimpleArgs(argsStr);
          calls.add(FunctionCall(name: name, arguments: args));
        }
      }
    }
    
    return calls;
  }

  /// Parse simple key=value arguments
  Map<String, dynamic> _parseSimpleArgs(String argsStr) {
    Map<String, dynamic> args = {};
    final pairs = argsStr.split(',');
    
    for (var pair in pairs) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        final key = parts[0].trim();
        final value = parts[1].trim();
        
        // Try to parse as number
        if (double.tryParse(value) != null) {
          args[key] = double.parse(value);
        } else if (value.startsWith('[') && value.endsWith(']')) {
          // Array
          args[key] = value.substring(1, value.length - 1)
              .split(',')
              .map((s) => double.tryParse(s.trim()) ?? s.trim())
              .toList();
        } else {
          args[key] = value;
        }
      }
    }
    
    return args;
  }

  /// Execute a function call
  FunctionResult executeFunction(FunctionCall call) {
    try {
      // Check if it's a math tool
      final tool = MathTools.getTool(call.name);
      if (tool != null) {
        final result = tool.execute(call.arguments);
        return FunctionResult(
          functionName: call.name,
          result: result,
        );
      }
      
      // Check if it's an expression evaluation
      if (call.name == 'evaluate_expression') {
        final expression = call.arguments['expression'] as String?;
        if (expression != null) {
          final result = MathExpressionEvaluator.tryEvaluate(expression);
          return FunctionResult(
            functionName: call.name,
            result: result,
          );
        }
      }
      
      return FunctionResult(
        functionName: call.name,
        error: 'Unknown function: ${call.name}',
      );
    } catch (e) {
      return FunctionResult(
        functionName: call.name,
        error: e.toString(),
      );
    }
  }

  /// Execute multiple function calls
  List<FunctionResult> executeFunctionCalls(List<FunctionCall> calls) {
    return calls.map((call) => executeFunction(call)).toList();
  }

  /// Process a calculation request with automatic function detection
  String processCalculation(String calculation) {
    try {
      // First try to evaluate as a direct expression
      final directResult = MathExpressionEvaluator.tryEvaluate(calculation);
      if (directResult != null) {
        return directResult.toString();
      }
      
      // If that fails, return error message
      return 'Error: Could not evaluate expression';
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Generate system prompt for function calling
  String generateSystemPrompt() {
    return '''You are a mathematical assistant with access to precise calculation tools.

When solving math problems, you should:
1. Break down complex problems into smaller steps
2. Use the available math functions for calculations instead of computing mentally
3. Show your work clearly with intermediate results

Available Functions:
${MathTools.getToolDefinitions().map((tool) => '- ${tool['name']}: ${tool['description']}').join('\n')}

To call a function, use this format:
\$\$function_name({"param1": value1, "param2": value2})\$\$

For example:
\$\$add({"numbers": [5, 3, 2]})\$\$
\$\$power({"base": 2, "exponent": 3})\$\$
\$\$solve_quadratic({"a": 1, "b": -5, "c": 6})\$\$

Always use these functions for calculations to ensure accuracy.'''; 
  }

  /// Process LLM response with embedded function calls
  Future<String> processResponse(String llmResponse) async {
    final calls = parseFunctionCalls(llmResponse);
    
    if (calls.isEmpty) {
      // No function calls, return as-is
      return llmResponse;
    }
    
    // Execute all function calls
    final results = executeFunctionCalls(calls);
    
    // Replace function calls with results in the response
    String processedResponse = llmResponse;
    
    for (int i = 0; i < calls.length; i++) {
      final call = calls[i];
      final result = results[i];
      
      // Replace the function call with its result
      final pattern = RegExp(
        r'\$\$' + RegExp.escape(call.name) + r'\s*\([^)]*\)\$\$',
        caseSensitive: false,
      );
      
      String replacement;
      if (result.error != null) {
        replacement = '[Error: ${result.error}]';
      } else {
        replacement = result.result?.toString() ?? '[No result]';
      }
      
      processedResponse = processedResponse.replaceFirst(pattern, replacement);
    }
    
    return processedResponse;
  }

  /// Create a structured solution with function calls
  Map<String, dynamic> createSolutionWithCalculations(
    String problem,
    List<Map<String, dynamic>> steps,
  ) {
    List<Map<String, dynamic>> processedSteps = [];
    
    for (var step in steps) {
      final stepText = step['description'] ?? '';
      final calculation = step['calculation'] as String?;
      
      Map<String, dynamic> processedStep = {
        'description': stepText,
      };
      
      if (calculation != null) {
        final result = processCalculation(calculation);
        processedStep['calculation'] = calculation;
        processedStep['result'] = result;
      }
      
      processedSteps.add(processedStep);
    }
    
    return {
      'problem': problem,
      'steps': processedSteps,
    };
  }
}
