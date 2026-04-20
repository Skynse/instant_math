import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
      debugPrint('Error initializing camera service: $e');
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
  Future<Uint8List?> takePicture({Size? viewportSize, Rect? scanRect}) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      if (viewportSize != null && scanRect != null) {
        return _cropToScanRect(bytes, viewportSize, scanRect);
      }
      return bytes;
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }

  Uint8List _cropToScanRect(Uint8List bytes, Size viewportSize, Rect scanRect) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return bytes;
    }

    final image = img.bakeOrientation(decoded);
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final scale = math.max(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );

    final fittedWidth = imageSize.width * scale;
    final fittedHeight = imageSize.height * scale;
    final offsetX = (viewportSize.width - fittedWidth) / 2;
    final offsetY = (viewportSize.height - fittedHeight) / 2;

    final sourceLeft = ((scanRect.left - offsetX) / scale).floor();
    final sourceTop = ((scanRect.top - offsetY) / scale).floor();
    final sourceRight = ((scanRect.right - offsetX) / scale).ceil();
    final sourceBottom = ((scanRect.bottom - offsetY) / scale).ceil();

    final x = sourceLeft.clamp(0, image.width - 1);
    final y = sourceTop.clamp(0, image.height - 1);
    final right = sourceRight.clamp(x + 1, image.width);
    final bottom = sourceBottom.clamp(y + 1, image.height);

    final cropped = img.copyCrop(
      image,
      x: x,
      y: y,
      width: right - x,
      height: bottom - y,
    );

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
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
