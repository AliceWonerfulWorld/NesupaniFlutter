import 'package:flutter/material.dart';
import 'dart:js_util' as js_util;

// 顔の距離状態を表す列挙型
enum FaceDistance { tooClose, tooFar, good }

/// MediaPipeの顔ランドマークを描画するためのカスタムペインター
class MediaPipeFacePainter extends CustomPainter {
  final dynamic mediaPipeResult;
  final Size containerSize;

  MediaPipeFacePainter(this.mediaPipeResult, this.containerSize);

  @override
  void paint(Canvas canvas, Size size) {
    try {
      // MediaPipeの結果からfaceLandmarksを取得
      final faceLandmarks = js_util.getProperty(mediaPipeResult, 'faceLandmarks');
      if (faceLandmarks == null || js_util.getProperty(faceLandmarks, 'length') == 0) {
        return; // 顔が見つからなければ何も描画しない
      }

      // 最初の顔のランドマークを取得
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      final landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;

      // 描画用の設定
      final paint = Paint()
        ..color = Colors.green
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      final dotPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 4
        ..style = PaintingStyle.fill;

      // 顔のランドマークを描画
      final Path path = Path();
      bool isFirstPoint = true;

      // 目のランドマークのインデックス（MediaPipe Face Landmarker）
      const int leftEyeUpperIndex = 159;
      const int leftEyeLowerIndex = 145;
      const int rightEyeUpperIndex = 386;
      const int rightEyeLowerIndex = 374;

      // 重要なランドマークを描画する
      void drawSpecialLandmark(int index, Color color) {
        if (landmarks.length <= index) return;
        
        final point = landmarks[index] as Map;
        final x = point['x'] is num ? (point['x'] as num).toDouble() * size.width : 0.0;
        final y = point['y'] is num ? (point['y'] as num).toDouble() * size.height : 0.0;
        
        // 特定のランドマークを強調
        canvas.drawCircle(
          Offset(x, y),
          8,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill
        );
      }

      // 目のランドマークを強調表示
      drawSpecialLandmark(leftEyeUpperIndex, Colors.blue);
      drawSpecialLandmark(leftEyeLowerIndex, Colors.cyan);
      drawSpecialLandmark(rightEyeUpperIndex, Colors.blue);
      drawSpecialLandmark(rightEyeLowerIndex, Colors.cyan);

      // すべてのランドマークを小さい点で描画
      for (int i = 0; i < landmarks.length; i++) {
        final point = landmarks[i] as Map;
        final x = point['x'] is num ? (point['x'] as num).toDouble() * size.width : 0.0;
        final y = point['y'] is num ? (point['y'] as num).toDouble() * size.height : 0.0;
        
        // すべてのポイントを小さい点で描画
        canvas.drawCircle(Offset(x, y), 2, dotPaint);
      }

      // 左目と右目の状態を判定
      bool isLeftEyeOpen = _isEyeOpen(landmarks, true);
      bool isRightEyeOpen = _isEyeOpen(landmarks, false);

      // 顔の距離を判定
      FaceDistance faceDistance = _checkFaceDistance(landmarks);

      // 目の状態を表示するテキスト描画
      final textStyle = TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black,
            offset: Offset(1, 1),
            blurRadius: 3,
          ),
        ],
      );

      // 顔の距離に関する警告メッセージを表示
      if (faceDistance != FaceDistance.good) {
        final warningText = faceDistance == FaceDistance.tooClose
            ? '顔が近すぎます'
            : '顔が遠すぎます';
        final warningColor = Colors.orange;
        
        final warningTextPainter = TextPainter(
          text: TextSpan(
            text: '⚠️ $warningText',
            style: textStyle.copyWith(
              color: warningColor,
              fontSize: 24,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        warningTextPainter.layout();
        warningTextPainter.paint(
          canvas,
          Offset(
            (size.width - warningTextPainter.width) / 2,
            size.height * 0.2,
          ),
        );
      }

      final leftEyeTextPainter = TextPainter(
        text: TextSpan(
          text: isLeftEyeOpen ? "左目: 開" : "左目: 閉",
          style: textStyle.copyWith(
            color: isLeftEyeOpen ? Colors.green : Colors.red,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      leftEyeTextPainter.layout();
      leftEyeTextPainter.paint(canvas, Offset(20, size.height - 60));

      final rightEyeTextPainter = TextPainter(
        text: TextSpan(
          text: isRightEyeOpen ? "右目: 開" : "右目: 閉",
          style: textStyle.copyWith(
            color: isRightEyeOpen ? Colors.green : Colors.red,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      rightEyeTextPainter.layout();
      rightEyeTextPainter.paint(canvas, Offset(20, size.height - 30));

    } catch (e) {
      print('MediaPipeFacePainter描画エラー: $e');
    }
  }

  // 目が開いているかどうかを判定する関数
  bool _isEyeOpen(List<dynamic> landmarks, bool isLeft) {
    // 左目と右目のランドマークインデックス
    const int leftEyeUpperIndex = 159;
    const int leftEyeLowerIndex = 145;
    const int rightEyeUpperIndex = 386;
    const int rightEyeLowerIndex = 374;
    
    // 左目か右目かに応じて対応するランドマークを取得
    final upperIndex = isLeft ? leftEyeUpperIndex : rightEyeUpperIndex;
    final lowerIndex = isLeft ? leftEyeLowerIndex : rightEyeLowerIndex;
    
    if (landmarks.length <= upperIndex || landmarks.length <= lowerIndex) {
      return true; // ランドマークがない場合はデフォルトで開いていると見なす
    }
    
    final eyeUpper = landmarks[upperIndex] as Map;
    final eyeLower = landmarks[lowerIndex] as Map;
    
    final eyeUpperY = eyeUpper['y'] is num ? (eyeUpper['y'] as num).toDouble() : 0.0;
    final eyeLowerY = eyeLower['y'] is num ? (eyeLower['y'] as num).toDouble() : 0.0;
    final eyeDistance = (eyeUpperY - eyeLowerY).abs();
    
    // しきい値
    const eyeClosedThreshold = 0.004;
    return eyeDistance > eyeClosedThreshold;
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
  bool shouldRepaint(MediaPipeFacePainter oldDelegate) {
    return mediaPipeResult != oldDelegate.mediaPipeResult;
  }
} 