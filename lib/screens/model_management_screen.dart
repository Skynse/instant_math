import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/server_service.dart';
import '../theme/theme.dart';
import 'model_download_screen.dart';

/// Server management screen — replaces the old model management screen.
class ModelManagementScreen extends ConsumerStatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  ConsumerState<ModelManagementScreen> createState() =>
      _ModelManagementScreenState();
}

class _ModelManagementScreenState
    extends ConsumerState<ModelManagementScreen> {
  bool _isChecking = false;
  bool? _isConnected;

  Future<void> _checkConnection() async {
    setState(() => _isChecking = true);
    final ok = await ServerService().checkHealth();
    setState(() {
      _isChecking = false;
      _isConnected = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Server Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
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
                    _isConnected == true
                        ? Icons.cloud_done
                        : _isConnected == false
                            ? Icons.cloud_off
                            : Icons.cloud_outlined,
                    size: 64,
                    color: _isConnected == true
                        ? AppColors.success
                        : _isConnected == false
                            ? AppColors.error
                            : AppColors.accentTeal,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Python Math Server',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnected == null
                        ? 'Tap "Check Connection" to test'
                        : _isConnected!
                            ? 'Connected — server is online'
                            : 'Cannot reach server',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isConnected == false
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ServerConfig.baseUrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  if (_isChecking) ...[
                    const SizedBox(height: 16),
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ModelDownloadScreen()),
                ),
                icon: const Icon(Icons.settings),
                label: const Text('Connection Settings'),
              ),
            ),

            const SizedBox(height: 32),

            // How to run the server
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
                      const Icon(Icons.terminal,
                          color: AppColors.accentBlue),
                      const SizedBox(width: 8),
                      const Text(
                        'Starting the server',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Run on your PC (same WiFi network):',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'cd projects/mathwizard\\mathwizard_server\nuvicorn app.main:app --host 0.0.0.0 --port 8000',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Then update the IP in server_service.dart:\n  ServerConfig.baseUrl = "http://<your-PC-IP>:8000"',
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
