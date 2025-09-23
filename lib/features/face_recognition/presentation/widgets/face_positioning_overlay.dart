import 'package:flutter/material.dart';

/// Ultra-simple overlay that shows an oval guide for face positioning
class FacePositioningOverlay extends StatelessWidget {
  final bool isFaceDetected;
  final bool isGoodQuality;

  const FacePositioningOverlay({
    super.key,
    this.isFaceDetected = false,
    this.isGoodQuality = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: OvalOverlayPainter(
          isFaceDetected: isFaceDetected,
          isGoodQuality: isGoodQuality,
        ),
        child: Container(),
      ),
    );
  }
}

/// Custom painter for the oval overlay
class OvalOverlayPainter extends CustomPainter {
  final bool isFaceDetected;
  final bool isGoodQuality;

  OvalOverlayPainter({
    required this.isFaceDetected,
    required this.isGoodQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate oval dimensions
    final center = Offset(size.width / 2, size.height / 2);
    final ovalWidth = size.width * 0.75;
    final ovalHeight = size.height * 0.45;

    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    // Create paths
    final screenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final ovalPath = Path()
      ..addOval(ovalRect);

    // Create the overlay with oval cutout
    final overlayPath = Path.combine(
      PathOperation.difference,
      screenPath,
      ovalPath,
    );

    // Paint the dark overlay
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, overlayPaint);

    // Determine oval border color
    Color borderColor = Colors.white;
    if (isFaceDetected) {
      borderColor = isGoodQuality ? Colors.green : Colors.orange;
    }

    // Draw the oval border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawOval(ovalRect, borderPaint);

    // Draw corner indicators for better guidance
    _drawCornerIndicators(canvas, ovalRect, borderColor);

    // Draw instruction text
    _drawInstructions(canvas, size, isFaceDetected, isGoodQuality);
  }

  void _drawCornerIndicators(Canvas canvas, Rect ovalRect, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const indicatorLength = 30.0;

    // Top-left indicator
    canvas.drawLine(
      Offset(ovalRect.left - 10, ovalRect.top),
      Offset(ovalRect.left + indicatorLength, ovalRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(ovalRect.left, ovalRect.top - 10),
      Offset(ovalRect.left, ovalRect.top + indicatorLength),
      paint,
    );

    // Top-right indicator
    canvas.drawLine(
      Offset(ovalRect.right - indicatorLength, ovalRect.top),
      Offset(ovalRect.right + 10, ovalRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(ovalRect.right, ovalRect.top - 10),
      Offset(ovalRect.right, ovalRect.top + indicatorLength),
      paint,
    );

    // Bottom-left indicator
    canvas.drawLine(
      Offset(ovalRect.left - 10, ovalRect.bottom),
      Offset(ovalRect.left + indicatorLength, ovalRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(ovalRect.left, ovalRect.bottom - indicatorLength),
      Offset(ovalRect.left, ovalRect.bottom + 10),
      paint,
    );

    // Bottom-right indicator
    canvas.drawLine(
      Offset(ovalRect.right - indicatorLength, ovalRect.bottom),
      Offset(ovalRect.right + 10, ovalRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(ovalRect.right, ovalRect.bottom - indicatorLength),
      Offset(ovalRect.right, ovalRect.bottom + 10),
      paint,
    );
  }

  void _drawInstructions(Canvas canvas, Size size, bool isFaceDetected, bool isGoodQuality) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    String instruction;
    if (!isFaceDetected) {
      instruction = 'Position your face in the oval';
    } else if (!isGoodQuality) {
      instruction = 'Move closer to the camera';
    } else {
      instruction = 'Hold steady - Face detected';
    }

    textPainter.text = TextSpan(
      text: instruction,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        shadows: [
          Shadow(
            blurRadius: 8,
            color: Colors.black54,
          ),
        ],
      ),
    );

    textPainter.layout();

    // Position text at top center
    final xCenter = (size.width - textPainter.width) / 2;
    final yPosition = size.height * 0.15;

    textPainter.paint(canvas, Offset(xCenter, yPosition));
  }

  @override
  bool shouldRepaint(OvalOverlayPainter oldDelegate) {
    return oldDelegate.isFaceDetected != isFaceDetected ||
           oldDelegate.isGoodQuality != isGoodQuality;
  }
}