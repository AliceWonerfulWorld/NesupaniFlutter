import 'package:flutter/material.dart';

class TrainInteriorPainter extends CustomPainter {
  final double offset;
  final bool isEyesOpen;

  TrainInteriorPainter({
    required this.offset,
    required this.isEyesOpen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 電車の内装の描画
    _drawInterior(canvas, size);
    
    // 窓の描画
    _drawWindows(canvas, size);
    
    // 手すりの描画
    _drawHandrails(canvas, size);
    
    // 座席の描画
    _drawSeats(canvas, size);
    
    // 床の描画
    _drawFloor(canvas, size);
    
    // 天井の描画
    _drawCeiling(canvas, size);

    // 広告スペースの描画
    _drawAds(canvas, size);
  }

  void _drawInterior(Canvas canvas, Size size) {
    // 壁のグラデーション
    final wallRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final wallPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.grey[100]!, Colors.grey[300]!],
      ).createShader(wallRect);
    canvas.drawRect(wallRect, wallPaint);
  }

  void _drawWindows(Canvas canvas, Size size) {
    // 窓枠
    final framePaint = Paint()..color = Colors.grey[400]!;
    final windowRect = getWindowRect(size);
    final rrect = RRect.fromRectAndRadius(windowRect, const Radius.circular(18));
    canvas.drawRRect(rrect, framePaint);

    // 窓ガラス
    final glassPaint = Paint()..color = Colors.white.withOpacity(0.85);
    final windowGlassRRect = RRect.fromRectAndRadius(
      windowRect.deflate(4),
      const Radius.circular(14),
    );
    canvas.drawRRect(windowGlassRRect, glassPaint);

    // 窓のハイライト
    final highlightPaint = Paint()..color = Colors.white.withOpacity(0.25);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(windowRect.left + 10, windowRect.top + 8, windowRect.width * 0.3, windowRect.height * 0.2),
        const Radius.circular(10),
      ),
      highlightPaint,
    );
    
    // 目を閉じているときの暗いオーバーレイ
    if (!isEyesOpen) {
      final darkOverlayPaint = Paint()..color = Colors.black.withOpacity(0.7);
      canvas.drawRRect(windowGlassRRect, darkOverlayPaint);
    }
  }

  static Rect getWindowRect(Size size) {
    final windowWidth = size.width * 0.8;
    final windowHeight = size.height * 0.18;
    final windowLeft = size.width * 0.1;
    final windowTop = size.height * 0.20;
    return Rect.fromLTWH(windowLeft, windowTop, windowWidth, windowHeight);
  }

  void _drawHandrails(Canvas canvas, Size size) {
    // つり革（2列、奥行き感）
    final handrailPaint = Paint()..color = Colors.grey[400]!;
    for (int row = 0; row < 2; row++) {
      for (int i = 0; i < 6; i++) {
        final x = size.width * (0.15 + i * 0.13) + row * 10;
        final y = size.height * 0.13 + row * 18;
        // 紐
        handrailPaint.strokeWidth = 4;
        canvas.drawLine(Offset(x, y), Offset(x, y + 30), handrailPaint);
        // 輪
        handrailPaint.style = PaintingStyle.stroke;
        handrailPaint.strokeWidth = 3;
        canvas.drawCircle(Offset(x, y + 40), 10, handrailPaint);
        handrailPaint.style = PaintingStyle.fill;
      }
    }
  }

  void _drawSeats(Canvas canvas, Size size) {
    // 座席
    for (int i = 0; i < 5; i++) {
      final seatPaint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.green[400]!, Colors.green[700]!],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width * 0.16, size.height * 0.12));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.05 + i * size.width * 0.18, size.height * 0.6, size.width * 0.16, size.height * 0.12),
          const Radius.circular(18),
        ),
        seatPaint,
      );
    }
    // 座席端の仕切り
    final borderPaint = Paint()..color = Colors.grey[700]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.04, size.height * 0.6, 6, size.height * 0.12), borderPaint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.92, size.height * 0.6, 6, size.height * 0.12), borderPaint);
    // 背もたれ
    final backPaint = Paint()..color = Colors.green[900]!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.04, size.height * 0.52, size.width * 0.92, size.height * 0.09),
        const Radius.circular(18),
      ),
      backPaint,
    );
  }

  void _drawFloor(Canvas canvas, Size size) {
    final floorPaint = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.fill;

    // 床の描画
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.8, size.width, size.height * 0.2),
      floorPaint,
    );

    // 床の模様
    final patternPaint = Paint()
      ..color = Colors.grey[500]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 床の模様を描画
    for (var i = 0; i < 5; i++) {
      final y = size.height * 0.8 + (i * size.height * 0.04);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        patternPaint,
      );
    }
  }

  void _drawCeiling(Canvas canvas, Size size) {
    // 天井
    final ceilingPaint = Paint()
      ..color = Colors.grey[50]!
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.13), ceilingPaint);

    // 照明
    final lightPaint = Paint()
      ..color = Colors.white.withOpacity(0.7);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.07),
        width: size.width * 0.5,
        height: 24,
      ),
      lightPaint,
    );

    // エアコン吹き出し口
    final acPaint = Paint()
      ..color = Colors.grey[300]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.35, size.height * 0.03, size.width * 0.3, 10), acPaint);
  }

  void _drawAds(Canvas canvas, Size size) {
    // 広告スペース
    final adPaint1 = Paint()..color = Colors.pink[200]!;
    final adPaint2 = Paint()..color = Colors.blue[200]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.12, size.height * 0.13, size.width * 0.2, size.height * 0.04), adPaint1);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.68, size.height * 0.13, size.width * 0.2, size.height * 0.04), adPaint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}