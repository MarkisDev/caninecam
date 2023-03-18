import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class ObjectPainter extends CustomPainter {
  ObjectPainter(this.imgSize, this.objects);

  final Size imgSize;
  final List<DetectedObject> objects;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculating the scale factor to resize the rectangle (newSize/originalSize)
    final double scaleX = size.width / imgSize.width;
    final double scaleY = size.height / imgSize.height;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Color.fromARGB(255, 255, 0, 0);

    for (DetectedObject detectedObject in objects) {
      canvas.drawRect(
        Rect.fromLTRB(
          detectedObject.boundingBox.left * scaleX,
          detectedObject.boundingBox.top * scaleY,
          detectedObject.boundingBox.right * scaleX,
          detectedObject.boundingBox.bottom * scaleY,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ObjectPainter oldDelegate) {
    // Repaint if object is moving or new objects detected
    return oldDelegate.imgSize != imgSize || oldDelegate.objects != objects;
  }
}
