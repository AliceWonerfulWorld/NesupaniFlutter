import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit_fd; // Alias to avoid conflict
import 'package:nesupani/screens/eye_detection/painters/train_interior_painter.dart';
import 'package:nesupani/screens/eye_detection/painters/face_landmark_painter.dart';
import 'package:nesupani/screens/eye_detection/painters/mediapipe_face_painter.dart'; // MediaPipeFacePainterの追加
import 'package:nesupani/screens/eye_detection/painters/face_distance_warning_painter.dart'; // 追加
import 'package:nesupani/screens/eye_detection/widgets/animated_scenery_widget.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:js/js.dart' as packageJs; // Renamed alias to avoid conflict
import 'dart:js' as dartJs; // Added for allowInterop
// URLを開くためのライブラリ
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'dart:js_util' as js_util;
import 'dart:ui_web' if (dart.library.io) 'dart:ui' as ui_web;
import 'dart:math' as math; // math関数を使用するためのインポート
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';  // Google Fontsをインポート
import 'package:nesupani/services/game_service.dart'; // GameServiceのインポート

// 背景のタイプを定義する列挙型
enum BackgroundType {
  dawn,    // 朝焼け
  morning, // 朝
  daytime, // 昼
  sunset,  // 夕焼け
  night,   // 夜
  rainy,   // 雨
  snowy,   // 雪
  autumn,  // 紅葉
}

// 背景タイプの名前と対応するアイコンを取得する拡張機能
extension BackgroundTypeExtension on BackgroundType {
  String get name {
    switch (this) {
      case BackgroundType.dawn:
        return '朝焼け';
      case BackgroundType.morning:
        return '朝';
      case BackgroundType.daytime:
        return '昼';
      case BackgroundType.sunset:
        return '夕焼け';
      case BackgroundType.night:
        return '夜';
      case BackgroundType.rainy:
        return '雨';
      case BackgroundType.snowy:
        return '雪';
      case BackgroundType.autumn:
        return '紅葉';
    }
  }
  
  IconData get icon {
    switch (this) {
      case BackgroundType.dawn:
        return Icons.wb_twilight;
      case BackgroundType.morning:
        return Icons.wb_sunny;
      case BackgroundType.daytime:
        return Icons.light_mode;
      case BackgroundType.sunset:
        return Icons.nightlight;
      case BackgroundType.night:
        return Icons.dark_mode;
      case BackgroundType.rainy:
        return Icons.umbrella;
      case BackgroundType.snowy:
        return Icons.ac_unit;
      case BackgroundType.autumn:
        return Icons.eco;
    }
  }
}

// MediaPipe Task objects will be handled by js_util typically,
// but if direct JS interop with @JS is needed for some structures, keep js.dart.

// 星空を描画するCustomPainter
class StarPainter extends CustomPainter {
  final int starCount;
  final Color starColor;
  final math.Random random = math.Random();

  StarPainter({this.starCount = 150, required this.starColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (int i = 0; i < starCount; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 1.2 + 0.3; // 星の半径 (0.3 to 1.5)
      paint.color = starColor.withOpacity(random.nextDouble() * 0.6 + 0.4); // 透明度 (0.4 to 1.0)
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// タイトル画面の背景を描画するCustomPainter
class TitleScreenBackgroundPainter extends CustomPainter {
  final BackgroundType backgroundType;
  
  TitleScreenBackgroundPainter({this.backgroundType = BackgroundType.morning});
  
  @override
  void paint(Canvas canvas, Size size) {
    // 1. 背景タイプに基づいて空と遠景を描画
    _drawSkyAndScenery(canvas, size);

    // 2. 電車内の前景要素（座席など）を描画
    _drawTrainInteriorElements(canvas, size);

    // 3. 窓枠を描画 (窓枠の内側は透過し、下の空が見える前提)
    _drawWindowFrame(canvas, size);

    // 4. ガラス効果を最後に描画
    _drawGlassEffects(canvas, size);
    
    // 5. 背景タイプに応じた特殊効果を描画
    _drawSpecialEffects(canvas, size);
  }

  void _drawSkyAndScenery(Canvas canvas, Size size) {
    // 背景タイプに応じて異なる空のグラデーションを設定
    List<Color> skyColors;
    List<double> colorStops;
    
    switch (backgroundType) {
      case BackgroundType.dawn: // 朝焼け
        skyColors = [
          const Color(0xFF1A1A2E), // 夜の名残
          const Color(0xFF6A5D7B), // 夜明け前の薄紫
          const Color(0xFFB88AAB), // ピンクがかった紫
          const Color(0xFFFFB08F), // 朝焼けのオレンジ
          const Color(0xFFADD8E6), // 明るい水色
        ];
        colorStops = [0.0, 0.3, 0.55, 0.75, 1.0];
        break;
        
      case BackgroundType.morning: // 朝
        skyColors = [
          const Color(0xFF87CEEB), // 明るい空色
          const Color(0xFF97DEFF), // より明るい青
          const Color(0xFFADE8F4), // 薄い青
          const Color(0xFFCAF0F8), // さらに薄い青
        ];
        colorStops = [0.0, 0.3, 0.6, 1.0];
        break;
        
      case BackgroundType.daytime: // 昼
        skyColors = [
          const Color(0xFF1E88E5), // 濃い青
          const Color(0xFF42A5F5), // 標準的な青
          const Color(0xFF90CAF9), // 明るい青
        ];
        colorStops = [0.0, 0.5, 1.0];
        break;
        
      case BackgroundType.sunset: // 夕焼け
        skyColors = [
          const Color(0xFF4A4969), // 暗い紫青
          const Color(0xFF7B6B8D), // 紫がかった色
          const Color(0xFFE98C6E), // 橙色
          const Color(0xFFF2D0A4), // 淡い黄色
        ];
        colorStops = [0.0, 0.3, 0.65, 1.0];
        break;
        
      case BackgroundType.night: // 夜
        skyColors = [
          const Color(0xFF0D1321), // 暗い青黒
          const Color(0xFF1D2D50), // 濃い紺
          const Color(0xFF4A6FA5), // 薄い紺
        ];
        colorStops = [0.0, 0.6, 1.0];
        break;
        
      case BackgroundType.rainy: // 雨
        skyColors = [
          const Color(0xFF2C3333), // 暗い灰色
          const Color(0xFF4F646F), // 青みがかった灰色
          const Color(0xFF7D8E9B), // 薄い灰色
        ];
        colorStops = [0.0, 0.5, 1.0];
        break;
        
      case BackgroundType.snowy: // 雪
        skyColors = [
          const Color(0xFFB8C5D6), // 薄い青灰色
          const Color(0xFFD2DDE9), // 青みがかった白
          const Color(0xFFEDF2F7), // ほぼ白
        ];
        colorStops = [0.0, 0.5, 1.0];
        break;
        
      case BackgroundType.autumn: // 紅葉
        skyColors = [
          const Color(0xFF7D6B7D), // 紫がかった灰色
          const Color(0xFF9C7C86), // 薄い赤紫
          const Color(0xFFE3BAB3), // 薄い桃色
          const Color(0xFFFFE8D6), // クリーム色
        ];
        colorStops = [0.0, 0.4, 0.7, 1.0];
        break;
    }

    // 空のグラデーション描画
    final skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        skyColors,
        colorStops,
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), skyPaint);

    // 雲の描画 (背景タイプに応じて調整)
    _drawClouds(canvas, size);

    // 遠景のシルエット (背景タイプに応じて調整)
    Color silhouetteColor;
    double opacity;
    
    switch (backgroundType) {
      case BackgroundType.night:
        silhouetteColor = const Color(0xFF1A1A2A);
        opacity = 0.8;
        break;
      case BackgroundType.rainy:
      case BackgroundType.snowy:
        silhouetteColor = const Color(0xFF464646);
        opacity = 0.4;
        break;
      default:
        silhouetteColor = const Color(0xFF424242);
        opacity = 0.5;
    }

    final silhouettePaint = Paint()..color = silhouetteColor.withOpacity(opacity);
    final path = Path();
    path.moveTo(0, size.height * 0.75);
    path.cubicTo(size.width * 0.1, size.height * 0.7, size.width * 0.15, size.height * 0.78, size.width * 0.25, size.height * 0.72);
    path.lineTo(size.width * 0.3, size.height * 0.75);
    path.cubicTo(size.width * 0.4, size.height * 0.68, size.width * 0.45, size.height * 0.75, size.width * 0.55, size.height * 0.7);
    path.lineTo(size.width * 0.6, size.height * 0.73);
    path.cubicTo(size.width * 0.7, size.height * 0.65, size.width * 0.8, size.height * 0.75, size.width * 0.9, size.height * 0.72);
    path.lineTo(size.width, size.height * 0.76);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, silhouettePaint);

    final distantSilhouettePaint = Paint()..color = silhouetteColor.withOpacity(opacity * 0.6);
    final distantPath = Path();
    distantPath.moveTo(0, size.height * 0.8);
    distantPath.quadraticBezierTo(size.width * 0.2, size.height * 0.75, size.width * 0.4, size.height * 0.78);
    distantPath.quadraticBezierTo(size.width * 0.6, size.height * 0.82, size.width * 0.8, size.height * 0.77);
    distantPath.lineTo(size.width, size.height * 0.81);
    distantPath.lineTo(size.width, size.height);
    distantPath.lineTo(0, size.height);
    distantPath.close();
    canvas.drawPath(distantPath, distantSilhouettePaint);
  }

  void _drawClouds(Canvas canvas, Size size) {
    final random = math.Random(123); // シード固定で毎回同じ雲に
    
    // 背景タイプに応じて雲の色と量を調整
    Color baseCloudColor;
    double opacityMultiplier;
    int cloudCountMultiplier;
    
    switch (backgroundType) {
      case BackgroundType.dawn:
        baseCloudColor = Colors.pink[50]!;
        opacityMultiplier = 0.6;
        cloudCountMultiplier = 1;
        break;
      case BackgroundType.morning:
        baseCloudColor = Colors.white;
        opacityMultiplier = 0.9;
        cloudCountMultiplier = 1;
        break;
      case BackgroundType.daytime:
        baseCloudColor = Colors.white;
        opacityMultiplier = 1.0;
        cloudCountMultiplier = 1;
        break;
      case BackgroundType.sunset:
        baseCloudColor = Colors.orange[100]!;
        opacityMultiplier = 0.8;
        cloudCountMultiplier = 1;
        break;
      case BackgroundType.night:
        baseCloudColor = Colors.grey[700]!;
        opacityMultiplier = 0.4;
        cloudCountMultiplier = 1;
        break;
      case BackgroundType.rainy:
        baseCloudColor = Colors.grey[500]!;
        opacityMultiplier = 0.9;
        cloudCountMultiplier = 2; // 雨の日は雲が多い
        break;
      case BackgroundType.snowy:
        baseCloudColor = Colors.grey[300]!;
        opacityMultiplier = 0.8;
        cloudCountMultiplier = 2; // 雪の日は雲が多い
        break;
      case BackgroundType.autumn:
        baseCloudColor = Colors.white;
        opacityMultiplier = 0.7;
        cloudCountMultiplier = 1;
        break;
    }

    final cloudPaint = Paint();

    // 雲の色々なバリエーション
    List<CloudProps> cloudProperties = [
      CloudProps(color: baseCloudColor.withOpacity(0.5 * opacityMultiplier), blurRadius: 20.0, count: 3 * cloudCountMultiplier, yFactor: 0.3, sizeFactor: 0.25),
      CloudProps(color: Colors.grey[300]!.withOpacity(0.4 * opacityMultiplier), blurRadius: 30.0, count: 2 * cloudCountMultiplier, yFactor: 0.4, sizeFactor: 0.35),
      CloudProps(color: baseCloudColor.withOpacity(0.6 * opacityMultiplier), blurRadius: 15.0, count: 4 * cloudCountMultiplier, yFactor: 0.25, sizeFactor: 0.2),
    ];

    for (var props in cloudProperties) {
      cloudPaint
        ..color = props.color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, props.blurRadius);
      for (int i = 0; i < props.count; i++) {
        final cloudWidth = size.width * (random.nextDouble() * 0.2 + props.sizeFactor); // 幅をランダムに
        final cloudHeight = cloudWidth * (random.nextDouble() * 0.3 + 0.4); // 高さを幅に応じて
        final x = random.nextDouble() * (size.width - cloudWidth);
        final y = random.nextDouble() * (size.height * props.yFactor);
        canvas.drawOval(Rect.fromLTWH(x, y, cloudWidth, cloudHeight), cloudPaint);
      }
    }
  }

  // 特殊効果を描画する (雨、雪、星など)
  void _drawSpecialEffects(Canvas canvas, Size size) {
    switch (backgroundType) {
      case BackgroundType.night:
        _drawStars(canvas, size);
        break;
      case BackgroundType.rainy:
        _drawRain(canvas, size);
        break;
      case BackgroundType.snowy:
        _drawSnow(canvas, size);
        break;
      case BackgroundType.autumn:
        _drawFallingLeaves(canvas, size);
        break;
      default:
        // 特に効果なし
        break;
    }
  }
  
  // 星を描画
  void _drawStars(Canvas canvas, Size size) {
    final random = math.Random(456); // 固定シードで一貫した配置
    final starPaint = Paint()..color = Colors.white;
    
    // 大きさの異なる星を描画
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.7; // 空の上部に限定
      final radius = random.nextDouble() * 1.2 + 0.3; // 0.3〜1.5の大きさ
      final opacity = random.nextDouble() * 0.5 + 0.5; // 0.5〜1.0の透明度
      
      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, starPaint);
    }
    
    // いくつかの星をきらめかせる (大きな星)
    for (int i = 0; i < 10; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.6; // さらに上部に限定
      final radius = random.nextDouble() * 0.8 + 1.2; // 1.2〜2.0の大きさ (大きめ)
      
      // きらめき効果 (グラデーションで)
      final shimmerPaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(x, y),
          radius * 2.5,
          [
            Colors.white.withOpacity(0.8),
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.0),
          ],
          [0.0, 0.5, 1.0],
        );
      
      canvas.drawCircle(Offset(x, y), radius * 2.5, shimmerPaint);
      canvas.drawCircle(Offset(x, y), radius, starPaint..color = Colors.white.withOpacity(0.9));
    }
  }
  
  // 雨を描画
  void _drawRain(Canvas canvas, Size size) {
    final random = math.Random(789);
    final rainPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    
    for (int i = 0; i < 100; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.7; // 窓の上部に限定
      final length = random.nextDouble() * 10 + 5; // 5〜15の長さ
      
      canvas.drawLine(
        Offset(x, y),
        Offset(x - length * 0.3, y + length), // 少し斜めに
        rainPaint,
      );
    }
  }
  
  // 雪を描画
  void _drawSnow(Canvas canvas, Size size) {
    final random = math.Random(101112);
    final snowPaint = Paint()..color = Colors.white.withOpacity(0.7);
    
    for (int i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.7; // 窓の上部に限定
      final radius = random.nextDouble() * 2.0 + 1.0; // 1.0〜3.0の大きさ
      
      canvas.drawCircle(Offset(x, y), radius, snowPaint);
    }
  }
  
  // 落ち葉を描画
  void _drawFallingLeaves(Canvas canvas, Size size) {
    final random = math.Random(131415);
    
    // 異なる色の落ち葉
    final leafColors = [
      Color(0xFFFF6B35), // オレンジ
      Color(0xFFF7C59F), // 薄橙
      Color(0xFFDDA448), // 黄土色
      Color(0xFFB83B5E), // 赤紫
      Color(0xFF9F5F80), // 薄紫
    ];
    
    for (int i = 0; i < 25; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.7; // 窓の上部に限定
      final leafSize = random.nextDouble() * 6.0 + 4.0; // 4.0〜10.0の大きさ
      final colorIndex = random.nextInt(leafColors.length);
      final rotation = random.nextDouble() * 2 * math.pi; // 0〜2πのランダムな回転
      
      // 簡易的な葉っぱの形
      final leafPath = Path();
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      
      // 楕円形の葉
      leafPath.addOval(Rect.fromCenter(
        center: Offset.zero,
        width: leafSize * 1.5,
        height: leafSize,
      ));
      
      // 中央の線 (葉脈)
      final veinPaint = Paint()
        ..color = Colors.brown.withOpacity(0.5)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      
      canvas.drawPath(leafPath, Paint()..color = leafColors[colorIndex].withOpacity(0.6));
      canvas.drawLine(Offset(-leafSize * 0.75, 0), Offset(leafSize * 0.75, 0), veinPaint);
      
      canvas.restore();
    }
  }

  // 以下の既存メソッドはそのまま残す
  void _drawTrainInteriorElements(Canvas canvas, Size size) {
    // 座席の背もたれの上部が少し見える (より具体的に窓の下部に合わせて描画)
    final seatTopPaint = Paint()..color = const Color(0xFF8D6E63); // より濃い木目調（TrainInteriorPainterの座席木部）
    final seatShadowPaint = Paint()..color = Colors.black.withOpacity(0.15);
    double seatVisibleHeight = size.height * 0.1;
    double frameThickness = 25.0; // _drawWindowFrameと合わせる
    double seatTopY = size.height - frameThickness - seatVisibleHeight;

    // 座席の背もたれの描画範囲を窓枠の下に合わせる
    Rect seatRect = Rect.fromLTWH(
        frameThickness,
        seatTopY,
        size.width - frameThickness * 2,
        seatVisibleHeight
    );
    // 角丸は窓枠に合わせる必要はないが、少し丸みをつける
    RRect seatRRect = RRect.fromRectAndCorners(seatRect, bottomLeft: Radius.circular(5), bottomRight: Radius.circular(5));
    canvas.drawRRect(seatRRect, seatTopPaint);

    // 座席に簡単な影
    canvas.drawRect(Rect.fromLTWH(seatRect.left, seatRect.top, seatRect.width, 5), seatShadowPaint);
  }

  void _drawWindowFrame(Canvas canvas, Size size) {
    // TrainInteriorPainterの窓枠デザインを参考にする
    double frameThickness = 25.0;
    // double innerPadding = 5.0; // 未使用なのでコメントアウト
    double cornerRadiusValue = 20.0;
    Radius cornerRadius = Radius.circular(cornerRadiusValue);

    // 1. 金属風の外枠の「フチ」 (strokeで)
    final metalEdgePaint = Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [const Color(0xFFBDBDBD), const Color(0xFFE0E0E0), const Color(0xFFBDBDBD)])
        ..style = PaintingStyle.stroke
        ..strokeWidth = frameThickness;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(frameThickness/2, frameThickness/2, size.width-frameThickness, size.height-frameThickness), cornerRadius), metalEdgePaint);

    // 2. 木目調の内枠の「フチ」
    final woodEdgePaint = Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [const Color(0xFF8D6E63), const Color(0xFFA1887F), const Color(0xFF8D6E63)])
        ..style = PaintingStyle.stroke
        ..strokeWidth = frameThickness - 8; // 金属枠より少し細く
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(frameThickness/2 + 4, frameThickness/2 + 4, size.width-frameThickness-8, size.height-frameThickness-8), Radius.circular(cornerRadius.x - 4 > 0 ? cornerRadius.x -4 : 2)), woodEdgePaint);

    // ハイライトとシャドウで立体感を出す
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 外枠のハイライトとシャドウ
    Path highlightPath = Path()
      ..addRRect(RRect.fromLTRBAndCorners(
          frameThickness / 2,
          frameThickness / 2,
          size.width - frameThickness / 2 - 1,
          size.height * 0.6,
          topLeft: cornerRadius,
          topRight: cornerRadius,
          bottomLeft: Radius.zero,
          bottomRight: Radius.zero));
    canvas.drawPath(highlightPath, highlightPaint);
    
    Path shadowPath = Path()
      ..addRRect(RRect.fromLTRBAndCorners(
          frameThickness / 2 + 1,
          size.height * 0.4,
          size.width - frameThickness / 2,
          size.height - frameThickness / 2 - 1,
          topLeft: Radius.zero,
          topRight: Radius.zero,
          bottomLeft: cornerRadius,
          bottomRight: cornerRadius));
    canvas.drawPath(shadowPath, shadowPaint);
  }

  void _drawGlassEffects(Canvas canvas, Size size) {
    double frameThickness = 25.0;
    Rect glassRect = Rect.fromLTWH(
      frameThickness,
      frameThickness,
      size.width - frameThickness * 2,
      size.height - frameThickness * 2,
    );
    RRect glassRRect = RRect.fromRectAndRadius(glassRect, Radius.circular(20.0 - frameThickness / 2 > 0 ? 20.0 - frameThickness / 2 : 5));

    // ガラスの光沢 (斜めのグラデーション)
    final glassShinePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(glassRect.left + glassRect.width * 0.1, glassRect.top + glassRect.height * 0.1),
        Offset(glassRect.right - glassRect.width * 0.1, glassRect.bottom - glassRect.height * 0.1),
        [
          Colors.white.withOpacity(0.08),
          Colors.white.withOpacity(0.02),
          Colors.transparent,
          Colors.white.withOpacity(0.01),
          Colors.white.withOpacity(0.05),
        ],
        [0.0, 0.3, 0.5, 0.7, 1.0]
      );
    canvas.drawRRect(glassRRect, glassShinePaint);

    // 朝露や汚れ（ほんの少し）
    final random = math.Random(456);
    final dewPaint = Paint()..color = Colors.white.withOpacity(0.05);
    for(int i=0; i<15; i++){
        double x = glassRect.left + random.nextDouble() * glassRect.width;
        double y = glassRect.top + random.nextDouble() * glassRect.height;
        double radius = random.nextDouble() * 1.5 + 0.5;
        canvas.drawCircle(Offset(x,y), radius, dewPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is TitleScreenBackgroundPainter) {
      return oldDelegate.backgroundType != backgroundType;
    }
    return true;
  }
}

// Helper class for cloud properties
class CloudProps {
  final Color color;
  final double blurRadius;
  final int count;
  final double yFactor; // 0.0 (top) to 1.0 (bottom)
  final double sizeFactor; // relative to screen width

  CloudProps({
    required this.color,
    required this.blurRadius,
    required this.count,
    required this.yFactor,
    required this.sizeFactor,
  });
}

class EyeDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  // GameServiceインスタンスを追加
  final GameService gameService;
  
  const EyeDetectionScreen({
    super.key,
    required this.cameras,
    required this.gameService,
  });

  @override
  State<EyeDetectionScreen> createState() => _EyeDetectionScreenState();
}

class _EyeDetectionScreenState extends State<EyeDetectionScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  late mlkit_fd.FaceDetector _faceDetector; // For mobile
  
  // For MediaPipe Web
  dynamic _mediaPipeFaceDetector; // Stores the MediaPipe FaceDetector task instance
  bool _isMediaPipeInitialized = false;
  bool _isMediaPipeInitializing = false; // 初期化処理中フラグを追加

  bool _isGameStarted = false;
  int _score = 0;
  Timer? _stationTimer;
  Timer? _eyesClosedScoreTimer; // 目を閉じている間のスコア加算タイマー
  String _currentStation = '';
  bool _isDebugMode = false;
  String _debugStatus = '';
  bool _isProcessing = false;
  bool _isEyesOpen = true;
  late AnimationController _animationController;
  late Animation<double> _sceneryAnimation;
  
  // ランダムな背景タイプを保持する変数
  BackgroundType _currentBackgroundType = BackgroundType.morning;
  
  // スコア計算に関する変数
  bool _wasEyesClosedDuringStation = false; // 現在の駅で目を閉じていたか
  int _consecutiveStationsWithEyesClosed = 0; // 連続で目を閉じていた駅の数
  static const int STATION_BASE_SCORE = 10; // 基本点（駅ごと）
  static const double CONSECUTIVE_BONUS_MULTIPLIER = 0.5; // 連続ボーナス係数
  static const int EYES_CLOSED_SCORE_INTERVAL = 200; // 目を閉じている間のスコア加算間隔（ミリ秒）- 短くして反応を早く
  static const int EYES_CLOSED_SCORE_INCREMENT = 1; // 目を閉じている間の加算量
  int _eyesClosedDuration = 0; // 目を閉じている累積時間（ミリ秒）
  
  final List<String> _stations = [
    '基山駅',
    'けやき台',
    '原田',
    '天拝山',
    '二日市',
    '都府楼南',
    '水城',
    '大野城',
    '春日',
    '南福岡',
    '笹原',
    '竹下',
    '博多',
    '吉塚',
    '箱崎',
    '千早',
    '香椎',
    '九産大前',
    '福工大前',
    '新宮中央'
  ];
  int _currentStationIndex = 0;
  mlkit_fd.Face? _debugFace; // For mobile
  dynamic _mediaPipeDebugResult; // For web
  bool _wasEyesOpen = true;
  bool _isGameOver = false;
  int _consecutiveBlinkCount = 0;
  static const int STATION_CHANGE_SECONDS = 3;
  static const double EYE_CLOSED_THRESHOLD = 0.3; // This might need adjustment for MediaPipe
  static const int SCORE_PER_BLINK = 10;
  static const int MAX_CONSECUTIVE_BLINKS = 5;
  Timer? _webDetectTimer;
  AudioPlayer? _audioPlayer;
  bool _isPlayingSound = false;

  // ゲームオーバー・クリアSE用 AudioPlayer
  AudioPlayer? _gameOverSoundPlayer;
  AudioPlayer? _gameClearSoundPlayer;

  // いびきSE用 AudioPlayer
  AudioPlayer? _snorePlayer;
  bool _isSnorePlaying = false;

  // 画面サイズに基づいて小さい画面かどうかを判定
  bool get isSmallScreen => MediaQuery.of(context).size.width < 600;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // アプリ起動時にランダムな背景タイプを選択
    _selectRandomBackground();
    
    // アプリ起動時の確実な初期化（最初のゲームから動くように）
    _performOneTimeInitialization();
    
    if (kIsWeb) {
      _initializeMediaPipe();
      // Use ui_web.platformViewRegistry for web
      ui_web.platformViewRegistry.registerViewFactory(
        'webcam-video',
        (int viewId) {
          var video = html.document.getElementById('webcam-video') as html.VideoElement?;
          if (video == null) {
            video = html.VideoElement()
              ..id = 'webcam-video'
              ..autoplay = true
              ..style.display = 'none'; 
            html.document.body?.append(video);
          }
          return video;
        },
      );
    }
    _initializeCamera(); 
    _initializeAudio();

    // Mobile face detector initialization
    _faceDetector = mlkit_fd.FaceDetector(
      options: mlkit_fd.FaceDetectorOptions(
        performanceMode: mlkit_fd.FaceDetectorMode.accurate,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.1,
        enableLandmarks: true,
      ),
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _sceneryAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController)
      ..addListener(() {
        if (mounted) {
          setState(() {
            // This will trigger a repaint when animation value changes
          });
        }
      });
  }

  // アプリ起動時に1回だけ実行される初期化メソッド
  void _performOneTimeInitialization() {
    print('■■■ アプリ起動時の初期化を実行 ■■■');
    
    // ゲーム状態を確実にリセット
    _isGameStarted = false;
    _isGameOver = false;
    _score = 0;
    _currentStation = '';
    _currentStationIndex = 0;
    _consecutiveBlinkCount = 0;
    _wasEyesClosedDuringStation = false;
    _consecutiveStationsWithEyesClosed = 0;
    _wasEyesOpen = true;
    _isDebugMode = false;
    _debugStatus = '';
    _debugFace = null;
    _mediaPipeDebugResult = null;
    _isEyesOpen = true;
    
    // 既存のタイマーを全てキャンセル（念のため）
    _stationTimer?.cancel();
    _stationTimer = null;
    _eyesClosedScoreTimer?.cancel();
    _eyesClosedScoreTimer = null;
    _webDetectTimer?.cancel();
    _webDetectTimer = null;
    
    print('■■■ アプリ起動時の初期化完了 ■■■');
  }

  Future<void> _initializeMediaPipe() async {
    if (!kIsWeb) return;
    if (_isMediaPipeInitialized || _isMediaPipeInitializing) { // 既に初期化済みか初期化中なら何もしない
      print('MediaPipe already initialized or is initializing. Skipping.');
      return;
    }
    _isMediaPipeInitializing = true; // 初期化処理開始
    print('Starting MediaPipe initialization process...');

    try {
      print('Initializing MediaPipe Face Detector...');

      // MyMediaPipeGlobal が利用可能になるまで少し待つ (最大5秒程度)
      dynamic myMediaPipeGlobalJs;
      bool foundGlobal = false;
      for (int i = 0; i < 100; i++) { // 100ms * 100 = 10秒
        myMediaPipeGlobalJs = js_util.getProperty(html.window, 'MyMediaPipeGlobal');
        if (myMediaPipeGlobalJs != null && js_util.hasProperty(myMediaPipeGlobalJs, 'FilesetResolver')) {
          foundGlobal = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!foundGlobal) {
        print("エラー: MyMediaPipeGlobal が window オブジェクトに見つかりません (タイムアウト後)。");
        print("MediaPipe scriptの遅延読み込みを試みます...");
        
        // スクリプトを強制的にロードしてみる
        final scriptElement = html.document.createElement('script') as html.ScriptElement;
        scriptElement.src = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.9/vision_bundle.js';
        scriptElement.type = 'text/javascript';
        html.document.head?.append(scriptElement);
        
        // さらに待機
        await Future.delayed(const Duration(seconds: 3));
        
        // 再度確認
        myMediaPipeGlobalJs = js_util.getProperty(html.window, 'MyMediaPipeGlobal');
        if (myMediaPipeGlobalJs == null) {
          _debugStatus = 'MediaPipeグローバルオブジェクト未検出(T)';
          if (mounted) setState(() {});
          _isMediaPipeInitializing = false;
          return;
        }
      }

      final filesetResolverClass = js_util.getProperty(myMediaPipeGlobalJs, 'FilesetResolver');
      if (filesetResolverClass == null) {
        print("エラー: FilesetResolver が MyMediaPipeGlobal に見つかりません。");
        _debugStatus = 'MediaPipe FilesetResolver未検出';
        if (mounted) setState(() {});
        _isMediaPipeInitializing = false;
        return;
      }

      // FaceDetectorの代わりにFaceLandmarkerを使用
      final faceLandmarkerClass = js_util.getProperty(myMediaPipeGlobalJs, 'FaceLandmarker');
      if (faceLandmarkerClass == null) {
        print("エラー: FaceLandmarker が MyMediaPipeGlobal に見つかりません。");
        _debugStatus = 'MediaPipe FaceLandmarker API未検出';
        if (mounted) setState(() {});
        return;
      }

      print('MediaPipe Global objects (FilesetResolver, FaceLandmarker) found.');

      // Step 1: Create a FilesetResolver for Vision Tasks
      final filesetResolver = await js_util.promiseToFuture(
        js_util.callMethod(filesetResolverClass, 'forVisionTasks', [
          // WASMファイルのパス
          'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.9/wasm' // バージョンを0.10.9に固定
        ])
      );

      if (filesetResolver == null) {
        print('MediaPipe FilesetResolver の作成に失敗しました。');
        _debugStatus = 'MediaPipe FilesetResolver作成失敗';
        if (mounted) setState(() {});
        return;
      }
      print('MediaPipe FilesetResolver created successfully.');

      // Step 2: Create FaceLandmarker with options
      final faceDetectorOptions = js_util.newObject();
      final baseOptions = js_util.newObject();
      js_util.setProperty(baseOptions, 'modelAssetPath', 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task');
      js_util.setProperty(baseOptions, 'delegate', 'GPU'); // または 'CPU'
      js_util.setProperty(faceDetectorOptions, 'baseOptions', baseOptions);
      js_util.setProperty(faceDetectorOptions, 'outputFaceBlendshapes', true); // 表情認識のための出力を有効化
      js_util.setProperty(faceDetectorOptions, 'numFaces', 1); // 検出する顔の数（1人分で十分）
      js_util.setProperty(faceDetectorOptions, 'runningMode', 'VIDEO'); // VIDEOモード

      // FaceLandmarkerを作成
      _mediaPipeFaceDetector = await js_util.promiseToFuture(
        js_util.callMethod(faceLandmarkerClass, 'createFromOptions', [filesetResolver, faceDetectorOptions])
      );

      if (_mediaPipeFaceDetector != null) {
        print('MediaPipe Face Landmarker instance created successfully.');
        
        // JavaScript側の内部的な準備が整うのを少し待つ（経験的な値）
        await Future.delayed(const Duration(milliseconds: 300)); 
        print('Short delay after MediaPipe instance creation completed.');

        _isMediaPipeInitialized = true;
        if(mounted) setState(() => _debugStatus = 'MediaPipe 初期化完了'); // 即座に反映

        // FaceDetectorインスタンス作成後、少し待機してみる (例: 1秒)
        print('Waiting a bit after FaceLandmarker creation (1 second)...');
        await Future.delayed(const Duration(seconds: 1));
        print('Finished waiting after FaceLandmarker creation.');
      } else {
        print('MediaPipe Face Landmarker の初期化に失敗しました (detector is null)。');
        _debugStatus = 'MediaPipe 初期化失敗 (detector null)';
      }
    } catch (e, s) {
      print('MediaPipe 初期化エラー: $e\n$s');
      _debugStatus = 'MediaPipe 初期化エラー: $e';
    } finally {
      _isMediaPipeInitializing = false; // 初期化処理完了
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _stopCamera() async {
    if (kIsWeb) {
      // Web用: video要素を削除
      final video = html.document.getElementById('webcam-video');
      if (video != null) {
        video.remove();
      }
      return;
    }
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) {
      var video = html.document.getElementById('webcam-video') as html.VideoElement?;
      if (video == null) {
        video = html.VideoElement()
          ..autoplay = true
          ..width = 640 // 明示的なサイズ設定が役立つことがある
          ..height = 480
          ..style.display = _isDebugMode ? 'block' : 'none'; // デバッグモードでは表示
        video.id = 'webcam-video';
        html.document.body?.append(video);
      } else {
        // すでに存在する場合はスタイルを更新
        video.style.display = _isDebugMode ? 'block' : 'none';
      }

      try {
        final stream = await html.window.navigator.mediaDevices?.getUserMedia({'video': true});
        if (stream != null) {
          video.srcObject = stream;
          await video.onLoadedMetadata.first; // メタデータがロードされるまで待つ
          print('Webcam stream acquired and metadata loaded for video element.');

          // videoWidth と videoHeight が利用可能になるまで待機 (最大5秒程度)
          int attempts = 0;
          while ((video.videoWidth == null || video.videoWidth == 0 || video.videoHeight == null || video.videoHeight == 0) && attempts < 50) {
            await Future.delayed(const Duration(milliseconds: 100));
            attempts++;
          }
          print('Video dimensions available after $attempts attempts: width=${video.videoWidth}, height=${video.videoHeight}');

          if (video.videoWidth == null || video.videoWidth == 0 || video.videoHeight == null || video.videoHeight == 0) {
            print('Failed to get video dimensions after waiting.');
            _debugStatus = 'Webcam dimensions not available.';
            if (mounted) setState(() {});
            // ここで早期リターンするか、エラー処理を継続するか検討
          } else {
            // MediaPipeが初期化済みで、ゲームが開始されている or デバッグモードならループ開始
            // この呼び出しは _startGame に一本化するためコメントアウト、または削除
            /*
            if ((_isGameStarted || _isDebugMode) && _isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
                 print('Camera initialized and conditions met, starting web face detection loop from _initializeCamera.');
                _startWebFaceDetectionLoop();
            } else {
                 print('Camera initialized but conditions not met to start loop from _initializeCamera (isGameStarted: $_isGameStarted, isDebugMode: $_isDebugMode, isMediaPipeInitialized: $_isMediaPipeInitialized)');
            }
            */
            print('Webcam video dimensions available. Loop start will be handled by _startGame.');
          }
        } else {
          print('Failed to get webcam stream.');
          _debugStatus = 'Webcam stream acquisition failed.';
          if (mounted) setState(() {});
        }
      } catch (e) {
        print('Error initializing webcam for web: $e');
        _debugStatus = 'Webcam initialization error: $e';
        if (mounted) setState(() {});
      }
      return;
    }

    if (widget.cameras.isEmpty) {
      print('カメラが見つかりません');
      return;
    }
    if (_controller != null) {
      await _stopCamera();
    }
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await _controller!.initialize();
      if (!mounted) {
        await _stopCamera();
        return;
      }
      _controller!.startImageStream((image) {
        if (!_isProcessing) {
          _processImage(image);
        }
      });
    } catch (e) {
      print('カメラの初期化エラー: $e');
      await _stopCamera();
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (!_isGameStarted && !_isDebugMode) return;
    if (_isProcessing || _isGameOver) return;

    _isProcessing = true;
    try {
      if (kIsWeb) {
        // Web用の顔認識処理 - MediaPipeに置き換えるため、古いface-api.jsコードは削除
        if (!_isMediaPipeInitialized || _mediaPipeFaceDetector == null) {
          _debugStatus = 'MediaPipe未初期化';
          if(mounted) setState(() {});
          _isProcessing = false;
          return;
        }
        
        final videoElement = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (videoElement == null || videoElement.readyState != 4 || videoElement.videoWidth == 0 || videoElement.videoHeight == 0) {
           if(mounted) {
            setState(() {
              _debugStatus = 'Webcam video not ready for MediaPipe.';
            });
           }
          _isProcessing = false;
          return;
        }

        // TODO: Implement MediaPipe detection call here
        // final num frameTime = html.window.performance.now(); // Example timestamp
        // js_util.callMethod(_mediaPipeFaceDetector, 'detectForVideo', [videoElement, frameTime]);
        // Detection results will be handled by a listener or callback if configured, 
        // or directly if detectForVideo returns results synchronously (less common for video).
        // For now, just a placeholder:
        _debugStatus = 'MediaPipe detecting...';
        if (mounted) setState(() {});

        // Mock processing to allow game logic to proceed for testing UI
        // This section needs to be replaced with actual MediaPipe result processing.
        // setState(() {
        //   _isEyesOpen = true; // Assume open for now
        //   _consecutiveBlinkCount = 0;
        //   _mediaPipeDebugResult = null; // Store actual result here
        // });

      } else {
        // 既存のモバイル用顔認識処理 (google_mlkit_face_detection)
        final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final rotation = _controller!.description.sensorOrientation;

        print('Processing image with width: ${image.width}, height: ${image.height}');

        final inputImage = mlkit_fd.InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: mlkit_fd.InputImageMetadata(
            size: imageSize,
            rotation: mlkit_fd.InputImageRotation.values[rotation ~/ 90],
            format: mlkit_fd.InputImageFormat.nv21, // Ensure this matches your CameraImage format
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        final faces = await _faceDetector.processImage(inputImage);
        if (faces.isEmpty) {
          setState(() {
            _debugStatus = '顔が検出されていません';
            _debugFace = null;
          });
          print('processImage: 顔が検出されていません, _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode');
          return;
        }

        final face = faces.first;
        if (face.leftEyeOpenProbability == null || face.rightEyeOpenProbability == null) {
          setState(() {
            _debugStatus = '目の状態を検出できません';
          });
          print('processImage: 目の状態を検出できません, _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode');
          return;
        }

        final isFrontCamera = _controller!.description.lensDirection == CameraLensDirection.front;
        final leftProb = isFrontCamera
            ? face.rightEyeOpenProbability ?? 1.0 // フロントカメラの場合、左右を入れ替え
            : face.leftEyeOpenProbability ?? 1.0;
        final rightProb = isFrontCamera
            ? face.leftEyeOpenProbability ?? 1.0 // フロントカメラの場合、左右を入れ替え
            : face.rightEyeOpenProbability ?? 1.0;

        final leftEyeClosed = leftProb < EYE_CLOSED_THRESHOLD;
        final rightEyeClosed = rightProb < EYE_CLOSED_THRESHOLD;

        final leftEyeOpen = !leftEyeClosed;
        final rightEyeOpen = !rightEyeClosed;

        setState(() {
          _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
          _isEyesOpen = leftEyeOpen || rightEyeOpen;
          _debugFace = face;
        });
        updateEyeState(!leftEyeOpen && !rightEyeOpen);
        print('processImage: _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode, left: $leftEyeOpen, right: $rightEyeOpen');

        if (_isGameStarted && _wasEyesOpen && leftEyeClosed && rightEyeClosed) {
          _addScore();
          print('スコア加算!');
        }
        _wasEyesOpen = leftEyeOpen || rightEyeOpen;

        if (_isEyesOpen) {
          setState(() {
            _consecutiveBlinkCount = 0;
          });
        }
      }
    } catch (e) {
      print('画像処理エラー: $e');
      setState(() {
        _debugStatus = 'エラー: $e';
      });
    } finally {
      _isProcessing = false;
    }
  }

  List<Map<String, double>> _getEyePointsWeb(dynamic landmarks, bool isLeftEye) {
    // face-api.jsのlandmarks.getPositions()は68点の配列
    final points = <Map<String, double>>[];
    final start = isLeftEye ? 36 : 42; // 左目のランドマークインデックス (0-indexed)
    final end = isLeftEye ? 41 : 47;   // 右目のランドマークインデックス (0-indexed)
    
    // landmarksオブジェクトから座標リストを取得 (getRelativePositionsまたはgetPositions)
    // face-api.jsのバージョンやランドマークモデルによってプロパティ名が異なる場合がある
    var positions = js_util.getProperty(landmarks, 'positions');
    if (positions == null) {
      // getPositionsメソッドを試す (古いバージョンの場合)
      if (js_util.hasProperty(landmarks, 'getPositions')) {
        positions = js_util.callMethod(landmarks, 'getPositions', []);
      }
    }

    if (positions == null) return points;

    final length = js_util.getProperty(positions, 'length') as int?;
    if (length == null || length < end + 1) return points; // 必要な点があるか確認

    for (var i = start; i <= end; i++) {
      final point = js_util.getProperty(positions, i);
      if (point != null) {
        final x = js_util.getProperty(point, 'x');
        final y = js_util.getProperty(point, 'y');
        if (x is num && y is num) {
          points.add({
            'x': x.toDouble(),
            'y': y.toDouble(),
          });
        }
      }
    }
    return points;
  }

  bool _isEyeOpen(List<Map<String, double>> eyePoints) {
    if (eyePoints.length < 6) return true;
    
    // 目の高さと幅の比率を計算
    final height = (eyePoints[1]['y']! - eyePoints[5]['y']!).abs();
    final width = (eyePoints[0]['x']! - eyePoints[3]['x']!).abs();
    final ratio = height / width;
    
    // 比率が一定値より小さい場合は目が開いていると判定
    return ratio > 0.25;
  }

  Future<void> _startGame() async {
    print('■■■ ゲーム開始処理: 開始 ■■■');
    
    // 念のため、既存のタイマーを全てキャンセル
    _stationTimer?.cancel();
    _stationTimer = null;
    _eyesClosedScoreTimer?.cancel();
    _eyesClosedScoreTimer = null;
    
    // 状態リセットと初期設定
    setState(() {
      _isGameStarted = true;
      _isGameOver = false;
      _score = 0;
      _currentStation = _stations[0];
      _currentStationIndex = 0;
      _consecutiveBlinkCount = 0;
      _wasEyesOpen = true;
      _isEyesOpen = true; // 初期の目の状態を「開」に明確化
      _debugStatus = 'ゲーム状態準備中...';
    });
    
    print('■■■ カメラ初期化開始 ■■■');
    await _initializeCamera(); // カメラの準備をまず行う
    print('■■■ カメラ初期化完了 ■■■');

    // Webの場合はMediaPipe初期化
    if (kIsWeb) {
      print('■■■ Web: MediaPipe初期化開始 ■■■');
      if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
        // _initializeMediaPipe内で_isMediaPipeInitializingがtrueになる
        await _initializeMediaPipe(); 
      }
      
      // MediaPipeの初期化が本当に完了するまで待つ (最大15秒)
      int attempts = 0;
      while (!_isMediaPipeInitialized && attempts < 150) { 
        print('MediaPipe完全初期化待機中... 試行: $attempts, 初期化済み: $_isMediaPipeInitialized, 初期化中フラグ: $_isMediaPipeInitializing');
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
        // _isMediaPipeInitializing が false になり、_isMediaPipeInitialized が true になるのを期待
      }
      
      if (!_isMediaPipeInitialized) {
        print('MediaPipe完全初期化待機タイムアウト。顔認識が機能しない可能性があります。');
        if(mounted) setState(() => _debugStatus = 'MP完全初期化失敗(T)');
        // タイムアウトしても、カメラとビデオ要素の準備ができていればループは試みる
        // ただし、MediaPipeインスタンスがないと検出はできない
      } else {
        print('MediaPipe完全初期化成功。');
        if(mounted) setState(() => _debugStatus = 'MP完全初期化成功');
      }

      // MediaPipeの初期化成否に関わらず、ループ開始は試みるが、
      // ループ内部でMediaPipeインスタンスの存在を確認する
      print('顔認識ループ開始試行 (MP初期化処理後)...');
      _startWebFaceDetectionLoop();

    } else { // モバイルの場合
      // モバイルではMediaPipeは使わないので、カメラ初期化後すぐにゲームロジックに進める
      print('モバイルプラットフォームです。MediaPipe処理はスキップします。');
    }

    print('■■■ 電車音声再生開始 ■■■');
    await _playTrainSound();
    
    await Future.delayed(Duration.zero); // イベントキュー処理
    print('イベントキュー処理後、タイマー作成開始');

    print('■■■ ゲームタイマー作成開始 ■■■');
    // 駅切り替えタイマー作成
    print('★★★ 駅切り替えタイマー作成開始 ★★★');
    _stationTimer = Timer.periodic(
      Duration(seconds: STATION_CHANGE_SECONDS),
      (timer) {
        print('【駅タイマー発火】isGameStarted: $_isGameStarted, isGameOver: $_isGameOver');
        if (!_isGameStarted || _isGameOver) {
          print('駅タイマー: 条件不一致またはゲーム終了のためキャンセル');
          timer.cancel();
          return;
        }
        
        if (mounted) {
          setState(() {
            if (_currentStationIndex < _stations.length - 1) {
              _currentStationIndex++;
              _currentStation = _stations[_currentStationIndex];
              print('駅を更新: $_currentStation (index: $_currentStationIndex)');
            } else {
              _isGameOver = true;
              _isGameStarted = false; 
              print('終点到着、ゲームオーバー');
              timer.cancel();
              _showGameOver(message: '終点に到着しました');
            }
          });
        } else {
          print('駅タイマー: mountedがfalseのためsetStateスキップ');
        }
      }
    );
    print('★★★ 駅タイマー作成成功 ★★★');
    
    // スコア加算タイマー
    print('◆◆◆ スコア加算タイマー作成開始 ◆◆◆');
    _eyesClosedScoreTimer = Timer.periodic(
      Duration(milliseconds: EYES_CLOSED_SCORE_INTERVAL),
      (timer) {
        if (!_isGameStarted || _isGameOver) {
          timer.cancel();
          return;
        }
        if (!_isEyesOpen) {
          _eyesClosedDuration += EYES_CLOSED_SCORE_INTERVAL;
          int bonus = 0;
          if (_eyesClosedDuration >= 3000) {
            bonus = 5; // 3秒以上連続で閉じていたら5点ボーナス
          } else if (_eyesClosedDuration >= 1500) {
            bonus = 2; // 1.5秒以上なら2点ボーナス
          }
          if (mounted) {
            setState(() {
              _score += EYES_CLOSED_SCORE_INCREMENT + bonus;
            });
          }
          // いびきSE再生
          if (!_isSnorePlaying && _snorePlayer != null) {
            _snorePlayer?.play();
            _isSnorePlaying = true;
          }
        } else {
          _eyesClosedDuration = 0;
          // いびきSE停止
          if (_isSnorePlaying && _snorePlayer != null) {
            _snorePlayer?.stop();
            _isSnorePlaying = false;
          }
        }
      }
    );
    print('◆◆◆ スコア加算タイマー作成成功 ◆◆◆');
    
    if (mounted) {
       setState(() {
         print('ゲーム開始処理の最後にUIを強制更新。現在の目の状態: $_isEyesOpen, スコア: $_score, 駅: $_currentStation');
         _debugStatus = kIsWeb ? _debugStatus : 'モバイルゲーム開始準備完了'; // Web以外の場合のステータス設定
       });
    }
    print('■■■ ゲーム開始処理: 完了 ■■■');
  }

  void _addScore() {
    if (!_isGameStarted || _isGameOver) return;

    setState(() {
      _consecutiveBlinkCount++;
      
      if (_consecutiveBlinkCount >= MAX_CONSECUTIVE_BLINKS) {
        _isGameOver = true;
        _isGameStarted = false;
        _stationTimer?.cancel();
        _showGameOver(message: '連続で目を閉じすぎました！');
      }
    });
  }

  Future<void> _resetToTitle() async {
    print('タイトルに戻ります: SE停止試行開始');
    await _stopTrainSound();
    // ゲームオーバー・クリアSEも停止
    await _gameOverSoundPlayer?.stop();
    await _gameClearSoundPlayer?.stop();
    print('タイトルに戻ります: SE停止完了');
    
    // 背景をランダムに変更
    _selectRandomBackground();
    
    setState(() {
      _isGameStarted = false;
      _isGameOver = false;
      _score = 0;
      _currentStation = '';
      _currentStationIndex = 0;
      _consecutiveBlinkCount = 0;
      _wasEyesClosedDuringStation = false;
      _consecutiveStationsWithEyesClosed = 0;
      _wasEyesOpen = true;
      _isDebugMode = false; 
      _debugStatus = '';
      _debugFace = null;
      _mediaPipeDebugResult = null;
    });
    
    print('タイマーキャンセル開始');
    _stationTimer?.cancel();
    _eyesClosedScoreTimer?.cancel();
    _stopWebFaceDetectionLoop();
    _stopCamera();
    print('タイマーキャンセル完了');
  }

  Future<void> _showGameOver({String? message, bool isClear = false}) async {
    print('ゲームオーバー処理開始: SE停止試行');
    // 確実にSEを停止するため、ゲーム状態も先に変更
    setState(() {
      _isGameStarted = false;
      _isGameOver = true;
    });
    
    _stationTimer?.cancel();
    _stationTimer = null;
    _eyesClosedScoreTimer?.cancel();
    _eyesClosedScoreTimer = null;
    
    await _stopTrainSound();
    print('ゲームオーバー処理: SE停止完了');

    // ゲームオーバー/クリアSEの再生
    if (isClear) {
      _gameClearSoundPlayer?.seek(Duration.zero); // 再生位置を最初に戻す
      _gameClearSoundPlayer?.play();
      
      // フリープレイモードではLINE連携処理をスキップ
      if (!widget.gameService.isFreePlay) {
        // ニックネーム入力ダイアログを表示
        await _showNicknameInputDialog();
      } else {
        print('フリープレイモードのためLINE連携処理をスキップしました');
      }
    } else {
      _gameOverSoundPlayer?.seek(Duration.zero); // 再生位置を最初に戻す
      _gameOverSoundPlayer?.play();
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isClear
                  ? [Color(0xFFFFF8E1), Color(0xFFFFECB3)]
                  : [Color(0xFFF8BBD0), Color(0xFFF48FB1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isClear ? Icons.emoji_events : Icons.sentiment_very_dissatisfied,
                color: isClear ? Colors.amber[800] : Colors.redAccent,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                isClear ? 'ゲームクリア！' : 'ゲームオーバー',
                style: GoogleFonts.mochiyPopOne(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: isClear ? Colors.amber[800] : Colors.redAccent,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message ?? (isClear ? 'おめでとうございます！' : 'また挑戦してね！'),
                style: GoogleFonts.mochiyPopOne(fontSize: 18, color: Colors.black87, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: isClear ? Colors.amber[100] : Colors.pink[100],
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.orange, size: 28),
                    const SizedBox(width: 8),
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$_score',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // フリープレイモード表示
              if (widget.gameService.isFreePlay && isClear)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'フリープレイモード',
                    style: GoogleFonts.mochiyPopOne(
                      fontSize: isSmallScreen ? 12 : 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              // LINEに戻るボタンを追加（クリア時のみ、かつフリープレイでない場合）
              if (isClear && !widget.gameService.isFreePlay)
                ElevatedButton.icon(
                  onPressed: () {
                    // LINEに戻るボタン
                    Navigator.of(context).pop();
                    // LINE公式アカウントのトーク画面を開く
                    _openUrl('https://line.me/R/ti/p/@910frzll');
                  },
                  icon: const Icon(Icons.chat),
                  label: Text('LINEに戻る', style: GoogleFonts.mochiyPopOne()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06C755), // LINE緑
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    elevation: 8,
                  ),
                ),
              if (isClear && !widget.gameService.isFreePlay)
                const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // 背景をランダムに変更してからタイトルへ戻る
                  _selectRandomBackground();
                  await _resetToTitle();
                },
                icon: const Icon(Icons.home),
                label: Text(isClear ? 'タイトルへ戻る' : 'タイトルへ戻る', style: GoogleFonts.mochiyPopOne()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isClear ? Colors.amber : Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  elevation: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ニックネーム入力ダイアログを表示するメソッド
  Future<void> _showNicknameInputDialog() async {
    final TextEditingController nicknameController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            padding: const EdgeInsets.all(28),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.emoji_events,
                  color: Colors.amber[800],
                  size: 60,
                ),
                const SizedBox(height: 24),
                Text(
                  'ゲームクリア！',
                  style: GoogleFonts.mochiyPopOne(
                    fontSize: 28,
                    color: Colors.amber[900],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'ニックネームを入力してください',
                  style: GoogleFonts.mochiyPopOne(
                    fontSize: 18,
                    color: Colors.amber[900],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nicknameController,
                  decoration: InputDecoration(
                    hintText: 'ニックネーム',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  style: GoogleFonts.mochiyPopOne(
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSubmitting)
                      const CircularProgressIndicator()
                    else
                      ElevatedButton.icon(
                        onPressed: () async {
                          final nickname = nicknameController.text.trim();
                          if (nickname.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ニックネームを入力してください'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setState(() => isSubmitting = true);

                          try {
                            final success = await widget.gameService.saveNickname(nickname);
                            if (success) {
                              Navigator.of(context).pop();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(widget.gameService.errorMessage),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('エラーが発生しました: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            setState(() => isSubmitting = false);
                          }
                        },
                        icon: const Icon(Icons.save),
                        label: Text('保存', style: GoogleFonts.mochiyPopOne()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 14,
                          ),
                          elevation: 8,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // URLを開くヘルパーメソッド
  void _openUrl(String url) {
    // Web上でURLを開く（すでにインポート済みのhtmlライブラリを使用）
    html.window.open(url, '_blank');
  }

  void _startWebFaceDetectionLoop() {
    print('▶▶▶ WebFaceDetectionLoopの開始試行');
    
    // 既存のタイマーを停止
    _webDetectTimer?.cancel();
    
    _webDetectTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!kIsWeb) {
        _webDetectTimer?.cancel();
        return;
      }
      
      // MediaPipeが未初期化の場合は初期化を試みる
      if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
        print('MP LOOP: MediaPipe未初期化のため初期化を試みます');
        _initializeMediaPipe();
        // 初期化中は検出をスキップするが、ループ自体は継続
        if (mounted) {
          setState(() {
            _debugStatus = 'MediaPipe初期化中...';
          });
        }
        return;
      }
      
      // 初期化中ならステータス更新のみ
      if (_isMediaPipeInitializing) {
        if (mounted) {
          setState(() {
            _debugStatus = 'MediaPipe初期化処理中...';
          });
        }
        return;
      }
      
      // MediaPipeが初期化完了していれば検出処理を実行
      if (_isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
        final videoElement = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (videoElement != null && videoElement.readyState == 4 && videoElement.videoWidth! > 0 && videoElement.videoHeight! > 0) {
          try {
            final num frameTime = html.window.performance.now();
            print('MP LOOP: Attempting to call detectForVideo with frameTime: $frameTime for video id: ${videoElement.id}');
            
            // FaceLandmarkerのdetectForVideoメソッドを正しく呼び出す
            final result = js_util.callMethod(_mediaPipeFaceDetector, 'detectForVideo', [videoElement, frameTime]);
            
            // 結果を直接処理（結果がnullでない場合）
            if (result != null) {
              print('MP LOOP: Direct result processing');
              _processMediaPipeResultsWeb(result);
            } else {
              print('MP LOOP: detectForVideo returned null result');
            }
            
            print('MP LOOP: detectForVideo call completed.');
          } catch (e, s) {
            print('Web MediaPipe detection error in loop: $e\n$s');
            if (mounted) {
              setState(() {
                _debugStatus = 'MediaPipe検出エラー: $e';
              });
            }
          }
        } else {
           if (mounted) {
              setState(() {
                _debugStatus = 'Video element not ready for MediaPipe detection.';
              });
            }
        }
      } else {
        if (mounted) {
          setState(() {
            _debugStatus = 'MediaPipe未初期化 (検出ループ実行中)';
          });
        }
      }
    });
    
    print('▶▶▶ WebFaceDetectionLoop開始完了');
  }

  void _stopWebFaceDetectionLoop() {
    _webDetectTimer?.cancel();
    _webDetectTimer = null;
  }

  void _toggleDebugMode() async {
    print('DEBUG_MODE: _toggleDebugMode called. Current _isDebugMode: $_isDebugMode');
    final newDebugModeState = !_isDebugMode;

    if (newDebugModeState) { // デバッグモードを有効にする場合
      print('DEBUG_MODE: Enabling debug mode...');
      setState(() {
        _isDebugMode = true;
        _debugStatus = 'デバッグモード準備中...';
      });

      if (kIsWeb) {
        print('DEBUG_MODE: Platform is Web.');
        await _initializeCamera(); // カメラを先に準備
        print('DEBUG_MODE: Camera initialized for debug mode.');

        // ビデオ要素の表示を更新
        var video = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (video != null) {
          video.style.display = 'block';
        }

        if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
          print('DEBUG_MODE: MediaPipe not initialized. Calling _initializeMediaPipe.');
          await _initializeMediaPipe();
        }

        if (_isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
          print('DEBUG_MODE: MediaPipe ready, starting web face detection loop.');
          setState(() => _debugStatus = 'MPデバッグ検出ループ開始試行');
          _startWebFaceDetectionLoop();
        } else {
          print('DEBUG_MODE: MediaPipe NOT ready. Cannot start detection loop.');
          setState(() => _debugStatus = 'MP準備未完了(デバッグ)');
        }
      } else { // Mobile
        print('DEBUG_MODE: Platform is Mobile, calling _initializeCamera.');
        await _initializeCamera();
        setState(() => _debugStatus = 'モバイルデバッグモード有効');
      }
    } else { // デバッグモードを無効にする場合
      print('DEBUG_MODE: Disabling debug mode...');
      if (kIsWeb) {
        print('DEBUG_MODE: Stopping web face detection loop (web).');
        _stopWebFaceDetectionLoop();
      }
      // _stopCamera(); // これは_resetToTitleに任せるか、状態に応じて判断
      setState(() {
        _isDebugMode = false;
        _debugStatus = '';
        _debugFace = null;
        _mediaPipeDebugResult = null;
      });
      print('DEBUG_MODE: Debug mode disabled.');
    }
  }

  void _showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent, size: 48),
                const SizedBox(height: 12),
                Text(
                  '遊び方',
                  style: GoogleFonts.mochiyPopOne(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 18),
                _howToRow(Icons.score, '出来るだけ長く目を閉じて眠ろう！目をつぶっている時間が長いほどスコアUP！'), // アイコンとテキスト変更
                const SizedBox(height: 12),
                _howToRow(Icons.flag, '「福工大前」駅が最終目的地だよ！'), // アイコンとテキスト変更
                const SizedBox(height: 12),
                _howToRow(Icons.train, '目的の駅「福工大前」で「降りる！」ボタンを押してクリア！'), // テキスト変更
                const SizedBox(height: 12),
                _howToRow(Icons.warning_amber, '寝過ごして福工大を通り過ぎたり、降りる駅を間違えるとゲームオーバー！'), // テキスト変更
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: Text('閉じる', style: GoogleFonts.mochiyPopOne()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _howToRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.orange, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.mochiyPopOne(fontSize: 18, color: Colors.black87, height: 1.4),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    print('dispose: リソース解放開始');
    WidgetsBinding.instance.removeObserver(this);
    _stationTimer?.cancel();
    _eyesClosedScoreTimer?.cancel(); // 目を閉じている間のスコア加算タイマーを停止
    _webDetectTimer?.cancel();
    _stopCamera();
    _faceDetector.close();
    _animationController.dispose();
    
    // 音声プレーヤーを確実に停止して解放
    if (_isPlayingSound) {
      _audioPlayer?.stop();
    }
    _audioPlayer?.dispose();
    _audioPlayer = null;
    
    // ゲームオーバー・クリアSEの解放
    _gameOverSoundPlayer?.dispose();
    _gameOverSoundPlayer = null;
    _gameClearSoundPlayer?.dispose();
    _gameClearSoundPlayer = null;
    // いびきSEの解放
    if (_isSnorePlaying) {
      _snorePlayer?.stop();
    }
    _snorePlayer?.dispose();
    _snorePlayer = null;
    
    print('dispose: リソース解放完了');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 画面サイズを取得
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.height < 600;

    return Scaffold(
      // オーバーフローを防止するレイアウト
      body: SafeArea(
        child: Stack(
          children: [
            // 背景 - これは常に表示
            Positioned.fill(
              child: CustomPaint(
                painter: TitleScreenBackgroundPainter(
                  backgroundType: _currentBackgroundType,
                ),
              ),
            ),
            
            // タイトル画面
            if (!_isGameStarted && !_isDebugMode) 
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 上部スペース
                      SizedBox(height: isSmallScreen ? 20 : screenSize.height * 0.05),
                      
                      // タイトルとメインコンテンツ
                      Text(
                        '寝過ごしパニック',
                        style: GoogleFonts.mochiyPopOne(
                          fontSize: isSmallScreen ? 36 : 42, // フォントサイズを大きく
                          color: Colors.white,
                          letterSpacing: 2.0,
                          shadows: const [
                            Shadow(
                              color: Colors.black38,
                              offset: Offset(2, 2),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      // 背景タイプ表示
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _currentBackgroundType.icon,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _currentBackgroundType.name,
                              style: GoogleFonts.mochiyPopOne(
                                fontSize: isSmallScreen ? 16 : 18,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // ステージ表示
                      Padding(
                        padding: EdgeInsets.only(top: 12, bottom: isSmallScreen ? 20 : 24),
                        child: Text(
                          'STAGE3',
                          style: GoogleFonts.mochiyPopOne(
                            fontSize: isSmallScreen ? 28 : 32,
                            color: Colors.amber[300],
                            letterSpacing: 6,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                offset: Offset(0, 3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // スタートボタン
                      Container(
                        width: isSmallScreen ? 240 : 280, // 幅を固定
                        height: isSmallScreen ? 60 : 70, // 高さを固定
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton(
                          onPressed: _isGameStarted ? null : _startGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blue[900],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(35),
                            ),
                            elevation: 8,
                            shadowColor: Colors.black38,
                          ),
                          child: Text(
                            'スタート',
                            style: GoogleFonts.mochiyPopOne(
                              fontSize: isSmallScreen ? 24 : 28,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      
                      // フリープレイモードの表示
                      if (widget.gameService.isFreePlay)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'フリープレイモード',
                            style: GoogleFonts.mochiyPopOne(
                              fontSize: isSmallScreen ? 14 : 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      
                      // 操作ボタン
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 16 : 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildActionButton(
                              onPressed: () => _showHowToPlayDialog(context),
                              icon: Icons.help_outline,
                              label: '遊び方',
                              color: Colors.blueAccent,
                              isSmallScreen: isSmallScreen,
                            ),
                            const SizedBox(width: 16),
                            _buildActionButton(
                              onPressed: _resetBackground,
                              icon: Icons.landscape,
                              label: '背景変更',
                              color: Colors.teal,
                              isSmallScreen: isSmallScreen,
                            ),
                          ],
                        ),
                      ),
                      
                      // デバッグとフリープレイボタン
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildActionButton(
                              onPressed: _toggleDebugMode,
                              icon: Icons.bug_report,
                              label: _isDebugMode ? 'デバッグ終了' : 'デバッグ開始',
                              color: _isDebugMode ? Colors.red : Colors.grey[700]!,
                              isSmallScreen: isSmallScreen,
                              width: isSmallScreen ? 140 : 160,
                            ),
                            const SizedBox(width: 16),
                            _buildActionButton(
                              onPressed: !widget.gameService.isFreePlay ? _toggleFreePlayMode : null,
                              icon: Icons.videogame_asset,
                              label: 'フリープレイ',
                              color: widget.gameService.isFreePlay ? Colors.grey : Colors.orange,
                              isSmallScreen: isSmallScreen,
                              width: isSmallScreen ? 140 : 160,
                            ),
                          ],
                        ),
                      ),
                      
                      // ゲーム説明テキスト
                      Padding(
                        padding: EdgeInsets.fromLTRB(24, isSmallScreen ? 8 : 16, 24, isSmallScreen ? 24 : 32),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'なんとか電車には乗り込めたKOU君だが既に疲れてウトウト...',
                                style: GoogleFonts.mochiyPopOne(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 14 : 16,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: isSmallScreen ? 8 : 12),
                              Text(
                                '果たして寝過ごさずに福工大前にたどり着けるのか！？',
                                style: GoogleFonts.mochiyPopOne(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 14 : 16,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // デバッグモードと他のゲーム画面要素はそのまま保持
            if (_isDebugMode) 
              if (kIsWeb)
                Positioned.fill(
                  child: Stack(
                    children: [
                      // カメラビューは透明なHtmlElementViewで配置
                      Positioned.fill(
                        child: Container(
                          color: Colors.transparent, // 背景を透明に
                          child: HtmlElementView(viewType: 'webcam-video'),
                        ),
                      ),
                      
                      // 顔のランドマークを表示するオーバーレイ
                      if (_mediaPipeDebugResult != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: MediaPipeFacePainter(
                            _mediaPipeDebugResult,
                            MediaQuery.of(context).size,
                          ),
                          foregroundPainter: _isDebugMode ? null : FaceDistanceWarningPainter(
                            _mediaPipeDebugResult,
                            MediaQuery.of(context).size,
                          ),
                        ),
                      ),
                      
                      // デバッグ情報オーバーレイ
                      Positioned(
                        right: 20,
                        top: 20,
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isMediaPipeInitialized ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'MediaPipe: ${_isMediaPipeInitialized ? "初期化済み" : "未初期化"}',
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _debugStatus,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _isEyesOpen ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '目の状態: ${_isEyesOpen ? "開いています" : "閉じています"}',
                                  style: TextStyle(
                                    color: _isEyesOpen ? Colors.greenAccent : Colors.redAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // タイトルへ戻るボタン (左上に丸く浮かせる)
                      Positioned(
                        top: 32,
                        left: 17,
                        child: Material(
                          color: Colors.white.withOpacity(0.85),
                          shape: const CircleBorder(),
                          elevation: 6,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.blueAccent, size: 28),
                            onPressed: _resetToTitle,
                            tooltip: 'タイトルへ',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_controller != null && _controller!.value.isInitialized)
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      // スクリーンサイズの取得
                      final screenSize = MediaQuery.of(context).size;
                      final isSmallScreen = screenSize.height < 600;
                      
                      Size adjustedPreviewSize = _controller!.value.previewSize!;
                      if (MediaQuery.of(context).orientation == Orientation.portrait && adjustedPreviewSize.width > adjustedPreviewSize.height) {
                        adjustedPreviewSize = Size(adjustedPreviewSize.height, adjustedPreviewSize.width);
                      }
                      return Center(
                        child: AspectRatio(
                          aspectRatio: 1 / _controller!.value.aspectRatio,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final previewW = constraints.maxWidth;
                              final previewH = constraints.maxHeight;
                              return Stack(
                                children: [
                                  CameraPreview(_controller!),
                                  if (_debugFace != null)
                                    CustomPaint(
                                      painter: FaceLandmarkPainter(
                                        _debugFace!,
                                        adjustedPreviewSize,
                                        _controller!.description.lensDirection == CameraLensDirection.front,
                                        previewW,
                                        previewH,
                                      ),
                                      size: Size(previewW, previewH),
                                    ),
                                  Positioned(
                                    top: 40,
                                    right: 40,
                                    child: ElevatedButton(
                                      onPressed: _toggleDebugMode,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isSmallScreen ? 16 : 24, 
                                          vertical: isSmallScreen ? 10 : 12
                                        ),
                                      ),
                                      child: Text(
                                        'デバッグモード終了',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
            // ゲーム画面も同様に保持
            if (_isGameStarted)
              Builder(
                builder: (context) {
                  // スクリーンサイズの取得（レスポンシブ対応）
                  final screenSize = MediaQuery.of(context).size;
                  final isSmallScreen = screenSize.height < 600;

                  final windowRect = TrainInteriorPainter.getWindowRect(screenSize);
                  return Stack(
                    children: [
                      // 電車内のイラスト（背景）
                      Positioned.fill(
                        child: CustomPaint(
                          painter: TrainInteriorPainter(
                            offset: _sceneryAnimation.value,
                            isEyesOpen: _isEyesOpen,
                          ),
                        ),
                      ),
                      // 窓の外の景色アニメーション（窓の内側だけにクリップ）
                      Positioned(
                        left: windowRect.left,
                        top: windowRect.top,
                        width: windowRect.width,
                        height: windowRect.height,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: AnimatedSceneryWidget(
                            offset: _sceneryAnimation.value,
                            isEyesOpen: _isEyesOpen,
                          ),
                        ),
                      ),
                      // 目が閉じている時の暗いオーバーレイ
                      if (!_isEyesOpen)
                        Positioned.fill(
                          child: Container(
                            color: Color.fromRGBO(0, 0, 0, 0.9),
                          ),
                        ),
                      // 駅名表示とスコア表示（上部中央に縦並びカード風）
                      Positioned(
                        top: isSmallScreen ? 16 : 24,
                        left: 32,
                        right: 32,
                        child: Column(
                          children: [
                            // 駅名カード
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 20 : 28, 
                                vertical: isSmallScreen ? 12 : 16
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5), // 透明度を 0.85 から 0.5 に変更
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.10),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.train, color: Colors.blueAccent, size: isSmallScreen ? 24 : 30),
                                  SizedBox(width: isSmallScreen ? 10 : 14),
                                  Text(
                                    _currentStation,
                                    style: GoogleFonts.mochiyPopOne(
                                      fontSize: isSmallScreen ? 22 : 26,
                                      color: Colors.blueAccent,
                                      letterSpacing: 2,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black26,
                                          offset: Offset(1, 2),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // スコアバッジ
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 20 : 24, 
                                vertical: isSmallScreen ? 8 : 10
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amberAccent,
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star, color: Colors.white, size: isSmallScreen ? 20 : 24),
                                  SizedBox(width: isSmallScreen ? 6 : 8),
                                  Text(
                                    'SCORE',
                                    style: GoogleFonts.mochiyPopOne(
                                      fontSize: isSmallScreen ? 16 : 18,
                                      color: Colors.white,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  SizedBox(width: isSmallScreen ? 8 : 10),
                                  Text(
                                    '$_score',
                                    style: GoogleFonts.mochiyPopOne(
                                      fontSize: isSmallScreen ? 18 : 22,
                                      color: Colors.white,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 顔認識状態表示（右下）
                      Positioned(
                        right: 16,
                        bottom: isSmallScreen ? 20 : 32,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _debugStatus,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmallScreen ? 13 : 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      // 降りる!ボタン（下中央に大きく）
                      Positioned(
                        // 位置調整：十分な余白を確保し、オーバーフローを防止
                        bottom: isSmallScreen ? 40 : 60, // より大きな値に
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (_currentStation == '福工大前') {
                                _isGameOver = true;
                                _isGameStarted = false;
                                _stationTimer?.cancel();
                                await _showGameOver(message: 'ゲームクリア！福工大前で降りました！', isClear: true);
                              } else {
                                _isGameOver = true;
                                _isGameStarted = false;
                                _stationTimer?.cancel();
                                await _showGameOver(message: '${_currentStation}で降りてしまいました。ゲームオーバー！');
                              }
                            },
                            icon: Icon(Icons.directions_walk, color: Colors.white, size: isSmallScreen ? 24 : 28),
                            label: Text(
                              '降りる！',
                              style: GoogleFonts.mochiyPopOne(
                                fontSize: isSmallScreen ? 18 : 22,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 28 : 36, 
                                vertical: isSmallScreen ? 14 : 18
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                              elevation: 12,
                              shadowColor: Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ),
                      // 目を閉じている時の暗いオーバーレイ（Stackの一番上に移動）
                      if (!_isEyesOpen)
                        Positioned.fill(
                          child: Container(
                            color: Color.fromRGBO(0, 0, 0, 1.0),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // MediaPipeからの検出結果を処理するコールバック関数 (Web用)
  void _processMediaPipeResultsWeb(dynamic result) {
    print('MP CALLED: _processMediaPipeResultsWeb with result');
    
    if (_isProcessing || (!_isGameStarted && !_isDebugMode) || _isGameOver) {
      _isProcessing = false;
      return;
    }
    _isProcessing = true;

    try {
      final faceLandmarks = js_util.getProperty(result, 'faceLandmarks');
      final faceBlendshapes = js_util.getProperty(result, 'faceBlendshapes');

      print('MP faceLandmarks: ${faceLandmarks != null ? "present" : "null"}');
      if (faceLandmarks != null) {
        print('MP faceLandmarks.length: ${js_util.getProperty(faceLandmarks, 'length')}');
      }

      if (faceLandmarks == null || js_util.getProperty(faceLandmarks, 'length') == 0) {
        if (mounted) {
          setState(() {
            _debugStatus = 'MP: 顔未検出';
            _isEyesOpen = true;
            _consecutiveBlinkCount = 0;
            _mediaPipeDebugResult = result;
          });
        }
        _isProcessing = false;
        return;
      }

      // 最初の顔のランドマークを取得
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      print('MP firstFaceLandmarks found');
      
      // ダーティファイする前にランドマークの長さを確認
      final landmarksLength = js_util.hasProperty(firstFaceLandmarks, 'length') 
          ? js_util.getProperty(firstFaceLandmarks, 'length') 
          : 'unknown';
      print('MP landmarks length: $landmarksLength');
      
      List<dynamic> landmarks;
      try {
        landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;
        print('MP landmarks dartified length: ${landmarks.length}');
      } catch (e) {
        print('Failed to dartify landmarks: $e');
        // ランドマークの変換に失敗した場合は代替手段を試す
        landmarks = [];
        final length = js_util.getProperty(firstFaceLandmarks, 'length') as int? ?? 0;
        for (int i = 0; i < length; i++) {
          try {
            final point = js_util.getProperty(firstFaceLandmarks, i);
            final x = js_util.getProperty(point, 'x');
            final y = js_util.getProperty(point, 'y');
            final z = js_util.getProperty(point, 'z');
            landmarks.add({
              'x': x is num ? x.toDouble() : 0.0,
              'y': y is num ? y.toDouble() : 0.0,
              'z': z is num ? z.toDouble() : 0.0,
            });
          } catch (e) {
            print('Landmark $i conversion error: $e');
          }
        }
      }
      
      // 目の状態をblendshapesから検出する方法を試みる
      bool eyesOpenFromBlendshapes = true;
      if (faceBlendshapes != null && js_util.getProperty(faceBlendshapes, 'length') > 0) {
        try {
          final firstBlendshapes = js_util.getProperty(faceBlendshapes, 0);
          final categories = js_util.getProperty(firstBlendshapes, 'categories');
          
          // 目を閉じる表情を探す (eyeBlinkLeft, eyeBlinkRight)
          double leftEyeClosedScore = 0.0;
          double rightEyeClosedScore = 0.0;
          
          if (categories != null) {
            final length = js_util.getProperty(categories, 'length') as int? ?? 0;
            for (int i = 0; i < length; i++) {
              final category = js_util.getProperty(categories, i);
              final name = js_util.getProperty(category, 'categoryName') as String?;
              final score = js_util.getProperty(category, 'score') as num?;
              
              if (name == 'eyeBlinkLeft' && score != null) {
                leftEyeClosedScore = score.toDouble();
              } else if (name == 'eyeBlinkRight' && score != null) {
                rightEyeClosedScore = score.toDouble();
              }
            }
          }
          
          // スコアが閾値を超えたら目を閉じていると判断
          final blendshapeThreshold = 0.35; // 0.3から0.35に変更 (判定を少し厳しく)
          final leftEyeClosed = leftEyeClosedScore > blendshapeThreshold;
          final rightEyeClosed = rightEyeClosedScore > blendshapeThreshold;
          eyesOpenFromBlendshapes = !(leftEyeClosed && rightEyeClosed);
          
          print('Blendshapes: Left eye closed: $leftEyeClosedScore, Right eye closed: $rightEyeClosedScore');
        } catch (e) {
          print('Blendshapes 処理エラー: $e');
        }
      }
      
      // 目のランドマークのインデックス（MediaPipe Face Landmarker）
      // 左目の上下のランドマークは約159（上）と145（下）
      // 右目の上下のランドマークは約386（上）と374（下）
      const int leftEyeUpperIndex = 159;
      const int leftEyeLowerIndex = 145;
      const int rightEyeUpperIndex = 386;
      const int rightEyeLowerIndex = 374;
      
      bool leftEyeOpen = true;
      bool rightEyeOpen = true;
      
      if (landmarks.length > rightEyeUpperIndex) {
        try {
          // 左目の開閉判定
          final leftEyeUpper = landmarks[leftEyeUpperIndex] as Map;
          final leftEyeLower = landmarks[leftEyeLowerIndex] as Map;
          
          // yプロパティの取得
          final leftEyeUpperY = leftEyeUpper['y'] is num ? (leftEyeUpper['y'] as num).toDouble() : 0.0;
          final leftEyeLowerY = leftEyeLower['y'] is num ? (leftEyeLower['y'] as num).toDouble() : 0.0;
          final leftEyeDistance = (leftEyeUpperY - leftEyeLowerY).abs();
          
          // 右目の開閉判定
          final rightEyeUpper = landmarks[rightEyeUpperIndex] as Map;
          final rightEyeLower = landmarks[rightEyeLowerIndex] as Map;
          final rightEyeUpperY = rightEyeUpper['y'] is num ? (rightEyeUpper['y'] as num).toDouble() : 0.0;
          final rightEyeLowerY = rightEyeLower['y'] is num ? (rightEyeLower['y'] as num).toDouble() : 0.0;
          final rightEyeDistance = (rightEyeUpperY - rightEyeLowerY).abs();
          
          // しきい値以下なら目を閉じていると判定
          const eyeClosedThreshold = 0.005; // 0.006から0.005に変更 (開いている判定を少し厳しく)
          leftEyeOpen = leftEyeDistance > eyeClosedThreshold;
          rightEyeOpen = rightEyeDistance > eyeClosedThreshold;
          
          print('目の開閉状態 - 左: $leftEyeOpen (距離: ${leftEyeDistance.toStringAsFixed(4)}), 右: $rightEyeOpen (距離: ${rightEyeDistance.toStringAsFixed(4)})');
          
          // ランドマークとblendshapesの両方から判定
          final newEyesOpenState = (leftEyeOpen || rightEyeOpen) && eyesOpenFromBlendshapes;
          print('最終判定: ${newEyesOpenState ? "目を開いている" : "目を閉じている"} (ランドマーク & ブレンドシェイプ結合)');
        
          _debugStatus = 'MP: 顔検出 左目: ${leftEyeOpen ? "開" : "閉"} 右目: ${rightEyeOpen ? "開" : "閉"}';
          
          if (mounted) {
            setState(() {
              // 目の状態更新
              _isEyesOpen = newEyesOpenState;
              updateEyeState(!newEyesOpenState);
              
              // 目を閉じた場合は駅通過フラグを立てる
              if (!newEyesOpenState) {
                _wasEyesClosedDuringStation = true;
                print('目を閉じています: スコア継続加算対象');
              }
              
              // まばたき検出
              if (_wasEyesOpen && !newEyesOpenState) {
                _addScore(); // まばたき連続カウント用
                print('MP: まばたき検出');
              }
              _wasEyesOpen = newEyesOpenState;
              
              if (newEyesOpenState) {
                _consecutiveBlinkCount = 0;
              }
              _mediaPipeDebugResult = result;
            });
          }
        } catch (e) {
          print('目の開閉判定エラー: $e');
          if (mounted) {
            setState(() {
              _debugStatus = 'MP解析エラー: $e';
              _mediaPipeDebugResult = result;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _debugStatus = 'MP: ランドマーク不足 (${landmarks.length})';
            _isEyesOpen = true;
            _mediaPipeDebugResult = result;
          });
        }
      }
    } catch (e, s) {
      print('MediaPipe結果処理エラー: $e\n$s');
      if (mounted) setState(() => _debugStatus = 'MP結果処理エラー: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // 目を閉じている間定期的にスコアを加算するタイマー
  void _startEyesClosedScoreTimer() {
    print('◆◆◆ スコア加算タイマー初期化開始 ◆◆◆');

    // 既存のタイマーを確実にキャンセル
    if (_eyesClosedScoreTimer != null) {
      print('既存のスコア加算タイマーをキャンセルします');
      _eyesClosedScoreTimer?.cancel();
      _eyesClosedScoreTimer = null;
    }
    
    print('スコア加算タイマー作成: 間隔=${EYES_CLOSED_SCORE_INTERVAL}ms');
    
    try {
      _eyesClosedScoreTimer = Timer.periodic(
        Duration(milliseconds: EYES_CLOSED_SCORE_INTERVAL), 
        (timer) {
          print('【スコア加算タイマー発火】: 時刻=${DateTime.now().toIso8601String()}');
          print('現在の状態: ゲーム状態=${_isGameStarted}, ゲームオーバー=${_isGameOver}, 目=${_isEyesOpen ? "開" : "閉"}, スコア=$_score');
          
          if (!_isGameStarted || _isGameOver) {
            print('スコア加算タイマー: ゲーム終了のためタイマー停止');
            timer.cancel();
            return;
          }
          
          // 目を閉じている場合のみスコア加算
          if (!_isEyesOpen) {
            final oldScore = _score;
            setState(() {
              _score += EYES_CLOSED_SCORE_INCREMENT;
            });
            print('スコア加算完了: $oldScore → $_score (+$EYES_CLOSED_SCORE_INCREMENT)');
          } else {
            print('目が開いているためスコア加算なし');
          }
        }
      );
      print('◆◆◆ スコア加算タイマー作成成功 ◆◆◆');
    } catch (e) {
      print('!!! スコア加算タイマー作成エラー: $e !!!');
    }
  }

  String _getEyeStateText(bool isLeft) {
    if (_mediaPipeDebugResult == null) return '検出中...';
    
    try {
      final faceLandmarks = js_util.getProperty(_mediaPipeDebugResult, 'faceLandmarks');
      if (faceLandmarks == null || js_util.getProperty(faceLandmarks, 'length') == 0) {
        return '検出中...';
      }
      
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      final landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;
      
      // 左目と右目のランドマークインデックス
      const int leftEyeUpperIndex = 159;
      const int leftEyeLowerIndex = 145;
      const int rightEyeUpperIndex = 386;
      const int rightEyeLowerIndex = 374;
      
      if (landmarks.length <= math.max(leftEyeUpperIndex, rightEyeUpperIndex)) {
        return '不明';
      }
      
      // 左目か右目かに応じて対応するランドマークを取得
      final upperIndex = isLeft ? leftEyeUpperIndex : rightEyeUpperIndex;
      final lowerIndex = isLeft ? leftEyeLowerIndex : rightEyeLowerIndex;
      
      final eyeUpper = landmarks[upperIndex] as Map;
      final eyeLower = landmarks[lowerIndex] as Map;
      
      final eyeUpperY = eyeUpper['y'] is num ? (eyeUpper['y'] as num).toDouble() : 0.0;
      final eyeLowerY = eyeLower['y'] is num ? (eyeLower['y'] as num).toDouble() : 0.0;
      final eyeDistance = (eyeUpperY - eyeLowerY).abs();
      
      // しきい値
      const eyeClosedThreshold = 0.004;
      final isOpen = eyeDistance > eyeClosedThreshold;
      
      return '${isOpen ? "開" : "閉"} (${eyeDistance.toStringAsFixed(4)})';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  Future<void> _initializeAudio() async {
    _audioPlayer = AudioPlayer();
    await _audioPlayer?.setAsset('assets/sounds/train_sound.mp3');
    await _audioPlayer?.setLoopMode(LoopMode.all);

    // ゲームオーバー・クリアSEの初期化
    _gameOverSoundPlayer = AudioPlayer();
    await _gameOverSoundPlayer?.setAsset('assets/sounds/game_over.mp3'); 
    // ループ再生はしないので LoopMode.off (デフォルト)

    _gameClearSoundPlayer = AudioPlayer();
    await _gameClearSoundPlayer?.setAsset('assets/sounds/game_clear.mp3');
    // ループ再生はしないので LoopMode.off (デフォルト)

    // いびきSEの初期化
    _snorePlayer = AudioPlayer();
    await _snorePlayer?.setAsset('assets/sounds/snore.mp3');
    await _snorePlayer?.setLoopMode(LoopMode.all);
  }

  Future<void> _playTrainSound() async {
    print('SE再生試行: isPlayingSound=$_isPlayingSound, audioPlayer is null: ${_audioPlayer == null}');
    if (!_isPlayingSound && _audioPlayer != null) {
      try {
        print('calling _audioPlayer.play()');
        _audioPlayer?.play(); // await を一時的に削除して、処理がブロックされないか確認
        print('_audioPlayer.play() called (no await)');
        // setStateは非同期処理の結果を待たずにすぐに実行される
        if (mounted) {
          setState(() {
            _isPlayingSound = true;
          });
        }
      } catch (e) {
        print('Audio play error: $e');
      }
    } else {
      print('SE再生スキップ: 既に再生中かオーディオプレーヤーがnull');
    }
  }

  Future<void> _stopTrainSound() async {
    print('SE停止試行: 現在の再生状態=${_isPlayingSound}');
    if (_audioPlayer != null) {
      try {
        // 現在の再生状態に関わらず停止を試みる
        await _audioPlayer?.stop();
        print('SE停止成功');
      } catch (e) {
        print('SE停止エラー: $e');
      } finally {
        setState(() {
          _isPlayingSound = false;
        });
      }
    } else {
      print('SE停止: オーディオプレーヤーが未初期化');
    }
  }

  // ランダムな背景タイプを選択するメソッド
  void _selectRandomBackground() {
    final random = math.Random();
    final backgroundTypes = BackgroundType.values;
    _currentBackgroundType = backgroundTypes[random.nextInt(backgroundTypes.length)];
    
    print('選択された背景タイプ: $_currentBackgroundType');
  }

  // 外部からも背景をリセットできるようにする
  void _resetBackground() {
    // 前の背景タイプを保存
    final oldBackgroundType = _currentBackgroundType;
    
    // 新しい背景タイプを選択（現在と異なるものを選ぶ）
    BackgroundType newType;
    final random = math.Random();
    final backgroundTypes = BackgroundType.values;
    
    do {
      newType = backgroundTypes[random.nextInt(backgroundTypes.length)];
    } while (newType == oldBackgroundType && backgroundTypes.length > 1);
    
    _currentBackgroundType = newType;
    
    // 視覚的なフィードバック
    if (mounted) {
      // フェードアウト・イン効果を使用した状態更新
      setState(() {
        // 状態を更新して再描画
      });
      
      print('背景タイプを変更: $oldBackgroundType → $_currentBackgroundType');
    }
  }
  
  // フリープレイモードの切り替え
  void _toggleFreePlayMode() {
    if (!widget.gameService.isFreePlay) {
      widget.gameService.setFreePlayMode();
      if (mounted) {
        setState(() {
          // UI更新
        });
      }
      
      // フリープレイモード有効時のメッセージ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'フリープレイモードを有効にしました。LINE連携なしでプレイできます。',
            style: GoogleFonts.mochiyPopOne(),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // アクションボタンを作成するヘルパーメソッド
  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required bool isSmallScreen,
    double? width,
  }) {
    return SizedBox(
      width: width,
      height: isSmallScreen ? 44 : 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: isSmallScreen ? 20 : 22),
        label: Text(
          label,
          style: GoogleFonts.mochiyPopOne(
            fontSize: isSmallScreen ? 14 : 16,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16 : 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  void updateEyeState(bool isClosed) {
    setState(() {
      _isEyesOpen = !isClosed;
    });
  }
}