import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ai_service.dart';
import '../services/model_manager_service.dart';
import '../theme/theme.dart';
import 'model_download_screen.dart';

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  final ModelManagerService _modelManager = ModelManagerService();
  final AIService _aiService = AIService();
  
  bool _isLoading = false;
  String _status = 'Checking model status...';
  bool _isInstalled = false;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
    
    // Listen to model status updates
    _modelManager.modelStatusStream.listen((status) {
      setState(() {
        _status = status.message;
        _isInstalled = status.isInstalled;
        if (status.progress != null) {
          _downloadProgress = status.progress!;
        }
      });
    });
  }

  Future<void> _checkModelStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await _modelManager.getModelStatus(_aiService.modelName);
      setState(() {
        _isInstalled = status.isInstalled;
        _status = status.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model?'),
        content: const Text(
          'This will delete the AI model from your device. You will need to re-download it to use the app.\n\nAre you sure?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      // Close the AI service first
      await _aiService.dispose();
      
      // Try to delete the model file manually
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final modelDir = Directory('${appDir.path}/models');
        
        if (await modelDir.exists()) {
          // Delete all files in the models directory
          final files = await modelDir.list().toList();
          for (var file in files) {
            if (file is File) {
              await file.delete();
            }
          }
        }
        
        setState(() {
          _isInstalled = false;
          _status = 'Model deleted. Please re-download.';
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model deleted successfully')),
        );
      } catch (e) {
        setState(() {
          _status = 'Error deleting model: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _redownloadModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-download Model?'),
        content: Text(
          'This will delete the current model and download a fresh copy (~304MB).\n\nUse this if the model is corrupted or not working properly.\n\nContinue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-download'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
        _status = 'Preparing to re-download...';
      });

      // Close the AI service first
      await _aiService.dispose();

      // Delete old model
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final modelDir = Directory('${appDir.path}/models');
        
        if (await modelDir.exists()) {
          final files = await modelDir.list().toList();
          for (var file in files) {
            if (file is File) {
              await file.delete();
            }
          }
        }
      } catch (e) {
        print('Error deleting old model: $e');
      }

      // Navigate to download screen
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ModelDownloadScreen()),
        );

        if (result == true) {
          await _checkModelStatus();
        }
      }

      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _openDownloadScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ModelDownloadScreen()),
    );

    if (result == true) {
      await _checkModelStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Model Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _isInstalled ? Icons.check_circle : Icons.error,
                          size: 64,
                          color: _isInstalled ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isInstalled ? 'Model Installed' : 'Model Not Installed',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.8),
                          ),
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

                  const SizedBox(height: 32),

                  // Actions
                  if (!_isInstalled) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openDownloadScreen,
                        icon: const Icon(Icons.download),
                        label: const Text('Download Model'),
                      ),
                    ),
                  ] else ...[
                    // Re-download button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading ? null : _redownloadModel,
                        icon: _isDownloading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                        label: Text(_isDownloading ? 'Re-downloading...' : 'Re-download Model'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Delete button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _deleteModel,
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text(
                          'Delete Model',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Troubleshooting section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.help_outline, color: AppColors.accentBlue),
                            const SizedBox(width: 8),
                            const Text(
                              'Troubleshooting',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'If the model is generating garbage output or not responding:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Try re-downloading the model\n'
                          '2. Delete and re-download if problems persist\n'
                          '3. Ensure you have stable internet during download\n'
                          '4. Check that you have enough storage space',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
