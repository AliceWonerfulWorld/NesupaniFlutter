import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class Utils {
  static InputImageRotation rotationIntToImageRotation(int rotation) {
    switch (rotation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  static Future<bool> isEyesOpen(Face face) async {
    final leftEyeOpenProbability = face.leftEyeOpenProbability ?? 0;
    final rightEyeOpenProbability = face.rightEyeOpenProbability ?? 0;
    return leftEyeOpenProbability > 0.2 && rightEyeOpenProbability > 0.2;
  }
} 