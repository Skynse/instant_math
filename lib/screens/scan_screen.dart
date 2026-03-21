import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/services.dart';
import '../theme/theme.dart';
import '../widgets/scan_overlay.dart';
import '../widgets/detected_pattern_card.dart';
import 'model_download_screen.dart';
import 'solution_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final AIService _aiService = AIService();
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
    _checkModelAndPromptDownload();
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

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _checkModelAndPromptDownload() async {
    if (!_aiService.isModelInstalled) {
      // Show model download screen
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ModelDownloadScreen()),
        );
        
        if (result == true) {
          // Model was loaded successfully
          setState(() {
            _detectionStatus = 'AI model ready. Align problem to scan.';
          });
        }
      }
    } else if (!_aiService.isModelLoaded) {
      // Model is installed but not loaded
      try {
        await _aiService.loadModel();
        setState(() {
          _detectionStatus = 'AI model ready. Align problem to scan.';
        });
      } catch (e) {
        setState(() {
          _detectionStatus = 'Error loading AI model. Please restart app.';
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraService.initializeController();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _detectionStatus = 'Camera error: $e';
      });
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
    setState(() {
      _detectionStatus = 'Analyzing image with AI...';
    });

    try {
      // Check if model is ready
      if (!_aiService.isModelLoaded) {
        setState(() {
          _isProcessing = false;
          _detectionStatus = 'AI model not ready. Please load model first.';
        });
        return;
      }

      // Process image with AI
      final result = await _aiService.processImage(imageBytes);
      
      if (result.containsKey('error')) {
        setState(() {
          _isProcessing = false;
          _detectionStatus = result['error'];
          _showDetection = false;
        });
      } else {
        setState(() {
          _isProcessing = false;
          _detectedProblem = result;
          _showDetection = true;
          _detectionStatus = 'Problem detected! Tap View to see solution.';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Error processing image: $e';
        _showDetection = false;
      });
    }
  }

  void _navigateToSolution() async {
    if (_detectedProblem == null) return;

    setState(() {
      _detectionStatus = 'Generating solution...';
      _isProcessing = true;
    });

    try {
      final equation = _detectedProblem!['equation'] ?? '';
      final subject = _detectedProblem!['subject'] ?? 'Mathematics';
      
      // Generate solution using AI
      final solution = await _aiService.generateSolution(equation, subject);
      
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Solution ready!';
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SolutionScreen(
              problem: _detectedProblem!,
              solution: solution,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _detectionStatus = 'Error generating solution: $e';
      });
    }
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
                    Icon(
                      Icons.camera_alt,
                      size: 64,
                      color: Colors.white24,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Initializing camera...',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          
          // Scan overlay
          const ScanOverlay(),
          
          // Align problem text
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
                // Detection status
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
                        const Icon(
                          Icons.auto_fix_high,
                          color: AppColors.accentTeal,
                          size: 20,
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _detectionStatus,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
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
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Gallery button
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
                      
                      // Calc button
                      _buildControlButton(
                        icon: Icons.calculate,
                        label: 'CALC',
                        onTap: () {
                          // TODO: Open calculator/manual input
                        },
                      ),
                    ],
                  ),
                ),
                
                // Detected pattern card
                if (_showDetection && _detectedProblem != null)
                  DetectedPatternCard(
                    patternName: 'DETECTED PROBLEM',
                    equation: _detectedProblem!['title'] ?? 'Unknown problem',
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
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
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
