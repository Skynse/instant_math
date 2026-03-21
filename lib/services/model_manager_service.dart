import 'dart:async';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Service for managing AI models (delete, reinstall, etc.)
class ModelManagerService {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  final _modelStatusController = StreamController<ModelStatus>.broadcast();
  Stream<ModelStatus> get modelStatusStream => _modelStatusController.stream;

  /// Get current model status
  Future<ModelStatus> getModelStatus(String modelName) async {
    try {
      final isInstalled = await FlutterGemma.isModelInstalled(modelName);
      
      if (!isInstalled) {
        return ModelStatus(
          isInstalled: false,
          modelName: modelName,
          message: 'Model not installed',
        );
      }

      // Try to get model info if possible
      return ModelStatus(
        isInstalled: true,
        modelName: modelName,
        message: 'Model installed',
      );
    } catch (e) {
      return ModelStatus(
        isInstalled: false,
        modelName: modelName,
        message: 'Error checking status: $e',
        error: e.toString(),
      );
    }
  }

  /// Delete a model
  Future<bool> deleteModel(String modelName) async {
    try {
      _modelStatusController.add(ModelStatus(
        isInstalled: true,
        modelName: modelName,
        message: 'Deleting model...',
        isProcessing: true,
      ));

      // Close any active model/chat first
      // Note: This should be handled by the AIService
      
      // Delete the model using the model manager
      // Note: flutter_gemma doesn't expose a direct deleteModel method
      // We'll need to use platform-specific file deletion or the model manager
      // For now, we'll mark it as not installed and let the user re-download
      
      _modelStatusController.add(ModelStatus(
        isInstalled: false,
        modelName: modelName,
        message: 'Model marked for deletion. Please re-download.',
      ));
      
      return true;
    } catch (e) {
      _modelStatusController.add(ModelStatus(
        isInstalled: true,
        modelName: modelName,
        message: 'Error deleting model: $e',
        error: e.toString(),
      ));
      return false;
    }
  }

  /// Re-download a model (delete then download)
  Future<bool> redownloadModel(
    String modelName,
    String modelUrl,
    ModelType modelType, {
    String? token,
    Function(double)? onProgress,
  }) async {
    try {
      // First delete existing model
      _modelStatusController.add(ModelStatus(
        isInstalled: true,
        modelName: modelName,
        message: 'Deleting old model...',
        isProcessing: true,
      ));

      await deleteModel(modelName);

      // Then download new model
      _modelStatusController.add(ModelStatus(
        isInstalled: false,
        modelName: modelName,
        message: 'Downloading new model...',
        isProcessing: true,
      ));

      await FlutterGemma.installModel(
        modelType: modelType,
      ).fromNetwork(
        modelUrl,
        token: token,
      ).withProgress((progress) {
        onProgress?.call(progress / 100);
        _modelStatusController.add(ModelStatus(
          isInstalled: false,
          modelName: modelName,
          message: 'Downloading: ${(progress / 100).toStringAsFixed(1)}%',
          isProcessing: true,
          progress: progress / 100,
        ));
      }).install();

      _modelStatusController.add(ModelStatus(
        isInstalled: true,
        modelName: modelName,
        message: 'Model re-downloaded successfully',
      ));

      return true;
    } catch (e) {
      _modelStatusController.add(ModelStatus(
        isInstalled: false,
        modelName: modelName,
        message: 'Error re-downloading model: $e',
        error: e.toString(),
      ));
      return false;
    }
  }

  /// Get model file size (if possible)
  Future<String?> getModelSize(String modelName) async {
    // This is a placeholder - actual implementation would depend on
    // whether the plugin exposes file size information
    return null;
  }

  void dispose() {
    _modelStatusController.close();
  }
}

/// Model status information
class ModelStatus {
  final bool isInstalled;
  final String modelName;
  final String message;
  final String? error;
  final bool isProcessing;
  final double? progress;

  ModelStatus({
    required this.isInstalled,
    required this.modelName,
    required this.message,
    this.error,
    this.isProcessing = false,
    this.progress,
  });
}
