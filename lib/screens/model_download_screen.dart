import 'package:flutter/material.dart';
import '../services/services.dart';
import '../theme/theme.dart';

/// Server connection status screen — replaces the old model-download screen.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  final AIService _aiService = AIService();
  bool _isChecking = false;
  bool? _isConnected;
  String _status = 'Tap "Check Connection" to test server.';

  Future<void> _checkConnection() async {
    setState(() {
      _isChecking = true;
      _status = 'Connecting to ${ServerConfig.baseUrl} ...';
    });
    final ok = await _aiService.checkServerHealth();
    setState(() {
      _isChecking = false;
      _isConnected = ok;
      _status = ok
          ? 'Server is online and ready!'
          : 'Cannot reach server at ${ServerConfig.baseUrl}.\n\nMake sure the Python server is running:\n  uvicorn app.main:app --host 0.0.0.0 --port 8000';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Server Setup'),
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
            Icon(
              _isConnected == null
                  ? Icons.cloud_outlined
                  : _isConnected!
                      ? Icons.cloud_done
                      : Icons.cloud_off,
              size: 80,
              color: _isConnected == null
                  ? AppColors.accentTeal
                  : _isConnected!
                      ? AppColors.success
                      : AppColors.error,
            ),
            const SizedBox(height: 24),
            const Text(
              'MathWizard Python Server',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'OCR and math solving are handled by a local Python server running on your PC. '
              'Your phone and PC must be on the same WiFi network.',
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isConnected == true
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: _isConnected == true
                            ? AppColors.success
                            : AppColors.accentBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Server URL',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ServerConfig.baseUrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isConnected == false
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (_isChecking) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isChecking ? null : _checkConnection,
                icon: const Icon(Icons.wifi_find),
                label: const Text('Check Connection'),
              ),
            ),
            const SizedBox(height: 12),
            if (_isConnected == true)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                ),
              ),
            const SizedBox(height: 8),
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
