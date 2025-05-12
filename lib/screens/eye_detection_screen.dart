import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage, InputImageData, InputImagePlaneMetadata;

class EyeDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const EyeDetectionScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<EyeDetectionScreen> createState() => _EyeDetectionScreenState();
}

class _EyeDetectionScreenState extends State<EyeDetectionScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  late FaceDetector _faceDetector;
  bool _isGameStarted = false;
  int _score = 0;
  Timer? _gameTimer;
  Timer? _stationTimer;
  String _currentStation = '';
  bool _isDebugMode = false;
  String _debugStatus = '';
  bool _isProcessing = false;
  bool _isEyesOpen = true;
  late AnimationController _animationController;
  late Animation<double> _sceneryAnimation;
  final List<String> _stations = [
    '東京', '新宿', '渋谷', '池袋', '上野',
    '品川', '秋葉原', '原宿', '代々木', '新大久保'
  ];
  int _currentStationIndex = 0;
  double _sceneryOffset = 0.0;
  Face? _debugFace;
  bool _wasEyesOpen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.15,
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
        setState(() {
          _sceneryOffset = _sceneryAnimation.value;
        });
      });
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
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }
  }

  Future<void> _initializeCamera() async {
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
      imageFormatGroup: ImageFormatGroup.yuv420,
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
    if (_isProcessing) return;

    _isProcessing = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final rotation = _controller!.description.sensorOrientation;
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.values[rotation ~/ 90],
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        setState(() {
          _debugStatus = '顔が検出されていません';
          _debugFace = null;
        });
        return;
      }

      final face = faces.first;
      if (face.leftEyeOpenProbability == null || face.rightEyeOpenProbability == null) {
        setState(() {
          _debugStatus = '目の状態を検出できません';
        });
        return;
      }

      final isFrontCamera = _controller!.description.lensDirection == CameraLensDirection.front;
      final leftProb = isFrontCamera
          ? face.rightEyeOpenProbability ?? 1.0
          : face.leftEyeOpenProbability ?? 1.0;
      final rightProb = isFrontCamera
          ? face.leftEyeOpenProbability ?? 1.0
          : face.rightEyeOpenProbability ?? 1.0;
      // 厳しめのしきい値
      final leftEyeClosed = leftProb < 0.2;
      final rightEyeClosed = rightProb < 0.2;
      final leftEyeOpen = !leftEyeClosed;
      final rightEyeOpen = !rightEyeClosed;

      setState(() {
        _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
        _isEyesOpen = leftEyeOpen || rightEyeOpen;
        _debugFace = face;
      });

      // 「開→完全に両目が閉じた瞬間」だけ加算
      if (_isGameStarted && _wasEyesOpen && leftEyeClosed && rightEyeClosed) {
        _addScore();
      }
      _wasEyesOpen = leftEyeOpen || rightEyeOpen;
    } catch (e) {
      print('画像処理エラー: $e');
      setState(() {
        _debugStatus = 'エラー: $e';
      });
    } finally {
      _isProcessing = false;
    }
  }

  void _startGame() {
    setState(() {
      _isGameStarted = true;
      _score = 0;
      _currentStation = _stations[0];
      _currentStationIndex = 0;
    });

    _gameTimer?.cancel();
    _gameTimer = Timer(const Duration(seconds: 30), () {
      setState(() {
        _isGameStarted = false;
      });
      _showGameOver();
    });

    _startStationTimer();
  }

  void _startStationTimer() {
    _stationTimer?.cancel();
    _stationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isGameStarted) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentStationIndex = (_currentStationIndex + 1) % _stations.length;
        _currentStation = _stations[_currentStationIndex];
      });
    });
  }

  void _addScore() {
    setState(() {
      _score += 10;
    });
  }

  void _showGameOver() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ゲームオーバー'),
        content: Text('スコア: $_score'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleDebugMode() async {
    setState(() {
      _isDebugMode = !_isDebugMode;
      if (!_isDebugMode) {
        _debugStatus = '';
        _debugFace = null;
      }
    });
    if (_isDebugMode) {
      await _initializeCamera();
    } else {
      await _stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameTimer?.cancel();
    _stationTimer?.cancel();
    _stopCamera();
    _faceDetector.close();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // イラスト風電車内
          Positioned.fill(child: CustomPaint(painter: TrainInteriorPainter())),
          // 窓の外の景色アニメーション
          if (_isGameStarted && _isEyesOpen)
            Positioned(
              left: MediaQuery.of(context).size.width * 0.08,
              top: MediaQuery.of(context).size.height * 0.18,
              width: MediaQuery.of(context).size.width * 0.84,
              height: MediaQuery.of(context).size.height * 0.18,
              child: AnimatedSceneryWidget(offset: _sceneryOffset),
            ),
          // スコア・駅名（座席の上に表示）
          if (_isGameStarted)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).size.height * 0.32,
              child: Column(
                children: [
                  Text(
                    'スコア: $_score',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black45, offset: Offset(1,1))],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '次の駅: $_currentStation',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ゲーム開始・デバッグボタン
          if (!_isGameStarted)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '寝過ごしゲーム',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _startGame,
                    child: const Text('ゲーム開始'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _toggleDebugMode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDebugMode ? Colors.red : null,
                    ),
                    child: Text(_isDebugMode ? 'デバッグモード終了' : 'デバッグモード開始'),
                  ),
                ],
              ),
            ),
          // デバッグモード時のカメラプレビュー
          if (_isDebugMode && _controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: Builder(
                builder: (context) {
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
                                  ),
                                  child: const Text('デバッグモード終了'),
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
          // ゲーム中も顔認識・目の状態を表示
          if (_isGameStarted)
            Positioned(
              top: 40,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _debugStatus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AnimatedSceneryWidget extends StatelessWidget {
  final double offset;
  const AnimatedSceneryWidget({super.key, required this.offset});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 空
          Positioned.fill(
            child: Container(color: Colors.lightBlueAccent),
          ),
          // 流れる木々
          Positioned(
            left: -200 + offset * 400,
            bottom: 0,
            child: Row(
              children: List.generate(5, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Icon(Icons.park, color: Colors.green[800], size: 60),
              )),
            ),
          ),
          // 流れる家
          Positioned(
            left: 100 - offset * 400,
            bottom: 10,
            child: Row(
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: Icon(Icons.home, color: Colors.brown[400], size: 50),
              )),
            ),
          ),
        ],
      ),
    );
  }
}

class TrainInteriorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // 床
    paint.color = const Color(0xFFE0C9A6);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3), paint);
    // 座席
    paint.color = Colors.green[400]!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.6, size.width, size.height * 0.12),
        const Radius.circular(18),
      ),
      paint,
    );
    // 背もたれ
    paint.color = Colors.green[700]!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.52, size.width, size.height * 0.09),
        const Radius.circular(18),
      ),
      paint,
    );
    // 窓
    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.18, size.width * 0.84, size.height * 0.18),
        const Radius.circular(16),
      ),
      paint,
    );
    // つり革
    paint.color = Colors.grey[400]!;
    for (int i = 0; i < 6; i++) {
      final x = size.width * (0.15 + i * 0.13);
      final y = size.height * 0.13;
      // 紐
      paint.strokeWidth = 4;
      canvas.drawLine(Offset(x, y), Offset(x, y + 30), paint);
      // 輪
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 3;
      canvas.drawCircle(Offset(x, y + 40), 10, paint);
      paint.style = PaintingStyle.fill;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class FaceLandmarkPainter extends CustomPainter {
  final Face face;
  final Size previewSize;
  final bool isFrontCamera;
  final double displayW;
  final double displayH;
  FaceLandmarkPainter(this.face, this.previewSize, this.isFrontCamera, this.displayW, this.displayH);

  @override
  void paint(Canvas canvas, Size size) {
    // カメラプレビューの表示サイズに合わせてスケーリング
    final scaleX = displayW / previewSize.width;
    final scaleY = displayH / previewSize.height;
    final paintPoint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final paintLine = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;

    Offset transform(Offset p) {
      double x = p.dx.toDouble() * scaleX;
      double y = p.dy.toDouble() * scaleY;
      if (isFrontCamera) {
        x = displayW - x;
      }
      return Offset(x, y);
    }

    for (final landmarkType in FaceLandmarkType.values) {
      final landmark = face.landmarks[landmarkType];
      if (landmark != null) {
        final offset = transform(Offset(landmark.position.x.toDouble(), landmark.position.y.toDouble()));
        canvas.drawCircle(offset, 5, paintPoint);
      }
    }
    void drawLine(FaceLandmarkType a, FaceLandmarkType b) {
      final la = face.landmarks[a];
      final lb = face.landmarks[b];
      if (la != null && lb != null) {
        final offsetA = transform(Offset(la.position.x.toDouble(), la.position.y.toDouble()));
        final offsetB = transform(Offset(lb.position.x.toDouble(), lb.position.y.toDouble()));
        canvas.drawLine(offsetA, offsetB, paintLine);
      }
    }
    drawLine(FaceLandmarkType.leftEye, FaceLandmarkType.rightEye);
    drawLine(FaceLandmarkType.leftEye, FaceLandmarkType.noseBase);
    drawLine(FaceLandmarkType.rightEye, FaceLandmarkType.noseBase);
    drawLine(FaceLandmarkType.noseBase, FaceLandmarkType.leftMouth);
    drawLine(FaceLandmarkType.noseBase, FaceLandmarkType.rightMouth);
    drawLine(FaceLandmarkType.leftMouth, FaceLandmarkType.rightMouth);
  }

  @override
  bool shouldRepaint(covariant FaceLandmarkPainter oldDelegate) => true;
} 