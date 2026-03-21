import 'package:flutter/material.dart';
import '../services/services.dart';
import '../theme/theme.dart';

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  final AIService _aiService = AIService();
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isLoading = false;
  String _status = 'Checking model status...';

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    final isInstalled = _aiService.isModelInstalled;
    setState(() {
      if (isInstalled) {
        _status = 'Model installed. Ready to load.';
      } else {
        _status = 'Model not installed. Download required.';
      }
    });
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _status = 'Downloading model...';
    });

    try {
      _aiService.downloadProgress.listen((progress) {
        setState(() {
          _downloadProgress = progress;
        });
      });

      await _aiService.downloadModel();
      
      setState(() {
        _isDownloading = false;
        _status = 'Model downloaded successfully!';
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _status = 'Error downloading model: $e';
      });
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading model into memory...';
    });

    try {
      await _aiService.loadModel();
      setState(() {
        _isLoading = false;
        _status = 'Model loaded and ready!';
      });
      
      // Navigate back after successful load
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error loading model: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Model Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.memory,
              size: 80,
              color: AppColors.accentTeal,
            ),
            const SizedBox(height: 24),
            const Text(
              'Gemma 3 270M Model',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'A powerful Google AI model (~300MB) that runs locally on your device for math problem solving.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _aiService.isModelInstalled ? Icons.check_circle : Icons.download,
                        color: _aiService.isModelInstalled ? AppColors.success : AppColors.accentBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _aiService.isModelInstalled ? 'Model Installed' : 'Model Not Installed',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              _status,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentTeal),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (!_aiService.isModelInstalled) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadModel,
                  icon: _isDownloading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                  label: Text(_isDownloading ? 'Downloading...' : 'Download Model (~304MB)'),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadModel,
                  icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                  label: Text(_isLoading ? 'Loading...' : 'Load Model'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
