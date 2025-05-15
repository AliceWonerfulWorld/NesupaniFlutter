import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceLandmarkPainter extends CustomPainter {
  final Face face;
  final Size previewSize;
  final bool isFrontCamera;
  final double displayW;
  final double displayH;

  FaceLandmarkPainter(
    this.face,
    this.previewSize,
    this.isFrontCamera,
    this.displayW,
    this.displayH,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 顔の境界ボックスを描画
    final rect = _scaleRect(
      face.boundingBox,
      previewSize,
      size,
    );
    canvas.drawRect(rect, paint);

    // 目のランドマークを描画
    if (face.leftEyeOpenProbability != null) {
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      if (leftEye != null) {
        final leftEyePoint = _scalePoint(
          leftEye.position,
          previewSize,
          size,
        );
        canvas.drawCircle(leftEyePoint, 4, paint);
      }
    }

    if (face.rightEyeOpenProbability != null) {
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      if (rightEye != null) {
        final rightEyePoint = _scalePoint(
          rightEye.position,
          previewSize,
          size,
        );
        canvas.drawCircle(rightEyePoint, 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  Rect _scaleRect(Rect rect, Size previewSize, Size displaySize) {
    final double scaleX = displaySize.width / previewSize.width;
    final double scaleY = displaySize.height / previewSize.height;

    return Rect.fromLTWH(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.width * scaleX,
      rect.height * scaleY,
    );
  }

  Offset _scalePoint(Point<int> point, Size previewSize, Size displaySize) {
    final double scaleX = displaySize.width / previewSize.width;
    final double scaleY = displaySize.height / previewSize.height;

    double x = point.x * scaleX;
    if (isFrontCamera) {
      x = displaySize.width - x; // フロントカメラの場合、X座標を反転
    }

    return Offset(
      x,
      point.y * scaleY,
    );
  }
}