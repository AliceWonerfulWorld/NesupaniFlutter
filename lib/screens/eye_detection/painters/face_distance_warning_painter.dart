import 'package:flutter/material.dart';
import 'dart:js_util' as js_util;
import 'mediapipe_face_painter.dart';

/// 顔の距離に関する警告を表示するためのカスタムペインター
class FaceDistanceWarningPainter extends CustomPainter {
  final dynamic mediaPipeResult;
  final Size containerSize;

  FaceDistanceWarningPainter(this.mediaPipeResult, this.containerSize);

  @override
  void paint(Canvas canvas, Size size) {
    try {
      // MediaPipeの結果からfaceLandmarksを取得
      final faceLandmarks = js_util.getProperty(mediaPipeResult, 'faceLandmarks');
      if (faceLandmarks == null || js_util.getProperty(faceLandmarks, 'length') == 0) {
        return;
      }

      // 最初の顔のランドマークを取得
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      final landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;

      // 顔の距離を判定
      FaceDistance faceDistance = _checkFaceDistance(landmarks);

      // 適切な距離の場合は何も表示しない
      if (faceDistance == FaceDistance.good) {
        return;
      }

      // 警告メッセージを表示
      final warningText = faceDistance == FaceDistance.tooClose
          ? '顔が近すぎます'
          : '顔が遠すぎます';

      // 警告メッセージのスタイル
      final textStyle = TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black54,
            offset: Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      );

      // 警告メッセージの背景用のペイント
      final bgPaint = Paint()
        ..color = Colors.orange.withOpacity(0.9)
        ..style = PaintingStyle.fill;

      // テキストを描画するためのペインター
      final textPainter = TextPainter(
        text: TextSpan(
          text: '⚠️ $warningText',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // 背景の矩形を描画
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.15),
          width: textPainter.width + 40,
          height: textPainter.height + 20,
        ),
        Radius.circular(20),
      );
      canvas.drawRRect(bgRect, bgPaint);

      // テキストを描画
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          size.height * 0.15 - textPainter.height / 2,
        ),
      );
    } catch (e) {
      print('FaceDistanceWarningPainter描画エラー: $e');
    }
  }

  // 顔の距離を判定する関数
  FaceDistance _checkFaceDistance(List<dynamic> landmarks) {
    // 顔の大きさを計算するために使用するランドマーク
    const int foreheadIndex = 10;  // 額
    const int chinIndex = 152;     // あご
    
    if (landmarks.length <= foreheadIndex || landmarks.length <= chinIndex) {
      return FaceDistance.good;
    }
    
    final forehead = landmarks[foreheadIndex] as Map;
    final chin = landmarks[chinIndex] as Map;
    
    // 顔の縦の長さを計算
    final foreheadY = forehead['y'] is num ? (forehead['y'] as num).toDouble() : 0.0;
    final chinY = chin['y'] is num ? (chin['y'] as num).toDouble() : 0.0;
    final faceHeight = (chinY - foreheadY).abs();
    
    // 画面に対する顔の大きさの比率で判定
    const double tooCloseThreshold = 0.5;    // 画面の50%以上を占める場合は近すぎる
    const double tooFarThreshold = 0.25;     // 画面の25%未満の場合は遠すぎる
    
    if (faceHeight > tooCloseThreshold) {
      return FaceDistance.tooClose;
    } else if (faceHeight < tooFarThreshold) {
      return FaceDistance.tooFar;
    }
    return FaceDistance.good;
  }

  @override
  bool shouldRepaint(FaceDistanceWarningPainter oldDelegate) {
    return mediaPipeResult != oldDelegate.mediaPipeResult;
  }
} 