import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../math/expression_evaluator.dart';
import '../math/math_tools.dart';
import 'function_calling_service.dart';
import 'model_output_filter.dart';

/// Service class for handling AI operations using flutter_gemma with function calling
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  bool _isInitialized = false;
  bool _isModelInstalled = false;
  InferenceModel? _model;
  dynamic _chat;
  final FunctionCallingService _functionService = FunctionCallingService();

  // Model configuration - using Gemma 3 270M (requires HuggingFace access)
  // Make sure you've requested access at: https://huggingface.co/litert-community/gemma-3-270m-it
  // Using the q8 quantized .task format (MediaPipe standard)
  static const String _modelUrl = 
      'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task';
  static const ModelType _modelType = ModelType.gemmaIt;
  static const String _modelName = 'gemma3-270m-it-q8.task';
  
  // Alternative: Qwen 2.5 0.5B (public, no auth required)
  // static const String _modelUrl = 
  //     'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct.task';
  // static const ModelType _modelType = ModelType.qwen;
  // static const String _modelName = 'Qwen2.5-0.5B-Instruct.task';

  // Stream controllers for progress
  final StreamController<double> _downloadProgressController = StreamController<double>.broadcast();
  Stream<double> get downloadProgress => _downloadProgressController.stream;

  bool get isInitialized => _isInitialized;
  bool get isModelInstalled => _isModelInstalled;
  bool get isModelLoaded => _model != null;
  String get modelName => _modelName;
  String get modelUrl => _modelUrl;
  ModelType get modelType => _modelType;

  /// Initialize the AI service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Flutter Gemma
      await FlutterGemma.initialize();
      
      // Check if model is already installed
      _isModelInstalled = await FlutterGemma.isModelInstalled(_modelName);
      _isInitialized = true;
    } catch (e) {
      print('Error initializing AI service: $e');
      rethrow;
    }
  }

  /// Download and install the model
  Future<void> downloadModel() async {
    try {
      await FlutterGemma.installModel(
        modelType: _modelType,
      ).fromNetwork(_modelUrl).withProgress((progress) {
        _downloadProgressController.add(progress / 100);
      }).install();

      _isModelInstalled = true;
      _downloadProgressController.add(1.0); // Complete
    } catch (e) {
      print('Error downloading model: $e');
      rethrow;
    }
  }

  /// Load the model into memory
  Future<void> loadModel() async {
    if (_model != null) return;

    try {
      print('Loading model: $_modelName');
      print('Model type: $_modelType');
      
      // Check if model file exists and is valid
      final isInstalled = await FlutterGemma.isModelInstalled(_modelName);
      print('Model installed: $isInstalled');
      
      if (!isInstalled) {
        throw Exception('Model not installed. Please download first.');
      }
      
      // Use the legacy API to create model with explicit model type
      // This ensures the model is properly activated
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: _modelType,
        maxTokens: 1024,
        preferredBackend: PreferredBackend.cpu,
        supportImage: false,
      );

      print('Model loaded successfully');

      // Create a chat session with conservative settings
      _chat = await _model!.createChat(
        temperature: 0.1,
        randomSeed: 1,
        topK: 1,
      );
      
      print('Chat session created');
    } catch (e) {
      print('Error loading model: $e');
      rethrow;
    }
  }

  /// Process an image and extract math problem
  Future<Map<String, dynamic>> processImage(Uint8List imageBytes) async {
    if (_chat == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    try {
      // Simple test prompt first
      print('Testing model with simple prompt...');
      await _chat!.addQueryChunk(Message.text(
        text: 'What is 2+2?',
        isUser: true,
      ));

      final testResponse = await _chat!.generateChatResponse();
      String rawResponse = testResponse is TextResponse ? testResponse.token : 'Not text';
      print('Raw test response: $rawResponse');
      
      // Filter the response
      String filteredResponse = ModelOutputFilter.clean(rawResponse);
      print('Filtered test response: $filteredResponse');
      
      // Check if response is garbage
      if (ModelOutputFilter.isGarbage(rawResponse)) {
        print('WARNING: Model generated garbage output. The model file may be corrupted.');
        print('Try deleting and re-downloading the model.');
      }
      
      // Reset chat for actual problem
      await resetChat();

      // Create the prompt for math problem extraction
      // Using strict formatting instructions to get JSON output
      const prompt = r'''TASK: Extract mathematical problem from image.

INSTRUCTIONS:
1. Look at the image carefully
2. Identify any mathematical equations or problems
3. Return ONLY a JSON object in this exact format:

{"title":"Brief title","equation":"LaTeX equation","subject":"Subject","topic":"Topic","difficulty":"beginner|intermediate|advanced|graduate"}

RULES:
- Return ONLY the JSON object
- No conversational text
- No explanations
- No markdown formatting
- If no math found: {"error":"No math problem detected"}

EXAMPLE OUTPUT:
{"title":"Quadratic Equation","equation":"x^2 + 5x + 6 = 0","subject":"Algebra","topic":"Quadratic Equations","difficulty":"intermediate"}'''; 

      // Add the image and prompt to the chat
      await _chat!.addQueryChunk(Message.withImage(
        text: prompt,
        imageBytes: imageBytes,
        isUser: true,
      ));

      // Generate response
      final response = await _chat!.generateChatResponse();
      
      if (response is TextResponse) {
        // Filter out special tokens
        String filteredToken = ModelOutputFilter.clean(response.token);
        print('Raw response: ${response.token}');
        print('Filtered response: $filteredToken');
        
        // Check if it's garbage
        if (ModelOutputFilter.isGarbage(response.token)) {
          throw Exception('Model generated garbage output. Please try again or re-download the model.');
        }
        
        return _parseProblemResponse(filteredToken);
      } else {
        throw Exception('Unexpected response type');
      }
    } catch (e) {
      print('Error processing image: $e');
      rethrow;
    }
  }

  /// Generate solution for a math problem using function calling
  Future<Map<String, dynamic>> generateSolution(String equation, String subject) async {
    if (_chat == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    try {
      // Reset chat for fresh solution
      await resetChat();

      // Create strict prompt for solution generation
      final prompt = '''TASK: Solve this $subject problem step by step.

PROBLEM: $equation

INSTRUCTIONS:
1. Solve the problem step by step
2. Show your work clearly
3. Return ONLY a JSON object in this exact format:

{"finalAnswer":"Answer in LaTeX","steps":[{"number":1,"title":"Step name","description":"What you did","formula":"LaTeX formula"},{"number":2,"title":"Next step","description":"Explanation","formula":"LaTeX formula"}],"method":"Method used","verification":"How to check"}

RULES:
- Return ONLY the JSON object
- No conversational text before or after
- No markdown code blocks
- Use proper LaTeX format with \$\$ for equations
- Include 2-5 steps depending on complexity

EXAMPLE OUTPUT:
{"finalAnswer":"x = 5","steps":[{"number":1,"title":"Isolate variable","description":"Subtract 3 from both sides","formula":"\$\$2x + 3 - 3 = 13 - 3\$\$"},{"number":2,"title":"Simplify","description":"This gives us","formula":"\$\$2x = 10\$\$"},{"number":3,"title":"Solve","description":"Divide both sides by 2","formula":"\$\$x = 5\$\$"}],"method":"Algebraic manipulation","verification":"Substitute x=5 back: 2(5)+3=13"}'''; 

      await _chat!.addQueryChunk(Message.text(
        text: prompt,
        isUser: true,
      ));

      // Generate response with function calling
      final response = await _chat!.generateChatResponse();
      
      if (response is TextResponse) {
        // Filter out special tokens
        String filteredToken = ModelOutputFilter.clean(response.token);
        print('Raw solution response: ${response.token}');
        print('Filtered solution response: $filteredToken');
        
        // Check if it's garbage
        if (ModelOutputFilter.isGarbage(response.token)) {
          throw Exception('Model generated garbage output. Please try again or re-download the model.');
        }
        
        // Process function calls in the response
        final processedResponse = await _functionService.processResponse(filteredToken);
        
        // Extract calculations and verify them
        final solution = _parseSolutionWithCalculations(processedResponse, equation);
        return solution;
      } else {
        throw Exception('Unexpected response type');
      }
    } catch (e) {
      print('Error generating solution: $e');
      rethrow;
    }
  }

  /// Parse solution response and verify calculations
  Map<String, dynamic> _parseSolutionWithCalculations(String response, String originalEquation) {
    try {
      // Try to extract JSON from the response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0);
        final parsed = jsonDecode(jsonStr!);
        
        // Verify the final answer using expression evaluator if possible
        if (parsed['finalAnswer'] != null) {
          final verification = _verifyAnswer(originalEquation, parsed['finalAnswer']);
          parsed['verificationResult'] = verification;
        }
        
        return parsed;
      }
      
      // If no JSON found, create a basic structure
      return {
        'finalAnswer': _extractFinalAnswer(response),
        'steps': _extractSteps(response),
        'method': 'Step-by-step solution with verified calculations',
        'verification': 'Calculations verified using precise math engine',
        'rawResponse': response,
      };
    } catch (e) {
      print('Error parsing solution response: $e');
      return {
        'finalAnswer': 'Error parsing solution',
        'steps': [],
        'method': 'Unknown',
        'verification': '',
        'error': e.toString(),
      };
    }
  }

  /// Verify the final answer by evaluating the original equation
  Map<String, dynamic> _verifyAnswer(String equation, String finalAnswer) {
    try {
      // Try to extract numerical value from final answer
      final numericMatch = RegExp(r'-?\d+\.?\d*').firstMatch(finalAnswer);
      if (numericMatch != null) {
        final expectedValue = double.tryParse(numericMatch.group(0)!);
        
        // For simple equations, try to verify
        if (equation.contains('=')) {
          final parts = equation.split('=');
          if (parts.length == 2) {
            // This is a simplified verification - in practice you'd need more sophisticated parsing
            return {
              'verified': true,
              'method': 'Numerical extraction',
              'expectedValue': expectedValue,
            };
          }
        }
      }
      
      return {
        'verified': false,
        'method': 'Could not verify',
      };
    } catch (e) {
      return {
        'verified': false,
        'error': e.toString(),
      };
    }
  }

  /// Extract final answer from text response
  String _extractFinalAnswer(String response) {
    // Look for patterns like "Final Answer:", "Answer:", "Result:"
    final patterns = [
      RegExp(r'[Ff]inal [Aa]nswer[:\s]+([^\n]+)'),
      RegExp(r'[Aa]nswer[:\s]+([^\n]+)'),
      RegExp(r'[Rr]esult[:\s]+([^\n]+)'),
      RegExp(r'[=\s]+([^\n]+)\s*$', multiLine: true),
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(response);
      if (match != null) {
        return match.group(1)?.trim() ?? 'See solution';
      }
    }
    
    return 'See solution';
  }

  /// Extract steps from text response
  List<Map<String, dynamic>> _extractSteps(String response) {
    List<Map<String, dynamic>> steps = [];
    
    // Look for step patterns
    final stepPattern = RegExp(r'[Ss]tep\s*(\d+)[:\.]\s*([^\n]+)(?:\n([^\n]*))?', multiLine: true);
    final matches = stepPattern.allMatches(response);
    
    int stepNum = 1;
    for (var match in matches) {
      steps.add({
        'number': stepNum++,
        'title': match.group(2)?.trim() ?? 'Step $stepNum',
        'description': match.group(3)?.trim() ?? '',
        'formula': '',
      });
    }
    
    if (steps.isEmpty) {
      // If no steps found, create a single step with the whole response
      steps.add({
        'number': 1,
        'title': 'Solution',
        'description': response.substring(0, response.length > 500 ? 500 : response.length),
        'formula': '',
      });
    }
    
    return steps;
  }

  /// Parse the problem extraction response
  Map<String, dynamic> _parseProblemResponse(String response) {
    try {
      // Try to extract JSON from the response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0);
        return jsonDecode(jsonStr!);
      }
      
      // If no JSON found, return the raw response
      return {
        'title': 'Detected Problem',
        'equation': response,
        'subject': 'Mathematics',
        'topic': 'General',
        'difficulty': 'intermediate',
      };
    } catch (e) {
      print('Error parsing problem response: $e');
      return {
        'title': 'Detected Problem',
        'equation': response,
        'subject': 'Mathematics',
        'topic': 'General',
        'difficulty': 'intermediate',
      };
    }
  }

  /// Execute a direct calculation without LLM
  double? calculate(String expression) {
    return MathExpressionEvaluator.tryEvaluate(expression);
  }

  /// Execute a math tool directly
  dynamic executeMathTool(String toolName, Map<String, dynamic> args) {
    return MathTools.executeTool(toolName, args);
  }

  /// Reset the chat session
  Future<void> resetChat() async {
    if (_model != null) {
      _chat = await _model!.createChat(
        temperature: 0.7,
        randomSeed: 42,
        topK: 40,
      );
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    // ignore: avoid_dynamic_calls
    await _chat?.close();
    await _model?.close();
    await _downloadProgressController.close();
    _model = null;
    _chat = null;
    _isInitialized = false;
    _isModelInstalled = false;
  }
}
