import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isCameraReady => _controller?.value.isInitialized ?? false;

  /// Initialize camera service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request camera permission
      final status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        throw Exception('Camera permission denied');
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      _isInitialized = true;
    } catch (e) {
      print('Error initializing camera service: $e');
      rethrow;
    }
  }

  /// Initialize camera controller
  Future<void> initializeController() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_controller != null) {
      await _controller!.dispose();
    }

    // Use the back camera
    final backCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
  }

  /// Take a picture
  Future<Uint8List?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      return bytes;
    } catch (e) {
      print('Error taking picture: $e');
      return null;
    }
  }

  /// Pick image from gallery
  Future<Uint8List?> pickFromGallery() async {
    // This will be implemented using image_picker
    // For now, return null
    return null;
  }

  /// Dispose camera controller
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}
