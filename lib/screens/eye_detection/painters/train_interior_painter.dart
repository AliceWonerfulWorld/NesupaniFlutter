import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

class TrainInteriorPainter extends CustomPainter {
  final double offset;
  final bool isEyesOpen;

  TrainInteriorPainter({
    required this.offset,
    required this.isEyesOpen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 0. Clip Path (オプション: 画面端の処理を滑らかにしたい場合)
    // final clipPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // canvas.clipPath(clipPath);

    // 1. 全体の背景 (夜空のグラデーション)
    _drawBackground(canvas, size);
    
    // 2. 床 - 質感向上
    _drawFloor(canvas, size);
    
    // 3. 壁面 - 質感・装飾向上
    _drawWall(canvas, size);
    
    // 4. 座席 (ボックスシート風) - 後ほど強化
    _drawSeats(canvas, size);
    
    // 5. 窓 - 装飾・質感向上
    _drawWindows(canvas, size);

    // 6. 荷物棚 - 後ほど強化
    _drawLuggageRack(canvas, size);

    // 7. 天井と照明 - 後ほど強化
    _drawCeilingAndLights(canvas, size);

    // 8. 細かいディテール (吊り革など) - 後ほど強化
    _drawDetails(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black,
          const Color(0xFF0A1931), // 深い藍色
          const Color(0xFF183A5A), // やや明るい藍色
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);
  }

  void _drawFloor(Canvas canvas, Size size) {
    final floorHeight = size.height * 0.20;
    final floorY = size.height - floorHeight;
    final floorRect = Rect.fromLTWH(0, floorY, size.width, floorHeight);
    
    // ベースの色
    final floorPaint = Paint()..color = const Color(0xFF4A3B31); // 濃い茶色
    canvas.drawRect(floorRect, floorPaint);

    // 木目テクスチャ風の描画
    final woodGrainDarkPaint = Paint()
      ..color = const Color(0xFF3A2E26) // より濃い茶色
      ..strokeWidth = 1.0;
    final woodGrainLightPaint = Paint()
      ..color = const Color(0xFF5A4A3E) // 少し明るい茶色
      ..strokeWidth = 0.5;

    int oscuroGrainCount = 20; // 暗い木目の線の数
    for (int i = 0; i < oscuroGrainCount; i++) {
      final y = floorY + (i * floorHeight / oscuroGrainCount) + math.Random().nextDouble() * 2 - 1; // 少し揺らぎを加える
      final startX = math.Random().nextDouble() * -size.width * 0.2; // 画面外から始まるように
      final endX = size.width + math.Random().nextDouble() * size.width * 0.2;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), woodGrainDarkPaint);
    }
    int claroGrainCount = 30; // 明るい木目の線の数
    for (int i = 0; i < claroGrainCount; i++) {
      final y = floorY + (i * floorHeight / claroGrainCount) + math.Random().nextDouble() * 1.5 - 0.75;
      final startX = math.Random().nextDouble() * -size.width * 0.1;
      final endX = size.width + math.Random().nextDouble() * size.width * 0.1;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), woodGrainLightPaint);
    }

    // 床の縁にわずかな陰影 (オプション)
    final floorEdgeGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.15)],
      stops: const [0.0, 1.0],
    );
    final floorEdgePaint = Paint()..shader = floorEdgeGradient.createShader(Rect.fromLTWH(0, floorY, size.width, floorHeight));
    canvas.drawRect(Rect.fromLTWH(0, floorY, size.width, floorHeight), floorEdgePaint);
  }

  void _drawWall(Canvas canvas, Size size) {
    final floorHeight = size.height * 0.20;
    final windowRect = getWindowRect(size);
    final windowBottomY = windowRect.bottom;
    final ceilingTopY = size.height * 0.15; // 天井の下端

    // 壁の下部 (木目調腰板)
    final woodPanelPaint = Paint()..color = const Color(0xFF6D5845); // やや明るい木目調
    final woodPanelTopY = windowRect.top + windowRect.height * 0.7; //窓の下1/3くらいから腰板
    final woodPanelRect = Rect.fromLTWH(0, woodPanelTopY, size.width, size.height - floorHeight - woodPanelTopY);
    canvas.drawRect(woodPanelRect, woodPanelPaint);
    
    // 腰板の木目
    final woodGrainDarkPaint = Paint()..color = const Color(0xFF5A4A3E)..strokeWidth = 1.5;
    final woodGrainLightPaint = Paint()..color = const Color(0xFF7E6B5A)..strokeWidth = 0.8;
    for (int i = 0; i < 15; i++) { // 縦の木目
        final x = (i * size.width / 15) + math.Random().nextDouble() * 3 - 1.5;
        canvas.drawLine(Offset(x, woodPanelTopY), Offset(x, size.height - floorHeight), woodGrainDarkPaint);
        if (i % 3 == 0) {
            final xLight = (i * size.width / 15) + math.Random().nextDouble() * 2 - 1;
            canvas.drawLine(Offset(xLight, woodPanelTopY), Offset(xLight, size.height - floorHeight), woodGrainLightPaint);
        }
    }
    // 腰板の上端モールディング
    final moldingPaint = Paint()..color = const Color(0xFF4A3B31)..strokeWidth = 4.0;
    canvas.drawLine(Offset(0, woodPanelTopY), Offset(size.width, woodPanelTopY), moldingPaint);

    // 壁の上部 (ネイビーブルーの壁紙風)
    final upperWallPaint = Paint()..color = const Color(0xFF1A2E4A); // ネイビーブルー
    final upperWallRect = Rect.fromLTWH(0, ceilingTopY, size.width, woodPanelTopY - ceilingTopY);
    canvas.drawRect(upperWallRect, upperWallPaint);

    // 壁紙にかすかな模様 (オプション: 細かいドットや織物風テクスチャ)
    final wallpaperPatternPaint = Paint()..color = Colors.white.withOpacity(0.03);
    for (double dx = 0; dx < size.width; dx += 10) {
      for (double dy = ceilingTopY; dy < woodPanelTopY; dy += 10) {
        if ((dx / 10).floor() % 2 == (dy / 10).floor() % 2) { // 市松模様風に間引く
          canvas.drawCircle(Offset(dx + math.Random().nextDouble() * 2, dy + math.Random().nextDouble() * 2), 0.5, wallpaperPatternPaint);
        }
      }
    }
  }

  void _drawSeats(Canvas canvas, Size size) {
    final seatColor = const Color(0xFF8C3B3B); // エンジ色
    final seatCushionPaint = Paint()..color = seatColor;
    final seatBackPaint = Paint()..color = seatColor.withOpacity(0.85); // 少し暗く

    final seatHeight = size.height * 0.18;
    final seatDepth = size.height * 0.12;
    final seatWidth = size.width * 0.35;
    final seatY = size.height * 0.80 - seatHeight; // 床の上に乗るように調整
    final seatSpacing = size.width * 0.05;

    // 画面両端にボックスシートを配置 (2組)
    for (int side = 0; side < 2; side++) {
      final seatX = (side == 0) ? seatSpacing : size.width - seatWidth - seatSpacing;

      // 座面
      final seatCushionRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(seatX, seatY, seatWidth, seatHeight),
        topLeft: const Radius.circular(10),
        topRight: const Radius.circular(10),
      );
      canvas.drawRRect(seatCushionRect, seatCushionPaint);
      // 座面の陰影
      final seatCushionShadowPaint = Paint()
        ..shader = LinearGradient(
            colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.2)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter)
        .createShader(seatCushionRect.outerRect);
      canvas.drawRRect(seatCushionRect, seatCushionShadowPaint);

      // 背もたれ (少し傾斜をつける)
      final seatBackPath = Path();
      seatBackPath.moveTo(seatX, seatY); // 左下
      seatBackPath.lineTo(seatX + seatDepth * 0.2, seatY - seatHeight * 0.8); // 左上 (少し内側)
      seatBackPath.lineTo(seatX + seatWidth - seatDepth * 0.2, seatY - seatHeight * 0.8); // 右上 (少し内側)
      seatBackPath.lineTo(seatX + seatWidth, seatY); // 右下
      seatBackPath.close();
      canvas.drawPath(seatBackPath, seatBackPaint);
      // 背もたれの陰影
       final seatBackShadowPaint = Paint()
        ..shader = LinearGradient(
            colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.15)],
            begin: Alignment.centerLeft, end: Alignment.centerRight)
        .createShader(seatBackPath.getBounds()); // Pathのバウンディングボックスを使用
      canvas.drawPath(seatBackPath, seatBackShadowPaint);

      //肘掛け (オプション)
      final armrestPaint = Paint()..color = const Color(0xFF5A3825); // 濃い木目
      final armrestWidth = seatWidth * 0.1;
      final armrestHeight = seatHeight * 0.4;
      final armrestY = seatY - armrestHeight * 0.5;
      // 手前側の肘掛け
      final armrestLRect = RRect.fromRectAndCorners(Rect.fromLTWH(seatX, armrestY, armrestWidth, armrestHeight), topLeft: Radius.circular(5));
      final armrestRRect = RRect.fromRectAndCorners(Rect.fromLTWH(seatX + seatWidth - armrestWidth, armrestY, armrestWidth, armrestHeight), topRight: Radius.circular(5));
      canvas.drawRRect(armrestLRect, armrestPaint);
      canvas.drawRRect(armrestRRect, armrestPaint);
    }
  }

  void _drawWindows(Canvas canvas, Size size) {
    final windowRect = getWindowRect(size);
    final frameColor = const Color(0xFFC0A080); // やや彩度を落とした真鍮風
    final frameShadowColor = const Color(0xFF8C6E4E);
    final frameHighlightColor = const Color(0xFFEADCC6);

    // 窓枠の影 (立体感を出すため)
    final frameShadowPaint = Paint()..color = frameShadowColor.withOpacity(0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(windowRect.translate(3, 3), const Radius.circular(10)),
      frameShadowPaint,
    );

    // 窓枠本体
    final framePaint = Paint()..color = frameColor;
    canvas.drawRRect(RRect.fromRectAndRadius(windowRect, const Radius.circular(8)), framePaint);
    
    // 窓枠のハイライト (内側)
    final frameHighlightPaint = Paint()
      ..color = frameHighlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromRectAndRadius(windowRect.deflate(2), const Radius.circular(6)), frameHighlightPaint);

    // 窓ガラス (夜なのでほぼ透明だが、枠は必要)
    final glassPaint = Paint()..color = Colors.transparent; // 夜景は背景で描画
    canvas.drawRRect(RRect.fromRectAndRadius(windowRect.deflate(6), const Radius.circular(4)), glassPaint);
    
    // 目を閉じているときの暗いオーバーレイ
    if (!isEyesOpen) {
      final darkOverlayPaint = Paint()..color = Colors.black.withOpacity(0.85);
      canvas.drawRRect(RRect.fromRectAndRadius(windowRect.deflate(6), const Radius.circular(4)), darkOverlayPaint);
    }

    // カーテン (上部に装飾として)
    final curtainColor = const Color(0xFF702828); // 深い赤
    final curtainPaint = Paint()..color = curtainColor;
    final curtainHeight = size.height * 0.06; // 少し高く
    final curtainTop = windowRect.top - curtainHeight + 8; // 窓枠に少し被る

    final curtainPath = Path();
    curtainPath.moveTo(windowRect.left - 15, curtainTop);
    int numFolds = 6; // ドレープの数
    double foldWidth = (windowRect.width + 30) / (numFolds * 2);
    for (int i = 0; i <= numFolds * 2; i++) {
      final x = windowRect.left - 15 + foldWidth * i;
      final yOffset = (i % 2 == 0) ? 0 : curtainHeight * 0.4;
      final controlOffsetY = (i % 2 == 0) ? curtainHeight * 0.2 : -curtainHeight * 0.2;
      if (i == 0) {
        curtainPath.lineTo(x, curtainTop + yOffset);
      } else {
        final prevX = windowRect.left - 15 + foldWidth * (i-1);
        final prevYOffset = ((i-1) % 2 == 0) ? 0 : curtainHeight * 0.4;
        curtainPath.quadraticBezierTo(
            prevX + foldWidth / 2, curtainTop + prevYOffset + controlOffsetY,
            x, curtainTop + yOffset
        );
      }
    }
    curtainPath.lineTo(windowRect.right + 15, curtainTop + curtainHeight * 0.8); // 右端の垂れ下がり
    curtainPath.lineTo(windowRect.right + 15, curtainTop);
    curtainPath.close();
    canvas.drawPath(curtainPath, curtainPaint);
    
    // カーテンの陰影
    final curtainShadowPaint = Paint()
      ..shader = LinearGradient(colors: [Colors.black.withOpacity(0.2), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)
      .createShader(Rect.fromLTWH(windowRect.left-15, curtainTop, windowRect.width+30, curtainHeight));
    canvas.drawPath(curtainPath, curtainShadowPaint);

    // カーテンレール
    final railPaint = Paint()..color = frameColor.withOpacity(0.8)..strokeWidth = 4.0;
    canvas.drawLine(Offset(windowRect.left - 20, curtainTop + 3), Offset(windowRect.right + 20, curtainTop + 3), railPaint);
    // カーテンレールの留め具 (簡易)
    for(int i=0; i<3; i++){
      final x = windowRect.left + (windowRect.width / 2 * i) - (i==0?5:0) + (i==2?5:0);
      canvas.drawCircle(Offset(x, curtainTop + 3), 4, Paint()..color = frameShadowColor);
    }
  }

  static Rect getWindowRect(Size size) {
    // 窓を少し大きく、中央に配置
    final windowWidth = size.width * 0.6;
    final windowHeight = size.height * 0.35;
    final windowLeft = (size.width - windowWidth) / 2;
    final windowTop = size.height * 0.20;
    return Rect.fromLTWH(windowLeft, windowTop, windowWidth, windowHeight);
  }

  void _drawLuggageRack(Canvas canvas, Size size) {
    final rackColor = const Color(0xFFB08D57); // 真鍮色
    final rackShadowColor = const Color(0xFF7A5F3A);
    final rackPaint = Paint()
      ..color = rackColor
      ..strokeWidth = 3.0; // 少し太く
    final rackY = size.height * 0.12;
    final rackDepth = 25.0;

    // 奥のバー (+影)
    canvas.drawLine(Offset(size.width * 0.08, rackY+2), Offset(size.width * 0.92, rackY+2), Paint()..color = rackShadowColor.withOpacity(0.7)..strokeWidth = 3.0);
    canvas.drawLine(Offset(size.width * 0.08, rackY), Offset(size.width * 0.92, rackY), rackPaint);
    // 手前のバー (+影)
    canvas.drawLine(Offset(size.width * 0.08 + rackDepth * 0.5, rackY + rackDepth+2), 
                    Offset(size.width * 0.92 - rackDepth * 0.5, rackY + rackDepth+2), Paint()..color = rackShadowColor.withOpacity(0.7)..strokeWidth = 3.0);
    canvas.drawLine(Offset(size.width * 0.08 + rackDepth * 0.5, rackY + rackDepth), 
                    Offset(size.width * 0.92 - rackDepth * 0.5, rackY + rackDepth), rackPaint);

    // 縦の支え (斜めに描画して奥行きを出す)
    for (int i = 0; i < 7; i++) {
      final x = size.width * 0.08 + (size.width * 0.84 / 6 * i);
      // 影
      canvas.drawLine(Offset(x+2, rackY+2), Offset(x + rackDepth * 0.5 + 2, rackY + rackDepth + 2), Paint()..color = rackShadowColor.withOpacity(0.6)..strokeWidth = rackPaint.strokeWidth);
      // 本体
      canvas.drawLine(Offset(x, rackY), Offset(x + rackDepth * 0.5, rackY + rackDepth), rackPaint);
    }

    // 網目 (よりリアルに, 奥行き方向に走る線を追加)
    final netPaint = Paint()..color = rackColor.withAlpha(150)..strokeWidth = 1.5;
    // 手前バーに沿う横線
    for(double d = 0; d < rackDepth; d += rackDepth/3){
        canvas.drawLine(Offset(size.width * 0.08 + rackDepth*0.5 -d*0.5, rackY + d), 
                        Offset(size.width * 0.92 - rackDepth*0.5 +d*0.5, rackY + d), netPaint);
    }
    // 斜めの線
    for (int i = 0; i <= 12; i++) {
      final startX = size.width * 0.08 + (size.width * 0.84 / 12 * i);
      canvas.drawLine(Offset(startX, rackY), Offset(startX + rackDepth * 0.5, rackY + rackDepth), netPaint);
    }
  }

 void _drawCeilingAndLights(Canvas canvas, Size size) {
    // 天井
    final ceilingPaint = Paint()..color = const Color(0xFFE0D6C0); // クリーム色
    final ceilingHeight = size.height * 0.15;
    final ceilingRect = Rect.fromLTWH(0, 0, size.width, ceilingHeight);
    canvas.drawRect(ceilingRect, ceilingPaint);

    // 天井の縁にわずかな陰影
    final ceilingEdgeGradient = LinearGradient(
      begin: Alignment.bottomCenter, end: Alignment.topCenter,
      colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.1)], stops: [0.0, 1.0]
    );
    canvas.drawRect(Rect.fromLTWH(0, ceilingHeight - 10, size.width, 10), Paint()..shader = ceilingEdgeGradient.createShader(Rect.fromLTWH(0, ceilingHeight-10, size.width, 10)));

    // 中央の照明器具 (クラシックなデザインに)
    final lightFixtureBasePaint = Paint()..color = const Color(0xFF8B4513); // 濃い木目調（台座）
    final lightFixtureGoldPaint = Paint()..color = const Color(0xFFD4AF37); // くすんだゴールド（金具）
    final fixtureWidth = size.width * 0.45;
    final fixtureHeight = ceilingHeight * 0.4;
    final fixtureX = (size.width - fixtureWidth) / 2;
    final fixtureY = ceilingHeight * 0.15;
    
    // 台座
    final baseRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(fixtureX, fixtureY, fixtureWidth, fixtureHeight),
        topLeft: Radius.circular(8), topRight: Radius.circular(8)
    );
    canvas.drawRRect(baseRect, lightFixtureBasePaint);

    // 照明カバー (ミルクガラス風)
    final glassCoverPaint = Paint()..color = Colors.white.withOpacity(0.85);
    final glassCoverRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(fixtureX + fixtureWidth * 0.1, fixtureY + fixtureHeight * 0.2, 
                      fixtureWidth * 0.8, fixtureHeight * 0.6),
        Radius.circular(4)
    );
    canvas.drawRRect(glassCoverRect, glassCoverPaint);

    // 金具の装飾
    canvas.drawRect(Rect.fromLTWH(fixtureX + fixtureWidth * 0.05, fixtureY + fixtureHeight * 0.15, fixtureWidth*0.9, fixtureHeight * 0.1), lightFixtureGoldPaint);
    canvas.drawRect(Rect.fromLTWH(fixtureX + fixtureWidth * 0.05, fixtureY + fixtureHeight * 0.75, fixtureWidth*0.9, fixtureHeight * 0.1), lightFixtureGoldPaint);

    // 発光部分
    final lightPaint = Paint()
      ..color = Colors.yellow[100]!.withOpacity(isEyesOpen ? 0.7 : 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0); // 少し広めにぼかす
    canvas.drawRRect(glassCoverRect.deflate(2), lightPaint);

    // 壁際の間接照明 (より柔らかく)
    final indirectLightPaint = Paint()
      ..shader = ui.Gradient.linear(
          Offset(0, ceilingHeight - 10), Offset(0, ceilingHeight + 20),
          [Colors.orange[200]!.withOpacity(isEyesOpen ? 0.20 : 0.05), Colors.transparent],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0);
    canvas.drawRect(Rect.fromLTWH(-10, ceilingHeight - 15, size.width + 20, 30), indirectLightPaint);
  }

  void _drawDetails(Canvas canvas, Size size) {
    // 吊り革 (よりリアルな形状と陰影)
    final strapColor = const Color(0xFF7A5230); // より深みのある革色
    final ringColor = const Color(0xFFA87E4E); // 明るめのアンティークゴールド
    final strapPaint = Paint()..color = strapColor;
    final ringPaint = Paint()..color = ringColor;
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.2);

    final strapTopY = size.height * 0.15;
    final strapBaseWidth = size.width * 0.015;
    final strapLength = size.height * 0.16;
    final ringOuterRadius = size.width * 0.035;
    final ringInnerRadius = size.width * 0.025;
    final ringThickness = ringOuterRadius - ringInnerRadius;

    for (int i = 0; i < 2; i++) { 
      final x = (i == 0) ? size.width * 0.28 : size.width * 0.72;
      
      // ストラップの影
      final strapShadowPath = Path()
        ..moveTo(x - strapBaseWidth / 2 + 2, strapTopY + 2)
        ..lineTo(x + strapBaseWidth / 2 + 2, strapTopY + 2)
        ..lineTo(x + strapBaseWidth * 0.8 + 2, strapTopY + strapLength + 2)
        ..lineTo(x - strapBaseWidth * 0.8 + 2, strapTopY + strapLength + 2)
        ..close();
      canvas.drawPath(strapShadowPath, shadowPaint);

      // ストラップ本体 (台形)
      final strapPath = Path()
        ..moveTo(x - strapBaseWidth / 2, strapTopY) // 上辺左
        ..lineTo(x + strapBaseWidth / 2, strapTopY) // 上辺右
        ..lineTo(x + strapBaseWidth * 0.8, strapTopY + strapLength) // 下辺右
        ..lineTo(x - strapBaseWidth * 0.8, strapTopY + strapLength) // 下辺左
        ..close();
      canvas.drawPath(strapPath, strapPaint);

      // 輪の影
      canvas.drawCircle(Offset(x, strapTopY + strapLength + ringOuterRadius + 2), ringOuterRadius, shadowPaint);
      // 輪本体
      final ringPath = Path()
        ..addOval(Rect.fromCircle(center: Offset(x, strapTopY + strapLength + ringOuterRadius), radius: ringOuterRadius))
        ..addOval(Rect.fromCircle(center: Offset(x, strapTopY + strapLength + ringOuterRadius), radius: ringInnerRadius));
      ringPath.fillType = PathFillType.evenOdd;
      canvas.drawPath(ringPath, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TrainInteriorPainter oldDelegate) {
    return oldDelegate.offset != offset || oldDelegate.isEyesOpen != isEyesOpen;
  }
}