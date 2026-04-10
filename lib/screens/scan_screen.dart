import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/ai_provider.dart';
import '../services/services.dart';
import '../theme/theme.dart';
import '../widgets/scan_overlay.dart';
import '../widgets/detected_pattern_card.dart';
import 'solution_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _showDetection = false;
  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  String _detectionStatus = 'Align problem within frame';
  Map<String, dynamic>? _detectedProblem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraService.controller;
    if (cameraController == null || !cameraController.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraService.initializeController();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      setState(() => _detectionStatus = 'Camera unavailable');
    }
  }

  Future<void> _takePicture() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _detectionStatus = 'Capturing image...';
    });
    try {
      final imageBytes = await _cameraService.takePicture();
      if (imageBytes != null) {
        await _processImage(imageBytes);
      } else {
        setState(() {
          _isProcessing = false;
          _detectionStatus = 'Failed to capture image';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Error: $e';
      });
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _detectionStatus = 'Loading image...';
    });
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        await _processImage(bytes);
      } else {
        setState(() {
          _isProcessing = false;
          _detectionStatus = 'Align problem within frame';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Error loading image: $e';
      });
    }
  }

  Future<void> _processImage(Uint8List imageBytes) async {
    setState(() => _detectionStatus = 'Reading and solving...');
    try {
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.processImageAndSolve(imageBytes);
      setState(() {
        _isProcessing = false;
        _detectedProblem = result;
        _showDetection = true;
        _detectionStatus = result['success'] == true
            ? 'Problem solved — tap View Solution'
            : 'Could not solve: ${result['error'] ?? 'unknown error'}';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Server error: $e';
        _showDetection = false;
      });
    }
  }

  void _openManualInput() {
    final controller = TextEditingController();
    String selectedMode = 'auto';

    const modes = [
      ('auto', 'Auto-detect'),
      ('solve', 'Solve'),
      ('expand', 'Expand'),
      ('factor', 'Factor'),
      ('simplify', 'Simplify'),
      ('differentiate', 'Differentiate'),
      ('integrate', 'Integrate'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Enter Problem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: r'e.g.  (x+2)(x+3)  or  \int x^2 dx',
                  helperText: 'LaTeX or plain math notation',
                ),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 16),
              const Text('What do you want to do?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: modes.map((m) {
                  final isSelected = selectedMode == m.$1;
                  return ChoiceChip(
                    label: Text(m.$2, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => setDialogState(() => selectedMode = m.$1),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                final mode = selectedMode;
                Navigator.pop(ctx);
                if (text.isNotEmpty) _solveText(text, mode: mode);
              },
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _solveText(String text, {String mode = 'auto'}) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _showDetection = false;
      _detectionStatus = 'Solving...';
    });
    try {
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.generateSolution(text, 'Mathematics', mode: mode);
      setState(() {
        _isProcessing = false;
        _detectedProblem = result;
        _showDetection = true;
        _detectionStatus = result['success'] == true
            ? 'Solved — tap View Solution'
            : 'Could not solve: ${result['error'] ?? 'unknown error'}';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Server error: $e';
        _showDetection = false;
      });
    }
  }

  void _navigateToSolution() {
    if (_detectedProblem == null) return;
    final combined = _detectedProblem!;
    final equation = combined['equation'] as String? ?? '';
    final problem = {
      'title': combined['title'] ?? 'Math Problem',
      'equation': equation,
      'subject': 'Mathematics',
      'topic': _inferTopic(equation),
      'difficulty': 'intermediate',
    };
    final solution = {
      'finalAnswer': combined['finalAnswer'] ?? '',
      'steps': combined['steps'] ?? [],
      'method': combined['method'] ?? '',
      'success': combined['success'] ?? false,
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SolutionScreen(problem: problem, solution: solution),
      ),
    );
  }

  String _inferTopic(String latex) {
    final l = latex.toLowerCase();
    if (l.contains(r'\int') || l.contains('dx')) return 'Calculus';
    if (l.contains(r'\lim')) return 'Limits';
    if (l.contains(r'\sin') || l.contains(r'\cos') || l.contains(r'\tan')) return 'Trigonometry';
    if (l.contains(';') || l.split('=').length > 2) return 'Systems of Equations';
    if (l.contains(r'\frac') || l.contains('=')) return 'Algebra';
    return 'General';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera preview
          if (_isCameraInitialized && _cameraService.controller != null)
            CameraPreview(_cameraService.controller!)
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, size: 64, color: Colors.white24),
                    SizedBox(height: 16),
                    Text('Initializing camera...', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),

          // Scan overlay
          const ScanOverlay(),

          // Center prompt
          if (!_isProcessing && !_showDetection)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ALIGN PROBLEM',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Status pill
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isProcessing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentTeal),
                          ),
                        )
                      else
                        const Icon(Icons.auto_fix_high, color: AppColors.accentTeal, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _detectionStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

                // Camera controls
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: Icons.photo_library,
                        label: 'GALLERY',
                        onTap: _pickFromGallery,
                      ),
                      // Capture button
                      GestureDetector(
                        onTap: _isProcessing ? null : _takePicture,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isProcessing ? Colors.grey : AppColors.primary,
                              width: 4,
                            ),
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                          child: Center(
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isProcessing ? Colors.grey : AppColors.primary,
                              ),
                              child: Icon(
                                _isProcessing ? Icons.hourglass_top : Icons.camera_alt,
                                color: AppColors.primaryDark,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildControlButton(
                        icon: Icons.edit,
                        label: 'TYPE',
                        onTap: _openManualInput,
                      ),
                    ],
                  ),
                ),

                // Detected pattern card
                if (_showDetection && _detectedProblem != null)
                  DetectedPatternCard(
                    patternName: _detectedProblem!['title'] ?? 'DETECTED PROBLEM',
                    equation: _detectedProblem!['equation'] as String? ?? '',
                    onView: _navigateToSolution,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
