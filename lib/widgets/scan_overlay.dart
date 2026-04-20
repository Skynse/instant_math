import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class ScanOverlay extends StatelessWidget {
  const ScanOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: ScanOverlayPainter());
  }
}

class ScanFrameGeometry {
  static Rect rectFor(Size size) {
    final width = size.width * 0.9;
    final height = width * 0.42;
    final centerY = size.height * 0.4;

    return Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: width,
      height: height,
    );
  }
}

class ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final cornerPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final scanArea = ScanFrameGeometry.rectFor(size);

    // Draw dashed border
    final dashPath = Path();
    const dashWidth = 10.0;
    const dashSpace = 5.0;

    // Top edge
    for (
      double x = scanArea.left;
      x < scanArea.right;
      x += dashWidth + dashSpace
    ) {
      dashPath.moveTo(x, scanArea.top);
      dashPath.lineTo(x + dashWidth, scanArea.top);
    }

    // Bottom edge
    for (
      double x = scanArea.left;
      x < scanArea.right;
      x += dashWidth + dashSpace
    ) {
      dashPath.moveTo(x, scanArea.bottom);
      dashPath.lineTo(x + dashWidth, scanArea.bottom);
    }

    // Left edge
    for (
      double y = scanArea.top;
      y < scanArea.bottom;
      y += dashWidth + dashSpace
    ) {
      dashPath.moveTo(scanArea.left, y);
      dashPath.lineTo(scanArea.left, y + dashWidth);
    }

    // Right edge
    for (
      double y = scanArea.top;
      y < scanArea.bottom;
      y += dashWidth + dashSpace
    ) {
      dashPath.moveTo(scanArea.right, y);
      dashPath.lineTo(scanArea.right, y + dashWidth);
    }

    canvas.drawPath(dashPath, paint);

    // Draw corners
    const cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(
      Offset(scanArea.left, scanArea.top + cornerLength),
      Offset(scanArea.left, scanArea.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanArea.left, scanArea.top),
      Offset(scanArea.left + cornerLength, scanArea.top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scanArea.right - cornerLength, scanArea.top),
      Offset(scanArea.right, scanArea.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanArea.right, scanArea.top),
      Offset(scanArea.right, scanArea.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scanArea.left, scanArea.bottom - cornerLength),
      Offset(scanArea.left, scanArea.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanArea.left, scanArea.bottom),
      Offset(scanArea.left + cornerLength, scanArea.bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scanArea.right - cornerLength, scanArea.bottom),
      Offset(scanArea.right, scanArea.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanArea.right, scanArea.bottom),
      Offset(scanArea.right, scanArea.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
