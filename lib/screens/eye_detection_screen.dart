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

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        setState(() {
          _debugStatus = '顔が検出されていません';
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

      final leftEyeOpen = face.leftEyeOpenProbability! > 0.5;
      final rightEyeOpen = face.rightEyeOpenProbability! > 0.5;

      setState(() {
        _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
      });

      if (_isGameStarted && !leftEyeOpen && !rightEyeOpen) {
        _addScore();
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

  void _toggleDebugMode() {
    setState(() {
      _isDebugMode = !_isDebugMode;
      if (!_isDebugMode) {
        _debugStatus = '';
      }
    });
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
          // デバッグモード時のカメラプレビュー
          if (_isDebugMode && _controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: 1 / _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
          // 電車内の背景
          if (_isGameStarted)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue.shade900,
                    Colors.blue.shade700,
                  ],
                ),
              ),
            ),
          // 外の景色（アニメーション）
          if (_isGameStarted && _isEyesOpen)
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(-_sceneryOffset * 1000, 0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.green.shade800,
                        Colors.green.shade600,
                        Colors.green.shade800,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          // 電車の窓枠
          if (_isGameStarted)
            Positioned.fill(
              child: CustomPaint(
                painter: TrainWindowPainter(),
              ),
            ),
          // ゲームUI
          Container(
            color: _isDebugMode ? Colors.transparent : Colors.blue[100],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isGameStarted) ...[
                    Text(
                      'スコア: $_score',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_currentStation.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
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
                  ] else ...[
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
                ],
              ),
            ),
          ),
          // デバッグモード時の情報表示
          if (_isDebugMode)
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

class TrainWindowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    // 窓枠を描画
    final windowWidth = size.width * 0.8;
    final windowHeight = size.height * 0.6;
    final windowLeft = (size.width - windowWidth) / 2;
    final windowTop = (size.height - windowHeight) / 2;

    // 外枠
    canvas.drawRect(
      Rect.fromLTWH(windowLeft, windowTop, windowWidth, windowHeight),
      paint,
    );

    // 縦の仕切り
    final dividerWidth = 10.0;
    final dividerX = size.width / 2 - dividerWidth / 2;
    canvas.drawRect(
      Rect.fromLTWH(dividerX, windowTop, dividerWidth, windowHeight),
      paint,
    );

    // 横の仕切り
    final dividerHeight = 10.0;
    final dividerY = size.height / 2 - dividerHeight / 2;
    canvas.drawRect(
      Rect.fromLTWH(windowLeft, dividerY, windowWidth, dividerHeight),
      paint,
    );
  }

  @override
  bool shouldRepaint(TrainWindowPainter oldDelegate) => false;
} 